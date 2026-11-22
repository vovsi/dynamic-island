import CryptoKit
import Foundation

/// Read-only client for the EcoFlow IoT Open Platform (the developer portal hands out an access key
/// and a secret key; the station itself stays on the EcoFlow cloud).
///
/// Every call is a signed GET: the query parameters, sorted by key, followed by `accessKey`, `nonce`
/// and `timestamp`, signed with HMAC-SHA256 and sent as the `sign` header. The platform's own test
/// vector (`…&accessKey=Fp4SvIprYSDPXtYJidEtUAd1o&nonce=345164&timestamp=1671171709428` signed with
/// `WIbFEKre0s6sLnh4ei7SPUeYnptHG6V` → `07c13b65e037…1473e`) reproduces with this code.
struct EcoFlowClient {
    /// Hosts the platform serves; an account registered in one region is rejected by the other.
    enum Region: String, CaseIterable, Identifiable {
        case global
        case europe

        var id: String { rawValue }

        var host: String {
            switch self {
            case .global: return "api.ecoflow.com"
            case .europe: return "api-e.ecoflow.com"
            }
        }

        var title: String {
            switch self {
            case .global: return tr("Global", "Глобальный")
            case .europe: return tr("Europe", "Европа")
            }
        }
    }

    /// One power station bound to the account.
    struct Device: Identifiable, Equatable {
        var id: String { serial }
        let serial: String
        let name: String
        let online: Bool
    }

    /// Current state of a station, as the app shows it.
    struct Reading: Equatable {
        let percent: Int
        let isCharging: Bool
        /// Time to full while charging, time left otherwise; `nil` when the station reports no estimate.
        let remainingMinutes: Int?
        let wattsIn: Int
        let wattsOut: Int
    }

    enum Failure: LocalizedError {
        case http(Int)
        case api(String)
        case unreachable
        case noData

        var errorDescription: String? {
            switch self {
            case .http(let code):
                return tr("EcoFlow replied with HTTP \(code).", "EcoFlow ответил HTTP \(code).")
            case .api(let message):
                return message
            case .unreachable:
                return tr("Could not reach the EcoFlow API.", "Не удалось связаться с API EcoFlow.")
            case .noData:
                return tr("The station reported no battery level.", "Станция не сообщила уровень заряда.")
            }
        }
    }

    let region: Region
    let accessKey: String
    let secretKey: String

    // MARK: - Calls

    /// Every station bound to the account, for the picker in Settings.
    func devices() async throws -> [Device] {
        let payload = try await get("/device/list")
        guard let list = payload["data"] as? [[String: Any]] else { throw Failure.noData }
        return list.compactMap { entry in
            guard let serial = entry["sn"] as? String, !serial.isEmpty else { return nil }
            let name = [entry["deviceName"] as? String, entry["productName"] as? String]
                .compactMap { $0 }
                .first { !$0.isEmpty }
            return Device(
                serial: serial,
                name: name ?? serial,
                online: (entry["online"] as? NSNumber)?.intValue == 1
            )
        }
    }

    /// All quotas of one station, reduced to the few values the island shows.
    func reading(serial: String) async throws -> Reading {
        let payload = try await get("/device/quota/all", ["sn": serial])
        guard let data = payload["data"] as? [String: Any] else { throw Failure.noData }

        // The LCD value is the one the station itself shows; the BMS values are the fallback.
        guard let level = ["bms_emsStatus.lcdShowSoc", "bms_bmsStatus.soc", "pd.soc", "bms_slave.soc"]
            .compactMap({ Self.number(data, $0) })
            .first
        else { throw Failure.noData }

        let wattsIn = Int(Self.number(data, "pd.wattsInSum") ?? 0)
        let wattsOut = Int(Self.number(data, "pd.wattsOutSum") ?? 0)
        // Power coming in is the plain fact; `chgState` is only consulted when watts are missing.
        let charging = wattsIn > 0 || (wattsIn == 0 && wattsOut == 0 && Self.number(data, "bms_emsStatus.chgState") == 1)

        let remainKey = charging ? "bms_emsStatus.chgRemainTime" : "bms_emsStatus.dsgRemainTime"
        let remain = Self.number(data, remainKey) ?? Self.number(data, "pd.remainTime")

        return Reading(
            percent: min(max(Int(level.rounded()), 0), 100),
            isCharging: charging,
            // 5999 is the station's "no estimate" placeholder.
            remainingMinutes: remain.map(Int.init).flatMap { (1..<5999).contains($0) ? $0 : nil },
            wattsIn: wattsIn,
            wattsOut: wattsOut
        )
    }

    // MARK: - Transport

    private func get(_ path: String, _ params: [String: String] = [:]) async throws -> [String: Any] {
        let signed = sign(params)
        var text = "https://\(region.host)/iot-open/sign\(path)"
        if !signed.query.isEmpty { text += "?\(signed.query)" }
        guard let url = URL(string: text) else { throw Failure.unreachable }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // No Content-Type on purpose: with "application/json" the platform looks for the signed
        // parameters in the request body and ignores the query string, so `sn` drops out of what it
        // signs and every call with a parameter comes back as "signature is wrong".
        for (field, value) in signed.headers { request.setValue(value, forHTTPHeaderField: field) }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw Failure.http(http.statusCode) }
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.noData }

        let message = (payload["message"] as? String) ?? ""
        guard message.lowercased() == "success" else {
            let code = (payload["code"] as? String) ?? String(describing: payload["code"] ?? "")
            // 8513 is returned both for a wrong key and for one issued in the other region.
            if code == "8513" {
                throw Failure.api(tr(
                    "Key rejected (8513) — check the keys and the region.",
                    "Ключ отклонён (8513) — проверьте ключи и регион."
                ))
            }
            throw Failure.api(message.isEmpty ? tr("EcoFlow error \(code).", "Ошибка EcoFlow \(code).") : message)
        }
        return payload
    }

    /// Signature string: the sorted query parameters, then the three credentials, HMAC-SHA256 as lowercase hex.
    private func sign(_ params: [String: String]) -> (query: String, headers: [String: String]) {
        let nonce = String(Int.random(in: 100_000...999_999))
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let query = params.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        var target = "accessKey=\(accessKey)&nonce=\(nonce)&timestamp=\(timestamp)"
        if !query.isEmpty { target = query + "&" + target }

        let mac = HMAC<SHA256>.authenticationCode(for: Data(target.utf8), using: SymmetricKey(data: Data(secretKey.utf8)))
        let signature = mac.map { String(format: "%02x", $0) }.joined()

        return (query, [
            "accessKey": accessKey,
            "nonce": nonce,
            "timestamp": timestamp,
            "sign": signature,
        ])
    }

    // MARK: - Parsing

    /// `/quota/all` returns flat dotted keys ("pd.soc"); older firmware nests them instead.
    private static func number(_ data: [String: Any], _ path: String) -> Double? {
        if let value = data[path], let number = double(value) { return number }

        var current: Any? = data
        for part in path.split(separator: ".") {
            guard let dictionary = current as? [String: Any] else { return nil }
            current = dictionary[String(part)]
        }
        return double(current)
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, !(value is Bool) { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}

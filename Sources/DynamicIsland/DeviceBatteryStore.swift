import AppKit
import Foundation
import IOKit

/// Battery levels of the Bluetooth accessories paired with this Mac, refreshed every minute, or only when the island expands in power saving mode.
///
/// Three sources, merged by device name: the IORegistry (Magic Mouse / Keyboard / Trackpad report
/// `BatteryPercent` there), `system_profiler SPBluetoothDataType` (AirPods report left/right/case there)
/// and, when it is set up, the EcoFlow cloud for a power station. Only the last one needs credentials.
@MainActor
final class DeviceBatteryStore: ObservableObject {
    static let shared = DeviceBatteryStore()
    static let refreshInterval: TimeInterval = 60
    /// Icons the mini dashboard shows at most.
    static let maxShown = 4

    @Published private(set) var devices: [DeviceBattery] = []
    /// What the iPhone file looks like right now, for the Settings window.
    @Published private(set) var phoneStatus: PhoneStatus = .off
    /// What the last EcoFlow poll ended with, for the Settings window.
    @Published private(set) var ecoFlowStatus: EcoFlowStatus = .off

    /// State of the file a Shortcuts automation on the iPhone writes into iCloud Drive.
    enum PhoneStatus: Equatable {
        case off
        case missing
        case unreadable
        /// Last level is older than `phoneStaleInterval`; the phone is left out of the island.
        case stale(Date)
        case ready(Date)
    }

    /// A level this old is treated as unknown rather than shown.
    nonisolated static let phoneStaleInterval: TimeInterval = 6 * 60 * 60

    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    /// Last seen level per device; a level that went up means the device is on a charger.
    private var lastPercent: [String: Int] = [:]

    func start() {
        guard defaultsObserver == nil else { return }

        // Picking the iPhone file or flipping power saving in Settings should take effect at once.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { DeviceBatteryStore.shared.applyMode() }
        }
        applyMode()
    }

    /// Power saving: no background polling, levels are read only when the island expands.
    private func applyMode() {
        if AppSettings.powerSaving {
            timer?.invalidate()
            timer = nil
            if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
            wakeObserver = nil
            return
        }
        if timer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { _ in
                MainActor.assumeIsolated { DeviceBatteryStore.shared.refresh() }
            }
            timer.tolerance = 10
            self.timer = timer
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { DeviceBatteryStore.shared.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        guard task == nil else { return }
        task = Task { [weak self] in
            let (collected, phoneStatus, ecoFlowStatus) = await Self.collect()
            guard let self else { return }
            self.apply(collected)
            if self.phoneStatus != phoneStatus { self.phoneStatus = phoneStatus }
            if self.ecoFlowStatus != ecoFlowStatus { self.ecoFlowStatus = ecoFlowStatus }
            self.task = nil
        }
    }

    /// Keeps the charging flag the accessory itself does not report: AirPods only show a level,
    /// so a level that climbed since the last reading is treated as "on a charger".
    private func apply(_ collected: [Reading]) {
        devices = collected
            .map { reading in
                let climbed = (lastPercent[reading.id] ?? reading.percent) < reading.percent
                return DeviceBattery(
                    id: reading.id,
                    name: reading.name,
                    kind: reading.kind,
                    percent: reading.percent,
                    isCharging: reading.isCharging || climbed,
                    detail: reading.detail
                )
            }
            .sorted(by: DeviceBattery.order)
        lastPercent = Dictionary(collected.map { ($0.id, $0.percent) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Collecting

    /// One source's reading, before the charging flag is reconciled with the previous one.
    private struct Reading {
        let id: String
        let name: String
        let kind: DeviceBattery.Kind
        let percent: Int
        let isCharging: Bool
        var detail: String? = nil
    }

    private static func collect() async -> ([Reading], PhoneStatus, EcoFlowStatus) {
        var byID: [String: Reading] = [:]
        // The IORegistry reports a charging flag, so it wins over system_profiler for the same device.
        for reading in await bluetoothReadings() { byID[reading.id] = reading }
        for reading in hidReadings() { byID[reading.id] = reading }
        let (phone, phoneStatus) = phoneReading()
        if let phone { byID[phone.id] = phone }
        let (station, ecoFlowStatus) = await ecoFlowReading()
        if let station { byID[station.id] = station }
        return (Array(byID.values), phoneStatus, ecoFlowStatus)
    }

    // MARK: - EcoFlow

    /// Charge of the power station, from the reading `EcoFlowService` keeps cached.
    private nonisolated static func ecoFlowReading() async -> (Reading?, EcoFlowStatus) {
        let (reading, name, status) = await EcoFlowService.shared.current()
        guard let reading else { return (nil, status) }
        return (
            Reading(
                // Prefixed so a station never collides with an accessory of the same name.
                id: "ecoflow:" + identifier(name),
                name: name,
                kind: .powerStation,
                percent: reading.percent,
                isCharging: reading.isCharging,
                detail: ecoFlowDetail(reading)
            ),
            status
        )
    }

    /// "2 h 15 min to full · +380 W" under the hover hint.
    private nonisolated static func ecoFlowDetail(_ reading: EcoFlowClient.Reading) -> String? {
        var parts: [String] = []
        if let minutes = reading.remainingMinutes {
            parts.append(reading.isCharging
                ? tr("\(duration(minutes)) to full", "\(duration(minutes)) до полного")
                : tr("\(duration(minutes)) left", "осталось \(duration(minutes))"))
        }
        if reading.isCharging, reading.wattsIn > 0 {
            parts.append("+\(reading.wattsIn) " + tr("W", "Вт"))
        } else if reading.wattsOut > 0 {
            parts.append("\(reading.wattsOut) " + tr("W", "Вт"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private nonisolated static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return tr("\(rest) min", "\(rest) мин") }
        if rest == 0 { return tr("\(hours) h", "\(hours) ч") }
        return tr("\(hours) h \(rest) min", "\(hours) ч \(rest) мин")
    }

    // MARK: - iPhone

    /// macOS exposes no iPhone battery level, so the phone writes its own into a file in iCloud Drive
    /// (a Shortcuts automation); this reads whatever landed there. Normally a bare "57", but
    /// `{"percent": 57}` with the optional `name`, `charging` and `date` keys is accepted too.
    private nonisolated static func phoneReading() -> (Reading?, PhoneStatus) {
        guard AppSettings.phoneBatteryEnabled else { return (nil, .off) }

        let url = URL(fileURLWithPath: (AppSettings.phoneBatteryPath as NSString).expandingTildeInPath)
        requestDownloadIfNeeded(url)
        guard let data = try? Data(contentsOf: url) else { return (nil, .missing) }
        guard let parsed = parsePhone(data) else { return (nil, .unreadable) }

        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let stamp = parsed.date ?? modified ?? Date()
        guard Date().timeIntervalSince(stamp) < phoneStaleInterval else { return (nil, .stale(stamp)) }

        let reading = Reading(
            id: identifier(parsed.name),
            name: parsed.name,
            kind: .phone,
            percent: parsed.percent,
            isCharging: parsed.charging
        )
        return (reading, .ready(stamp))
    }

    /// An iCloud file that has not been downloaded yet sits next to a `.name.icloud` placeholder.
    private nonisolated static func requestDownloadIfNeeded(_ url: URL) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: url.path) else { return }
        let placeholder = url
            .deletingLastPathComponent()
            .appendingPathComponent("." + url.lastPathComponent + ".icloud")
        guard manager.fileExists(atPath: placeholder.path) else { return }
        try? manager.startDownloadingUbiquitousItem(at: url)
    }

    private nonisolated static func parsePhone(_ data: Data) -> (name: String, percent: Int, charging: Bool, date: Date?)? {
        if let dictionary = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            guard let level = ["percent", "level", "battery", "batteryLevel"].compactMap({ number(dictionary[$0]) }).first
            else { return nil }
            let name = (dictionary["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "iPhone"
            let charging = ["charging", "isCharging", "plugged"].compactMap { flag(dictionary[$0]) }.first ?? false
            let date = ["date", "updated", "timestamp"].compactMap { dictionary[$0] as? String }.first.flatMap(parseDate)
            return (name, clamped(level), charging, date)
        }
        // The documented shortcut writes just the number: "57", "57 %" or "0.57".
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let level = Double(text.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return ("iPhone", clamped(level), false, nil)
    }

    /// Shortcuts writes the level either as 0…1 or as 0…100, depending on the action used.
    private nonisolated static func clamped(_ level: Double) -> Int {
        let percent = level <= 1 ? level * 100 : level
        return min(max(Int(percent.rounded()), 0), 100)
    }

    private nonisolated static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, !(value is Bool) { return number.doubleValue }
        if let text = value as? String { return Double(text.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    private nonisolated static func flag(_ value: Any?) -> Bool? {
        if let boolean = value as? Bool { return boolean }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String {
            return ["true", "yes", "1", "да"].contains(text.lowercased())
        }
        return nil
    }

    private nonisolated static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Magic accessories, read straight from the IORegistry.
    private nonisolated static func hidReadings() -> [Reading] {
        guard let matching = IOServiceMatching("AppleDeviceManagementHIDEventService") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var readings: [Reading] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any],
                  let percent = properties["BatteryPercent"] as? Int,
                  (0...100).contains(percent)
            else { continue }

            let name = (properties["Product"] as? String) ?? tr("Accessory", "Аксессуар")
            let category = (properties["Accessory Category"] as? String) ?? ""
            // Bit 0 of the status flags is set while the accessory charges.
            let flags = (properties["BatteryStatusFlags"] as? Int) ?? 0

            readings.append(Reading(
                id: identifier(name),
                name: name,
                kind: kind(category: category, name: name),
                percent: percent,
                isCharging: flags & 0x1 != 0
            ))
        }
        return readings
    }

    /// Connected Bluetooth devices that report a level, AirPods above all.
    private nonisolated static func bluetoothReadings() async -> [Reading] {
        guard let output = try? await Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]),
              let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var readings: [Reading] = []
        for controller in controllers {
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let id = identifier(name)
                    let kind = kind(category: (info["device_minorType"] as? String) ?? "", name: name)

                    // Earbuds: the lower of the two sides is what matters.
                    let sides = ["device_batteryLevelLeft", "device_batteryLevelRight"].compactMap { percent(info[$0]) }
                    if let main = percent(info["device_batteryLevelMain"]) ?? percent(info["device_batteryLevel"]) ?? sides.min() {
                        readings.append(Reading(id: id, name: name, kind: kind, percent: main, isCharging: false))
                    }
                    if let caseLevel = percent(info["device_batteryLevelCase"]) {
                        readings.append(Reading(
                            id: id + "-case",
                            name: tr("\(name) case", "Кейс \(name)"),
                            kind: .headphonesCase,
                            percent: caseLevel,
                            isCharging: false
                        ))
                    }
                }
            }
        }
        return readings
    }

    // MARK: - Parsing

    /// "87 %" → 87.
    private nonisolated static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return value as? Int }
        let digits = text.prefix { $0.isNumber }
        guard let number = Int(digits), (0...100).contains(number) else { return nil }
        return number
    }

    /// The device name is the one key both sources agree on: BLE addresses are randomized and
    /// change on every reconnect, which would reset levels and dismissed warnings.
    private nonisolated static func identifier(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private nonisolated static func kind(category: String, name: String) -> DeviceBattery.Kind {
        let haystack = (category + " " + name).lowercased()
        if haystack.contains("trackpad") { return .trackpad }
        if haystack.contains("mouse") { return .mouse }
        if haystack.contains("keyboard") { return .keyboard }
        if haystack.contains("headphone") || haystack.contains("airpod") || haystack.contains("headset") || haystack.contains("buds") {
            return .headphones
        }
        return .other
    }
}

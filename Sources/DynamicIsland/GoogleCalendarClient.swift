import AppKit
import CryptoKit
import SwiftUI

struct GoogleCalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color
    let isPrimary: Bool
    let isVisibleInGoogle: Bool
}

struct GoogleAuthExpired: LocalizedError {
    var errorDescription: String? { "Google access expired or was revoked. Reconnect in Settings." }
}

struct GoogleAPIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private enum GoogleEndpoints {
    static let authorize = "https://accounts.google.com/o/oauth2/v2/auth"
    static let token = URL(string: "https://oauth2.googleapis.com/token")!
    static let revoke = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let api = "https://www.googleapis.com/calendar/v3"
    static let scope = "https://www.googleapis.com/auth/calendar.readonly"

    static func authorizationURL(clientID: String, redirectURI: String, challenge: String, state: String) -> URL {
        var components = URLComponents(string: authorize)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }
}

/// Google Calendar API v3 over OAuth 2.0 (installed app, loopback redirect + PKCE).
/// Credentials and tokens are kept in `LocalConfigStore`.
@MainActor
final class GoogleCalendarClient {
    private static let signInTimeout: TimeInterval = 5 * 60

    private var signInServer: LoopbackServer?

    private var settings: LocalConfig.Google { LocalConfigStore.current.google }

    var hasCredentials: Bool { !settings.clientID.isEmpty && !settings.clientSecret.isEmpty }
    var isConnected: Bool { settings.refreshToken != nil }

    // MARK: - Sign-in

    func signIn() async throws {
        guard hasCredentials else {
            throw GoogleAPIError(message: "Enter the OAuth Client ID and Client Secret first.")
        }
        let clientID = settings.clientID
        let clientSecret = settings.clientSecret
        let verifier = Self.randomToken(length: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomToken(length: 32)

        let server = LoopbackServer()
        signInServer = server
        defer { signInServer = nil }

        let callback = try await server.awaitCallback(timeout: Self.signInTimeout) { port in
            let url = GoogleEndpoints.authorizationURL(
                clientID: clientID,
                redirectURI: "http://127.0.0.1:\(port)",
                challenge: challenge,
                state: state
            )
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }

        if let error = callback.query["error"] {
            throw GoogleAPIError(message: error == "access_denied" ? "Access was denied." : "Sign-in failed: \(error)")
        }
        guard callback.query["state"] == state, let code = callback.query["code"] else {
            throw GoogleAPIError(message: "Invalid sign-in response.")
        }

        let token = try await requestToken([
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": "http://127.0.0.1:\(callback.port)",
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        guard let refreshToken = token.refreshToken else {
            throw GoogleAPIError(message: "Google returned no refresh token.")
        }
        LocalConfigStore.update {
            $0.google.refreshToken = refreshToken
            $0.google.accessToken = token.accessToken
            $0.google.accessTokenExpiry = Date().addingTimeInterval(token.expiresIn ?? 0)
            $0.google.calendarIDs = nil
        }
    }

    func cancelSignIn() {
        signInServer?.cancel()
    }

    func signOut() async {
        let token = settings.refreshToken
        LocalConfigStore.update {
            $0.google.refreshToken = nil
            $0.google.accessToken = nil
            $0.google.accessTokenExpiry = nil
            $0.google.calendarIDs = nil
        }
        guard let token else { return }
        var request = URLRequest(url: GoogleEndpoints.revoke)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(["token": token])
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - API

    func calendarList() async throws -> [GoogleCalendarInfo] {
        let list: CalendarListDTO = try await get(
            "/users/me/calendarList",
            query: [URLQueryItem(name: "maxResults", value: "250")]
        )
        return (list.items ?? [])
            .filter { $0.deleted != true && $0.hidden != true }
            .map {
                GoogleCalendarInfo(
                    id: $0.id,
                    title: $0.summaryOverride ?? $0.summary ?? $0.id,
                    color: $0.backgroundColor.flatMap(Color.init(hex:)) ?? .blue,
                    isPrimary: $0.primary == true,
                    isVisibleInGoogle: $0.selected == true
                )
            }
            .sorted { ($0.isPrimary ? 0 : 1, $0.title) < ($1.isPrimary ? 0 : 1, $1.title) }
    }

    func events(in calendars: [GoogleCalendarInfo], from start: Date, to end: Date) async throws -> [DayEvent] {
        let formatter = ISO8601DateFormatter()
        var seen = Set<String>()
        var result: [DayEvent] = []

        for calendar in calendars {
            let list: EventListDTO = try await get(
                "/calendars/\(Self.pathEscape(calendar.id))/events",
                query: [
                    URLQueryItem(name: "timeMin", value: formatter.string(from: start)),
                    URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
                    URLQueryItem(name: "singleEvents", value: "true"),
                    URLQueryItem(name: "orderBy", value: "startTime"),
                    URLQueryItem(name: "maxResults", value: "250"),
                ]
            )
            for item in list.items ?? [] {
                let declined = item.attendees?.contains { $0.isSelf == true && $0.responseStatus == "declined" } ?? false
                guard item.status != "cancelled", !declined,
                      let itemStart = item.start.flatMap(Self.parse),
                      let itemEnd = item.end.flatMap(Self.parse) else { continue }

                // The same meeting can appear in several calendars.
                let key = "\(item.iCalUID ?? item.id)|\(itemStart.date.timeIntervalSince1970)"
                guard seen.insert(key).inserted else { continue }

                result.append(DayEvent(
                    id: "\(calendar.id)|\(item.id)",
                    title: item.summary?.isEmpty == false ? item.summary! : "(No title)",
                    start: itemStart.date,
                    end: itemEnd.date,
                    isAllDay: itemStart.isAllDay,
                    color: calendar.color
                ))
            }
        }
        return result.sorted(by: DayEvent.order)
    }

    // MARK: - HTTP

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(string: GoogleEndpoints.api + path)!
        components.queryItems = query
        guard let url = components.url else { throw GoogleAPIError(message: "Bad request URL.") }

        for attempt in 0..<2 {
            let token = try await accessToken(forceRefresh: attempt > 0)
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, attempt == 0 { continue }
            guard (200..<300).contains(status) else {
                let message = (try? JSONDecoder().decode(APIErrorDTO.self, from: data))?.error?.message
                throw GoogleAPIError(message: message ?? "Google Calendar API error (HTTP \(status)).")
            }
            return try JSONDecoder().decode(T.self, from: data)
        }
        throw GoogleAuthExpired()
    }

    private func accessToken(forceRefresh: Bool) async throws -> String {
        let current = settings
        if !forceRefresh, let token = current.accessToken,
           let expiry = current.accessTokenExpiry, expiry.timeIntervalSinceNow > 60 {
            return token
        }
        guard let refreshToken = current.refreshToken else { throw GoogleAuthExpired() }

        do {
            let response = try await requestToken([
                "client_id": current.clientID,
                "client_secret": current.clientSecret,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token",
            ])
            let token = response.accessToken ?? ""
            LocalConfigStore.update {
                $0.google.accessToken = token
                $0.google.accessTokenExpiry = Date().addingTimeInterval(response.expiresIn ?? 0)
            }
            return token
        } catch is GoogleAuthExpired {
            LocalConfigStore.update {
                $0.google.refreshToken = nil
                $0.google.accessToken = nil
                $0.google.accessTokenExpiry = nil
            }
            throw GoogleAuthExpired()
        }
    }

    private func requestToken(_ form: [String: String]) async throws -> TokenDTO {
        var request = URLRequest(url: GoogleEndpoints.token)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(form)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(TokenDTO.self, from: data)

        if let error = response.error {
            if error == "invalid_grant" { throw GoogleAuthExpired() }
            throw GoogleAPIError(message: response.errorDescription ?? error)
        }
        guard response.accessToken != nil else {
            throw GoogleAPIError(message: "Google returned no access token.")
        }
        return response
    }

    // MARK: - Helpers

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func formBody(_ form: [String: String]) -> Data {
        let body = form
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func pathEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved.union(CharacterSet(charactersIn: "@"))) ?? value
    }

    private static func randomToken(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func parse(_ time: EventListDTO.Time) -> (date: Date, isAllDay: Bool)? {
        if let value = time.dateTime {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: value) { return (date, false) }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: value).map { ($0, false) }
        }
        if let value = time.date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: value).map { ($0, true) }
        }
        return nil
    }
}

// MARK: - DTOs

private struct TokenDTO: Decodable {
    let accessToken: String?
    let expiresIn: Double?
    let refreshToken: String?
    let error: String?
    let errorDescription: String?
}

private struct APIErrorDTO: Decodable {
    struct Body: Decodable { let message: String? }
    let error: Body?
}

private struct CalendarListDTO: Decodable {
    struct Entry: Decodable {
        let id: String
        let summary: String?
        let summaryOverride: String?
        let backgroundColor: String?
        let primary: Bool?
        let selected: Bool?
        let hidden: Bool?
        let deleted: Bool?
    }

    let items: [Entry]?
}

private struct EventListDTO: Decodable {
    struct Time: Decodable {
        let dateTime: String?
        let date: String?
    }

    struct Attendee: Decodable {
        let isSelf: Bool?
        let responseStatus: String?

        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
            case responseStatus
        }
    }

    struct Item: Decodable {
        let id: String
        let iCalUID: String?
        let status: String?
        let summary: String?
        let start: Time?
        let end: Time?
        let attendees: [Attendee]?
    }

    let items: [Item]?
}

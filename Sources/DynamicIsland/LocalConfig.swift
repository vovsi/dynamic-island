import Foundation

/// Local-only configuration: credentials, access tokens and personal data.
/// Lives in `~/Library/Application Support/DynamicIsland/config.json` (dir 0700, file 0600),
/// never inside the repository.
struct LocalConfig: Codable {
    struct Google: Codable {
        var clientID = ""
        var clientSecret = ""
        var refreshToken: String?
        var accessToken: String?
        var accessTokenExpiry: Date?
        /// Calendars shown in the schedule; `nil` means "calendars visible in Google Calendar".
        var calendarIDs: [String]?

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            clientID = try c.decodeIfPresent(String.self, forKey: .clientID) ?? ""
            clientSecret = try c.decodeIfPresent(String.self, forKey: .clientSecret) ?? ""
            refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
            accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
            accessTokenExpiry = try c.decodeIfPresent(Date.self, forKey: .accessTokenExpiry)
            calendarIDs = try c.decodeIfPresent([String].self, forKey: .calendarIDs)
        }
    }

    var google = Google()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        google = try c.decodeIfPresent(Google.self, forKey: .google) ?? Google()
    }
}

@MainActor
enum LocalConfigStore {
    static let directory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DynamicIsland", isDirectory: true)

    static let fileURL = directory.appendingPathComponent("config.json")

    private static var cached: LocalConfig?

    static var current: LocalConfig {
        if let cached { return cached }
        let loaded = read()
        cached = loaded
        return loaded
    }

    static func update(_ change: (inout LocalConfig) -> Void) {
        var config = current
        change(&config)
        cached = config
        write(config)
    }

    private static func read() -> LocalConfig {
        guard let data = try? Data(contentsOf: fileURL) else { return LocalConfig() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(LocalConfig.self, from: data)
        } catch {
            NSLog("DynamicIsland: cannot parse \(fileURL.path): \(error)")
            return LocalConfig()
        }
    }

    private static func write(_ config: LocalConfig) {
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try encoder.encode(config).write(to: fileURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            NSLog("DynamicIsland: cannot write \(fileURL.path): \(error)")
        }
    }
}

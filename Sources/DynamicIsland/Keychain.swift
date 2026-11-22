import Foundation
import Security

/// The few secrets the app has to keep (EcoFlow API keys) live in the login keychain, never in
/// `UserDefaults` and never in the repository.
///
/// They share one keychain item, read once per launch. macOS asks for the keychain password per
/// item whose access list the running build is not on, so one item read one time means a single
/// prompt after an update instead of one per secret on every poll.
enum Keychain {
    private static let service = "app.dynamicisland.secrets"
    /// Account of the item that holds every secret as one JSON object.
    private static let vault = "secrets"
    /// Items from builds that kept a secret each; folded into the vault on first read.
    private static let legacyAccounts = [
        AppSettings.ecoFlowAccessKeyAccount,
        AppSettings.ecoFlowSecretKeyAccount,
    ]

    private static let lock = NSLock()
    private static var cache: [String: String]?

    static func string(_ account: String) -> String? {
        guard let value = secrets()[account], !value.isEmpty else { return nil }
        return value
    }

    static func has(_ account: String) -> Bool { string(account) != nil }

    /// An empty value removes the secret.
    static func set(_ value: String, account: String) {
        lock.lock()
        defer { lock.unlock() }

        var secrets = load()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            secrets.removeValue(forKey: account)
        } else {
            secrets[account] = trimmed
        }
        store(secrets)
    }

    // MARK: - Vault

    private static func secrets() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return load()
    }

    /// Caller holds `lock`.
    private static func load() -> [String: String] {
        if let cache { return cache }

        var secrets = data(for: vault)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]

        var migrated = false
        for account in legacyAccounts where secrets[account] == nil {
            guard let raw = data(for: account),
                  let text = String(data: raw, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { continue }
            secrets[account] = text
            migrated = true
        }

        cache = secrets
        if migrated {
            store(secrets)
            for account in legacyAccounts { SecItemDelete(query(account) as CFDictionary) }
        }
        return secrets
    }

    /// Caller holds `lock`. The item is replaced rather than updated: a fresh one carries the
    /// access list of the build that wrote it, so a later update is not met with another prompt.
    private static func store(_ secrets: [String: String]) {
        cache = secrets

        SecItemDelete(query(vault) as CFDictionary)
        guard !secrets.isEmpty, let blob = try? JSONEncoder().encode(secrets) else { return }

        var insert = query(vault)
        insert[kSecValueData as String] = blob
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    private static func data(for account: String) -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

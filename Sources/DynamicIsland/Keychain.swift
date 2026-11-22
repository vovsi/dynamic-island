import Foundation
import Security

/// The few secrets the app has to keep (EcoFlow API keys) live in the login keychain, never in
/// `UserDefaults` and never in the repository.
enum Keychain {
    private static let service = "app.dynamicisland.secrets"

    static func string(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty
        else { return nil }
        return text
    }

    /// An empty value removes the item.
    static func set(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            SecItemDelete(baseQuery(account) as CFDictionary)
            return
        }

        let data = Data(trimmed.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary) == errSecSuccess { return }

        var insert = baseQuery(account)
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func has(_ account: String) -> Bool { string(account) != nil }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

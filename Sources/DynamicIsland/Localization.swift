import Foundation

/// UI language chosen in Settings; `.system` follows the macOS preferred language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case ru

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return tr("System", "Системный")
        case .en: return "English"
        case .ru: return "Русский"
        }
    }
}

enum L10n {
    static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppSettings.languageKey) ?? "") ?? .system
    }

    static var isRussian: Bool {
        switch language {
        case .ru: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
        }
    }

    static var languageCode: String { isRussian ? "ru" : "en" }

    /// Locale for dates and numbers: the system one, or the chosen language with the user's region.
    static var locale: Locale {
        guard language != .system else { return .autoupdatingCurrent }
        return Locale(identifier: "\(languageCode)_\(Locale.current.region?.identifier ?? "US")")
    }
}

/// Every user-facing string goes through this with both translations.
func tr(_ en: String, _ ru: String) -> String {
    L10n.isRussian ? ru : en
}

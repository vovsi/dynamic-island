import Foundation

enum AppSettings {
    static let collapseOnMouseExitKey = "collapseOnMouseExit"
    static let hapticFeedbackKey = "hapticFeedback"
    static let autoCheckUpdatesKey = "autoCheckUpdates"
    static let eventAlertLeadKey = "eventAlertLeadMinutes"
    static let eventAlertTrailKey = "eventAlertTrailMinutes"
    static let eventAlertSoundKey = "eventAlertSound"
    static let lowBatteryAlertKey = "lowBatteryAlert"
    static let lowBatteryThresholdKey = "lowBatteryThresholdPercent"
    static let phoneBatteryEnabledKey = "phoneBatteryEnabled"
    static let phoneBatteryPathKey = "phoneBatteryPath"
    static let languageKey = "language"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            collapseOnMouseExitKey: true,
            hapticFeedbackKey: true,
            autoCheckUpdatesKey: true,
            eventAlertLeadKey: 5,
            eventAlertTrailKey: 5,
            eventAlertSoundKey: true,
            lowBatteryAlertKey: true,
            lowBatteryThresholdKey: 20,
            phoneBatteryEnabledKey: false,
            languageKey: AppLanguage.system.rawValue,
        ])
    }

    static var collapseOnMouseExit: Bool { UserDefaults.standard.bool(forKey: collapseOnMouseExitKey) }
    static var hapticFeedback: Bool { UserDefaults.standard.bool(forKey: hapticFeedbackKey) }
    static var autoCheckUpdates: Bool { UserDefaults.standard.bool(forKey: autoCheckUpdatesKey) }
    /// Minutes before a schedule event starts when the collapsed island starts signalling it.
    static var eventAlertLead: Int { UserDefaults.standard.integer(forKey: eventAlertLeadKey) }
    /// Minutes after a schedule event starts the signal stays on.
    static var eventAlertTrail: Int { UserDefaults.standard.integer(forKey: eventAlertTrailKey) }
    static var eventAlertSound: Bool { UserDefaults.standard.bool(forKey: eventAlertSoundKey) }
    /// Warn beside the collapsed notch when an accessory drops to this level and is not charging.
    static var lowBatteryAlert: Bool { UserDefaults.standard.bool(forKey: lowBatteryAlertKey) }
    static var lowBatteryThreshold: Int { UserDefaults.standard.integer(forKey: lowBatteryThresholdKey) }

    /// iPhone level written to a file by a Shortcuts automation on the phone (iCloud Drive syncs it here).
    static var phoneBatteryEnabled: Bool { UserDefaults.standard.bool(forKey: phoneBatteryEnabledKey) }

    static var phoneBatteryPath: String {
        get {
            let stored = UserDefaults.standard.string(forKey: phoneBatteryPathKey) ?? ""
            return stored.isEmpty ? defaultPhoneBatteryPath : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: phoneBatteryPathKey) }
    }

    static var defaultPhoneBatteryPath: String {
        NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/DynamicIsland/battery.json"
    }

    /// Per-calendar block chosen in Settings (EventKit calendar identifier → block).
    static var calendarBlocks: [String: CalendarBlock] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: calendarBlocksKey) as? [String: String] ?? [:]
            return raw.compactMapValues(CalendarBlock.init(rawValue:))
        }
        set { UserDefaults.standard.set(newValue.mapValues(\.rawValue), forKey: calendarBlocksKey) }
    }

    private static let calendarBlocksKey = "calendarBlocks"

    /// City for the weather; empty means "current location".
    static var weatherCity: String {
        get { UserDefaults.standard.string(forKey: weatherCityKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: weatherCityKey) }
    }

    private static let weatherCityKey = "weatherCity"
}

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
    static let ecoFlowEnabledKey = "ecoFlowEnabled"
    static let ecoFlowSerialKey = "ecoFlowSerial"
    static let ecoFlowNameKey = "ecoFlowName"
    static let ecoFlowRegionKey = "ecoFlowRegion"
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
            ecoFlowEnabledKey: false,
            ecoFlowRegionKey: EcoFlowClient.Region.europe.rawValue,
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

    /// iPhone level written as a plain number to a file by a Shortcuts automation on the phone
    /// (iCloud Drive syncs it here).
    static var phoneBatteryEnabled: Bool { UserDefaults.standard.bool(forKey: phoneBatteryEnabledKey) }

    static var phoneBatteryPath: String {
        get {
            let stored = UserDefaults.standard.string(forKey: phoneBatteryPathKey) ?? ""
            return stored.isEmpty ? defaultPhoneBatteryPath : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: phoneBatteryPathKey) }
    }

    static var defaultPhoneBatteryPath: String {
        NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/DynamicIsland/battery.txt"
    }

    // MARK: - EcoFlow

    /// Charge of an EcoFlow power station, read from the EcoFlow IoT Open Platform.
    /// The two API keys live in the Keychain, never in `UserDefaults`.
    static var ecoFlowEnabled: Bool { UserDefaults.standard.bool(forKey: ecoFlowEnabledKey) }

    static let ecoFlowAccessKeyAccount = "ecoflow.accessKey"
    static let ecoFlowSecretKeyAccount = "ecoflow.secretKey"

    static var ecoFlowSerial: String {
        get { UserDefaults.standard.string(forKey: ecoFlowSerialKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: ecoFlowSerialKey) }
    }

    /// Name shown in the island; empty falls back to the product name.
    static var ecoFlowName: String {
        get { UserDefaults.standard.string(forKey: ecoFlowNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: ecoFlowNameKey) }
    }

    static var ecoFlowRegion: EcoFlowClient.Region {
        get { EcoFlowClient.Region(rawValue: UserDefaults.standard.string(forKey: ecoFlowRegionKey) ?? "") ?? .europe }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: ecoFlowRegionKey) }
    }

    /// Whether both API keys are already in the Keychain.
    static var ecoFlowConfigKeysStored: Bool {
        Keychain.has(ecoFlowAccessKeyAccount) && Keychain.has(ecoFlowSecretKeyAccount)
    }

    /// Everything a poll needs, or `nil` while any of it is missing.
    static var ecoFlowConfig: EcoFlowService.Config? {
        guard let accessKey = Keychain.string(ecoFlowAccessKeyAccount),
              let secretKey = Keychain.string(ecoFlowSecretKeyAccount)
        else { return nil }
        let serial = ecoFlowSerial
        guard !serial.isEmpty else { return nil }

        let name = ecoFlowName.trimmingCharacters(in: .whitespacesAndNewlines)
        return EcoFlowService.Config(
            region: ecoFlowRegion,
            accessKey: accessKey,
            secretKey: secretKey,
            serial: serial,
            name: name.isEmpty ? "EcoFlow" : name
        )
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

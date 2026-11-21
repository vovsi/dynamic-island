import Foundation

enum AppSettings {
    static let collapseOnMouseExitKey = "collapseOnMouseExit"
    static let hapticFeedbackKey = "hapticFeedback"
    static let autoCheckUpdatesKey = "autoCheckUpdates"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            collapseOnMouseExitKey: true,
            hapticFeedbackKey: true,
            autoCheckUpdatesKey: true,
        ])
    }

    static var collapseOnMouseExit: Bool { UserDefaults.standard.bool(forKey: collapseOnMouseExitKey) }
    static var hapticFeedback: Bool { UserDefaults.standard.bool(forKey: hapticFeedbackKey) }
    static var autoCheckUpdates: Bool { UserDefaults.standard.bool(forKey: autoCheckUpdatesKey) }

    /// macOS calendars hidden from the island (EventKit calendar identifiers).
    static var excludedMacCalendarIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: excludedMacCalendarIDsKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: excludedMacCalendarIDsKey) }
    }

    private static let excludedMacCalendarIDsKey = "excludedMacCalendarIDs"
}

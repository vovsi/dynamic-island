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
}

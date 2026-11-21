import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake (no idle system sleep, display stays on) until `endDate`.
@MainActor
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()

    /// Hour presets offered in the island.
    static let presets = [1, 2, 3, 4, 6, 8, 12]

    @Published private(set) var endDate: Date?

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var timer: Timer?

    private static let endDateKey = "keepAwakeUntil"
    private static let assertionName = "Dynamic Island: keep awake" as CFString

    var isActive: Bool { endDate != nil }

    private init() {}

    /// Resumes a session that was running when the app quit.
    func start() {
        guard let saved = UserDefaults.standard.object(forKey: Self.endDateKey) as? Date else { return }
        if saved > Date() {
            activate(until: saved)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.endDateKey)
        }
    }

    func activate(hours: Int) {
        activate(until: Date().addingTimeInterval(TimeInterval(hours) * 3600))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        releaseAssertion()
        endDate = nil
        UserDefaults.standard.removeObject(forKey: Self.endDateKey)
    }

    private func activate(until date: Date) {
        timer?.invalidate()
        guard createAssertion() else { return }
        endDate = date
        UserDefaults.standard.set(date, forKey: Self.endDateKey)

        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The display-sleep assertion also blocks idle system sleep.
    private func createAssertion() -> Bool {
        guard !hasAssertion else { return true }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.assertionName,
            &assertionID
        )
        hasAssertion = result == kIOReturnSuccess
        return hasAssertion
    }

    private func releaseAssertion() {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertionID)
        hasAssertion = false
    }

    /// "1 h 05 min" / "42 min" left until `endDate`, rounded up to a minute.
    static func remainingText(until end: Date, now: Date) -> String {
        let minutes = max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return tr("\(rest) min", "\(rest) мин") }
        return rest == 0
            ? tr("\(hours) h", "\(hours) ч")
            : tr("\(hours) h \(rest) min", "\(hours) ч \(rest) мин")
    }
}

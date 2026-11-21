import AppKit
import EventKit
import SwiftUI

/// Today's events split into the island's "Events" and "Schedule" blocks, refreshed in the background.
@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()
    static let refreshInterval: TimeInterval = 5 * 60

    private static let internetAccountsURL = URL(
        string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"
    )!
    private static let calendarPrivacyURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
    )!

    enum AccessState: Equatable {
        case ready
        case notDetermined
        case denied
    }

    @Published private(set) var access: AccessState = .notDetermined
    @Published private(set) var events: [DayEvent] = []
    @Published private(set) var schedule: [DayEvent] = []
    @Published private(set) var calendars: [CalendarOption] = []
    @Published private(set) var lastRefresh: Date?

    private let source = MacCalendarSource()
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var hasScheduleCalendars: Bool { calendars.contains { $0.block == .schedule } }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { _ in
            MainActor.assumeIsolated { CalendarStore.shared.refresh() }
        }
        timer.tolerance = 30
        self.timer = timer

        observe(NotificationCenter.default, .EKEventStoreChanged) { $0.reload() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { $0.refresh() }

        Task {
            if source.access == .notDetermined { _ = await source.requestAccess() }
            refresh()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping (CalendarStore) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action(CalendarStore.shared) }
        }
        observers.append((center, token))
    }

    // MARK: - Refresh

    /// Syncs remote accounts and reloads today's events.
    func refresh() {
        if source.access == .granted { source.syncRemoteSources() }
        reload()
    }

    private func reload() {
        switch source.access {
        case .granted: access = .ready
        case .notDetermined: access = .notDetermined
        case .denied: access = .denied
        }
        guard access == .ready else {
            events = []
            schedule = []
            calendars = []
            return
        }

        let overrides = AppSettings.calendarBlocks
        calendars = source.calendars()
            .map {
                CalendarOption(
                    id: $0.id,
                    title: $0.title,
                    account: $0.account,
                    color: $0.color,
                    block: overrides[$0.id] ?? ($0.isRemoteAccount ? .schedule : .events)
                )
            }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }

        let blocks = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0.block) })
        let today = DayEvent.todayRange()
        let all = source.events(
            from: today.start,
            to: today.end,
            calendarIDs: Set(calendars.filter { $0.block != .hidden }.map(\.id))
        )
        events = all.filter { blocks[$0.calendarID] == .events }
        schedule = all.filter { blocks[$0.calendarID] == .schedule }
        lastRefresh = Date()
    }

    // MARK: - Actions

    func requestAccess() async {
        _ = await source.requestAccess()
        refresh()
    }

    func setBlock(_ block: CalendarBlock, for calendarID: String) {
        var overrides = AppSettings.calendarBlocks
        overrides[calendarID] = block
        AppSettings.calendarBlocks = overrides
        reload()
    }

    /// Google is connected through System Settings → Internet Accounts; EventKit picks it up automatically.
    func openInternetAccounts() {
        NSWorkspace.shared.open(Self.internetAccountsURL)
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(Self.calendarPrivacyURL)
    }
}

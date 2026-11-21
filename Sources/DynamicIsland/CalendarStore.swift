import AppKit
import EventKit
import SwiftUI

/// Today's events from macOS Calendar and Google Calendar, refreshed in the background.
@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()
    static let refreshInterval: TimeInterval = 5 * 60

    enum MacState: Equatable {
        case ready
        case notDetermined
        case denied
    }

    enum GoogleState: Equatable {
        case ready
        case notConfigured
        case disconnected
        case failed(String)
    }

    @Published private(set) var macState: MacState = .notDetermined
    @Published private(set) var macEvents: [DayEvent] = []
    @Published private(set) var macCalendars: [CalendarOption] = []

    @Published private(set) var googleState: GoogleState = .notConfigured
    @Published private(set) var googleEvents: [DayEvent] = []
    @Published private(set) var googleCalendars: [CalendarOption] = []
    @Published private(set) var googleAccount: String?
    @Published private(set) var isGoogleSigningIn = false
    @Published private(set) var googleSignInError: String?

    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false

    private let mac = MacCalendarSource()
    private let google = GoogleCalendarClient()
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var isGoogleConnected: Bool { google.isConnected }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { _ in
            Task { @MainActor in await CalendarStore.shared.refresh() }
        }
        timer.tolerance = 30
        self.timer = timer

        observe(NotificationCenter.default, .EKEventStoreChanged) { $0.refreshMac() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { store in
            Task { await store.refresh() }
        }

        Task {
            if mac.access == .notDetermined { _ = await mac.requestAccess() }
            await refresh()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping (CalendarStore) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action(CalendarStore.shared) }
        }
        observers.append((center, token))
    }

    // MARK: - Refresh

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshMac()
        await refreshGoogle()
        lastRefresh = Date()
        isRefreshing = false
    }

    func refreshMac() {
        switch mac.access {
        case .granted: macState = .ready
        case .notDetermined: macState = .notDetermined
        case .denied: macState = .denied
        }
        guard macState == .ready else {
            macEvents = []
            macCalendars = []
            return
        }
        let excluded = AppSettings.excludedMacCalendarIDs
        let today = DayEvent.todayRange()
        macCalendars = mac.calendarOptions(excluded: excluded)
        macEvents = mac.events(from: today.start, to: today.end, excluded: excluded)
    }

    func refreshGoogle() async {
        guard google.hasCredentials else {
            clearGoogle(state: .notConfigured)
            return
        }
        guard google.isConnected else {
            clearGoogle(state: .disconnected)
            return
        }

        do {
            let calendars = try await google.calendarList()
            let selected = LocalConfigStore.current.google.calendarIDs.map(Set.init)
                ?? Set(calendars.filter { $0.isPrimary || $0.isVisibleInGoogle }.map(\.id))

            googleAccount = calendars.first(where: \.isPrimary)?.id
            googleCalendars = calendars.map {
                CalendarOption(id: $0.id, title: $0.title, group: "", color: $0.color, isEnabled: selected.contains($0.id))
            }

            let today = DayEvent.todayRange()
            googleEvents = try await google.events(
                in: calendars.filter { selected.contains($0.id) },
                from: today.start,
                to: today.end
            )
            googleState = .ready
        } catch is GoogleAuthExpired {
            clearGoogle(state: .failed(GoogleAuthExpired().localizedDescription))
        } catch {
            // Keep the last successful events; network hiccups should not blank the schedule.
            googleState = .failed(error.localizedDescription)
        }
    }

    private func clearGoogle(state: GoogleState) {
        googleState = state
        googleEvents = []
        googleCalendars = []
        googleAccount = nil
    }

    // MARK: - macOS Calendar

    func requestMacAccess() async {
        _ = await mac.requestAccess()
        refreshMac()
    }

    func setMacCalendar(_ id: String, enabled: Bool) {
        var excluded = AppSettings.excludedMacCalendarIDs
        if enabled { excluded.remove(id) } else { excluded.insert(id) }
        AppSettings.excludedMacCalendarIDs = excluded
        refreshMac()
    }

    // MARK: - Google Calendar

    func signInToGoogle(clientID: String, clientSecret: String) async {
        LocalConfigStore.update {
            $0.google.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.google.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        isGoogleSigningIn = true
        googleSignInError = nil
        do {
            try await google.signIn()
        } catch is CancellationError {
        } catch {
            googleSignInError = error.localizedDescription
        }
        isGoogleSigningIn = false
        await refreshGoogle()
    }

    func cancelGoogleSignIn() {
        google.cancelSignIn()
    }

    func signOutOfGoogle() async {
        await google.signOut()
        googleSignInError = nil
        await refreshGoogle()
    }

    func setGoogleCalendar(_ id: String, enabled: Bool) {
        var ids = Set(googleCalendars.filter(\.isEnabled).map(\.id))
        if enabled { ids.insert(id) } else { ids.remove(id) }
        LocalConfigStore.update { $0.google.calendarIDs = ids.sorted() }
        googleCalendars = googleCalendars.map {
            var option = $0
            option.isEnabled = ids.contains($0.id)
            return option
        }
        Task { await refreshGoogle() }
    }
}

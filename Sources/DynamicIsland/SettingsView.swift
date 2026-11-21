import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Dynamic Island Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            self.window = window
        }
        CalendarStore.shared.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var updates = UpdateManager.shared
    @ObservedObject private var calendars = CalendarStore.shared
    @ObservedObject private var weather = WeatherStore.shared

    @AppStorage(AppSettings.collapseOnMouseExitKey) private var collapseOnMouseExit = true
    @AppStorage(AppSettings.hapticFeedbackKey) private var hapticFeedback = true
    @AppStorage(AppSettings.autoCheckUpdatesKey) private var autoCheckUpdates = true
    @AppStorage(AppSettings.eventAlertLeadKey) private var eventAlertLead = 5
    @AppStorage(AppSettings.eventAlertTrailKey) private var eventAlertTrail = 5

    @StateObject private var state = SettingsState()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                if let loginItemError = state.loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("Collapse when cursor leaves the island", isOn: $collapseOnMouseExit)
                Toggle("Haptic feedback", isOn: $hapticFeedback)
            }

            calendarSections

            Section("Event Alert") {
                Stepper("Show \(eventAlertLead) min before start", value: $eventAlertLead, in: 0...60)
                Stepper("Keep \(eventAlertTrail) min after start", value: $eventAlertTrail, in: 0...60)
                Text("The collapsed island shows a pulsing warning beside the notch when a Schedule event is near.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            weatherSection

            Section("Refresh") {
                LabeledContent("Last updated") {
                    if let lastRefresh = calendars.lastRefresh {
                        Text(lastRefresh, format: .dateTime.hour().minute().second())
                    } else {
                        Text("—")
                    }
                }
                HStack {
                    Text("Calendars refresh every 5 minutes in the background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh Now") { calendars.refresh() }
                }
            }

            Section("Updates") {
                LabeledContent("Version", value: "\(updates.version) (\(updates.shortCommit))")
                LabeledContent("Branch", value: updates.branch)
                if let lastChecked = updates.lastChecked {
                    LabeledContent("Last checked") {
                        Text(lastChecked, format: .relative(presentation: .named))
                    }
                }
                Toggle("Check for updates automatically", isOn: $autoCheckUpdates)

                statusRow

                HStack {
                    Button("Check for Updates") {
                        Task { await updates.check() }
                    }
                    .disabled(updates.isBusy)

                    Spacer()

                    Button("Update & Restart") {
                        Task { await updates.performUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!updates.isUpdateAvailable || updates.isBusy)
                }

                if !updates.log.isEmpty {
                    DisclosureGroup("Build log", isExpanded: $state.showLog) {
                        ScrollView {
                            Text(updates.log)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 140)
                    }
                }
            }

            Section {
                HStack {
                    Text("Right-click the island for quick actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Dynamic Island", role: .destructive) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 600)
    }

    // MARK: - Weather

    private var weatherSection: some View {
        Section("Weather") {
            HStack {
                TextField("City", text: $state.weatherCity, prompt: Text("Current location"))
                    .onSubmit { weather.setCity(state.weatherCity) }
                Button("Save") { weather.setCity(state.weatherCity) }
                    .disabled(state.weatherCity.trimmingCharacters(in: .whitespaces) == AppSettings.weatherCity)
            }
            switch weather.status {
            case .needsLocation:
                HStack {
                    Text("Location access is denied. Enter a city or allow access.")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open Privacy Settings") { weather.openLocationPrivacySettings() }
                }
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            case .loading, .ready:
                EmptyView()
            }
            HStack {
                if let lastUpdate = weather.lastUpdate {
                    Text("Updated \(lastUpdate.formatted(date: .omitted, time: .shortened)) · refreshes hourly")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { weather.refresh() }
            }
            Text("Leave the city empty to use your current location. Weather data by Open-Meteo.com.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Calendars

    @ViewBuilder
    private var calendarSections: some View {
        Section("Calendars") {
            switch calendars.access {
            case .notDetermined:
                HStack {
                    Text("Access to Calendar is required.")
                    Spacer()
                    Button("Allow Access") { Task { await calendars.requestAccess() } }
                }
            case .denied:
                HStack {
                    Text("Access to Calendar is denied.")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open Privacy Settings") { calendars.openPrivacySettings() }
                }
            case .ready:
                HStack {
                    Text(calendars.hasScheduleCalendars ? "Google account connected." : "Google account is not connected.")
                        .foregroundStyle(calendars.hasScheduleCalendars ? Color.secondary : Color.orange)
                    Spacer()
                    Button(calendars.hasScheduleCalendars ? "Add Account…" : "Connect Google…") {
                        calendars.openInternetAccounts()
                    }
                }
            }
            Text("Google is connected through System Settings → Internet Accounts → Google (enable Calendars). How often macOS syncs it is set in Calendar → Settings → Accounts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ForEach(accounts, id: \.id) { account in
            Section(account.title) {
                ForEach(calendars.calendars.filter { $0.accountID == account.id }) { option in
                    Picker(selection: Binding(
                        get: { option.block },
                        set: { calendars.setBlock($0, for: option.id) }
                    )) {
                        ForEach(CalendarBlock.allCases) { Text($0.title).tag($0) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(option.color).frame(width: 8, height: 8)
                            Text(option.title)
                        }
                    }
                }
            }
        }
    }

    /// One section per account; same-named accounts (e.g. two "Google") get a number.
    private var accounts: [(id: String, title: String)] {
        var seen = Set<String>()
        var titleCount: [String: Int] = [:]
        return calendars.calendars.compactMap { option in
            guard seen.insert(option.accountID).inserted else { return nil }
            let base = option.account.isEmpty ? "Other" : option.account
            titleCount[base, default: 0] += 1
            let number = titleCount[base]!
            return (option.accountID, number == 1 ? base : "\(base) \(number)")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch updates.status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…")
            }
        case .upToDate:
            Label("You're up to date.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available(let remote):
            Label("Update available: \(remote.prefix(7))", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .updating(let step):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(step)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

}

/// View-local state (the CLT toolchain has no SwiftUI macro plugin, so `@State` is unavailable).
@MainActor
private final class SettingsState: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginItemError: String?
    @Published var showLog = false
    @Published var weatherCity = AppSettings.weatherCity

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

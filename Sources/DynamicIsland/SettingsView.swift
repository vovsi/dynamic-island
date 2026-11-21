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
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var updates = UpdateManager.shared
    @ObservedObject private var calendars = CalendarStore.shared

    @AppStorage(AppSettings.collapseOnMouseExitKey) private var collapseOnMouseExit = true
    @AppStorage(AppSettings.hapticFeedbackKey) private var hapticFeedback = true
    @AppStorage(AppSettings.autoCheckUpdatesKey) private var autoCheckUpdates = true

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

            macCalendarSection
            googleCalendarSection

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
                    Button("Refresh Now") {
                        Task { await calendars.refresh() }
                    }
                    .disabled(calendars.isRefreshing)
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

    // MARK: - Calendars

    @ViewBuilder
    private var macCalendarSection: some View {
        Section("macOS Calendar — Events") {
            switch calendars.macState {
            case .notDetermined:
                HStack {
                    Text("Access to Calendar is required.")
                    Spacer()
                    Button("Allow Access") { Task { await calendars.requestMacAccess() } }
                }
            case .denied:
                HStack {
                    Text("Access to Calendar is denied.")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            case .ready:
                if calendars.macCalendars.isEmpty {
                    Text("No calendars found.").foregroundStyle(.secondary)
                }
                ForEach(calendars.macCalendars) { option in
                    calendarToggle(option) { calendars.setMacCalendar(option.id, enabled: $0) }
                }
            }
        }
    }

    @ViewBuilder
    private var googleCalendarSection: some View {
        Section("Google Calendar — Schedule") {
            if calendars.isGoogleConnected {
                HStack {
                    Label(calendars.googleAccount ?? "Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Disconnect") { Task { await calendars.signOutOfGoogle() } }
                }
                if case .failed(let message) = calendars.googleState {
                    Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                ForEach(calendars.googleCalendars) { option in
                    calendarToggle(option) { calendars.setGoogleCalendar(option.id, enabled: $0) }
                }
            } else {
                TextField("Client ID", text: $state.googleClientID)
                SecureField("Client Secret", text: $state.googleClientSecret)
                HStack {
                    if calendars.isGoogleSigningIn {
                        ProgressView().controlSize(.small)
                        Text("Waiting for sign-in in the browser…")
                        Spacer()
                        Button("Cancel") { calendars.cancelGoogleSignIn() }
                    } else {
                        Spacer()
                        Button("Connect Google Calendar") {
                            Task {
                                await calendars.signInToGoogle(
                                    clientID: state.googleClientID,
                                    clientSecret: state.googleClientSecret
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.googleClientID.isEmpty || state.googleClientSecret.isEmpty)
                    }
                }
                if let error = calendars.googleSignInError ?? failedGoogleMessage {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                Text("Google Cloud Console → enable Google Calendar API → OAuth client ID of type “Desktop app”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Credentials and tokens are stored locally in \(LocalConfigStore.fileURL.path).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var failedGoogleMessage: String? {
        if case .failed(let message) = calendars.googleState { return message }
        return nil
    }

    private func calendarToggle(_ option: CalendarOption, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { option.isEnabled }, set: set)) {
            HStack(spacing: 6) {
                Circle().fill(option.color).frame(width: 8, height: 8)
                Text(option.title)
                if !option.group.isEmpty {
                    Text(option.group).foregroundStyle(.secondary)
                }
            }
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
    @Published var googleClientID = LocalConfigStore.current.google.clientID
    @Published var googleClientSecret = LocalConfigStore.current.google.clientSecret

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

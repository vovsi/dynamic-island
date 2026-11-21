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
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
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
        .frame(width: 480)
        .frame(minHeight: 520)
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

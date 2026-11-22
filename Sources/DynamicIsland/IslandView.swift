import SwiftUI

struct IslandRootView: View {
    static let coordinateSpace = "island"

    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject private var updates = UpdateManager.shared
    @AppStorage(AppSettings.languageKey) private var language = AppLanguage.system.rawValue
    var onTap: () -> Void

    var body: some View {
        let size = viewModel.size
        let shape = NotchShape(topRadius: viewModel.topRadius, bottomRadius: viewModel.bottomRadius)

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(
                    color: .black.opacity(viewModel.isExpanded ? 0.55 : 0),
                    radius: viewModel.isExpanded ? 18 : 0,
                    y: viewModel.isExpanded ? 8 : 0
                )

            ZStack(alignment: .top) {
                if viewModel.isExpanded {
                    DashboardView(
                        notchSize: viewModel.notch.size,
                        horizontalInset: viewModel.topRadius + 18,
                        updateAvailable: updates.isUpdateAvailable,
                        isWeatherExpanded: viewModel.isWeatherExpanded,
                        isKeepAwakePickerOpen: viewModel.isKeepAwakePickerOpen,
                        onOpenSettings: viewModel.onOpenSettings,
                        onWeatherToggle: viewModel.onWeatherToggle,
                        onKeepAwakePickerToggle: viewModel.onKeepAwakePickerToggle,
                        onWeatherFrame: { viewModel.weatherFrame = $0 }
                    )
                    .id(language)
                    .transition(.islandContent)
                } else if viewModel.hasEventAlert, let eventStart = viewModel.eventAlertStart {
                    EventAlertIndicator(
                        eventStart: eventStart,
                        sideWidth: IslandViewModel.alertSideWidth,
                        inset: viewModel.topRadius,
                        isHovering: viewModel.isHovering,
                        onDismiss: viewModel.onDismissEventAlert
                    )
                        .frame(height: viewModel.notch.size.height)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .coordinateSpace(name: Self.coordinateSpace)
            .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .onTapGesture { onTap() }
        .contextMenu {
            Button(tr("Settings…", "Настройки…")) { viewModel.onOpenSettings() }
            Button(tr("Check for Updates", "Проверить обновления")) { Task { await UpdateManager.shared.check() } }
            Divider()
            Button(tr("Quit Dynamic Island", "Завершить Dynamic Island")) { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, L10n.locale)
    }
}

// MARK: - Event alert

/// Collapsed-island signal for a schedule event: pulsing red dot on the left, mm:ss countdown to the start on the right
/// (blue, red once it hits 00:00). On hover the countdown turns into a close button that dismisses the current alert.
private struct EventAlertIndicator: View {
    let eventStart: Date
    let sideWidth: CGFloat
    let inset: CGFloat
    let isHovering: Bool
    let onDismiss: () -> Void

    private static let pulsePeriod: TimeInterval = 1.6
    private static let countdownColor = Color(red: 0.3, green: 0.68, blue: 1.0)

    var body: some View {
        HStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate / Self.pulsePeriod * 2 * .pi
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(0.3 + 0.7 * (0.5 + 0.5 * sin(phase)))
            }
            .frame(width: sideWidth)

            Spacer(minLength: 0)

            ZStack {
                if isHovering {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: sideWidth, height: sideWidth)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tr("Dismiss this alert", "Скрыть напоминание"))
                    .transition(.opacity)
                } else {
                    // Ticks aligned to the event start so the display flips exactly on whole seconds.
                    TimelineView(.periodic(from: eventStart.addingTimeInterval(-86_400), by: 1)) { context in
                        let remaining = max(0, Int(ceil(eventStart.timeIntervalSince(context.date))))
                        Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(remaining > 0 ? Self.countdownColor : .red)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: sideWidth)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, inset)
    }
}

// MARK: - Content transition

private struct BlurScaleModifier: ViewModifier {
    var progress: CGFloat // 0 = hidden, 1 = visible

    func body(content: Content) -> some View {
        content
            .blur(radius: (1 - progress) * 10)
            .scaleEffect(0.86 + 0.14 * progress, anchor: .top)
            .opacity(progress)
    }
}

extension AnyTransition {
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurScaleModifier(progress: 0),
                identity: BlurScaleModifier(progress: 1)
            )
            .animation(.spring(response: 0.42, dampingFraction: 0.82).delay(0.06)),
            removal: .modifier(
                active: BlurScaleModifier(progress: 0),
                identity: BlurScaleModifier(progress: 1)
            )
            .animation(.easeIn(duration: 0.14))
        )
    }
}

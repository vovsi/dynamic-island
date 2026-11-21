import SwiftUI

struct IslandRootView: View {
    static let coordinateSpace = "island"

    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject private var updates = UpdateManager.shared
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
                        onOpenSettings: viewModel.onOpenSettings,
                        onWeatherToggle: viewModel.onWeatherToggle,
                        onWeatherFrame: { viewModel.weatherFrame = $0 }
                    )
                    .transition(.islandContent)
                } else if viewModel.hasEventAlert {
                    EventAlertIndicator(sideWidth: IslandViewModel.alertSideWidth, inset: viewModel.topRadius)
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
            Button("Settings…") { viewModel.onOpenSettings() }
            Button("Check for Updates") { Task { await UpdateManager.shared.check() } }
            Divider()
            Button("Quit Dynamic Island") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Event alert

/// Collapsed-island signal for a schedule event: pulsing red warning on the left, blue schedule icon on the right.
private struct EventAlertIndicator: View {
    let sideWidth: CGFloat
    let inset: CGFloat

    private static let pulsePeriod: TimeInterval = 1.6

    var body: some View {
        HStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate / Self.pulsePeriod * 2 * .pi
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .opacity(0.3 + 0.7 * (0.5 + 0.5 * sin(phase)))
            }
            .frame(width: sideWidth)

            Spacer(minLength: 0)

            Image(systemName: "clock.fill")
                .foregroundStyle(.blue)
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

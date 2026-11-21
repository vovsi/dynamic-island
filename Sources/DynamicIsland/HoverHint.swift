import SwiftUI

/// Tooltip bubble shown under a control on hover. AppKit's `.help` tooltips only appear while the app
/// is active, and the island's non-activating panel never activates it.
extension View {
    /// `nil` or an empty text shows nothing.
    func hoverHint(_ text: String?) -> some View {
        modifier(HoverHintModifier(text: text ?? ""))
    }
}

/// One hint at a time, shown after a short delay.
@MainActor
private final class HoverHintCenter: ObservableObject {
    static let shared = HoverHintCenter()

    @Published private(set) var visible: String?

    private var hovered: String?
    private var showWork: DispatchWorkItem?

    private static let delay: TimeInterval = 0.5

    func hover(_ text: String, isInside: Bool) {
        if isInside {
            hovered = text
            showWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.hovered == text else { return }
                    withAnimation(.easeOut(duration: 0.12)) { self.visible = text }
                }
            }
            showWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
        } else if hovered == text {
            dismiss()
        }
    }

    func dismiss() {
        showWork?.cancel()
        showWork = nil
        hovered = nil
        if visible != nil {
            withAnimation(.easeIn(duration: 0.08)) { visible = nil }
        }
    }
}

private struct HoverHintModifier: ViewModifier {
    let text: String
    @ObservedObject private var center = HoverHintCenter.shared

    func body(content: Content) -> some View {
        if text.isEmpty {
            content
        } else {
            content
                .onHover { center.hover(text, isInside: $0) }
                .simultaneousGesture(TapGesture().onEnded { center.dismiss() })
                .onDisappear { if center.visible == text { center.dismiss() } }
                .overlay(alignment: .top) {
                    GeometryReader { proxy in
                        if center.visible == text {
                            HintBubble(text: text)
                                .fixedSize()
                                .frame(width: proxy.size.width)
                                .offset(y: proxy.size.height + 4)
                                .transition(.opacity)
                        }
                    }
                    .allowsHitTesting(false)
                }
        }
    }
}

private struct HintBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(white: 0.16))
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
    }
}

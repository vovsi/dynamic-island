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
    @Environment(\.islandWidth) private var islandWidth

    func body(content: Content) -> some View {
        if text.isEmpty {
            content
        } else {
            content
                .onHover { center.hover(text, isInside: $0) }
                .simultaneousGesture(TapGesture().onEnded { center.dismiss() })
                .onDisappear { if center.visible == text { center.dismiss() } }
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        if center.visible == text {
                            HintBubble(text: text)
                                .fixedSize()
                                .offset(
                                    x: HintBubble.offsetX(
                                        text,
                                        anchor: proxy.frame(in: .named(IslandRootView.coordinateSpace)),
                                        islandWidth: islandWidth
                                    ),
                                    y: proxy.size.height + 4
                                )
                                .transition(.opacity)
                        }
                    }
                    .allowsHitTesting(false)
                }
        }
    }
}

// MARK: - Island width

/// The island clips its contents, so a bubble has to be placed against the island's own width
/// rather than the control it belongs to.
private struct IslandWidthKey: EnvironmentKey {
    /// Overridden by `IslandRootView`; the expanded width is only a sane stand-in.
    static let defaultValue: CGFloat = IslandViewModel.expandedWidth
}

extension EnvironmentValues {
    var islandWidth: CGFloat {
        get { self[IslandWidthKey.self] }
        set { self[IslandWidthKey.self] = newValue }
    }
}

private struct HintBubble: View {
    let text: String

    private static let margin: CGFloat = 6
    private static let sideInset: CGFloat = 8
    private static let fontSize: CGFloat = 11

    /// Horizontal shift from the control's leading edge: centred on the control, then pulled back
    /// inside the island so a bubble beside the first or last control is not cut in half.
    static func offsetX(_ text: String, anchor: CGRect, islandWidth: CGFloat) -> CGFloat {
        let width = measuredWidth(text)
        let rightmost = max(islandWidth - margin - width, margin)
        let centred = anchor.midX - width / 2
        return min(max(centred, margin), rightmost) - anchor.minX
    }

    /// Measured, since the bubble is laid out before anything can report its size back.
    private static func measuredWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let text = (text as NSString).size(withAttributes: [.font: font]).width
        return text.rounded(.up) + 2 * sideInset + 2 // + the 1 pt border on either side
    }

    var body: some View {
        Text(text)
            .font(.system(size: Self.fontSize, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, Self.sideInset)
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

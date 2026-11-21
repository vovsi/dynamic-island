import AppKit
import SwiftUI

@MainActor
final class IslandViewModel: ObservableObject {
    enum State {
        case collapsed
        case expanded
    }

    @Published var state: State = .collapsed
    @Published var isHovering = false
    @Published var notch: NotchInfo = .fallback

    var onOpenSettings: () -> Void = {}
    var onCollapseRequest: () -> Void = {}

    // MARK: - Geometry

    static let expandedWidth: CGFloat = 680
    static let expandedContentHeight: CGFloat = 200
    static let hoverGrowth = CGSize(width: 18, height: 4)

    var isExpanded: Bool { state == .expanded }

    var topRadius: CGFloat { isExpanded ? 14 : 6 }
    var bottomRadius: CGFloat { isExpanded ? 34 : 10 }

    var expandedSize: CGSize {
        CGSize(width: Self.expandedWidth, height: notch.size.height + Self.expandedContentHeight)
    }

    var collapsedSize: CGSize {
        CGSize(width: notch.size.width + 2 * 6, height: notch.size.height)
    }

    /// Current island size, including the concave top "ears".
    var size: CGSize {
        switch state {
        case .expanded:
            return expandedSize
        case .collapsed:
            guard isHovering else { return collapsedSize }
            return CGSize(
                width: collapsedSize.width + Self.hoverGrowth.width,
                height: collapsedSize.height + Self.hoverGrowth.height
            )
        }
    }

    /// Island rect in global screen coordinates.
    func screenRect(for size: CGSize) -> NSRect {
        NSRect(
            x: notch.midX - size.width / 2,
            y: notch.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    var hitRect: NSRect {
        screenRect(for: size).insetBy(dx: -2, dy: -2)
    }
}

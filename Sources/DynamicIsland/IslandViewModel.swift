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
    @Published var isWeatherExpanded = false
    /// Hour picker for the keep-awake mode, opened by the pill button.
    @Published var isKeepAwakePickerOpen = false
    /// A schedule event is about to start (or has just started): shown beside the collapsed notch.
    @Published var hasEventAlert = false

    /// Weather block frame in the island's coordinate space (top-left origin).
    var weatherFrame: CGRect = .zero

    var onOpenSettings: () -> Void = {}
    var onCollapseRequest: () -> Void = {}
    var onWeatherToggle: () -> Void = {}
    var onKeepAwakePickerToggle: () -> Void = {}
    var onDismissEventAlert: () -> Void = {}

    // MARK: - Geometry

    static let expandedWidth: CGFloat = 680
    static let expandedContentHeight: CGFloat = 200
    /// Extra height while the 7-day forecast is open below the notch.
    static let weatherExtraHeight: CGFloat = 40
    static let hoverGrowth = CGSize(width: 18, height: 4)
    /// Width added on each side of the collapsed notch for the event alert icons.
    static let alertSideWidth: CGFloat = 30

    var isExpanded: Bool { state == .expanded }

    var topRadius: CGFloat { isExpanded ? 14 : 6 }
    var bottomRadius: CGFloat { isExpanded ? 34 : 10 }

    var expandedSize: CGSize {
        CGSize(
            width: Self.expandedWidth,
            height: notch.size.height + Self.expandedContentHeight + (isWeatherExpanded ? Self.weatherExtraHeight : 0)
        )
    }

    /// Largest island size; the panel is laid out for it once.
    var maxExpandedSize: CGSize {
        CGSize(width: Self.expandedWidth, height: notch.size.height + Self.expandedContentHeight + Self.weatherExtraHeight)
    }

    var collapsedSize: CGSize {
        let alert = hasEventAlert ? 2 * Self.alertSideWidth : 0
        return CGSize(width: notch.size.width + 2 * 6 + alert, height: notch.size.height)
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

    /// Weather block in global screen coordinates.
    var weatherScreenRect: NSRect {
        guard !weatherFrame.isNull else { return .zero }
        let island = screenRect(for: size)
        return NSRect(
            x: island.minX + weatherFrame.minX,
            y: island.maxY - weatherFrame.maxY,
            width: weatherFrame.width,
            height: weatherFrame.height
        )
    }

    var hitRect: NSRect {
        screenRect(for: size).insetBy(dx: -2, dy: -2)
    }
}

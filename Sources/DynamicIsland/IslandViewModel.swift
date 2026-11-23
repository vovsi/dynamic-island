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
    /// Start of the event the alert counts down to.
    @Published var eventAlertStart: Date?
    /// Accessory that is low on battery and not charging: shown beside the collapsed notch until it charges.
    @Published var batteryAlert: DeviceBattery?

    /// Weather block frame in the island's coordinate space (top-left origin).
    var weatherFrame: CGRect = .zero

    var onOpenSettings: () -> Void = {}
    var onCollapseRequest: () -> Void = {}
    var onWeatherToggle: () -> Void = {}
    var onKeepAwakePickerToggle: () -> Void = {}
    var onDismissEventAlert: () -> Void = {}
    var onDismissBatteryAlert: () -> Void = {}

    // MARK: - Geometry

    /// Width of the expanded island before the top row asks for more room.
    nonisolated static let baseExpandedWidth: CGFloat = 680
    static let expandedContentHeight: CGFloat = 200
    /// Extra height while the 7-day forecast is open below the notch.
    static let weatherExtraHeight: CGFloat = 40
    static let hoverGrowth = CGSize(width: 18, height: 4)
    /// Width added on each side of the collapsed notch for an alert (dot / countdown / battery badge).
    static let alertSideWidth: CGFloat = 46
    /// Corner radius of the expanded island, and the inset its content keeps from the edges.
    static let expandedTopRadius: CGFloat = 14
    static let expandedInset: CGFloat = expandedTopRadius + 18
    /// Gap between battery badges, as a share of their size.
    static let badgeSpacingRatio: CGFloat = 0.22

    var isExpanded: Bool { state == .expanded }

    /// Height of the expanded island's top row: the notch height scaled by the user's setting,
    /// leaving a hairline of black above and below at scale 1.
    static func topRowHeight(notchHeight: CGFloat) -> CGFloat {
        max((notchHeight - 4) * AppSettings.topRowScale, 20)
    }

    /// Band the top row occupies; it never shrinks below the notch, which has to stay clear,
    /// and keeps the same hairline above and below the row once the row outgrows it.
    static func topRowBandHeight(notchHeight: CGFloat) -> CGFloat {
        max(notchHeight, topRowHeight(notchHeight: notchHeight) + 4)
    }

    /// Band the top row occupies on the current screen.
    var topRowBandHeight: CGFloat { Self.topRowBandHeight(notchHeight: notch.size.height) }

    /// Header buttons and battery badges are squares of this size.
    static func topRowButtonSize(notchHeight: CGFloat) -> CGFloat {
        min(topRowHeight(notchHeight: notchHeight), 30 * AppSettings.topRowScale)
    }

    /// Gap between the weather pill, the badges and the buttons.
    static var topRowGap: CGFloat { 8 * AppSettings.topRowScale }

    /// Accessories shown as badges left of the notch.
    private var badgeCount: Int { min(DeviceBatteryStore.shared.devices.count, DeviceBatteryStore.maxShown) }

    /// The island widens as the top row is scaled up, so the badges really grow with it instead of
    /// being squeezed back down by the room left of the notch. Capped by the screen.
    var expandedWidth: CGFloat {
        let button = Self.topRowButtonSize(notchHeight: notch.size.height)
        let count = CGFloat(badgeCount)
        let badges = count > 0
            ? count * button + (count - 1) * button * Self.badgeSpacingRatio + Self.topRowGap
            : 0
        // Measured for a placeholder reading, so an hourly weather refresh never resizes the island.
        let left = WeatherPill.minWidth(for: nil, scale: AppSettings.topRowScale) + badges
        let needed = 2 * (left + Self.expandedInset + 8) + notch.size.width
        let limit = max(Self.baseExpandedWidth, notch.screenFrame.width - 80)
        return min(max(Self.baseExpandedWidth, needed), limit)
    }

    var topRadius: CGFloat { isExpanded ? Self.expandedTopRadius : 6 }
    var bottomRadius: CGFloat { isExpanded ? 34 : 10 }

    var expandedSize: CGSize {
        CGSize(
            width: expandedWidth,
            height: topRowBandHeight + Self.expandedContentHeight + (isWeatherExpanded ? Self.weatherExtraHeight : 0)
        )
    }

    /// Largest island size; the panel is laid out for it once.
    var maxExpandedSize: CGSize {
        CGSize(width: expandedWidth, height: topRowBandHeight + Self.expandedContentHeight + Self.weatherExtraHeight)
    }

    var collapsedSize: CGSize {
        let alert = (hasEventAlert || batteryAlert != nil) ? 2 * Self.alertSideWidth : 0
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

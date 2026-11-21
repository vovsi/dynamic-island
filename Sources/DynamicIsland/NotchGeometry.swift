import AppKit

/// Physical notch (camera housing) location on a screen, in global screen coordinates.
struct NotchInfo: Equatable {
    var screenFrame: NSRect
    var size: CGSize
    var midX: CGFloat
    var hasNotch: Bool

    static let fallback = NotchInfo(
        screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
        size: CGSize(width: 190, height: 32),
        midX: 720,
        hasNotch: false
    )
}

enum NotchGeometry {
    /// Prefers the built-in display with a notch; otherwise uses the main screen with a virtual notch.
    static func detect() -> NotchInfo {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return .fallback }
        let frame = screen.frame

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            let minX = frame.minX + left.width
            return NotchInfo(
                screenFrame: frame,
                size: CGSize(width: width, height: screen.safeAreaInsets.top),
                midX: minX + width / 2,
                hasNotch: true
            )
        }

        let menuBarHeight = max(frame.maxY - screen.visibleFrame.maxY, 24)
        return NotchInfo(
            screenFrame: frame,
            size: CGSize(width: 190, height: menuBarHeight),
            midX: frame.midX,
            hasNotch: false
        )
    }
}

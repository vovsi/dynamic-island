import AppKit
import SwiftUI

/// Transparent, borderless panel that sits above the menu bar on every Space.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        // Clicks land on the island itself; the transparent padding around it is left out of the
        // window's hit test by its alpha, so the menu bar beside the notch stays clickable.
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Allow placement over the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosting view that reacts to the very first click without activating the app, and reports the cursor
/// entering and leaving the island.
///
/// The tracking area replaces a global `mouseMoved` monitor: a monitor is woken by every move anywhere
/// on screen, while this only fires when the cursor crosses the island itself.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    var onMouseEntered: () -> Void = {}
    var onMouseExited: () -> Void = {}

    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // The app is an accessory and its panel never becomes key, so the area has to stay active
        // whatever the app's state, dragging included.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onMouseEntered() }
    override func mouseExited(with event: NSEvent) { onMouseExited() }
}

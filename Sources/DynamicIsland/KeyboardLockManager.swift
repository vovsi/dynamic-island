import AppKit
import ApplicationServices

/// Swallows every keyboard event (keys, modifiers, media/brightness keys) so the keyboard can be wiped.
/// Mouse and trackpad events are untouched, so the lock is turned off by clicking the button again.
/// Needs the Accessibility permission; the lock is not restored after a relaunch.
@MainActor
final class KeyboardLockManager: ObservableObject {
    static let shared = KeyboardLockManager()

    @Published private(set) var isLocked = false

    /// Read by the C callback to re-enable the tap after the system disables it.
    nonisolated(unsafe) private static var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// NX_SYSDEFINED: media, volume and brightness keys arrive with subtype NX_SUBTYPE_AUX_CONTROL_BUTTONS.
    private static let systemDefinedType: UInt32 = 14
    private static let auxControlButtonsSubtype: Int16 = 8

    private init() {}

    func toggle() {
        isLocked ? unlock() : lock()
    }

    func lock() {
        guard !isLocked else { return }
        guard Self.isTrusted(prompt: true) else { return }

        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        var mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        mask |= CGEventMask(1) << Self.systemDefinedType

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: nil
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Self.tap = tap
        runLoopSource = source
        isLocked = true
    }

    func unlock() {
        guard isLocked else { return }
        if let tap = Self.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        Self.tap = nil
        runLoopSource = nil
        isLocked = false
    }

    private static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = KeyboardLockManager.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp, .flagsChanged:
            return nil
        default:
            if type.rawValue == systemDefinedType,
               NSEvent(cgEvent: event)?.subtype.rawValue == auxControlButtonsSubtype {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
    }
}

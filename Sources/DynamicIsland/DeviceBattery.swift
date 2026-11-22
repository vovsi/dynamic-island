import AppKit
import SwiftUI

/// Battery level of one device the island watches: a connected Apple/Bluetooth accessory
/// (mouse, keyboard, trackpad, headphones, case), the iPhone, or an EcoFlow power station.
struct DeviceBattery: Identifiable, Equatable {
    enum Kind: Int {
        case phone
        case powerStation
        case mouse
        case keyboard
        case trackpad
        case headphones
        case headphonesCase
        case other

        /// Sort order in the mini dashboard.
        var rank: Int { rawValue }
    }

    /// Lowercased device name; an earbud case gets a `-case` suffix.
    let id: String
    let name: String
    let kind: Kind
    let percent: Int
    /// Reported by the accessory, or inferred from a level that went up since the last reading.
    let isCharging: Bool
    /// Extra line for the hover hint, e.g. the time a power station has left.
    var detail: String? = nil

    var isLow: Bool { percent <= AppSettings.lowBatteryThreshold }
    /// Low and not plugged in: worth warning about.
    var needsCharging: Bool { isLow && !isCharging }

    var tint: Color { isLow ? .red : .green }

    /// Short label for hover hints: "Magic Mouse — 87% · charging".
    var label: String {
        var parts = ["\(name) — \(percent)%"]
        if isCharging { parts.append(tr("charging", "заряжается")) }
        if let detail, !detail.isEmpty { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    static func order(_ a: DeviceBattery, _ b: DeviceBattery) -> Bool {
        if a.kind.rank != b.kind.rank { return a.kind.rank < b.kind.rank }
        if a.percent != b.percent { return a.percent < b.percent }
        return a.name.localizedCompare(b.name) == .orderedAscending
    }
}

// MARK: - Symbols

extension DeviceBattery {
    /// SF Symbol for the device, picking the first name this macOS actually ships.
    var symbol: String {
        switch kind {
        case .phone:
            return Self.symbol(["iphone", "iphone.gen3"])
        case .powerStation:
            return Self.symbol(["powerplug.portable.fill", "minus.plus.batteryblock.fill", "powerplug.fill", "bolt.batteryblock.fill"])
        case .mouse:
            return Self.symbol(["computermouse.fill", "magicmouse.fill", "cursorarrow.click"])
        case .keyboard:
            return Self.symbol(["keyboard.fill", "keyboard"])
        case .trackpad:
            return Self.symbol(["trackpad.fill", "rectangle.and.hand.point.up.left.fill", "rectangle.fill"])
        case .headphones:
            let lowered = name.lowercased()
            if lowered.contains("max") { return Self.symbol(["airpodsmax", "headphones"]) }
            if lowered.contains("pro") { return Self.symbol(["airpodspro", "airpods", "headphones"]) }
            if lowered.contains("airpod") { return Self.symbol(["airpods.gen3", "airpods", "headphones"]) }
            return "headphones"
        case .headphonesCase:
            return Self.symbol(["airpods.chargingcase.fill", "airpodspro.chargingcase.wireless.fill", "rectangle.portrait.fill"])
        case .other:
            return Self.symbol(["wave.3.right.circle.fill", "dot.radiowaves.right"])
        }
    }

    private static func symbol(_ candidates: [String]) -> String {
        candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
            ?? candidates.last
            ?? "circle"
    }
}

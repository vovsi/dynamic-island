import SwiftUI

/// Device icon inside a ring that fills with its battery level: green above the low-battery
/// threshold, red at or below it.
struct DeviceBatteryBadge: View {
    let device: DeviceBattery
    var size: CGFloat = 24

    private var lineWidth: CGFloat { max(size * 0.1, 2) }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: max(CGFloat(device.percent) / 100, 0.02))
                .stroke(device.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: device.symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            if device.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(.green)
                    .shadow(color: .black.opacity(0.8), radius: 1)
                    .offset(x: size * 0.3, y: size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.3), value: device.percent)
    }
}

/// Mini dashboard beside the weather pill: one badge per connected accessory that reports a level.
struct DeviceBatteryBar: View {
    @ObservedObject var store: DeviceBatteryStore
    var size: CGFloat = 24
    var spacing: CGFloat = 5

    /// Lowest levels first, so a device that needs charging is never the one cut off.
    private var shown: [DeviceBattery] {
        Array(store.devices.sorted { $0.percent < $1.percent }.prefix(DeviceBatteryStore.maxShown))
            .sorted(by: DeviceBattery.order)
    }

    /// Width this bar takes, so the weather pill can give up exactly that much room.
    static func width(count: Int, size: CGFloat = 24, spacing: CGFloat = 5) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * size + CGFloat(count - 1) * spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(shown) { device in
                DeviceBatteryBadge(device: device, size: size)
                    .hoverHint(device.label)
            }
        }
    }
}

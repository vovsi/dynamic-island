import SwiftUI

// MARK: - Mock data

struct Metric: Identifiable {
    enum Kind { case currency, count, percent }

    let id: String
    let title: String
    let icon: String
    let tint: Color
    let kind: Kind
    var values: [Double]

    var current: Double { values.last ?? 0 }

    var delta: Double {
        guard let first = values.first, first != 0 else { return 0 }
        return (current - first) / first * 100
    }

    var formattedValue: String {
        switch kind {
        case .currency:
            return current >= 1000
                ? String(format: "$%.1fK", current / 1000)
                : String(format: "$%.0f", current)
        case .count:
            return Int(current).formatted(.number.locale(Locale(identifier: "en_US")))
        case .percent:
            return String(format: "%.2f%%", current)
        }
    }

    var formattedDelta: String {
        String(format: "%@%.1f%%", delta >= 0 ? "+" : "", delta)
    }
}

/// Placeholder metrics with a random walk so the dashboard feels alive.
@MainActor
final class DashboardModel: ObservableObject {
    @Published var metrics: [Metric] = [
        Metric(id: "revenue", title: "Revenue", icon: "dollarsign.circle.fill", tint: .green,
               kind: .currency, values: DashboardModel.seed(base: 12_400, spread: 900)),
        Metric(id: "users", title: "Active Users", icon: "person.2.fill", tint: .blue,
               kind: .count, values: DashboardModel.seed(base: 1_284, spread: 120)),
        Metric(id: "orders", title: "Orders", icon: "cart.fill", tint: .orange,
               kind: .count, values: DashboardModel.seed(base: 342, spread: 30)),
        Metric(id: "conversion", title: "Conversion", icon: "chart.line.uptrend.xyaxis", tint: .purple,
               kind: .percent, values: DashboardModel.seed(base: 3.6, spread: 0.4)),
    ]

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        withAnimation(.smooth(duration: 0.5)) {
            for index in metrics.indices {
                let last = metrics[index].current
                let next = max(0, last * (1 + Double.random(in: -0.035...0.04)))
                metrics[index].values.removeFirst()
                metrics[index].values.append(next)
            }
        }
    }

    private static func seed(base: Double, spread: Double, count: Int = 24) -> [Double] {
        var value = base - spread
        return (0..<count).map { _ in
            value += Double.random(in: -spread / 6...spread / 4)
            return max(0, value)
        }
    }
}

// MARK: - Views

struct DashboardView: View {
    let notchSize: CGSize
    let horizontalInset: CGFloat
    let updateAvailable: Bool
    let onOpenSettings: () -> Void

    @StateObject private var model = DashboardModel()

    var body: some View {
        VStack(spacing: 10) {
            header
            HStack(spacing: 10) {
                ForEach(model.metrics) { metric in
                    MetricCard(metric: metric)
                }
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, 16)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    /// Top row sits beside the camera housing: content left and right of the notch.
    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Dashboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                LiveBadge()
            }

            Spacer(minLength: notchSize.width + 24)

            HStack(spacing: 10) {
                if updateAvailable {
                    Button(action: onOpenSettings) {
                        Label("Update", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                }

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .frame(height: notchSize.height)
    }
}

private struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            PhaseAnimator([1.0, 0.3]) { opacity in
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
            Text("LIVE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green)
        }
    }
}

private struct MetricCard: View {
    let metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: metric.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(metric.tint)
                Text(metric.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Text(metric.formattedValue)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text(metric.formattedDelta)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(metric.delta >= 0 ? Color.green : Color.red)

            Sparkline(values: metric.values, tint: metric.tint)
                .frame(height: 26)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)], startPoint: .top, endPoint: .bottom))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        let range = max(hi - lo, .ulpOfOne)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - CGFloat((value - lo) / range) * (size.height - 2) - 1
            )
        }
    }
}

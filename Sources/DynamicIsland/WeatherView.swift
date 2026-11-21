import SwiftUI

/// Small weather pill beside the notch (always visible); tapping it opens `WeatherForecastPanel` below.
struct WeatherPill: View {
    @ObservedObject var weather: WeatherStore
    let isActive: Bool
    let height: CGFloat
    /// Room left of the notch; the pill must never reach under the camera housing.
    let maxWidth: CGFloat
    let onToggle: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        compact
            .frame(height: height)
            .background(Capsule().fill(Color(white: isActive ? 0.18 : 0.1)))
            .contentShape(Capsule())
            .onTapGesture {
                weather.current == nil ? onOpenSettings() : onToggle()
            }
            .help(weather.current == nil ? "Weather settings" : "")
    }

    // MARK: - Compact

    private var compact: some View {
        HStack(spacing: 6) {
            if let current = weather.current {
                Image(systemName: WeatherCondition.symbol(code: current.code, isDay: current.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 12))
                Text(Self.degrees(current.temperature))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if let city = weather.city {
                    Text(city)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            } else {
                Image(systemName: weather.status == .needsLocation ? "location.slash" : "cloud")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(weather.status == .loading ? "Weather…" : "Set location")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: maxWidth, maxHeight: .infinity, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}

/// Current conditions and the 7-day forecast, shown below the notch while the pill is active.
struct WeatherForecastPanel: View {
    @ObservedObject var weather: WeatherStore
    let onToggle: () -> Void

    var body: some View {
        expanded
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.12))
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture(perform: onToggle)
    }

    // MARK: - Expanded

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let current = weather.current {
                HStack(spacing: 10) {
                    Image(systemName: WeatherCondition.symbol(code: current.code, isDay: current.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 24))
                    Text(WeatherPill.degrees(current.temperature))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(weather.city ?? "")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(WeatherCondition.title(code: current.code))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(details(current))
                            .font(.system(size: 9.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)

                let low = weather.days.map(\.min).min() ?? 0
                let high = weather.days.map(\.max).max() ?? 0
                VStack(spacing: 2) {
                    ForEach(Array(weather.days.enumerated()), id: \.element.id) { index, day in
                        DayRow(day: day, isToday: index == 0, weekLow: low, weekHigh: high)
                    }
                }
            }
        }
        .padding(10)
    }

    private func details(_ current: WeatherStore.Current) -> String {
        let wind = String(format: "%.0f", current.windSpeed) + (weather.usesMetric ? " m/s" : " mph")
        return "Feels \(WeatherPill.degrees(current.apparentTemperature)) · \(wind) · \(Int(current.humidity))%"
    }
}

private struct DayRow: View {
    let day: WeatherStore.Day
    let isToday: Bool
    let weekLow: Double
    let weekHigh: Double

    private static let weekday: Date.FormatStyle = {
        var style = Date.FormatStyle().weekday(.abbreviated)
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return style
    }()

    var body: some View {
        HStack(spacing: 8) {
            Text(isToday ? "Today" : day.date.formatted(Self.weekday))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(isToday ? 1 : 0.75))
                .frame(width: 42, alignment: .leading)
            Image(systemName: WeatherCondition.symbol(code: day.code))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 11))
                .frame(width: 18)
            Text(day.precipitationChance.map { $0 >= 20 ? "\($0)%" : "" } ?? "")
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.cyan)
                .frame(width: 28, alignment: .leading)
            Spacer(minLength: 0)
            Text(WeatherPill.degrees(day.min))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 28, alignment: .trailing)
            TemperatureBar(low: day.min, high: day.max, weekLow: weekLow, weekHigh: weekHigh)
                .frame(width: 60, height: 4)
            Text(WeatherPill.degrees(day.max))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 28, alignment: .trailing)
        }
        .frame(height: 17)
    }
}

private struct TemperatureBar: View {
    let low: Double
    let high: Double
    let weekLow: Double
    let weekHigh: Double

    var body: some View {
        GeometryReader { geo in
            let span = max(weekHigh - weekLow, 1)
            let start = CGFloat((low - weekLow) / span) * geo.size.width
            let width = max(CGFloat((high - low) / span) * geo.size.width, geo.size.height)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: width)
                    .offset(x: min(start, geo.size.width - width))
            }
        }
    }
}

/// Union of the weather pill and forecast panel frames in the island's coordinate space,
/// used to close the forecast once the cursor leaves both.
struct WeatherFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = value.union(nextValue()) }
}

extension View {
    func reportsWeatherFrame() -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: WeatherFrameKey.self, value: geo.frame(in: .named(IslandRootView.coordinateSpace)))
        })
    }
}

import SwiftUI

/// Expanded island: weather, today's events, today's schedule (Google account calendars), settings button.
struct DashboardView: View {
    let notchSize: CGSize
    let horizontalInset: CGFloat
    let updateAvailable: Bool
    let isWeatherExpanded: Bool
    let isKeepAwakePickerOpen: Bool
    let onOpenSettings: () -> Void
    let onWeatherToggle: () -> Void
    let onKeepAwakePickerToggle: () -> Void
    let onWeatherFrame: (CGRect) -> Void

    @ObservedObject private var store = CalendarStore.shared
    @ObservedObject private var keepAwake = KeepAwakeManager.shared
    @ObservedObject private var keyboardLock = KeyboardLockManager.shared

    private var weatherHeight: CGFloat { max(notchSize.height - 8, 20) }
    private let cardSpacing: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: cardSpacing) {
                header
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack(alignment: .top, spacing: cardSpacing) {
                        EventsCard(store: store, now: context.date, onOpenSettings: onOpenSettings)
                        ScheduleCard(store: store, now: context.date, onOpenSettings: onOpenSettings)
                    }
                }
            }

            // Pill stays left of the notch; the forecast covers the Events card below the notch
            // (never under the camera housing, which screenshots do not show).
            WeatherPill(
                weather: WeatherStore.shared,
                isActive: isWeatherExpanded,
                height: weatherHeight,
                maxWidth: max((IslandViewModel.expandedWidth - notchSize.width) / 2 - horizontalInset - 8, 60),
                onToggle: onWeatherToggle,
                onOpenSettings: onOpenSettings
            )
            .reportsWeatherFrame()
            .padding(.top, (notchSize.height - weatherHeight) / 2)

            if isWeatherExpanded {
                WeatherForecastPanel(weather: WeatherStore.shared, onToggle: onWeatherToggle)
                    .frame(width: (IslandViewModel.expandedWidth - 2 * horizontalInset - cardSpacing) / 2)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .reportsWeatherFrame()
                    .padding(.top, notchSize.height + cardSpacing)
                    .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
            }

            if isKeepAwakePickerOpen {
                KeepAwakePicker(manager: keepAwake, onClose: onKeepAwakePickerToggle)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(.top, notchSize.height + 4)
                    .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .onPreferenceChange(WeatherFrameKey.self) { frame in
            MainActor.assumeIsolated { onWeatherFrame(frame) }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, 16)
    }

    /// Top row sits beside the camera housing.
    private var header: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Button(action: keyboardLock.toggle) {
                TouchpadIcon(color: keyboardLock.isLocked ? .orange : .white.opacity(0.75))
                    .frame(width: 13, height: 11)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(keyboardLock.isLocked ? 0.2 : 0.1)))
            }
            .buttonStyle(.plain)
            .hoverHint(tr("Keyboard cleaning", "Очистка клавиатуры"))
            if let end = keepAwake.endDate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(KeepAwakeManager.remainingText(until: end, now: context.date))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .fixedSize()
                }
                .hoverHint(tr("Anti-sleep is on", "Антисон включён"))
            }
            Button(action: onKeepAwakePickerToggle) {
                TabletIcon(color: keepAwake.isActive ? .orange : .white.opacity(0.75))
                    .frame(width: 11, height: 11)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(isKeepAwakePickerOpen ? 0.2 : 0.1)))
            }
            .buttonStyle(.plain)
            .hoverHint(tr("Anti-sleep", "Антисон"))
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(0.1)))
                    .overlay(alignment: .topTrailing) {
                        if updateAvailable {
                            Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                        }
                    }
            }
            .buttonStyle(.plain)
            .hoverHint(tr("Settings", "Настройки"))
        }
        .frame(height: notchSize.height)
        .zIndex(1) // hint bubbles hang over the cards below
    }
}

// MARK: - Keyboard lock

/// Touchpad with two buttons along its bottom edge, stroked as one path so overlaps keep an even tint.
private struct TouchpadIcon: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let line = max(w * 0.11, 1.2)
            let rect = CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: line / 2, dy: line / 2)
            let buttonsTop = rect.minY + rect.height * 0.66
            Path { path in
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: w * 0.18, height: w * 0.18), style: .continuous)
                path.move(to: CGPoint(x: rect.minX, y: buttonsTop))
                path.addLine(to: CGPoint(x: rect.maxX, y: buttonsTop))
                path.move(to: CGPoint(x: rect.midX, y: buttonsTop))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
            .stroke(color, lineWidth: line)
        }
    }
}

// MARK: - Keep awake

/// Round tablet with a score line across it.
private struct TabletIcon: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle().fill(color)
                Rectangle()
                    .frame(width: proxy.size.width * 1.2, height: max(proxy.size.width * 0.14, 1.2))
                    .rotationEffect(.degrees(-45))
                    .blendMode(.destinationOut)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .compositingGroup()
    }
}

/// Hour presets for the keep-awake mode, shown under the pill button.
private struct KeepAwakePicker: View {
    @ObservedObject var manager: KeepAwakeManager
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TabletIcon(color: .orange)
                    .frame(width: 10, height: 10)
                Text(tr("Keep awake for", "Не спать в течение"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 8)
                if manager.isActive {
                    chip(tr("Turn off", "Выключить"), tint: .red) {
                        manager.stop()
                        onClose()
                    }
                }
            }
            HStack(spacing: 5) {
                ForEach(KeepAwakeManager.presets, id: \.self) { hours in
                    chip(tr("\(hours) h", "\(hours) ч"), tint: .white) {
                        manager.activate(hours: hours)
                        onClose()
                    }
                }
            }
        }
        .padding(10)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.12))
                .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {}
    }

    private func chip(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cards

private struct EventsCard: View {
    @ObservedObject var store: CalendarStore
    let now: Date
    let onOpenSettings: () -> Void

    var body: some View {
        Card(title: CalendarBlock.events.title, icon: "calendar", tint: .red, onTap: { openApp(bundleID: "com.apple.iCal") }) {
            if let placeholder = AccessPlaceholder(store: store, onOpenSettings: onOpenSettings) {
                placeholder
            } else if store.events.isEmpty {
                Placeholder(text: tr("No events today.", "Сегодня событий нет."))
            } else {
                EventList(events: store.events, now: now) { event in
                    EventRow(event: event, now: now)
                }
            }
        }
    }
}

private struct ScheduleCard: View {
    @ObservedObject var store: CalendarStore
    let now: Date
    let onOpenSettings: () -> Void

    var body: some View {
        Card(title: CalendarBlock.schedule.title, icon: "clock", tint: .blue, onTap: { openApp(bundleID: "com.apple.reminders") }) {
            if let placeholder = AccessPlaceholder(store: store, onOpenSettings: onOpenSettings) {
                placeholder
            } else if store.schedule.isEmpty {
                if store.hasScheduleCalendars {
                    Placeholder(text: tr("Nothing scheduled today.", "На сегодня ничего не запланировано."))
                } else {
                    Placeholder(text: tr("Connect your Google account.", "Подключите аккаунт Google."), action: tr("Connect", "Подключить"), perform: store.openInternetAccounts)
                }
            } else {
                let next = store.schedule.first { !$0.isAllDay && $0.start > now }?.id
                EventList(events: store.schedule, now: now) { event in
                    ScheduleRow(event: event, now: now, isNext: event.id == next)
                }
            }
        }
    }
}

/// Shown instead of a card's content while calendar access is not granted.
private struct AccessPlaceholder: View {
    @ObservedObject var store: CalendarStore
    let onOpenSettings: () -> Void

    init?(store: CalendarStore, onOpenSettings: @escaping () -> Void) {
        guard store.access != .ready else { return nil }
        self.store = store
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        if store.access == .notDetermined {
            Placeholder(text: tr("Calendar access is required.", "Нужен доступ к Календарю."), action: tr("Allow Access", "Разрешить")) {
                Task { await store.requestAccess() }
            }
        } else {
            Placeholder(text: tr("Calendar access is denied.", "Доступ к Календарю запрещён."), action: tr("Open Settings", "Открыть настройки"), perform: store.openPrivacySettings)
        }
    }
}

private struct Card<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let onTap: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 4)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onTap)
    }
}

private func openApp(bundleID: String) {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
}

private struct Placeholder: View {
    let text: String
    var action: String?
    var perform: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(3)
            if let action {
                Button(action: perform) {
                    Text(action)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.14)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Scrollable list that starts at the first event that has not ended yet.
private struct EventList<Row: View>: View {
    let events: [DayEvent]
    let now: Date
    @ViewBuilder let row: (DayEvent) -> Row

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(events) { row($0).id($0.id) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                if let focus = events.first(where: { !$0.isAllDay && !$0.hasEnded(at: now) }) {
                    proxy.scrollTo(focus.id, anchor: .top)
                }
            }
        }
    }
}

// MARK: - Rows

private func timeText(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L10n.locale))
}

private struct EventRow: View {
    let event: DayEvent
    let now: Date

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 14)
            Text(event.isAllDay ? tr("All day", "Весь день") : "\(timeText(event.start))–\(timeText(event.end))")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .fixedSize()
            Text(event.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .opacity(event.hasEnded(at: now) ? 0.4 : 1)
    }
}

private struct ScheduleRow: View {
    let event: DayEvent
    let now: Date
    let isNext: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(event.isAllDay ? tr("All day", "Весь день") : timeText(event.start))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 40, alignment: .leading)
                .fixedSize()
            marker
            Text(event.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 4)
            badge
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isOngoing ? Color.green.opacity(0.14) : .clear)
        )
        .opacity(!event.isAllDay && event.hasEnded(at: now) ? 0.4 : 1)
    }

    private var isOngoing: Bool { !event.isAllDay && event.isOngoing(at: now) }

    /// Calendar events get a color bar, reminders an empty checkbox circle.
    @ViewBuilder
    private var marker: some View {
        if event.isReminder {
            Image(systemName: "circle")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(event.color)
                .frame(width: 9)
        } else {
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 14)
                .frame(width: 9)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if isOngoing {
            Text(tr("Now", "Сейчас"))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green)
        } else if isNext {
            Text(Self.relative(from: now, to: event.start))
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
        } else if !event.isAllDay && !event.isReminder {
            Text(timeText(event.end))
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    static func relative(from now: Date, to date: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 { return tr("in \(minutes) min", "через \(minutes) мин") }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0
            ? tr("in \(hours) h", "через \(hours) ч")
            : tr("in \(hours) h \(rest) min", "через \(hours) ч \(rest) мин")
    }
}

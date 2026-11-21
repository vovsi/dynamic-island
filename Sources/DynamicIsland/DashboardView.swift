import SwiftUI

/// Expanded island: today's events, today's schedule (Google account calendars), settings button.
struct DashboardView: View {
    let notchSize: CGSize
    let horizontalInset: CGFloat
    let updateAvailable: Bool
    let onOpenSettings: () -> Void

    @ObservedObject private var store = CalendarStore.shared

    var body: some View {
        VStack(spacing: 10) {
            header
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(alignment: .top, spacing: 10) {
                    EventsCard(store: store, now: context.date, onOpenSettings: onOpenSettings)
                    ScheduleCard(store: store, now: context.date, onOpenSettings: onOpenSettings)
                }
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, 16)
    }

    /// Top row sits beside the camera housing.
    private var header: some View {
        HStack {
            Spacer(minLength: 0)
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
            .help(updateAvailable ? "Settings — update available" : "Settings")
        }
        .frame(height: notchSize.height)
    }
}

// MARK: - Cards

private struct EventsCard: View {
    @ObservedObject var store: CalendarStore
    let now: Date
    let onOpenSettings: () -> Void

    var body: some View {
        Card(title: "Events", icon: "calendar", tint: .red, trailing: now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) {
            if let placeholder = AccessPlaceholder(store: store, onOpenSettings: onOpenSettings) {
                placeholder
            } else if store.events.isEmpty {
                Placeholder(text: "No events today.")
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
        Card(title: "Schedule", icon: "clock", tint: .blue, trailing: nil) {
            if let placeholder = AccessPlaceholder(store: store, onOpenSettings: onOpenSettings) {
                placeholder
            } else if !store.hasScheduleCalendars {
                Placeholder(text: "Connect your Google account.", action: "Connect", perform: store.openInternetAccounts)
            } else if store.schedule.isEmpty {
                Placeholder(text: "Nothing scheduled today.")
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
            Placeholder(text: "Calendar access is required.", action: "Allow Access") {
                Task { await store.requestAccess() }
            }
        } else {
            Placeholder(text: "Calendar access is denied.", action: "Open Settings", perform: store.openPrivacySettings)
        }
    }
}

private struct Card<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let trailing: String?
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
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
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
    }
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
    date.formatted(date: .omitted, time: .shortened)
}

private struct EventRow: View {
    let event: DayEvent
    let now: Date

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 14)
            Text(event.isAllDay ? "All day" : "\(timeText(event.start))–\(timeText(event.end))")
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
            Text(event.isAllDay ? "All day" : timeText(event.start))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 40, alignment: .leading)
                .fixedSize()
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 14)
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

    @ViewBuilder
    private var badge: some View {
        if isOngoing {
            Text("Now")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.green)
        } else if isNext {
            Text(Self.relative(from: now, to: event.start))
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
        } else if !event.isAllDay {
            Text(timeText(event.end))
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    static func relative(from now: Date, to date: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
    }
}

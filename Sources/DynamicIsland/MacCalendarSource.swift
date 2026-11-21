import EventKit
import SwiftUI

/// Calendars and events from macOS (EventKit): local, iCloud and accounts added in
/// System Settings → Internet Accounts (Google etc.).
@MainActor
final class MacCalendarSource {
    enum Access {
        case granted
        case notDetermined
        case denied
    }

    struct CalendarInfo {
        let id: String
        let title: String
        let accountID: String
        let account: String
        let color: Color
        /// Google (or another third-party CalDAV) account — goes to the schedule by default.
        let isRemoteAccount: Bool
    }

    private var store = EKEventStore()

    var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    var remindersAccess: Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestRemindersAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        if granted { store = EKEventStore() }
        return granted
    }

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        // A fresh store picks up calendars that became visible after the grant.
        if granted { store = EKEventStore() }
        return granted
    }

    /// Re-creates the store so accounts added in System Settings show up (a long-lived store keeps
    /// its initial source list), then asks EventKit to sync them; changes arrive via `EKEventStoreChanged`.
    func reloadSources() {
        store = EKEventStore()
        store.refreshSourcesIfNecessary()
    }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event).map { calendar in
            let source = calendar.source
            return CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                accountID: source?.sourceIdentifier ?? "",
                account: source?.title ?? "",
                color: Color(nsColor: calendar.color),
                isRemoteAccount: source.map(Self.isRemoteAccount) ?? false
            )
        }
    }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [DayEvent] {
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled && !Self.isDeclined($0) }
            .map {
                DayEvent(
                    id: "\($0.calendarItemIdentifier)|\($0.startDate.timeIntervalSince1970)",
                    calendarID: $0.calendar.calendarIdentifier,
                    title: $0.title?.isEmpty == false ? $0.title : tr("(No title)", "(Без названия)"),
                    start: $0.startDate,
                    end: $0.endDate,
                    isAllDay: $0.isAllDay,
                    color: Color(nsColor: $0.calendar.color)
                )
            }
            .sorted(by: DayEvent.order)
    }

    /// Incomplete reminders due within [start, end), from all reminder lists.
    func reminders(from start: Date, to end: Date) async -> [DayEvent] {
        guard remindersAccess == .granted else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: nil)
        return await Self.fetchReminders(store: store, predicate: predicate)
    }

    private nonisolated static func fetchReminders(store: EKEventStore, predicate: NSPredicate) async -> [DayEvent] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).compactMap(dayEvent))
            }
        }
    }

    private nonisolated static func dayEvent(_ reminder: EKReminder) -> DayEvent? {
        guard let components = reminder.dueDateComponents,
              let due = Calendar.current.date(from: components) else { return nil }
        let isAllDay = components.hour == nil
        let start = isAllDay ? Calendar.current.startOfDay(for: due) : due
        return DayEvent(
            id: "reminder|\(reminder.calendarItemIdentifier)",
            calendarID: reminder.calendar.calendarIdentifier,
            title: reminder.title?.isEmpty == false ? reminder.title : tr("(No title)", "(Без названия)"),
            start: start,
            end: isAllDay ? Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start : start,
            isAllDay: isAllDay,
            color: Color(nsColor: reminder.calendar.color),
            isReminder: true
        )
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    private static func isRemoteAccount(_ source: EKSource) -> Bool {
        guard source.sourceType == .calDAV else { return false }
        let title = source.title.lowercased()
        if title.contains("google") || title.hasSuffix("gmail.com") || title.hasSuffix("googlemail.com") {
            return true
        }
        let iCloud = title == "icloud" || ["icloud.com", "me.com", "mac.com"].contains { title.hasSuffix($0) }
        return !iCloud
    }
}

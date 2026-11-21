import EventKit
import SwiftUI

/// Events from the macOS Calendar app (EventKit).
@MainActor
final class MacCalendarSource {
    enum Access {
        case granted
        case notDetermined
        case denied
    }

    private var store = EKEventStore()

    var access: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        // A fresh store picks up calendars that became visible after the grant.
        if granted { store = EKEventStore() }
        return granted
    }

    func calendarOptions(excluded: Set<String>) -> [CalendarOption] {
        store.calendars(for: .event)
            .map {
                CalendarOption(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    group: $0.source?.title ?? "",
                    color: Color(nsColor: $0.color),
                    isEnabled: !excluded.contains($0.calendarIdentifier)
                )
            }
            .sorted { ($0.group, $0.title) < ($1.group, $1.title) }
    }

    func events(from start: Date, to end: Date, excluded: Set<String>) -> [DayEvent] {
        let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map {
                DayEvent(
                    id: "\($0.calendarItemIdentifier)|\($0.startDate.timeIntervalSince1970)",
                    title: $0.title?.isEmpty == false ? $0.title : "(No title)",
                    start: $0.startDate,
                    end: $0.endDate,
                    isAllDay: $0.isAllDay,
                    color: Color(nsColor: $0.calendar.color)
                )
            }
            .sorted(by: DayEvent.order)
    }
}

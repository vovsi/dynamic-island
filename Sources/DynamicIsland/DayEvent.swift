import SwiftUI

struct DayEvent: Identifiable, Equatable {
    let id: String
    let calendarID: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    /// Item from the Reminders app (zero-length at its due time) rather than a calendar event.
    var isReminder = false

    func isOngoing(at date: Date) -> Bool { start <= date && date < end }
    func hasEnded(at date: Date) -> Bool { end <= date }

    /// All-day events first, then by start time.
    static func order(_ a: DayEvent, _ b: DayEvent) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.start != b.start { return a.start < b.start }
        return a.title.localizedCompare(b.title) == .orderedAscending
    }

    static func todayRange(now: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }
}

/// Island block a calendar is shown in.
enum CalendarBlock: String, CaseIterable, Identifiable {
    case events
    case schedule
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .events: return tr("Events", "События")
        case .schedule: return tr("Schedule", "Расписание")
        case .hidden: return tr("Hidden", "Скрыт")
        }
    }
}

struct CalendarOption: Identifiable, Equatable {
    let id: String
    let title: String
    let accountID: String
    let account: String
    let color: Color
    var block: CalendarBlock
}

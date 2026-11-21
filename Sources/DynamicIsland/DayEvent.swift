import SwiftUI

struct DayEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color

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

struct CalendarOption: Identifiable, Equatable {
    let id: String
    let title: String
    let group: String
    let color: Color
    var isEnabled: Bool
}

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

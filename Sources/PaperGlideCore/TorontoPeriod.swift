import Foundation

/// Civil day and Monday-start week in `America/Toronto`.
///
/// Day keys are the calendar date. Week keys are the Monday of that civil
/// week. Both use `Calendar` day math, not 24-hour steps, so the spring-forward
/// gap and the fall-back repeated hour stay on the same Toronto date.
public enum TorontoGrouping: String, Codable, Equatable {
    case day
    case week
    case month
}

public enum TorontoPeriod {
    public static let identifier = "America/Toronto"

    public static func dayKey(for date: Date) -> String {
        let parts = calendar().dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Monday of the Toronto civil week that contains `date`, as `yyyy-MM-dd`.
    public static func weekKey(for date: Date) -> String {
        let calendar = calendar()
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let daysFromMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: start) ?? start
        return dayKey(for: monday)
    }

    /// `yyyy-MM` for the Toronto civil month.
    public static func monthKey(for date: Date) -> String {
        let parts = calendar().dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// First civil day of the Toronto month, as `yyyy-MM-dd`.
    public static func monthStartKey(for date: Date) -> String {
        monthKey(for: date) + "-01"
    }

    public static func bucketKey(for date: Date, grouping: TorontoGrouping) -> String {
        switch grouping {
        case .day: return dayKey(for: date)
        case .week: return weekKey(for: date)
        case .month: return monthStartKey(for: date)
        }
    }

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

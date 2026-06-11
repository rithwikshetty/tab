import Foundation

/// `expense_date` is a calendar date, not an instant. Storage convention:
/// the user's local calendar day anchored at 12:00 UTC — the same instant the
/// pull-side parser produces for a `yyyy-MM-dd` column value. Anchoring at
/// save time is what keeps "the day the user picked" stable across push,
/// pull, and timezone changes; serializing the anchor in UTC is then exact.
enum ExpenseDates {
    /// UTC-noon instant for the calendar day (in `calendar`) containing `date`.
    static func utcNoonAnchor(forLocalDay date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 12
        return utcCalendar.date(from: components) ?? date
    }

    /// `yyyy-MM-dd` for an anchored date, evaluated in UTC.
    static func serialized(_ anchored: Date) -> String {
        serializer.string(from: anchored)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let serializer: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

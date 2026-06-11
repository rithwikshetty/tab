import Foundation
import Testing
@testable import Tab

/// `expense_date` is a calendar date, not an instant. The contract: whatever
/// day the user saw in the picker is the day that gets stored, pushed,
/// pulled, and displayed — regardless of their timezone or time of day.
@Suite("Expense dates")
struct ExpenseDatesTests {
    private func calendar(_ tzID: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tzID)!
        return c
    }

    private func instant(_ y: Int, _ m: Int, _ d: Int, hour: Int, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    @Test("evening expense west of UTC keeps the user's calendar day")
    func eveningWestOfUTC() {
        // 6pm June 10 in Los Angeles is already June 11 in UTC — the bug case.
        let cal = calendar("America/Los_Angeles")
        let picked = instant(2026, 6, 10, hour: 18, in: cal)
        let anchored = ExpenseDates.utcNoonAnchor(forLocalDay: picked, calendar: cal)
        #expect(ExpenseDates.serialized(anchored) == "2026-06-10")
    }

    @Test("morning expense east of UTC keeps the user's calendar day")
    func morningEastOfUTC() {
        // 8am June 10 in Sydney is June 9 in UTC.
        let cal = calendar("Australia/Sydney")
        let picked = instant(2026, 6, 10, hour: 8, in: cal)
        let anchored = ExpenseDates.utcNoonAnchor(forLocalDay: picked, calendar: cal)
        #expect(ExpenseDates.serialized(anchored) == "2026-06-10")
    }

    @Test("anchoring is idempotent — re-saving an already-anchored date keeps the day")
    func anchorIdempotent() {
        let cal = calendar("America/Los_Angeles")
        let picked = instant(2026, 6, 10, hour: 18, in: cal)
        let once = ExpenseDates.utcNoonAnchor(forLocalDay: picked, calendar: cal)
        let twice = ExpenseDates.utcNoonAnchor(forLocalDay: once, calendar: cal)
        #expect(once == twice)
    }

    @Test("anchor round-trips through the pull-side parser")
    func anchorMatchesPullConvention() {
        let cal = calendar("Europe/Lisbon")
        let picked = instant(2026, 12, 31, hour: 23, in: cal)
        let anchored = ExpenseDates.utcNoonAnchor(forLocalDay: picked, calendar: cal)
        // Pull parses yyyy-MM-dd at UTC noon; the anchor must already be that instant.
        var utc = Calendar(identifier: .iso8601)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour], from: anchored)
        #expect(parts.year == 2026 && parts.month == 12 && parts.day == 31)
        #expect(parts.hour == 12)
    }
}

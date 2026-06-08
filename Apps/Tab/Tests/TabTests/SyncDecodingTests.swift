import Foundation
import Testing
@testable import Tab

/// Regression coverage for the sync pull aborting on `expenses.expense_date`.
///
/// `expense_date` is a Postgres `date`, so PostgREST serialises it as a bare
/// `yyyy-MM-dd` with no time. The Supabase client's default JSON decoder parses
/// dates as full ISO-8601 timestamps only and throws on a date-only string. That
/// made `pullExpenses()` throw and aborted the whole pull *after* trips had synced
/// — the user saw trips but none of their expenses, payments, splits, or settlements.
@Suite struct SyncDecodingTests {

    /// A decoder configured exactly like the Supabase client's default: its custom
    /// date strategy parses full ISO-8601 timestamps and rejects bare dates. Decoding
    /// `ExpenseDTO` through this is what reproduces the production failure.
    private func supabaseLikeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: .iso8601.year().month().day()
                .dateTimeSeparator(.standard).time(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(string, strategy: .iso8601.year().month().day()
                .dateTimeSeparator(.standard).time(includingFractionalSeconds: false)) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(string)"
            )
        }
        return decoder
    }

    private let expensesJSON = """
    [
      {
        "id": "a2000000-0000-4000-8000-000000000001",
        "trip_id": "a0000000-0000-4000-8000-000000000001",
        "amount": 96000.00000000,
        "currency": "JPY",
        "category_id": "00000003-0000-0000-0000-000000000000",
        "description": "Shinjuku hotel",
        "expense_date": "2026-05-09",
        "receipt_storage_path": null,
        "payment_method": "card",
        "created_by": "654067a4-75cc-4c76-953f-7059cb91fc91",
        "last_edited_by": null,
        "created_at": "2026-06-05T07:40:11.940977+00:00",
        "updated_at": "2026-06-05T07:40:11.940995+00:00",
        "deleted_at": null,
        "write_id": "11111111-2222-3333-4444-555555555555"
      }
    ]
    """

    @Test func decodesExpenseRowWithBareDateColumn() throws {
        let rows = try supabaseLikeDecoder().decode([ExpenseDTO].self, from: Data(expensesJSON.utf8))
        #expect(rows.count == 1)
        let dto = try #require(rows.first)
        #expect(dto.currency == "JPY")
        #expect(dto.amount == Decimal(string: "96000.00000000"))
        #expect(dto.deletedAt == nil)
        #expect(dto.createdAt <= dto.updatedAt)

        // expense_date resolves to UTC noon of the stated calendar day so local
        // date-only formatters west of UTC do not show the previous day.
        var utc = Calendar(identifier: .iso8601)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour], from: dto.expenseDate)
        #expect(parts.year == 2026)
        #expect(parts.month == 5)
        #expect(parts.day == 9)
        #expect(parts.hour == 12)

        let westOfUTCFormatter = DateFormatter()
        westOfUTCFormatter.calendar = Calendar(identifier: .iso8601)
        westOfUTCFormatter.dateFormat = "yyyy-MM-dd"
        westOfUTCFormatter.locale = Locale(identifier: "en_US_POSIX")
        westOfUTCFormatter.timeZone = TimeZone(secondsFromGMT: -8 * 60 * 60)
        #expect(westOfUTCFormatter.string(from: dto.expenseDate) == "2026-05-09")
    }

    @Test func defaultDateStrategyRejectsBareDate() {
        // Guardrail: confirms the reproduction decoder genuinely fails on a date-only
        // string, so the decode above succeeds because of ExpenseDTO's own parsing.
        #expect(throws: (any Error).self) {
            _ = try supabaseLikeDecoder().decode(Date.self, from: Data("\"2026-05-09\"".utf8))
        }
    }

    @Test func decodesVisibleProfileWithoutActivityCursor() throws {
        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000002",
            "display_name": "Bob",
            "avatar_url": null,
            "created_at": "2026-06-05T07:40:11.940977+00:00",
            "updated_at": "2026-06-05T07:40:11.940995+00:00",
            "write_id": "11111111-2222-3333-4444-555555555555"
          }
        ]
        """

        let rows = try supabaseLikeDecoder().decode([ProfileDTO].self, from: Data(json.utf8))

        let dto = try #require(rows.first)
        #expect(dto.displayName == "Bob")
        #expect(dto.activityLastSeenAt == nil)
    }
}

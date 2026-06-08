import Foundation
import Testing
@testable import Tab

@MainActor
@Suite("Activity presenter")
struct ActivityPresenterTests {
    private let currentUser = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let otherUser = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let tripID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @Test("feed shows your own activity without marking it unread")
    func feedShowsOwnActivityWithoutMarkingItUnread() throws {
        let seenAt = Date(timeIntervalSince1970: 1_800_000_000)
        let ownExpenseID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
        let otherExpenseID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!

        let sections = ActivityPresenter.sections(
            from: [
                activity(
                    actorID: currentUser,
                    action: "expense_created",
                    entityID: ownExpenseID,
                    timestamp: seenAt.addingTimeInterval(120),
                    snapshot: ["actor_name": "You", "trip_name": "Lisbon", "description": "Coffee", "amount": "6.00", "currency": "EUR"]
                ),
                activity(
                    actorID: otherUser,
                    action: "expense_created",
                    entityID: otherExpenseID,
                    timestamp: seenAt.addingTimeInterval(60),
                    snapshot: ["actor_name": "Bo", "trip_name": "Lisbon", "description": "Dinner", "amount": "40.00", "currency": "EUR"]
                ),
            ],
            currentUserID: currentUser,
            lastSeenAt: seenAt,
            mutedTripIDs: [],
            myTripPersonIDs: [],
            calendar: fixedCalendar,
            now: seenAt
        )

        let rows = sections.flatMap(\.rows)
        #expect(rows.map(\.target) == [
            .expense(tripID: tripID, expenseID: ownExpenseID),
            .expense(tripID: tripID, expenseID: otherExpenseID),
        ])
        #expect(rows.map(\.isUnread) == [false, true])
    }

    @Test("unread count still excludes your own activity")
    func unreadCountStillExcludesOwnActivity() {
        let seenAt = Date(timeIntervalSince1970: 1_800_000_000)

        let count = ActivityPresenter.unreadCount(
            from: [
                activity(
                    actorID: currentUser,
                    action: "settlement_created",
                    entityID: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
                    timestamp: seenAt.addingTimeInterval(120),
                    snapshot: ["actor_name": "You", "trip_name": "Lisbon", "from_name": "You", "to_name": "Bo", "amount": "10.00", "currency": "EUR"]
                ),
                activity(
                    actorID: otherUser,
                    action: "settlement_created",
                    entityID: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!,
                    timestamp: seenAt.addingTimeInterval(60),
                    snapshot: ["actor_name": "Bo", "trip_name": "Lisbon", "from_name": "Bo", "to_name": "You", "amount": "5.00", "currency": "EUR"]
                ),
            ],
            currentUserID: currentUser,
            lastSeenAt: seenAt,
            mutedTripIDs: []
        )

        #expect(count == 1)
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func activity(
        actorID: UUID,
        action: String,
        entityID: UUID,
        timestamp: Date,
        snapshot: [String: String]
    ) -> ActivityEntity {
        ActivityEntity(
            id: UUID(),
            tripID: tripID,
            actorID: actorID,
            action: action,
            entityType: "expense",
            entityID: entityID,
            timestamp: timestamp,
            snapshotData: try? JSONEncoder().encode(snapshot)
        )
    }
}

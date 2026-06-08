import Foundation
import Testing
@testable import Tab

@Suite("Activity navigation")
struct ActivityNavigationTests {
    private let tripID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let expenseID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let settlementID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!

    @Test("openable expense activity goes straight to expense detail")
    func openableExpenseActivityGoesStraightToExpenseDetail() {
        let stack = ActivityNavigation.stack(
            for: .expense(tripID: tripID, expenseID: expenseID),
            expenseIsOpenable: { $0 == expenseID },
            settlementIsOpenable: { _ in false }
        )

        #expect(stack == [.expense(expenseID)])
    }

    @Test("missing expense activity falls back to the trip")
    func missingExpenseActivityFallsBackToTrip() {
        let stack = ActivityNavigation.stack(
            for: .expense(tripID: tripID, expenseID: expenseID),
            expenseIsOpenable: { _ in false },
            settlementIsOpenable: { _ in false }
        )

        #expect(stack == [.trip(tripID)])
    }

    @Test("openable settlement activity goes straight to settlement detail")
    func openableSettlementActivityGoesStraightToSettlementDetail() {
        let stack = ActivityNavigation.stack(
            for: .settlement(tripID: tripID, settlementID: settlementID),
            expenseIsOpenable: { _ in false },
            settlementIsOpenable: { $0 == settlementID }
        )

        #expect(stack == [.settlement(settlementID)])
    }
}

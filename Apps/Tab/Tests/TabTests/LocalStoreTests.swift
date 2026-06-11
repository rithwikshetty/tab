import Foundation
import SwiftData
import Testing
@testable import Tab

@MainActor
@Suite("Local store wipe")
struct LocalStoreTests {
    @Test("wipe removes every cached row so the next account starts clean")
    func wipeClearsEverything() throws {
        let container = try TabModelContainer.makeInMemory()
        let ctx = container.mainContext

        let userID = UUID()
        let trip = TripEntity(name: "Prev user trip", createdByID: userID)
        ctx.insert(trip)
        ctx.insert(ProfileEntity(id: userID, displayName: "Prev"))
        let person = TripPersonEntity(
            id: UUID(), userID: userID, email: "prev@x.test", displayName: "Prev",
            invitedByID: userID, trip: trip, joinedAt: .now
        )
        ctx.insert(person)
        let expense = ExpenseEntity(
            amount: 10, currency: "EUR", descriptionText: "Lunch",
            expenseDate: .now, createdByID: userID, trip: trip
        )
        ctx.insert(expense)
        ctx.insert(PaymentEntity(tripPersonID: person.id, amountPaid: 10, paymentModeRaw: "equal", expense: expense))
        ctx.insert(ExpenseSplitEntity(tripPersonID: person.id, amountOwed: 10, splitTypeRaw: "equal", expense: expense))
        // A never-pushed local row — the kind reconcile would otherwise never remove.
        let ghost = TripEntity(name: "Unpushed", createdByID: userID)
        ctx.insert(ghost)
        try ctx.save()

        try LocalStore.wipe(ctx)

        #expect(try ctx.fetch(FetchDescriptor<TripEntity>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ProfileEntity>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<TripPersonEntity>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ExpenseEntity>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<PaymentEntity>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<ExpenseSplitEntity>()).isEmpty)
    }
}

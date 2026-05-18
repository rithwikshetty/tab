import Foundation
import SwiftData

@MainActor
enum Deletion {
    /// Soft-deletes an expense. Mirrors what `ExpenseDetailView.performDelete`
    /// did before this was extracted: bumps the expense's sync fields and the
    /// parent trip's activity timestamp so the list re-sorts.
    static func softDelete(expense: ExpenseEntity, in context: ModelContext) {
        let now = Date.now
        expense.deletedAt = now
        expense.updatedAt = now
        expense.writeID = UUID()
        if let trip = expense.trip {
            trip.lastActivityAt = now
            trip.updatedAt = now
        }
        try? context.save()
    }

    /// Soft-deletes a trip. RLS allows any member to update `deleted_at`; the
    /// 30-day purge window then handles eventual hard delete server-side.
    static func softDelete(trip: TripEntity, in context: ModelContext) {
        let now = Date.now
        trip.deletedAt = now
        trip.updatedAt = now
        trip.writeID = UUID()
        try? context.save()
    }
}

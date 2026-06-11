import Foundation
import SwiftData

/// Local-store maintenance that spans every model type. Kept in one place so
/// the entity list can't drift out of sync with the container schema.
@MainActor
enum LocalStore {
    /// Deletes every locally-cached row. Called on sign-out so a second account
    /// on the same device never sees the previous user's trips, expenses, or
    /// pending (never-pushed) writes.
    static func wipe(_ ctx: ModelContext) throws {
        // Object-level deletes, not `delete(model:)` batch deletes: a batch
        // delete can't satisfy the mandatory non-optional inverse on
        // ExpenseSplit/Payment → Expense. Deleting the aggregate roots cascades
        // to their children (trip → people/expenses/settlements → payments/splits).
        for trip in try ctx.fetch(FetchDescriptor<TripEntity>()) { ctx.delete(trip) }
        for profile in try ctx.fetch(FetchDescriptor<ProfileEntity>()) { ctx.delete(profile) }
        for category in try ctx.fetch(FetchDescriptor<CategoryEntity>()) { ctx.delete(category) }
        for activity in try ctx.fetch(FetchDescriptor<ActivityEntity>()) { ctx.delete(activity) }
        for mute in try ctx.fetch(FetchDescriptor<TripMuteEntity>()) { ctx.delete(mute) }
        try ctx.save()
    }
}

import Foundation
import SwiftData

enum TabModelContainer {
    static let schema = Schema([
        ProfileEntity.self, TripEntity.self, TripPersonEntity.self,
        CategoryEntity.self, ExpenseEntity.self, PaymentEntity.self,
        ExpenseSplitEntity.self, SettlementEntity.self,
        ActivityEntity.self, TripMuteEntity.self,
    ])

    static func make() -> ModelContainer {
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// Real SwiftData backed by memory only — used by tests.
    static func makeInMemory() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

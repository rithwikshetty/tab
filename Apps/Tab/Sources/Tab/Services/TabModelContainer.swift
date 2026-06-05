import Foundation
import SwiftData

enum TabModelContainer {
    static func make() -> ModelContainer {
        do {
            return try ModelContainer(
                for: ProfileEntity.self, TripEntity.self, TripPersonEntity.self,
                     CategoryEntity.self, ExpenseEntity.self, PaymentEntity.self,
                     ExpenseSplitEntity.self, SettlementEntity.self,
                     ActivityEntity.self, TripMuteEntity.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}

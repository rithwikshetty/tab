import Foundation
import SwiftData

enum RoamModelContainer {
    static func make() -> ModelContainer {
        do {
            return try ModelContainer(
                for: ProfileEntity.self, TripEntity.self, TripMemberEntity.self,
                     CategoryEntity.self, ExpenseEntity.self, ExpenseSplitEntity.self,
                     SettlementEntity.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}

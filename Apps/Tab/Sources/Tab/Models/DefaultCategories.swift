import Foundation
import SwiftUI

struct DefaultCategory: Hashable, Sendable {
    let id: UUID
    let name: String
    let icon: String
}

enum DefaultCategories {
    static let food       = DefaultCategory(id: UUID(uuidString: "00000001-0000-0000-0000-000000000000")!, name: "Food & Drink", icon: "bowl-food")
    static let transport  = DefaultCategory(id: UUID(uuidString: "00000002-0000-0000-0000-000000000000")!, name: "Transport",    icon: "car-profile")
    static let lodging    = DefaultCategory(id: UUID(uuidString: "00000003-0000-0000-0000-000000000000")!, name: "Lodging",      icon: "bed")
    static let activities = DefaultCategory(id: UUID(uuidString: "00000004-0000-0000-0000-000000000000")!, name: "Activities",   icon: "mask-happy")
    static let shopping   = DefaultCategory(id: UUID(uuidString: "00000005-0000-0000-0000-000000000000")!, name: "Shopping",     icon: "shopping-bag")
    static let other      = DefaultCategory(id: UUID(uuidString: "00000006-0000-0000-0000-000000000000")!, name: "Other",        icon: "tag")

    static let all: [DefaultCategory] = [food, transport, lodging, activities, shopping, other]

    static func tone(for categoryID: UUID) -> Color {
        switch categoryID {
        case food.id:       return Sage.CategoryTone.food
        case transport.id:  return Sage.CategoryTone.transport
        case lodging.id:    return Sage.CategoryTone.lodging
        case activities.id: return Sage.CategoryTone.activities
        case shopping.id:   return Sage.CategoryTone.shopping
        case other.id:      return Sage.CategoryTone.other
        default:            return Sage.text
        }
    }
}

import Foundation

struct DefaultCategory: Hashable, Sendable {
    let id: UUID
    let name: String
    let icon: String
}

enum DefaultCategories {
    static let food       = DefaultCategory(id: UUID(uuidString: "00000001-0000-0000-0000-000000000000")!, name: "Food & Drink", icon: "🍽")
    static let transport  = DefaultCategory(id: UUID(uuidString: "00000002-0000-0000-0000-000000000000")!, name: "Transport",    icon: "🚗")
    static let lodging    = DefaultCategory(id: UUID(uuidString: "00000003-0000-0000-0000-000000000000")!, name: "Lodging",      icon: "🏨")
    static let activities = DefaultCategory(id: UUID(uuidString: "00000004-0000-0000-0000-000000000000")!, name: "Activities",   icon: "🎭")
    static let shopping   = DefaultCategory(id: UUID(uuidString: "00000005-0000-0000-0000-000000000000")!, name: "Shopping",     icon: "🛍")
    static let other      = DefaultCategory(id: UUID(uuidString: "00000006-0000-0000-0000-000000000000")!, name: "Other",        icon: "⋯")

    static let all: [DefaultCategory] = [food, transport, lodging, activities, shopping, other]
}

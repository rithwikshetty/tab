import Foundation

struct MemberCard: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let initial: String
    let tone: AvatarTone

    init(id: UUID, displayName: String, avatarName: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.initial = AvatarInitial.from(avatarName ?? displayName)
        self.tone = AvatarTone.deterministic(for: id)
    }
}

struct TripCard: Identifiable, Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case owed(String)
        case owe(String)
        case settled(String)
        case empty
    }

    let id: UUID
    let name: String
    let members: [MemberCard]
    let status: Status
    let isCompleted: Bool
}

struct ExpenseRowItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let categoryID: UUID?
    let icon: String
    let name: String
    let payerName: String
    let payerIsYou: Bool
    let yourShare: String
    let totalAmount: String
}

struct ExpenseDay: Identifiable, Hashable, Sendable {
    let id: String
    let dateLabel: String
    let expenses: [ExpenseRowItem]
}

struct BalanceDetailItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let counterparty: String
    let amount: String
}

struct BalanceSummary: Hashable, Sendable {
    let label: String
    let amount: String
    let details: [BalanceDetailItem]
}

struct CategoryOption: Identifiable, Hashable, Sendable {
    let id: UUID
    let icon: String
    let name: String
}

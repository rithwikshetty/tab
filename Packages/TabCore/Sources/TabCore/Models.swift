import Foundation

public struct ExpenseSplit: Hashable, Codable, Sendable {
    public let participantID: UUID
    public let amountOwed: Decimal
    public let splitType: SplitType

    public init(participantID: UUID, amountOwed: Decimal, splitType: SplitType) {
        self.participantID = participantID
        self.amountOwed = amountOwed
        self.splitType = splitType
    }
}

public struct Expense: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let tripID: UUID
    public let amount: Money
    public let categoryID: UUID?
    public let descriptionText: String?
    public let receiptStoragePath: String?
    public let expenseDate: Date
    public let payments: [Payment]
    public let splits: [ExpenseSplit]
    public let createdBy: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    public init(
        id: UUID = UUID(),
        tripID: UUID,
        amount: Money,
        categoryID: UUID? = nil,
        descriptionText: String? = nil,
        receiptStoragePath: String? = nil,
        expenseDate: Date,
        payments: [Payment],
        splits: [ExpenseSplit],
        createdBy: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.tripID = tripID
        self.amount = amount
        self.categoryID = categoryID
        self.descriptionText = descriptionText
        self.receiptStoragePath = receiptStoragePath
        self.expenseDate = expenseDate
        self.payments = payments
        self.splits = splits
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

public struct Settlement: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let tripID: UUID
    public let fromUserID: UUID
    public let toUserID: UUID
    public let amount: Money
    public let note: String?
    public let settledAt: Date
    public let createdBy: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    public init(
        id: UUID = UUID(),
        tripID: UUID,
        fromUserID: UUID,
        toUserID: UUID,
        amount: Money,
        note: String? = nil,
        settledAt: Date,
        createdBy: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.tripID = tripID
        self.fromUserID = fromUserID
        self.toUserID = toUserID
        self.amount = amount
        self.note = note
        self.settledAt = settledAt
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

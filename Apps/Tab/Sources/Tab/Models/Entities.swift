import Foundation
import SwiftData

// MARK: - Profile

@Model
final class ProfileEntity {
    #Unique<ProfileEntity>([\.id])

    var id: UUID
    var displayName: String
    var avatarURL: String?
    var updatedAt: Date
    var writeID: UUID
    var pushedWriteID: UUID?

    init(
        id: UUID,
        displayName: String,
        avatarURL: String? = nil,
        updatedAt: Date = .now,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.updatedAt = updatedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - Trip

@Model
final class TripEntity {
    #Unique<TripEntity>([\.id])

    var id: UUID
    var name: String
    var createdByID: UUID
    var lastActivityAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var writeID: UUID
    var pushedWriteID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \TripPersonEntity.trip)
    var people: [TripPersonEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \ExpenseEntity.trip)
    var expenses: [ExpenseEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \SettlementEntity.trip)
    var settlements: [SettlementEntity] = []

    init(
        id: UUID = UUID(),
        name: String,
        createdByID: UUID,
        lastActivityAt: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.createdByID = createdByID
        self.lastActivityAt = lastActivityAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - TripPerson

@Model
final class TripPersonEntity {
    #Unique<TripPersonEntity>([\.id])

    var id: UUID
    var userID: UUID?
    var email: String
    var displayName: String
    var invitedByID: UUID?
    var joinedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var writeID: UUID
    var pushedWriteID: UUID?

    var trip: TripEntity?

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        email: String,
        displayName: String,
        invitedByID: UUID? = nil,
        trip: TripEntity? = nil,
        joinedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.userID = userID
        self.email = email
        self.displayName = displayName
        self.invitedByID = invitedByID
        self.trip = trip
        self.joinedAt = joinedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - Category

@Model
final class CategoryEntity {
    #Unique<CategoryEntity>([\.id])

    var id: UUID
    var tripID: UUID?         // nil for built-in defaults
    var name: String
    var icon: String
    var isDefault: Bool
    var updatedAt: Date
    var deletedAt: Date?
    var writeID: UUID
    var pushedWriteID: UUID?

    init(
        id: UUID = UUID(),
        tripID: UUID? = nil,
        name: String,
        icon: String,
        isDefault: Bool,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.tripID = tripID
        self.name = name
        self.icon = icon
        self.isDefault = isDefault
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - Expense

@Model
final class ExpenseEntity {
    #Unique<ExpenseEntity>([\.id])

    var id: UUID
    var amount: Decimal
    var currency: String
    var categoryID: UUID?
    var descriptionText: String
    var expenseDate: Date
    var receiptStoragePath: String?
    var createdByID: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var writeID: UUID
    var pushedWriteID: UUID?

    var trip: TripEntity?

    @Relationship(deleteRule: .cascade, inverse: \PaymentEntity.expense)
    var payments: [PaymentEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \ExpenseSplitEntity.expense)
    var splits: [ExpenseSplitEntity] = []

    init(
        id: UUID = UUID(),
        amount: Decimal,
        currency: String,
        categoryID: UUID? = nil,
        descriptionText: String,
        expenseDate: Date,
        receiptStoragePath: String? = nil,
        createdByID: UUID,
        trip: TripEntity? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.categoryID = categoryID
        self.descriptionText = descriptionText
        self.expenseDate = expenseDate
        self.receiptStoragePath = receiptStoragePath
        self.createdByID = createdByID
        self.trip = trip
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - Payment

@Model
final class PaymentEntity {
    #Unique<PaymentEntity>([\.id])

    var id: UUID
    var tripPersonID: UUID
    var amountPaid: Decimal
    var paymentModeRaw: String
    var updatedAt: Date
    var writeID: UUID
    var pushedWriteID: UUID?

    var expense: ExpenseEntity?

    init(
        tripPersonID: UUID,
        amountPaid: Decimal,
        paymentModeRaw: String,
        expense: ExpenseEntity? = nil,
        updatedAt: Date = .now,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = UUID()
        self.tripPersonID = tripPersonID
        self.amountPaid = amountPaid
        self.paymentModeRaw = paymentModeRaw
        self.expense = expense
        self.updatedAt = updatedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - ExpenseSplit

@Model
final class ExpenseSplitEntity {
    #Unique<ExpenseSplitEntity>([\.id])

    var id: UUID
    var tripPersonID: UUID
    var amountOwed: Decimal
    var splitTypeRaw: String
    var updatedAt: Date
    var writeID: UUID
    var pushedWriteID: UUID?

    var expense: ExpenseEntity?

    init(
        tripPersonID: UUID,
        amountOwed: Decimal,
        splitTypeRaw: String,
        expense: ExpenseEntity? = nil,
        updatedAt: Date = .now,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = UUID()
        self.tripPersonID = tripPersonID
        self.amountOwed = amountOwed
        self.splitTypeRaw = splitTypeRaw
        self.expense = expense
        self.updatedAt = updatedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

// MARK: - Settlement

@Model
final class SettlementEntity {
    #Unique<SettlementEntity>([\.id])

    var id: UUID
    var fromPersonID: UUID
    var toPersonID: UUID
    var amount: Decimal
    var currency: String
    var note: String?
    var settledAt: Date
    var createdByID: UUID
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var writeID: UUID
    var pushedWriteID: UUID?

    var trip: TripEntity?

    init(
        id: UUID = UUID(),
        fromPersonID: UUID,
        toPersonID: UUID,
        amount: Decimal,
        currency: String,
        note: String? = nil,
        settledAt: Date,
        createdByID: UUID,
        trip: TripEntity? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        writeID: UUID = UUID(),
        pushedWriteID: UUID? = nil
    ) {
        self.id = id
        self.fromPersonID = fromPersonID
        self.toPersonID = toPersonID
        self.amount = amount
        self.currency = currency
        self.note = note
        self.settledAt = settledAt
        self.createdByID = createdByID
        self.trip = trip
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.writeID = writeID
        self.pushedWriteID = pushedWriteID
    }
}

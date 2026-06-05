import Foundation

// MARK: - Profile

struct ProfileDTO: Codable, Sendable {
    let id: UUID
    let displayName: String
    let avatarURL: String?
    let createdAt: Date
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

// MARK: - Trip

struct TripDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let createdBy: UUID
    let lastActivityAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdBy = "created_by"
        case lastActivityAt = "last_activity_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case writeID = "write_id"
    }
}

struct TripInsertDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdBy = "created_by"
    }
}

struct TripUpdateDTO: Codable, Sendable {
    let name: String?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case name
        case deletedAt = "deleted_at"
    }
}

// MARK: - TripPerson

struct TripPersonDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID
    let userID: UUID?
    let email: String
    let displayName: String
    let invitedBy: UUID?
    let joinedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case userID = "user_id"
        case email
        case displayName = "display_name"
        case invitedBy = "invited_by"
        case joinedAt = "joined_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

struct TripPersonSuggestionDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String { email }
    let userID: UUID?
    let email: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email
        case displayName = "display_name"
    }
}

// MARK: - Category

struct CategoryDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID?
    let name: String
    let icon: String
    let isDefault: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case name, icon
        case isDefault = "is_default"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case writeID = "write_id"
    }
}

struct CategoryInsertDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID?
    let name: String
    let icon: String
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case name, icon
        case isDefault = "is_default"
    }
}

// MARK: - Expense

struct ExpenseDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID
    let amount: Decimal
    let currency: String
    let categoryID: UUID?
    let description: String
    let expenseDate: Date
    let receiptStoragePath: String?
    let paymentMethod: String
    let createdBy: UUID
    let lastEditedBy: UUID?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case amount, currency
        case categoryID = "category_id"
        case description
        case expenseDate = "expense_date"
        case receiptStoragePath = "receipt_storage_path"
        case paymentMethod = "payment_method"
        case createdBy = "created_by"
        case lastEditedBy = "last_edited_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case writeID = "write_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tripID = try c.decode(UUID.self, forKey: .tripID)
        amount = try c.decode(Decimal.self, forKey: .amount)
        currency = try c.decode(String.self, forKey: .currency)
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        description = try c.decode(String.self, forKey: .description)
        // `expense_date` is a Postgres `date` (bare `yyyy-MM-dd`, no time component).
        // The Supabase client's default date strategy only parses full ISO-8601
        // timestamps, so it throws on a date-only string — which would abort the
        // entire pull (expenses, payments, splits, settlements) after trips have
        // already synced. Decode it as a plain string and parse it ourselves; the
        // remaining timestamptz fields stay on the client's default strategy.
        let rawExpenseDate = try c.decode(String.self, forKey: .expenseDate)
        expenseDate = try Self.parseExpenseDate(rawExpenseDate, container: c)
        receiptStoragePath = try c.decodeIfPresent(String.self, forKey: .receiptStoragePath)
        paymentMethod = try c.decode(String.self, forKey: .paymentMethod)
        createdBy = try c.decode(UUID.self, forKey: .createdBy)
        lastEditedBy = try c.decodeIfPresent(UUID.self, forKey: .lastEditedBy)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        writeID = try c.decode(UUID.self, forKey: .writeID)
    }

    private static func parseExpenseDate(
        _ raw: String,
        container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date {
        if let date = dateOnlyFormatter.date(from: raw) { return date }
        // Defensive fallback: tolerate a full ISO-8601 timestamp if the column shape ever changes.
        if let date = try? Date(raw, strategy: .iso8601) { return date }
        throw DecodingError.dataCorruptedError(
            forKey: .expenseDate,
            in: container,
            debugDescription: "Unrecognized expense_date format: \(raw)"
        )
    }

    /// Matches the UTC `yyyy-MM-dd` shape produced by `SyncService` on push, so the
    /// `expense_date` round-trips to the same calendar day it was stored under.
    static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

struct ExpenseInsertDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID
    let amount: Decimal
    let currency: String
    let categoryID: UUID?
    let description: String
    let expenseDate: Date
    let receiptStoragePath: String?
    let paymentMethod: String
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case amount, currency
        case categoryID = "category_id"
        case description
        case expenseDate = "expense_date"
        case receiptStoragePath = "receipt_storage_path"
        case paymentMethod = "payment_method"
        case createdBy = "created_by"
    }
}

struct ExpenseDeleteUpdateDTO: Codable, Sendable {
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
    }
}

// MARK: - ExpensePayment

struct ExpensePaymentDTO: Codable, Sendable {
    let expenseID: UUID
    let tripPersonID: UUID
    let amountPaid: Decimal
    let paymentMode: String
    let createdAt: Date
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case expenseID = "expense_id"
        case tripPersonID = "trip_person_id"
        case amountPaid = "amount_paid"
        case paymentMode = "payment_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

struct ExpensePaymentInsertDTO: Codable, Sendable {
    let expenseID: UUID
    let tripPersonID: UUID
    let amountPaid: Decimal
    let paymentMode: String

    enum CodingKeys: String, CodingKey {
        case expenseID = "expense_id"
        case tripPersonID = "trip_person_id"
        case amountPaid = "amount_paid"
        case paymentMode = "payment_mode"
    }
}

// MARK: - ExpenseSplit

struct ExpenseSplitDTO: Codable, Sendable {
    let expenseID: UUID
    let tripPersonID: UUID
    let amountOwed: Decimal
    let splitType: String
    let createdAt: Date
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case expenseID = "expense_id"
        case tripPersonID = "trip_person_id"
        case amountOwed = "amount_owed"
        case splitType = "split_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

struct ExpenseSplitInsertDTO: Codable, Sendable {
    let expenseID: UUID
    let tripPersonID: UUID
    let amountOwed: Decimal
    let splitType: String

    enum CodingKeys: String, CodingKey {
        case expenseID = "expense_id"
        case tripPersonID = "trip_person_id"
        case amountOwed = "amount_owed"
        case splitType = "split_type"
    }
}

// MARK: - Settlement

struct SettlementDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID
    let fromPersonID: UUID
    let toPersonID: UUID
    let amount: Decimal
    let currency: String
    let note: String?
    let settledAt: Date
    let createdBy: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case fromPersonID = "from_person_id"
        case toPersonID = "to_person_id"
        case amount, currency, note
        case settledAt = "settled_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case writeID = "write_id"
    }
}

struct SettlementInsertDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID
    let fromPersonID: UUID
    let toPersonID: UUID
    let amount: Decimal
    let currency: String
    let note: String?
    let settledAt: Date
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case fromPersonID = "from_person_id"
        case toPersonID = "to_person_id"
        case amount, currency, note
        case settledAt = "settled_at"
        case createdBy = "created_by"
    }
}

struct SettlementDeleteUpdateDTO: Codable, Sendable {
    let deletedAt: Date?
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

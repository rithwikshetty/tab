import Foundation
import SwiftData
import Supabase
import os

private let syncLog = Logger(subsystem: "com.rithwikshetty.roam", category: "sync")

@MainActor
@Observable
final class SyncService {
    enum Phase: Equatable {
        case idle
        case pulling
        case pushing
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastPullAt: Date?

    private let client = SupabaseClientProvider.shared
    private let container: ModelContainer
    private weak var auth: AuthService?

    init(container: ModelContainer, auth: AuthService) {
        self.container = container
        self.auth = auth
    }

    /// Returns true when a real Supabase session exists (i.e. not mock auth).
    private var hasRealSession: Bool {
        client.auth.currentSession != nil
    }

    // MARK: - Pull

    func pullAll() async {
        guard hasRealSession else { return }
        phase = .pulling
        do {
            try await pullProfiles()
            try await pullTrips()
            try await pullTripMembers()
            try await pullCategories()
            try await pullExpenses()
            try await pullExpenseSplits()
            try await pullSettlements()
            lastPullAt = .now
            phase = .idle
        } catch {
            syncLog.error("pull failed: \(error.localizedDescription, privacy: .public)")
            phase = .error(error.localizedDescription)
        }
    }

    private func pullProfiles() async throws {
        let rows: [ProfileDTO] = try await client
            .from("profiles")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try upsertProfile(dto, in: ctx)
        }
        try ctx.save()
    }

    private func pullTrips() async throws {
        let rows: [TripDTO] = try await client
            .from("trips")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try upsertTrip(dto, in: ctx)
        }
        try ctx.save()
    }

    private func pullTripMembers() async throws {
        let rows: [TripMemberDTO] = try await client
            .from("trip_members")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try upsertTripMember(dto, in: ctx)
        }
        try ctx.save()
    }

    private func pullCategories() async throws {
        let rows: [CategoryDTO] = try await client
            .from("categories")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try upsertCategory(dto, in: ctx)
        }
        try ctx.save()
    }

    private func pullExpenses() async throws {
        let rows: [ExpenseDTO] = try await client
            .from("expenses")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try upsertExpense(dto, in: ctx)
        }
        try ctx.save()
    }

    private func pullExpenseSplits() async throws {
        let rows: [ExpenseSplitDTO] = try await client
            .from("expense_splits")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try upsertExpenseSplit(dto, in: ctx)
        }
        try ctx.save()
    }

    private func pullSettlements() async throws {
        let rows: [SettlementDTO] = try await client
            .from("settlements")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try upsertSettlement(dto, in: ctx)
        }
        try ctx.save()
    }

    // MARK: - Upserts (server → local)

    private func upsertProfile(_ dto: ProfileDTO, in ctx: ModelContext) throws {
        let id = dto.id
        let existing = try ctx.fetch(FetchDescriptor<ProfileEntity>(
            predicate: #Predicate { $0.id == id }
        )).first

        if let entity = existing {
            if entity.writeID == dto.writeID { return }
            entity.displayName = dto.displayName
            entity.avatarURL = dto.avatarURL
            entity.updatedAt = dto.updatedAt
            entity.writeID = dto.writeID
            entity.pushedWriteID = dto.writeID
        } else {
            ctx.insert(ProfileEntity(
                id: dto.id,
                displayName: dto.displayName,
                avatarURL: dto.avatarURL,
                updatedAt: dto.updatedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
        }
    }

    private func upsertTrip(_ dto: TripDTO, in ctx: ModelContext) throws {
        let id = dto.id
        let existing = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == id }
        )).first

        if let entity = existing {
            if entity.writeID == dto.writeID { return }
            entity.name = dto.name
            entity.createdByID = dto.createdBy
            entity.lastActivityAt = dto.lastActivityAt
            entity.updatedAt = dto.updatedAt
            entity.deletedAt = dto.deletedAt
            entity.writeID = dto.writeID
            entity.pushedWriteID = dto.writeID
        } else {
            ctx.insert(TripEntity(
                id: dto.id,
                name: dto.name,
                createdByID: dto.createdBy,
                lastActivityAt: dto.lastActivityAt,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                deletedAt: dto.deletedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
        }
    }

    private func upsertTripMember(_ dto: TripMemberDTO, in ctx: ModelContext) throws {
        let tripID = dto.tripID
        let userID = dto.userID

        let trip = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == tripID }
        )).first

        guard let trip else { return }

        let existing = trip.members.first(where: { $0.userID == userID })
        if let entity = existing {
            if entity.writeID == dto.writeID { return }
            entity.joinedAt = dto.joinedAt
            entity.updatedAt = dto.updatedAt
            entity.writeID = dto.writeID
            entity.pushedWriteID = dto.writeID
        } else {
            ctx.insert(TripMemberEntity(
                userID: dto.userID,
                trip: trip,
                joinedAt: dto.joinedAt,
                updatedAt: dto.updatedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
        }
    }

    private func upsertCategory(_ dto: CategoryDTO, in ctx: ModelContext) throws {
        let id = dto.id
        let existing = try ctx.fetch(FetchDescriptor<CategoryEntity>(
            predicate: #Predicate { $0.id == id }
        )).first

        if let entity = existing {
            if entity.writeID == dto.writeID { return }
            entity.name = dto.name
            entity.icon = dto.icon
            entity.isDefault = dto.isDefault
            entity.tripID = dto.tripID
            entity.updatedAt = dto.updatedAt
            entity.deletedAt = dto.deletedAt
            entity.writeID = dto.writeID
            entity.pushedWriteID = dto.writeID
        } else {
            ctx.insert(CategoryEntity(
                id: dto.id,
                tripID: dto.tripID,
                name: dto.name,
                icon: dto.icon,
                isDefault: dto.isDefault,
                updatedAt: dto.updatedAt,
                deletedAt: dto.deletedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
        }
    }

    private func upsertExpense(_ dto: ExpenseDTO, in ctx: ModelContext) throws {
        let id = dto.id
        let tripID = dto.tripID
        let trip = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == tripID }
        )).first

        let existing = try ctx.fetch(FetchDescriptor<ExpenseEntity>(
            predicate: #Predicate { $0.id == id }
        )).first

        if let entity = existing {
            if entity.writeID == dto.writeID { return }
            entity.payerID = dto.payerID
            entity.amount = dto.amount
            entity.currency = dto.currency
            entity.categoryID = dto.categoryID
            entity.descriptionText = dto.description
            entity.expenseDate = dto.expenseDate
            entity.receiptStoragePath = dto.receiptStoragePath
            entity.createdByID = dto.createdBy
            entity.updatedAt = dto.updatedAt
            entity.deletedAt = dto.deletedAt
            entity.writeID = dto.writeID
            entity.pushedWriteID = dto.writeID
        } else {
            ctx.insert(ExpenseEntity(
                id: dto.id,
                payerID: dto.payerID,
                amount: dto.amount,
                currency: dto.currency,
                categoryID: dto.categoryID,
                descriptionText: dto.description,
                expenseDate: dto.expenseDate,
                receiptStoragePath: dto.receiptStoragePath,
                createdByID: dto.createdBy,
                trip: trip,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                deletedAt: dto.deletedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
        }
    }

    private func upsertExpenseSplit(_ dto: ExpenseSplitDTO, in ctx: ModelContext) throws {
        let expenseID = dto.expenseID
        let userID = dto.userID
        let expense = try ctx.fetch(FetchDescriptor<ExpenseEntity>(
            predicate: #Predicate { $0.id == expenseID }
        )).first
        guard let expense else { return }

        let existing = expense.splits.first(where: { $0.userID == userID })
        if let entity = existing {
            if entity.writeID == dto.writeID { return }
            entity.amountOwed = dto.amountOwed
            entity.splitTypeRaw = dto.splitType
            entity.updatedAt = dto.updatedAt
            entity.writeID = dto.writeID
            entity.pushedWriteID = dto.writeID
        } else {
            ctx.insert(ExpenseSplitEntity(
                userID: dto.userID,
                amountOwed: dto.amountOwed,
                splitTypeRaw: dto.splitType,
                expense: expense,
                updatedAt: dto.updatedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
        }
    }

    private func upsertSettlement(_ dto: SettlementDTO, in ctx: ModelContext) throws {
        let id = dto.id
        let tripID = dto.tripID
        let trip = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == tripID }
        )).first

        let existing = try ctx.fetch(FetchDescriptor<SettlementEntity>(
            predicate: #Predicate { $0.id == id }
        )).first

        if let entity = existing {
            if entity.writeID == dto.writeID { return }
            entity.fromUserID = dto.fromUser
            entity.toUserID = dto.toUser
            entity.amount = dto.amount
            entity.currency = dto.currency
            entity.note = dto.note
            entity.settledAt = dto.settledAt
            entity.createdByID = dto.createdBy
            entity.updatedAt = dto.updatedAt
            entity.deletedAt = dto.deletedAt
            entity.writeID = dto.writeID
            entity.pushedWriteID = dto.writeID
        } else {
            ctx.insert(SettlementEntity(
                id: dto.id,
                fromUserID: dto.fromUser,
                toUserID: dto.toUser,
                amount: dto.amount,
                currency: dto.currency,
                note: dto.note,
                settledAt: dto.settledAt,
                createdByID: dto.createdBy,
                trip: trip,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                deletedAt: dto.deletedAt,
                writeID: dto.writeID,
                pushedWriteID: dto.writeID
            ))
        }
    }

    // MARK: - Push

    func pushPending() async {
        guard hasRealSession else { return }
        phase = .pushing
        do {
            try await pushTrips()
            try await pushSettlements()
            try await pushExpensesAndSplits()
            phase = .idle
        } catch {
            syncLog.error("push failed: \(error.localizedDescription, privacy: .public)")
            phase = .error(error.localizedDescription)
        }
    }

    private func pushTrips() async throws {
        let ctx = container.mainContext
        let dirty = try ctx.fetch(FetchDescriptor<TripEntity>()).filter { $0.pushedWriteID != $0.writeID }
        guard !dirty.isEmpty else { return }
        for trip in dirty {
            let insert = TripInsertDTO(id: trip.id, name: trip.name, createdBy: trip.createdByID)
            do {
                try await client
                    .from("trips")
                    .upsert(insert, onConflict: "id")
                    .execute()
                trip.pushedWriteID = trip.writeID
            } catch {
                syncLog.error("trip push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try ctx.save()
    }

    private func pushSettlements() async throws {
        let ctx = container.mainContext
        let dirty = try ctx.fetch(FetchDescriptor<SettlementEntity>()).filter { $0.pushedWriteID != $0.writeID }
        guard !dirty.isEmpty else { return }
        for settlement in dirty {
            let insert = SettlementInsertDTO(
                id: settlement.id,
                tripID: settlement.trip?.id ?? UUID(),
                fromUser: settlement.fromUserID,
                toUser: settlement.toUserID,
                amount: settlement.amount,
                currency: settlement.currency,
                note: settlement.note,
                settledAt: settlement.settledAt,
                createdBy: settlement.createdByID
            )
            do {
                try await client.from("settlements").upsert(insert, onConflict: "id").execute()
                settlement.pushedWriteID = settlement.writeID
            } catch {
                syncLog.error("settlement push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try ctx.save()
    }

    /// Expenses + splits via the create_expense_with_splits RPC (transactional).
    private func pushExpensesAndSplits() async throws {
        let ctx = container.mainContext
        let dirtyExpenses = try ctx
            .fetch(FetchDescriptor<ExpenseEntity>())
            .filter { $0.pushedWriteID != $0.writeID }
        guard !dirtyExpenses.isEmpty else { return }

        for expense in dirtyExpenses {
            guard let tripID = expense.trip?.id else { continue }

            let expensePayload: [String: AnyJSON] = [
                "id": .string(expense.id.uuidString),
                "trip_id": .string(tripID.uuidString),
                "payer_id": .string(expense.payerID.uuidString),
                "amount": .string(Self.decimalString(expense.amount)),
                "currency": .string(expense.currency),
                "category_id": expense.categoryID.map { .string($0.uuidString) } ?? .null,
                "description": .string(expense.descriptionText),
                "expense_date": .string(Self.dateOnlyFormatter.string(from: expense.expenseDate)),
                "receipt_storage_path": expense.receiptStoragePath.map { .string($0) } ?? .null,
                "created_by": .string(expense.createdByID.uuidString),
            ]

            let splitsPayload: [AnyJSON] = expense.splits.map { split in
                AnyJSON.object([
                    "user_id": .string(split.userID.uuidString),
                    "amount_owed": .string(Self.decimalString(split.amountOwed)),
                    "split_type": .string(split.splitTypeRaw),
                ])
            }

            do {
                try await client.rpc("create_expense_with_splits", params: [
                    "p_expense": AnyJSON.object(expensePayload),
                    "p_splits": AnyJSON.array(splitsPayload),
                ]).execute()
                expense.pushedWriteID = expense.writeID
                for split in expense.splits { split.pushedWriteID = split.writeID }
            } catch {
                syncLog.error("expense push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try ctx.save()
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

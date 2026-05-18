import Foundation
import SwiftData
import Supabase
import os

private let syncLog = Logger(subsystem: "com.rithwikshetty.tab", category: "sync")

private struct TripMemberRemoteKey: Hashable, Sendable {
    let tripID: UUID
    let userID: UUID
}

private struct ExpensePaymentRemoteKey: Hashable, Sendable {
    let expenseID: UUID
    let userID: UUID
}

private struct ExpenseSplitRemoteKey: Hashable, Sendable {
    let expenseID: UUID
    let userID: UUID
}

@MainActor
@Observable
final class SyncService {
    enum Phase: Equatable {
        case idle
        case pulling
        case pushing
        case error(String)
    }

    enum SyncError: LocalizedError {
        case signInRequired
        case localTripMissing
        case deletedTrip

        var errorDescription: String? {
            switch self {
            case .signInRequired: "Sign in to sync this trip."
            case .localTripMissing: "Trip not found on this device."
            case .deletedTrip: "This trip has been deleted."
            }
        }
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

    func ensureTripUploaded(tripID: UUID) async throws {
        guard hasRealSession else { throw SyncError.signInRequired }

        let ctx = container.mainContext
        let trip = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == tripID }
        )).first

        guard let trip else { throw SyncError.localTripMissing }
        guard trip.deletedAt == nil else { throw SyncError.deletedTrip }
        guard trip.pushedWriteID != trip.writeID else { return }

        try await pushCurrentProfileIfNeeded(in: ctx)
        try await pushTrip(trip)
        try ctx.save()
    }

    // MARK: - Pull

    func pullAll() async {
        guard hasRealSession else { return }
        phase = .pulling
        do {
            let profileIDs = try await pullProfiles()
            let tripIDs = try await pullTrips()
            let tripMemberKeys = try await pullTripMembers()
            let categoryIDs = try await pullCategories()
            let expenseIDs = try await pullExpenses()
            let expensePaymentKeys = try await pullExpensePayments()
            let expenseSplitKeys = try await pullExpenseSplits()
            let settlementIDs = try await pullSettlements()
            try reconcileLocalRows(
                remoteProfileIDs: profileIDs,
                remoteTripIDs: tripIDs,
                remoteTripMemberKeys: tripMemberKeys,
                remoteCategoryIDs: categoryIDs,
                remoteExpenseIDs: expenseIDs,
                remoteExpensePaymentKeys: expensePaymentKeys,
                remoteExpenseSplitKeys: expenseSplitKeys,
                remoteSettlementIDs: settlementIDs
            )
            lastPullAt = .now
            phase = .idle
        } catch {
            syncLog.error("pull failed: \(error.localizedDescription, privacy: .public)")
            phase = .error(error.localizedDescription)
        }
    }

    private func pullProfiles() async throws -> Set<UUID> {
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
        return Set(rows.map(\.id))
    }

    private func pullTrips() async throws -> Set<UUID> {
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
        return Set(rows.map(\.id))
    }

    private func pullTripMembers() async throws -> Set<TripMemberRemoteKey> {
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
        return Set(rows.map { TripMemberRemoteKey(tripID: $0.tripID, userID: $0.userID) })
    }

    private func pullCategories() async throws -> Set<UUID> {
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
        return Set(rows.map(\.id))
    }

    private func pullExpenses() async throws -> Set<UUID> {
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
        return Set(rows.map(\.id))
    }

    private func pullExpensePayments() async throws -> Set<ExpensePaymentRemoteKey> {
        let rows: [ExpensePaymentDTO] = try await client
            .from("expense_payments")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try upsertExpensePayment(dto, in: ctx)
        }
        try ctx.save()
        return Set(rows.map { ExpensePaymentRemoteKey(expenseID: $0.expenseID, userID: $0.userID) })
    }

    private func pullExpenseSplits() async throws -> Set<ExpenseSplitRemoteKey> {
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
        return Set(rows.map { ExpenseSplitRemoteKey(expenseID: $0.expenseID, userID: $0.userID) })
    }

    private func pullSettlements() async throws -> Set<UUID> {
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
        return Set(rows.map(\.id))
    }

    private func reconcileLocalRows(
        remoteProfileIDs: Set<UUID>,
        remoteTripIDs: Set<UUID>,
        remoteTripMemberKeys: Set<TripMemberRemoteKey>,
        remoteCategoryIDs: Set<UUID>,
        remoteExpenseIDs: Set<UUID>,
        remoteExpensePaymentKeys: Set<ExpensePaymentRemoteKey>,
        remoteExpenseSplitKeys: Set<ExpenseSplitRemoteKey>,
        remoteSettlementIDs: Set<UUID>
    ) throws {
        let ctx = container.mainContext

        for payment in try ctx.fetch(FetchDescriptor<PaymentEntity>()) {
            guard payment.pushedWriteID != nil, let expenseID = payment.expense?.id else { continue }
            if !remoteExpensePaymentKeys.contains(ExpensePaymentRemoteKey(expenseID: expenseID, userID: payment.userID)) {
                ctx.delete(payment)
            }
        }

        for split in try ctx.fetch(FetchDescriptor<ExpenseSplitEntity>()) {
            guard split.pushedWriteID != nil, let expenseID = split.expense?.id else { continue }
            if !remoteExpenseSplitKeys.contains(ExpenseSplitRemoteKey(expenseID: expenseID, userID: split.userID)) {
                ctx.delete(split)
            }
        }

        for settlement in try ctx.fetch(FetchDescriptor<SettlementEntity>()) {
            if settlement.pushedWriteID != nil && !remoteSettlementIDs.contains(settlement.id) {
                ctx.delete(settlement)
            }
        }

        for expense in try ctx.fetch(FetchDescriptor<ExpenseEntity>()) {
            if expense.pushedWriteID != nil && !remoteExpenseIDs.contains(expense.id) {
                ctx.delete(expense)
            }
        }

        for member in try ctx.fetch(FetchDescriptor<TripMemberEntity>()) {
            guard member.pushedWriteID != nil, let tripID = member.trip?.id else { continue }
            if !remoteTripMemberKeys.contains(TripMemberRemoteKey(tripID: tripID, userID: member.userID)) {
                ctx.delete(member)
            }
        }

        for trip in try ctx.fetch(FetchDescriptor<TripEntity>()) {
            if trip.pushedWriteID != nil && !remoteTripIDs.contains(trip.id) {
                ctx.delete(trip)
            }
        }

        for category in try ctx.fetch(FetchDescriptor<CategoryEntity>()) {
            guard !category.isDefault else { continue }
            if category.pushedWriteID != nil && !remoteCategoryIDs.contains(category.id) {
                ctx.delete(category)
            }
        }

        for profile in try ctx.fetch(FetchDescriptor<ProfileEntity>()) {
            guard profile.pushedWriteID != nil else { continue }
            if auth?.currentUser?.id == profile.id { continue }
            if !remoteProfileIDs.contains(profile.id) {
                ctx.delete(profile)
            }
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

    private func upsertExpensePayment(_ dto: ExpensePaymentDTO, in ctx: ModelContext) throws {
        let expenseID = dto.expenseID
        let userID = dto.userID
        let expense = try ctx.fetch(FetchDescriptor<ExpenseEntity>(
            predicate: #Predicate { $0.id == expenseID }
        )).first
        guard let expense else { return }

        let existing = expense.payments.first(where: { $0.userID == userID })
        if let entity = existing {
            if entity.writeID == dto.writeID { return }
            entity.amountPaid = dto.amountPaid
            entity.paymentModeRaw = dto.paymentMode
            entity.updatedAt = dto.updatedAt
            entity.writeID = dto.writeID
            entity.pushedWriteID = dto.writeID
        } else {
            ctx.insert(PaymentEntity(
                userID: dto.userID,
                amountPaid: dto.amountPaid,
                paymentModeRaw: dto.paymentMode,
                expense: expense,
                updatedAt: dto.updatedAt,
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
            try await pushProfiles()
            try await pushTrips()
            try await pushSettlements()
            await pushPendingReceiptUploads()
            try await pushExpensesAndSplits()
            phase = .idle
        } catch {
            syncLog.error("push failed: \(error.localizedDescription, privacy: .public)")
            phase = .error(error.localizedDescription)
        }
    }

    private func pushProfiles() async throws {
        let ctx = container.mainContext
        let dirty = try ctx.fetch(FetchDescriptor<ProfileEntity>())
            .filter { $0.pushedWriteID != $0.writeID }
        guard !dirty.isEmpty else { return }

        for profile in dirty {
            do {
                try await pushProfile(profile)
            } catch {
                syncLog.error("profile push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try ctx.save()
    }

    private func pushCurrentProfileIfNeeded(in ctx: ModelContext) async throws {
        guard let userID = auth?.currentUser?.id else { throw SyncError.signInRequired }
        let profile = try ctx.fetch(FetchDescriptor<ProfileEntity>(
            predicate: #Predicate { $0.id == userID }
        )).first
        guard let profile, profile.pushedWriteID != profile.writeID else { return }
        try await pushProfile(profile)
    }

    private func pushProfile(_ profile: ProfileEntity) async throws {
        let insert = ProfileInsertDTO(
            id: profile.id,
            displayName: profile.displayName,
            avatarURL: profile.avatarURL
        )
        try await client
            .from("profiles")
            .upsert(insert, onConflict: "id")
            .execute()
        profile.pushedWriteID = profile.writeID
    }

    private func pushTrips() async throws {
        let ctx = container.mainContext
        let dirty = try ctx.fetch(FetchDescriptor<TripEntity>()).filter { $0.pushedWriteID != $0.writeID }
        guard !dirty.isEmpty else { return }
        for trip in dirty {
            do {
                try await pushTrip(trip)
            } catch {
                syncLog.error("trip push failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        try ctx.save()
    }

    private func pushTrip(_ trip: TripEntity) async throws {
        if trip.pushedWriteID == nil {
            let insert = TripInsertDTO(id: trip.id, name: trip.name, createdBy: trip.createdByID)
            try await client
                .from("trips")
                .insert(insert)
                .execute()
        } else {
            let update = TripUpdateDTO(name: trip.name, deletedAt: trip.deletedAt)
            try await client
                .from("trips")
                .update(update)
                .eq("id", value: trip.id.uuidString)
                .execute()
        }
        trip.pushedWriteID = trip.writeID
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

    private func pushPendingReceiptUploads() async {
        let ctx = container.mainContext
        do {
            let paths = try Set(
                ctx.fetch(FetchDescriptor<ExpenseEntity>())
                    .filter { $0.deletedAt == nil }
                    .compactMap(\.receiptStoragePath)
            )
            for path in paths {
                do {
                    try await ReceiptStorage.uploadPendingReceipt(path: path)
                } catch {
                    syncLog.error("receipt upload failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            syncLog.error("pending receipt scan failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Expenses + payments + splits via the create_expense_with_payments_and_splits RPC (transactional).
    /// Soft-deletes (deletedAt != nil) bypass the RPC and use a direct UPDATE,
    /// since the RPC upserts the row + splits but ignores deleted_at.
    private func pushExpensesAndSplits() async throws {
        let ctx = container.mainContext
        let dirtyExpenses = try ctx
            .fetch(FetchDescriptor<ExpenseEntity>())
            .filter { $0.pushedWriteID != $0.writeID }
        guard !dirtyExpenses.isEmpty else { return }

        for expense in dirtyExpenses {
            guard let trip = expense.trip else { continue }
            let tripID = trip.id

            if expense.deletedAt != nil {
                if expense.pushedWriteID == nil {
                    ctx.delete(expense)
                } else if trip.deletedAt != nil {
                    // Parent trip is also (locally) soft-deleted. The DB trigger
                    // `validate_expense_row` rejects updates to `deleted_at` on
                    // expenses under deleted trips, so don't even try — mark
                    // this expense write resolved and let the trip delete carry.
                    expense.pushedWriteID = expense.writeID
                } else {
                    do {
                        try await client
                            .from("expenses")
                            .update(ExpenseDeleteUpdateDTO(deletedAt: expense.deletedAt))
                            .eq("id", value: expense.id.uuidString)
                            .execute()
                        expense.pushedWriteID = expense.writeID
                    } catch {
                        syncLog.error("expense delete push failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                continue
            }

            // Don't push new/edited expenses under a soft-deleted trip — the
            // server's RPC validates the parent trip is active and would reject.
            if trip.deletedAt != nil { continue }

            let expensePayload: [String: AnyJSON] = [
                "id": .string(expense.id.uuidString),
                "trip_id": .string(tripID.uuidString),
                "amount": .string(Self.decimalString(expense.amount)),
                "currency": .string(expense.currency),
                "category_id": expense.categoryID.map { .string($0.uuidString) } ?? .null,
                "description": .string(expense.descriptionText),
                "expense_date": .string(Self.dateOnlyFormatter.string(from: expense.expenseDate)),
                "receipt_storage_path": expense.receiptStoragePath.map { .string($0) } ?? .null,
                "created_by": .string(expense.createdByID.uuidString),
            ]

            let paymentsPayload: [AnyJSON] = expense.payments.map { payment in
                AnyJSON.object([
                    "user_id": .string(payment.userID.uuidString),
                    "amount_paid": .string(Self.decimalString(payment.amountPaid)),
                    "payment_mode": .string(payment.paymentModeRaw),
                ])
            }

            let splitsPayload: [AnyJSON] = expense.splits.map { split in
                AnyJSON.object([
                    "user_id": .string(split.userID.uuidString),
                    "amount_owed": .string(Self.decimalString(split.amountOwed)),
                    "split_type": .string(split.splitTypeRaw),
                ])
            }

            do {
                try await client.rpc("create_expense_with_payments_and_splits", params: [
                    "p_expense":  AnyJSON.object(expensePayload),
                    "p_payments": AnyJSON.array(paymentsPayload),
                    "p_splits":   AnyJSON.array(splitsPayload),
                ]).execute()
                expense.pushedWriteID = expense.writeID
                for payment in expense.payments { payment.pushedWriteID = payment.writeID }
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

import Foundation
import SwiftData
import Supabase
import os

private let syncLog = Logger(subsystem: "com.example.tab", category: "sync")

private struct ExpensePaymentRemoteKey: Hashable, Sendable {
    let expenseID: UUID
    let tripPersonID: UUID
}

private struct ExpenseSplitRemoteKey: Hashable, Sendable {
    let expenseID: UUID
    let tripPersonID: UUID
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
        #if DEBUG
        if auth?.isUsingMockAuth == true { return false }
        #endif
        guard let session = client.auth.currentSession,
              !session.isExpired,
              let currentUserID = auth?.currentUser?.id else {
            return false
        }
        return session.user.id == currentUserID
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

    func claimTripPeopleForCurrentEmail() async {
        guard hasRealSession else { return }
        do {
            try await client
                .rpc("claim_trip_people_for_current_email")
                .execute()
        } catch {
            syncLog.error("trip people claim failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func addTripPerson(tripID: UUID, email: String, displayName: String? = nil) async throws {
        try await ensureTripUploaded(tripID: tripID)

        let personID = UUID()
        let row: TripPersonDTO = try await client
            .rpc("add_trip_person_by_email", params: [
                "p_trip_id": AnyJSON.string(tripID.uuidString),
                "p_email": AnyJSON.string(email),
                "p_display_name": displayName.map { AnyJSON.string($0) } ?? .null,
                "p_person_id": AnyJSON.string(personID.uuidString),
            ])
            .execute()
            .value

        let ctx = container.mainContext
        try upsertTripPerson(row, in: ctx)
        try ctx.save()
    }

    func suggestTripPeople(query: String? = nil) async throws -> [TripPersonSuggestionDTO] {
        guard hasRealSession else { return [] }
        return try await client
            .rpc("suggest_trip_people", params: [
                "p_query": query.map { AnyJSON.string($0) } ?? .null,
                "p_limit": AnyJSON.integer(12),
            ])
            .execute()
            .value
    }

    // MARK: - Pull

    func pullAll() async {
        guard hasRealSession else { return }
        phase = .pulling
        do {
            let profileIDs = try await pullProfiles()
            let tripIDs = try await pullTrips()
            let tripPersonIDs = try await pullTripPeople()
            let categoryIDs = try await pullCategories()
            let expenseIDs = try await pullExpenses()
            let expensePaymentKeys = try await pullExpensePayments()
            let expenseSplitKeys = try await pullExpenseSplits()
            let settlementIDs = try await pullSettlements()
            try reconcileLocalRows(
                remoteProfileIDs: profileIDs,
                remoteTripIDs: tripIDs,
                remoteTripPersonIDs: tripPersonIDs,
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

    private func pullTripPeople() async throws -> Set<UUID> {
        let rows: [TripPersonDTO] = try await client
            .from("trip_people")
            .select()
            .execute()
            .value

        let ctx = container.mainContext
        for dto in rows {
            try upsertTripPerson(dto, in: ctx)
        }
        try ctx.save()
        return Set(rows.map(\.id))
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
        return Set(rows.map { ExpensePaymentRemoteKey(expenseID: $0.expenseID, tripPersonID: $0.tripPersonID) })
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
        return Set(rows.map { ExpenseSplitRemoteKey(expenseID: $0.expenseID, tripPersonID: $0.tripPersonID) })
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
        remoteTripPersonIDs: Set<UUID>,
        remoteCategoryIDs: Set<UUID>,
        remoteExpenseIDs: Set<UUID>,
        remoteExpensePaymentKeys: Set<ExpensePaymentRemoteKey>,
        remoteExpenseSplitKeys: Set<ExpenseSplitRemoteKey>,
        remoteSettlementIDs: Set<UUID>
    ) throws {
        let ctx = container.mainContext

        for payment in try ctx.fetch(FetchDescriptor<PaymentEntity>()) {
            guard payment.pushedWriteID != nil, let expenseID = payment.expense?.id else { continue }
            if !remoteExpensePaymentKeys.contains(ExpensePaymentRemoteKey(expenseID: expenseID, tripPersonID: payment.tripPersonID)) {
                ctx.delete(payment)
            }
        }

        for split in try ctx.fetch(FetchDescriptor<ExpenseSplitEntity>()) {
            guard split.pushedWriteID != nil, let expenseID = split.expense?.id else { continue }
            if !remoteExpenseSplitKeys.contains(ExpenseSplitRemoteKey(expenseID: expenseID, tripPersonID: split.tripPersonID)) {
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

        for person in try ctx.fetch(FetchDescriptor<TripPersonEntity>()) {
            guard person.pushedWriteID != nil else { continue }
            if !remoteTripPersonIDs.contains(person.id) {
                ctx.delete(person)
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

    private func upsertTripPerson(_ dto: TripPersonDTO, in ctx: ModelContext) throws {
        let tripID = dto.tripID
        let id = dto.id

        let trip = try ctx.fetch(FetchDescriptor<TripEntity>(
            predicate: #Predicate { $0.id == tripID }
        )).first

        guard let trip else { return }

        let existing = try ctx.fetch(FetchDescriptor<TripPersonEntity>(
            predicate: #Predicate { $0.id == id }
        )).first
        if let entity = existing {
            if entity.writeID == dto.writeID { return }
            entity.userID = dto.userID
            entity.email = dto.email
            entity.displayName = dto.displayName
            entity.invitedByID = dto.invitedBy
            entity.joinedAt = dto.joinedAt
            entity.createdAt = dto.createdAt
            entity.updatedAt = dto.updatedAt
            entity.writeID = dto.writeID
            entity.pushedWriteID = dto.writeID
        } else {
            ctx.insert(TripPersonEntity(
                id: dto.id,
                userID: dto.userID,
                email: dto.email,
                displayName: dto.displayName,
                invitedByID: dto.invitedBy,
                trip: trip,
                joinedAt: dto.joinedAt,
                createdAt: dto.createdAt,
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
            entity.paymentMethodRaw = dto.paymentMethod
            entity.createdByID = dto.createdBy
            entity.lastEditedByID = dto.lastEditedBy
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
                paymentMethodRaw: dto.paymentMethod,
                createdByID: dto.createdBy,
                lastEditedByID: dto.lastEditedBy,
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
        let tripPersonID = dto.tripPersonID
        let expense = try ctx.fetch(FetchDescriptor<ExpenseEntity>(
            predicate: #Predicate { $0.id == expenseID }
        )).first
        guard let expense else { return }

        let existing = expense.payments.first(where: { $0.tripPersonID == tripPersonID })
        if let entity = existing {
            if entity.writeID == dto.writeID { return }
            entity.amountPaid = dto.amountPaid
            entity.paymentModeRaw = dto.paymentMode
            entity.updatedAt = dto.updatedAt
            entity.writeID = dto.writeID
            entity.pushedWriteID = dto.writeID
        } else {
            ctx.insert(PaymentEntity(
                tripPersonID: dto.tripPersonID,
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
        let tripPersonID = dto.tripPersonID
        let expense = try ctx.fetch(FetchDescriptor<ExpenseEntity>(
            predicate: #Predicate { $0.id == expenseID }
        )).first
        guard let expense else { return }

        let existing = expense.splits.first(where: { $0.tripPersonID == tripPersonID })
        if let entity = existing {
            if entity.writeID == dto.writeID { return }
            entity.amountOwed = dto.amountOwed
            entity.splitTypeRaw = dto.splitType
            entity.updatedAt = dto.updatedAt
            entity.writeID = dto.writeID
            entity.pushedWriteID = dto.writeID
        } else {
            ctx.insert(ExpenseSplitEntity(
                tripPersonID: dto.tripPersonID,
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
            entity.fromPersonID = dto.fromPersonID
            entity.toPersonID = dto.toPersonID
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
                fromPersonID: dto.fromPersonID,
                toPersonID: dto.toPersonID,
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
        guard let currentUserID = auth?.currentUser?.id else { return }
        let dirty = try ctx.fetch(FetchDescriptor<ProfileEntity>())
            .filter { $0.id == currentUserID && $0.pushedWriteID != $0.writeID }
        guard !dirty.isEmpty else { return }

        for profile in dirty {
            do {
                try await ensureCurrentProfile(profile)
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
        try await ensureCurrentProfile(profile)
    }

    private func ensureCurrentProfile(_ profile: ProfileEntity) async throws {
        try await client
            .rpc("ensure_current_profile", params: [
                "p_display_name": AnyJSON.string(profile.displayName),
                "p_avatar_url": profile.avatarURL.map { AnyJSON.string($0) } ?? .null,
            ])
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
            guard let user = auth?.currentUser else { throw SyncError.signInRequired }
            let creatorPerson = trip.people.first { $0.userID == user.id }
            let person = creatorPerson ?? TripPersonEntity(
                userID: user.id,
                email: user.email.map(Self.normalizedEmail) ?? "\(user.id.uuidString.lowercased())@users.tab",
                displayName: user.displayName,
                invitedByID: user.id,
                trip: trip,
                joinedAt: .now
            )
            if creatorPerson == nil {
                container.mainContext.insert(person)
            }
            try await client
                .rpc("create_trip_with_self", params: [
                    "p_trip_id": AnyJSON.string(trip.id.uuidString),
                    "p_person_id": AnyJSON.string(person.id.uuidString),
                    "p_name": AnyJSON.string(trip.name),
                ])
                .execute()
            person.pushedWriteID = person.writeID
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
            if settlement.deletedAt != nil {
                if settlement.pushedWriteID == nil {
                    ctx.delete(settlement)
                } else {
                    do {
                        try await client
                            .from("settlements")
                            .update(SettlementDeleteUpdateDTO(
                                deletedAt: settlement.deletedAt,
                                updatedAt: settlement.updatedAt,
                                writeID: settlement.writeID
                            ))
                            .eq("id", value: settlement.id.uuidString)
                            .execute()
                        settlement.pushedWriteID = settlement.writeID
                    } catch {
                        syncLog.error("settlement delete push failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                continue
            }
            let insert = SettlementInsertDTO(
                id: settlement.id,
                tripID: settlement.trip?.id ?? UUID(),
                fromPersonID: settlement.fromPersonID,
                toPersonID: settlement.toPersonID,
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
                "payment_method": .string(expense.paymentMethodRaw),
                "created_by": .string(expense.createdByID.uuidString),
                "last_edited_by": expense.lastEditedByID.map { .string($0.uuidString) } ?? .null,
            ]

            let paymentsPayload: [AnyJSON] = expense.payments.map { payment in
                AnyJSON.object([
                    "trip_person_id": .string(payment.tripPersonID.uuidString),
                    "amount_paid": .string(Self.decimalString(payment.amountPaid)),
                    "payment_mode": .string(payment.paymentModeRaw),
                ])
            }

            let splitsPayload: [AnyJSON] = expense.splits.map { split in
                AnyJSON.object([
                    "trip_person_id": .string(split.tripPersonID.uuidString),
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

    private static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

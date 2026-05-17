import Foundation
import Supabase
import Realtime
import os

private let realtimeLog = Logger(subsystem: "com.rithwikshetty.tab", category: "realtime")

@MainActor
@Observable
final class RealtimeService {
    private let client = SupabaseClientProvider.shared
    private let sync: SyncService

    private(set) var subscribedTripID: UUID?
    private var channel: RealtimeChannelV2?
    private var streamTasks: [Task<Void, Never>] = []

    init(sync: SyncService) {
        self.sync = sync
    }

    /// Subscribe to live changes on the given trip's expenses/splits/settlements/members.
    /// Any change triggers a sync pull so local SwiftData stays in sync.
    func subscribe(to tripID: UUID) async {
        guard client.auth.currentSession != nil else { return }
        if subscribedTripID == tripID { return }
        await unsubscribe()

        let channel = client.channel("trip-\(tripID.uuidString)")
        let filter: RealtimePostgresFilter = .eq("trip_id", value: tripID.uuidString)

        let expenseStream = channel.postgresChange(
            AnyAction.self, schema: "public", table: "expenses", filter: filter
        )
        let settlementStream = channel.postgresChange(
            AnyAction.self, schema: "public", table: "settlements", filter: filter
        )
        let memberStream = channel.postgresChange(
            AnyAction.self, schema: "public", table: "trip_members", filter: filter
        )
        // expense_splits has no trip_id; gets updated via the parent expense pull.

        do {
            try await channel.subscribeWithError()
        } catch {
            realtimeLog.error("subscribe failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.channel = channel
        self.subscribedTripID = tripID

        streamTasks = [
            Task { [weak self] in
                for await _ in expenseStream { await self?.handleChange() }
            },
            Task { [weak self] in
                for await _ in settlementStream { await self?.handleChange() }
            },
            Task { [weak self] in
                for await _ in memberStream { await self?.handleChange() }
            },
        ]
    }

    func unsubscribe() async {
        guard let channel else { return }
        streamTasks.forEach { $0.cancel() }
        streamTasks.removeAll()
        await channel.unsubscribe()
        self.channel = nil
        self.subscribedTripID = nil
    }

    private func handleChange() async {
        realtimeLog.info("realtime change — pulling")
        await sync.pullAll()
    }
}

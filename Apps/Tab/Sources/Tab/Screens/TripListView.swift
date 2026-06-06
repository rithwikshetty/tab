import SwiftUI
import SwiftData

struct TripListView: View {
    var onSelect: (UUID) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query(
        filter: #Predicate<TripEntity> { $0.deletedAt == nil },
        sort: \TripEntity.lastActivityAt,
        order: .reverse
    )
    private var trips: [TripEntity]

    @State private var showingNewTrip = false
    @State private var pendingDeletion: TripEntity?

    private var cards: [TripCard] {
        guard let userID = auth.currentUser?.id else { return [] }
        return trips.compactMap { trip in
            guard let currentPerson = trip.people.first(where: { $0.userID == userID }) else { return nil }
            return TripPresenter.card(
                from: trip,
                currentPersonID: currentPerson.id,
                currentUserDisplayName: auth.currentUser?.displayName
            )
        }
    }

    private var tripsByID: [UUID: TripEntity] {
        Dictionary(uniqueKeysWithValues: trips.map { ($0.id, $0) })
    }

    private var activeCards: [TripCard]    { cards.filter { !$0.isCompleted } }
    private var completedCards: [TripCard] { cards.filter {  $0.isCompleted } }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LargeTitle(title: "Trips")

                if trips.isEmpty {
                    EmptyTripsView()
                } else {
                    if !activeCards.isEmpty {
                        SectionHeaderText(title: "Active")
                        Card { tripRows(activeCards) }
                    }
                    if !completedCards.isEmpty {
                        SectionHeaderText(title: "Completed")
                        Card { tripRows(completedCards) }
                    }
                }

                Spacer(minLength: FloatingActionLayout.scrollBottomClearance)
            }
            .scrollIndicators(.hidden)
            .background(Sage.bg.ignoresSafeArea())
            .refreshable { await sync.pullAll() }

            Fab(systemImage: "plus", accessibilityIdentifier: "trips.addButton") { showingNewTrip = true }
                .floatingActionPlacement()
        }
        .sheet(isPresented: $showingNewTrip) {
            NewTripSheet()
        }
        .alert(
            "Delete trip?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { trip in
            Button("Delete", role: .destructive) { confirmDelete(trip) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { trip in
            Text("\"\(trip.name)\" will be removed for everyone. You can recover it for 30 days.")
        }
    }

    @ViewBuilder
    private func tripRows(_ cards: [TripCard]) -> some View {
        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
            SwipeToDeleteRow(
                onTap: { onSelect(card.id) },
                onTrigger: { requestDelete(for: card.id) }
            ) {
                TripCardRow(trip: card)
            }
            if index < cards.count - 1 { RowDivider() }
        }
    }

    private func requestDelete(for tripID: UUID) {
        guard let trip = tripsByID[tripID] else { return }
        pendingDeletion = trip
    }

    private func confirmDelete(_ trip: TripEntity) {
        pendingDeletion = nil
        Deletion.softDelete(trip: trip, in: context)
        Haptics.success()
        Task { await sync.pushPending() }
    }
}

private struct EmptyTripsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "suitcase")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Sage.textSecondary)
            Text("No trips yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Sage.text)
            Text("Tap + to start your first trip")
                .font(.system(size: 14))
                .foregroundStyle(Sage.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.bottom, 40)
    }
}

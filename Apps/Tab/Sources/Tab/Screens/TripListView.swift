import SwiftUI
import SwiftData

struct TripListView: View {
    var onSelect: (UUID) -> Void = { _ in }

    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query(
        filter: #Predicate<TripEntity> { $0.deletedAt == nil },
        sort: \TripEntity.lastActivityAt,
        order: .reverse
    )
    private var trips: [TripEntity]

    @Query private var profiles: [ProfileEntity]

    @State private var showingNewTrip = false

    private var profilesByID: [UUID: ProfileEntity] {
        Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    private var cards: [TripCard] {
        guard let userID = auth.currentUser?.id else { return [] }
        return trips.map { trip in
            TripPresenter.card(
                from: trip,
                currentUserID: userID,
                profileFor: { id in profilesByID[id] }
            )
        }
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
                        Card {
                            ForEach(Array(activeCards.enumerated()), id: \.element.id) { index, card in
                                Button { onSelect(card.id) } label: {
                                    TripCardRow(trip: card)
                                }
                                .buttonStyle(.plain)
                                if index < activeCards.count - 1 { RowDivider() }
                            }
                        }
                    }
                    if !completedCards.isEmpty {
                        SectionHeaderText(title: "Completed")
                        Card {
                            ForEach(Array(completedCards.enumerated()), id: \.element.id) { index, card in
                                Button { onSelect(card.id) } label: {
                                    TripCardRow(trip: card)
                                }
                                .buttonStyle(.plain)
                                if index < completedCards.count - 1 { RowDivider() }
                            }
                        }
                    }
                }

                Spacer(minLength: 120)
            }
            .scrollIndicators(.hidden)
            .refreshable { await sync.pullAll() }

            Fab(systemImage: "plus") { showingNewTrip = true }
                .padding(.trailing, 18)
                .padding(.bottom, 100)
        }
        .sheet(isPresented: $showingNewTrip) {
            NewTripSheet()
        }
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

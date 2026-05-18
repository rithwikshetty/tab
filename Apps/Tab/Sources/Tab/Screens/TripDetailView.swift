import SwiftUI
import SwiftData

struct TripDetailView: View {
    let tripID: UUID
    var onAddExpense: () -> Void = {}
    var onOpenExpense: (UUID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(RealtimeService.self) private var realtime
    @Environment(SyncService.self) private var sync

    @Query private var trips: [TripEntity]
    @Query private var categories: [CategoryEntity]

    @State private var segment: Int = 0
    @State private var showingPeople: Bool = false
    @State private var pendingDeletion: ExpenseEntity?

    init(
        tripID: UUID,
        onAddExpense: @escaping () -> Void = {},
        onOpenExpense: @escaping (UUID) -> Void = { _ in }
    ) {
        self.tripID = tripID
        self.onAddExpense = onAddExpense
        self.onOpenExpense = onOpenExpense
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
    }

    private var trip: TripEntity? { trips.first }

    private var categoriesByID: [UUID: CategoryEntity] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if let trip, trip.deletedAt == nil {
                content(for: trip)
            } else {
                MissingTripView { dismiss() }
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task(id: tripID) {
            await realtime.subscribe(to: tripID)
        }
        .onDisappear {
            Task { await realtime.unsubscribe() }
        }
        .alert(
            "Delete this expense?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { expense in
            Button("Delete", role: .destructive) { confirmDelete(expense) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("It will be removed from balances. You can recover it for 30 days.")
        }
    }

    @ViewBuilder
    private func content(for trip: TripEntity) -> some View {
        let userID = auth.currentUser?.id ?? UUID()
        let currentPersonID = trip.people.first(where: { $0.userID == userID })?.id ?? UUID()
        let peopleByID = Dictionary(uniqueKeysWithValues: trip.people.map { ($0.id, $0) })
        let memberCards = trip.people.sortedForDisplay(currentPersonID: currentPersonID).map { person -> MemberCard in
            if person.id == currentPersonID {
                return MemberCard(id: person.id, displayName: "You", avatarName: auth.currentUser?.displayName ?? person.displayName)
            }
            return MemberCard(id: person.id, displayName: person.displayName)
        }
        let summaries = BalancePresenter.summaries(
            expenses: trip.expenses,
            settlements: trip.settlements,
            people: trip.people,
            currentPersonID: currentPersonID,
            personFor: { id in peopleByID[id] }
        )
        let activeExpenses = trip.expenses.filter { $0.deletedAt == nil }
        let days = ExpenseListPresenter.days(
            expenses: activeExpenses,
            currentPersonID: currentPersonID,
            personFor: { id in peopleByID[id] },
            categoryFor: { id in id.flatMap { categoriesByID[$0] } }
        )

        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LargeTitle(title: trip.name)

                HStack(spacing: 0) {
                    AvatarGroup(
                        members: memberCards,
                        size: 44,
                        borderWidth: 3,
                        onAddTap: { showingPeople = true }
                    )
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 16)

                if summaries.isEmpty {
                    EmptyBalanceCard()
                } else {
                    ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                        BalanceCard(summary: summary)
                    }
                }

                Segmented(options: ["Expenses", "Balances"], selection: $segment)
                    .padding(.top, 2)
                    .padding(.bottom, 16)

                ZStack {
                    if segment == 0 {
                        expensesSection(days: days)
                            .transition(.opacity)
                    } else {
                        balancesSection(summaries: summaries)
                            .transition(.opacity)
                    }
                }
                .animation(.snappy(duration: 0.18), value: segment)

                Spacer(minLength: 160)
            }
            .scrollIndicators(.hidden)
            .refreshable { await sync.pullAll() }

            Fab(
                label: "Add expense",
                systemImage: "plus",
                accessibilityIdentifier: "trip.addExpenseButton",
                action: onAddExpense
            )
                .padding(.trailing, 18)
                .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingPeople) {
            TripPeopleSheet(tripID: trip.id, tripName: trip.name)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func expensesSection(days: [ExpenseDay]) -> some View {
        if days.isEmpty {
            VStack(spacing: 6) {
                Text("No expenses yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Sage.text)
                Text("Tap + to log your first one")
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
        } else {
            VStack(spacing: 0) {
                ForEach(days) { day in
                    Text(day.dateLabel.uppercased())
                        .font(.dateHeader)
                        .tracking(1.32)
                        .foregroundStyle(Sage.textSecondary)
                        .padding(.horizontal, 26)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 0) {
                        ForEach(Array(day.expenses.enumerated()), id: \.element.id) { index, item in
                            SwipeToDeleteRow(
                                onTap: {
                                    Haptics.light()
                                    onOpenExpense(item.id)
                                },
                                onTrigger: { requestDelete(for: item.id) }
                            ) {
                                ExpenseRow(item: item)
                            }
                            if index < day.expenses.count - 1 { RowDivider() }
                        }
                    }
                    .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Sage.cardBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                }
            }
        }
    }

    @ViewBuilder
    private func balancesSection(summaries: [BalanceSummary]) -> some View {
        if summaries.isEmpty {
            VStack(spacing: 6) {
                Text("Everyone's settled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Sage.text)
                Text("Balances will appear here once you have expenses")
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 24)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(summary.label + " · " + summary.amount)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Sage.text)
                                .padding(.bottom, 4)
                            ForEach(summary.details) { detail in
                                HStack {
                                    Text(detail.counterparty)
                                        .font(.balanceDetail)
                                        .foregroundStyle(Sage.text.opacity(0.78))
                                    Spacer()
                                    Text(detail.amount)
                                        .font(.balanceDetail.weight(.semibold))
                                        .foregroundStyle(Sage.text)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
    }
}

extension TripDetailView {
    fileprivate func requestDelete(for expenseID: UUID) {
        guard
            let trip,
            let expense = trip.expenses.first(where: { $0.id == expenseID && $0.deletedAt == nil })
        else { return }
        pendingDeletion = expense
    }

    fileprivate func confirmDelete(_ expense: ExpenseEntity) {
        pendingDeletion = nil
        Deletion.softDelete(expense: expense, in: context)
        Haptics.success()
        Task { await sync.pushPending() }
    }
}

private struct MissingTripView: View {
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(Sage.textSecondary)
            Text("Trip not found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Sage.text)
            Button("Back to trips") { onBack() }
                .font(.system(size: 15))
                .foregroundStyle(Sage.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

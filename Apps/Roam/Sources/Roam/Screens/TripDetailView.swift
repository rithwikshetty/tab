import SwiftUI
import SwiftData

struct TripDetailView: View {
    let tripID: UUID
    var onAddExpense: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(RealtimeService.self) private var realtime
    @Environment(SyncService.self) private var sync

    @Query private var trips: [TripEntity]
    @Query private var profiles: [ProfileEntity]
    @Query private var categories: [CategoryEntity]

    @State private var segment: Int = 0

    init(tripID: UUID, onAddExpense: @escaping () -> Void = {}) {
        self.tripID = tripID
        self.onAddExpense = onAddExpense
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
    }

    private var trip: TripEntity? { trips.first }

    private var profilesByID: [UUID: ProfileEntity] {
        Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    private var categoriesByID: [UUID: CategoryEntity] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if let trip {
                content(for: trip)
            } else {
                MissingTripView { dismiss() }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .medium))
                        Text("Trips")
                            .font(.navLink)
                            .tracking(-0.07)
                    }
                    .foregroundStyle(Sage.accent)
                }
            }
        }
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task(id: tripID) {
            await realtime.subscribe(to: tripID)
        }
        .onDisappear {
            Task { await realtime.unsubscribe() }
        }
    }

    @ViewBuilder
    private func content(for trip: TripEntity) -> some View {
        let userID = auth.currentUser?.id ?? UUID()
        let memberCards = trip.members.map { m -> MemberCard in
            if m.userID == userID {
                MemberCard(id: m.userID, displayName: "You")
            } else {
                MemberCard(id: m.userID, displayName: profilesByID[m.userID]?.displayName ?? "Member")
            }
        }
        let summaries = BalancePresenter.summaries(
            expenses: trip.expenses,
            settlements: trip.settlements,
            members: trip.members,
            currentUserID: userID,
            profileFor: { id in profilesByID[id] }
        )
        let activeExpenses = trip.expenses.filter { $0.deletedAt == nil }
        let days = ExpenseListPresenter.days(
            expenses: activeExpenses,
            currentUserID: userID,
            profileFor: { id in profilesByID[id] },
            categoryFor: { id in id.flatMap { categoriesByID[$0] } }
        )

        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LargeTitle(title: trip.name)

                HStack(spacing: 0) {
                    AvatarGroup(members: memberCards, size: 44, borderWidth: 3, showAddButton: true)
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

                if segment == 0 {
                    expensesSection(days: days)
                } else {
                    balancesSection(summaries: summaries)
                }

                Spacer(minLength: 160)
            }
            .scrollIndicators(.hidden)
            .refreshable { await sync.pullAll() }

            Fab(label: "Add expense", systemImage: "plus", action: onAddExpense)
                .padding(.trailing, 18)
                .padding(.bottom, 24)
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
                            ExpenseRow(item: item)
                            if index < day.expenses.count - 1 { RowDivider() }
                        }
                    }
                    .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Sage.cardBorder, lineWidth: 1)
                    )
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

private struct ExpenseRow: View {
    let item: ExpenseRowItem

    private var tone: Color {
        guard let id = item.categoryID else { return Sage.text }
        return DefaultCategories.tone(for: id)
    }

    var body: some View {
        HStack(spacing: 14) {
            phosphorIcon(named: item.icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(tone)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.expenseName)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                    .lineLimit(1)
                Text("Paid by \(item.payerName) · your share \(item.yourShare)")
                    .font(.expenseMeta)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            Text(item.totalAmount)
                .font(.expenseAmount)
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
                .monospacedDigit()
            Chevron(size: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

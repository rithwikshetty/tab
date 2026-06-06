import SwiftUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

struct TripDetailView: View {
    let tripID: UUID
    var onAddExpense: () -> Void = {}
    var onOpenExpense: (UUID) -> Void = { _ in }
    var onSettleUp: () -> Void = {}
    var onOpenSettlement: (UUID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(RealtimeService.self) private var realtime
    @Environment(SyncService.self) private var sync

    @Query private var trips: [TripEntity]
    @Query private var categories: [CategoryEntity]
    @Query private var muteRows: [TripMuteEntity]

    @State private var segment: Int = 0
    @State private var showingPeople: Bool = false
    @State private var pendingDeletion: ExpenseEntity?
    @State private var pendingSettlementDeletion: SettlementEntity?
    @State private var showingEditDetails: Bool = false

    init(
        tripID: UUID,
        onAddExpense: @escaping () -> Void = {},
        onOpenExpense: @escaping (UUID) -> Void = { _ in },
        onSettleUp: @escaping () -> Void = {},
        onOpenSettlement: @escaping (UUID) -> Void = { _ in }
    ) {
        self.tripID = tripID
        self.onAddExpense = onAddExpense
        self.onOpenExpense = onOpenExpense
        self.onSettleUp = onSettleUp
        self.onOpenSettlement = onOpenSettlement
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
        _muteRows = Query(filter: #Predicate<TripMuteEntity> { $0.tripID == tripID })
    }

    private var trip: TripEntity? { trips.first }

    private var isMuted: Bool { muteRows.first?.isMuted ?? false }

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
        .toolbarBackground(.hidden, for: .navigationBar)
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
        .alert(
            "Delete this settlement?",
            isPresented: Binding(
                get: { pendingSettlementDeletion != nil },
                set: { if !$0 { pendingSettlementDeletion = nil } }
            ),
            presenting: pendingSettlementDeletion
        ) { settlement in
            Button("Delete", role: .destructive) { confirmDeleteSettlement(settlement) }
            Button("Cancel", role: .cancel) { pendingSettlementDeletion = nil }
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
        let days = TimelinePresenter.days(
            expenses: trip.expenses,
            settlements: trip.settlements,
            currentPersonID: currentPersonID,
            personFor: { id in peopleByID[id] },
            categoryFor: { id in id.flatMap { categoriesByID[$0] } }
        )
        let overview = OverviewPresenter.overview(
            expenses: trip.expenses,
            currentPersonID: currentPersonID,
            personName: { id in peopleByID[id]?.displayName ?? "Member" },
            categoryName: { id in id.flatMap { categoriesByID[$0]?.name } ?? "Other" }
        )

        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                HStack(alignment: .center, spacing: 12) {
                    Text(trip.name)
                        .font(.largeTitle30)
                        .tracking(-0.75)
                        .foregroundStyle(Sage.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    AvatarGroup(
                        members: memberCards,
                        size: 34,
                        borderWidth: 2.5,
                        maxVisible: 5,
                        onAddTap: { showingPeople = true }
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 14)

                if summaries.isEmpty {
                    EmptyBalanceCard()
                } else {
                    ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                        BalanceCard(summary: summary)
                    }
                }

                Segmented(options: ["Expenses", "Balances", "Overview"], selection: $segment)
                    .padding(.top, 2)
                    .padding(.bottom, 16)

                ZStack {
                    if segment == 0 {
                        timelineSection(days: days)
                            .transition(.opacity)
                    } else if segment == 1 {
                        balancesSection(summaries: summaries)
                            .transition(.opacity)
                    } else {
                        OverviewView(state: overview)
                            .transition(.opacity)
                    }
                }
                .animation(.snappy(duration: 0.18), value: segment)

                Spacer(minLength: FloatingActionLayout.scrollBottomClearance)
            }
            .scrollIndicators(.hidden)
            .refreshable { await sync.pullAll() }

            Fab(
                label: "Add expense",
                systemImage: "plus",
                accessibilityIdentifier: "trip.addExpenseButton",
                action: onAddExpense
            )
                .floatingActionPlacement()
        }
        .sheet(isPresented: $showingPeople) {
            TripPeopleSheet(tripID: trip.id, tripName: trip.name)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingEditDetails) {
            EditTripSheet(tripID: trip.id)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditDetails = true
                    } label: {
                        Label("Edit details", systemImage: "pencil")
                    }
                    Button {
                        onSettleUp()
                    } label: {
                        Label("Settle up", systemImage: "arrow.right.arrow.left")
                    }
                    Button {
                        Haptics.light()
                        sync.setTripMuted(tripID: trip.id, muted: !isMuted)
                    } label: {
                        Label(
                            isMuted ? "Unmute notifications" : "Mute notifications",
                            systemImage: isMuted ? "bell.slash" : "bell"
                        )
                    }
                    ShareLink(
                        item: exportItem(for: trip),
                        preview: SharePreview("\(trip.name) Expenses")
                    ) {
                        Label("Export to Excel", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Sage.accent)
                        .frame(width: 32, height: 32)
                }
                .accessibilityIdentifier("tripDetail.actionsButton")
            }
        }
    }

    @ViewBuilder
    private func timelineSection(days: [TimelineDay]) -> some View {
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

                    ForEach(timelineBlocks(for: day.items)) { block in
                        switch block {
                        case .expenses(let expenseItems):
                            VStack(spacing: 0) {
                                ForEach(Array(expenseItems.enumerated()), id: \.element.id) { index, e in
                                    SwipeToDeleteRow(
                                        onTap: {
                                            Haptics.light()
                                            onOpenExpense(e.id)
                                        },
                                        onTrigger: { requestDelete(for: e.id) }
                                    ) {
                                        ExpenseRow(item: e)
                                    }
                                    if index < expenseItems.count - 1 { RowDivider() }
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

                        case .settlement(let s):
                            SwipeToDeleteRow(
                                onTap: {
                                    Haptics.light()
                                    onOpenSettlement(s.id)
                                },
                                onTrigger: { requestDeleteSettlement(for: s.id) }
                            ) {
                                SettlementRow(item: s)
                            }
                            .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Sage.Avatar.slate.opacity(0.18), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 18)
                            .padding(.bottom, 6)
                        }
                    }
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

private enum TimelineBlock: Identifiable {
    case expenses([ExpenseRowItem])
    case settlement(SettlementRowItem)

    var id: String {
        switch self {
        case .expenses(let items):
            "expenses-" + items.map(\.id.uuidString).joined(separator: "-")
        case .settlement(let item):
            "settlement-\(item.id.uuidString)"
        }
    }
}

extension TripDetailView {
    private func timelineBlocks(for items: [TimelineItem]) -> [TimelineBlock] {
        var blocks: [TimelineBlock] = []
        var expenseRun: [ExpenseRowItem] = []

        func flushExpenses() {
            guard !expenseRun.isEmpty else { return }
            blocks.append(.expenses(expenseRun))
            expenseRun = []
        }

        for item in items {
            switch item {
            case .expense(let expense):
                expenseRun.append(expense)
            case .settlement(let settlement):
                flushExpenses()
                blocks.append(.settlement(settlement))
            }
        }

        flushExpenses()
        return blocks
    }

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

    fileprivate func requestDeleteSettlement(for settlementID: UUID) {
        guard
            let trip,
            let settlement = trip.settlements.first(where: { $0.id == settlementID && $0.deletedAt == nil })
        else { return }
        pendingSettlementDeletion = settlement
    }

    fileprivate func confirmDeleteSettlement(_ settlement: SettlementEntity) {
        pendingSettlementDeletion = nil
        Deletion.softDelete(settlement: settlement, in: context)
        Haptics.success()
        Task { await sync.pushPending() }
    }

    fileprivate func exportItem(for trip: TripEntity) -> TripExportTransferable {
        let peopleByID = Dictionary(uniqueKeysWithValues: trip.people.map { ($0.id, $0) })
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let data = TripExporter.extractData(
            trip: trip,
            categories: categoriesByID,
            peopleByID: peopleByID
        )
        return TripExportTransferable(data: data)
    }
}

private struct TripExportTransferable: Transferable {
    let data: TripExporter.ExportData

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .xlsx) { item in
            SentTransferredFile(try TripExporter.generateXLSX(from: item.data))
        }
    }
}

private extension UTType {
    static var xlsx: UTType {
        UTType(filenameExtension: "xlsx")
            ?? UTType("org.openxmlformats.spreadsheetml.sheet")
            ?? .spreadsheet
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

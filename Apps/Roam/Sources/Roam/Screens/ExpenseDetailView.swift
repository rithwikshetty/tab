import SwiftUI
import SwiftData
import RoamCore

struct ExpenseDetailView: View {
    let expenseID: UUID
    var onDeleted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query private var expenses: [ExpenseEntity]
    @Query private var profiles: [ProfileEntity]
    @Query private var categories: [CategoryEntity]

    @State private var confirmDelete = false

    init(expenseID: UUID, onDeleted: @escaping () -> Void = {}) {
        self.expenseID = expenseID
        self.onDeleted = onDeleted
        _expenses = Query(filter: #Predicate<ExpenseEntity> { $0.id == expenseID })
    }

    private var expense: ExpenseEntity? { expenses.first }

    private var profilesByID: [UUID: ProfileEntity] {
        Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    private var categoriesByID: [UUID: CategoryEntity] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if let expense, expense.deletedAt == nil {
                content(for: expense)
            } else {
                MissingExpenseView { dismiss() }
            }
        }
        .background(Sage.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .medium))
                        Text(expense?.trip?.name ?? "Trip")
                            .font(.navLink)
                            .tracking(-0.07)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Sage.accent)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete expense", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Sage.accent)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Delete this expense?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It will be removed from balances. You can recover it for 30 days.")
        }
    }

    @ViewBuilder
    private func content(for expense: ExpenseEntity) -> some View {
        let userID = auth.currentUser?.id ?? UUID()
        let category = expense.categoryID.flatMap { categoriesByID[$0] }
        let categoryName = category?.name ?? "Other"
        let categoryTone = expense.categoryID.map { DefaultCategories.tone(for: $0) } ?? Sage.text
        let categoryIcon = category?.icon ?? "tag"

        let payerIsYou = expense.payerID == userID
        let payerName = payerIsYou
            ? "You"
            : (profilesByID[expense.payerID]?.displayName ?? "Member")
        let payerMember = MemberCard(id: expense.payerID, displayName: payerName)

        let splitRows = buildSplitRows(expense: expense, currentUserID: userID)
        let splitType = expense.splits.first?.splitType ?? .equal
        let participantCount = expense.splits.count

        let loggedByIsYou = expense.createdByID == userID
        let loggedByName = loggedByIsYou
            ? "You"
            : (profilesByID[expense.createdByID]?.displayName ?? "Member")

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock(
                    categoryName: categoryName,
                    categoryTone: categoryTone,
                    categoryIcon: categoryIcon,
                    description: expense.descriptionText
                )

                amountBlock(
                    amount: expense.amount,
                    currency: expense.currency,
                    date: expense.expenseDate
                )

                paidByCard(member: payerMember, isYou: payerIsYou)

                sectionLabel("Split")
                splitCard(rows: splitRows, splitType: splitType, count: participantCount, currency: expense.currency)

                sectionLabel("Details")
                detailsCard(
                    expense: expense,
                    loggedByName: loggedByName
                )

                deleteButton
                    .padding(.top, 18)
                    .padding(.bottom, 28)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func headerBlock(
        categoryName: String,
        categoryTone: Color,
        categoryIcon: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                phosphorIcon(named: categoryIcon)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(categoryTone)
                    .frame(width: 18, height: 18)
                Text(categoryName.uppercased())
                    .font(.sectionLabel)
                    .tracking(1.32)
                    .foregroundStyle(categoryTone)
            }

            Text(description)
                .font(.largeTitle30)
                .tracking(-0.75)
                .foregroundStyle(Sage.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func amountBlock(amount: Decimal, currency: String, date: Date) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TOTAL")
                    .font(.balanceLabel)
                    .tracking(1.10)
                    .foregroundStyle(Sage.accentStrong.opacity(0.85))
                Text(MoneyFormatter.format(amount, currency: currency))
                    .font(.balanceAmount)
                    .tracking(-0.85)
                    .foregroundStyle(Sage.accentStrong)
                    .monospacedDigit()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                Text(Self.dayFormatter.string(from: date))
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(Sage.text.opacity(0.85))
                Text(Self.monthYearFormatter.string(from: date).lowercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.88)
                    .foregroundStyle(Sage.textSecondary)
            }
            .padding(.top, 16)
            .padding(.trailing, 18)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Sage.accentGlow, .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)
                .offset(x: 40, y: -40)
                .allowsHitTesting(false)
        }
        .background(Sage.accentTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Sage.accentSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func paidByCard(member: MemberCard, isYou: Bool) -> some View {
        HStack(spacing: 12) {
            Avatar(initial: member.initial, tone: member.tone, size: 32, borderWidth: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("PAID BY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.32)
                    .foregroundStyle(Sage.textSecondary)
                Text(isYou ? "You paid the bill" : "\(member.displayName) paid the bill")
                    .font(.system(size: 14.5, weight: .medium))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func splitCard(
        rows: [SplitRowItem],
        splitType: SplitType,
        count: Int,
        currency: String
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                splitRow(row, currency: currency)
                if index < rows.count - 1 { RowDivider() }
            }
            RowDivider()
            HStack {
                Spacer()
                Text("\(splitTypeLabel(splitType)) · \(count) ways")
                    .font(.system(size: 11.5, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Sage.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func splitRow(_ row: SplitRowItem, currency: String) -> some View {
        HStack(spacing: 12) {
            Avatar(initial: row.member.initial, tone: row.member.tone, size: 26, borderWidth: 2)
            Text(row.member.displayName)
                .font(.system(size: 14, weight: row.isYou ? .semibold : .medium))
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
            Spacer()
            Text(MoneyFormatter.format(row.amount, currency: currency))
                .font(.system(size: 14, weight: row.isYou ? .semibold : .regular))
                .tracking(-0.07)
                .foregroundStyle(row.isYou ? Sage.text : Sage.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func detailsCard(expense: ExpenseEntity, loggedByName: String) -> some View {
        VStack(spacing: 0) {
            detailRow(label: "Date", value: Self.fullDateFormatter.string(from: expense.expenseDate))
            RowDivider()
            detailRow(label: "Logged by", value: loggedByName)
            RowDivider()
            detailRow(label: "Logged at", value: Self.timestampFormatter.string(from: expense.createdAt))
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.formRowLabel)
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
            Spacer()
            Text(value)
                .font(.formRowValue)
                .tracking(-0.07)
                .foregroundStyle(Sage.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var deleteButton: some View {
        Button {
            Haptics.light()
            confirmDelete = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                Text("Delete expense")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.07)
            }
            .foregroundStyle(Sage.warning)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Sage.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Sage.warning.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(1.32)
            .foregroundStyle(Sage.textSecondary)
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func splitTypeLabel(_ type: SplitType) -> String {
        switch type {
        case .equal: "equal"
        case .exact: "exact"
        case .percentage: "percentage"
        case .shares: "shares"
        case .adjustment: "adjustment"
        }
    }

    private func buildSplitRows(expense: ExpenseEntity, currentUserID: UUID) -> [SplitRowItem] {
        expense.splits
            .map { split -> SplitRowItem in
                let isYou = split.userID == currentUserID
                let name = isYou
                    ? "You"
                    : (profilesByID[split.userID]?.displayName ?? "Member")
                let member = MemberCard(id: split.userID, displayName: name)
                return SplitRowItem(
                    id: split.userID,
                    member: member,
                    amount: split.amountOwed,
                    isYou: isYou
                )
            }
            .sorted { lhs, rhs in
                if lhs.isYou != rhs.isYou { return lhs.isYou }
                return lhs.member.displayName.localizedCaseInsensitiveCompare(rhs.member.displayName) == .orderedAscending
            }
    }

    private func performDelete() {
        guard let expense else { return }
        expense.deletedAt = .now
        expense.updatedAt = .now
        expense.writeID = UUID()
        if let trip = expense.trip {
            trip.lastActivityAt = .now
            trip.updatedAt = .now
        }
        try? context.save()
        Haptics.success()
        onDeleted()
        dismiss()
        Task { await sync.pushPending() }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

private struct SplitRowItem: Identifiable, Hashable {
    let id: UUID
    let member: MemberCard
    let amount: Decimal
    let isYou: Bool
}

private struct MissingExpenseView: View {
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(Sage.textSecondary)
            Text("Expense not found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Sage.text)
            Button("Back") { onBack() }
                .font(.system(size: 15))
                .foregroundStyle(Sage.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

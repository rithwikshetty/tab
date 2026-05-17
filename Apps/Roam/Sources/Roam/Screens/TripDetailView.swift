import SwiftUI

struct TripDetailView: View {
    let trip: DemoTrip
    var onAddExpense: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var segment: Int = 0

    private let days = SampleData.lisbonExpenseDays
    private let balance = SampleData.lisbonBalance

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LargeTitle(title: trip.name)

                HStack(spacing: 0) {
                    AvatarGroup(members: trip.members, size: 44, borderWidth: 3, showAddButton: true)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 16)

                BalanceCard(
                    label: balance.label,
                    amount: balance.amount,
                    details: balance.details
                )

                Segmented(options: ["Expenses", "Balances"], selection: $segment)
                    .padding(.top, 2)
                    .padding(.bottom, 16)

                if segment == 0 {
                    expensesSection
                } else {
                    balancesPlaceholder
                }

                Spacer(minLength: 160)
            }
            .scrollIndicators(.hidden)

            Fab(label: "Add expense", systemImage: "plus", action: onAddExpense)
                .padding(.trailing, 18)
                .padding(.bottom, 100)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {}
                    .font(.navLink)
                    .foregroundStyle(Sage.accent)
            }
        }
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var expensesSection: some View {
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
                    ForEach(Array(day.expenses.enumerated()), id: \.element.id) { index, expense in
                        ExpenseRow(expense: expense)
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

    private var balancesPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-currency balances coming next.")
                .font(.system(size: 14))
                .foregroundStyle(Sage.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 16)
    }
}

private struct ExpenseRow: View {
    let expense: DemoExpense

    var body: some View {
        HStack(spacing: 12) {
            Text(expense.icon)
                .font(.system(size: 17))
                .frame(width: 36, height: 36)
                .background(Sage.iconBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.name)
                    .font(.expenseName)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                    .lineLimit(1)
                Text("Paid by \(expense.payerName) · your share \(expense.yourShare)")
                    .font(.expenseMeta)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            Text(expense.totalAmount)
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

#Preview {
    NavigationStack {
        TripDetailView(trip: SampleData.trips[0])
    }
    .background(Sage.bg)
}

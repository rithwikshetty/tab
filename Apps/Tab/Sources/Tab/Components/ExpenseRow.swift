import SwiftUI

struct ExpenseRow: View {
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
                if let sourceName = item.sourceName {
                    HStack(spacing: 6) {
                        Text(sourceName)
                        Text("·")
                        Text("Paid by \(item.payerName) · your share \(item.yourShare)")
                    }
                    .font(.expenseMeta)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                } else {
                    Text("Paid by \(item.payerName) · your share \(item.yourShare)")
                        .font(.expenseMeta)
                        .tracking(-0.07)
                        .foregroundStyle(Sage.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
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
        .contentShape(Rectangle())
    }
}

#Preview("Expense rows") {
    VStack(spacing: 0) {
        ExpenseRow(item: ExpenseRowItem(
            id: UUID(), categoryID: nil, icon: "ForkKnife",
            name: "Pizza dinner", payerName: "Alex", payerIsYou: false,
            yourShare: "€12.50", totalAmount: "€50.00"
        ))
        RowDivider()
        ExpenseRow(item: ExpenseRowItem(
            id: UUID(), categoryID: nil, icon: "Car",
            name: "Airport taxi", payerName: "You", payerIsYou: true,
            yourShare: "€8.00", totalAmount: "€32.00"
        ))
    }
    .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Sage.bg)
}

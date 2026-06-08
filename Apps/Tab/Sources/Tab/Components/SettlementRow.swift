import SwiftUI

struct SettlementRow: View {
    let item: SettlementRowItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Sage.Avatar.slate)
                .frame(width: 28, height: 28)
                .background(Sage.Avatar.slate.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.expenseMeta)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.textSecondary)
                    .lineLimit(1)
                if let sourceName = item.sourceName {
                    Text(sourceName)
                        .font(.system(size: 11))
                        .foregroundStyle(Sage.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(item.formattedAmount)
                .font(.expenseAmount)
                .tracking(-0.07)
                .foregroundStyle(Sage.Avatar.slate)
                .monospacedDigit()

            Chevron(size: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

#Preview("Settlement rows") {
    VStack(spacing: 0) {
        SettlementRow(item: SettlementRowItem(
            id: UUID(),
            fromName: "You",
            toName: "Alice",
            formattedAmount: "\u{20AC}5.00",
            text: "You settled with Alice"
        ))
        RowDivider()
        SettlementRow(item: SettlementRowItem(
            id: UUID(),
            fromName: "Alice",
            toName: "Bob",
            formattedAmount: "\u{20AC}22.50",
            text: "Alice settled with Bob"
        ))
    }
    .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Sage.Avatar.slate.opacity(0.25), lineWidth: 1)
    )
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Sage.bg)
}

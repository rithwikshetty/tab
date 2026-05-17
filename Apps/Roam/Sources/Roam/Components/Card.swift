import SwiftUI

struct Card<Content: View>: View {
    var horizontalPadding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Sage.cardBorder, lineWidth: 1)
            )
            .shadow(color: Sage.shadow, radius: 1, x: 0, y: 1)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 14)
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Sage.rowDivider)
            .frame(height: 1)
    }
}

#Preview("Card") {
    VStack(spacing: 0) {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("First row")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Sage.text)
                    Spacer()
                    Text("€12.50")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Sage.text)
                        .monospacedDigit()
                }
                .padding(14)
                RowDivider()
                HStack {
                    Text("Second row")
                        .font(.system(size: 13))
                        .foregroundStyle(Sage.textSecondary)
                    Spacer()
                    Text("€4.20")
                        .font(.system(size: 13))
                        .foregroundStyle(Sage.textSecondary)
                        .monospacedDigit()
                }
                .padding(14)
            }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Sage.bg)
}

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

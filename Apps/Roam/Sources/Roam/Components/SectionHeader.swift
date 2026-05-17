import SwiftUI

struct SectionHeaderText: View {
    let title: String
    var topPadding: CGFloat = 22

    var body: some View {
        Text(title.uppercased())
            .font(.sectionHeader)
            .tracking(1.32)
            .foregroundStyle(Sage.textSecondary)
            .padding(.horizontal, 26)
            .padding(.top, topPadding)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LargeTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle30)
            .tracking(-0.75)
            .foregroundStyle(Sage.text)
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

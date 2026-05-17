import SwiftUI

struct Chevron: View {
    var size: CGFloat = 12
    var color: Color = Sage.text
    var opacity: Double = 0.45

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: size * 0.85, weight: .medium))
            .foregroundStyle(color.opacity(opacity))
    }
}

#Preview("Chevron") {
    HStack(spacing: 24) {
        Chevron(size: 10)
        Chevron(size: 12)
        Chevron(size: 16)
        Chevron(size: 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Sage.bg)
}

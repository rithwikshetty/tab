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

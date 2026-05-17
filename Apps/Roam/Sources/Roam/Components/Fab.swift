import SwiftUI

struct Fab: View {
    var label: String? = nil
    var systemImage: String = "plus"
    var action: () -> Void = {}

    private var isCircle: Bool { label == nil }

    var body: some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: isCircle ? 22 : 18, weight: .medium))
                if let label {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.07)
                }
            }
            .foregroundStyle(.white)
            .frame(minWidth: 52, minHeight: 52)
            .padding(.horizontal, isCircle ? 0 : 20)
            .background(Sage.accent, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 8)
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Fab") {
    VStack(spacing: 32) {
        Fab(label: "Add expense", systemImage: "plus")
        Fab(systemImage: "plus")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Sage.bg)
}

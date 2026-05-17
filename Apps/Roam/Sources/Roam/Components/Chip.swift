import SwiftUI

struct CategoryChip: View {
    let category: DemoCategory
    let isActive: Bool
    var emojiOnly: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(category.icon)
                    .font(.system(size: 14))
                if !emojiOnly {
                    Text(category.name)
                        .font(.chip)
                        .tracking(-0.07)
                }
            }
            .padding(.horizontal, emojiOnly ? 10 : 12)
            .padding(.vertical, 8)
            .foregroundStyle(isActive ? .white : Sage.text)
            .background(isActive ? Sage.accent : Sage.surface, in: Capsule())
            .overlay(
                Capsule().stroke(isActive ? Sage.accent : Sage.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CurrencyPill: View {
    let code: String
    let symbol: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text("\(symbol) \(code)")
                    .font(.pill)
                    .tracking(-0.07)
                Text("▾")
                    .font(.system(size: 9))
                    .opacity(0.55)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(Sage.text)
            .background(Sage.surface2, in: Capsule())
            .overlay(Capsule().stroke(Sage.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

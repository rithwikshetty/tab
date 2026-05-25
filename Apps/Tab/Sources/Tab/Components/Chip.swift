import SwiftUI

struct CategoryChip: View {
    let category: CategoryOption
    let isActive: Bool
    var emojiOnly: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                phosphorIcon(named: category.icon)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(isActive ? .white : DefaultCategories.tone(for: category.id))
                    .frame(width: 20, height: 20)
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

func phosphorIcon(named name: String) -> Image {
    Image("Categories/\(name)")
}

struct CurrencyPill: View {
    let code: String
    let symbol: String
    var action: () -> Void = {}

    private var title: String {
        let normalizedCode = code.uppercased()
        let cleanedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedSymbol.isEmpty || cleanedSymbol.uppercased() == normalizedCode {
            return normalizedCode
        }
        return "\(cleanedSymbol) \(normalizedCode)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
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

struct DropdownPill: View {
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.pill)
                .tracking(-0.07)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.55)
                .padding(.leading, 2)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(Sage.text)
        .background(Sage.surface2, in: Capsule())
        .overlay(Capsule().stroke(Sage.cardBorder, lineWidth: 1))
    }
}

#Preview("Chips") {
    VStack(spacing: 20) {
        HStack(spacing: 8) {
            CategoryChip(
                category: CategoryOption(id: DefaultCategories.food.id, icon: "bowl-food", name: "Food & Drink"),
                isActive: true
            )
            CategoryChip(
                category: CategoryOption(id: DefaultCategories.transport.id, icon: "car-profile", name: "Transport"),
                isActive: false
            )
            CategoryChip(
                category: CategoryOption(id: DefaultCategories.lodging.id, icon: "bed", name: "Lodging"),
                isActive: false
            )
        }
        HStack(spacing: 8) {
            CategoryChip(
                category: CategoryOption(id: DefaultCategories.food.id, icon: "bowl-food", name: "Food"),
                isActive: true,
                emojiOnly: true
            )
            CategoryChip(
                category: CategoryOption(id: DefaultCategories.transport.id, icon: "car-profile", name: "Transport"),
                isActive: false,
                emojiOnly: true
            )
            CategoryChip(
                category: CategoryOption(id: DefaultCategories.lodging.id, icon: "bed", name: "Lodging"),
                isActive: false,
                emojiOnly: true
            )
            CategoryChip(
                category: CategoryOption(id: DefaultCategories.activities.id, icon: "mask-happy", name: "Activities"),
                isActive: false,
                emojiOnly: true
            )
            CategoryChip(
                category: CategoryOption(id: DefaultCategories.shopping.id, icon: "shopping-bag", name: "Shopping"),
                isActive: false,
                emojiOnly: true
            )
            CategoryChip(
                category: CategoryOption(id: DefaultCategories.other.id, icon: "tag", name: "Other"),
                isActive: false,
                emojiOnly: true
            )
        }
        HStack(spacing: 8) {
            CurrencyPill(code: "EUR", symbol: "€")
            CurrencyPill(code: "USD", symbol: "$")
            CurrencyPill(code: "GBP", symbol: "£")
            DropdownPill(title: "Card")
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Sage.bg)
}

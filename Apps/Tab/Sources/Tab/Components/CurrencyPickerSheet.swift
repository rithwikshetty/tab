import SwiftUI
import TabCore

struct CurrencyPickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var currencies: [CurrencyMetadata] {
        CurrencyCatalog.search(query)
    }

    var body: some View {
        NavigationStack {
            List(currencies) { currency in
                Button {
                    selection = currency.code
                    dismiss()
                } label: {
                    CurrencyPickerRow(
                        currency: currency,
                        isSelected: currency.code == CurrencyCatalog.normalizedCode(selection)
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Sage.surface)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Sage.bg)
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search code or name")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.navLinkBold)
                        .foregroundStyle(Sage.accent)
                }
            }
            .toolbarBackground(Sage.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct CurrencyPickerRow: View {
    let currency: CurrencyMetadata
    let isSelected: Bool

    private var symbolText: String {
        currency.symbol.uppercased() == currency.code ? currency.code : currency.symbol
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(symbolText)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Sage.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(currency.code)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                Text(currency.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Sage.accent)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

#Preview("Currency Picker") {
    CurrencyPickerSheet(selection: .constant("EUR"))
}

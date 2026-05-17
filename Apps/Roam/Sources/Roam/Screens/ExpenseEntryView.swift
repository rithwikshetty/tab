import SwiftUI

struct ExpenseEntryView: View {
    let trip: DemoTrip
    var onCancel: () -> Void = {}

    @State private var amountWhole: String = "85"
    @State private var amountFraction: String = "00"
    @State private var description: String = "Dinner at Ramiro"
    @State private var selectedCategory: UUID = SampleData.categories[0].id
    @State private var splitMode: Int = 0
    @State private var participants: [Participant] = [
        Participant(name: "You", share: "€28.33", isOn: true),
        Participant(name: "Anya", share: "€28.33", isOn: true),
        Participant(name: "Sam", share: "€28.34", isOn: true),
    ]

    private let categories = SampleData.categories

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                amountBlock

                TextField("Description", text: $description)
                    .textFieldStyle(.plain)
                    .font(.formRow)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)

                sectionLabel("Category")
                categoryChips

                sectionLabel("Details").padding(.top, 22)
                paidByRow
                splitRow

                participantsCard

                dateRow

                receiptPlaceholder

                Spacer(minLength: 32)
            }
        }
        .scrollIndicators(.hidden)
        .background(Sage.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
                    .font(.navLink)
                    .foregroundStyle(Sage.text)
            }
            ToolbarItem(placement: .principal) {
                Text("New expense")
                    .font(.navTitle)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", action: onCancel)
                    .font(.navLinkBold)
                    .foregroundStyle(Sage.accent)
            }
        }
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var amountBlock: some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(amountWhole + ".")
                    .font(.amountValue)
                    .tracking(-2.08)
                    .foregroundStyle(Sage.text)
                    .monospacedDigit()
                Text(amountFraction)
                    .font(.amountValue)
                    .tracking(-2.08)
                    .foregroundStyle(Sage.text.opacity(0.7))
                    .monospacedDigit()
            }
            Spacer()
            CurrencyPill(code: "EUR", symbol: "€")
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sage.rowDivider).frame(height: 1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(1.32)
            .foregroundStyle(Sage.textSecondary)
            .padding(.horizontal, 24)
            .padding(.top, 0)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    let isActive = category.id == selectedCategory
                    let isFirst = category.id == categories.first?.id
                    CategoryChip(
                        category: category,
                        isActive: isActive,
                        emojiOnly: !isFirst
                    ) {
                        selectedCategory = category.id
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 4)
        }
    }

    private var paidByRow: some View {
        HStack(spacing: 12) {
            Text("Paid by")
                .font(.formRowLabel)
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
            Spacer()
            HStack(spacing: 4) {
                Text("You")
                    .font(.formRowValue.weight(.medium))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                Chevron(size: 9)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sage.rowDivider).frame(height: 1)
        }
    }

    private var splitRow: some View {
        HStack(spacing: 14) {
            Text("Split")
                .font(.formRowLabel)
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
            Spacer()
            Segmented(
                options: ["Equal", "Exact"],
                selection: $splitMode,
                mini: true,
                horizontalPadding: 0
            )
            .frame(maxWidth: 180)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sage.rowDivider).frame(height: 1)
        }
    }

    private var participantsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(participants.enumerated()), id: \.element.id) { index, participant in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(participant.isOn ? Sage.accent : Sage.textSecondary.opacity(0.4), in: Circle())
                    Text(participant.name)
                        .font(.formRow.weight(.medium))
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                    Spacer()
                    Text(participant.share)
                        .font(.system(size: 13))
                        .tracking(-0.07)
                        .foregroundStyle(Sage.textSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture { participants[index].isOn.toggle() }
                if index < participants.count - 1 { RowDivider() }
            }
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var dateRow: some View {
        HStack(spacing: 12) {
            Text("Date")
                .font(.formRowLabel)
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
            Spacer()
            HStack(spacing: 4) {
                Text("Today, 14 May")
                    .font(.formRowValue.weight(.medium))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                Chevron(size: 9)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sage.rowDivider).frame(height: 1)
        }
    }

    private var receiptPlaceholder: some View {
        HStack(spacing: 6) {
            Text("＋").font(.system(size: 15, weight: .regular))
            Text("Add photo")
        }
        .font(.system(size: 13, weight: .medium))
        .tracking(-0.07)
        .foregroundStyle(Sage.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Sage.accentSoft, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 18)
    }
}

private struct Participant: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var share: String
    var isOn: Bool
}

#Preview {
    NavigationStack {
        ExpenseEntryView(trip: SampleData.trips[0])
    }
    .background(Sage.bg)
}

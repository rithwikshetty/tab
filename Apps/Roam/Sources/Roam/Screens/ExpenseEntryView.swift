import SwiftUI
import SwiftData
import RoamCore

struct ExpenseEntryView: View {
    let tripID: UUID
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query private var trips: [TripEntity]
    @Query private var profiles: [ProfileEntity]

    @Query(filter: #Predicate<CategoryEntity> { $0.isDefault && $0.deletedAt == nil })
    private var categories: [CategoryEntity]

    private var orderedCategories: [CategoryEntity] {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return DefaultCategories.all.compactMap { byID[$0.id] }
    }

    @State private var amountText: String = ""
    @State private var description: String = ""
    @State private var selectedCategoryID: UUID = DefaultCategories.food.id
    @State private var splitMode: Int = 0
    @State private var exactAmountTextByUserID: [UUID: String] = [:]
    @State private var participantSet: Set<UUID> = []
    @State private var currency: String = "EUR"
    @State private var expenseDate: Date = .now
    @FocusState private var amountFocused: Bool

    init(tripID: UUID, onDone: @escaping () -> Void = {}) {
        self.tripID = tripID
        self.onDone = onDone
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
    }

    private var trip: TripEntity? { trips.first }

    private var profilesByID: [UUID: ProfileEntity] {
        Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    private var totalAmount: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var selectedSplitType: SplitType {
        splitMode == 0 ? .equal : .exact
    }

    private var canSave: Bool {
        totalAmount > 0
            && !description.trimmingCharacters(in: .whitespaces).isEmpty
            && !participantSet.isEmpty
            && auth.currentUser != nil
            && computedSplits != nil
    }

    private var computedSplits: [ExpenseSplit]? {
        guard totalAmount > 0, !participantSet.isEmpty else { return nil }
        let participants = Array(participantSet)
        switch selectedSplitType {
        case .equal:
            return try? SplitCalculator.calculate(
                totalAmount: totalAmount,
                currency: currency,
                participants: participants,
                splitType: .equal
            )
        case .exact:
            guard let exactAmounts else { return nil }
            return try? SplitCalculator.calculate(
                totalAmount: totalAmount,
                currency: currency,
                participants: participants,
                splitType: .exact,
                exactAmounts: exactAmounts
            )
        case .percentage, .shares, .adjustment:
            return nil
        }
    }

    private var exactAmounts: [UUID: Decimal]? {
        guard selectedSplitType == .exact else { return nil }
        var amounts: [UUID: Decimal] = [:]
        for userID in participantSet {
            let raw = exactAmountTextByUserID[userID, default: ""].trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, let amount = decimalAmount(from: raw) else { return nil }
            amounts[userID] = amount
        }
        return amounts
    }

    private var exactEnteredTotal: Decimal {
        participantSet.reduce(Decimal(0)) { total, userID in
            total + (decimalAmount(from: exactAmountTextByUserID[userID, default: ""]) ?? 0)
        }
    }

    private var exactSplitFooter: (text: String, isValid: Bool)? {
        guard selectedSplitType == .exact, totalAmount > 0 else { return nil }
        let remaining = totalAmount - exactEnteredTotal
        if computedSplits != nil {
            return ("Exact total \(MoneyFormatter.format(exactEnteredTotal, currency: currency))", true)
        } else if remaining >= 0 {
            return ("Remaining \(MoneyFormatter.format(remaining, currency: currency))", false)
        } else {
            return ("Over by \(MoneyFormatter.format(-remaining, currency: currency))", false)
        }
    }

    private var participantRows: [ParticipantRow] {
        guard let trip, let userID = auth.currentUser?.id else { return [] }
        let splits = computedSplits ?? []
        return trip.members.map { member in
            let name = member.userID == userID
                ? "You"
                : (profilesByID[member.userID]?.displayName ?? "Member")
            let isOn = participantSet.contains(member.userID)
            let share = splits.first(where: { $0.participantID == member.userID })?.amountOwed ?? 0
            let shareText = isOn ? MoneyFormatter.format(share, currency: currency) : "—"
            return ParticipantRow(userID: member.userID, name: name, share: shareText, isOn: isOn)
        }
    }

    var body: some View {
        Group {
            if trip != nil {
                form
            } else {
                Color.clear.onAppear { onDone() }
            }
        }
        .background(Sage.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onDone)
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
                Button("Save") { save() }
                    .font(.navLinkBold)
                    .foregroundStyle(canSave ? Sage.accent : Sage.accent.opacity(0.4))
                    .disabled(!canSave)
            }
        }
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            if participantSet.isEmpty, let trip {
                participantSet = Set(trip.members.map(\.userID))
            }
            if selectedSplitType == .exact {
                seedMissingExactAmountsFromEqual()
            }
            amountFocused = true
        }
        .onChange(of: splitMode) { _, newValue in
            if newValue == 1 {
                seedMissingExactAmountsFromEqual()
            }
        }
        .onChange(of: participantSet) {
            if selectedSplitType == .exact {
                seedMissingExactAmountsFromEqual()
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 0) {
                amountBlock

                TextField("Description", text: $description)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .font(.formRow)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Sage.rowDivider).frame(height: 1)
                    }

                sectionLabel("Category")
                categoryChips

                sectionLabel("Details").padding(.top, 22)
                paidByRow
                splitRow

                participantsCard

                dateRow

                Spacer(minLength: 32)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var amountBlock: some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            TextField("0.00", text: $amountText)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .font(.amountValue)
                .tracking(-2.08)
                .foregroundStyle(Sage.text)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: amountText) { _, new in
                    amountText = sanitizeAmount(new)
                }

            Menu {
                ForEach(["EUR", "USD", "GBP", "JPY", "CHF"], id: \.self) { code in
                    Button(action: { currency = code }) {
                        Label(code, systemImage: code == currency ? "checkmark" : "")
                    }
                }
            } label: {
                CurrencyPill(code: currency, symbol: MoneyFormatter.currencySymbol(currency))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sage.rowDivider).frame(height: 1)
        }
    }

    private func sanitizeAmount(_ input: String) -> String {
        var cleaned = input.replacingOccurrences(of: ",", with: ".")
        cleaned = cleaned.filter { $0.isNumber || $0 == "." }
        let parts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let whole = String(parts[0])
            let frac = String(parts[1].prefix(2))
            return whole + "." + frac
        }
        return cleaned
    }

    private func decimalAmount(from input: String) -> Decimal? {
        Decimal(string: input.replacingOccurrences(of: ",", with: "."))
    }

    private func plainAmountString(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: amount as NSDecimalNumber) ?? NSDecimalNumber(decimal: amount).stringValue
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(1.32)
            .foregroundStyle(Sage.textSecondary)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(orderedCategories) { category in
                    let isActive = category.id == selectedCategoryID
                    CategoryChip(
                        category: category.asOption,
                        isActive: isActive,
                        emojiOnly: !isActive
                    ) {
                        Haptics.light()
                        selectedCategoryID = category.id
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
            ForEach(Array(participantRows.enumerated()), id: \.element.userID) { index, row in
                participantRow(row)
                if index < participantRows.count - 1 { RowDivider() }
            }

            if let footer = exactSplitFooter {
                RowDivider()
                Text(footer.text)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.07)
                    .foregroundStyle(footer.isValid ? Sage.textSecondary : Sage.warning)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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

    private func participantRow(_ row: ParticipantRow) -> some View {
        HStack(spacing: 12) {
            Button {
                toggleParticipant(row.userID)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        row.isOn ? Sage.accent : Sage.textSecondary.opacity(0.4),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)

            Text(row.name)
                .font(.formRow.weight(.medium))
                .tracking(-0.07)
                .foregroundStyle(Sage.text)

            Spacer()

            if selectedSplitType == .exact, row.isOn {
                TextField("0.00", text: Binding(
                    get: { exactAmountTextByUserID[row.userID, default: ""] },
                    set: { exactAmountTextByUserID[row.userID] = sanitizeAmount($0) }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13))
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
                .monospacedDigit()
                .frame(width: 88)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Sage.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )
            } else {
                Text(row.share)
                    .font(.system(size: 13))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func toggleParticipant(_ userID: UUID) {
        Haptics.light()
        if participantSet.contains(userID) {
            if participantSet.count > 1 {
                participantSet.remove(userID)
            }
        } else {
            participantSet.insert(userID)
        }
    }

    private func seedMissingExactAmountsFromEqual() {
        guard totalAmount > 0, !participantSet.isEmpty else { return }
        guard let splits = try? SplitCalculator.calculate(
            totalAmount: totalAmount,
            currency: currency,
            participants: Array(participantSet),
            splitType: .equal
        ) else { return }

        for split in splits {
            let current = exactAmountTextByUserID[split.participantID, default: ""]
            if current.trimmingCharacters(in: .whitespaces).isEmpty {
                exactAmountTextByUserID[split.participantID] = plainAmountString(split.amountOwed)
            }
        }
    }

    private var dateRow: some View {
        HStack(spacing: 12) {
            Text("Date")
                .font(.formRowLabel)
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
            Spacer()
            DatePicker("", selection: $expenseDate, displayedComponents: .date)
                .labelsHidden()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sage.rowDivider).frame(height: 1)
        }
    }

    private func save() {
        guard canSave, let trip, let user = auth.currentUser else { return }
        guard let splits = computedSplits else { return }

        let expense = ExpenseEntity(
            payerID: user.id,
            amount: totalAmount,
            currency: currency,
            categoryID: selectedCategoryID,
            descriptionText: description.trimmingCharacters(in: .whitespaces),
            expenseDate: expenseDate,
            createdByID: user.id,
            trip: trip
        )
        context.insert(expense)

        for split in splits {
            let entity = ExpenseSplitEntity(
                userID: split.participantID,
                amountOwed: split.amountOwed,
                splitTypeRaw: split.splitType.rawValue,
                expense: expense
            )
            context.insert(entity)
        }
        trip.lastActivityAt = .now
        trip.updatedAt = .now
        trip.writeID = UUID()

        try? context.save()
        Haptics.success()
        onDone()

        Task { await sync.pushPending() }
    }
}

private struct ParticipantRow: Hashable {
    let userID: UUID
    let name: String
    let share: String
    let isOn: Bool
}

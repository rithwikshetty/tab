import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import TabCore

struct ExpenseEntryView: View {
    let tripID: UUID

    @Environment(\.dismiss) private var dismiss
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
    @State private var isDatePickerPresented = false

    /// Empty = single-payer with the recorder paying the full amount (default).
    /// Non-empty = explicit ledger from PaymentSplitView. Sum must equal totalAmount.
    @State private var paymentEntries: [Payment] = []

    @State private var receiptPickerItem: PhotosPickerItem?
    @State private var receiptThumbnail: UIImage?
    @State private var receiptJPEG: Data?
    @State private var receiptError: String?
    @State private var isPreparingReceipt = false
    @State private var receiptLoadID = UUID()

    @FocusState private var descriptionFocused: Bool

    private enum Layout {
        static let hPad: CGFloat = 18
        static let cardHPad: CGFloat = 18
        static let cardInnerHPad: CGFloat = 16
        static let rowVPad: CGFloat = 14
        static let sectionGap: CGFloat = 22
        static let sectionLabelTop: CGFloat = 8
        static let sectionLabelBottom: CGFloat = 10
    }

    init(tripID: UUID) {
        self.tripID = tripID
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
            && paymentLedgerValid
            && !isPreparingReceipt
    }

    /// Empty ledger = OK (defaults to single-payer at save time).
    /// Non-empty ledger = sum must equal totalAmount.
    private var paymentLedgerValid: Bool {
        if paymentEntries.isEmpty { return true }
        let sum = paymentEntries.reduce(Decimal(0)) { $0 + $1.amountPaid }
        return sum == totalAmount
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
                Color.clear.onAppear { dismiss() }
            }
        }
        .background(Sage.bg.ignoresSafeArea())
        .navigationTitle("New expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .font(.navLinkBold)
                    .foregroundStyle(canSave ? Sage.accent : Sage.accent.opacity(0.4))
                    .disabled(!canSave)
                    .animation(.snappy(duration: 0.15), value: canSave)
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
        .onChange(of: receiptPickerItem) { _, newItem in
            guard let newItem else { return }
            loadReceipt(from: newItem)
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 0) {
                amountBlock
                hairline
                descriptionRow

                categoryChips
                    .padding(.top, Layout.sectionGap)

                Card(horizontalPadding: Layout.cardHPad) {
                    paymentSplitRow
                    RowDivider()
                    dateRow
                }
                .padding(.top, Layout.sectionGap)

                sectionLabel("Split between")
                participantsCard

                receiptSection

                Spacer(minLength: 24)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture { descriptionFocused = false }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Sage.rowDivider)
            .frame(height: 1)
    }

    private var amountBlock: some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            DecimalTextField(
                text: $amountText,
                placeholder: "0.00",
                font: .systemFont(ofSize: 52, weight: .light),
                textColor: UIColor(Sage.text),
                placeholderColor: UIColor(Sage.textSecondary.opacity(0.55)),
                alignment: .left,
                tintColor: UIColor(Sage.accent),
                becomeFirstResponderOnAppear: true,
                accessibilityIdentifier: "expense.amountField"
            )
            .frame(height: 62)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: amountText) { _, new in
                let sanitized = sanitizeAmount(new)
                if sanitized != new {
                    amountText = sanitized
                } else {
                    refreshEqualPaymentsForCurrentTotal()
                }
            }

            Menu {
                ForEach(["EUR", "USD", "GBP", "JPY", "CHF"], id: \.self) { code in
                    Button(action: {
                        withAnimation(.snappy(duration: 0.18)) { currency = code }
                    }) {
                        Label(code, systemImage: code == currency ? "checkmark" : "")
                    }
                }
            } label: {
                CurrencyPill(code: currency, symbol: MoneyFormatter.currencySymbol(currency))
            }
        }
        .padding(.horizontal, Layout.hPad)
        .padding(.top, 14)
        .padding(.bottom, 14)
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
            .padding(.horizontal, Layout.hPad)
            .padding(.top, Layout.sectionLabelTop)
            .padding(.bottom, Layout.sectionLabelBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var descriptionRow: some View {
        TextField("Description", text: $description)
            .focused($descriptionFocused)
            .accessibilityIdentifier("expense.descriptionField")
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .onSubmit { descriptionFocused = false }
            .font(.formRow)
            .tracking(-0.07)
            .foregroundStyle(Sage.text)
            .padding(.horizontal, Layout.hPad)
            .padding(.vertical, Layout.rowVPad)
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
                        withAnimation(.snappy(duration: 0.22)) {
                            selectedCategoryID = category.id
                        }
                    }
                }
            }
            .padding(.horizontal, Layout.hPad)
            .padding(.bottom, 4)
        }
    }

    private var paymentSplitRow: some View {
        NavigationLink {
            PaymentSplitView(
                tripID: tripID,
                totalAmount: totalAmount,
                currency: currency,
                payments: $paymentEntries,
                splitMode: $splitMode,
                participantSet: $participantSet,
                exactSplitAmountText: $exactAmountTextByUserID
            )
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 0) {
                        Text(paidByShortLabel)
                            .font(.formRow.weight(.semibold))
                            .tracking(-0.07)
                            .foregroundStyle(paymentLedgerValid ? Sage.accentStrong : Sage.warning)
                            .accessibilityIdentifier("expense.paidBySummary")
                        Text(" \u{00B7} ")
                            .font(.system(size: 13))
                            .foregroundStyle(Sage.textSecondary)
                        Text(splitTypeLabel)
                            .font(.formRow.weight(.medium))
                            .tracking(-0.07)
                            .foregroundStyle(Sage.text)
                    }
                    Text(splitSummarySubtitle)
                        .font(.system(size: 12.5))
                        .tracking(-0.07)
                        .foregroundStyle(Sage.textSecondary)
                }
                Spacer()
                Chevron(size: 9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Layout.rowVPad)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("expense.paidByRow")
        .disabled(totalAmount <= 0)
        .opacity(totalAmount > 0 ? 1 : 0.5)
    }

    private var paidByShortLabel: String {
        if paymentEntries.isEmpty { return "You" }
        if paymentEntries.count == 1, let only = paymentEntries.first {
            return only.payerID == auth.currentUser?.id
                ? "You"
                : (profilesByID[only.payerID]?.displayName ?? "Member")
        }
        return "\(paymentEntries.count) people"
    }

    private var splitTypeLabel: String {
        splitMode == 0 ? "Equal split" : "Exact split"
    }

    private var splitSummarySubtitle: String {
        let count = participantSet.count
        let payer = paidByShortLabel
        if !paymentLedgerValid {
            return "\(payer) paid \u{00B7} doesn't reconcile"
        }
        return "Split between \(count) \(count == 1 ? "person" : "people")"
    }

    private var dateRow: some View {
        Button {
            descriptionFocused = false
            isDatePickerPresented = true
        } label: {
            HStack(spacing: 12) {
                Text("Date")
                    .font(.formRowLabel)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                Spacer()
                Text(Self.expenseDateFormatter.string(from: expenseDate))
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Sage.accent)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, Layout.rowVPad)
        .contentShape(Rectangle())
        .popover(isPresented: $isDatePickerPresented) {
            InlineDatePicker(selection: $expenseDate, tintColor: UIColor(Sage.accent)) {
                isDatePickerPresented = false
            }
            .frame(width: 320, height: 324)
            .padding(12)
            .presentationCompactAdaptation(.popover)
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
                    .transition(.opacity)
            }
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, Layout.cardHPad)
        .padding(.bottom, 14)
        .animation(.snappy(duration: 0.2), value: selectedSplitType)
    }

    private var receiptSection: some View {
        VStack(spacing: 6) {
            if let thumb = receiptThumbnail {
                receiptThumbnailCard(thumb)
            } else {
                receiptPlaceholder
            }
            if let receiptError {
                Text(receiptError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Sage.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Layout.cardHPad)
        .padding(.top, 6)
        .padding(.bottom, 18)
        .animation(.snappy(duration: 0.2), value: receiptThumbnail != nil)
    }

    private var receiptPlaceholder: some View {
        let preparing = isPreparingReceipt
        return PhotosPicker(selection: $receiptPickerItem, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 6) {
                if preparing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Sage.accent)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(preparing ? "Preparing…" : "Add photo")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.07)
            }
            .foregroundStyle(Sage.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Sage.accentSoft, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
        .disabled(preparing)
    }

    private func receiptThumbnailCard(_ image: UIImage) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Receipt attached")
                    .font(.system(size: 14, weight: .medium))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                if let bytes = receiptJPEG?.count {
                    Text(byteString(bytes))
                        .font(.system(size: 12))
                        .foregroundStyle(Sage.textSecondary)
                }
            }

            Spacer(minLength: 8)

            PhotosPicker(selection: $receiptPickerItem, matching: .images, photoLibrary: .shared()) {
                Text("Replace")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Sage.accent)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.light()
                clearReceipt()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Sage.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Sage.surface2, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
    }

    private func byteString(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    private func loadReceipt(from item: PhotosPickerItem) {
        let loadID = UUID()
        receiptLoadID = loadID
        isPreparingReceipt = true
        receiptError = nil
        Task {
            defer {
                Task { @MainActor in
                    guard receiptLoadID == loadID else { return }
                    isPreparingReceipt = false
                }
            }
            guard let raw = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    guard receiptLoadID == loadID else { return }
                    receiptPickerItem = nil
                    receiptError = "Couldn't read photo."
                }
                return
            }
            do {
                let jpeg = try await Task.detached(priority: .userInitiated) {
                    try ReceiptStorage.prepareJPEG(from: raw)
                }.value
                let preview = UIImage(data: jpeg)
                await MainActor.run {
                    guard receiptLoadID == loadID else { return }
                    receiptJPEG = jpeg
                    receiptThumbnail = preview
                }
            } catch {
                await MainActor.run {
                    guard receiptLoadID == loadID else { return }
                    receiptPickerItem = nil
                    receiptError = (error as? LocalizedError)?.errorDescription ?? "Couldn't process image."
                    receiptJPEG = nil
                    receiptThumbnail = nil
                }
            }
        }
    }

    private func clearReceipt() {
        receiptLoadID = UUID()
        receiptPickerItem = nil
        receiptThumbnail = nil
        receiptJPEG = nil
        receiptError = nil
        isPreparingReceipt = false
    }

    private func participantRow(_ row: ParticipantRow) -> some View {
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                withAnimation(.snappy(duration: 0.18)) {
                    toggleParticipant(row.userID)
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        row.isOn ? Sage.accent : Sage.textSecondary.opacity(0.4),
                        in: Circle()
                    )
                    .scaleEffect(row.isOn ? 1.0 : 0.92)
                    .animation(.snappy(duration: 0.18), value: row.isOn)
            }
            .buttonStyle(.plain)

            Text(row.name)
                .font(.formRow.weight(.medium))
                .tracking(-0.07)
                .foregroundStyle(Sage.text)

            Spacer()

            if selectedSplitType == .exact, row.isOn {
                InlineDecimalTextField(
                    text: Binding(
                        get: { exactAmountTextByUserID[row.userID, default: ""] },
                        set: { exactAmountTextByUserID[row.userID] = sanitizeAmount($0) }
                    ),
                    accessibilityIdentifier: "expense.splitAmount.\(row.userID.uuidString)"
                )
                .frame(width: 88, height: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
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
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func toggleParticipant(_ userID: UUID) {
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

    private func refreshEqualPaymentsForCurrentTotal() {
        guard totalAmount > 0, !paymentEntries.isEmpty else { return }
        guard paymentEntries.allSatisfy({ $0.paymentMode == .equal }) else { return }

        let payerIDs = paymentEntries.map(\.payerID)
        guard let recalculated = try? PaymentCalculator.calculate(
            totalAmount: totalAmount,
            currency: currency,
            payers: payerIDs,
            paymentMode: .equal
        ) else { return }
        paymentEntries = recalculated
    }

    private func save() {
        guard canSave, let trip, let user = auth.currentUser else { return }
        guard let splits = computedSplits else { return }

        let expenseID = UUID()
        let tripID = trip.id
        let receiptPath: String?
        if let receiptJPEG {
            do {
                receiptPath = try ReceiptStorage.persistPendingUpload(
                    jpeg: receiptJPEG,
                    tripID: tripID,
                    expenseID: expenseID
                )
            } catch {
                receiptError = (error as? LocalizedError)?.errorDescription ?? "Couldn't prepare receipt."
                return
            }
        } else {
            receiptPath = nil
        }

        let expense = ExpenseEntity(
            id: expenseID,
            amount: totalAmount,
            currency: currency,
            categoryID: selectedCategoryID,
            descriptionText: description.trimmingCharacters(in: .whitespaces),
            expenseDate: expenseDate,
            receiptStoragePath: receiptPath,
            createdByID: user.id,
            trip: trip
        )
        context.insert(expense)

        let payments = paymentEntries.isEmpty
            ? [Payment(payerID: user.id, amountPaid: totalAmount, paymentMode: .equal)]
            : paymentEntries
        for payment in payments {
            let entity = PaymentEntity(
                userID: payment.payerID,
                amountPaid: payment.amountPaid,
                paymentModeRaw: payment.paymentMode.rawValue,
                expense: expense
            )
            context.insert(entity)
        }

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

        dismiss()

        Task {
            if let receiptPath {
                try? await ReceiptStorage.uploadPendingReceipt(path: receiptPath)
            }
            await sync.pushPending()
        }
    }

    private static let expenseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct InlineDatePicker: UIViewRepresentable {
    @Binding var selection: Date
    let tintColor: UIColor
    let onSelection: () -> Void

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.tintColor = tintColor
        picker.setDate(selection, animated: false)
        picker.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        uiView.tintColor = tintColor
        if !Calendar.current.isDate(uiView.date, inSameDayAs: selection) {
            uiView.setDate(selection, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: InlineDatePicker

        init(parent: InlineDatePicker) {
            self.parent = parent
        }

        @MainActor
        @objc func valueChanged(_ picker: UIDatePicker) {
            let previousDate = parent.selection
            parent.selection = picker.date
            guard !Calendar.current.isDate(picker.date, inSameDayAs: previousDate) else { return }
            parent.onSelection()
        }
    }
}

private struct ParticipantRow: Hashable {
    let userID: UUID
    let name: String
    let share: String
    let isOn: Bool
}

struct InlineDecimalTextField: View {
    @Binding var text: String
    let accessibilityIdentifier: String

    var body: some View {
        TextField("0.00", text: $text)
            .keyboardType(.decimalPad)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Sage.text)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct DecimalTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: UIFont
    var textColor: UIColor
    var placeholderColor: UIColor
    var alignment: NSTextAlignment = .left
    var tintColor: UIColor
    var becomeFirstResponderOnAppear: Bool = false
    var accessibilityIdentifier: String? = nil

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.accessibilityIdentifier = accessibilityIdentifier
        tf.keyboardType = .decimalPad
        tf.font = font
        tf.textColor = textColor
        tf.textAlignment = alignment
        tf.tintColor = tintColor
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor, .font: font]
        )
        tf.delegate = context.coordinator
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )

        if becomeFirstResponderOnAppear {
            DispatchQueue.main.async {
                tf.becomeFirstResponder()
            }
        }
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.accessibilityIdentifier = accessibilityIdentifier
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DecimalTextField

        init(parent: DecimalTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ tf: UITextField) {
            parent.text = tf.text ?? ""
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
    }
}

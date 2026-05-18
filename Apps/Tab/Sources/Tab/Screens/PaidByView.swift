import SwiftUI
import SwiftData
import TabCore

struct PaidByView: View {
    let tripID: UUID
    let totalAmount: Decimal
    let currency: String
    @Binding var payments: [Payment]

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    @Query private var trips: [TripEntity]
    @Query private var profiles: [ProfileEntity]

    @State private var draft = PaidByDraft()
    @FocusState private var focusedPayerID: UUID?

    private enum Layout {
        static let hPad: CGFloat = 18
        static let cardHPad: CGFloat = 18
    }

    init(tripID: UUID, totalAmount: Decimal, currency: String, payments: Binding<[Payment]>) {
        self.tripID = tripID
        self.totalAmount = totalAmount
        self.currency = currency
        self._payments = payments
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
    }

    private var trip: TripEntity? { trips.first }

    private var profilesByID: [UUID: ProfileEntity] {
        Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    private var members: [UUID] {
        trip?.members.map(\.userID) ?? []
    }

    private var computedPayments: [Payment]? {
        draft.computedPayments(totalAmount: totalAmount, currency: currency)
    }

    private var reconcileFooter: (text: String, isValid: Bool)? {
        guard !draft.selectedPayerIDs.isEmpty, totalAmount > 0 else { return nil }
        switch draft.mode {
        case .equal:
            guard let payments = computedPayments else { return nil }
            let amounts = Set(payments.map(\.amountPaid))
            if amounts.count == 1, let amount = amounts.first {
                return ("Each pays \(MoneyFormatter.format(amount, currency: currency))", true)
            }
            return ("Equal total \(MoneyFormatter.format(totalAmount, currency: currency))", true)
        case .exact:
            let remaining = totalAmount - draft.enteredExactTotal
            if computedPayments != nil {
                return ("Exact total \(MoneyFormatter.format(draft.enteredExactTotal, currency: currency))", true)
            }
            if remaining >= 0 {
                return ("Remaining \(MoneyFormatter.format(remaining, currency: currency))", false)
            } else {
                return ("Over by \(MoneyFormatter.format(-remaining, currency: currency))", false)
            }
        default:
            return nil
        }
    }

    private var canSave: Bool {
        computedPayments != nil
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
        .navigationTitle("Paid by")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { commit() }
                    .font(.navLinkBold)
                    .foregroundStyle(canSave ? Sage.accent : Sage.accent.opacity(0.4))
                    .disabled(!canSave)
                    .animation(.snappy(duration: 0.15), value: canSave)
            }
        }
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { draft.seed(payments: payments, currentUserID: auth.currentUser?.id, members: members) }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 0) {
                totalRow
                hairline

                modeRow
                hairline

                payerCard

                Spacer(minLength: 24)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Sage.rowDivider)
            .frame(height: 1)
    }

    private var totalRow: some View {
        HStack {
            Text("Total")
                .font(.formRowLabel)
                .foregroundStyle(Sage.textSecondary)
            Spacer()
            Text(MoneyFormatter.format(totalAmount, currency: currency))
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Sage.text)
                .monospacedDigit()
        }
        .padding(.horizontal, Layout.hPad)
        .padding(.vertical, 16)
    }

    private var modeRow: some View {
        HStack(spacing: 12) {
            Text("Mode")
                .font(.formRowLabel)
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
            Spacer()
            Segmented(
                options: ["Equal", "Exact"],
                selection: Binding(
                    get: { draft.mode == .equal ? 0 : 1 },
                    set: { newValue in
                        let newMode: PaymentMode = newValue == 0 ? .equal : .exact
                        draft.setMode(newMode, totalAmount: totalAmount, currency: currency)
                        if newMode != .exact {
                            focusedPayerID = nil
                        }
                    }
                ),
                mini: true,
                horizontalPadding: 0
            )
            .frame(maxWidth: 180)
        }
        .padding(.horizontal, Layout.hPad)
        .padding(.vertical, 12)
    }

    private var payerCard: some View {
        VStack(spacing: 0) {
            ForEach(members, id: \.self) { userID in
                payerRow(userID: userID)
                if userID != members.last { RowDivider() }
            }
            if let footer = reconcileFooter {
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
        .padding(.top, 8)
        .animation(.snappy(duration: 0.2), value: draft.mode)
    }

    private func payerRow(userID: UUID) -> some View {
        let isOn = draft.selectedPayerIDs.contains(userID)
        let isYou = userID == auth.currentUser?.id
        let name = isYou ? "You" : (profilesByID[userID]?.displayName ?? "Member")
        let payment = computedPayments?.first(where: { $0.payerID == userID })
        let displayShare = isOn ? MoneyFormatter.format(payment?.amountPaid ?? 0, currency: currency) : "—"

        return HStack(spacing: 12) {
            Button {
                Haptics.light()
                withAnimation(.snappy(duration: 0.18)) {
                    togglePayer(userID)
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        isOn ? Sage.accent : Sage.textSecondary.opacity(0.4),
                        in: Circle()
                    )
                    .scaleEffect(isOn ? 1.0 : 0.92)
                    .animation(.snappy(duration: 0.18), value: isOn)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("paidBy.toggle.\(userID.uuidString)")
            .accessibilityLabel("Toggle payer \(name)")

            Text(name)
                .font(.formRow.weight(.medium))
                .tracking(-0.07)
                .foregroundStyle(Sage.text)

            Spacer()

            if draft.mode == .exact, isOn {
                InlineDecimalTextField(
                    text: Binding(
                        get: { draft.exactAmountTextByUserID[userID, default: ""] },
                        set: { draft.setExactAmount($0, for: userID) }
                    ),
                    accessibilityIdentifier: "paidBy.exactAmount.\(userID.uuidString)"
                )
                .frame(width: 88, height: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Sage.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )
                .focused($focusedPayerID, equals: userID)
            } else {
                Text(displayShare)
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

    private func togglePayer(_ userID: UUID) {
        draft.togglePayer(userID, totalAmount: totalAmount, currency: currency)
    }

    private func commit() {
        guard let computed = computedPayments else { return }
        payments = computed
        Haptics.light()
        dismiss()
    }
}

@Observable
private final class PaidByDraft {
    var mode: PaymentMode = .equal
    var selectedPayerIDs: Set<UUID> = []
    var exactAmountTextByUserID: [UUID: String] = [:]

    private var exactAmountsManuallyEdited = false
    private var hasSeeded = false

    var enteredExactTotal: Decimal {
        selectedPayerIDs.reduce(Decimal(0)) { total, userID in
            total + (Self.decimal(from: exactAmountTextByUserID[userID, default: ""]) ?? 0)
        }
    }

    func seed(payments: [Payment], currentUserID: UUID?, members: [UUID]) {
        guard !hasSeeded else { return }
        hasSeeded = true

        if payments.isEmpty {
            if let currentUserID {
                selectedPayerIDs = [currentUserID]
            } else if let first = members.first {
                selectedPayerIDs = [first]
            }
            mode = .equal
        } else {
            selectedPayerIDs = Set(payments.map(\.payerID))
            mode = payments.first?.paymentMode ?? .equal
            if mode == .exact {
                exactAmountsManuallyEdited = true
                for payment in payments {
                    exactAmountTextByUserID[payment.payerID] = Self.plainAmountString(payment.amountPaid)
                }
            }
        }
    }

    func setMode(_ newMode: PaymentMode, totalAmount: Decimal, currency: String) {
        mode = newMode
        if newMode == .exact {
            exactAmountsManuallyEdited = false
            seedExactFromEqual(totalAmount: totalAmount, currency: currency, overwriteExisting: true)
        }
    }

    func togglePayer(_ userID: UUID, totalAmount: Decimal, currency: String) {
        if selectedPayerIDs.contains(userID) {
            if selectedPayerIDs.count > 1 {
                selectedPayerIDs.remove(userID)
                exactAmountTextByUserID.removeValue(forKey: userID)
                if mode == .exact && !exactAmountsManuallyEdited {
                    seedExactFromEqual(totalAmount: totalAmount, currency: currency, overwriteExisting: true)
                }
            }
        } else {
            selectedPayerIDs.insert(userID)
            if mode == .exact {
                seedExactFromEqual(
                    totalAmount: totalAmount,
                    currency: currency,
                    overwriteExisting: !exactAmountsManuallyEdited
                )
            }
        }
    }

    func setExactAmount(_ input: String, for userID: UUID) {
        exactAmountsManuallyEdited = true
        exactAmountTextByUserID[userID] = Self.sanitize(input)
    }

    func computedPayments(totalAmount: Decimal, currency: String) -> [Payment]? {
        guard !selectedPayerIDs.isEmpty, totalAmount > 0 else { return nil }
        let payerList = Array(selectedPayerIDs)

        switch mode {
        case .equal:
            return try? PaymentCalculator.calculate(
                totalAmount: totalAmount,
                currency: currency,
                payers: payerList,
                paymentMode: .equal
            )
        case .exact:
            var amounts: [UUID: Decimal] = [:]
            for id in selectedPayerIDs {
                let raw = exactAmountTextByUserID[id, default: ""].trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty, let amount = Self.decimal(from: raw) else { return nil }
                amounts[id] = amount
            }
            return try? PaymentCalculator.calculate(
                totalAmount: totalAmount,
                currency: currency,
                payers: payerList,
                paymentMode: .exact,
                exactAmounts: amounts
            )
        case .percentage, .shares, .adjustment:
            return nil
        }
    }

    private func seedExactFromEqual(totalAmount: Decimal, currency: String, overwriteExisting: Bool) {
        guard !selectedPayerIDs.isEmpty, totalAmount > 0 else { return }
        guard let computed = try? PaymentCalculator.calculate(
            totalAmount: totalAmount,
            currency: currency,
            payers: Array(selectedPayerIDs),
            paymentMode: .equal
        ) else { return }

        exactAmountTextByUserID = exactAmountTextByUserID.filter { selectedPayerIDs.contains($0.key) }
        for payment in computed {
            let existing = exactAmountTextByUserID[payment.payerID, default: ""]
                .trimmingCharacters(in: .whitespaces)
            if overwriteExisting || existing.isEmpty {
                exactAmountTextByUserID[payment.payerID] = Self.plainAmountString(payment.amountPaid)
            }
        }
    }

    private static func sanitize(_ input: String) -> String {
        var cleaned = input.replacingOccurrences(of: ",", with: ".")
        cleaned = cleaned.filter { $0.isNumber || $0 == "." }
        let parts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            return String(parts[0]) + "." + String(parts[1].prefix(2))
        }
        return cleaned
    }

    private static func decimal(from input: String) -> Decimal? {
        Decimal(string: input.replacingOccurrences(of: ",", with: "."))
    }

    private static func plainAmountString(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: amount as NSDecimalNumber) ?? NSDecimalNumber(decimal: amount).stringValue
    }
}

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

    @State private var mode: PaymentMode = .equal
    @State private var selectedPayerIDs: Set<UUID> = []
    @State private var exactAmountTextByUserID: [UUID: String] = [:]

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

    private var enteredExactTotal: Decimal {
        selectedPayerIDs.reduce(Decimal(0)) { total, userID in
            total + (decimal(from: exactAmountTextByUserID[userID, default: ""]) ?? 0)
        }
    }

    private var computedPayments: [Payment]? {
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
                guard !raw.isEmpty, let amount = decimal(from: raw) else { return nil }
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

    private var reconcileFooter: (text: String, isValid: Bool)? {
        guard !selectedPayerIDs.isEmpty, totalAmount > 0 else { return nil }
        switch mode {
        case .equal:
            guard let payments = computedPayments else { return nil }
            let amounts = Set(payments.map(\.amountPaid))
            if amounts.count == 1, let amount = amounts.first {
                return ("Each pays \(MoneyFormatter.format(amount, currency: currency))", true)
            }
            return ("Equal total \(MoneyFormatter.format(totalAmount, currency: currency))", true)
        case .exact:
            let remaining = totalAmount - enteredExactTotal
            if computedPayments != nil {
                return ("Exact total \(MoneyFormatter.format(enteredExactTotal, currency: currency))", true)
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
        .onAppear { seed() }
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
                    get: { mode == .equal ? 0 : 1 },
                    set: { mode = $0 == 0 ? .equal : .exact }
                ),
                mini: true,
                horizontalPadding: 0
            )
            .frame(maxWidth: 180)
        }
        .padding(.horizontal, Layout.hPad)
        .padding(.vertical, 12)
        .onChange(of: mode) { _, newMode in
            if newMode == .exact { seedExactFromEqual() }
        }
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
        .animation(.snappy(duration: 0.2), value: mode)
    }

    private func payerRow(userID: UUID) -> some View {
        let isOn = selectedPayerIDs.contains(userID)
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

            Text(name)
                .font(.formRow.weight(.medium))
                .tracking(-0.07)
                .foregroundStyle(Sage.text)

            Spacer()

            if mode == .exact, isOn {
                DecimalTextField(
                    text: Binding(
                        get: { exactAmountTextByUserID[userID, default: ""] },
                        set: { exactAmountTextByUserID[userID] = sanitize($0) }
                    ),
                    placeholder: "0.00",
                    font: .systemFont(ofSize: 13),
                    textColor: UIColor(Sage.text),
                    placeholderColor: UIColor(Sage.textSecondary.opacity(0.5)),
                    alignment: .right,
                    tintColor: UIColor(Sage.accent)
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
        if selectedPayerIDs.contains(userID) {
            if selectedPayerIDs.count > 1 {
                selectedPayerIDs.remove(userID)
                exactAmountTextByUserID.removeValue(forKey: userID)
            }
        } else {
            selectedPayerIDs.insert(userID)
            if mode == .exact { seedExactFromEqual() }
        }
    }

    private func seed() {
        if payments.isEmpty {
            if let me = auth.currentUser?.id {
                selectedPayerIDs = [me]
            } else if let first = members.first {
                selectedPayerIDs = [first]
            }
            mode = .equal
        } else {
            selectedPayerIDs = Set(payments.map(\.payerID))
            mode = payments.first?.paymentMode ?? .equal
            if mode == .exact {
                for p in payments {
                    exactAmountTextByUserID[p.payerID] = plainAmountString(p.amountPaid)
                }
            }
        }
    }

    private func seedExactFromEqual() {
        guard !selectedPayerIDs.isEmpty, totalAmount > 0 else { return }
        guard let computed = try? PaymentCalculator.calculate(
            totalAmount: totalAmount,
            currency: currency,
            payers: Array(selectedPayerIDs),
            paymentMode: .equal
        ) else { return }
        for p in computed {
            let existing = exactAmountTextByUserID[p.payerID, default: ""].trimmingCharacters(in: .whitespaces)
            if existing.isEmpty {
                exactAmountTextByUserID[p.payerID] = plainAmountString(p.amountPaid)
            }
        }
    }

    private func commit() {
        guard let computed = computedPayments else { return }
        payments = computed
        Haptics.light()
        dismiss()
    }

    private func sanitize(_ input: String) -> String {
        var cleaned = input.replacingOccurrences(of: ",", with: ".")
        cleaned = cleaned.filter { $0.isNumber || $0 == "." }
        let parts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            return String(parts[0]) + "." + String(parts[1].prefix(2))
        }
        return cleaned
    }

    private func decimal(from input: String) -> Decimal? {
        Decimal(string: input.replacingOccurrences(of: ",", with: "."))
    }

    private func plainAmountString(_ amount: Decimal) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = false
        return f.string(from: amount as NSDecimalNumber) ?? NSDecimalNumber(decimal: amount).stringValue
    }
}

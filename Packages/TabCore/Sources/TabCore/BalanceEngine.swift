import Foundation

public struct UserBalance: Hashable, Sendable {
    public let forUser: UUID
    public let withUser: UUID
    public let currency: String
    public let amount: Decimal

    public init(forUser: UUID, withUser: UUID, currency: String, amount: Decimal) {
        self.forUser = forUser
        self.withUser = withUser
        self.currency = currency
        self.amount = amount
    }
}

public enum BalanceEngine {
    public static func compute(
        expenses: [Expense],
        settlements: [Settlement]
    ) -> [UserBalance] {
        var canonical: [PairKey: [String: Decimal]] = [:]

        for expense in expenses where expense.deletedAt == nil {
            let currency = expense.amount.currency
            distributePairs(for: expense).forEach { (pair, amount) in
                let key = PairKey(pair.creditor, pair.debtor)
                let signed = key.signedAmount(
                    creditor: pair.creditor,
                    debtor: pair.debtor,
                    amount: amount
                )
                canonical[key, default: [:]][currency, default: 0] += signed
            }
        }

        for settlement in settlements where settlement.deletedAt == nil {
            let currency = settlement.amount.currency
            let key = PairKey(settlement.fromUserID, settlement.toUserID)
            let signed = key.signedAmount(
                creditor: settlement.toUserID,
                debtor: settlement.fromUserID,
                amount: settlement.amount.amount
            )
            canonical[key, default: [:]][currency, default: 0] -= signed
        }

        var balances: [UserBalance] = []
        let orderedKeys = canonical.keys.sorted { lhs, rhs in
            if lhs.lo.uuidString != rhs.lo.uuidString {
                return lhs.lo.uuidString < rhs.lo.uuidString
            }
            return lhs.hi.uuidString < rhs.hi.uuidString
        }

        for key in orderedKeys {
            let byCurrency = canonical[key] ?? [:]
            for currency in byCurrency.keys.sorted() {
                let amount = byCurrency[currency] ?? 0
                guard amount != 0 else { continue }

                balances.append(UserBalance(
                    forUser: key.lo, withUser: key.hi, currency: currency, amount: amount
                ))
                balances.append(UserBalance(
                    forUser: key.hi, withUser: key.lo, currency: currency, amount: -amount
                ))
            }
        }
        return balances
    }

    /// For one expense, distribute its pair debts using net-per-user.
    /// Returns (creditor, debtor) → amount the debtor owes the creditor for this expense.
    /// Multi-payer formula: each debtor's shortfall is split across creditors proportionally
    /// to each creditor's surplus.
    static func distributePairs(for expense: Expense) -> [(pair: (creditor: UUID, debtor: UUID), amount: Decimal)] {
        var nets: [UUID: Decimal] = [:]
        for payment in expense.payments {
            nets[payment.payerID, default: 0] += payment.amountPaid
        }
        for split in expense.splits {
            nets[split.participantID, default: 0] -= split.amountOwed
        }

        var creditors: [(id: UUID, surplus: Decimal)] = []
        var debtors: [(id: UUID, shortfall: Decimal)] = []
        for (user, net) in nets {
            if net > 0 { creditors.append((user, net)) }
            else if net < 0 { debtors.append((user, -net)) }
        }
        let totalSurplus = creditors.reduce(Decimal(0)) { $0 + $1.surplus }
        guard totalSurplus > 0 else { return [] }

        // Deterministic ordering for reproducibility.
        creditors.sort { $0.id.uuidString < $1.id.uuidString }
        debtors.sort { $0.id.uuidString < $1.id.uuidString }

        // Shares are quantized to the expense currency's minor units so every
        // emitted balance is settleable: raw proportional shares are floored,
        // then the leftover minor units are distributed largest-fractional-
        // remainder first (lowest creditor UUID on ties), keeping each debtor's
        // distributed total exactly equal to their shortfall.
        let multiplier = CurrencyCatalog.minorUnitMultiplier(for: expense.amount.currency)

        var result: [(pair: (creditor: UUID, debtor: UUID), amount: Decimal)] = []
        for debtor in debtors {
            var sharesMinor: [Decimal] = []
            var fractions: [(index: Int, fraction: Decimal)] = []
            var allocatedMinor = Decimal(0)
            for (index, creditor) in creditors.enumerated() {
                let rawMinor = debtor.shortfall * creditor.surplus * multiplier / totalSurplus
                let floored = floorToInteger(rawMinor)
                sharesMinor.append(floored)
                allocatedMinor += floored
                fractions.append((index, rawMinor - floored))
            }

            var leftover = floorToInteger(debtor.shortfall * multiplier) - allocatedMinor
            let distributionOrder = fractions.sorted { lhs, rhs in
                if lhs.fraction != rhs.fraction { return lhs.fraction > rhs.fraction }
                return creditors[lhs.index].id.uuidString < creditors[rhs.index].id.uuidString
            }
            var next = 0
            while leftover > 0 {
                sharesMinor[distributionOrder[next % distributionOrder.count].index] += 1
                leftover -= 1
                next += 1
            }

            for (index, creditor) in creditors.enumerated() where sharesMinor[index] != 0 {
                result.append((pair: (creditor: creditor.id, debtor: debtor.id), amount: sharesMinor[index] / multiplier))
            }
        }
        return result
    }

    private static func floorToInteger(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .down)
        return result
    }
}

struct PairKey: Hashable {
    let lo: UUID
    let hi: UUID

    init(_ a: UUID, _ b: UUID) {
        if a.uuidString < b.uuidString {
            self.lo = a
            self.hi = b
        } else {
            self.lo = b
            self.hi = a
        }
    }

    // Canonical sign convention: positive value means `hi` owes `lo`.
    func signedAmount(creditor: UUID, debtor: UUID, amount: Decimal) -> Decimal {
        debtor == hi ? amount : -amount
    }
}

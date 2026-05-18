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
        for (key, byCurrency) in canonical {
            for (currency, amount) in byCurrency where amount != 0 {
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

        var result: [(pair: (creditor: UUID, debtor: UUID), amount: Decimal)] = []
        for debtor in debtors {
            for creditor in creditors {
                let share = debtor.shortfall * creditor.surplus / totalSurplus
                if share != 0 {
                    result.append((pair: (creditor: creditor.id, debtor: debtor.id), amount: share))
                }
            }
        }
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

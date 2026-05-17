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
            let payer = expense.payerID
            for split in expense.splits where split.participantID != payer {
                let debtor = split.participantID
                let key = PairKey(payer, debtor)
                let signed = key.signedAmount(creditor: payer, debtor: debtor, amount: split.amountOwed)
                canonical[key, default: [:]][currency, default: 0] += signed
            }
        }

        for settlement in settlements where settlement.deletedAt == nil {
            let currency = settlement.amount.currency
            let key = PairKey(settlement.fromUserID, settlement.toUserID)
            // Settlement: debtor pays creditor → reduces what debtor owes creditor.
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
                // canonical convention: positive amount means `key.hi` owes `key.lo`.
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

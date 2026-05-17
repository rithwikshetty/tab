import Testing
import Foundation
@testable import RoamCore

@Suite("BalanceEngine")
struct BalanceEngineTests {
    let trip = UUID()
    let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let bob = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    let charlie = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    // MARK: empty inputs

    @Test("empty expenses + settlements → empty balances")
    func emptyInput() {
        let result = BalanceEngine.compute(expenses: [], settlements: [])
        #expect(result.isEmpty)
    }

    // MARK: single expense

    @Test("one expense, equal split 2 ways → mirrored pair")
    func singleExpenseTwoWay() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 30, currency: "EUR",
            participants: [alice, bob], splitType: .equal
        )
        let expense = makeExpense(payer: alice, amount: 30, currency: "EUR", splits: splits)
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [])

        // Expect two mirrored UserBalance entries (Alice<->Bob, EUR).
        #expect(balances.count == 2)
        let aliceBalance = try #require(balances.first { $0.forUser == alice && $0.withUser == bob })
        let bobBalance = try #require(balances.first { $0.forUser == bob && $0.withUser == alice })
        #expect(aliceBalance.currency == "EUR")
        #expect(aliceBalance.amount == 15)   // Bob owes Alice 15
        #expect(bobBalance.amount == -15)    // Alice's side from Bob's perspective
    }

    @Test("payer not in participants → no self-balance entry")
    func payerNotInParticipants() {
        // Alice paid for an expense where only Bob and Charlie participate.
        let splits = [
            ExpenseSplit(participantID: bob, amountOwed: 20, splitType: .exact),
            ExpenseSplit(participantID: charlie, amountOwed: 20, splitType: .exact),
        ]
        let expense = makeExpense(payer: alice, amount: 40, currency: "EUR", splits: splits)
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [])

        // 4 entries: Alice<->Bob and Alice<->Charlie, both mirrored. No Alice<->Alice.
        #expect(balances.count == 4)
        #expect(balances.allSatisfy { $0.forUser != $0.withUser })
        let aliceBob = try? #require(balances.first { $0.forUser == alice && $0.withUser == bob })
        #expect(aliceBob?.amount == 20)
        let aliceCharlie = try? #require(balances.first { $0.forUser == alice && $0.withUser == charlie })
        #expect(aliceCharlie?.amount == 20)
    }

    @Test("payer in participants — their own split has no effect")
    func payerInParticipantsTheirSplitIgnored() throws {
        // Alice pays €30 for a 3-way split (Alice, Bob, Charlie). Each owes €10.
        let splits = try SplitCalculator.calculate(
            totalAmount: 30, currency: "EUR",
            participants: [alice, bob, charlie], splitType: .equal
        )
        let expense = makeExpense(payer: alice, amount: 30, currency: "EUR", splits: splits)
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [])

        // Expect 4 entries: Alice<->Bob, Alice<->Charlie (both directions). No Alice<->Alice.
        #expect(balances.count == 4)
        let aliceBob = try #require(balances.first { $0.forUser == alice && $0.withUser == bob })
        let aliceCharlie = try #require(balances.first { $0.forUser == alice && $0.withUser == charlie })
        #expect(aliceBob.amount == 10)
        #expect(aliceCharlie.amount == 10)
    }

    // MARK: multiple expenses, same currency

    @Test("multiple expenses with reciprocal payments net out")
    func reciprocalExpensesNet() {
        // Alice paid €30 dinner (Alice/Bob each owe €15 → Bob owes Alice €15)
        let dinner = makeExpense(
            payer: alice, amount: 30, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 15, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 15, splitType: .equal),
            ]
        )
        // Bob paid €20 snacks (Alice/Bob each owe €10 → Alice owes Bob €10)
        let snacks = makeExpense(
            payer: bob, amount: 20, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 10, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 10, splitType: .equal),
            ]
        )
        let balances = BalanceEngine.compute(expenses: [dinner, snacks], settlements: [])

        // Net: Bob owes Alice €5
        let aliceBob = try? #require(balances.first { $0.forUser == alice && $0.withUser == bob })
        let bobAlice = try? #require(balances.first { $0.forUser == bob && $0.withUser == alice })
        #expect(aliceBob?.amount == 5)
        #expect(bobAlice?.amount == -5)
    }

    @Test("zero net balance is omitted")
    func zeroNetOmitted() {
        // Alice paid €20, splits Alice/Bob equally (Bob owes 10).
        let e1 = makeExpense(
            payer: alice, amount: 20, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 10, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 10, splitType: .equal),
            ]
        )
        // Bob paid €20, splits Alice/Bob equally (Alice owes 10).
        let e2 = makeExpense(
            payer: bob, amount: 20, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 10, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 10, splitType: .equal),
            ]
        )
        let balances = BalanceEngine.compute(expenses: [e1, e2], settlements: [])
        // Alice and Bob owe each other 10 → net 0. No entry.
        #expect(balances.isEmpty)
    }

    // MARK: multi-currency

    @Test("expenses in different currencies produce separate balance entries per currency")
    func multiCurrency() {
        let eurExpense = makeExpense(
            payer: alice, amount: 30, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 15, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 15, splitType: .equal),
            ]
        )
        let usdExpense = makeExpense(
            payer: alice, amount: 40, currency: "USD",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 20, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 20, splitType: .equal),
            ]
        )
        let balances = BalanceEngine.compute(expenses: [eurExpense, usdExpense], settlements: [])
        // Expect 4 entries: Alice<->Bob in EUR, Alice<->Bob in USD, both mirrored.
        #expect(balances.count == 4)
        let aliceBobEUR = balances.first { $0.forUser == alice && $0.withUser == bob && $0.currency == "EUR" }
        let aliceBobUSD = balances.first { $0.forUser == alice && $0.withUser == bob && $0.currency == "USD" }
        #expect(aliceBobEUR?.amount == 15)
        #expect(aliceBobUSD?.amount == 20)
    }

    // MARK: settlements

    @Test("settlement reduces the debtor's balance to the creditor")
    func settlementReducesBalance() {
        let expense = makeExpense(
            payer: alice, amount: 30, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 15, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 15, splitType: .equal),
            ]
        )
        // Bob pays Alice €15 → settles.
        let settlement = makeSettlement(from: bob, to: alice, amount: 15, currency: "EUR")
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [settlement])
        #expect(balances.isEmpty)
    }

    @Test("partial settlement leaves remaining balance")
    func partialSettlement() {
        let expense = makeExpense(
            payer: alice, amount: 30, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 15, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 15, splitType: .equal),
            ]
        )
        let settlement = makeSettlement(from: bob, to: alice, amount: 5, currency: "EUR")
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [settlement])
        let aliceBob = try? #require(balances.first { $0.forUser == alice && $0.withUser == bob })
        #expect(aliceBob?.amount == 10)
    }

    @Test("over-settlement flips the direction of the balance")
    func overSettlement() {
        let expense = makeExpense(
            payer: alice, amount: 30, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 15, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 15, splitType: .equal),
            ]
        )
        // Bob pays Alice €20 — €5 more than he owed. Now Alice owes Bob €5.
        let settlement = makeSettlement(from: bob, to: alice, amount: 20, currency: "EUR")
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [settlement])
        let aliceBob = try? #require(balances.first { $0.forUser == alice && $0.withUser == bob })
        let bobAlice = try? #require(balances.first { $0.forUser == bob && $0.withUser == alice })
        #expect(aliceBob?.amount == -5)
        #expect(bobAlice?.amount == 5)
    }

    // MARK: soft-delete

    @Test("soft-deleted expense is excluded from balances")
    func softDeletedExpenseExcluded() {
        let active = makeExpense(
            payer: alice, amount: 30, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 15, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 15, splitType: .equal),
            ]
        )
        let deleted = makeExpense(
            payer: alice, amount: 100, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 50, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 50, splitType: .equal),
            ],
            deletedAt: Date()
        )
        let balances = BalanceEngine.compute(expenses: [active, deleted], settlements: [])
        let aliceBob = try? #require(balances.first { $0.forUser == alice && $0.withUser == bob })
        #expect(aliceBob?.amount == 15)
    }

    @Test("soft-deleted settlement is excluded")
    func softDeletedSettlementExcluded() {
        let expense = makeExpense(
            payer: alice, amount: 30, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 15, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 15, splitType: .equal),
            ]
        )
        let deletedSettlement = makeSettlement(
            from: bob, to: alice, amount: 15, currency: "EUR",
            deletedAt: Date()
        )
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [deletedSettlement])
        let aliceBob = try? #require(balances.first { $0.forUser == alice && $0.withUser == bob })
        #expect(aliceBob?.amount == 15)
    }

    // MARK: helpers

    private func makeExpense(
        payer: UUID,
        amount: Decimal,
        currency: String,
        splits: [ExpenseSplit],
        deletedAt: Date? = nil
    ) -> Expense {
        let now = Date()
        return Expense(
            tripID: trip,
            payerID: payer,
            amount: Money(amount: amount, currency: currency),
            expenseDate: now,
            splits: splits,
            createdBy: payer,
            createdAt: now,
            updatedAt: now,
            deletedAt: deletedAt
        )
    }

    private func makeSettlement(
        from: UUID,
        to: UUID,
        amount: Decimal,
        currency: String,
        deletedAt: Date? = nil
    ) -> Settlement {
        let now = Date()
        return Settlement(
            tripID: trip,
            fromUserID: from,
            toUserID: to,
            amount: Money(amount: amount, currency: currency),
            settledAt: now,
            createdBy: from,
            createdAt: now,
            updatedAt: now,
            deletedAt: deletedAt
        )
    }
}

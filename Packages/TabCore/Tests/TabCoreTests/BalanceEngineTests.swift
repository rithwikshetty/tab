import Testing
import Foundation
@testable import TabCore

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

    @Test("balances are emitted in deterministic pair and currency order")
    func deterministicOutputOrder() {
        let eurExpense = makeExpense(
            payer: alice, amount: 90, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 30, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 30, splitType: .equal),
                ExpenseSplit(participantID: charlie, amountOwed: 30, splitType: .equal),
            ]
        )
        let usdExpense = makeExpense(
            payer: bob, amount: 20, currency: "USD",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 10, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 10, splitType: .equal),
            ]
        )

        let balances = BalanceEngine.compute(expenses: [eurExpense, usdExpense], settlements: [])

        #expect(balances.count == 6)
        #expect(balances[0].forUser == alice)
        #expect(balances[0].withUser == bob)
        #expect(balances[0].currency == "EUR")
        #expect(balances[0].amount == 30)
        #expect(balances[1].forUser == bob)
        #expect(balances[1].withUser == alice)
        #expect(balances[1].currency == "EUR")
        #expect(balances[1].amount == -30)
        #expect(balances[2].forUser == alice)
        #expect(balances[2].withUser == bob)
        #expect(balances[2].currency == "USD")
        #expect(balances[2].amount == -10)
        #expect(balances[3].forUser == bob)
        #expect(balances[3].withUser == alice)
        #expect(balances[3].currency == "USD")
        #expect(balances[3].amount == 10)
        #expect(balances[4].forUser == alice)
        #expect(balances[4].withUser == charlie)
        #expect(balances[4].currency == "EUR")
        #expect(balances[4].amount == 30)
        #expect(balances[5].forUser == charlie)
        #expect(balances[5].withUser == alice)
        #expect(balances[5].currency == "EUR")
        #expect(balances[5].amount == -30)
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

    // MARK: multi-payer

    @Test("two payers, equal split among participants: debtor's debt distributes proportionally")
    func twoPayersEqualSplit() {
        // €100. Alice paid €60, Bob paid €40. Three participants A/B/C, each owes (approx) €33.33.
        let expense = makeExpense(
            payments: [
                Payment(payerID: alice, amountPaid: 60, paymentMode: .exact),
                Payment(payerID: bob, amountPaid: 40, paymentMode: .exact),
            ],
            amount: 100, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: Decimal(string: "33.33")!, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: Decimal(string: "33.33")!, splitType: .equal),
                ExpenseSplit(participantID: charlie, amountOwed: Decimal(string: "33.34")!, splitType: .equal),
            ],
            createdBy: alice
        )
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [])

        // Nets: Alice = 60-33.33 = +26.67. Bob = 40-33.33 = +6.67. Charlie = -33.34.
        // Total surplus = 33.34. Charlie's debt distributes proportionally:
        //   Charlie→Alice = 33.34 * 26.67 / 33.34 = 26.67
        //   Charlie→Bob   = 33.34 *  6.67 / 33.34 =  6.67
        let charlieAlice = balances.first { $0.forUser == charlie && $0.withUser == alice }
        let charlieBob = balances.first { $0.forUser == charlie && $0.withUser == bob }
        #expect(charlieAlice?.amount == Decimal(string: "-26.67"))   // Charlie owes Alice
        #expect(charlieBob?.amount == Decimal(string: "-6.67"))      // Charlie owes Bob
        // No Alice↔Bob entry — both are creditors with no debt to each other from this expense.
        let aliceBob = balances.first { $0.forUser == alice && $0.withUser == bob }
        #expect(aliceBob == nil)
    }

    @Test("user paid more than owed becomes net creditor; user paid less becomes net debtor")
    func payerWithMixedNet() {
        // €50. Alice paid €30, Bob paid €20. Splits Alice=€40, Bob=€10.
        // Nets: Alice = -10 (paid less than owed → debtor). Bob = +10 (creditor).
        let expense = makeExpense(
            payments: [
                Payment(payerID: alice, amountPaid: 30, paymentMode: .exact),
                Payment(payerID: bob, amountPaid: 20, paymentMode: .exact),
            ],
            amount: 50, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 40, splitType: .exact),
                ExpenseSplit(participantID: bob, amountOwed: 10, splitType: .exact),
            ],
            createdBy: alice
        )
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [])
        // Alice owes Bob €10.
        let aliceBob = balances.first { $0.forUser == alice && $0.withUser == bob }
        let bobAlice = balances.first { $0.forUser == bob && $0.withUser == alice }
        #expect(aliceBob?.amount == -10)
        #expect(bobAlice?.amount == 10)
    }

    @Test("three users, three payers, one big debtor")
    func twoCreditorsOneDebtor() {
        // €100. A paid €60, B paid €40, C paid €0. Splits A=€20, B=€20, C=€60.
        // Nets: A = +40 (creditor), B = +20 (creditor), C = -60 (debtor).
        // Total surplus = 60.
        // C→A = 60 * 40 / 60 = 40. C→B = 60 * 20 / 60 = 20.
        let expense = makeExpense(
            payments: [
                Payment(payerID: alice, amountPaid: 60, paymentMode: .exact),
                Payment(payerID: bob, amountPaid: 40, paymentMode: .exact),
            ],
            amount: 100, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 20, splitType: .exact),
                ExpenseSplit(participantID: bob, amountOwed: 20, splitType: .exact),
                ExpenseSplit(participantID: charlie, amountOwed: 60, splitType: .exact),
            ],
            createdBy: alice
        )
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [])
        let charlieAlice = balances.first { $0.forUser == charlie && $0.withUser == alice }
        let charlieBob = balances.first { $0.forUser == charlie && $0.withUser == bob }
        #expect(charlieAlice?.amount == -40)
        #expect(charlieBob?.amount == -20)
    }

    @Test("user paid exactly what they owe contributes nothing")
    func netZeroUserExcluded() {
        // €30. Alice paid €30. Splits Alice=€10, Bob=€10, Charlie=€10.
        // Standard single-payer pattern via payments array of length 1.
        // Now: also give Bob a €10 self-payment (Bob paid €10, owes €10 → net 0).
        let expense = makeExpense(
            payments: [
                Payment(payerID: alice, amountPaid: 20, paymentMode: .exact),
                Payment(payerID: bob, amountPaid: 10, paymentMode: .exact),
            ],
            amount: 30, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 10, splitType: .equal),
                ExpenseSplit(participantID: bob, amountOwed: 10, splitType: .equal),
                ExpenseSplit(participantID: charlie, amountOwed: 10, splitType: .equal),
            ],
            createdBy: alice
        )
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [])
        // Nets: A=+10, B=0, C=-10. So C owes A only — no Bob involvement.
        let charlieAlice = balances.first { $0.forUser == charlie && $0.withUser == alice }
        #expect(charlieAlice?.amount == -10)
        let charlieBob = balances.first { $0.forUser == charlie && $0.withUser == bob }
        #expect(charlieBob == nil)
        let aliceBob = balances.first { $0.forUser == alice && $0.withUser == bob }
        #expect(aliceBob == nil)
    }

    @Test("multi-payer pair amounts in this expense sum to total surplus (and total shortfall)")
    func multiPayerSumInvariant() {
        // €250 case from grill: A paid 100, B paid 50, C paid 100. Splits A=120, B=80, C=50.
        let expense = makeExpense(
            payments: [
                Payment(payerID: alice, amountPaid: 100, paymentMode: .exact),
                Payment(payerID: bob, amountPaid: 50, paymentMode: .exact),
                Payment(payerID: charlie, amountPaid: 100, paymentMode: .exact),
            ],
            amount: 250, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 120, splitType: .exact),
                ExpenseSplit(participantID: bob, amountOwed: 80, splitType: .exact),
                ExpenseSplit(participantID: charlie, amountOwed: 50, splitType: .exact),
            ],
            createdBy: alice
        )
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [])
        // Nets: A=-20, B=-30, C=+50. Only Charlie is creditor.
        // A owes C 20, B owes C 30.
        let aliceCharlie = balances.first { $0.forUser == alice && $0.withUser == charlie }
        let bobCharlie = balances.first { $0.forUser == bob && $0.withUser == charlie }
        #expect(aliceCharlie?.amount == -20)
        #expect(bobCharlie?.amount == -30)
        let aliceBob = balances.first { $0.forUser == alice && $0.withUser == bob }
        #expect(aliceBob == nil)
    }

    @Test("settlement applies to multi-payer-derived balance")
    func settlementAgainstMultiPayer() {
        // Same as twoCreditorsOneDebtor: C owes A €40, C owes B €20.
        let expense = makeExpense(
            payments: [
                Payment(payerID: alice, amountPaid: 60, paymentMode: .exact),
                Payment(payerID: bob, amountPaid: 40, paymentMode: .exact),
            ],
            amount: 100, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 20, splitType: .exact),
                ExpenseSplit(participantID: bob, amountOwed: 20, splitType: .exact),
                ExpenseSplit(participantID: charlie, amountOwed: 60, splitType: .exact),
            ],
            createdBy: alice
        )
        // Charlie pays Alice €40 — fully settles that side.
        let settlement = makeSettlement(from: charlie, to: alice, amount: 40, currency: "EUR")
        let balances = BalanceEngine.compute(expenses: [expense], settlements: [settlement])
        let charlieAlice = balances.first { $0.forUser == charlie && $0.withUser == alice }
        let charlieBob = balances.first { $0.forUser == charlie && $0.withUser == bob }
        #expect(charlieAlice == nil)   // settled to zero
        #expect(charlieBob?.amount == -20)   // still owes Bob
    }

    @Test("multi-payer in two different currencies stays per-currency separated")
    func multiPayerMultiCurrency() {
        let usdExpense = makeExpense(
            payments: [
                Payment(payerID: alice, amountPaid: 60, paymentMode: .exact),
                Payment(payerID: bob, amountPaid: 40, paymentMode: .exact),
            ],
            amount: 100, currency: "USD",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 20, splitType: .exact),
                ExpenseSplit(participantID: bob, amountOwed: 20, splitType: .exact),
                ExpenseSplit(participantID: charlie, amountOwed: 60, splitType: .exact),
            ],
            createdBy: alice
        )
        let eurExpense = makeExpense(
            payments: [
                Payment(payerID: charlie, amountPaid: 50, paymentMode: .exact),
            ],
            amount: 50, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 25, splitType: .equal),
                ExpenseSplit(participantID: charlie, amountOwed: 25, splitType: .equal),
            ],
            createdBy: charlie
        )
        let balances = BalanceEngine.compute(expenses: [usdExpense, eurExpense], settlements: [])
        // USD: C owes A 40, C owes B 20.
        let charlieAliceUSD = balances.first {
            $0.forUser == charlie && $0.withUser == alice && $0.currency == "USD"
        }
        #expect(charlieAliceUSD?.amount == -40)
        // EUR: A owes C 25.
        let aliceCharlieEUR = balances.first {
            $0.forUser == alice && $0.withUser == charlie && $0.currency == "EUR"
        }
        #expect(aliceCharlieEUR?.amount == -25)
    }

    @Test("multi-payer aggregates across multiple expenses correctly")
    func multiPayerAcrossExpenses() {
        // Expense 1: A paid 60, B paid 40. Splits A=20, B=20, C=60. → C owes A 40, C owes B 20.
        let e1 = makeExpense(
            payments: [
                Payment(payerID: alice, amountPaid: 60, paymentMode: .exact),
                Payment(payerID: bob, amountPaid: 40, paymentMode: .exact),
            ],
            amount: 100, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 20, splitType: .exact),
                ExpenseSplit(participantID: bob, amountOwed: 20, splitType: .exact),
                ExpenseSplit(participantID: charlie, amountOwed: 60, splitType: .exact),
            ],
            createdBy: alice
        )
        // Expense 2: C paid 30. Splits A=15, C=15. → A owes C 15.
        let e2 = makeExpense(
            payments: [
                Payment(payerID: charlie, amountPaid: 30, paymentMode: .equal),
            ],
            amount: 30, currency: "EUR",
            splits: [
                ExpenseSplit(participantID: alice, amountOwed: 15, splitType: .equal),
                ExpenseSplit(participantID: charlie, amountOwed: 15, splitType: .equal),
            ],
            createdBy: charlie
        )
        let balances = BalanceEngine.compute(expenses: [e1, e2], settlements: [])
        // A↔C net: from e1, C owes A 40. From e2, A owes C 15. Net: C owes A 25.
        let charlieAlice = balances.first { $0.forUser == charlie && $0.withUser == alice }
        #expect(charlieAlice?.amount == -25)
        // B↔C: C owes B 20 (only e1).
        let charlieBob = balances.first { $0.forUser == charlie && $0.withUser == bob }
        #expect(charlieBob?.amount == -20)
    }

    // MARK: helpers

    private func makeExpense(
        payer: UUID,
        amount: Decimal,
        currency: String,
        splits: [ExpenseSplit],
        deletedAt: Date? = nil
    ) -> Expense {
        makeExpense(
            payments: [Payment(payerID: payer, amountPaid: amount, paymentMode: .equal)],
            amount: amount,
            currency: currency,
            splits: splits,
            createdBy: payer,
            deletedAt: deletedAt
        )
    }

    private func makeExpense(
        payments: [Payment],
        amount: Decimal,
        currency: String,
        splits: [ExpenseSplit],
        createdBy: UUID,
        deletedAt: Date? = nil
    ) -> Expense {
        let now = Date()
        return Expense(
            tripID: trip,
            amount: Money(amount: amount, currency: currency),
            expenseDate: now,
            payments: payments,
            splits: splits,
            createdBy: createdBy,
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

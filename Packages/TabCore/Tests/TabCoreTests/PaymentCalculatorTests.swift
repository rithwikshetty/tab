import Testing
import Foundation
@testable import TabCore

@Suite("PaymentCalculator")
struct PaymentCalculatorTests {
    let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let bob = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    let charlie = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    // MARK: equal

    @Test("single payer, equal mode: full amount to the payer")
    func singlePayerEqual() throws {
        let payments = try PaymentCalculator.calculate(
            totalAmount: 50,
            currency: "EUR",
            payers: [alice],
            paymentMode: .equal
        )
        #expect(payments.count == 1)
        #expect(payments[0].payerID == alice)
        #expect(payments[0].amountPaid == 50)
        #expect(payments[0].paymentMode == .equal)
    }

    @Test("equal mode: two payers, clean divide")
    func equalTwoPayers() throws {
        let payments = try PaymentCalculator.calculate(
            totalAmount: 30,
            currency: "EUR",
            payers: [alice, bob],
            paymentMode: .equal
        )
        #expect(payments.count == 2)
        #expect(payments.allSatisfy { $0.amountPaid == 15 })
        #expect(payments.allSatisfy { $0.paymentMode == .equal })
        #expect(Set(payments.map(\.payerID)) == [alice, bob])
    }

    @Test("equal mode: $10/3 distributes 1-cent remainder to lowest UUID")
    func equalThreeWayWithRemainder() throws {
        let payments = try PaymentCalculator.calculate(
            totalAmount: 10,
            currency: "USD",
            payers: [bob, charlie, alice],
            paymentMode: .equal
        )
        #expect(payments.count == 3)
        let sum = payments.reduce(Decimal(0)) { $0 + $1.amountPaid }
        #expect(sum == 10)
        let byUser = Dictionary(uniqueKeysWithValues: payments.map { ($0.payerID, $0.amountPaid) })
        #expect(byUser[alice] == Decimal(string: "3.34"))
        #expect(byUser[bob] == Decimal(string: "3.33"))
        #expect(byUser[charlie] == Decimal(string: "3.33"))
    }

    @Test("equal mode: $0.05/3 distributes 2-cent remainder to two lowest UUIDs")
    func equalTwoCentRemainder() throws {
        let payments = try PaymentCalculator.calculate(
            totalAmount: Decimal(string: "0.05")!,
            currency: "USD",
            payers: [alice, bob, charlie],
            paymentMode: .equal
        )
        let sum = payments.reduce(Decimal(0)) { $0 + $1.amountPaid }
        #expect(sum == Decimal(string: "0.05"))
        let byUser = Dictionary(uniqueKeysWithValues: payments.map { ($0.payerID, $0.amountPaid) })
        #expect(byUser[alice] == Decimal(string: "0.02"))
        #expect(byUser[bob] == Decimal(string: "0.02"))
        #expect(byUser[charlie] == Decimal(string: "0.01"))
    }

    @Test("equal mode: zero amount → all payers paid zero")
    func equalZeroAmount() throws {
        let payments = try PaymentCalculator.calculate(
            totalAmount: 0,
            currency: "EUR",
            payers: [alice, bob, charlie],
            paymentMode: .equal
        )
        #expect(payments.count == 3)
        #expect(payments.allSatisfy { $0.amountPaid == 0 })
    }

    @Test("equal mode: JPY uses whole-yen minor units")
    func equalJPYUsesWholeUnits() throws {
        let payments = try PaymentCalculator.calculate(
            totalAmount: 101,
            currency: "JPY",
            payers: [bob, alice],
            paymentMode: .equal
        )
        let byUser = Dictionary(uniqueKeysWithValues: payments.map { ($0.payerID, $0.amountPaid) })
        #expect(byUser[alice] == 51)
        #expect(byUser[bob] == 50)
    }

    @Test("equal mode: invalid currency precision is mapped from split calculator")
    func equalInvalidCurrencyPrecisionThrows() {
        #expect(throws: PaymentCalculatorError.amountHasTooManyFractionDigits(currency: "JPY", maximumFractionDigits: 0)) {
            _ = try PaymentCalculator.calculate(
                totalAmount: Decimal(string: "10.25")!,
                currency: "JPY",
                payers: [alice, bob],
                paymentMode: .equal
            )
        }
    }

    @Test("equal mode: empty payers throws emptyPayers")
    func equalEmptyPayersThrows() {
        #expect(throws: PaymentCalculatorError.emptyPayers) {
            _ = try PaymentCalculator.calculate(
                totalAmount: 10,
                currency: "EUR",
                payers: [],
                paymentMode: .equal
            )
        }
    }

    // MARK: exact

    @Test("exact mode: amounts sum to total")
    func exactValid() throws {
        let payments = try PaymentCalculator.calculate(
            totalAmount: 250,
            currency: "EUR",
            payers: [alice, bob, charlie],
            paymentMode: .exact,
            exactAmounts: [alice: 100, bob: 100, charlie: 50]
        )
        #expect(payments.count == 3)
        let byUser = Dictionary(uniqueKeysWithValues: payments.map { ($0.payerID, $0.amountPaid) })
        #expect(byUser[alice] == 100)
        #expect(byUser[bob] == 100)
        #expect(byUser[charlie] == 50)
        #expect(payments.allSatisfy { $0.paymentMode == .exact })
    }

    @Test("exact mode: amounts don't sum to total throws")
    func exactSumMismatchThrows() {
        #expect(throws: PaymentCalculatorError.self) {
            _ = try PaymentCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                payers: [alice, bob],
                paymentMode: .exact,
                exactAmounts: [alice: 50, bob: 30]
            )
        }
    }

    @Test("exact mode: missing payer amount throws")
    func exactMissingPayerThrows() {
        #expect(throws: PaymentCalculatorError.self) {
            _ = try PaymentCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                payers: [alice, bob, charlie],
                paymentMode: .exact,
                exactAmounts: [alice: 50, bob: 50]
            )
        }
    }

    @Test("exact mode: extra non-payer amount throws")
    func exactExtraNonPayerThrows() {
        #expect(throws: PaymentCalculatorError.self) {
            _ = try PaymentCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                payers: [alice, bob],
                paymentMode: .exact,
                exactAmounts: [alice: 40, bob: 30, charlie: 30]
            )
        }
    }

    @Test("exact mode: single payer with full amount")
    func exactSinglePayer() throws {
        let payments = try PaymentCalculator.calculate(
            totalAmount: 99,
            currency: "EUR",
            payers: [alice],
            paymentMode: .exact,
            exactAmounts: [alice: 99]
        )
        #expect(payments.count == 1)
        #expect(payments[0].payerID == alice)
        #expect(payments[0].amountPaid == 99)
        #expect(payments[0].paymentMode == .exact)
    }

    @Test("exact mode: off-by-one-cent throws")
    func exactOffByOneCentThrows() {
        #expect(throws: PaymentCalculatorError.self) {
            _ = try PaymentCalculator.calculate(
                totalAmount: Decimal(string: "10.00")!,
                currency: "EUR",
                payers: [alice, bob],
                paymentMode: .exact,
                exactAmounts: [alice: Decimal(string: "5.00")!, bob: Decimal(string: "4.99")!]
            )
        }
    }

    @Test("exact mode: nil exactAmounts throws")
    func exactNilAmountsThrows() {
        #expect(throws: PaymentCalculatorError.exactAmountsRequired) {
            _ = try PaymentCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                payers: [alice, bob],
                paymentMode: .exact,
                exactAmounts: nil
            )
        }
    }

    // MARK: unsupported

    @Test("unsupported modes throw unsupportedPaymentMode",
          arguments: [SplitType.percentage, .shares, .adjustment])
    func unsupportedModes(_ mode: PaymentMode) {
        #expect(throws: PaymentCalculatorError.self) {
            _ = try PaymentCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                payers: [alice],
                paymentMode: mode
            )
        }
    }
}

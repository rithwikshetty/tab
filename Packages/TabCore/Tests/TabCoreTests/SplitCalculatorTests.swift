import Testing
import Foundation
@testable import TabCore

@Suite("SplitCalculator")
struct SplitCalculatorTests {
    // Stable UUIDs so the remainder-distribution order is deterministic across runs.
    // Lexicographic order: alice < bob < charlie.
    let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let bob = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    let charlie = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    // MARK: equal

    @Test("equal split: even total, two-way")
    func equalEvenTwoWay() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 30,
            currency: "EUR",
            participants: [alice, bob],
            splitType: .equal
        )
        #expect(splits.count == 2)
        #expect(splits.allSatisfy { $0.amountOwed == 15 })
        #expect(splits.allSatisfy { $0.splitType == .equal })
        #expect(Set(splits.map(\.participantID)) == [alice, bob])
    }

    @Test("equal split: $10/3 distributes 1-cent remainder to first sorted participant")
    func equalThreeWayWithRemainder() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 10,
            currency: "USD",
            participants: [bob, charlie, alice],  // intentionally unsorted
            splitType: .equal
        )
        #expect(splits.count == 3)
        let sum = splits.reduce(Decimal(0)) { $0 + $1.amountOwed }
        #expect(sum == 10)
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        // alice has the lowest UUID, so alice gets the extra cent
        #expect(byUser[alice] == Decimal(string: "3.34"))
        #expect(byUser[bob] == Decimal(string: "3.33"))
        #expect(byUser[charlie] == Decimal(string: "3.33"))
    }

    @Test("equal split: $1/3 — 1 cent goes to lowest UUID")
    func equalDollarThreeWay() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 1,
            currency: "USD",
            participants: [alice, bob, charlie],
            splitType: .equal
        )
        let sum = splits.reduce(Decimal(0)) { $0 + $1.amountOwed }
        #expect(sum == 1)
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == Decimal(string: "0.34"))
        #expect(byUser[bob] == Decimal(string: "0.33"))
        #expect(byUser[charlie] == Decimal(string: "0.33"))
    }

    @Test("equal split: single participant gets the whole amount")
    func equalSingleParticipant() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 50,
            currency: "EUR",
            participants: [alice],
            splitType: .equal
        )
        #expect(splits.count == 1)
        #expect(splits[0].amountOwed == 50)
        #expect(splits[0].participantID == alice)
    }

    @Test("equal split: zero amount → all participants owe zero")
    func equalZeroAmount() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 0,
            currency: "EUR",
            participants: [alice, bob, charlie],
            splitType: .equal
        )
        #expect(splits.allSatisfy { $0.amountOwed == 0 })
    }

    @Test("equal split: empty participants throws emptyParticipants")
    func equalEmptyParticipantsThrows() {
        #expect(throws: SplitCalculatorError.emptyParticipants) {
            _ = try SplitCalculator.calculate(
                totalAmount: 10,
                currency: "EUR",
                participants: [],
                splitType: .equal
            )
        }
    }

    @Test("equal split: 2-cent remainder distributes to two lowest UUIDs")
    func equalTwoCentRemainder() throws {
        // $1.00 / 3 = 33.33¢ each, remainder 1¢? Let's check:
        // Actually need a case with 2¢ remainder. $0.05 / 3 = 1¢ each, 2¢ remainder.
        let splits = try SplitCalculator.calculate(
            totalAmount: Decimal(string: "0.05")!,
            currency: "USD",
            participants: [alice, bob, charlie],
            splitType: .equal
        )
        let sum = splits.reduce(Decimal(0)) { $0 + $1.amountOwed }
        #expect(sum == Decimal(string: "0.05"))
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == Decimal(string: "0.02"))
        #expect(byUser[bob] == Decimal(string: "0.02"))
        #expect(byUser[charlie] == Decimal(string: "0.01"))
    }

    @Test("equal split: JPY uses whole-yen minor units")
    func equalJPYUsesWholeUnits() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 101,
            currency: "JPY",
            participants: [bob, alice],
            splitType: .equal
        )
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == 51)
        #expect(byUser[bob] == 50)
    }

    @Test("equal split: KWD uses three decimal minor units")
    func equalKWDUsesThreeDecimals() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: Decimal(string: "1.001")!,
            currency: "KWD",
            participants: [alice, bob],
            splitType: .equal
        )
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == Decimal(string: "0.501"))
        #expect(byUser[bob] == Decimal(string: "0.500"))
    }

    @Test("equal split: rejects amounts with too many currency fraction digits")
    func equalRejectsInvalidCurrencyPrecision() {
        #expect(throws: SplitCalculatorError.amountHasTooManyFractionDigits(currency: "JPY", maximumFractionDigits: 0)) {
            _ = try SplitCalculator.calculate(
                totalAmount: Decimal(string: "10.25")!,
                currency: "JPY",
                participants: [alice, bob],
                splitType: .equal
            )
        }
    }

    // MARK: exact

    @Test("exact split: amounts sum to total")
    func exactValid() throws {
        let splits = try SplitCalculator.calculate(
            totalAmount: 100,
            currency: "EUR",
            participants: [alice, bob, charlie],
            splitType: .exact,
            exactAmounts: [alice: 40, bob: 30, charlie: 30]
        )
        #expect(splits.count == 3)
        let byUser = Dictionary(uniqueKeysWithValues: splits.map { ($0.participantID, $0.amountOwed) })
        #expect(byUser[alice] == 40)
        #expect(byUser[bob] == 30)
        #expect(byUser[charlie] == 30)
        #expect(splits.allSatisfy { $0.splitType == .exact })
    }

    @Test("exact split: amounts don't sum to total throws")
    func exactSumMismatchThrows() {
        #expect(throws: SplitCalculatorError.self) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .exact,
                exactAmounts: [alice: 50, bob: 30]
            )
        }
    }

    @Test("exact split: missing a participant amount throws")
    func exactMissingParticipantThrows() {
        #expect(throws: SplitCalculatorError.self) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob, charlie],
                splitType: .exact,
                exactAmounts: [alice: 50, bob: 50]
            )
        }
    }

    @Test("exact split: extra non-participant amount throws")
    func exactExtraNonParticipantThrows() {
        #expect(throws: SplitCalculatorError.self) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .exact,
                exactAmounts: [alice: 40, bob: 30, charlie: 30]
            )
        }
    }

    @Test("exact split: nil exactAmounts throws")
    func exactNilAmountsThrows() {
        #expect(throws: SplitCalculatorError.self) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice, bob],
                splitType: .exact,
                exactAmounts: nil
            )
        }
    }

    // MARK: unsupported

    @Test("unsupported types throw unsupportedSplitType",
          arguments: [SplitType.percentage, .shares, .adjustment])
    func unsupportedTypes(_ type: SplitType) {
        #expect(throws: SplitCalculatorError.self) {
            _ = try SplitCalculator.calculate(
                totalAmount: 100,
                currency: "EUR",
                participants: [alice],
                splitType: type
            )
        }
    }
}

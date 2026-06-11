import Foundation
import Testing
@testable import Tab

@Suite("Money formatter input handling")
struct MoneyFormatterTests {
    // MARK: currency switch preserves value

    @Test("switching USD text to JPY preserves the value, not the digits")
    func currencySwitchPreservesValue() {
        #expect(MoneyFormatter.convertAmountText("123.45", to: "JPY") == "123")
    }

    @Test("switching JPY text to USD renders the new precision")
    func currencySwitchAddsPrecision() {
        #expect(MoneyFormatter.convertAmountText("123", to: "USD") == "123.00")
    }

    @Test("empty amount text stays empty across a currency switch")
    func currencySwitchKeepsEmpty() {
        #expect(MoneyFormatter.convertAmountText("", to: "JPY") == "")
    }

    // MARK: paste sanitation

    @Test("US-formatted paste with grouping separators keeps its value")
    func pasteUSGrouping() {
        #expect(MoneyFormatter.sanitizeAmountInput("1,234.56", currency: "USD") == "1234.56")
    }

    @Test("EU-formatted paste with grouping separators keeps its value")
    func pasteEUGrouping() {
        #expect(MoneyFormatter.sanitizeAmountInput("1.234,56", currency: "USD") == "1234.56")
    }

    @Test("repeated grouping separators are stripped, not misread as decimals")
    func pasteMillionsGrouping() {
        #expect(MoneyFormatter.sanitizeAmountInput("1.234.567", currency: "USD") == "1234567")
    }

    // MARK: zero-decimal currencies truncate instead of concatenating

    @Test("typing a decimal point in a zero-decimal currency truncates the rest")
    func zeroDecimalCurrencyTruncates() {
        #expect(MoneyFormatter.sanitizeAmountInput("123.45", currency: "JPY") == "123")
    }

    @Test("digits beyond the currency precision are dropped, not appended")
    func excessFractionTruncates() {
        #expect(MoneyFormatter.sanitizeAmountInput("12.3456", currency: "USD") == "12.34")
    }

    // MARK: typing semantics unchanged

    @Test("comma typed as decimal separator still works")
    func commaAsDecimal() {
        #expect(MoneyFormatter.sanitizeAmountInput("12,5", currency: "EUR") == "12.5")
    }
}

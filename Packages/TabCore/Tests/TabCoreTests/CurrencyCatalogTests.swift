import Foundation
import Testing
@testable import TabCore

@Suite("CurrencyCatalog")
struct CurrencyCatalogTests {
    @Test("default code is the hard fallback currency")
    func defaultCodeIsHardFallbackCurrency() {
        #expect(CurrencyCatalog.defaultCode == "INR")
        #expect(CurrencyCatalog.isSupported(CurrencyCatalog.defaultCode))
    }

    @Test("supported currencies include common ISO 4217 codes")
    func includesCommonISOCodes() {
        #expect(CurrencyCatalog.supported.count > 100)
        #expect(CurrencyCatalog.isSupported("EUR"))
        #expect(CurrencyCatalog.isSupported("usd"))
        #expect(CurrencyCatalog.isSupported("JPY"))
        #expect(CurrencyCatalog.isSupported("KWD"))
    }

    @Test("metadata exposes symbols, names, and fraction digits")
    func metadata() throws {
        let usd = try #require(CurrencyCatalog.metadata(for: "USD"))
        let jpy = try #require(CurrencyCatalog.metadata(for: "JPY"))
        let kwd = try #require(CurrencyCatalog.metadata(for: "KWD"))

        #expect(!usd.symbol.isEmpty)
        #expect(usd.name.localizedCaseInsensitiveContains("Dollar"))
        #expect(usd.fractionDigits == 2)
        #expect(jpy.fractionDigits == 0)
        #expect(kwd.fractionDigits == 3)
    }

    @Test("precision validation respects each currency minor unit")
    func precisionValidation() {
        #expect(CurrencyCatalog.hasValidPrecision(10, currency: "JPY"))
        #expect(!CurrencyCatalog.hasValidPrecision(Decimal(string: "10.01")!, currency: "JPY"))
        #expect(CurrencyCatalog.hasValidPrecision(Decimal(string: "1.234")!, currency: "KWD"))
        #expect(!CurrencyCatalog.hasValidPrecision(Decimal(string: "1.2345")!, currency: "KWD"))
    }

    @Test("search matches code and localized currency name")
    func search() {
        #expect(CurrencyCatalog.search("usd").contains { $0.code == "USD" })
        #expect(CurrencyCatalog.search("yen").contains { $0.code == "JPY" })
    }
}

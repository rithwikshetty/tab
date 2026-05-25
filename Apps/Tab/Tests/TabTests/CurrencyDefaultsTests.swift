import Foundation
import Testing
@testable import Tab

@Suite("Currency defaults")
struct CurrencyDefaultsTests {
    @Test("empty trip uses the user's saved currency before device region")
    func emptyTripUsesSavedCurrencyBeforeRegion() {
        let defaults = isolatedDefaults()
        CurrencyDefaults.remember("JPY", defaults: defaults)

        let trip = TripEntity(name: "Tokyo", createdByID: UUID())
        let currency = CurrencyDefaults.defaultCurrency(
            for: trip,
            defaults: defaults,
            locale: Locale(identifier: "en_US")
        )

        #expect(currency == "JPY")
    }

    @Test("trip's most recently used active currency beats saved currency and device region")
    func tripRecentCurrencyBeatsSavedAndRegion() {
        let defaults = isolatedDefaults()
        CurrencyDefaults.remember("JPY", defaults: defaults)
        let userID = UUID()
        let trip = TripEntity(name: "Lisbon", createdByID: userID)
        trip.expenses = [
            expense(currency: "USD", createdByID: userID, createdAt: date(1), updatedAt: date(1), trip: trip),
            expense(currency: "CHF", createdByID: userID, createdAt: date(2), updatedAt: date(2), trip: trip)
        ]

        let currency = CurrencyDefaults.defaultCurrency(
            for: trip,
            defaults: defaults,
            locale: Locale(identifier: "en_GB")
        )

        #expect(currency == "CHF")
    }

    @Test("first run with no trip, no saved currency, and no region currency falls back to INR")
    func firstRunFallsBackToINR() {
        let currency = CurrencyDefaults.initialCurrency(
            defaults: isolatedDefaults(),
            locale: Locale(identifier: "en_001")
        )

        #expect(currency == "INR")
    }

    @Test("first run uses device region currency before INR fallback")
    func firstRunUsesDeviceRegionCurrency() {
        let currency = CurrencyDefaults.initialCurrency(
            defaults: isolatedDefaults(),
            locale: Locale(identifier: "en_GB")
        )

        #expect(currency == "GBP")
    }

    @Test("deleted and unsupported trip currencies are ignored")
    func deletedAndUnsupportedTripCurrenciesAreIgnored() {
        let userID = UUID()
        let trip = TripEntity(name: "Messy", createdByID: userID)
        trip.expenses = [
            expense(currency: "USD", createdByID: userID, createdAt: date(1), updatedAt: date(1), trip: trip),
            expense(currency: "JPY", createdByID: userID, createdAt: date(3), updatedAt: date(3), deletedAt: date(4), trip: trip),
            expense(currency: "XXX", createdByID: userID, createdAt: date(5), updatedAt: date(5), trip: trip)
        ]

        let currency = CurrencyDefaults.defaultCurrency(
            for: trip,
            defaults: isolatedDefaults(),
            locale: Locale(identifier: "en_GB")
        )

        #expect(currency == "USD")
    }

    @Test("settlements count as recent trip currency")
    func settlementsCountAsRecentTripCurrency() {
        let userID = UUID()
        let trip = TripEntity(name: "Multi", createdByID: userID)
        trip.expenses = [
            expense(currency: "USD", createdByID: userID, createdAt: date(1), updatedAt: date(1), trip: trip)
        ]
        trip.settlements = [
            settlement(currency: "AED", createdByID: userID, createdAt: date(4), updatedAt: date(4), trip: trip)
        ]

        let currency = CurrencyDefaults.defaultCurrency(
            for: trip,
            defaults: isolatedDefaults(),
            locale: Locale(identifier: "en_GB")
        )

        #expect(currency == "AED")
    }

    @Test("remembered currency is normalized and unsupported values are ignored")
    func rememberedCurrencyIsNormalizedAndUnsupportedValuesAreIgnored() {
        let defaults = isolatedDefaults()

        CurrencyDefaults.remember("usd", defaults: defaults)
        #expect(CurrencyDefaults.initialCurrency(defaults: defaults, locale: Locale(identifier: "en_GB")) == "USD")

        CurrencyDefaults.remember("not-a-code", defaults: defaults)
        #expect(CurrencyDefaults.initialCurrency(defaults: defaults, locale: Locale(identifier: "en_GB")) == "USD")
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "CurrencyDefaultsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func expense(
        currency: String,
        createdByID: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        trip: TripEntity
    ) -> ExpenseEntity {
        ExpenseEntity(
            amount: 10,
            currency: currency,
            descriptionText: "Test expense",
            expenseDate: createdAt,
            createdByID: createdByID,
            trip: trip,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    private func settlement(
        currency: String,
        createdByID: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        trip: TripEntity
    ) -> SettlementEntity {
        SettlementEntity(
            fromPersonID: UUID(),
            toPersonID: UUID(),
            amount: 10,
            currency: currency,
            settledAt: createdAt,
            createdByID: createdByID,
            trip: trip,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

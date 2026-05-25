import Foundation
import TabCore

enum CurrencyDefaults {
    static let fallbackCode = CurrencyCatalog.defaultCode

    private static let lastSelectedCurrencyKey = "tab.currency.lastSelected"

    static var initialCurrency: String {
        initialCurrency(defaults: .standard, locale: .current)
    }

    static func initialCurrency(defaults: UserDefaults = .standard, locale: Locale = .current) -> String {
        lastSelectedCurrency(defaults: defaults)
            ?? deviceRegionCurrency(locale: locale)
            ?? fallbackCode
    }

    static func defaultCurrency(
        for trip: TripEntity?,
        defaults: UserDefaults = .standard,
        locale: Locale = .current
    ) -> String {
        mostRecentTripCurrency(in: trip)
            ?? lastSelectedCurrency(defaults: defaults)
            ?? deviceRegionCurrency(locale: locale)
            ?? fallbackCode
    }

    static func remember(_ code: String, defaults: UserDefaults = .standard) {
        let normalized = CurrencyCatalog.normalizedCode(code)
        guard CurrencyCatalog.isSupported(normalized) else { return }
        defaults.set(normalized, forKey: lastSelectedCurrencyKey)
    }

    static func lastSelectedCurrency(defaults: UserDefaults = .standard) -> String? {
        guard let code = defaults.string(forKey: lastSelectedCurrencyKey) else { return nil }
        let normalized = CurrencyCatalog.normalizedCode(code)
        return CurrencyCatalog.isSupported(normalized) ? normalized : nil
    }

    static func deviceRegionCurrency(locale: Locale = .current) -> String? {
        guard let code = locale.currency?.identifier else { return nil }
        let normalized = CurrencyCatalog.normalizedCode(code)
        return CurrencyCatalog.isSupported(normalized) ? normalized : nil
    }

    static func mostRecentTripCurrency(in trip: TripEntity?) -> String? {
        guard let trip else { return nil }

        let expenseCandidates = trip.expenses.compactMap { expense -> CurrencyCandidate? in
            guard expense.deletedAt == nil else { return nil }
            return CurrencyCandidate(currency: expense.currency, date: max(expense.createdAt, expense.updatedAt))
        }

        let settlementCandidates = trip.settlements.compactMap { settlement -> CurrencyCandidate? in
            guard settlement.deletedAt == nil else { return nil }
            return CurrencyCandidate(currency: settlement.currency, date: max(settlement.createdAt, settlement.updatedAt))
        }

        return (expenseCandidates + settlementCandidates)
            .filter { CurrencyCatalog.isSupported($0.currency) }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.currency < rhs.currency
            }
            .first?
            .currency
    }
}

private struct CurrencyCandidate {
    let currency: String
    let date: Date

    init(currency: String, date: Date) {
        self.currency = CurrencyCatalog.normalizedCode(currency)
        self.date = date
    }
}

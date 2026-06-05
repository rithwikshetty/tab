import Foundation
import TabCore

enum MoneyFormatter {
    static func currencySymbol(_ code: String) -> String {
        CurrencyCatalog.displayMetadata(for: code).symbol
    }

    static func amountPlaceholder(currency: String) -> String {
        plainAmountString(0, currency: currency)
    }

    static func sanitizeAmountInput(_ input: String, currency: String) -> String {
        let fractionDigits = CurrencyCatalog.fractionDigits(for: currency)
        let normalized = input.replacingOccurrences(of: ",", with: ".")
        var output = ""
        var hasDecimalSeparator = false
        var fractionCount = 0

        for character in normalized {
            if character.isNumber {
                if hasDecimalSeparator {
                    guard fractionCount < fractionDigits else { continue }
                    fractionCount += 1
                }
                output.append(character)
            } else if character == ".", fractionDigits > 0, !hasDecimalSeparator {
                hasDecimalSeparator = true
                output.append(character)
            }
        }

        return output
    }

    static func decimal(from input: String) -> Decimal? {
        Decimal(string: input.replacingOccurrences(of: ",", with: "."))
    }

    static func plainAmountString(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = CurrencyCatalog.fractionDigits(for: currency)
        formatter.maximumFractionDigits = CurrencyCatalog.fractionDigits(for: currency)
        formatter.usesGroupingSeparator = false
        return formatter.string(from: amount as NSDecimalNumber) ?? NSDecimalNumber(decimal: amount).stringValue
    }

    static func format(_ amount: Decimal, currency: String) -> String {
        let metadata = CurrencyCatalog.displayMetadata(for: currency)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = metadata.fractionDigits
        formatter.maximumFractionDigits = metadata.fractionDigits
        formatter.usesGroupingSeparator = true
        let value = formatter.string(from: amount as NSDecimalNumber) ?? plainAmountString(amount, currency: currency)

        guard metadata.symbol.uppercased() != metadata.code else {
            return "\(metadata.code) \(value)"
        }
        return "\(metadata.code) \(metadata.symbol)\(value)"
    }

    static func format(_ money: Money) -> String {
        format(money.amount, currency: money.currency)
    }

    /// Like `format`, but without the ISO code prefix — just the symbol and amount
    /// (e.g. `£640.00`). Used where the currency is already established by context
    /// (the Overview tab is scoped to one currency). Falls back to the code when the
    /// currency has no distinct symbol, so disambiguation is never fully lost.
    static func formatSymbol(_ amount: Decimal, currency: String) -> String {
        let metadata = CurrencyCatalog.displayMetadata(for: currency)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = metadata.fractionDigits
        formatter.maximumFractionDigits = metadata.fractionDigits
        formatter.usesGroupingSeparator = true
        let value = formatter.string(from: amount as NSDecimalNumber) ?? plainAmountString(amount, currency: currency)

        guard metadata.symbol.uppercased() != metadata.code else {
            return "\(metadata.code) \(value)"
        }
        return "\(metadata.symbol)\(value)"
    }

    static func formatSigned(_ amount: Decimal, currency: String) -> String {
        let abs = amount < 0 ? -amount : amount
        let prefix: String = amount < 0 ? "-" : ""
        return prefix + format(abs, currency: currency)
    }
}

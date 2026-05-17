import Foundation
import TabCore

enum MoneyFormatter {
    static func currencySymbol(_ code: String) -> String {
        switch code.uppercased() {
        case "EUR": return "€"
        case "USD": return "$"
        case "GBP": return "£"
        case "JPY": return "¥"
        case "CHF": return "Fr"
        case "SEK", "NOK", "DKK": return "kr"
        default:    return code.uppercased() + " "
        }
    }

    static func format(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        let value = formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
        return "\(currencySymbol(currency))\(value)"
    }

    static func format(_ money: Money) -> String {
        format(money.amount, currency: money.currency)
    }

    static func formatSigned(_ amount: Decimal, currency: String) -> String {
        let abs = amount < 0 ? -amount : amount
        let prefix: String = amount < 0 ? "-" : ""
        return prefix + format(abs, currency: currency)
    }
}

import Foundation

/// Lightweight, shared email validation for invite/add flows. Intentionally
/// permissive (we never bounce a real address) but rejects shapes the server
/// would reject — including the `|` member-signature delimiter used by
/// non-group containers.
enum EmailValidator {
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValid(_ value: String) -> Bool {
        let email = normalized(value)
        guard !email.contains("|"), let at = email.firstIndex(of: "@") else { return false }
        let local = email[..<at]
        let domain = email[email.index(after: at)...]
        return !local.isEmpty && domain.contains(".") && !domain.hasSuffix(".")
    }
}

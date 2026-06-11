import Foundation
import Testing
@testable import Tab

@Suite("Email validator")
struct EmailValidatorTests {
    @Test("accepts a normal address")
    func acceptsNormal() {
        #expect(EmailValidator.isValid("alice@example.com"))
    }

    @Test("rejects an address with no domain dot")
    func rejectsNoDot() {
        #expect(!EmailValidator.isValid("a@b"))
    }

    @Test("rejects a missing local part or trailing-dot domain")
    func rejectsMalformed() {
        #expect(!EmailValidator.isValid("@example.com"))
        #expect(!EmailValidator.isValid("alice@example."))
        #expect(!EmailValidator.isValid("alice"))
    }

    @Test("rejects the member-signature delimiter the server forbids")
    func rejectsPipe() {
        #expect(!EmailValidator.isValid("b@b.com|c@c.com"))
    }

    @Test("is case- and whitespace-insensitive")
    func normalizes() {
        #expect(EmailValidator.isValid("  Alice@Example.COM  "))
    }
}

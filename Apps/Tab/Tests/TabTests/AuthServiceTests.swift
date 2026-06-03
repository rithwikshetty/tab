import Testing
@testable import Tab

@Suite("Auth service presentation")
struct AuthServiceTests {
    @Test("Apple private relay emails are hidden from user-facing labels")
    func privateRelayEmailsAreHidden() {
        let email = "ABC123@privaterelay.appleid.com"

        #expect(AuthService.isApplePrivateRelayEmail(email))
        #expect(AuthService.visibleEmail(from: email) == nil)
        #expect(AuthService.fallbackDisplayName(fromEmail: email) == "You")
    }

    @Test("regular emails remain visible and produce readable fallback names")
    func regularEmailsRemainVisible() {
        let email = "  rithwik@example.com  "

        #expect(!AuthService.isApplePrivateRelayEmail(email))
        #expect(AuthService.visibleEmail(from: email) == "rithwik@example.com")
        #expect(AuthService.fallbackDisplayName(fromEmail: email) == "Rithwik")
    }

    @Test("display names are trimmed and capped")
    func displayNamesAreNormalized() {
        let longName = "  " + String(repeating: "A", count: 80) + "  "

        #expect(AuthService.normalizedDisplayName("  Rithwik Shetty  ") == "Rithwik Shetty")
        #expect(AuthService.normalizedDisplayName(longName)?.count == 60)
        #expect(AuthService.normalizedDisplayName("   ") == nil)
    }

    @Test("email verification codes keep exactly eight digits")
    func verificationCodesAreNormalized() {
        #expect(AuthService.emailVerificationCodeLength == 8)
        #expect(AuthService.normalizedVerificationCode("12345678") == "12345678")
        #expect(AuthService.normalizedVerificationCode("1234 5678") == "12345678")
        #expect(AuthService.normalizedVerificationCode("abc12345678") == "12345678")
        #expect(AuthService.normalizedVerificationCode("1234567") == nil)
        #expect(AuthService.normalizedVerificationCode("123456789") == nil)
    }
}

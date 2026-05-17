import Testing
import Foundation
@testable import TabCore

@Suite("TabCore smoke")
struct SmokeTests {
    @Test("Money is constructible and Hashable")
    func moneyBasics() {
        let a = Money(amount: 10, currency: "EUR")
        let b = Money(amount: 10, currency: "EUR")
        let c = Money(amount: 10, currency: "USD")
        #expect(a == b)
        #expect(a != c)
    }
}

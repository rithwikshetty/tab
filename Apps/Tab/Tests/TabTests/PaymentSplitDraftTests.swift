import Foundation
import Testing
import TabCore
@testable import Tab

@MainActor
@Suite("Payment split draft")
struct PaymentSplitDraftTests {
    private let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let bob = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    @Test("removing the last extra payer in exact mode leaves a valid single payer")
    func exactModeUntoggleToOnePayerStaysValid() {
        let draft = PaymentSplitDraft()
        draft.selectedPayerIDs = [alice, bob]
        draft.setPayerMode(.exact, totalAmount: 100, currency: "USD")
        // The user edits an amount (so payerEdited becomes true), then removes Bob.
        draft.setExactPayerAmount("30", for: bob, currency: "USD")
        draft.togglePayer(bob, totalAmount: 100, currency: "USD")

        #expect(draft.selectedPayerIDs == [alice])
        // The lone remaining payer must resolve to a payable ledger, not a dead end.
        let payments = draft.computedPayments(totalAmount: 100, currency: "USD")
        #expect(payments != nil)
        #expect(payments?.count == 1)
        #expect(payments?.first?.amountPaid == 100)
    }

    @Test("a single exact payer covers the full total")
    func singleExactPayerCoversTotal() {
        let draft = PaymentSplitDraft()
        draft.selectedPayerIDs = [alice, bob]
        draft.setPayerMode(.exact, totalAmount: 80, currency: "USD")
        draft.togglePayer(bob, totalAmount: 80, currency: "USD")
        #expect(draft.computedPayments(totalAmount: 80, currency: "USD")?.first?.amountPaid == 80)
    }
}

import Foundation

public typealias PaymentMode = SplitType

public struct Payment: Hashable, Codable, Sendable {
    public let payerID: UUID
    public let amountPaid: Decimal
    public let paymentMode: PaymentMode

    public init(payerID: UUID, amountPaid: Decimal, paymentMode: PaymentMode) {
        self.payerID = payerID
        self.amountPaid = amountPaid
        self.paymentMode = paymentMode
    }
}

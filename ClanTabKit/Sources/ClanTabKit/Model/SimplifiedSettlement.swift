import Foundation

/// One transaction in the minimal settle-up plan produced by `Simplify.simplify`.
/// `fromId` should pay `toId` `amountMinor` (in `currency`) to move both members'
/// balances toward zero. The plan is computed per currency and never nets across
/// currencies.
public struct SimplifiedSettlement: Codable, Sendable, Equatable, Hashable {
    public let fromId: String
    public let toId: String
    public let amountMinor: Int64
    public let currency: String

    public init(fromId: String, toId: String, amountMinor: Int64, currency: String) {
        self.fromId = fromId
        self.toId = toId
        self.amountMinor = amountMinor
        self.currency = currency
    }
}

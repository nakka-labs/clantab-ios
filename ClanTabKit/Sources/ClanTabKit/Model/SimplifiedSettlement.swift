import Foundation

/// One transaction in the minimal settle-up plan produced by `Simplify.simplify`.
/// `fromId` should pay `toId` `amountMinor` to move both members' balances toward zero.
public struct SimplifiedSettlement: Codable, Sendable, Equatable {
    public let fromId: String
    public let toId: String
    public let amountMinor: Int64

    public init(fromId: String, toId: String, amountMinor: Int64) {
        self.fromId = fromId
        self.toId = toId
        self.amountMinor = amountMinor
    }
}

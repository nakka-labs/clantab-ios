import Foundation

/// A member's net position in one currency, derived from expenses and settlements
/// — never stored or cached, always recomputed on read (see `Balances.compute`).
///
/// `netMinor` is positive when the member is owed money, negative when they owe
/// money. A member with activity in more than one currency has one `Balance` per
/// currency; the currencies are never blended (no FX).
public struct Balance: Codable, Sendable, Equatable {
    public let memberId: String
    public let currency: String
    public let netMinor: Int64

    public init(memberId: String, currency: String, netMinor: Int64) {
        self.memberId = memberId
        self.currency = currency
        self.netMinor = netMinor
    }
}

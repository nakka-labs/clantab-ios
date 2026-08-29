import Foundation

/// A member's net position, derived from expenses and settlements — never stored or
/// cached, always recomputed on read (see `Balances.compute`).
///
/// `netMinor` is positive when the member is owed money, negative when they owe money.
public struct Balance: Codable, Sendable, Equatable {
    public let memberId: String
    public let netMinor: Int64

    public init(memberId: String, netMinor: Int64) {
        self.memberId = memberId
        self.netMinor = netMinor
    }
}

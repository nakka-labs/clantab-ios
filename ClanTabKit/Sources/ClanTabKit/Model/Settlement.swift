import Foundation

/// A recorded "I paid this outside the app" event between two members. Settling is
/// trust-based — ClanTab never processes payments, it only records that one happened.
public struct Settlement: Identifiable, Codable, Sendable {
    public let id: String
    public let fromId: String
    public let toId: String
    public let amountMinor: Int64
    /// ISO 4217 code. A settlement clears debt in exactly one currency — you
    /// can't net ₹500 owed against $45 owed.
    public let currency: String
    public let date: Date

    public init(id: String, fromId: String, toId: String, amountMinor: Int64, currency: String, date: Date) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.amountMinor = amountMinor
        self.currency = currency
        self.date = date
    }
}

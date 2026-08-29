import Foundation

/// A recorded "I paid this outside the app" event between two members. Settling is
/// trust-based — ClanTab never processes payments, it only records that one happened.
public struct Settlement: Identifiable, Codable, Sendable {
    public let id: String
    public let fromId: String
    public let toId: String
    public let amountMinor: Int64
    public let date: Date

    public init(id: String, fromId: String, toId: String, amountMinor: Int64, date: Date) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.amountMinor = amountMinor
        self.date = date
    }
}

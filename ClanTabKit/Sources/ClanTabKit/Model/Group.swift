import Foundation

/// A shared ledger for a small group (5-10 people). Addressed by an unguessable
/// capability `id` (the shareable link) and a low-entropy human-typeable `joinCode`.
/// See `DESIGN.md` §1 for why these are two different identifiers.
public struct Group: Identifiable, Codable, Sendable {
    public let id: String
    public let joinCode: String
    public let name: String
    public let currency: String
    public let createdAt: Date
    public var members: [Member]

    public init(
        id: String,
        joinCode: String,
        name: String,
        currency: String,
        createdAt: Date,
        members: [Member]
    ) {
        self.id = id
        self.joinCode = joinCode
        self.name = name
        self.currency = currency
        self.createdAt = createdAt
        self.members = members
    }
}

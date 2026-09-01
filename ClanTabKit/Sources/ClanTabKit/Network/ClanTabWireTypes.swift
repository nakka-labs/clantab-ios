import Foundation

// Wire request/response DTOs for the API contract in `DESIGN.md` §2. Model types
// (`Member`, `Expense`, `Settlement`, `Balance`, `SimplifiedSettlement`) are reused
// directly wherever the wire shape matches them exactly.

/// The subset of `Group` fields the server returns alongside other resources.
/// `id` is already known by the caller (the capability URL). `joinCode` is
/// returned from both `POST /api/groups` and `GET /api/groups/:groupId`
/// (`DESIGN.md` §2/§12) so Group Home can re-share it, not just the
/// post-creation confirmation step.
public struct GroupSummary: Codable, Sendable, Equatable {
    public let name: String
    public let currency: String
    public let createdAt: Date
    public let joinCode: String

    public init(name: String, currency: String, createdAt: Date, joinCode: String) {
        self.name = name
        self.currency = currency
        self.createdAt = createdAt
        self.joinCode = joinCode
    }
}

/// The server's structured error body: `{ "error": { "code", "message" } }`.
struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }
    let error: Body
}

// MARK: - POST /api/groups

public struct CreateGroupRequest: Encodable, Sendable {
    public let name: String
    public let currency: String
    public let creatorDisplayName: String

    public init(name: String, currency: String, creatorDisplayName: String) {
        self.name = name
        self.currency = currency
        self.creatorDisplayName = creatorDisplayName
    }
}

public struct CreateGroupResponse: Decodable, Sendable {
    public let groupId: String
    public let joinCode: String
    public let member: Member
    public let group: GroupSummary
}

// MARK: - GET /api/groups/resolve/:joinCode

public struct ResolveJoinCodeResponse: Decodable, Sendable {
    public let groupId: String
}

// MARK: - POST /api/groups/:groupId/members

public struct JoinGroupRequest: Encodable, Sendable {
    public let displayName: String

    public init(displayName: String) {
        self.displayName = displayName
    }
}

public struct JoinGroupResponse: Decodable, Sendable {
    public let member: Member
}

// MARK: - GET /api/groups/:groupId

public struct GroupStateResponse: Decodable, Sendable {
    public let group: GroupSummary
    public let members: [Member]
    public let expenses: [Expense]
    public let settlements: [Settlement]
    public let balances: [Balance]
    public let simplifiedSettlements: [SimplifiedSettlement]
}

// MARK: - POST /api/groups/:groupId/expenses

public struct AddExpenseRequest: Sendable {
    /// Optional client-generated id (`DESIGN.md` §2): a retried POST with the same
    /// id is treated as an idempotent no-op replay rather than a duplicate.
    public let id: String?
    public let payerId: String
    public let amountMinor: Int64
    /// ISO 4217 code the expense (and every split) is in.
    public let currency: String
    public let description: String
    public let date: Date
    public let splitType: SplitType
    public let splits: [ExpenseSplit]
    public let category: String?
    public let categoryIcon: String?

    public init(
        id: String? = nil,
        payerId: String,
        amountMinor: Int64,
        currency: String,
        description: String,
        date: Date,
        splitType: SplitType,
        splits: [ExpenseSplit],
        category: String? = nil,
        categoryIcon: String? = nil
    ) {
        self.id = id
        self.payerId = payerId
        self.amountMinor = amountMinor
        self.currency = currency
        self.description = description
        self.date = date
        self.splitType = splitType
        self.splits = splits
        self.category = category
        self.categoryIcon = categoryIcon
    }
}

extension AddExpenseRequest: Encodable {
    private enum CodingKeys: String, CodingKey {
        case id, payerId, amountMinor, currency, description, date, splitType, splits, category, categoryIcon
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Optional fields are genuinely optional on the wire (DESIGN.md §2) — omit
        // the key entirely rather than encoding an explicit `null`.
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(payerId, forKey: .payerId)
        try container.encode(amountMinor, forKey: .amountMinor)
        try container.encode(currency, forKey: .currency)
        try container.encode(description, forKey: .description)
        try container.encode(date, forKey: .date)
        try container.encode(splitType, forKey: .splitType)
        try container.encode(splits, forKey: .splits)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(categoryIcon, forKey: .categoryIcon)
    }
}

public struct AddExpenseResponse: Decodable, Sendable {
    public let expense: Expense
}

// MARK: - POST /api/groups/:groupId/settlements

public struct AddSettlementRequest: Sendable {
    public let id: String?
    public let fromId: String
    public let toId: String
    public let amountMinor: Int64
    public let currency: String

    public init(id: String? = nil, fromId: String, toId: String, amountMinor: Int64, currency: String) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.amountMinor = amountMinor
        self.currency = currency
    }
}

extension AddSettlementRequest: Encodable {
    private enum CodingKeys: String, CodingKey {
        case id, fromId, toId, amountMinor, currency
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(fromId, forKey: .fromId)
        try container.encode(toId, forKey: .toId)
        try container.encode(amountMinor, forKey: .amountMinor)
        try container.encode(currency, forKey: .currency)
    }
}

public struct AddSettlementResponse: Decodable, Sendable {
    public let settlement: Settlement
}

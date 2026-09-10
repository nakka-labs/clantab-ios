import Foundation

// Wire request/response DTOs for the API contract in `DESIGN.md` §2. Model types
// (`Member`, `Expense`, `Settlement`, `Balance`, `SimplifiedSettlement`) are reused
// directly wherever the wire shape matches them exactly.

/// The subset of `Group` fields the server returns alongside other resources.
/// `id` is already known by the caller (the capability URL). `joinCode` is
/// returned from both `POST /api/groups` and `GET /api/groups/:groupId`
/// (`DESIGN.md` §2/§12) so Group Home can re-share it, not just the
/// post-creation confirmation step.
///
/// `accessToken` (`ACCESS_TOKEN_PLAN.md`) is the rotatable capability-link
/// credential, separate from `groupId` itself — re-shareable for the same
/// reason `joinCode` is: whoever's asking already holds valid access, so the
/// current token exposes nothing new. `nil` only for a group that predates
/// this feature and has never had its link regenerated — `groupId`
/// possession alone still works for one of those, unchanged.
public struct GroupSummary: Codable, Sendable, Equatable {
    public let name: String
    public let currency: String
    public let createdAt: Date
    public let joinCode: String
    public let accessToken: String?
    /// A single emoji the group picked as its visual identity (`CHECKLIST.md`
    /// "Group visual identity"), or `nil` if it has none. Shown in the groups
    /// list and the Group Home header; set via `updateGroup`.
    public let emoji: String?
    /// When the group was archived (`CHECKLIST.md` "Archive a group") — a
    /// group-wide "this trip is over, hide it" flag, `nil` while active.
    /// Toggled via `updateGroup(archived:)`.
    public let archivedAt: Date?
    /// The group's saved default split (`FEATURE_BACKLOG.md` "Default split
    /// config per group") — percentage weights that pre-fill Add Expense.
    /// `nil` = split equally among everyone. Set via `updateGroup(defaultSplit:)`.
    public let defaultSplit: DefaultSplit?

    public init(
        name: String, currency: String, createdAt: Date, joinCode: String,
        accessToken: String? = nil, emoji: String? = nil, archivedAt: Date? = nil,
        defaultSplit: DefaultSplit? = nil
    ) {
        self.name = name
        self.currency = currency
        self.createdAt = createdAt
        self.joinCode = joinCode
        self.accessToken = accessToken
        self.emoji = emoji
        self.archivedAt = archivedAt
        self.defaultSplit = defaultSplit
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
    /// The group's *current* access token (`ACCESS_TOKEN_PLAN.md` Part 3) —
    /// always up to date even across a link rotation, since a code is
    /// resolved fresh each time rather than bookmarked.
    public let accessToken: String?
}

// MARK: - POST /api/groups/:groupId/regenerate-link

public struct RegenerateLinkResponse: Decodable, Sendable {
    public let accessToken: String
}

// MARK: - POST /api/groups/:groupId/view-link

public struct ViewLinkResponse: Decodable, Sendable {
    /// The read-only capability secret (`FEATURE_BACKLOG.md` "Read-only web
    /// link for balances") — authorizes only `GET /g/:groupId/balances`.
    public let viewToken: String
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

// MARK: - PATCH /api/groups/:groupId/members/:memberId

/// Whether an optional request field should be left alone, cleared, or set to
/// a new value — encodes as "omit the key" / explicit JSON `null` /
/// the value, matching the worker's `optionalStringOrNull` (empty-string
/// values are never valid here — `null` is the one unambiguous "clear").
public enum FieldUpdate<Value: Sendable>: Sendable {
    case unchanged
    case cleared
    case set(Value)
}

/// Rename a member and/or set their UPI VPA (`FEATURE_BACKLOG.md` "UPI deep
/// link on Settle Up") — at least one of the two, enforced server-side.
public struct UpdateMemberRequest: Encodable, Sendable {
    public let displayName: String?
    private let upiVpaUpdate: FieldUpdate<String>

    public init(displayName: String? = nil, upiVpa: FieldUpdate<String> = .unchanged) {
        self.displayName = displayName
        self.upiVpaUpdate = upiVpa
    }

    private enum CodingKeys: String, CodingKey { case displayName, upiVpa }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        switch upiVpaUpdate {
        case .unchanged: break
        case .cleared: try container.encodeNil(forKey: .upiVpa)
        case .set(let value): try container.encode(value, forKey: .upiVpa)
        }
    }
}

// MARK: - PATCH /api/groups/:groupId

public struct UpdateGroupRequest: Encodable, Sendable {
    public let name: String?
    public let currency: String?
    /// The group's visual-identity emoji (`CHECKLIST.md` "Group visual
    /// identity") — `.unchanged` omits the key, `.cleared` sends `null`,
    /// `.set` sends the emoji, matching the worker's `optionalStringOrNull`.
    private let emojiUpdate: FieldUpdate<String>
    /// Archive (`true`) / unarchive (`false`) the group (`CHECKLIST.md`
    /// "Archive a group"); `nil` omits the key. The server stamps / clears
    /// the `archived_at` timestamp itself.
    private let archived: Bool?
    /// The group's default split (`FEATURE_BACKLOG.md` "Default split config
    /// per group") — `.unchanged` omits the key, `.cleared` sends `null`
    /// ("split equally"), `.set` sends the weights.
    private let defaultSplitUpdate: FieldUpdate<DefaultSplit>

    public init(
        name: String? = nil, currency: String? = nil,
        emoji: FieldUpdate<String> = .unchanged, archived: Bool? = nil,
        defaultSplit: FieldUpdate<DefaultSplit> = .unchanged
    ) {
        self.name = name
        self.currency = currency
        self.emojiUpdate = emoji
        self.archived = archived
        self.defaultSplitUpdate = defaultSplit
    }

    private enum CodingKeys: String, CodingKey { case name, currency, emoji, archived, defaultSplit }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(archived, forKey: .archived)
        switch emojiUpdate {
        case .unchanged: break
        case .cleared: try container.encodeNil(forKey: .emoji)
        case .set(let value): try container.encode(value, forKey: .emoji)
        }
        switch defaultSplitUpdate {
        case .unchanged: break
        case .cleared: try container.encodeNil(forKey: .defaultSplit)
        case .set(let value): try container.encode(value, forKey: .defaultSplit)
        }
    }
}

public struct UpdateGroupResponse: Decodable, Sendable {
    public let group: GroupSummary
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
    /// The line items an `itemized` expense was built from — `nil` (key omitted)
    /// for every other `splitType`. `splits` is still resolved client-side and
    /// carries the balance-affecting shares; the server stores `items` alongside
    /// for display / re-edit and validates the two agree (`DESIGN.md` §6).
    public let items: [LineItem]?
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
        items: [LineItem]? = nil,
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
        self.items = items
        self.category = category
        self.categoryIcon = categoryIcon
    }
}

extension AddExpenseRequest: Encodable {
    private enum CodingKeys: String, CodingKey {
        case id, payerId, amountMinor, currency, description, date, splitType, splits, items, category, categoryIcon
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
        try container.encodeIfPresent(items, forKey: .items)
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

// MARK: - GET /api/groups/:groupId/trash
// POST /api/groups/:groupId/{expenses,settlements}/:id/restore
// (restore decodes into AddExpenseResponse/AddSettlementResponse — same shape)

/// Soft-deleted expenses/settlements, newest-deleted first
/// (`FEATURE_BACKLOG.md` "Delete goes to trash, with attribution").
public struct TrashResponse: Decodable, Sendable {
    public let expenses: [Expense]
    public let settlements: [Settlement]
}

// MARK: - POST /api/groups/:groupId/report

/// A group's name/content in general, or one specific member — Apple
/// Guideline 1.2 requires a report mechanism for shared user-generated
/// content (`SHIP_PLAN.md` Track 3 §7). "Block" is the existing "Remove"
/// member action in `GroupSettingsView`; this is the other half.
public enum ReportTarget: Sendable, Equatable {
    case group
    case member(id: String)
}

public struct ReportRequest: Encodable, Sendable {
    public let targetType: String
    public let targetId: String?
    public let reason: String
    public let details: String?

    public init(target: ReportTarget, reason: String, details: String? = nil) {
        switch target {
        case .group:
            self.targetType = "group"
            self.targetId = nil
        case .member(let id):
            self.targetType = "member"
            self.targetId = id
        }
        self.reason = reason
        self.details = details
    }

    private enum CodingKeys: String, CodingKey { case targetType, targetId, reason, details }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetType, forKey: .targetType)
        try container.encodeIfPresent(targetId, forKey: .targetId)
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(details, forKey: .details)
    }
}

public struct ReportResponse: Decodable, Sendable {
    public struct Report: Decodable, Sendable, Equatable {
        public let id: String
        public let groupId: String
        public let targetType: String
        public let targetId: String?
        public let reason: String
        public let details: String?
        public let reportedBy: String?
        public let createdAt: Date
    }
    public let report: Report
}

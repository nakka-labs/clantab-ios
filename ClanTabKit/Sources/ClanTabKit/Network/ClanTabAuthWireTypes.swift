import Foundation

// Wire request/response DTOs for the accounts endpoints (`ACCOUNTS_DESIGN.md`
// §5–§7, §11). All additive — the pre-accounts routes and their types are
// untouched. Sign in with Apple gates only these identity-scoped calls; guest
// access and the capability link stay exactly as they were.

// MARK: - POST /api/auth/apple

public struct AppleSignInRequest: Encodable, Sendable {
    /// The JWT from `ASAuthorizationAppleIDCredential.identityToken`.
    public let identityToken: String
    /// `ASAuthorizationAppleIDCredential.authorizationCode`, if present — the
    /// server exchanges it for a refresh token so it can revoke on account
    /// deletion (`ACCOUNTS_DESIGN.md` §11). Only sent on a fresh sign-in.
    public let authorizationCode: String?

    public init(identityToken: String, authorizationCode: String? = nil) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
    }

    private enum CodingKeys: String, CodingKey { case identityToken, authorizationCode }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identityToken, forKey: .identityToken)
        try container.encodeIfPresent(authorizationCode, forKey: .authorizationCode)
    }
}

// MARK: - POST /api/auth/google

/// `MANDATORY_LOGIN_PLAN.md` Part 1 — no `authorizationCode` equivalent: the
/// Google flow here requests no offline access, so there's no refresh token to
/// exchange.
public struct GoogleSignInRequest: Encodable, Sendable {
    /// The ID token from the Authorization Code + PKCE exchange
    /// (`GoogleSignInButton`), not the official Google Sign-In SDK.
    public let identityToken: String

    public init(identityToken: String) {
        self.identityToken = identityToken
    }
}

/// One of the signed-in identity's group memberships, as the server's identity
/// index knows it (`ACCOUNTS_DESIGN.md` §7). `displayName` is denormalised from
/// the group at claim time.
public struct GroupMembershipSummary: Codable, Sendable, Equatable, Identifiable {
    public let groupId: String
    public let memberId: String
    public let displayName: String
    /// `true` only for an auto-created private 1:1 tab (`CHECKLIST.md`
    /// "Friends/contacts list... + private 1:1 tabs") — the client omits it
    /// from the visible groups list / dashboard totals. Optional so a
    /// response predating this field (or an older cached fixture) still
    /// decodes; `nil` reads the same as `false`.
    public let hidden: Bool?

    public var id: String { groupId }
    /// `hidden`'s "or false" reading — the call-site-friendly form.
    public var isHidden: Bool { hidden == true }

    public init(groupId: String, memberId: String, displayName: String, hidden: Bool? = nil) {
        self.groupId = groupId
        self.memberId = memberId
        self.displayName = displayName
        self.hidden = hidden
    }
}

/// `POST /api/auth/apple` and `POST /api/auth/refresh`. `groups` is present on
/// sign-in and absent on refresh.
public struct SessionResponse: Decodable, Sendable {
    public let sessionToken: String
    public let expiresAt: Date
    public let groups: [GroupMembershipSummary]?
}

// MARK: - GET /api/auth/groups

public struct MyGroupsResponse: Decodable, Sendable {
    public let groups: [GroupMembershipSummary]
}

// MARK: - GET /api/auth/groups/balances  (dashboard fallback sync)

/// The signed-in member's own nonzero balances in one group, per currency —
/// the fallback path that keeps `KnownGroupsStore.myBalances` current when a
/// push was missed or notifications are denied (`CHECKLIST.md` "Dashboard
/// fallback sync for missed/denied push").
public struct GroupBalanceSummary: Decodable, Sendable, Equatable {
    public let groupId: String
    public let balances: [Balance]
    /// When the group was archived (`CHECKLIST.md` "Archive a group"), so the
    /// dashboard can hide it without opening every group. `nil` = active.
    public let archivedAt: Date?

    public init(groupId: String, balances: [Balance], archivedAt: Date? = nil) {
        self.groupId = groupId
        self.balances = balances
        self.archivedAt = archivedAt
    }
}

public struct GroupBalancesResponse: Decodable, Sendable {
    public let groups: [GroupBalanceSummary]
}

// MARK: - GET /api/auth/people  (cross-group settling)

/// The caller's net with one linked person in one currency. `netMinor > 0`
/// means the caller owes them; `< 0` means they owe the caller. Nonzero only.
public struct CrossGroupNet: Codable, Sendable, Equatable {
    public let currency: String
    public let netMinor: Int64

    public init(currency: String, netMinor: Int64) {
        self.currency = currency
        self.netMinor = netMinor
    }
}

/// One group's simplified settle-up edge between the caller and a linked
/// person. The caller settles each of these with an ordinary `addSettlement`.
public struct CrossGroupEdge: Codable, Sendable, Equatable, Identifiable {
    public let groupId: String
    public let groupName: String
    public let currency: String
    public let amountMinor: Int64
    /// `true` → the caller pays; `false` → the person pays the caller.
    public let youPay: Bool
    public let myMemberId: String
    public let theirMemberId: String

    public var id: String { "\(groupId)-\(currency)" }

    public init(
        groupId: String, groupName: String, currency: String, amountMinor: Int64,
        youPay: Bool, myMemberId: String, theirMemberId: String
    ) {
        self.groupId = groupId
        self.groupName = groupName
        self.currency = currency
        self.amountMinor = amountMinor
        self.youPay = youPay
        self.myMemberId = myMemberId
        self.theirMemberId = theirMemberId
    }
}

public struct CrossGroupPerson: Codable, Sendable, Equatable, Identifiable {
    /// Opaque, server-assigned — never the Apple `sub`.
    public let id: String
    public let displayName: String
    public let net: [CrossGroupNet]
    /// The `groups` key on the wire — the per-group edges.
    public let groups: [CrossGroupEdge]

    public init(id: String, displayName: String, net: [CrossGroupNet], groups: [CrossGroupEdge]) {
        self.id = id
        self.displayName = displayName
        self.net = net
        self.groups = groups
    }
}

public struct PeopleAcrossGroupsResponse: Decodable, Sendable {
    public let people: [CrossGroupPerson]
}

// MARK: - GET /api/auth/friends (CHECKLIST.md "Friends/contacts list... + private 1:1 tabs")

/// One group the caller shares with a `Friend` — a formal group, or (once it
/// exists) their private 1:1 tab. Used both for display and as the proof pair
/// for `ClanTabClient.ensureFriendTab` (the caller must have a claimed member
/// here, and `theirMemberId` a different one).
public struct FriendGroup: Codable, Sendable, Equatable, Identifiable {
    public let groupId: String
    public let groupName: String
    /// `true` only for the private 1:1 tab, once it exists.
    public let hidden: Bool
    public let myMemberId: String
    public let theirMemberId: String

    public var id: String { groupId }

    public init(groupId: String, groupName: String, hidden: Bool, myMemberId: String, theirMemberId: String) {
        self.groupId = groupId
        self.groupName = groupName
        self.hidden = hidden
        self.myMemberId = myMemberId
        self.theirMemberId = theirMemberId
    }
}

/// One other claimed person the caller shares a group with — formal or a
/// private 1:1 tab — regardless of balance. Unlike `CrossGroupPerson` (a
/// settle-up worklist, nonzero-only), this is a directory: a settled friend
/// still appears.
public struct Friend: Codable, Sendable, Equatable, Identifiable {
    /// Opaque, server-assigned — never the Apple/Google `sub`.
    public let id: String
    public let displayName: String
    public let net: [CrossGroupNet]
    public let groups: [FriendGroup]

    public init(id: String, displayName: String, net: [CrossGroupNet], groups: [FriendGroup]) {
        self.id = id
        self.displayName = displayName
        self.net = net
        self.groups = groups
    }

    /// The private 1:1 tab's groupId, if one already exists between the
    /// caller and this friend.
    public var existingTabGroupId: String? {
        groups.first { $0.hidden }?.groupId
    }

    /// The group to send as proof when calling `ensureFriendTab` — the
    /// existing private tab if there is one (re-opening it needs no new
    /// proof), else any shared formal group. `nil` only if `groups` is
    /// somehow empty, which shouldn't happen for a real friend.
    public var tabProofGroup: FriendGroup? {
        groups.first { $0.hidden } ?? groups.first
    }
}

public struct FriendsResponse: Decodable, Sendable {
    public let friends: [Friend]
}

// MARK: - POST /api/auth/friends/tab

/// Ensure the private 1:1 tab between the caller and a friend exists, and
/// return it — safe to call any number of times (`CHECKLIST.md`
/// "Friends/contacts list... + private 1:1 tabs").
public struct EnsureFriendTabRequest: Encodable, Sendable {
    /// Any group the caller shares with this friend (`Friend.tabProofGroup`).
    public let groupId: String
    public let theirMemberId: String
    /// The caller's own display name — seeds the tab's member row the first
    /// time it's created; a no-op on every call after.
    public let myDisplayName: String
    /// The friend's display name, as the caller currently knows it (from
    /// `Friend.displayName`) — same "seeds on first call only" contract.
    public let theirDisplayName: String
    /// The tab's starting currency, only used the first time it's created —
    /// the currency of the shared group the friendship was found through.
    public let currency: String

    public init(groupId: String, theirMemberId: String, myDisplayName: String, theirDisplayName: String, currency: String) {
        self.groupId = groupId
        self.theirMemberId = theirMemberId
        self.myDisplayName = myDisplayName
        self.theirDisplayName = theirDisplayName
        self.currency = currency
    }
}

public struct EnsureFriendTabResponse: Decodable, Sendable {
    public let groupId: String
    public let accessToken: String
}

// MARK: - POST /api/auth/devices

/// Register an APNs device token for push (`FEATURE_BACKLOG.md` "Push
/// notifications"). Idempotent — safe to send on every launch.
public struct RegisterDeviceRequest: Encodable, Sendable {
    public let token: String
    public let platform: String

    public init(token: String, platform: String = "ios") {
        self.token = token
        self.platform = platform
    }
}

// MARK: - GET /api/groups/:groupId/claimable

public struct ClaimableMembersResponse: Decodable, Sendable {
    /// This group's placeholder members (`identity_sub IS NULL`) — the "this is
    /// me" picker list.
    public let members: [Member]
}

// MARK: - POST /api/groups/:groupId/members/:memberId/claim

public struct ClaimMemberResponse: Decodable, Sendable {
    public let member: Member
}

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

    public var id: String { groupId }

    public init(groupId: String, memberId: String, displayName: String) {
        self.groupId = groupId
        self.memberId = memberId
        self.displayName = displayName
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

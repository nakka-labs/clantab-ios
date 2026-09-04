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

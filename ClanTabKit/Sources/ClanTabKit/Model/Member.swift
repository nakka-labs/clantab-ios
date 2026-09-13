import Foundation

/// A participant in a `Group` — a placeholder name, or one linked to a
/// signed-in identity (Sign in with Apple/Google) via `isClaimed`.
public struct Member: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let displayName: String
    /// UPI VPA (e.g. "name@bank"), user-supplied and never verified or
    /// processed by ClanTab (`FEATURE_BACKLOG.md` "UPI deep link on Settle
    /// Up") — `nil` for a member who hasn't set one.
    public let upiVpa: String?
    /// R2 object key for this member's profile photo (`CHECKLIST.md` "Profile
    /// photos"), set by the server from the linked identity — `nil` for a guest
    /// or a claimed member whose identity has no photo. Resolve it to a URL with
    /// `ClanTabClient.presignMediaView`; fall back to `MemberColor` initials.
    public let avatarKey: String?
    /// Whether this member is linked to a signed-in identity — never the
    /// identity itself, just the boolean (`CHECKLIST.md` R4/R1). A claimed
    /// member's `displayName`/`upiVpa` can only change via that identity, not
    /// a plain group-settings rename; the server enforces this independently.
    public let isClaimed: Bool

    public init(id: String, displayName: String, upiVpa: String? = nil, avatarKey: String? = nil, isClaimed: Bool) {
        self.id = id
        self.displayName = displayName
        self.upiVpa = upiVpa
        self.avatarKey = avatarKey
        self.isClaimed = isClaimed
    }
}

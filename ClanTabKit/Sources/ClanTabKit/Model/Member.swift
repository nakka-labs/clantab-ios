import Foundation

/// A participant in a `Group`. Identity is device-local (chosen once, stored in
/// UserDefaults per group) — there are no accounts or passwords.
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

    public init(id: String, displayName: String, upiVpa: String? = nil, avatarKey: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.upiVpa = upiVpa
        self.avatarKey = avatarKey
    }
}

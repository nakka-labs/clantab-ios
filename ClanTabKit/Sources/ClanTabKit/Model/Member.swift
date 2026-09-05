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

    public init(id: String, displayName: String, upiVpa: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.upiVpa = upiVpa
    }
}

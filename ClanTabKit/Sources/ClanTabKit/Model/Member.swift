import Foundation

/// A participant in a `Group`. Identity is device-local (chosen once, stored in
/// UserDefaults per group) — there are no accounts or passwords.
public struct Member: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

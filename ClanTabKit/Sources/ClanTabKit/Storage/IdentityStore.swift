import Foundation

/// Who "you" are in one group, remembered locally on this device. Mirrors the web
/// client's `identity.ts` (`DESIGN.md` §7): there is no account, so this local
/// record — not a login — is what lets the app greet you by name and pre-fill
/// `payerId` when you add an expense.
public struct GroupIdentity: Codable, Sendable, Equatable {
    public let memberId: String
    public let displayName: String

    public init(memberId: String, displayName: String) {
        self.memberId = memberId
        self.displayName = displayName
    }
}

/// Abstracts local persistence of per-group identity so ClanTabKit's callers never
/// depend on a concrete storage mechanism. The app supplies `UserDefaultsIdentityStore`;
/// tests and previews use `InMemoryIdentityStore`.
public protocol IdentityStoring: Sendable {
    func identity(forGroup groupId: String) -> GroupIdentity?
    func setIdentity(_ identity: GroupIdentity, forGroup groupId: String)
    func removeIdentity(forGroup groupId: String)
}

/// `UserDefaults`-backed identity store, namespaced `"clantab:<groupId>"` — the
/// same key scheme as the web client's `localStorage["clantab:" + groupId]`.
public final class UserDefaultsIdentityStore: IdentityStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func identity(forGroup groupId: String) -> GroupIdentity? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.key(for: groupId)) else { return nil }
        return try? JSONDecoder().decode(GroupIdentity.self, from: data)
    }

    public func setIdentity(_ identity: GroupIdentity, forGroup groupId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(identity) else { return }
        defaults.set(data, forKey: Self.key(for: groupId))
    }

    public func removeIdentity(forGroup groupId: String) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.key(for: groupId))
    }

    private static func key(for groupId: String) -> String {
        "clantab:\(groupId)"
    }
}

/// In-memory identity store for tests and SwiftUI previews — never persists across
/// launches.
public final class InMemoryIdentityStore: IdentityStoring, @unchecked Sendable {
    private var storage: [String: GroupIdentity] = [:]
    private let lock = NSLock()

    public init() {}

    public func identity(forGroup groupId: String) -> GroupIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return storage[groupId]
    }

    public func setIdentity(_ identity: GroupIdentity, forGroup groupId: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[groupId] = identity
    }

    public func removeIdentity(forGroup groupId: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: groupId)
    }
}

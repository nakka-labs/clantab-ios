import Foundation

/// Per-group capability-link credentials (`ACCESS_TOKEN_PLAN.md`,
/// `DESIGN.md` §8) — the rotatable `?token=` secret carried on every
/// group-data route. Kept **out** of the `UserDefaults` blob that holds a
/// group's display fields (`name`/`emoji`/`myBalances`): `access_token` is
/// the same class of secret as the session token, so it gets the same
/// Keychain protection (`CHECKLIST.md` "move `KnownGroup.accessToken` into
/// the Keychain"). `UserDefaultsKnownGroupsStore` owns one of these and
/// merges the token back onto each `KnownGroup` on read.
public protocol GroupAccessTokenStoring: Sendable {
    func token(for groupId: String) -> String?
    /// Insert or replace `groupId`'s token.
    func setToken(_ token: String, for groupId: String)
    /// Drop `groupId`'s token — on leaving/forgetting the group.
    func removeToken(for groupId: String)
}

/// In-memory access-token store for tests and previews — never persists.
public final class InMemoryGroupAccessTokenStore: GroupAccessTokenStoring, @unchecked Sendable {
    private var tokens: [String: String]
    private let lock = NSLock()

    public init(_ tokens: [String: String] = [:]) {
        self.tokens = tokens
    }

    public func token(for groupId: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return tokens[groupId]
    }

    public func setToken(_ token: String, for groupId: String) {
        lock.lock(); defer { lock.unlock() }
        tokens[groupId] = token
    }

    public func removeToken(for groupId: String) {
        lock.lock(); defer { lock.unlock() }
        tokens[groupId] = nil
    }
}

#if canImport(Security)
import Security

/// Keychain-backed access-token store — one `kSecClassGenericPassword` item
/// holding a `[groupId: token]` JSON map, `kSecAttrAccessibleAfterFirstUnlock`
/// so a background launch (an App Intent, a push handler) can read it before
/// the device is unlocked, exactly like `KeychainSessionStore`.
public final class KeychainGroupAccessTokenStore: GroupAccessTokenStoring, @unchecked Sendable {
    private let service: String
    private let account = "groupAccessTokens"
    private let lock = NSLock()

    public init(service: String = "com.clantab.app.groupAccessTokens") {
        self.service = service
    }

    public func token(for groupId: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return load()[groupId]
    }

    public func setToken(_ token: String, for groupId: String) {
        lock.lock(); defer { lock.unlock() }
        var map = load()
        guard map[groupId] != token else { return }
        map[groupId] = token
        save(map)
    }

    public func removeToken(for groupId: String) {
        lock.lock(); defer { lock.unlock() }
        var map = load()
        guard map[groupId] != nil else { return }
        map[groupId] = nil
        save(map)
    }

    private func load() -> [String: String] {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    private func save(_ map: [String: String]) {
        if map.isEmpty {
            SecItemDelete(baseQuery() as CFDictionary)
            return
        }
        guard let data = try? JSONEncoder().encode(map) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery()
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
#endif

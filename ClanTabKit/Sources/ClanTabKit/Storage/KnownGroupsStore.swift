import Foundation

/// A group this device knows about — the entry behind the start screen's "Your
/// Groups" list. For a guest this list *is* their set of groups (whatever invite
/// links they've opened here); for a signed-in user it's a local cache of the
/// server's authoritative list (`ACCOUNTS_DESIGN.md` §7), so the list still
/// renders offline.
public struct KnownGroup: Codable, Sendable, Equatable, Identifiable {
    public let groupId: String
    /// Best-known group name for the list UI. Empty until the first group-state
    /// load fills it in (a join/deep-link only yields a `groupId`).
    public var name: String
    public var lastOpenedAt: Date
    /// The group's current access token (`ACCESS_TOKEN_PLAN.md`) — `nil` for a
    /// group that predates the feature and was never regenerated, or one this
    /// device only ever learned about via `GET /api/auth/groups` (which
    /// doesn't return a token; the Bearer-session alternate credential covers
    /// that case server-side instead).
    ///
    /// **Not** part of `Codable` — it's a credential, so
    /// `UserDefaultsKnownGroupsStore` keeps it in the Keychain
    /// (`GroupAccessTokenStoring`) rather than the `UserDefaults` display blob
    /// (`CHECKLIST.md` / `DESIGN.md` §8) and merges it back onto each group on
    /// read. In-memory holders (`InMemoryKnownGroupsStore`) just carry it.
    public var accessToken: String? = nil
    /// The group's visual-identity emoji (`CHECKLIST.md` "Group visual
    /// identity"), cached from the last group-state load so the "Your Groups"
    /// list can show it offline. `nil` = the group has none.
    public var emoji: String?
    /// The signed-in member's own balances in this group, last time it was
    /// fetched — the "you owe / you're owed" line on the groups list. `nil`
    /// means "never fetched yet," distinct from `[]` ("fetched, settled up")
    /// — the list shows nothing for the former rather than a misleading
    /// "Settled up" for a group that hasn't loaded once.
    public var myBalances: [Balance]?
    /// When the group was archived (`CHECKLIST.md` "Archive a group"), cached
    /// from the last group-state load or dashboard reconcile so the "Your
    /// Groups" list can hide it offline. `nil` = active.
    public var archivedAt: Date?

    public var isArchived: Bool { archivedAt != nil }

    public var id: String { groupId }

    /// `accessToken` is deliberately absent — see its doc comment. The
    /// synthesized `Codable` conformance uses these keys, so the token is
    /// never written to or read from the `UserDefaults` blob.
    enum CodingKeys: String, CodingKey {
        case groupId, name, lastOpenedAt, emoji, myBalances, archivedAt
    }

    public init(
        groupId: String, name: String, lastOpenedAt: Date, accessToken: String? = nil,
        emoji: String? = nil, myBalances: [Balance]? = nil, archivedAt: Date? = nil
    ) {
        self.groupId = groupId
        self.name = name
        self.lastOpenedAt = lastOpenedAt
        self.accessToken = accessToken
        self.emoji = emoji
        self.myBalances = myBalances
        self.archivedAt = archivedAt
    }
}

/// Abstracts local persistence of the known-groups list. The app supplies
/// `UserDefaultsKnownGroupsStore`; tests and previews use
/// `InMemoryKnownGroupsStore`.
public protocol KnownGroupsStoring: Sendable {
    /// Most recently opened first.
    func all() -> [KnownGroup]
    /// Insert or update. Always bumps `lastOpenedAt` to `date`. A non-empty
    /// `name` replaces the stored one; `nil` leaves the stored name untouched
    /// (so a join, which has no name, never clobbers a cached one). Same for
    /// `accessToken` — `nil` leaves whatever's already stored alone, so a
    /// caller that doesn't have the current token handy (e.g. mirroring
    /// `GET /api/auth/groups`) never clobbers one learned elsewhere.
    func remember(groupId: String, name: String?, accessToken: String?, at date: Date)
    /// Drop a group from the list (its capability URL now 404s, or the account
    /// was deleted).
    func forget(groupId: String)
    /// Update the cached balance summary for an already-known group — a
    /// no-op if the group isn't known (shouldn't happen: entering a group
    /// always `remember`s it first). Deliberately separate from `remember`:
    /// this fires on every refetch, including the ~25s background poll, and
    /// shouldn't bump `lastOpenedAt` on every tick the way `remember` does.
    func updateBalances(groupId: String, myBalances: [Balance])

    /// Update the cached visual-identity emoji for an already-known group —
    /// `nil` clears it (the group's emoji was removed). No-op if the group
    /// isn't known. Separate from `remember` for the same reason
    /// `updateBalances` is: it fires on every state load, not just on open.
    func setEmoji(groupId: String, emoji: String?)

    /// Update the cached archived-at timestamp (`CHECKLIST.md` "Archive a
    /// group") — `nil` means the group is active again. No-op if the group
    /// isn't known. Same "fires on every state load / reconcile" rationale as
    /// `setEmoji`.
    func setArchivedAt(groupId: String, archivedAt: Date?)
}

public extension KnownGroupsStoring {
    func remember(groupId: String, name: String? = nil, accessToken: String? = nil, at date: Date = Date()) {
        remember(groupId: groupId, name: name, accessToken: accessToken, at: date)
    }
}

/// `UserDefaults`-backed known-groups list, stored as one JSON array under
/// `"clantab.knownGroups"` — display fields only. Each group's `accessToken`
/// is a credential and lives in the Keychain instead
/// (`GroupAccessTokenStoring`, `DESIGN.md` §8); `all()` merges it back on.
public final class UserDefaultsKnownGroupsStore: KnownGroupsStoring, @unchecked Sendable {
    private static let key = "clantab.knownGroups"
    private let defaults: UserDefaults
    private let accessTokens: any GroupAccessTokenStoring
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        accessTokens: any GroupAccessTokenStoring = defaultAccessTokenStore()
    ) {
        self.defaults = defaults
        self.accessTokens = accessTokens
        migrateLegacyAccessTokens()
    }

    public func all() -> [KnownGroup] {
        lock.lock(); defer { lock.unlock() }
        return load()
            .map { group in
                var group = group
                group.accessToken = accessTokens.token(for: group.groupId)
                return group
            }
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    public func remember(groupId: String, name: String?, accessToken: String?, at date: Date) {
        lock.lock(); defer { lock.unlock() }
        var groups = load()
        if let index = groups.firstIndex(where: { $0.groupId == groupId }) {
            groups[index].lastOpenedAt = date
            if let name, !name.isEmpty { groups[index].name = name }
        } else {
            groups.append(KnownGroup(groupId: groupId, name: name ?? "", lastOpenedAt: date))
        }
        save(groups)
        // `nil` never clobbers a token learned elsewhere (mirrors the
        // `name` rule) — see `KnownGroupsStoring.remember`'s doc comment.
        if let accessToken { accessTokens.setToken(accessToken, for: groupId) }
    }

    public func forget(groupId: String) {
        lock.lock(); defer { lock.unlock() }
        save(load().filter { $0.groupId != groupId })
        accessTokens.removeToken(for: groupId)
    }

    public func updateBalances(groupId: String, myBalances: [Balance]) {
        lock.lock(); defer { lock.unlock() }
        var groups = load()
        guard let index = groups.firstIndex(where: { $0.groupId == groupId }) else { return }
        groups[index].myBalances = myBalances
        save(groups)
    }

    public func setEmoji(groupId: String, emoji: String?) {
        lock.lock(); defer { lock.unlock() }
        var groups = load()
        guard let index = groups.firstIndex(where: { $0.groupId == groupId }) else { return }
        groups[index].emoji = emoji
        save(groups)
    }

    public func setArchivedAt(groupId: String, archivedAt: Date?) {
        lock.lock(); defer { lock.unlock() }
        var groups = load()
        guard let index = groups.firstIndex(where: { $0.groupId == groupId }) else { return }
        groups[index].archivedAt = archivedAt
        save(groups)
    }

    /// One-time move of any `accessToken` still embedded in an older
    /// `UserDefaults` blob into the Keychain store, then rewrite the blob
    /// without it. Runs on `init`; a no-op once every blob is clean.
    private func migrateLegacyAccessTokens() {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.key),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        var found = false
        for entry in raw {
            guard let groupId = entry["groupId"] as? String,
                  let token = entry["accessToken"] as? String, !token.isEmpty
            else { continue }
            found = true
            if accessTokens.token(for: groupId) == nil {
                accessTokens.setToken(token, for: groupId)
            }
        }
        if found { save(load()) } // re-encodes without `accessToken` (not a CodingKey)
    }

    private func load() -> [KnownGroup] {
        guard let data = defaults.data(forKey: Self.key),
              let groups = try? JSONDecoder().decode([KnownGroup].self, from: data)
        else { return [] }
        return groups
    }

    private func save(_ groups: [KnownGroup]) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// `KeychainGroupAccessTokenStore` where the Security framework exists (Apple
/// platforms), an in-memory store elsewhere (Linux CI) — the same
/// `#if canImport(Security)` split `KeychainSessionStore` uses.
public func defaultAccessTokenStore() -> any GroupAccessTokenStoring {
    #if canImport(Security)
    KeychainGroupAccessTokenStore()
    #else
    InMemoryGroupAccessTokenStore()
    #endif
}

/// In-memory known-groups store for tests and SwiftUI previews.
public final class InMemoryKnownGroupsStore: KnownGroupsStoring, @unchecked Sendable {
    private var groups: [KnownGroup]
    private let lock = NSLock()

    public init(_ groups: [KnownGroup] = []) {
        self.groups = groups
    }

    public func all() -> [KnownGroup] {
        lock.lock(); defer { lock.unlock() }
        return groups.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    public func remember(groupId: String, name: String?, accessToken: String?, at date: Date) {
        lock.lock(); defer { lock.unlock() }
        if let index = groups.firstIndex(where: { $0.groupId == groupId }) {
            groups[index].lastOpenedAt = date
            if let name, !name.isEmpty { groups[index].name = name }
            if let accessToken { groups[index].accessToken = accessToken }
        } else {
            groups.append(KnownGroup(groupId: groupId, name: name ?? "", lastOpenedAt: date, accessToken: accessToken))
        }
    }

    public func forget(groupId: String) {
        lock.lock(); defer { lock.unlock() }
        groups.removeAll { $0.groupId == groupId }
    }

    public func updateBalances(groupId: String, myBalances: [Balance]) {
        lock.lock(); defer { lock.unlock() }
        guard let index = groups.firstIndex(where: { $0.groupId == groupId }) else { return }
        groups[index].myBalances = myBalances
    }

    public func setEmoji(groupId: String, emoji: String?) {
        lock.lock(); defer { lock.unlock() }
        guard let index = groups.firstIndex(where: { $0.groupId == groupId }) else { return }
        groups[index].emoji = emoji
    }

    public func setArchivedAt(groupId: String, archivedAt: Date?) {
        lock.lock(); defer { lock.unlock() }
        guard let index = groups.firstIndex(where: { $0.groupId == groupId }) else { return }
        groups[index].archivedAt = archivedAt
    }
}

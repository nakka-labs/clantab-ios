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
    public var accessToken: String?
    /// The signed-in member's own balances in this group, last time it was
    /// fetched — the "you owe / you're owed" line on the groups list. `nil`
    /// means "never fetched yet," distinct from `[]` ("fetched, settled up")
    /// — the list shows nothing for the former rather than a misleading
    /// "Settled up" for a group that hasn't loaded once.
    public var myBalances: [Balance]?

    public var id: String { groupId }

    public init(groupId: String, name: String, lastOpenedAt: Date, accessToken: String? = nil, myBalances: [Balance]? = nil) {
        self.groupId = groupId
        self.name = name
        self.lastOpenedAt = lastOpenedAt
        self.accessToken = accessToken
        self.myBalances = myBalances
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
}

public extension KnownGroupsStoring {
    func remember(groupId: String, name: String? = nil, accessToken: String? = nil, at date: Date = Date()) {
        remember(groupId: groupId, name: name, accessToken: accessToken, at: date)
    }
}

/// `UserDefaults`-backed known-groups list, stored as one JSON array under
/// `"clantab.knownGroups"`.
public final class UserDefaultsKnownGroupsStore: KnownGroupsStoring, @unchecked Sendable {
    private static let key = "clantab.knownGroups"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func all() -> [KnownGroup] {
        lock.lock(); defer { lock.unlock() }
        return load().sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    public func remember(groupId: String, name: String?, accessToken: String?, at date: Date) {
        lock.lock(); defer { lock.unlock() }
        var groups = load()
        if let index = groups.firstIndex(where: { $0.groupId == groupId }) {
            groups[index].lastOpenedAt = date
            if let name, !name.isEmpty { groups[index].name = name }
            if let accessToken { groups[index].accessToken = accessToken }
        } else {
            groups.append(KnownGroup(groupId: groupId, name: name ?? "", lastOpenedAt: date, accessToken: accessToken))
        }
        save(groups)
    }

    public func forget(groupId: String) {
        lock.lock(); defer { lock.unlock() }
        save(load().filter { $0.groupId != groupId })
    }

    public func updateBalances(groupId: String, myBalances: [Balance]) {
        lock.lock(); defer { lock.unlock() }
        var groups = load()
        guard let index = groups.firstIndex(where: { $0.groupId == groupId }) else { return }
        groups[index].myBalances = myBalances
        save(groups)
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
}

import Foundation

/// Persists when a "Remind" nudge (`ClanTabClient.remind`) was last sent, per
/// settle-up edge (`CHECKLIST.md` D10) — `MemberProfileView.remindSent` used
/// to be a bare `@State` `Set`, so the "sent" checkmark reset the moment the
/// screen closed and reopened, with nothing stopping the same person being
/// re-reminded on every single visit. One JSON blob in `UserDefaults`, same
/// shape as `BalanceAgingStoring`; a missing key means "never reminded."
public protocol RemindHistoryStoring: Sendable {
    func load() -> [String: Date]
    func save(_ map: [String: Date])
}

public final class UserDefaultsRemindHistoryStore: RemindHistoryStoring, @unchecked Sendable {
    private static let key = "clantab.remindHistory"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [String: Date] {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.key),
              let map = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return map
    }

    public func save(_ map: [String: Date]) {
        lock.lock(); defer { lock.unlock() }
        if map.isEmpty {
            defaults.removeObject(forKey: Self.key)
            return
        }
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// In-memory remind history for tests and previews.
public final class InMemoryRemindHistoryStore: RemindHistoryStoring, @unchecked Sendable {
    private var map: [String: Date]
    private let lock = NSLock()

    public init(_ map: [String: Date] = [:]) {
        self.map = map
    }

    public func load() -> [String: Date] {
        lock.lock(); defer { lock.unlock() }
        return map
    }

    public func save(_ map: [String: Date]) {
        lock.lock(); defer { lock.unlock() }
        self.map = map
    }
}

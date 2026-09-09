import Foundation

/// Persists the balance-aging map (`BalanceAging`) — per `(groupId, currency)`,
/// when the debt started and whether its nudge has fired. One JSON blob in
/// `UserDefaults`; a missing key means "not currently owed".
public protocol BalanceAgingStoring: Sendable {
    func load() -> [String: BalanceAgingEntry]
    func save(_ map: [String: BalanceAgingEntry])
}

public final class UserDefaultsBalanceAgingStore: BalanceAgingStoring, @unchecked Sendable {
    private static let key = "clantab.balanceAging"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [String: BalanceAgingEntry] {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.key),
              let map = try? JSONDecoder().decode([String: BalanceAgingEntry].self, from: data)
        else { return [:] }
        return map
    }

    public func save(_ map: [String: BalanceAgingEntry]) {
        lock.lock(); defer { lock.unlock() }
        if map.isEmpty {
            defaults.removeObject(forKey: Self.key)
            return
        }
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// In-memory aging map for tests and previews.
public final class InMemoryBalanceAgingStore: BalanceAgingStoring, @unchecked Sendable {
    private var map: [String: BalanceAgingEntry]
    private let lock = NSLock()

    public init(_ map: [String: BalanceAgingEntry] = [:]) {
        self.map = map
    }

    public func load() -> [String: BalanceAgingEntry] {
        lock.lock(); defer { lock.unlock() }
        return map
    }

    public func save(_ map: [String: BalanceAgingEntry]) {
        lock.lock(); defer { lock.unlock() }
        self.map = map
    }
}

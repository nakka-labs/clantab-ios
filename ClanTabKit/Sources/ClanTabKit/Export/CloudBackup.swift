import Foundation

/// A lossless, self-describing snapshot of one group's ledger, built for an
/// off-device backup destination (`CHECKLIST.md` "CloudKit backup, tier 2").
///
/// This is a *backup*, never a source of truth: the worker's `GroupDO` stays
/// authoritative (`AGENTS.md`, `DESIGN.md`). Nothing in the app reads a
/// `CloudBackupSnapshot` back into live state — it exists so a user who loses
/// every device can still recover their groups' data (via the CloudKit
/// Dashboard today, a restore flow later).
///
/// Same shape as `Export.json`'s `Snapshot` (group name + currency + the three
/// model arrays), plus the identity/versioning fields a bare backup blob needs
/// to be interpreted on its own: which group it belongs to, when it was taken,
/// and which schema wrote it.
/// Not `Equatable`: `Expense`/`Settlement` aren't (same as `Export.Snapshot`).
/// Compare two snapshots by their `CloudBackup.encode` bytes instead.
public struct CloudBackupSnapshot: Codable, Sendable {
    /// Bump when the payload shape changes incompatibly. A restore path reads
    /// this first and refuses a newer version it doesn't understand rather
    /// than silently mis-parsing it.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// The group's permanent capability id (`DESIGN.md` §1) — the backup's
    /// primary key, so re-backing-up the same group overwrites rather than
    /// accumulates.
    public let groupId: String
    public let capturedAt: Date
    public let groupName: String
    public let currency: String
    public let members: [Member]
    public let expenses: [Expense]
    public let settlements: [Settlement]

    public init(
        schemaVersion: Int = CloudBackupSnapshot.currentSchemaVersion,
        groupId: String,
        capturedAt: Date,
        groupName: String,
        currency: String,
        members: [Member],
        expenses: [Expense],
        settlements: [Settlement]
    ) {
        self.schemaVersion = schemaVersion
        self.groupId = groupId
        self.capturedAt = capturedAt
        self.groupName = groupName
        self.currency = currency
        self.members = members
        self.expenses = expenses
        self.settlements = settlements
    }
}

/// Pure builders for the backup payload — no CloudKit, no I/O, so this compiles
/// and tests on Linux CI alongside the rest of `ClanTabKit`. The App target's
/// `CloudKitGroupBackup` wraps the encoded bytes in a `CKRecord` and writes it
/// to the user's private database.
public enum CloudBackup {
    /// One record per group; a re-backup replaces it in place.
    public static func recordName(forGroupId groupId: String) -> String {
        "group-\(groupId)"
    }

    public static func snapshot(
        groupId: String,
        groupName: String,
        currency: String,
        members: [Member],
        expenses: [Expense],
        settlements: [Settlement],
        capturedAt: Date
    ) -> CloudBackupSnapshot {
        CloudBackupSnapshot(
            groupId: groupId,
            capturedAt: capturedAt,
            groupName: groupName,
            currency: currency,
            members: members,
            expenses: expenses,
            settlements: settlements
        )
    }

    /// Deterministic bytes for a snapshot — pretty-printed, key-sorted, ISO
    /// 8601 dates, matching `Export.json`'s conventions so a backup blob reads
    /// the same as a hand-triggered export.
    public static func encode(_ snapshot: CloudBackupSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> CloudBackupSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CloudBackupSnapshot.self, from: data)
    }

    /// A content fingerprint of the encoded payload, used only to skip a
    /// CloudKit write when nothing has changed since the last one — not a
    /// security primitive, so a fast non-cryptographic hash (FNV-1a, 64-bit)
    /// is enough and keeps `ClanTabKit` dependency-free (`AGENTS.md`). Same
    /// spirit as the djb2 hue hash in `OKLCH`.
    public static func checksum(of data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(hash, radix: 16)
    }
}

/// When the off-device backup is due — pure, so it's testable without a clock,
/// `UserDefaults`, or CloudKit. Same shape as `BackupNudge.shouldShow`, but
/// this backup is silent and cheap (a write to the user's own private
/// database), so it runs far more often than the visible 30-day nudge card —
/// just throttled so a burst of refetches doesn't hammer CloudKit.
public enum CloudBackupSchedule {
    /// Minimum gap between writes when the ledger *has* changed — a refetch
    /// after every add/edit/delete would otherwise fire one per mutation.
    public static let minimumInterval: TimeInterval = 10 * 60
    /// Re-write at least this often even when the ledger is unchanged, so the
    /// backup record's own freshness (and existence) is defended against a
    /// lost or never-completed earlier write.
    public static let refreshInterval: TimeInterval = 24 * 60 * 60

    public static func shouldBackUp(
        now: Date = Date(),
        lastBackupAt: Date?,
        lastChecksum: String?,
        currentChecksum: String
    ) -> Bool {
        guard let lastBackupAt else { return true }
        let elapsed = now.timeIntervalSince(lastBackupAt)
        if lastChecksum != currentChecksum {
            return elapsed >= minimumInterval
        }
        return elapsed >= refreshInterval
    }
}

/// The last successful backup's timestamp + payload checksum, per group — what
/// `CloudBackupSchedule` needs to decide whether to write again. Mirrors
/// `BackupNudgeStoring`'s tiny persistence surface.
public struct CloudBackupState: Codable, Sendable, Equatable {
    public let lastBackupAt: Date
    public let checksum: String

    public init(lastBackupAt: Date, checksum: String) {
        self.lastBackupAt = lastBackupAt
        self.checksum = checksum
    }
}

public protocol CloudBackupStateStoring: Sendable {
    func state(forGroupId groupId: String) -> CloudBackupState?
    func record(_ state: CloudBackupState, forGroupId groupId: String)
}

/// `UserDefaults`-backed, one JSON dictionary keyed by groupId.
public final class UserDefaultsCloudBackupStateStore: CloudBackupStateStoring, @unchecked Sendable {
    private static let key = "clantab.cloudBackup.state"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func state(forGroupId groupId: String) -> CloudBackupState? {
        lock.lock(); defer { lock.unlock() }
        return load()[groupId]
    }

    public func record(_ state: CloudBackupState, forGroupId groupId: String) {
        lock.lock(); defer { lock.unlock() }
        var all = load()
        all[groupId] = state
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private func load() -> [String: CloudBackupState] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: CloudBackupState].self, from: data)
        else { return [:] }
        return decoded
    }
}

/// In-memory state store for tests and previews.
public final class InMemoryCloudBackupStateStore: CloudBackupStateStoring, @unchecked Sendable {
    private var states: [String: CloudBackupState]
    private let lock = NSLock()

    public init(_ states: [String: CloudBackupState] = [:]) {
        self.states = states
    }

    public func state(forGroupId groupId: String) -> CloudBackupState? {
        lock.lock(); defer { lock.unlock() }
        return states[groupId]
    }

    public func record(_ state: CloudBackupState, forGroupId groupId: String) {
        lock.lock(); defer { lock.unlock() }
        states[groupId] = state
    }
}

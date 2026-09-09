import CloudKit
import Foundation
import ClanTabKit

/// Writes a lossless per-group ledger snapshot somewhere off-device
/// (`CHECKLIST.md` "CloudKit backup, tier 2"). A *backup destination only* —
/// nothing reads it back into live state; the worker's `GroupDO` stays the
/// single source of truth (`AGENTS.md`). Injected into `GroupViewModel` so
/// tests get the no-op and skip CloudKit entirely.
protocol GroupBackupWriting: Sendable {
    func backUpIfNeeded(
        groupId: String,
        groupName: String,
        currency: String,
        members: [Member],
        expenses: [Expense],
        settlements: [Settlement]
    ) async
}

/// Default in `GroupViewModel` and used by every test/preview — the real
/// `CloudKitGroupBackup` is wired in only at `GroupHomeView`'s construction
/// site, so nothing touches `CKContainer` unless the app is actually running.
struct NoOpGroupBackup: GroupBackupWriting {
    func backUpIfNeeded(
        groupId: String, groupName: String, currency: String,
        members: [Member], expenses: [Expense], settlements: [Settlement]
    ) async {}
}

/// Snapshots a group's ledger into the user's **private** CloudKit database,
/// one `GroupBackup` record per group (keyed by `CloudBackup.recordName`), so a
/// re-backup overwrites in place rather than piling up.
///
/// Best-effort throughout, exactly like `AuthViewModel.registerDeviceToken` and
/// the widget snapshot: every failure path is swallowed (no iCloud account, no
/// entitlement yet, offline, a CloudKit error) — a backup that doesn't happen
/// is never a user-facing problem, and the next refetch tries again.
///
/// Owner setup, same portal caveat as Sign in with Apple / push / App Groups
/// (`App/project.yml`): the **CloudKit** capability must be enabled on the App
/// ID and the `iCloud.com.clantab.app` container created before a TestFlight
/// build. Until then `accountStatus()` / the write just fail and this no-ops.
final class CloudKitGroupBackup: GroupBackupWriting {
    static let recordType = "GroupBackup"

    private let database: CKDatabase
    private let accountStatus: @Sendable () async -> CKAccountStatus
    private let stateStore: CloudBackupStateStoring
    private let now: @Sendable () -> Date

    init(
        container: CKContainer = .default(),
        stateStore: CloudBackupStateStoring = UserDefaultsCloudBackupStateStore(defaults: .standard),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.database = container.privateCloudDatabase
        self.accountStatus = { (try? await container.accountStatus()) ?? .couldNotDetermine }
        self.stateStore = stateStore
        self.now = now
    }

    func backUpIfNeeded(
        groupId: String,
        groupName: String,
        currency: String,
        members: [Member],
        expenses: [Expense],
        settlements: [Settlement]
    ) async {
        guard await accountStatus() == .available else { return }

        let timestamp = now()
        let snapshot = CloudBackup.snapshot(
            groupId: groupId, groupName: groupName, currency: currency,
            members: members, expenses: expenses, settlements: settlements,
            capturedAt: timestamp
        )
        guard let payload = try? CloudBackup.encode(snapshot) else { return }
        let checksum = CloudBackup.checksum(of: payload)

        let prior = stateStore.state(forGroupId: groupId)
        guard CloudBackupSchedule.shouldBackUp(
            now: timestamp,
            lastBackupAt: prior?.lastBackupAt,
            lastChecksum: prior?.checksum,
            currentChecksum: checksum
        ) else { return }

        // CKAsset needs a file on disk; a large group's JSON can also exceed
        // the per-field size soft limit, so the blob always goes via an asset.
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clantab-backup-\(groupId)-\(UUID().uuidString).json")
        guard (try? payload.write(to: assetURL, options: .atomic)) != nil else { return }
        defer { try? FileManager.default.removeItem(at: assetURL) }

        let record = Self.makeRecord(for: snapshot, payloadURL: assetURL, checksum: checksum)

        do {
            // `.allKeys` overwrites the existing record unconditionally — this
            // client is the only writer and always has the freshest ledger.
            let result = try await database.modifyRecords(
                saving: [record], deleting: [], savePolicy: .allKeys, atomically: true
            )
            // `atomically: true` throws on failure, but confirm the per-record
            // result too before treating the backup as done.
            guard case .success? = result.saveResults[record.recordID] else {
                print("CloudKit backup for \(groupId): save returned no success result")
                return
            }
            stateStore.record(CloudBackupState(lastBackupAt: timestamp, checksum: checksum), forGroupId: groupId)
            print("CloudKit backup ok: \(CloudBackup.recordName(forGroupId: groupId)) (\(snapshot.expenses.count) expenses, \(snapshot.settlements.count) settlements)")
        } catch {
            print("CloudKit backup failed for \(groupId): \(error)")
        }
    }

    /// Build the `CKRecord` from a snapshot. Metadata fields are plain
    /// (queryable in the CloudKit Dashboard); the full ledger rides in the
    /// `payload` asset. Pure enough to unit-test without an iCloud account.
    static func makeRecord(for snapshot: CloudBackupSnapshot, payloadURL: URL, checksum: String) -> CKRecord {
        let recordID = CKRecord.ID(recordName: CloudBackup.recordName(forGroupId: snapshot.groupId))
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["groupId"] = snapshot.groupId as CKRecordValue
        record["groupName"] = snapshot.groupName as CKRecordValue
        record["currency"] = snapshot.currency as CKRecordValue
        record["capturedAt"] = snapshot.capturedAt as CKRecordValue
        record["schemaVersion"] = snapshot.schemaVersion as CKRecordValue
        record["memberCount"] = snapshot.members.count as CKRecordValue
        record["expenseCount"] = snapshot.expenses.count as CKRecordValue
        record["settlementCount"] = snapshot.settlements.count as CKRecordValue
        record["checksum"] = checksum as CKRecordValue
        record["payload"] = CKAsset(fileURL: payloadURL)
        return record
    }
}

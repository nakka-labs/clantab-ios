import XCTest
import CloudKit
import ClanTabKit
@testable import ClanTab

final class CloudKitBackupTests: XCTestCase {
    private let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSnapshot() -> CloudBackupSnapshot {
        let alice = Member(id: "alice", displayName: "Alice")
        let bob = Member(id: "bob", displayName: "Bob")
        let expense = Expense(
            id: "e1", payerId: "alice", amountMinor: 1000, currency: "USD",
            description: "Dinner", date: capturedAt, splitType: .equal,
            splits: [
                ExpenseSplit(memberId: "alice", amountMinor: 500),
                ExpenseSplit(memberId: "bob", amountMinor: 500),
            ], category: nil
        )
        let settlement = Settlement(
            id: "s1", fromId: "bob", toId: "alice", amountMinor: 500,
            currency: "USD", date: capturedAt
        )
        return CloudBackup.snapshot(
            groupId: "grp-123", groupName: "Goa Trip", currency: "USD",
            members: [alice, bob], expenses: [expense], settlements: [settlement],
            capturedAt: capturedAt
        )
    }

    func testMakeRecordMapsMetadataAndAttachesPayloadAsset() throws {
        let snapshot = makeSnapshot()
        let payload = try CloudBackup.encode(snapshot)
        let checksum = CloudBackup.checksum(of: payload)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clantab-backup-test-\(UUID().uuidString).json")
        try payload.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let record = CloudKitGroupBackup.makeRecord(for: snapshot, payloadURL: url, checksum: checksum)

        XCTAssertEqual(record.recordType, "GroupBackup")
        // One deterministic record per group, so a re-backup overwrites it.
        XCTAssertEqual(record.recordID.recordName, "group-grp-123")
        XCTAssertEqual(record["groupId"] as? String, "grp-123")
        XCTAssertEqual(record["groupName"] as? String, "Goa Trip")
        XCTAssertEqual(record["currency"] as? String, "USD")
        XCTAssertEqual(record["capturedAt"] as? Date, capturedAt)
        XCTAssertEqual(record["schemaVersion"] as? Int, CloudBackupSnapshot.currentSchemaVersion)
        XCTAssertEqual(record["memberCount"] as? Int, 2)
        XCTAssertEqual(record["expenseCount"] as? Int, 1)
        XCTAssertEqual(record["settlementCount"] as? Int, 1)
        XCTAssertEqual(record["checksum"] as? String, checksum)

        let asset = try XCTUnwrap(record["payload"] as? CKAsset)
        XCTAssertEqual(asset.fileURL, url)
    }

    /// The no-op writer must never touch CloudKit — it's what every test and
    /// preview gets, and `GroupViewModel` defaults to it.
    func testNoOpBackupIsInert() async {
        await NoOpGroupBackup().backUpIfNeeded(
            groupId: "g", groupName: "G", currency: "USD",
            members: [], expenses: [], settlements: []
        )
    }
}

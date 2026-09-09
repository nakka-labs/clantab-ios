import Testing
import Foundation
@testable import ClanTabKit

@Suite("CloudBackup")
struct CloudBackupTests {
    private let alice = Member(id: "alice", displayName: "Alice")
    private let bob = Member(id: "bob", displayName: "Bob")
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func expense(id: String = "e1", amount: Int64 = 1250) -> Expense {
        Expense(
            id: id,
            payerId: alice.id,
            amountMinor: amount,
            currency: "USD",
            description: "Dinner",
            date: t0,
            splitType: .equal,
            splits: [
                ExpenseSplit(memberId: alice.id, amountMinor: amount - amount / 2),
                ExpenseSplit(memberId: bob.id, amountMinor: amount / 2),
            ],
            category: nil
        )
    }

    private func settlement(id: String = "s1") -> Settlement {
        Settlement(id: id, fromId: bob.id, toId: alice.id, amountMinor: 625, currency: "USD", date: t0)
    }

    private func makeSnapshot(expenses: [Expense]? = nil, settlements: [Settlement]? = nil) -> CloudBackupSnapshot {
        CloudBackup.snapshot(
            groupId: "grp-123",
            groupName: "Goa Trip",
            currency: "USD",
            members: [alice, bob],
            expenses: expenses ?? [expense()],
            settlements: settlements ?? [settlement()],
            capturedAt: t0
        )
    }

    @Test("record name is one stable key per group")
    func testRecordName() {
        #expect(CloudBackup.recordName(forGroupId: "grp-123") == "group-grp-123")
    }

    @Test("snapshot carries identity, schema version, and the full ledger")
    func testSnapshotContents() {
        let snapshot = makeSnapshot()
        #expect(snapshot.groupId == "grp-123")
        #expect(snapshot.groupName == "Goa Trip")
        #expect(snapshot.currency == "USD")
        #expect(snapshot.capturedAt == t0)
        #expect(snapshot.schemaVersion == CloudBackupSnapshot.currentSchemaVersion)
        #expect(snapshot.members.count == 2)
        #expect(snapshot.expenses.count == 1)
        #expect(snapshot.settlements.count == 1)
    }

    @Test("encode/decode round-trips losslessly")
    func testRoundTrip() throws {
        let snapshot = makeSnapshot(
            expenses: [expense(id: "e1"), expense(id: "e2", amount: 999)],
            settlements: [settlement(id: "s1"), settlement(id: "s2")]
        )
        let data = try CloudBackup.encode(snapshot)
        let decoded = try CloudBackup.decode(data)
        // Snapshots aren't Equatable (Expense/Settlement aren't) — re-encoding
        // the decoded value must reproduce the same deterministic bytes.
        #expect(try CloudBackup.encode(decoded) == data)
        #expect(decoded.groupId == snapshot.groupId)
        #expect(decoded.expenses.map(\.id) == ["e1", "e2"])
        #expect(decoded.settlements.map(\.id) == ["s1", "s2"])
    }

    @Test("encoding is deterministic — same input, identical bytes")
    func testDeterministicEncoding() throws {
        let a = try CloudBackup.encode(makeSnapshot())
        let b = try CloudBackup.encode(makeSnapshot())
        #expect(a == b)
    }

    @Test("checksum is stable for equal payloads and differs when the ledger changes")
    func testChecksum() throws {
        let base = try CloudBackup.encode(makeSnapshot())
        let same = try CloudBackup.encode(makeSnapshot())
        let changed = try CloudBackup.encode(makeSnapshot(expenses: [expense(id: "e1"), expense(id: "e2")]))

        #expect(CloudBackup.checksum(of: base) == CloudBackup.checksum(of: same))
        #expect(CloudBackup.checksum(of: base) != CloudBackup.checksum(of: changed))
    }
}

@Suite("CloudBackupSchedule")
struct CloudBackupScheduleTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("always backs up when there's no prior backup")
    func testFirstBackup() {
        #expect(CloudBackupSchedule.shouldBackUp(now: t0, lastBackupAt: nil, lastChecksum: nil, currentChecksum: "abc"))
    }

    @Test("a changed ledger backs up once the minimum interval has passed")
    func testChangedLedger() {
        let tooSoon = t0.addingTimeInterval(CloudBackupSchedule.minimumInterval - 1)
        #expect(!CloudBackupSchedule.shouldBackUp(now: tooSoon, lastBackupAt: t0, lastChecksum: "old", currentChecksum: "new"))

        let due = t0.addingTimeInterval(CloudBackupSchedule.minimumInterval)
        #expect(CloudBackupSchedule.shouldBackUp(now: due, lastBackupAt: t0, lastChecksum: "old", currentChecksum: "new"))
    }

    @Test("an unchecked ledger only re-writes on the slow refresh cadence")
    func testUnchangedLedger() {
        let withinDay = t0.addingTimeInterval(CloudBackupSchedule.refreshInterval - 1)
        #expect(!CloudBackupSchedule.shouldBackUp(now: withinDay, lastBackupAt: t0, lastChecksum: "same", currentChecksum: "same"))

        let nextDay = t0.addingTimeInterval(CloudBackupSchedule.refreshInterval)
        #expect(CloudBackupSchedule.shouldBackUp(now: nextDay, lastBackupAt: t0, lastChecksum: "same", currentChecksum: "same"))
    }
}

@Suite("CloudBackupStateStore")
struct CloudBackupStateStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("in-memory store starts empty and records per group")
    func testInMemory() {
        let store = InMemoryCloudBackupStateStore()
        #expect(store.state(forGroupId: "g1") == nil)

        store.record(CloudBackupState(lastBackupAt: t0, checksum: "aaa"), forGroupId: "g1")
        #expect(store.state(forGroupId: "g1") == CloudBackupState(lastBackupAt: t0, checksum: "aaa"))
        #expect(store.state(forGroupId: "g2") == nil)
    }

    @Test("UserDefaults store persists across instances, keyed by group")
    func testUserDefaultsPersistence() throws {
        let suite = "CloudBackupStateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        UserDefaultsCloudBackupStateStore(defaults: defaults)
            .record(CloudBackupState(lastBackupAt: t0, checksum: "xyz"), forGroupId: "g1")

        let reloaded = UserDefaultsCloudBackupStateStore(defaults: defaults).state(forGroupId: "g1")
        #expect(reloaded == CloudBackupState(lastBackupAt: t0, checksum: "xyz"))
    }
}

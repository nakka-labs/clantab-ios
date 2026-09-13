import CloudKit
import ClanTabKit
import SwiftUI

/// Settings row surfacing CloudKit backup status (`CHECKLIST.md` R15) — the
/// tier-2 backup (`CloudKitGroupBackup`) runs silently on every group visit;
/// this is the first in-app signal that it's working (or not) at all.
/// Read-only — no manual "Back Up Now" button, the automatic cadence
/// (`CloudBackupSchedule.shouldBackUp`) already covers the real need; the
/// request here reads more like "prove it's working," which a status line
/// answers without one.
struct CloudBackupStatusRow: View {
    let knownGroups: KnownGroupsStoring
    var stateStore: CloudBackupStateStoring = UserDefaultsCloudBackupStateStore(defaults: .standard)
    /// Injected so previews/tests never touch a real `CKContainer`.
    var accountStatus: @Sendable () async -> CKAccountStatus = {
        (try? await CKContainer.default().accountStatus()) ?? .couldNotDetermine
    }

    @State private var status: CKAccountStatus?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "icloud")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("iCloud Backup")
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task { status = await accountStatus() }
    }

    private var statusLine: String {
        guard let status else { return "Checking…" }
        guard status == .available else { return Self.line(forUnavailable: status) }
        switch CloudBackupSummary.compute(groupIds: knownGroups.all().map(\.groupId), stateStore: stateStore) {
        case .neverBackedUp:
            return "Not backed up yet"
        case .synced(let lastBackupAt):
            return "Last synced \(RemindHistory.relativeLabel(since: lastBackupAt))"
        case .failing(_, let lastBackupAt):
            guard let lastBackupAt else { return "Not syncing" }
            return "Not syncing — last success \(RemindHistory.relativeLabel(since: lastBackupAt))"
        }
    }

    /// `.available` never reaches here — `statusLine` branches on it first.
    private static func line(forUnavailable status: CKAccountStatus) -> String {
        switch status {
        case .noAccount: return "Not signed into iCloud"
        case .restricted: return "iCloud is restricted on this device"
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable"
        case .available, .couldNotDetermine: fallthrough
        @unknown default: return "Couldn't check iCloud status"
        }
    }
}

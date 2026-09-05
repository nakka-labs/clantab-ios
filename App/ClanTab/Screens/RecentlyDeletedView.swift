import SwiftUI
import ClanTabKit

/// "Recently Deleted" (`FEATURE_BACKLOG.md` "Delete goes to trash, with
/// attribution") — every soft-deleted expense and settlement in this group,
/// newest-deleted first, with Restore. Group Home's in-the-moment "Undo"
/// toast is quick access to this same restore action; this screen offers it
/// indefinitely after. No purge job — trash is kept forever.
struct RecentlyDeletedView: View {
    let groupId: String
    let client: ClanTabClient
    let accessToken: String?
    let members: [Member]
    /// Called after a successful restore, so the presenting screen can
    /// refetch and pick the item back up in the live ledger.
    let onRestored: () -> Void
    let onDone: () -> Void

    @State private var items: [ActivityItem]?
    @State private var loadError: String?
    @State private var restoringId: String?

    var body: some View {
        Form {
            if let items {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing Deleted",
                        systemImage: "trash",
                        description: Text("Deleted expenses and settlements show up here, and can be restored any time.")
                    )
                } else {
                    Section {
                        ForEach(items) { item in
                            HStack {
                                ActivityRow(item: item)
                                Spacer()
                                if restoringId == item.id {
                                    ProgressView()
                                } else {
                                    Button("Restore") { Task { await restore(item) } }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            } else if loadError == nil {
                Section {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                }
            }

            if let loadError {
                Section { Text(loadError).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
        }
        .task { await load() }
    }

    private func load() async {
        loadError = nil
        do {
            let trash = try await client.trash(groupId: groupId, accessToken: accessToken)
            items = (
                trash.expenses.map { ActivityItem(expense: $0, members: members) }
                    + trash.settlements.map { ActivityItem(settlement: $0, members: members) }
            )
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        } catch {
            loadError = friendlyMessage(for: error)
        }
    }

    private func restore(_ item: ActivityItem) async {
        restoringId = item.id
        defer { restoringId = nil }
        do {
            switch item.kind {
            case .expense(let expense):
                _ = try await client.restoreExpense(groupId: groupId, expenseId: expense.id, accessToken: accessToken)
            case .settlement(let settlement):
                _ = try await client.restoreSettlement(groupId: groupId, settlementId: settlement.id, accessToken: accessToken)
            }
            items?.removeAll { $0.id == item.id }
            onRestored()
        } catch {
            loadError = friendlyMessage(for: error)
        }
    }
}

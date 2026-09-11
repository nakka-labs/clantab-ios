import SwiftUI
import ClanTabKit

/// Add someone to the group by name alone, without leaving the sheet that
/// needed them (`CHECKLIST.md` "Add member inline from Add Expense") — the
/// same add-by-name-only placeholder `GroupSettingsView`'s "Add Someone"
/// already exposes as its own screen trip, reachable inline instead.
struct AddMemberSheet: View {
    let groupId: String
    let client: ClanTabClient
    let accessToken: String?
    let onAdded: (Member) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .submitLabel(.done)
                        .onSubmit { Task { await add() } }
                } footer: {
                    Text("Adds them to the ledger by name alone — no app or account needed. They can sign in and claim this spot for themselves later.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add Someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await add() } }
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
        }
    }

    private func add() async {
        guard !trimmedName.isEmpty else { return }
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }
        do {
            let response = try await client.joinGroup(
                groupId: groupId, JoinGroupRequest(displayName: trimmedName), accessToken: accessToken
            )
            onAdded(response.member)
            dismiss()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}

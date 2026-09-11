import SwiftUI
import ClanTabKit

/// Picks who paid: a searchable list of the group's members (`CHECKLIST.md`
/// "Add member inline from Add Expense... + search on the member picker"),
/// plus an inline "Add" for someone not in the group yet — the same
/// add-by-name-only placeholder `GroupSettingsView`'s "Add Someone" already
/// uses, just reachable without leaving this sheet. Pushed from
/// `AddExpenseView`; writes the selection back through the binding and pops.
struct MemberPickerView: View {
    @Binding var selection: String
    let members: [Member]
    let groupId: String
    let client: ClanTabClient
    let accessToken: String?
    /// Called once a new member is actually added, so the caller can append
    /// it to its own local member list immediately.
    let onMemberAdded: (Member) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }

    private var filteredMembers: [Member] {
        guard !trimmedSearch.isEmpty else { return members }
        return members.filter { $0.displayName.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    /// Whether typing "Add <name>" would just recreate someone already here —
    /// hides the add row for an exact (case-insensitive) name match.
    private var hasExactMatch: Bool {
        members.contains { $0.displayName.caseInsensitiveCompare(trimmedSearch) == .orderedSame }
    }

    var body: some View {
        Form {
            Section {
                ForEach(filteredMembers) { member in
                    Button {
                        selection = member.id
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            MemberAvatar(member, size: 28)
                            Text(member.displayName)
                            Spacer()
                            if selection == member.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }

            if !trimmedSearch.isEmpty, !hasExactMatch {
                Section {
                    Button {
                        Task { await addAndSelect() }
                    } label: {
                        if isAdding {
                            ProgressView()
                        } else {
                            Label("Add “\(trimmedSearch)”", systemImage: "person.badge.plus")
                        }
                    }
                    .disabled(isAdding)
                } footer: {
                    Text("Adds them to the ledger by name alone — no app or account needed.")
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .searchable(text: $searchText, prompt: "Search or add a name")
        .navigationTitle("Paid By")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addAndSelect() async {
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }
        do {
            let response = try await client.joinGroup(
                groupId: groupId, JoinGroupRequest(displayName: trimmedSearch), accessToken: accessToken
            )
            onMemberAdded(response.member)
            selection = response.member.id
            dismiss()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}

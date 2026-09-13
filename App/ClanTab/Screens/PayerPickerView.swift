import SwiftUI
import ClanTabKit

/// Picks who paid — one multi-select list, not a picker plus a separate
/// "Add Payer" mode-toggle button (`CHECKLIST.md` R12). Selecting exactly
/// one member behaves like the old single-payer case; selecting more reveals
/// the per-payer amount split `AddExpenseView.payerAmountRows` already
/// drives off `isMultiPayer`. Same searchable-list-plus-inline-add shape as
/// `MemberPickerView`, just with checkmarks instead of select-and-pop.
struct PayerPickerView: View {
    @Binding var selection: Set<String>
    let members: [Member]
    let groupId: String
    let client: ClanTabClient
    let accessToken: String?
    /// Called once a new member is actually added, so the caller can append
    /// it to its own local member list immediately.
    let onMemberAdded: (Member) -> Void

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
                        toggle(member.id)
                    } label: {
                        HStack(spacing: 12) {
                            MemberAvatar(member, size: 28)
                            Text(member.displayName)
                            Spacer()
                            if selection.contains(member.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .tint(.primary)
                }
            } footer: {
                // An expense always needs at least one payer — the last
                // remaining selection can't be tapped off (see `toggle`
                // below), so the row alone (dimmed, not a "disabled" gray)
                // hints at why nothing happened.
                if selection.count == 1 {
                    Text("At least one person has to have paid.")
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

    /// Never lets the selection go empty — same principle as
    /// `GroupSettingsView.isRemovable`'s "a group must keep at least one
    /// member," just for payers on this one expense.
    private func toggle(_ memberId: String) {
        if selection.contains(memberId) {
            guard selection.count > 1 else { return }
            selection.remove(memberId)
        } else {
            selection.insert(memberId)
        }
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
            selection.insert(response.member.id)
            searchText = ""
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}

import SwiftUI
import ClanTabKit

/// Apple Guideline 1.2's report mechanism for shared user-generated content
/// (`SHIP_PLAN.md` Track 3 §7) — reachable either from a specific member row
/// (`target: .member`) or generally from Group Settings (`target: .group`).
/// "Block" is the existing "Remove" member action in `GroupSettingsView`;
/// this is the other half.
struct ReportContentView: View {
    let groupId: String
    let target: ReportTarget
    /// Shown in the sheet so it's clear what's being reported — the
    /// member's display name, or the group's own name for a general report.
    let targetLabel: String
    let client: ClanTabClient
    let accessToken: String?
    /// Pre-fills the details field with read-only-in-spirit context — e.g.
    /// the flagged text of a reported comment (`CHECKLIST.md` "Comments on an
    /// expense") — so the admin sees exactly what was flagged even if the
    /// reporter adds nothing of their own. Still just a starting value; the
    /// user can edit or clear it like anything else they typed.
    var contextNote: String? = nil
    let onSubmitted: () -> Void
    let onCancel: () -> Void

    static let reasons = ["Inappropriate name", "Harassment or abuse", "Spam", "Other"]

    @State private var reason = ReportContentView.reasons[0]
    @State private var details: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        groupId: String, target: ReportTarget, targetLabel: String, client: ClanTabClient,
        accessToken: String?, contextNote: String? = nil, onSubmitted: @escaping () -> Void, onCancel: @escaping () -> Void
    ) {
        self.groupId = groupId
        self.target = target
        self.targetLabel = targetLabel
        self.client = client
        self.accessToken = accessToken
        self.contextNote = contextNote
        self.onSubmitted = onSubmitted
        self.onCancel = onCancel
        _details = State(initialValue: contextNote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Reporting", value: targetLabel)
                    Picker("Reason", selection: $reason) {
                        ForEach(Self.reasons, id: \.self) { Text($0) }
                    }
                } footer: {
                    Text("Sent for review. This doesn't remove or block anyone by itself — use \"Remove\" in Group Settings for that.")
                }

                Section("Details (optional)") {
                    TextField("What happened?", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Report a Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Submit") { Task { await submit() } }
                    }
                }
            }
            .dismissibleKeyboard()
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await client.report(
                groupId: groupId,
                target: target,
                reason: reason,
                details: trimmedDetails.isEmpty ? nil : trimmedDetails,
                accessToken: accessToken
            )
            onSubmitted()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}

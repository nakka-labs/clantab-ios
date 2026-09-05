import SwiftUI
import ClanTabKit

/// Manage this group's recurring reminders (`FEATURE_BACKLOG.md` "Recurring
/// reminders (not auto-post)") — list, add, delete. Tapping one opens
/// `AddExpenseView` pre-filled (`recurringTemplate:`); the reminder itself
/// never posts anything — same "confirm before it counts" pattern as
/// Duplicate.
///
/// Tapping the notification just opens the app to wherever it already was —
/// it doesn't deep-link straight to this screen for the specific group/
/// reminder. That's a deliberate scope cut for this pass: the reminder
/// already delivers its value (a nudge to come log something); a few extra
/// taps once inside the app is minor friction, not a correctness issue.
struct RecurringRemindersView: View {
    let groupId: String
    let members: [Member]
    let client: ClanTabClient
    let accessToken: String?
    let store: RecurringTemplatesStoring
    let onLogged: () -> Void
    let onDone: () -> Void

    @State private var templates: [RecurringTemplate] = []
    @State private var isPresentingNew = false
    @State private var loggingTemplate: RecurringTemplate?
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            if templates.isEmpty {
                ContentUnavailableView(
                    "No Recurring Reminders",
                    systemImage: "repeat",
                    description: Text("Get a reminder to log rent, groceries, or anything else that comes up on a schedule.")
                )
            } else {
                Section {
                    ForEach(templates) { template in
                        Button {
                            loggingTemplate = template
                        } label: {
                            row(for: template)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) { delete(template) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("Tap a reminder any time to log it — nothing posts automatically.")
                }
            }

            if notificationsDenied {
                Section {
                    Text("Notifications are off for ClanTab, so reminders won't alert you — this list still works, you'll just need to check it yourself. Turn notifications on in Settings if you'd like the alert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Recurring Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done", action: onDone) }
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNew = true } label: { Image(systemName: "plus") }
            }
        }
        .task { reload() }
        .sheet(isPresented: $isPresentingNew) {
            NavigationStack {
                NewRecurringReminderView(
                    groupId: groupId,
                    members: members,
                    onSaved: { template in
                        isPresentingNew = false
                        Task { await scheduleAndSave(template) }
                    },
                    onCancel: { isPresentingNew = false }
                )
            }
        }
        .sheet(item: $loggingTemplate) { template in
            NavigationStack {
                AddExpenseView(
                    groupId: groupId,
                    members: members,
                    defaultCurrency: template.currency,
                    currentMemberId: nil,
                    client: client,
                    accessToken: accessToken,
                    recurringTemplate: template,
                    onSaved: {
                        loggingTemplate = nil
                        onLogged()
                    },
                    onCancel: { loggingTemplate = nil }
                )
            }
        }
    }

    @ViewBuilder
    private func row(for template: RecurringTemplate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.description).foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(template.cadence.label)
                    if RecurringTemplateValidation.validity(of: template, members: members) == .payerNoLongerAMember {
                        Text("· needs updating").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MoneyFormat.string(minorUnits: template.amountMinor, currency: template.currency))
                .foregroundStyle(.secondary)
        }
    }

    private func reload() {
        templates = store.all(forGroup: groupId)
    }

    private func scheduleAndSave(_ template: RecurringTemplate) async {
        let authorized = await RecurringReminderScheduler.requestAuthorization()
        notificationsDenied = !authorized
        store.save(template)
        if authorized {
            RecurringReminderScheduler.schedule(template)
        }
        reload()
    }

    private func delete(_ template: RecurringTemplate) {
        RecurringReminderScheduler.cancel(templateId: template.id)
        store.remove(id: template.id)
        reload()
    }
}

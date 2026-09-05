import SwiftUI
import ClanTabKit

/// The "new reminder" form — description, amount, currency, payer, category,
/// cadence (`FEATURE_BACKLOG.md`). Doesn't touch the network or the store
/// itself; hands the built `RecurringTemplate` back to
/// `RecurringRemindersView`, which schedules the notification and persists it.
struct NewRecurringReminderView: View {
    let groupId: String
    let members: [Member]
    let onSaved: (RecurringTemplate) -> Void
    let onCancel: () -> Void

    @State private var description = ""
    @State private var amountText = ""
    @State private var currency = AppConfig.supportedCurrencies.first!
    @State private var payerId: String
    @State private var category: ExpenseCategory = .uncategorized
    @State private var cadence: RecurringTemplate.Cadence = .monthly
    /// 1...31 for `.monthly`; 1...7 (`Calendar.Component.weekday`, 1 = Sunday)
    /// for `.weekly`.
    @State private var cadenceAnchor = 1

    init(groupId: String, members: [Member], onSaved: @escaping (RecurringTemplate) -> Void, onCancel: @escaping () -> Void) {
        self.groupId = groupId
        self.members = members
        self.onSaved = onSaved
        self.onCancel = onCancel
        _payerId = State(initialValue: members.first?.id ?? "")
    }

    private var amountMinor: Int64? { MoneyFormat.minorUnits(from: amountText) }

    private var canSubmit: Bool {
        guard let amountMinor, amountMinor > 0 else { return false }
        return !description.trimmingCharacters(in: .whitespaces).isEmpty && !payerId.isEmpty
    }

    var body: some View {
        Form {
            Section("Reminder") {
                TextField("Description", text: $description)
                HStack {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        ForEach(AppConfig.supportedCurrencies, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                Picker("Usually paid by", selection: $payerId) {
                    ForEach(members) { member in
                        Text(member.displayName).tag(member.id)
                    }
                }
                NavigationLink {
                    CategoryPickerView(selection: $category)
                } label: {
                    HStack {
                        Text("Category")
                        Spacer()
                        Label(category.name, systemImage: category.symbolName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Picker("Repeats", selection: $cadence) {
                    ForEach(RecurringTemplate.Cadence.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .onChange(of: cadence) { _, _ in cadenceAnchor = 1 }
                cadenceAnchorPicker
            } footer: {
                Text("A reminder just nudges you to log this — nothing gets added to the ledger until you confirm.")
            }

            Section {
                Button("Add Reminder") {
                    onSaved(
                        RecurringTemplate(
                            id: UUID().uuidString,
                            groupId: groupId,
                            description: description.trimmingCharacters(in: .whitespaces),
                            amountMinor: amountMinor ?? 0,
                            currency: currency,
                            payerId: payerId,
                            category: category == .uncategorized ? nil : category.name,
                            categoryIcon: category == .uncategorized ? nil : category.symbolName,
                            cadence: cadence,
                            cadenceAnchor: cadenceAnchor
                        )
                    )
                }
                .disabled(!canSubmit)
            }
        }
        .navigationTitle("New Reminder")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
        }
        .dismissibleKeyboard()
    }

    @ViewBuilder
    private var cadenceAnchorPicker: some View {
        switch cadence {
        case .weekly:
            Picker("Day", selection: $cadenceAnchor) {
                ForEach(Array(zip(1...7, Self.weekdaySymbols)), id: \.0) { value, symbol in
                    Text(symbol).tag(value)
                }
            }
        case .monthly:
            Picker("Day of Month", selection: $cadenceAnchor) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
        }
    }

    /// `Calendar.current.weekdaySymbols` is Sunday-first, matching
    /// `DateComponents.weekday`'s 1 = Sunday convention.
    private static var weekdaySymbols: [String] {
        Calendar.current.weekdaySymbols
    }
}

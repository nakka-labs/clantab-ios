import SwiftUI
import ClanTabKit

/// Manually record a settlement, independent of Settle Up's suggestions
/// (`CHECKLIST.md` R14) — "I paid them some amount, not necessarily what the
/// app suggested, and want it logged." `ClanTabClient.addSettlement` already
/// exists and needed no changes; the gap was purely that nothing called it
/// except `SettleUpView`'s "Mark as Paid" against a server-computed
/// suggestion. Same field set as `EditSettlementView`'s counterpart (from,
/// to, amount, currency — no date, matching that screen's own omission:
/// `settled_at` is server-stamped "now," not user-editable there either), a
/// small create-mode sibling rather than a nullable-`settlement` branch on
/// that view, since the two screens' identity (title, what "Save" means)
/// differ enough to be confusing shoehorned into one.
struct AddSettlementView: View {
    let groupId: String
    let members: [Member]
    let client: ClanTabClient
    let accessToken: String?
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var fromId: String
    @State private var toId: String
    @State private var amountText = ""
    @State private var currency: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        groupId: String, members: [Member], defaultCurrency: String,
        client: ClanTabClient, accessToken: String?,
        onSaved: @escaping () -> Void, onCancel: @escaping () -> Void
    ) {
        self.groupId = groupId
        self.members = members
        self.client = client
        self.accessToken = accessToken
        self.onSaved = onSaved
        self.onCancel = onCancel
        _fromId = State(initialValue: members.first?.id ?? "")
        _toId = State(initialValue: members.dropFirst().first?.id ?? members.first?.id ?? "")
        _currency = State(initialValue: defaultCurrency)
    }

    private var currencyChoices: [String] {
        AppConfig.supportedCurrencies.contains(currency)
            ? AppConfig.supportedCurrencies
            : [currency] + AppConfig.supportedCurrencies
    }

    private var amountMinor: Int64? { MoneyFormat.minorUnits(from: amountText) }

    private var canSave: Bool {
        guard let amountMinor, amountMinor > 0 else { return false }
        return fromId != toId
    }

    var body: some View {
        Form {
            Section("From") {
                Picker("Paid by", selection: $fromId) {
                    ForEach(members) { member in Text(member.displayName).tag(member.id) }
                }
            }
            Section("To") {
                Picker("Paid to", selection: $toId) {
                    ForEach(members) { member in Text(member.displayName).tag(member.id) }
                }
            }
            Section("Amount") {
                HStack {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        ForEach(currencyChoices, id: \.self) { code in Text(code).tag(code) }
                    }
                    .labelsHidden()
                }
                if fromId == toId {
                    Text("Paid by and paid to must be different people.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Record a Settlement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        guard let amountMinor else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await client.addSettlement(
                groupId: groupId,
                AddSettlementRequest(id: UUID().uuidString, fromId: fromId, toId: toId, amountMinor: amountMinor, currency: currency),
                accessToken: accessToken
            )
            onSaved()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}

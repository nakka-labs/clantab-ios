import SwiftUI
import ClanTabKit

/// Edit an already-recorded settlement (`CHECKLIST.md` "Friend playtest,
/// round 3" — server (`GroupDO.updateSettlement`) and kit
/// (`ClanTabClient.updateSettlement`) were already fully wired; the client
/// never added a UI for it). A settlement has no description/category to
/// edit — just who paid whom, how much, and in what currency — so this is
/// a small standalone form rather than reusing `AddExpenseView`. The date
/// (`settled_at`) is preserved server-side and isn't offered here.
struct EditSettlementView: View {
    let groupId: String
    let members: [Member]
    let settlement: Settlement
    let client: ClanTabClient
    let accessToken: String?
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var fromId: String
    @State private var toId: String
    @State private var amountText: String
    @State private var currency: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        groupId: String, members: [Member], settlement: Settlement,
        client: ClanTabClient, accessToken: String?,
        onSaved: @escaping () -> Void, onCancel: @escaping () -> Void
    ) {
        self.groupId = groupId
        self.members = members
        self.settlement = settlement
        self.client = client
        self.accessToken = accessToken
        self.onSaved = onSaved
        self.onCancel = onCancel
        _fromId = State(initialValue: settlement.fromId)
        _toId = State(initialValue: settlement.toId)
        _amountText = State(initialValue: MoneyFormat.plainString(minorUnits: settlement.amountMinor))
        _currency = State(initialValue: settlement.currency)
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
        .navigationTitle("Edit Settlement")
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
            _ = try await client.updateSettlement(
                groupId: groupId, settlementId: settlement.id,
                AddSettlementRequest(fromId: fromId, toId: toId, amountMinor: amountMinor, currency: currency),
                accessToken: accessToken
            )
            onSaved()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}

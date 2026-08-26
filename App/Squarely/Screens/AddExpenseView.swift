import SwiftUI
import SquareKit

/// Amount, payer, description, and an equal-or-exact split — the whole shape
/// mirrors `PLAN.md` §1's `Expense` model. All money entry converts through
/// `MoneyFormat.minorUnits(from:)` at the text-field boundary; everything past
/// that point (splits, validation, the request itself) stays integer minor
/// units, per `AGENTS.md`.
struct AddExpenseView: View {
    let groupId: String
    let members: [Member]
    let currency: String
    let currentMemberId: String?
    let client: SquarelyClient
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var amountText = ""
    @State private var description = ""
    @State private var payerId: String
    @State private var splitType: SplitType = .equal
    @State private var includedMemberIds: Set<String>
    @State private var exactAmountText: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        groupId: String,
        members: [Member],
        currency: String,
        currentMemberId: String?,
        client: SquarelyClient,
        onSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.groupId = groupId
        self.members = members
        self.currency = currency
        self.currentMemberId = currentMemberId
        self.client = client
        self.onSaved = onSaved
        self.onCancel = onCancel
        _payerId = State(initialValue: currentMemberId ?? members.first?.id ?? "")
        _includedMemberIds = State(initialValue: Set(members.map(\.id)))
    }

    private var amountMinor: Int64? {
        MoneyFormat.minorUnits(from: amountText)
    }

    var body: some View {
        Form {
            Section("Expense") {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                TextField("Description", text: $description)
                Picker("Paid by", selection: $payerId) {
                    ForEach(members) { member in
                        Text(member.displayName).tag(member.id)
                    }
                }
            }

            Section("Split") {
                Picker("Split type", selection: $splitType) {
                    Text("Equally").tag(SplitType.equal)
                    Text("Exact amounts").tag(SplitType.exact)
                }
                .pickerStyle(.segmented)

                switch splitType {
                case .equal:
                    ForEach(members) { member in
                        Toggle(member.displayName, isOn: includedBinding(for: member.id))
                    }
                case .exact:
                    ForEach(members) { member in
                        HStack {
                            Text(member.displayName)
                            Spacer()
                            TextField("0.00", text: exactAmountBinding(for: member.id))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                    if let amountMinor {
                        Text(remainingLabel(amountMinor - exactSplitsTotal))
                            .font(.footnote)
                            .foregroundStyle(amountMinor == exactSplitsTotal ? .secondary : .red)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Add Expense")
                    }
                }
                .disabled(!canSubmit || isSubmitting)
            }
        }
        .navigationTitle("Add Expense")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    private func includedBinding(for memberId: String) -> Binding<Bool> {
        Binding(
            get: { includedMemberIds.contains(memberId) },
            set: { isOn in
                if isOn {
                    includedMemberIds.insert(memberId)
                } else {
                    includedMemberIds.remove(memberId)
                }
            }
        )
    }

    private func exactAmountBinding(for memberId: String) -> Binding<String> {
        Binding(
            get: { exactAmountText[memberId] ?? "" },
            set: { exactAmountText[memberId] = $0 }
        )
    }

    private var exactSplitsTotal: Int64 {
        members.reduce(Int64(0)) { partial, member in
            partial + (MoneyFormat.minorUnits(from: exactAmountText[member.id] ?? "") ?? 0)
        }
    }

    private func remainingLabel(_ remaining: Int64) -> String {
        if remaining == 0 { return "Splits match the total." }
        let formatted = MoneyFormat.string(minorUnits: abs(remaining), currency: currency)
        return remaining > 0 ? "\(formatted) unassigned" : "\(formatted) over the total"
    }

    private var canSubmit: Bool {
        guard let amountMinor, amountMinor > 0 else { return false }
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !payerId.isEmpty else { return false }

        switch splitType {
        case .equal:
            return !includedMemberIds.isEmpty
        case .exact:
            return exactSplitsTotal == amountMinor
        }
    }

    private func save() async {
        guard let amountMinor else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let splits: [ExpenseSplit]
            switch splitType {
            case .equal:
                let memberIds = members.map(\.id).filter { includedMemberIds.contains($0) }
                splits = Validation.equalSplit(amountMinor: amountMinor, memberIds: memberIds, remainderRecipient: payerId)
            case .exact:
                splits = members.compactMap { member in
                    guard let value = MoneyFormat.minorUnits(from: exactAmountText[member.id] ?? ""), value > 0 else {
                        return nil
                    }
                    return ExpenseSplit(memberId: member.id, amountMinor: value)
                }
            }

            // The same rule the server enforces (DESIGN.md §6) - catching a
            // mismatch here means a clear error before it ever hits the network,
            // even though `canSubmit` should already rule this out.
            try Validation.validateSplitsSum(amountMinor: amountMinor, splits: splits)

            _ = try await client.addExpense(
                groupId: groupId,
                AddExpenseRequest(
                    id: UUID().uuidString,
                    payerId: payerId,
                    amountMinor: amountMinor,
                    description: description,
                    date: Date(),
                    splitType: splitType,
                    splits: splits
                )
            )
            onSaved()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}

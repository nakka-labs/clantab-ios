import SwiftUI
import ClanTabKit

/// Amount, payer, description, and an equal / exact / percentage split — the
/// whole shape mirrors `PLAN.md` §1's `Expense` model. All money entry converts
/// through `MoneyFormat.minorUnits(from:)` at the text-field boundary; everything
/// past that point (splits, validation, the request itself) stays integer minor
/// units, per `AGENTS.md`. Percentages are resolved to minor-unit shares client
/// side (`Validation.percentageSplit`) — the wire only carries `amountMinor`.
struct AddExpenseView: View {
    let groupId: String
    let members: [Member]
    /// The currency to pre-select — the group's last-used one.
    let defaultCurrency: String
    let currentMemberId: String?
    let client: ClanTabClient
    let accessToken: String?
    /// When set, the form edits this expense (`PUT`) instead of adding a new one.
    let editing: Expense?
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var amountText = ""
    @State private var description = ""
    @State private var payerId: String
    @State private var currency: String
    @State private var splitType: SplitType = .equal
    @State private var includedMemberIds: Set<String>
    @State private var exactAmountText: [String: String] = [:]
    @State private var percentText: [String: String] = [:]
    @State private var category: ExpenseCategory = .uncategorized
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    /// The currencies the user can pick — the supported set, plus the default if
    /// it's somehow outside it (an older group on a currency since removed).
    private var currencyChoices: [String] {
        AppConfig.supportedCurrencies.contains(defaultCurrency)
            ? AppConfig.supportedCurrencies
            : [defaultCurrency] + AppConfig.supportedCurrencies
    }

    init(
        groupId: String,
        members: [Member],
        defaultCurrency: String,
        currentMemberId: String?,
        client: ClanTabClient,
        accessToken: String? = nil,
        editing: Expense? = nil,
        /// Pre-fill from this expense (same payer/split/category) but leave
        /// `editing` `nil` — `save()` then POSTs a fresh expense with today's
        /// date and a blank amount, rather than PUTing over the original
        /// (`FEATURE_BACKLOG.md` "Duplicate an expense"). Mutually exclusive
        /// with `editing`; a caller never sets both.
        duplicating: Expense? = nil,
        onSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.groupId = groupId
        self.members = members
        self.defaultCurrency = defaultCurrency
        self.currentMemberId = currentMemberId
        self.client = client
        self.accessToken = accessToken
        self.editing = editing
        self.onSaved = onSaved
        self.onCancel = onCancel

        guard let expense = editing ?? duplicating else {
            _payerId = State(initialValue: currentMemberId ?? members.first?.id ?? "")
            _currency = State(initialValue: defaultCurrency)
            _includedMemberIds = State(initialValue: Set(members.map(\.id)))
            return
        }

        // Duplicating leaves the amount blank — everything else about the
        // expense carries over, but the amount is the one field that's
        // rarely identical trip to trip (that's the whole reason this isn't
        // just an "undo delete" of a fresh copy).
        if editing != nil {
            _amountText = State(initialValue: MoneyFormat.plainString(minorUnits: expense.amountMinor))
        }
        _description = State(initialValue: expense.description)
        _payerId = State(initialValue: expense.payerId)
        _currency = State(initialValue: expense.currency)
        _splitType = State(initialValue: expense.splitType)
        _category = State(initialValue: ExpenseCategory.resolve(name: expense.category, symbolName: expense.categoryIcon))
        _includedMemberIds = State(initialValue: Set(expense.splits.map(\.memberId)))

        var exact: [String: String] = [:]
        for split in expense.splits {
            exact[split.memberId] = MoneyFormat.plainString(minorUnits: split.amountMinor)
        }
        _exactAmountText = State(initialValue: exact)

        var percent: [String: String] = [:]
        if expense.splitType == .percentage, expense.amountMinor > 0 {
            // Percentages aren't stored — only the resolved minor-unit shares.
            // Back-compute for the field; a no-op re-save re-resolves and may
            // shift a minor unit, which the remainder rule absorbs.
            for split in expense.splits {
                let pct = (Double(split.amountMinor) / Double(expense.amountMinor) * 100).rounded()
                percent[split.memberId] = String(Int(pct))
            }
        }
        _percentText = State(initialValue: percent)
    }

    private var isEditing: Bool { editing != nil }

    private var amountMinor: Int64? {
        MoneyFormat.minorUnits(from: amountText)
    }

    var body: some View {
        Form {
            Section("Expense") {
                HStack {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    if currencyChoices.count > 1 {
                        Picker("Currency", selection: $currency) {
                            ForEach(currencyChoices, id: \.self) { code in Text(code).tag(code) }
                        }
                        .labelsHidden()
                    }
                }
                TextField("Description", text: $description)
                Picker("Paid by", selection: $payerId) {
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

            Section("Split") {
                Picker("Split type", selection: $splitType) {
                    Text("Equally").tag(SplitType.equal)
                    Text("Exact").tag(SplitType.exact)
                    Text("Percentage").tag(SplitType.percentage)
                }
                .pickerStyle(.segmented)

                splitDetail
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
                        Text(isEditing ? "Save Changes" : "Add Expense")
                    }
                }
                .disabled(!canSubmit || isSubmitting)
            }
        }
        .navigationTitle(isEditing ? "Edit Expense" : "Add Expense")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
        .dismissibleKeyboard()
    }

    /// Broken out of `body` on its own: a `switch` mixed directly into a
    /// `Section`'s content closure alongside a `Picker` was tripping up
    /// overload resolution for `Section` itself (it was matching SwiftUI's
    /// `Table`-oriented initializer instead of the plain one). Giving the
    /// type checker a named, independently-inferred boundary here fixes it.
    @ViewBuilder
    private var splitDetail: some View {
        switch splitType {
        case .equal:
            ForEach(members) { member in
                Toggle(member.displayName, isOn: includedBinding(for: member.id))
            }
        case .exact:
            exactSplitRows
        case .percentage:
            percentSplitRows
        }
    }

    @ViewBuilder
    private var exactSplitRows: some View {
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
                .foregroundStyle(amountMinor == exactSplitsTotal ? Color.secondary : Color.red)
        }
    }

    @ViewBuilder
    private var percentSplitRows: some View {
        ForEach(members) { member in
            HStack {
                Text(member.displayName)
                Spacer()
                TextField("0", text: percentBinding(for: member.id))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text("%").foregroundStyle(.secondary)
            }
        }
        Text(percentRemainingLabel)
            .font(.footnote)
            .foregroundStyle(percentTotal == 100 ? Color.secondary : Color.red)
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

    private func percentBinding(for memberId: String) -> Binding<String> {
        Binding(
            get: { percentText[memberId] ?? "" },
            set: { percentText[memberId] = $0 }
        )
    }

    private var exactSplitsTotal: Int64 {
        members.reduce(Int64(0)) { partial, member in
            partial + (MoneyFormat.minorUnits(from: exactAmountText[member.id] ?? "") ?? 0)
        }
    }

    /// Parsed whole-number percent for a member (a blank or non-numeric field is `0`).
    private func percent(for memberId: String) -> Int {
        Int(percentText[memberId]?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
    }

    private var percentTotal: Int {
        members.reduce(0) { $0 + percent(for: $1.id) }
    }

    private var percentRemainingLabel: String {
        let remaining = 100 - percentTotal
        if remaining == 0 { return "Percentages add up to 100%." }
        return remaining > 0 ? "\(remaining)% left to assign" : "\(-remaining)% over 100%"
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
        case .percentage:
            return percentTotal == 100
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
            case .percentage:
                // Resolve percentages to exact minor units here — the wire only
                // ever carries `amountMinor` shares (DESIGN.md §6).
                let weights = members
                    .map { (memberId: $0.id, weight: percent(for: $0.id)) }
                    .filter { $0.weight > 0 }
                splits = Validation.percentageSplit(
                    amountMinor: amountMinor,
                    weights: weights,
                    remainderRecipient: payerId
                )
            }

            // The same rule the server enforces (DESIGN.md §6) - catching a
            // mismatch here means a clear error before it ever hits the network,
            // even though `canSubmit` should already rule this out.
            try Validation.validateSplitsSum(amountMinor: amountMinor, splits: splits)

            // `.uncategorized` is the "no category" sentinel — send nil, not the
            // placeholder name, so it stays distinguishable from a real category.
            let isCategorised = category != .uncategorized
            let request = AddExpenseRequest(
                id: isEditing ? nil : UUID().uuidString,
                payerId: payerId,
                amountMinor: amountMinor,
                currency: currency,
                description: description,
                // Adding stamps "now"; editing keeps the original date (there's
                // no date field in this form).
                date: editing?.date ?? Date(),
                splitType: splitType,
                splits: splits,
                category: isCategorised ? category.name : nil,
                categoryIcon: isCategorised ? category.symbolName : nil
            )
            if let editing {
                _ = try await client.updateExpense(groupId: groupId, expenseId: editing.id, request, accessToken: accessToken)
            } else {
                _ = try await client.addExpense(groupId: groupId, request, accessToken: accessToken)
            }
            onSaved()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}

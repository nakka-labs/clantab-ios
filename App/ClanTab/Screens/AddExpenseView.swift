import SwiftUI
import PhotosUI
import ClanTabKit

/// Amount, payer, description, and an equal / exact / percentage split — the
/// whole shape mirrors `PLAN.md` §1's `Expense` model. All money entry converts
/// through `MoneyFormat.minorUnits(from:)` at the text-field boundary; everything
/// past that point (splits, validation, the request itself) stays integer minor
/// units, per `AGENTS.md`. Percentages are resolved to minor-unit shares client
/// side (`Validation.percentageSplit`) — the wire only carries `amountMinor`.
struct AddExpenseView: View {
    let groupId: String
    /// Mutable, not `let` (`CHECKLIST.md` "Add member inline from Add
    /// Expense") — adding someone by name from inside this sheet appends to
    /// this local copy immediately, so the new member shows up in every
    /// picker here without waiting for the parent to refetch group state.
    @State private var members: [Member]
    /// The currency to pre-select — the group's last-used one.
    let defaultCurrency: String
    let currentMemberId: String?
    let client: ClanTabClient
    let accessToken: String?
    /// The signed-in identity's session token — the media-presign endpoint needs
    /// it for a receipt upload (`CHECKLIST.md` "Photo attachment on an expense").
    var sessionToken: String?
    /// When set, the form edits this expense (`PUT`) instead of adding a new one.
    let editing: Expense?
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var amountText = ""
    @State private var description = ""
    @State private var payerId: String
    /// Whether "Paid by" is in multi-payer entry mode (`CHECKLIST.md`
    /// "Multiple payers on one expense") — off by default; `payerId` alone
    /// covers the overwhelmingly common single-payer case.
    @State private var isMultiPayer = false
    /// Per-member contribution amounts while `isMultiPayer` — parallel to
    /// `exactAmountText`'s shape, just on the credit side of the expense.
    @State private var payerAmountText: [String: String] = [:]
    @State private var currency: String
    /// The expense's own date (`CHECKLIST.md` UX audit [14]) — defaults to
    /// "now" at the moment this sheet opens (adding), overridden in `init` to
    /// the stored date while editing. Duplicating/a recurring reminder both
    /// leave it at the default, same as their blank amount — "today" is the
    /// whole point of logging a repeat.
    @State private var date = Date()
    @State private var splitType: SplitType = .equal
    @State private var includedMemberIds: Set<String>
    /// Filters every member list on this screen at once (`CHECKLIST.md`
    /// "...+ search on the member picker") — shown only once a group is big
    /// enough that scanning it is real friction.
    @State private var memberSearchText = ""
    @State private var isPresentingAddMember = false
    /// Drives `MoreSplitsSheet` (`CHECKLIST.md` UX audit [15]) — the primary
    /// segmented control only carries Equally/Exact/%; Shares and Items (and
    /// a way back) live one tap away here.
    @State private var isPresentingMoreSplits = false
    @State private var exactAmountText: [String: String] = [:]
    @State private var percentText: [String: String] = [:]
    /// Per-member ratio weights for a `.shares` split (`CHECKLIST.md` "Split by
    /// shares"), as strings. Empty until the user first picks "Shares" (or when
    /// editing a shares expense), then seeded to `1` each.
    @State private var shareText: [String: String] = [:]
    /// Line-item drafts for an `.itemized` split (`FEATURE_BACKLOG.md`
    /// "Itemized expense entry"). Empty until the user picks "Items" for the
    /// first time (or when editing an itemized expense), when it's seeded.
    @State private var itemDrafts: [ItemDraft] = []
    /// Tax/tip on an itemized expense (`CHECKLIST.md` "Tax/tip proportional
    /// split on itemized expenses") — as strings, same as every other money
    /// field on this screen. Blank (the default) means "none", not "zero" —
    /// `taxMinorValue`/`tipMinorValue` treat both the same.
    @State private var taxText = ""
    @State private var tipText = ""

    /// One editable line item — the mutable, string-typed counterpart to
    /// `ClanTabKit.LineItem`, resolved to exact splits only on save.
    struct ItemDraft: Identifiable {
        let id: String
        var name: String
        var amountText: String
        var participantIds: Set<String>

        init(id: String = UUID().uuidString, name: String = "", amountText: String = "", participantIds: Set<String>) {
            self.id = id
            self.name = name
            self.amountText = amountText
            self.participantIds = participantIds
        }
    }
    @State private var category: ExpenseCategory = .uncategorized
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    /// Receipt photos (`CHECKLIST.md` "Photo attachment on an expense"). The
    /// expense id is fixed up front so receipts can be uploaded to
    /// `expenses/<groupId>/<expenseId>/…` before the expense is saved.
    @State private var expenseId: String
    @State private var attachmentKeys: [String]
    @State private var pickedReceipts: [PhotosPickerItem] = []
    @State private var isUploadingReceipt = false
    /// Receipts + Comments, tucked behind one disclosure (`CHECKLIST.md` UX
    /// audit [17]) — closed by default on a fresh expense (nothing to show
    /// yet), open by default while editing (comments' own existence isn't
    /// knowable synchronously before their `.task` fetch resolves, so
    /// "editing at all" is the simplification, not "has content").
    @State private var isShowingMoreDetails = false
    @Environment(\.avatarImageLoader) private var avatarLoader

    // MARK: Comments (CHECKLIST.md "Comments on an expense")
    /// Only meaningful once the expense actually exists server-side — i.e.
    /// while editing; a fresh Add Expense has nothing to attach a comment to
    /// until it's first saved, so the whole section stays hidden until then.
    @State private var comments: [Comment] = []
    @State private var isLoadingComments = false
    @State private var newCommentText = ""
    @State private var isPostingComment = false
    @State private var commentError: String?
    @State private var reportingComment: (target: ReportTarget, label: String, note: String)?

    /// The currencies the user can pick — the supported set, plus the default if
    /// it's somehow outside it (an older group on a currency since removed).
    private var currencyChoices: [String] {
        AppConfig.supportedCurrencies.contains(defaultCurrency)
            ? AppConfig.supportedCurrencies
            : [defaultCurrency] + AppConfig.supportedCurrencies
    }

    // MARK: - Member search + inline add (CHECKLIST.md "Add member inline
    // from Add Expense, + search on the member picker")

    private var trimmedMemberSearch: String { memberSearchText.trimmingCharacters(in: .whitespaces) }

    private var filteredMembers: [Member] {
        guard !trimmedMemberSearch.isEmpty else { return members }
        return members.filter { $0.displayName.localizedCaseInsensitiveContains(trimmedMemberSearch) }
    }

    /// A search field for whichever member list is on screen — only once a
    /// group is big enough that scrolling to find someone is real friction.
    @ViewBuilder
    private var memberSearchField: some View {
        if members.count > 8 {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search members", text: $memberSearchText)
                    .textInputAutocapitalization(.words)
                if !memberSearchText.isEmpty {
                    Button { memberSearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Adds someone by name alone, without leaving this sheet — the same
    /// add-by-name-only placeholder `GroupSettingsView`'s "Add Someone"
    /// already exposes as its own screen trip.
    private var addMemberButton: some View {
        Button {
            isPresentingAddMember = true
        } label: {
            Label("Add Someone", systemImage: "person.badge.plus")
        }
        .coachMark(id: "addExpense.addMember", text: "Add someone new without leaving this screen.")
    }

    init(
        groupId: String,
        members: [Member],
        defaultCurrency: String,
        currentMemberId: String?,
        client: ClanTabClient,
        accessToken: String? = nil,
        sessionToken: String? = nil,
        editing: Expense? = nil,
        /// Pre-fill from this expense (same payer/split/category) but leave
        /// `editing` `nil` — `save()` then POSTs a fresh expense with today's
        /// date and a blank amount, rather than PUTing over the original
        /// (`FEATURE_BACKLOG.md` "Duplicate an expense"). Mutually exclusive
        /// with `editing`; a caller never sets both.
        duplicating: Expense? = nil,
        /// Pre-fill from a recurring reminder (`FEATURE_BACKLOG.md`) — amount,
        /// description, category, and currency carry over; the split is
        /// always a fresh equal split among *current* members (the template
        /// doesn't store one, sidestepping the stale-member problem). The
        /// payer pre-fills to `template.payerId` only if they're still a
        /// member; otherwise falls back like a blank form would.
        /// `editing` stays `nil`, same reasoning as `duplicating`.
        recurringTemplate: RecurringTemplate? = nil,
        /// The group's saved default split (`FEATURE_BACKLOG.md` "Default split
        /// config per group") — a *fresh* Add Expense opens on a percentage
        /// split pre-filled from it, when every weighted member is still in the
        /// group. Editing / duplicating / a recurring reminder ignore it.
        defaultSplit: DefaultSplit? = nil,
        onSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.groupId = groupId
        _members = State(initialValue: members)
        self.defaultCurrency = defaultCurrency
        self.currentMemberId = currentMemberId
        self.client = client
        self.accessToken = accessToken
        self.sessionToken = sessionToken
        self.editing = editing
        self.onSaved = onSaved
        self.onCancel = onCancel

        // Fixed for the life of the sheet — receipts upload against it, and an
        // add sends it as the idempotency id (`CHECKLIST.md`).
        _expenseId = State(initialValue: editing?.id ?? UUID().uuidString)
        _attachmentKeys = State(initialValue: editing?.attachments ?? [])
        _isShowingMoreDetails = State(initialValue: editing != nil)

        if let template = recurringTemplate {
            _amountText = State(initialValue: MoneyFormat.plainString(minorUnits: template.amountMinor))
            _description = State(initialValue: template.description)
            let payerStillAMember = members.contains { $0.id == template.payerId }
            _payerId = State(initialValue: payerStillAMember ? template.payerId : (currentMemberId ?? members.first?.id ?? ""))
            _currency = State(initialValue: template.currency)
            _category = State(initialValue: ExpenseCategory.resolve(name: template.category, symbolName: template.categoryIcon))
            _includedMemberIds = State(initialValue: Set(members.map(\.id)))
            return
        }

        guard let expense = editing ?? duplicating else {
            _payerId = State(initialValue: currentMemberId ?? members.first?.id ?? "")
            _currency = State(initialValue: defaultCurrency)
            _includedMemberIds = State(initialValue: Set(members.map(\.id)))
            // Open on the group's saved default split when it's still valid
            // for the current members (`FEATURE_BACKLOG.md` "Default split
            // config per group").
            if let resolved = defaultSplit?.resolved(for: members) {
                _splitType = State(initialValue: .percentage)
                _percentText = State(initialValue: Dictionary(
                    uniqueKeysWithValues: resolved.weights.map { ($0.memberId, String($0.weight)) }
                ))
            }
            return
        }

        // Duplicating leaves the amount blank — everything else about the
        // expense carries over, but the amount is the one field that's
        // rarely identical trip to trip (that's the whole reason this isn't
        // just an "undo delete" of a fresh copy).
        if editing != nil {
            _amountText = State(initialValue: MoneyFormat.plainString(minorUnits: expense.amountMinor))
            _date = State(initialValue: expense.date)
        }
        _description = State(initialValue: expense.description)
        // A genuine multi-payer expense (`CHECKLIST.md` "Multiple payers on
        // one expense") rehydrates into the multi-payer entry mode directly;
        // `payerId` (nil for that case) only fills the single-payer Picker.
        if expense.payers.count > 1 {
            _isMultiPayer = State(initialValue: true)
            _payerAmountText = State(initialValue: Dictionary(
                uniqueKeysWithValues: expense.payers.map { ($0.memberId, MoneyFormat.plainString(minorUnits: $0.amountMinor)) }
            ))
            _payerId = State(initialValue: currentMemberId ?? members.first?.id ?? "")
        } else {
            _payerId = State(initialValue: expense.payerId ?? currentMemberId ?? members.first?.id ?? "")
        }
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

        // An itemized expense stores its line items directly — rehydrate them
        // as drafts. Duplicating gets fresh item ids (a fresh expense); editing
        // keeps them so a save diffs rather than rebuilds.
        if expense.splitType == .itemized, let items = expense.items {
            _itemDrafts = State(initialValue: items.map { item in
                ItemDraft(
                    id: editing != nil ? item.id : UUID().uuidString,
                    name: item.name,
                    amountText: MoneyFormat.plainString(minorUnits: item.amountMinor),
                    participantIds: Set(item.participantIds)
                )
            })
            _taxText = State(initialValue: expense.taxMinor.map { MoneyFormat.plainString(minorUnits: $0) } ?? "")
            _tipText = State(initialValue: expense.tipMinor.map { MoneyFormat.plainString(minorUnits: $0) } ?? "")
        }

        // A shares expense stores its raw weights — rehydrate them directly
        // (no back-computing, unlike percentage). Duplicating reuses the same
        // weights; there are no per-item ids to regenerate.
        if expense.splitType == .shares, let shares = expense.shares {
            _shareText = State(initialValue: Dictionary(
                uniqueKeysWithValues: shares.map { ($0.memberId, String($0.weight)) }
            ))
        }
    }

    private var isEditing: Bool { editing != nil }

    /// The typed amount, resolving a `+`/`-` expression (`CHECKLIST.md`
    /// "Inline calculator on the amount field") — `nil` while it doesn't fully
    /// parse, which keeps the submit button disabled just like a blank field.
    private var amountMinor: Int64? {
        MoneyFormat.evaluate(amountText)
    }

    @FocusState private var amountFocused: Bool

    private var amountHasExpression: Bool {
        amountText.contains(where: { $0 == "+" || $0 == "-" })
    }

    /// Append `+` / `-` to the running amount expression, keeping focus so the
    /// next term can be typed. A trailing operator is swapped, not stacked
    /// (`"12 + "` then `-` → `"12 - "`); a blank field is left alone.
    /// The one place `splitType` actually changes (`CHECKLIST.md` UX audit
    /// [15]) — called from both the primary segmented control and
    /// `MoreSplitsSheet`, so the seeding side effects run regardless of
    /// which one picked Shares/Items.
    private func selectSplitType(_ newValue: SplitType) {
        splitType = newValue
        // Seed the first line item the moment "Items" is picked (unless
        // editing already filled them), so the section isn't an empty shell.
        if newValue == .itemized, itemDrafts.isEmpty {
            itemDrafts = [ItemDraft(participantIds: includedMemberIds.isEmpty ? Set(members.map(\.id)) : includedMemberIds)]
        }
        // Seed every member at weight 1 the first time "Shares" is picked,
        // so an equal split is the starting point.
        if newValue == .shares, shareText.isEmpty {
            shareText = Dictionary(uniqueKeysWithValues: members.map { ($0.id, "1") })
        }
    }

    private func appendOperator(_ op: String) {
        var text = amountText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let last = text.last, last == "+" || last == "-" {
            text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        amountText = "\(text) \(op) "
    }

    var body: some View {
        Form {
            Section("Expense") {
                HStack {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        // Same SF Rounded bold-numeral treatment as
                        // BalanceHeroView (`DESIGN_BIBLE.md`'s "single
                        // highest-leverage move", `FEATURE_BACKLOG.md`
                        // "Amount-entry typography") — the amount is the
                        // most important thing on this screen.
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .focused($amountFocused)
                        .onChange(of: amountFocused) { _, focused in
                            // Resolve "12 + 8" to "20.00" once the field loses
                            // focus, but leave a bare number ("12") alone.
                            guard !focused, amountHasExpression,
                                  let resolved = MoneyFormat.evaluate(amountText) else { return }
                            amountText = MoneyFormat.plainString(minorUnits: resolved)
                        }
                    // `.decimalPad` has no operator keys — surface + / − so a
                    // running total can be typed in place (`CHECKLIST.md`
                    // "Inline calculator"). Shown even before the field is
                    // focused (`CHECKLIST.md` UX audit [19]) — otherwise
                    // there's no hint the feature exists until you've already
                    // tapped in; tapping one now focuses the field too, so
                    // it's a valid way to *start* an expression, not just
                    // continue one.
                    Button { amountFocused = true; appendOperator("+") } label: { Image(systemName: "plus") }
                    Button { amountFocused = true; appendOperator("-") } label: { Image(systemName: "minus") }
                    if currencyChoices.count > 1 {
                        Picker("Currency", selection: $currency) {
                            ForEach(currencyChoices, id: \.self) { code in Text(code).tag(code) }
                        }
                        .labelsHidden()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                TextField("Description", text: $description)
                if isMultiPayer {
                    payerAmountRows
                } else {
                    NavigationLink {
                        MemberPickerView(
                            selection: $payerId, members: members, groupId: groupId,
                            client: client, accessToken: accessToken,
                            onMemberAdded: { members.append($0) }
                        )
                    } label: {
                        HStack {
                            Text("Paid by")
                            Spacer()
                            Text(members.first { $0.id == payerId }?.displayName ?? "")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                // Multiple payers (`CHECKLIST.md` "Multiple payers on one
                // expense") is the rare case — a plain toggle keeps the common
                // single-payer Picker as the default, undisturbed. Real
                // button styling, not `.footnote` (`CHECKLIST.md` UX audit
                // [16]) — this switches modes, it isn't fine print.
                Button(isMultiPayer ? "Paid by one person" : "Split the cost between payers") {
                    isMultiPayer.toggle()
                    if isMultiPayer, payerAmountText.isEmpty {
                        // Seed with whatever's already entered for the single
                        // payer, so switching modes doesn't lose the amount.
                        payerAmountText = [payerId: amountText]
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            Section("Split") {
                // A 5-way segmented control gave every mode equal visual
                // weight (`CHECKLIST.md` UX audit [15]) — Equally/Exact/%
                // cover the common case and stay a 1-tap segmented control;
                // Shares/Items (rarer) move one tap further, behind
                // `MoreSplitsSheet`.
                if splitType == .shares || splitType == .itemized {
                    HStack {
                        Text("Split type")
                        Spacer()
                        Text(splitType.fullLabel).foregroundStyle(.secondary)
                    }
                    Button("Change") { isPresentingMoreSplits = true }
                } else {
                    Picker("Split type", selection: Binding(
                        get: { splitType },
                        set: { selectSplitType($0) }
                    )) {
                        Text("Equally").tag(SplitType.equal)
                        Text("Exact").tag(SplitType.exact)
                        Text("%").tag(SplitType.percentage)
                    }
                    .pickerStyle(.segmented)
                    // Same "not fine print" treatment as the multi-payer
                    // toggle above (`CHECKLIST.md` UX audit [16]) — this
                    // opens a real mode switch, not a footnote.
                    Button("More Split Types (Shares, Items)") { isPresentingMoreSplits = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                splitDetail
            }

            // Receipts + Comments used to be two always-visible Sections —
            // the single most overloaded screen in the app got more
            // crowded with every feature this file has picked up
            // (`CHECKLIST.md` UX audit [17]). One disclosure now, closed
            // by default on a fresh expense.
            Section {
                DisclosureGroup("More Details", isExpanded: $isShowingMoreDetails) {
                    receiptsRows
                    if isEditing { commentsRows }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                    // A retry affordance right where the error is, not just
                    // the (identical) primary button below (`CHECKLIST.md`
                    // UX audit [33]) — most useful for the offline case,
                    // where nothing else on screen changed and trying again
                    // is the entire fix.
                    Button("Retry") { Task { await save() } }
                        .disabled(isSubmitting)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(isEditing ? "Save Changes" : "Add Expense")
                        }
                    }
                    // Fill the row and read as the primary action — a solid
                    // accent fill when enabled, clearly distinct from the
                    // muted grey it drops to while a required field is empty
                    // (`CHECKLIST.md` "Add Expense submit button contrast").
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSubmit || isSubmitting)
                .primaryButtonShadow(active: canSubmit && !isSubmitting)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .materialSheetContent()
        .navigationTitle(isEditing ? "Edit Expense" : "Add Expense")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
        .dismissibleKeyboard()
        .onChange(of: pickedReceipts) { _, items in
            guard !items.isEmpty else { return }
            Task { await uploadPickedReceipts(items) }
        }
        .task { if isEditing { await loadComments() } }
        .sheet(isPresented: Binding(get: { reportingComment != nil }, set: { if !$0 { reportingComment = nil } })) {
            if let reportingComment {
                ReportContentView(
                    groupId: groupId,
                    target: reportingComment.target,
                    targetLabel: reportingComment.label,
                    client: client,
                    accessToken: accessToken,
                    contextNote: reportingComment.note,
                    onSubmitted: { self.reportingComment = nil },
                    onCancel: { self.reportingComment = nil }
                )
            }
        }
        .sheet(isPresented: $isPresentingMoreSplits) {
            MoreSplitsSheet(current: splitType, onPicked: selectSplitType)
        }
        .sheet(isPresented: $isPresentingAddMember) {
            AddMemberSheet(groupId: groupId, client: client, accessToken: accessToken) { member in
                members.append(member)
                // Fresh from "Add Expense" this is almost always someone who
                // should be on the expense right away — the equal split
                // (every split type's starting point) includes them by
                // default, same as every other member.
                includedMemberIds.insert(member.id)
            }
        }
    }

    // MARK: - Receipts (CHECKLIST.md "Photo attachment on an expense")

    /// Plain rows, not a `Section` — this lives inside `isShowingMoreDetails`'s
    /// `DisclosureGroup` now (`CHECKLIST.md` UX audit [17]), so a real inline
    /// caption stands in for the `Section` header that used to label it.
    @ViewBuilder
    private var receiptsRows: some View {
        Group {
            Text("Receipts").font(.caption).foregroundStyle(.secondary)
            if !attachmentKeys.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(attachmentKeys, id: \.self) { key in
                            ReceiptThumbnail(
                                key: key,
                                accessToken: accessToken,
                                size: 72,
                                onRemove: { attachmentKeys.removeAll { $0 == key } }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 8))
            }

            PhotosPicker(
                selection: $pickedReceipts,
                maxSelectionCount: 5,
                matching: .images,
                preferredItemEncoding: .compatible,
                photoLibrary: .shared()
            ) {
                HStack {
                    Label(attachmentKeys.isEmpty ? "Add Receipt" : "Add Another", systemImage: "paperclip")
                    Spacer()
                    if isUploadingReceipt { ProgressView() }
                }
            }
            .disabled(isUploadingReceipt)
        }
    }

    // MARK: - Comments (CHECKLIST.md "Comments on an expense")

    /// Plain rows, not a `Section` — see `receiptsRows`'s doc comment.
    @ViewBuilder
    private var commentsRows: some View {
        Group {
            Text("Comments").font(.caption).foregroundStyle(.secondary)
            if isLoadingComments, comments.isEmpty {
                HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            } else {
                ForEach(comments) { comment in
                    commentRow(comment)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Add a comment", text: $newCommentText, axis: .vertical)
                    .lineLimit(1...4)
                Button {
                    Task { await postComment() }
                } label: {
                    if isPostingComment {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(isPostingComment || newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let commentError {
                Text(commentError).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: Comment) -> some View {
        let author = members.first { $0.id == comment.authorMemberId }
        HStack(alignment: .top, spacing: 10) {
            MemberAvatar(name: author?.displayName ?? "Someone", avatarKey: author?.avatarKey, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(author?.displayName ?? "Someone").font(.subheadline.weight(.medium))
                Text(comment.text).font(.subheadline)
            }
        }
        .swipeActions {
            Button(role: .destructive) { Task { await delete(comment) } } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                reportingComment = (
                    target: .member(id: comment.authorMemberId),
                    label: "\(author?.displayName ?? "Someone")'s comment",
                    note: "Comment: \"\(comment.text)\""
                )
            } label: {
                Label("Report", systemImage: "flag")
            }
            .tint(.orange)
        }
    }

    private func loadComments() async {
        isLoadingComments = true
        defer { isLoadingComments = false }
        do {
            comments = try await client.listComments(groupId: groupId, expenseId: expenseId, accessToken: accessToken).comments
            commentError = nil
        } catch {
            commentError = friendlyMessage(for: error)
        }
    }

    private func postComment() async {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let currentMemberId else { return }
        isPostingComment = true
        commentError = nil
        defer { isPostingComment = false }
        do {
            let response = try await client.addComment(
                groupId: groupId, expenseId: expenseId,
                AddCommentRequest(id: UUID().uuidString, authorMemberId: currentMemberId, text: text),
                accessToken: accessToken
            )
            comments.append(response.comment)
            newCommentText = ""
        } catch {
            commentError = friendlyMessage(for: error)
        }
    }

    private func delete(_ comment: Comment) async {
        do {
            try await client.deleteComment(
                groupId: groupId, expenseId: expenseId, commentId: comment.id,
                accessToken: accessToken, deletedBy: currentMemberId
            )
            comments.removeAll { $0.id == comment.id }
        } catch {
            commentError = friendlyMessage(for: error)
        }
    }

    private func uploadPickedReceipts(_ items: [PhotosPickerItem]) async {
        defer { pickedReceipts = [] }
        guard let sessionToken else {
            errorMessage = "Sign in to attach a receipt."
            return
        }
        isUploadingReceipt = true
        defer { isUploadingReceipt = false }

        for item in items {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let picked = UIImage(data: data),
                let jpeg = ReceiptImage.jpegData(from: picked)
            else {
                errorMessage = "Couldn't read one of those photos."
                continue
            }
            do {
                let ticket = try await client.presignMediaUpload(
                    .receipt, contentType: "image/jpeg", contentLength: jpeg.count,
                    groupId: groupId, expenseId: expenseId, token: sessionToken, accessToken: accessToken
                )
                try await client.uploadImage(jpeg, using: ticket)
                if let small = UIImage(data: jpeg) { avatarLoader?.prime(ticket.key, with: small) }
                attachmentKeys.append(ticket.key)
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
        }
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
            memberSearchField
            ForEach(filteredMembers) { member in
                Toggle(isOn: includedBinding(for: member.id)) {
                    HStack(spacing: 10) {
                        MemberAvatar(member, size: 24)
                        Text(member.displayName)
                    }
                }
                .accessibilityLabel(member.displayName)
            }
            // Saves taps once a group has more than a few people
            // (`FEATURE_BACKLOG.md` "Select All / Select None").
            if members.count > 2 {
                HStack {
                    Button("Select All") { includedMemberIds = Set(members.map(\.id)) }
                        .disabled(includedMemberIds.count == members.count)
                    Spacer()
                    Button("Select None") { includedMemberIds = [] }
                        .disabled(includedMemberIds.isEmpty)
                }
                .font(.footnote)
            }
            addMemberButton
        case .exact:
            exactSplitRows
        case .percentage:
            percentSplitRows
        case .shares:
            shareSplitRows
        case .itemized:
            itemizedSplitRows
        }
    }

    /// `true` once the total's known and doesn't match the entered splits —
    /// drives both the footer line and, per `FEATURE_BACKLOG.md` "Inline
    /// error highlighting", the specific rows that have something entered.
    private var exactMismatch: Bool {
        guard let amountMinor else { return false }
        return amountMinor != exactSplitsTotal
    }

    private var percentMismatch: Bool { percentTotal != 100 }

    @ViewBuilder
    private var exactSplitRows: some View {
        memberSearchField
        ForEach(filteredMembers) { member in
            HStack(spacing: 10) {
                MemberAvatar(member, size: 24)
                Text(member.displayName)
                Spacer()
                TextField("0.00", text: exactAmountBinding(for: member.id))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .foregroundStyle(exactMismatch && hasEntry(exactAmountText[member.id]) ? Color.red : Color.primary)
                    .accessibilityLabel("\(member.displayName)'s share")
            }
        }
        if let amountMinor {
            Text(remainingLabel(amountMinor - exactSplitsTotal))
                .font(.footnote)
                .foregroundStyle(amountMinor == exactSplitsTotal ? Color.secondary : Color.red)
        }
    }

    /// Whether a split's text field has anything meaningful typed in it — an
    /// untouched (blank/zero) row shouldn't turn red just because *other*
    /// rows don't sum up yet.
    private func hasEntry(_ text: String?) -> Bool {
        (MoneyFormat.minorUnits(from: text ?? "") ?? 0) > 0
    }

    // MARK: - Multiple payers (CHECKLIST.md "Multiple payers on one expense")

    private func payerAmountBinding(for memberId: String) -> Binding<String> {
        Binding(
            get: { payerAmountText[memberId] ?? "" },
            set: { payerAmountText[memberId] = $0 }
        )
    }

    private var payersTotal: Int64 {
        members.reduce(Int64(0)) { $0 + (MoneyFormat.minorUnits(from: payerAmountText[$1.id] ?? "") ?? 0) }
    }

    private var payersMismatch: Bool {
        guard let amountMinor else { return false }
        return amountMinor != payersTotal
    }

    /// The entered payers as resolved `ExpensePayment`s (zero/blank rows
    /// dropped) — used for both `save()` and the running-total row labels.
    private var enteredPayers: [ExpensePayment] {
        members.compactMap { member in
            guard let value = MoneyFormat.minorUnits(from: payerAmountText[member.id] ?? ""), value > 0 else { return nil }
            return ExpensePayment(memberId: member.id, amountMinor: value)
        }
    }

    @ViewBuilder
    private var payerAmountRows: some View {
        memberSearchField
        ForEach(filteredMembers) { member in
            HStack(spacing: 10) {
                MemberAvatar(member, size: 24)
                Text(member.displayName)
                Spacer()
                TextField("0.00", text: payerAmountBinding(for: member.id))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .foregroundStyle(payersMismatch && hasEntry(payerAmountText[member.id]) ? Color.red : Color.primary)
                    .accessibilityLabel("\(member.displayName)'s contribution")
            }
        }
        if let amountMinor {
            Text(remainingLabel(amountMinor - payersTotal))
                .font(.footnote)
                .foregroundStyle(amountMinor == payersTotal ? Color.secondary : Color.red)
        }
    }

    @ViewBuilder
    private var percentSplitRows: some View {
        memberSearchField
        ForEach(filteredMembers) { member in
            HStack(spacing: 10) {
                MemberAvatar(member, size: 24)
                Text(member.displayName)
                Spacer()
                TextField("0", text: percentBinding(for: member.id))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .foregroundStyle(percentMismatch && percent(for: member.id) > 0 ? Color.red : Color.primary)
                    .accessibilityLabel("\(member.displayName)'s percentage")
                Text("%").foregroundStyle(.secondary)
            }
        }
        Text(percentRemainingLabel)
            .font(.footnote)
            .foregroundStyle(percentTotal == 100 ? Color.secondary : Color.red)
    }

    // MARK: Shares split

    /// Parsed whole-number weight for a member (blank / non-numeric → 0).
    private func share(for memberId: String) -> Int {
        max(0, Int(shareText[memberId]?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0)
    }

    private var shareTotal: Int {
        members.reduce(0) { $0 + share(for: $1.id) }
    }

    /// The resolved per-member splits at the current amount + weights — used for
    /// the live "pays ₹x" line so it matches exactly what `save()` will send
    /// (remainder rule included).
    private func resolvedShareSplits(_ amountMinor: Int64) -> [ExpenseSplit] {
        let weights = members
            .map { (memberId: $0.id, weight: share(for: $0.id)) }
            .filter { $0.weight > 0 }
        guard !weights.isEmpty else { return [] }
        return Validation.sharesSplit(amountMinor: amountMinor, weights: weights, remainderRecipient: remainderRecipient)
    }

    private func shareTextBinding(for memberId: String) -> Binding<String> {
        Binding(
            get: { shareText[memberId] ?? "" },
            set: { shareText[memberId] = $0 }
        )
    }

    private func shareStepperBinding(for memberId: String) -> Binding<Int> {
        Binding(
            get: { share(for: memberId) },
            set: { shareText[memberId] = String(max(0, $0)) }
        )
    }

    @ViewBuilder
    private var shareSplitRows: some View {
        let resolved = amountMinor.map { resolvedShareSplits($0) } ?? []
        memberSearchField
        ForEach(filteredMembers) { member in
            let w = share(for: member.id)
            let owed = resolved.first { $0.memberId == member.id }?.amountMinor
            HStack(spacing: 10) {
                MemberAvatar(member, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(member.displayName)
                    if w > 0, shareTotal > 0, let owed {
                        Text("\(w)/\(shareTotal) · \(MoneyFormat.string(minorUnits: owed, currency: currency))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                TextField("0", text: shareTextBinding(for: member.id))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 36)
                    .accessibilityLabel("\(member.displayName)'s shares")
                Stepper("", value: shareStepperBinding(for: member.id), in: 0...999)
                    .labelsHidden()
            }
        }
        Text(shareTotal > 0 ? "Split into \(shareTotal) share\(shareTotal == 1 ? "" : "s")." : "Give at least one member a share.")
            .font(.footnote)
            .foregroundStyle(shareTotal > 0 ? Color.secondary : Color.red)
    }

    // MARK: Itemized split

    private var itemsOnlyTotal: Int64 {
        itemDrafts.reduce(Int64(0)) { $0 + (MoneyFormat.minorUnits(from: $1.amountText) ?? 0) }
    }

    private var taxMinorValue: Int64 { MoneyFormat.minorUnits(from: taxText) ?? 0 }
    private var tipMinorValue: Int64 { MoneyFormat.minorUnits(from: tipText) ?? 0 }

    /// What the itemization actually adds up to: the items themselves, plus
    /// tax/tip (`CHECKLIST.md` "Tax/tip proportional split on itemized
    /// expenses") — this is what must equal `amountMinor`, not the items alone.
    private var itemizedTotal: Int64 { itemsOnlyTotal + taxMinorValue + tipMinorValue }

    /// `true` once the amount is known and the line items don't add up to it.
    private var itemizedMismatch: Bool {
        guard let amountMinor else { return false }
        return amountMinor != itemizedTotal
    }

    @ViewBuilder
    private var itemizedSplitRows: some View {
        ForEach($itemDrafts) { $item in
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Item", text: $item.name)
                    TextField("0.00", text: $item.amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .foregroundStyle(itemizedMismatch && (MoneyFormat.minorUnits(from: item.amountText) ?? 0) > 0 ? Color.red : Color.primary)
                }
                // An inline avatar row, not a `Menu` (`CHECKLIST.md` UX audit
                // [18]) — who's sharing this item is visible at a glance, and
                // toggling one doesn't require opening anything.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(members) { member in
                            let isIncluded = item.participantIds.contains(member.id)
                            Button {
                                if isIncluded {
                                    item.participantIds.remove(member.id)
                                } else {
                                    item.participantIds.insert(member.id)
                                }
                            } label: {
                                MemberAvatar(member, size: 30)
                                    .saturation(isIncluded ? 1 : 0)
                                    .opacity(isIncluded ? 1 : 0.35)
                                    .overlay(alignment: .bottomTrailing) {
                                        if isIncluded {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 13))
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .green)
                                                .background(Circle().fill(.white).padding(1.5))
                                                .offset(x: 2, y: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(member.displayName)
                            .accessibilityAddTraits(isIncluded ? [.isSelected] : [])
                            .accessibilityHint("Double tap to \(isIncluded ? "remove" : "add")")
                        }
                    }
                    .padding(.vertical, 2)
                }
                if item.participantIds.isEmpty {
                    Text("No one — tap someone above to add them")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            // No longer `.accessibilityElement(children: .combine)` — that
            // collapsed the name/amount fields and every avatar toggle into
            // one opaque VoiceOver stop, which would have made the new
            // per-member buttons (added for [18] above) unreachable. Each
            // field and avatar is its own stop now, which is also more
            // useful: a VoiceOver user can act on one member at a time
            // instead of getting a single "Line item X" blob.
        }
        .onDelete { itemDrafts.remove(atOffsets: $0) }

        Button {
            itemDrafts.append(ItemDraft(participantIds: Set(members.map(\.id))))
        } label: {
            Label("Add Item", systemImage: "plus.circle")
        }
        .font(.footnote)

        // Tax/tip (`CHECKLIST.md` "Tax/tip proportional split on itemized
        // expenses") — split by each person's own item subtotal at save time
        // (`Validation.itemizedSplit`), not split evenly like the items above.
        HStack(spacing: 8) {
            Text("Tax")
            TextField("0.00", text: $taxText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
        HStack(spacing: 8) {
            Text("Tip")
            TextField("0.00", text: $tipText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
        if taxMinorValue > 0 || tipMinorValue > 0 {
            Text("Split by what each person ordered, not evenly.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if let amountMinor {
            HStack {
                Text(remainingLabel(amountMinor - itemizedTotal))
                    .font(.footnote)
                    .foregroundStyle(amountMinor == itemizedTotal ? Color.secondary : Color.red)
                Spacer()
                if itemizedMismatch, itemizedTotal > 0 {
                    Button("Use \(MoneyFormat.string(minorUnits: itemizedTotal, currency: currency))") {
                        amountText = MoneyFormat.plainString(minorUnits: itemizedTotal)
                    }
                    .font(.footnote)
                }
            }
        } else if itemizedTotal > 0 {
            // No amount typed yet — offer the items' sum as the amount.
            Button("Set amount to \(MoneyFormat.string(minorUnits: itemizedTotal, currency: currency))") {
                amountText = MoneyFormat.plainString(minorUnits: itemizedTotal)
            }
            .font(.footnote)
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
        if isMultiPayer {
            guard payersTotal == amountMinor, !enteredPayers.isEmpty else { return false }
        } else {
            guard !payerId.isEmpty else { return false }
        }

        switch splitType {
        case .equal:
            return !includedMemberIds.isEmpty
        case .exact:
            return exactSplitsTotal == amountMinor
        case .percentage:
            return percentTotal == 100
        case .shares:
            return shareTotal > 0
        case .itemized:
            guard !itemDrafts.isEmpty, itemizedTotal == amountMinor else { return false }
            return itemDrafts.allSatisfy { item in
                (MoneyFormat.minorUnits(from: item.amountText) ?? 0) > 0 && !item.participantIds.isEmpty
            }
        }
    }

    /// Who the remainder of an uneven split lands on — normally "the payer",
    /// which stops being a single id once multiple payers are entered
    /// (`CHECKLIST.md` "Multiple payers on one expense"). The largest
    /// contributor is the closest equivalent; falls back to the first member
    /// if that's somehow ambiguous (ties broken by member order).
    private var remainderRecipient: String {
        guard isMultiPayer else { return payerId }
        return enteredPayers.max { $0.amountMinor < $1.amountMinor }?.memberId ?? members.first?.id ?? payerId
    }

    private func save() async {
        guard let amountMinor else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let payers: [ExpensePayment] = isMultiPayer
                ? enteredPayers
                : [ExpensePayment(memberId: payerId, amountMinor: amountMinor)]
            try Validation.validatePayersSum(amountMinor: amountMinor, payers: payers)

            let splits: [ExpenseSplit]
            // Only an itemized expense carries `items`, only a shares expense
            // carries `shares`, on the wire.
            var items: [LineItem]?
            var shares: [ShareWeight]?
            switch splitType {
            case .equal:
                let memberIds = members.map(\.id).filter { includedMemberIds.contains($0) }
                splits = Validation.equalSplit(amountMinor: amountMinor, memberIds: memberIds, remainderRecipient: remainderRecipient)
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
                    remainderRecipient: remainderRecipient
                )
            case .shares:
                // Resolve ratios to exact minor units here — same as percentage,
                // the wire only carries `amountMinor` shares (DESIGN.md §6). The
                // raw weights ride along too, for re-edit.
                let entered = members
                    .map { (member: $0, weight: share(for: $0.id)) }
                    .filter { $0.weight > 0 }
                shares = entered.map { ShareWeight(memberId: $0.member.id, weight: $0.weight) }
                try Validation.validateShares(
                    weights: shares ?? [],
                    validMemberIds: Set(members.map(\.id))
                )
                splits = Validation.sharesSplit(
                    amountMinor: amountMinor,
                    weights: entered.map { (memberId: $0.member.id, weight: $0.weight) },
                    remainderRecipient: remainderRecipient
                )
            case .itemized:
                // Order each item's participants by the group's member order so
                // the resolved splits are deterministic regardless of tap order.
                let resolved = itemDrafts.map { draft in
                    LineItem(
                        id: draft.id,
                        name: draft.name.trimmingCharacters(in: .whitespaces),
                        amountMinor: MoneyFormat.minorUnits(from: draft.amountText) ?? 0,
                        participantIds: members.map(\.id).filter { draft.participantIds.contains($0) }
                    )
                }
                items = resolved
                // Resolve the line items to exact per-member shares — the wire
                // carries both, and the server checks they agree (DESIGN.md §6).
                // Tax/tip (`CHECKLIST.md` "Tax/tip proportional split on
                // itemized expenses") are distributed proportionally by each
                // participant's own item subtotal, not evenly.
                try Validation.validateItems(
                    amountMinor: amountMinor,
                    items: resolved,
                    validMemberIds: Set(members.map(\.id)),
                    taxMinor: taxMinorValue,
                    tipMinor: tipMinorValue
                )
                splits = Validation.itemizedSplit(
                    items: resolved,
                    remainderRecipient: remainderRecipient,
                    taxMinor: taxMinorValue,
                    tipMinor: tipMinorValue
                )
            }

            // The same rule the server enforces (DESIGN.md §6) - catching a
            // mismatch here means a clear error before it ever hits the network,
            // even though `canSubmit` should already rule this out.
            try Validation.validateSplitsSum(amountMinor: amountMinor, splits: splits)

            // `.uncategorized` is the "no category" sentinel — send nil, not the
            // placeholder name, so it stays distinguishable from a real category.
            let isCategorised = category != .uncategorized
            // Omit the key entirely when there were no receipts and are none —
            // otherwise send the full desired list (an edit that dropped one
            // deletes its R2 object server-side).
            let hadAttachments = !(editing?.attachments ?? []).isEmpty
            let request = AddExpenseRequest(
                id: isEditing ? nil : expenseId,
                payers: payers,
                amountMinor: amountMinor,
                currency: currency,
                description: description,
                date: date,
                splitType: splitType,
                splits: splits,
                items: items,
                shares: shares,
                taxMinor: (splitType == .itemized && taxMinorValue > 0) ? taxMinorValue : nil,
                tipMinor: (splitType == .itemized && tipMinorValue > 0) ? tipMinorValue : nil,
                category: isCategorised ? category.name : nil,
                categoryIcon: isCategorised ? category.symbolName : nil,
                attachments: (attachmentKeys.isEmpty && !hadAttachments) ? nil : attachmentKeys
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

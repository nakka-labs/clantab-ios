import SwiftUI
import ClanTabKit

/// A one-shot action to run when Group Home first appears — currently only
/// the Home Screen "Add Expense" quick action (`CHECKLIST.md`).
enum GroupHomeAction: Equatable {
    case addExpense
}

struct GroupHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let client: ClanTabClient
    private let knownGroups: KnownGroupsStoring
    private let auth: AuthViewModel
    private let initialAction: GroupHomeAction?
    private let onInitialActionConsumed: () -> Void
    private let onOpenSettings: () -> Void
    /// Switch straight to another known group — the same `enterGroup` path
    /// `RootView` uses everywhere else (`NAV_POLISH_PLAN.md` Part 1).
    private let onSwitchGroup: (_ groupId: String) -> Void
    /// Leave this group's screen for the create-group flow — the "Your
    /// Groups" sheet's way out of the single-group dead end (there's no
    /// other route back to `StartView` once `resolveInitialRoute()` has
    /// skipped straight into one group).
    private let onCreateNewGroup: () -> Void
    private let onLeaveGroup: () -> Void
    private let onGroupUnavailable: () -> Void
    private let recurringTemplatesStore: RecurringTemplatesStoring = UserDefaultsRecurringTemplatesStore()
    @State private var viewModel: GroupViewModel
    @State private var nudgeError: String?
    @State private var mutationError: String?
    @State private var editingExpense: Expense?
    @State private var duplicatingExpense: Expense?
    @State private var pendingDelete: ActivityItem?
    @State private var isPresentingAddExpense = false
    @State private var isPresentingSettleUp = false
    @State private var isPresentingImport = false
    @State private var isPresentingGroupSettings = false
    @State private var isPresentingGroupSwitcher = false
    @State private var isPresentingRecentlyDeleted = false
    @State private var isPresentingRecurringReminders = false
    @State private var expenseAddedTrigger = 0
    @State private var settlementMarkedTrigger = 0
    @State private var filter = ActivityFilter()
    @State private var undoBanner: UndoBanner?
    @State private var backupNudgeDismissed = false
    /// A `GroupHomeAction` still to run — cleared once state has loaded and
    /// it's been carried out (`CHECKLIST.md` "Home Screen quick action").
    @State private var pendingInitialAction: GroupHomeAction?

    /// The fast-path "Undo" toast after a swipe-to-delete (`FEATURE_BACKLOG.md`
    /// "Delete goes to trash") — the same restore action `RecentlyDeletedView`
    /// offers indefinitely after, just quick access for ~5s.
    private struct UndoBanner: Equatable {
        enum Kind { case expense, settlement }
        let id = UUID()
        let kind: Kind
        let itemId: String
        let label: String
    }

    init(
        groupId: String,
        client: ClanTabClient,
        knownGroups: KnownGroupsStoring,
        auth: AuthViewModel,
        accessToken: String? = nil,
        initialAction: GroupHomeAction? = nil,
        onInitialActionConsumed: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onSwitchGroup: @escaping (_ groupId: String) -> Void = { _ in },
        onCreateNewGroup: @escaping () -> Void = {},
        onLeaveGroup: @escaping () -> Void = {},
        onGroupUnavailable: @escaping () -> Void = {}
    ) {
        self.client = client
        self.knownGroups = knownGroups
        self.auth = auth
        self.initialAction = initialAction
        self.onInitialActionConsumed = onInitialActionConsumed
        _pendingInitialAction = State(initialValue: initialAction)
        self.onOpenSettings = onOpenSettings
        self.onSwitchGroup = onSwitchGroup
        self.onCreateNewGroup = onCreateNewGroup
        self.onLeaveGroup = onLeaveGroup
        self.onGroupUnavailable = onGroupUnavailable
        _viewModel = State(initialValue: GroupViewModel(
            groupId: groupId, client: client, auth: auth, knownGroups: knownGroups,
            accessToken: accessToken, backup: CloudKitGroupBackup()
        ))
    }

    /// Other groups this device knows about, for the "Your Groups" sheet's
    /// list — hidden entirely when empty, leaving just "Create a Group"
    /// (the toolbar entry to reach that sheet is always shown regardless).
    private var otherKnownGroups: [KnownGroup] {
        knownGroups.all().filter { $0.groupId != viewModel.groupId }
    }

    /// The nav-bar title: the group's name, prefixed with its visual-identity
    /// emoji (`CHECKLIST.md` "Group visual identity") when it has one.
    private var headerTitle: String {
        let name = viewModel.state?.group.name ?? "Group"
        if let emoji = viewModel.state?.group.emoji, !emoji.isEmpty {
            return "\(emoji) \(name)"
        }
        return name
    }

    var body: some View {
        List {
            if auth.shouldShowSyncNudge() {
                Section {
                    SyncNudgeCard(
                        onCredential: { token, userID, authCode in
                            nudgeError = nil
                            Task { await auth.signIn(identityToken: token, userID: userID, authorizationCode: authCode) }
                        },
                        onFailure: { nudgeError = $0 },
                        onDismiss: { auth.dismissSyncNudge() }
                    )
                    if let message = auth.errorMessage ?? nudgeError {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
            }

            if let state = viewModel.state, auth.shouldShowBackupNudge(), !backupNudgeDismissed {
                Section {
                    BackupNudgeCard(
                        csvURL: backupCSVURL(state),
                        onDismiss: { backupNudgeDismissed = true }
                    )
                }
                .onAppear { auth.recordBackupNudgeShown() }
            }

            // Always present — while state loads it's a redacted placeholder in
            // the group's accent, so opening a group lands on its coloured
            // identity card immediately instead of a blank screen (`CHECKLIST.md`
            // "Spring/matched-geometry transition").
            Section {
                BalanceHeroView(
                    balances: viewModel.myBalances,
                    accent: GroupColor.color(forId: viewModel.groupId),
                    wash: GroupColor.wash(forId: viewModel.groupId),
                    isLoading: viewModel.state == nil
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if let settlements = viewModel.state?.simplifiedSettlements, !settlements.isEmpty {
                Section {
                    Button {
                        isPresentingSettleUp = true
                    } label: {
                        Label("Settle Up", systemImage: "checkmark.circle")
                    }
                }
            }

            if let state = viewModel.state, !state.expenses.isEmpty {
                Section {
                    NavigationLink {
                        InsightsView(
                            expenses: state.expenses,
                            members: state.members,
                            groupName: state.group.name,
                            groupEmoji: state.group.emoji
                        )
                    } label: {
                        Label("Spending Insights", systemImage: "chart.bar")
                    }
                }
            }

            if let state = viewModel.state {
                Section("Members") {
                    ForEach(state.members) { member in
                        MemberBalanceRow(
                            member: member,
                            balances: viewModel.balances(forMember: member.id)
                        )
                    }
                }

                Section {
                    let items = activityFeed(state: state)
                    if items.isEmpty {
                        // The genuine zero-state gets ClanTab's custom
                        // empty-state glyph (`DESIGN_BIBLE.md` §4) — it's the
                        // first thing a brand-new group shows; a filtered
                        // no-match is a transient outcome, so it keeps a plain
                        // SF Symbol.
                        if filter.isActive {
                            ContentUnavailableView(
                                "Nothing Matches",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("No expense here fits that search. Try different words, or clear the filters.")
                            )
                        } else {
                            ContentUnavailableView(
                                "No Expenses Yet",
                                image: "EmptyStateGlyph",
                                description: Text("Add the first one and ClanTab keeps a running tally of who owes whom.")
                            )
                        }
                    } else {
                        ForEach(items) { item in
                            ActivityRow(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture { edit(item) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { pendingDelete = item } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    if case .expense(let expense) = item.kind {
                                        Button { edit(item) } label: { Label("Edit", systemImage: "pencil") }
                                            .tint(.blue)
                                        Button { duplicatingExpense = expense } label: {
                                            Label("Duplicate", systemImage: "doc.on.doc")
                                        }
                                        .tint(.orange)
                                    }
                                }
                        }
                    }
                    if let mutationError {
                        Text(mutationError).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    HStack {
                        Text("Activity")
                        if filter.isActive {
                            Spacer()
                            Button("Clear Filters") { filter = ActivityFilter() }
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Surface.canvas)
        .navigationTitle(headerTitle)
        .searchable(text: $filter.searchText, prompt: "Search activity")
        .refreshable { await viewModel.refetch() }
        .task(id: viewModel.state == nil) {
            // Opened via the Home Screen "Add Expense" quick action
            // (`CHECKLIST.md`); the state check waits for the members/currency
            // the form needs — cold launch reaches here with the action
            // already pending.
            runInitialActionIfReady()
        }
        .onChange(of: initialAction) { _, action in
            // The same action arriving while this exact group is already on
            // screen (a warm-launch quick action) — the initializer above
            // won't re-run, so react to the prop change too.
            pendingInitialAction = action
            runInitialActionIfReady()
        }
        .task {
            await viewModel.load()
            // Poll while Group Home is on screen so another device's expenses
            // and settlements appear without a manual pull-to-refresh. `.task`
            // is cancelled automatically when the view goes away; a suspended
            // (backgrounded) app just stops ticking and the scenePhase handler
            // below catches up on return.
            while !Task.isCancelled {
                try? await Task.sleep(for: GroupViewModel.pollInterval)
                await viewModel.autoRefetch()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.autoRefetch() }
            }
        }
        .onChange(of: viewModel.groupUnavailable) { _, unavailable in
            if unavailable { onGroupUnavailable() }
        }
        .onChange(of: viewModel.state?.group.name) { _, name in
            // Cache the group's name for the start-screen "Your Groups" list —
            // a join/deep-link only ever gave us the groupId.
            if let name, !name.isEmpty {
                knownGroups.remember(groupId: viewModel.groupId, name: name, at: Date())
            }
        }
        .onChange(of: viewModel.state?.group.emoji) { _, emoji in
            // Cache the group's visual-identity emoji for the "Your Groups"
            // list (`CHECKLIST.md`). A load with no emoji clears any stale one.
            if viewModel.state != nil {
                knownGroups.setEmoji(groupId: viewModel.groupId, emoji: emoji)
            }
        }
        .onChange(of: viewModel.accessToken) { _, token in
            // Keep the local cache current — picks up a rotation from
            // another device (via a refetch) or this one's own "Regenerate
            // Link" (`ACCESS_TOKEN_PLAN.md`).
            if let token {
                knownGroups.remember(groupId: viewModel.groupId, accessToken: token, at: Date())
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.state == nil {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                // Always shown, even with no other known groups — otherwise
                // there's no way back to the create-group flow once
                // `resolveInitialRoute()` has skipped straight into the
                // device's one group.
                Button {
                    isPresentingGroupSwitcher = true
                } label: {
                    Label("Your Groups", systemImage: "square.on.square")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let state = viewModel.state, !state.expenses.isEmpty || !state.settlements.isEmpty {
                    activityFilterMenu(state: state)
                }
                groupSettingsButton
                shareMenu
                Button {
                    isPresentingAddExpense = true
                } label: {
                    Label("Add Expense", systemImage: "plus")
                }
                .disabled(viewModel.state == nil)
            }
        }
        .sheet(isPresented: $isPresentingAddExpense) {
            NavigationStack {
                AddExpenseView(
                    groupId: viewModel.groupId,
                    members: viewModel.state?.members ?? [],
                    defaultCurrency: viewModel.lastUsedCurrency,
                    currentMemberId: viewModel.myIdentity?.memberId,
                    client: client,
                    accessToken: viewModel.accessToken,
                    onSaved: {
                        isPresentingAddExpense = false
                        expenseAddedTrigger += 1
                        Task { await viewModel.refetch() }
                    },
                    onCancel: { isPresentingAddExpense = false }
                )
            }
            .materialSheet()
        }
        .sheet(isPresented: $isPresentingSettleUp) {
            NavigationStack {
                SettleUpView(
                    groupId: viewModel.groupId,
                    client: client,
                    accessToken: viewModel.accessToken,
                    viewModel: viewModel,
                    onSettled: {
                        // The one confirm-moment that gets the branded sound
                        // as well as the haptic (`DESIGN_BIBLE.md` §5).
                        settlementMarkedTrigger += 1
                        ConfirmationSound.play()
                    },
                    onDone: { isPresentingSettleUp = false }
                )
            }
            .materialSheet()
        }
        .sheet(isPresented: $isPresentingImport) {
            NavigationStack {
                ImportCSVView(
                    groupId: viewModel.groupId,
                    existingMembers: viewModel.state?.members ?? [],
                    client: client,
                    accessToken: viewModel.accessToken,
                    onImported: {
                        isPresentingImport = false
                        expenseAddedTrigger += 1
                        Task { await viewModel.refetch() }
                    },
                    onCancel: { isPresentingImport = false }
                )
            }
            .materialSheet()
        }
        .sheet(item: $editingExpense) { expense in
            NavigationStack {
                AddExpenseView(
                    groupId: viewModel.groupId,
                    members: viewModel.state?.members ?? [],
                    defaultCurrency: expense.currency,
                    currentMemberId: viewModel.myIdentity?.memberId,
                    client: client,
                    accessToken: viewModel.accessToken,
                    editing: expense,
                    onSaved: {
                        editingExpense = nil
                        mutationError = nil
                        expenseAddedTrigger += 1
                        Task { await viewModel.refetch() }
                    },
                    onCancel: { editingExpense = nil }
                )
            }
            .materialSheet()
        }
        .sheet(item: $duplicatingExpense) { expense in
            NavigationStack {
                AddExpenseView(
                    groupId: viewModel.groupId,
                    members: viewModel.state?.members ?? [],
                    defaultCurrency: expense.currency,
                    currentMemberId: viewModel.myIdentity?.memberId,
                    client: client,
                    accessToken: viewModel.accessToken,
                    duplicating: expense,
                    onSaved: {
                        duplicatingExpense = nil
                        expenseAddedTrigger += 1
                        Task { await viewModel.refetch() }
                    },
                    onCancel: { duplicatingExpense = nil }
                )
            }
            .materialSheet()
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) { Task { await performDelete(item) } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isPresentingGroupSettings) {
            if let state = viewModel.state {
                NavigationStack {
                    GroupSettingsView(
                        groupId: viewModel.groupId,
                        state: state,
                        client: client,
                        accessToken: viewModel.accessToken,
                        myMemberId: viewModel.myIdentity?.memberId,
                        onChanged: { Task { await viewModel.refetch() } },
                        onRegenerated: { viewModel.updateAccessToken($0) },
                        onLeave: { isPresentingGroupSettings = false; onLeaveGroup() },
                        onDone: { isPresentingGroupSettings = false }
                    )
                }
                .materialSheet()
            }
        }
        .sheet(isPresented: $isPresentingGroupSwitcher) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Button {
                            isPresentingGroupSwitcher = false
                            onCreateNewGroup()
                        } label: {
                            Label("Create a Group", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        if !otherKnownGroups.isEmpty {
                            GroupsListView(
                                groups: otherKnownGroups,
                                onOpenGroup: { groupId in
                                    isPresentingGroupSwitcher = false
                                    onSwitchGroup(groupId)
                                },
                                onRemoveGroup: { groupId in
                                    knownGroups.forget(groupId: groupId)
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .navigationTitle("Your Groups")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { isPresentingGroupSwitcher = false }
                    }
                }
            }
            .materialSheet()
        }
        .sheet(isPresented: $isPresentingRecentlyDeleted) {
            NavigationStack {
                RecentlyDeletedView(
                    groupId: viewModel.groupId,
                    client: client,
                    accessToken: viewModel.accessToken,
                    members: viewModel.state?.members ?? [],
                    onRestored: { Task { await viewModel.refetch() } },
                    onDone: { isPresentingRecentlyDeleted = false }
                )
            }
            .materialSheet()
        }
        .sheet(isPresented: $isPresentingRecurringReminders) {
            NavigationStack {
                RecurringRemindersView(
                    groupId: viewModel.groupId,
                    members: viewModel.state?.members ?? [],
                    client: client,
                    accessToken: viewModel.accessToken,
                    store: recurringTemplatesStore,
                    onLogged: {
                        expenseAddedTrigger += 1
                        Task { await viewModel.refetch() }
                    },
                    onDone: { isPresentingRecurringReminders = false }
                )
            }
            .materialSheet()
        }
        .overlay(alignment: .bottom) {
            if let undoBanner {
                HStack {
                    Text("Deleted \"\(undoBanner.label)\"")
                        .lineLimit(1)
                    Spacer()
                    Button("Undo") { Task { await undo() } }
                        .fontWeight(.semibold)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.claimSettle, value: undoBanner)
        .sensoryFeedback(.success, trigger: expenseAddedTrigger)
        .sensoryFeedback(.success, trigger: settlementMarkedTrigger)
    }

    private var deleteTitle: String {
        guard let pendingDelete else { return "" }
        if case .settlement = pendingDelete.kind { return "Delete this settlement?" }
        return "Delete this expense?"
    }

    /// Carry out a still-pending `GroupHomeAction` once the group's state has
    /// loaded (`CHECKLIST.md` "Home Screen quick action").
    private func runInitialActionIfReady() {
        guard pendingInitialAction == .addExpense, viewModel.state != nil else { return }
        pendingInitialAction = nil
        onInitialActionConsumed()
        isPresentingAddExpense = true
    }

    private func edit(_ item: ActivityItem) {
        if case .expense(let expense) = item.kind {
            mutationError = nil
            editingExpense = expense
        }
    }

    private func performDelete(_ item: ActivityItem) async {
        mutationError = nil
        let deletedBy = viewModel.myIdentity?.memberId
        do {
            let banner: UndoBanner
            switch item.kind {
            case .expense(let expense):
                try await client.deleteExpense(
                    groupId: viewModel.groupId, expenseId: expense.id,
                    accessToken: viewModel.accessToken, deletedBy: deletedBy
                )
                banner = UndoBanner(kind: .expense, itemId: expense.id, label: expense.description)
            case .settlement(let settlement):
                try await client.deleteSettlement(
                    groupId: viewModel.groupId, settlementId: settlement.id,
                    accessToken: viewModel.accessToken, deletedBy: deletedBy
                )
                banner = UndoBanner(kind: .settlement, itemId: settlement.id, label: "Settlement")
            }
            await viewModel.refetch()
            showUndo(banner)
        } catch {
            mutationError = friendlyMessage(for: error)
        }
    }

    /// Shows the "Undo" toast for ~5s, then dismisses it — unless a newer
    /// delete has already replaced it (compares by `id`, not just nil-ness).
    private func showUndo(_ banner: UndoBanner) {
        undoBanner = banner
        Task {
            try? await Task.sleep(for: .seconds(5))
            if undoBanner?.id == banner.id { undoBanner = nil }
        }
    }

    private func undo() async {
        guard let banner = undoBanner else { return }
        undoBanner = nil
        mutationError = nil
        do {
            switch banner.kind {
            case .expense:
                _ = try await client.restoreExpense(groupId: viewModel.groupId, expenseId: banner.itemId, accessToken: viewModel.accessToken)
            case .settlement:
                _ = try await client.restoreSettlement(groupId: viewModel.groupId, settlementId: banner.itemId, accessToken: viewModel.accessToken)
            }
            await viewModel.refetch()
        } catch {
            mutationError = friendlyMessage(for: error)
        }
    }

    /// The same CSV export `shareMenu`'s "Export CSV" item builds, reused by
    /// `BackupNudgeCard` (`FEATURE_BACKLOG.md` "Backup, in two tiers").
    private func backupCSVURL(_ state: GroupStateResponse) -> URL? {
        let filenameBase = ExportFile.sanitizedFilename(state.group.name)
        let csv = Export.csv(members: state.members, expenses: state.expenses, settlements: state.settlements)
        return ExportFile.write(csv, filename: "\(filenameBase)-export.csv")
    }

    /// Group Settings gets its own toolbar entry (found 2026-09-09: it was
    /// buried as the last of 7 items inside `shareMenu`, a menu labeled and
    /// iconed as "share" — the wrong home for rename/currency/leave-group).
    /// `slider.horizontal.3` matches the icon `GroupSettingsView` already
    /// used for its own row there, so nothing about the destination changes,
    /// only how it's reached.
    private var groupSettingsButton: some View {
        Button {
            isPresentingGroupSettings = true
        } label: {
            Label("Group Settings", systemImage: "slider.horizontal.3")
        }
        .disabled(viewModel.state == nil)
    }

    @ViewBuilder
    private var shareMenu: some View {
        if let state = viewModel.state {
            Menu {
                ShareLink("Share Invite Link", item: AppConfig.groupShareURL(groupId: viewModel.groupId, accessToken: viewModel.accessToken))
                ShareLink("Share Join Code (\(state.group.joinCode))", item: state.group.joinCode)

                let filenameBase = ExportFile.sanitizedFilename(state.group.name)
                let csv = Export.csv(members: state.members, expenses: state.expenses, settlements: state.settlements)
                if let csvURL = ExportFile.write(csv, filename: "\(filenameBase)-export.csv") {
                    ShareLink("Export CSV", item: csvURL)
                }

                if let jsonData = try? Export.json(
                    groupName: state.group.name,
                    currency: state.group.currency,
                    members: state.members,
                    expenses: state.expenses,
                    settlements: state.settlements
                ), let jsonURL = ExportFile.write(jsonData, filename: "\(filenameBase)-export.json") {
                    ShareLink("Export JSON", item: jsonURL)
                }

                Divider()
                Button("Import from CSV", systemImage: "square.and.arrow.down") {
                    isPresentingImport = true
                }
                Button("Recently Deleted", systemImage: "trash") {
                    isPresentingRecentlyDeleted = true
                }
                Button("Recurring Reminders", systemImage: "repeat") {
                    isPresentingRecurringReminders = true
                }
            } label: {
                Label("Group Options", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func activityFeed(state: GroupStateResponse) -> [ActivityItem] {
        let filtered = ActivityFiltering.apply(
            filter,
            expenses: state.expenses,
            settlements: state.settlements,
            members: state.members
        )
        let expenseItems = filtered.expenses.map { ActivityItem(expense: $0, members: state.members) }
        let settlementItems = filtered.settlements.map { ActivityItem(settlement: $0, members: state.members) }
        return (expenseItems + settlementItems).sorted { $0.date > $1.date }
    }

    /// The toolbar filter control: member + category pickers, plus Clear. Text
    /// search is the nav-bar `.searchable` field. The icon fills in when a
    /// filter is active.
    @ViewBuilder
    private func activityFilterMenu(state: GroupStateResponse) -> some View {
        let categories = ActivityFiltering.categories(in: state.expenses)

        Menu {
            Picker("Member", selection: $filter.memberId) {
                Text("Everyone").tag(String?.none)
                ForEach(state.members) { member in
                    Text(member.displayName).tag(Optional(member.id))
                }
            }

            if !categories.isEmpty {
                Picker("Category", selection: $filter.category) {
                    Text("All categories").tag(CategoryFilter.any)
                    ForEach(categories, id: \.name) { category in
                        Label(category.name, systemImage: category.symbolName)
                            .tag(category == .uncategorized ? CategoryFilter.uncategorized : CategoryFilter.named(category.name))
                    }
                }
            }

            if filter.isActive {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle") { filter = ActivityFilter() }
            }
        } label: {
            Label(
                "Filter Activity",
                systemImage: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
    }
}

import SwiftUI
import ClanTabKit

struct GroupHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let client: ClanTabClient
    private let knownGroups: KnownGroupsStoring
    private let auth: AuthViewModel
    private let onOpenSettings: () -> Void
    /// Switch straight to another known group — the same `enterGroup` path
    /// `RootView` uses everywhere else (`NAV_POLISH_PLAN.md` Part 1).
    private let onSwitchGroup: (_ groupId: String) -> Void
    private let onLeaveGroup: () -> Void
    private let onGroupUnavailable: () -> Void
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
    @State private var expenseAddedTrigger = 0
    @State private var settlementMarkedTrigger = 0
    @State private var filter = ActivityFilter()
    @State private var undoBanner: UndoBanner?

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
        onOpenSettings: @escaping () -> Void = {},
        onSwitchGroup: @escaping (_ groupId: String) -> Void = { _ in },
        onLeaveGroup: @escaping () -> Void = {},
        onGroupUnavailable: @escaping () -> Void = {}
    ) {
        self.client = client
        self.knownGroups = knownGroups
        self.auth = auth
        self.onOpenSettings = onOpenSettings
        self.onSwitchGroup = onSwitchGroup
        self.onLeaveGroup = onLeaveGroup
        self.onGroupUnavailable = onGroupUnavailable
        _viewModel = State(initialValue: GroupViewModel(groupId: groupId, client: client, auth: auth, accessToken: accessToken))
    }

    /// Other groups this device knows about — when there are none, "Switch
    /// Group" has nowhere to go, so the toolbar entry stays hidden.
    private var otherKnownGroups: [KnownGroup] {
        knownGroups.all().filter { $0.groupId != viewModel.groupId }
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

            if viewModel.state != nil {
                Section {
                    BalanceHeroView(balances: viewModel.myBalances)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

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
                        InsightsView(expenses: state.expenses, members: state.members)
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
                        Text(filter.isActive ? "Nothing matches your filters." : "No expenses yet.")
                            .foregroundStyle(.secondary)
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
        .navigationTitle(viewModel.state?.group.name ?? "Group")
        .searchable(text: $filter.searchText, prompt: "Search activity")
        .refreshable { await viewModel.refetch() }
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
            if !otherKnownGroups.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresentingGroupSwitcher = true
                    } label: {
                        Label("Switch Group", systemImage: "square.on.square")
                    }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let state = viewModel.state, !state.expenses.isEmpty || !state.settlements.isEmpty {
                    activityFilterMenu(state: state)
                }
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
        }
        .sheet(isPresented: $isPresentingSettleUp) {
            NavigationStack {
                SettleUpView(
                    groupId: viewModel.groupId,
                    client: client,
                    accessToken: viewModel.accessToken,
                    viewModel: viewModel,
                    onSettled: { settlementMarkedTrigger += 1 },
                    onDone: { isPresentingSettleUp = false }
                )
            }
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
                        onChanged: { Task { await viewModel.refetch() } },
                        onRegenerated: { viewModel.updateAccessToken($0) },
                        onLeave: { isPresentingGroupSettings = false; onLeaveGroup() },
                        onDone: { isPresentingGroupSettings = false }
                    )
                }
            }
        }
        .sheet(isPresented: $isPresentingGroupSwitcher) {
            NavigationStack {
                ScrollView {
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
                    .padding()
                }
                .navigationTitle("Switch Group")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { isPresentingGroupSwitcher = false }
                    }
                }
            }
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
        .animation(.default, value: undoBanner)
        .sensoryFeedback(.success, trigger: expenseAddedTrigger)
        .sensoryFeedback(.success, trigger: settlementMarkedTrigger)
    }

    private var deleteTitle: String {
        guard let pendingDelete else { return "" }
        if case .settlement = pendingDelete.kind { return "Delete this settlement?" }
        return "Delete this expense?"
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
                Button("Group Settings", systemImage: "slider.horizontal.3") {
                    isPresentingGroupSettings = true
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

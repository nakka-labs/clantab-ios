import SwiftUI
import ClanTabKit

struct GroupHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let client: ClanTabClient
    private let onGroupUnavailable: () -> Void
    @State private var viewModel: GroupViewModel
    @State private var isPresentingAddExpense = false
    @State private var isPresentingSettleUp = false
    @State private var expenseAddedTrigger = 0
    @State private var settlementMarkedTrigger = 0
    @State private var filter = ActivityFilter()

    init(
        groupId: String,
        client: ClanTabClient,
        identityStore: IdentityStoring,
        onGroupUnavailable: @escaping () -> Void = {}
    ) {
        self.client = client
        self.onGroupUnavailable = onGroupUnavailable
        _viewModel = State(initialValue: GroupViewModel(groupId: groupId, client: client, identityStore: identityStore))
    }

    var body: some View {
        List {
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
                        }
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
        .overlay {
            if viewModel.isLoading && viewModel.state == nil {
                ProgressView()
            }
        }
        .toolbar {
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
                    viewModel: viewModel,
                    onSettled: { settlementMarkedTrigger += 1 },
                    onDone: { isPresentingSettleUp = false }
                )
            }
        }
        .sensoryFeedback(.success, trigger: expenseAddedTrigger)
        .sensoryFeedback(.success, trigger: settlementMarkedTrigger)
    }

    @ViewBuilder
    private var shareMenu: some View {
        if let state = viewModel.state {
            Menu {
                ShareLink("Share Invite Link", item: AppConfig.groupShareURL(groupId: viewModel.groupId))
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
            } label: {
                Label("Share & Export", systemImage: "square.and.arrow.up")
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

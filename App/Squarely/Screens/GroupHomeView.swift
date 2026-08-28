import SwiftUI
import SquareKit

struct GroupHomeView: View {
    private let client: SquarelyClient
    private let onGroupUnavailable: () -> Void
    @State private var viewModel: GroupViewModel
    @State private var isPresentingAddExpense = false
    @State private var isPresentingSettleUp = false
    @State private var expenseAddedTrigger = 0
    @State private var settlementMarkedTrigger = 0

    init(
        groupId: String,
        client: SquarelyClient,
        identityStore: IdentityStoring,
        onGroupUnavailable: @escaping () -> Void = {}
    ) {
        self.client = client
        self.onGroupUnavailable = onGroupUnavailable
        _viewModel = State(initialValue: GroupViewModel(groupId: groupId, client: client, identityStore: identityStore))
    }

    var body: some View {
        List {
            if let balance = viewModel.myBalance {
                Section {
                    BalanceHeroView(balance: balance, currency: currency)
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

            if let state = viewModel.state {
                Section("Members") {
                    ForEach(state.members) { member in
                        MemberBalanceRow(
                            member: member,
                            netMinor: state.balances.first { $0.memberId == member.id }?.netMinor ?? 0,
                            currency: currency
                        )
                    }
                }

                Section("Activity") {
                    let items = activityFeed(state: state)
                    if items.isEmpty {
                        Text("No expenses yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            ActivityRow(item: item, currency: currency)
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
        .refreshable { await viewModel.refetch() }
        .task { await viewModel.load() }
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
                    currency: currency,
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

    private var currency: String {
        viewModel.state?.group.currency ?? ""
    }

    private func activityFeed(state: GroupStateResponse) -> [ActivityItem] {
        let expenseItems = state.expenses.map { ActivityItem(expense: $0, members: state.members) }
        let settlementItems = state.settlements.map { ActivityItem(settlement: $0, members: state.members) }
        return (expenseItems + settlementItems).sorted { $0.date > $1.date }
    }
}

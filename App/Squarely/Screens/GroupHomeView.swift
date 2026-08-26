import SwiftUI
import SquareKit

struct GroupHomeView: View {
    private let client: SquarelyClient
    @State private var viewModel: GroupViewModel
    @State private var isPresentingAddExpense = false
    @State private var isPresentingSettleUp = false

    init(groupId: String, client: SquarelyClient, identityStore: IdentityStoring) {
        self.client = client
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
        .overlay {
            if viewModel.isLoading && viewModel.state == nil {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
                    onDone: { isPresentingSettleUp = false }
                )
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

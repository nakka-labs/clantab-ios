import SwiftUI
import SquareKit

struct GroupHomeView: View {
    @State private var viewModel: GroupViewModel

    init(groupId: String, client: SquarelyClient, identityStore: IdentityStoring) {
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

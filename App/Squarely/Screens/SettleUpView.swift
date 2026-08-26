import SwiftUI
import SquareKit

/// Renders the server-computed settle-up plan (`DESIGN.md` §2's
/// `simplifiedSettlements` — never recomputed client-side) as minimal
/// transaction cards, each with a 1-tap "Mark as Paid". Squarely never
/// processes money itself: marking paid just records that the payment
/// happened outside the app.
///
/// Takes the same `GroupViewModel` instance `GroupHomeView` holds, rather than
/// a static snapshot, so "Mark as Paid" → `refetch()` naturally updates this
/// list (and the presenting screen) with the server's freshly recomputed plan.
struct SettleUpView: View {
    let groupId: String
    let client: SquarelyClient
    let viewModel: GroupViewModel
    let onDone: () -> Void

    @State private var pendingRowId: String?
    @State private var errorMessage: String?

    private var members: [Member] {
        viewModel.state?.members ?? []
    }

    private var currency: String {
        viewModel.state?.group.currency ?? ""
    }

    private var settlements: [SimplifiedSettlement] {
        viewModel.state?.simplifiedSettlements ?? []
    }

    var body: some View {
        List {
            if settlements.isEmpty {
                Section {
                    Text("Everyone is settled up.").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(Array(settlements.enumerated()), id: \.offset) { _, settlement in
                        settlementRow(settlement)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settle Up")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done", action: onDone)
            }
        }
    }

    private func settlementRow(_ settlement: SimplifiedSettlement) -> some View {
        let rowId = "\(settlement.fromId)->\(settlement.toId)"
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name(for: settlement.fromId)) pays \(name(for: settlement.toId))")
                Text(MoneyFormat.string(minorUnits: settlement.amountMinor, currency: currency))
                    .font(.headline)
            }
            Spacer()
            Button {
                Task { await markPaid(settlement, rowId: rowId) }
            } label: {
                if pendingRowId == rowId {
                    ProgressView()
                } else {
                    Text("Mark as Paid")
                }
            }
            .buttonStyle(.bordered)
            .disabled(pendingRowId != nil)
        }
        .padding(.vertical, 4)
    }

    private func name(for memberId: String) -> String {
        members.first { $0.id == memberId }?.displayName ?? "Someone"
    }

    private func markPaid(_ settlement: SimplifiedSettlement, rowId: String) async {
        pendingRowId = rowId
        errorMessage = nil
        defer { pendingRowId = nil }

        do {
            _ = try await client.addSettlement(
                groupId: groupId,
                AddSettlementRequest(
                    id: UUID().uuidString,
                    fromId: settlement.fromId,
                    toId: settlement.toId,
                    amountMinor: settlement.amountMinor
                )
            )
            await viewModel.refetch()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}

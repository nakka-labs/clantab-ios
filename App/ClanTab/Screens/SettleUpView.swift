import SwiftUI
import ClanTabKit

/// Renders the server-computed settle-up plan (`DESIGN.md` §2's
/// `simplifiedSettlements` — never recomputed client-side) as minimal
/// transaction cards, each with a 1-tap "Mark as Paid". ClanTab never
/// processes money itself: marking paid just records that the payment
/// happened outside the app.
///
/// Takes the same `GroupViewModel` instance `GroupHomeView` holds, rather than
/// a static snapshot, so "Mark as Paid" → `refetch()` naturally updates this
/// list (and the presenting screen) with the server's freshly recomputed plan.
struct SettleUpView: View {
    let groupId: String
    let client: ClanTabClient
    let viewModel: GroupViewModel
    let onSettled: () -> Void
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
        let payer = name(for: settlement.fromId)
        let payee = name(for: settlement.toId)
        let amount = MoneyFormat.string(minorUnits: settlement.amountMinor, currency: currency)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(payer) pays \(payee)")
                Text(amount)
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
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
            .accessibilityLabel("Mark \(payer)'s \(amount) payment to \(payee) as paid")
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
            onSettled()
            await viewModel.refetch()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}

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
    let accessToken: String?
    let viewModel: GroupViewModel
    let onSettled: () -> Void
    let onDone: () -> Void

    @State private var pendingRowId: String?
    @State private var errorMessage: String?

    private var members: [Member] {
        viewModel.state?.members ?? []
    }

    private var settlements: [SimplifiedSettlement] {
        viewModel.state?.simplifiedSettlements ?? []
    }

    /// The plan grouped into per-currency sections, in the order currencies
    /// first appear (matching the server's `simplifiedSettlements` order).
    private var settlementsByCurrency: [(currency: String, items: [SimplifiedSettlement])] {
        var order: [String] = []
        var groups: [String: [SimplifiedSettlement]] = [:]
        for s in settlements {
            if groups[s.currency] == nil { order.append(s.currency) }
            groups[s.currency, default: []].append(s)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        List {
            if settlements.isEmpty {
                Section {
                    Text("Everyone is settled up.").foregroundStyle(.secondary)
                }
            } else {
                ForEach(settlementsByCurrency, id: \.currency) { group in
                    Section(settlementsByCurrency.count > 1 ? group.currency : "") {
                        ForEach(group.items, id: \.self) { settlement in
                            settlementRow(settlement)
                        }
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
        let rowId = "\(settlement.currency):\(settlement.fromId)->\(settlement.toId)"
        let payer = name(for: settlement.fromId)
        let payee = name(for: settlement.toId)
        let amount = MoneyFormat.string(minorUnits: settlement.amountMinor, currency: settlement.currency)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
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
            if let upiURL = upiPayURL(for: settlement) {
                Link(destination: upiURL) {
                    Label("Pay via UPI", systemImage: "indianrupeesign.circle")
                }
                .font(.subheadline)
                .accessibilityLabel("Open a UPI app to pay \(payee) \(amount)")
            }
        }
        .padding(.vertical, 4)
    }

    private func name(for memberId: String) -> String {
        members.first { $0.id == memberId }?.displayName ?? "Someone"
    }

    /// A plain `upi://pay?...` deep link handing off to whichever UPI app the
    /// payer has installed (`FEATURE_BACKLOG.md` "UPI deep link on Settle
    /// Up") — ClanTab never sees or moves the money, just constructs the
    /// URI. `nil` unless the payee has set a UPI VPA and the settlement is
    /// actually in INR (UPI's only currency).
    private func upiPayURL(for settlement: SimplifiedSettlement) -> URL? {
        guard settlement.currency == "INR",
              let payee = members.first(where: { $0.id == settlement.toId }),
              let vpa = payee.upiVpa, !vpa.isEmpty
        else { return nil }
        var components = URLComponents()
        components.scheme = "upi"
        components.host = "pay"
        let amount = Decimal(settlement.amountMinor) / 100
        components.queryItems = [
            URLQueryItem(name: "pa", value: vpa),
            URLQueryItem(name: "pn", value: payee.displayName),
            URLQueryItem(name: "am", value: NSDecimalNumber(decimal: amount).stringValue),
            URLQueryItem(name: "cu", value: "INR"),
            URLQueryItem(name: "tn", value: "ClanTab settle up"),
        ]
        return components.url
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
                    amountMinor: settlement.amountMinor,
                    currency: settlement.currency
                ),
                accessToken: accessToken
            )
            onSettled()
            await viewModel.refetch()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}

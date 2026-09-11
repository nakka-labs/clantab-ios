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
    @State private var confirmingSettlement: SimplifiedSettlement?
    /// The shareable recap card (`CHECKLIST.md`), rendered off-screen once the
    /// plan is in hand and re-rendered whenever it changes.
    @State private var shareCard: Image?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        .materialSheetContent()
        .navigationTitle("Settle Up")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done", action: onDone)
            }
            if let shareCard {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: shareCard,
                        preview: SharePreview("\(groupName) — settle up", image: shareCard)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: settlements) {
            shareCard = RecapCard.render(RecapCard(
                groupName: groupName,
                groupEmoji: viewModel.state?.group.emoji,
                members: members,
                content: .settleUp(settlements)
            ))
        }
        .confirmationDialog(
            "Mark as paid?",
            isPresented: Binding(get: { confirmingSettlement != nil }, set: { if !$0 { confirmingSettlement = nil } }),
            presenting: confirmingSettlement,
            actions: { settlement in
                Button("Mark as Paid") {
                    Task { await markPaid(settlement, rowId: rowId(for: settlement)) }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: { settlement in
                Text(
                    "\(name(for: settlement.fromId)) pays \(name(for: settlement.toId)) "
                        + "\(MoneyFormat.string(minorUnits: settlement.amountMinor, currency: settlement.currency)). "
                        + "ClanTab just records this as settled — it doesn't move any money."
                )
            }
        )
    }

    private func rowId(for settlement: SimplifiedSettlement) -> String {
        "\(settlement.currency):\(settlement.fromId)->\(settlement.toId)"
    }

    private var groupName: String { viewModel.state?.group.name ?? "Your group" }

    private func settlementRow(_ settlement: SimplifiedSettlement) -> some View {
        let rowId = rowId(for: settlement)
        let payer = name(for: settlement.fromId)
        let payee = name(for: settlement.toId)
        let amount = MoneyFormat.string(minorUnits: settlement.amountMinor, currency: settlement.currency)
        let markPaidButton = Button {
            confirmingSettlement = settlement
        } label: {
            Group {
                if pendingRowId == rowId {
                    ProgressView()
                } else {
                    Text("Mark as Paid").lineLimit(1)
                }
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .disabled(pendingRowId != nil)
        .accessibilityLabel("Mark \(payer)'s \(amount) payment to \(payee) as paid")

        let summary = VStack(alignment: .leading, spacing: 2) {
            Text("\(payer) pays \(payee)")
            Text(amount).font(.headline).lineLimit(1)
        }
        .accessibilityElement(children: .combine)

        return VStack(alignment: .leading, spacing: 8) {
            // At accessibility text sizes the button can't sit beside the
            // names without both wrapping badly — it drops full-width below.
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top) { MemberAvatar(name: payer, size: 32); summary }
                markPaidButton
            } else {
                HStack {
                    MemberAvatar(name: payer, size: 32)
                    summary
                    Spacer()
                    markPaidButton
                }
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
        guard let payee = members.first(where: { $0.id == settlement.toId }) else { return nil }
        return UPIPayLink.url(
            vpa: payee.upiVpa,
            payeeName: payee.displayName,
            amountMinor: settlement.amountMinor,
            currency: settlement.currency
        )
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

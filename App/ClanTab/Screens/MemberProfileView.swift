import ClanTabKit
import SwiftUI

/// A read-only profile for one group member (`CHECKLIST.md` "Member profile
/// screen: settle-up amount + UPI ID") — their net balance in this group, the
/// one-line settle-up figure between them and you, and their UPI ID if they've
/// set one. All of it is data the group state already carries; this screen just
/// gathers it in one place, reachable by tapping a member anywhere they show up.
struct MemberProfileView: View {
    let member: Member
    /// This member's balances in the group, one per currency (nonzero only —
    /// empty means settled up). Pass `GroupViewModel.balances(forMember:)`.
    let balances: [Balance]
    /// The simplified settle-up plan for the whole group; the screen picks out
    /// the single edge (if any) between `myMemberId` and this member.
    let simplifiedSettlements: [SimplifiedSettlement]
    /// "Me" in this group, for phrasing the settle-up line. `nil` before the
    /// identity resolves — the settle-up section just hides.
    let myMemberId: String?

    /// The settle-up edges that involve both me and this member.
    private var settleEdges: [SimplifiedSettlement] {
        guard let myMemberId else { return [] }
        return simplifiedSettlements.filter {
            ($0.fromId == myMemberId && $0.toId == member.id) ||
            ($0.fromId == member.id && $0.toId == myMemberId)
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    MemberAvatar(member, size: 56)
                    Text(member.displayName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            Section("Balance in this group") {
                if balances.isEmpty {
                    Text("Settled up").foregroundStyle(.secondary)
                } else {
                    ForEach(balances, id: \.currency) { balance in
                        let amount = MoneyFormat.string(minorUnits: abs(balance.netMinor), currency: balance.currency)
                        HStack {
                            Text(balance.netMinor > 0 ? "Is owed" : "Owes")
                            Spacer()
                            Text(amount)
                                .foregroundStyle(balance.netMinor > 0 ? .green : .red)
                        }
                    }
                }
            }

            if myMemberId != nil, !settleEdges.isEmpty {
                Section("Settle up") {
                    ForEach(settleEdges, id: \.self) { edge in
                        settleRow(edge)
                    }
                }
            }

            if let vpa = member.upiVpa, !vpa.isEmpty {
                Section("UPI ID") {
                    HStack {
                        Text(vpa).textSelection(.enabled)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = vpa
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Copy UPI ID")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Surface.canvas)
        .navigationTitle(member.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func settleRow(_ edge: SimplifiedSettlement) -> some View {
        let iPay = edge.fromId == myMemberId
        let amount = MoneyFormat.string(minorUnits: edge.amountMinor, currency: edge.currency)
        VStack(alignment: .leading, spacing: 6) {
            Text(iPay ? "You pay \(member.displayName) \(amount)" : "\(member.displayName) pays you \(amount)")
            if iPay,
               let url = UPIPayLink.url(
                   vpa: member.upiVpa,
                   payeeName: member.displayName,
                   amountMinor: edge.amountMinor,
                   currency: edge.currency
               ) {
                Link(destination: url) {
                    Label("Pay via UPI", systemImage: "indianrupeesign.circle")
                }
                .font(.subheadline)
                .accessibilityLabel("Open a UPI app to pay \(member.displayName) \(amount)")
            }
        }
        .padding(.vertical, 2)
    }
}

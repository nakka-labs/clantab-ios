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
    let groupId: String
    let client: ClanTabClient
    let accessToken: String?
    /// This group's own active ledger — used only to build "Together in this
    /// group" below (`CHECKLIST.md` "Friend playtest, round 3"), not for any
    /// balance math (that stays server-computed, passed in via `balances`/
    /// `simplifiedSettlements`). Defaults empty so every existing call site
    /// (and every preview) keeps compiling unchanged.
    var expenses: [Expense] = []
    var settlements: [Settlement] = []
    /// Needed only to resolve names inside `ActivityItem`/`ActivityRow` —
    /// same list `GroupHomeView`'s own activity feed uses.
    var groupMembers: [Member] = []

    @State private var remindingEdge: SimplifiedSettlement?
    @State private var remindSent: Set<String> = [] // edge ids that got a confirmed "sent"
    @State private var remindError: String?

    /// The settle-up edges that involve both me and this member.
    private var settleEdges: [SimplifiedSettlement] {
        guard let myMemberId else { return [] }
        return simplifiedSettlements.filter {
            ($0.fromId == myMemberId && $0.toId == member.id) ||
            ($0.fromId == member.id && $0.toId == myMemberId)
        }
    }

    /// Every settle-up edge touching this member, against *anyone* in the
    /// group — not just against me (`settleEdges`, above, which the
    /// "Settle up" section still uses for its own pay/remind actions).
    /// Round-3 playtest, 2026-09-13: "Balance in this group" showed only
    /// the member's single net figure with no breakdown of who actually
    /// makes it up.
    private var allEdges: [SimplifiedSettlement] {
        simplifiedSettlements.filter { $0.fromId == member.id || $0.toId == member.id }
    }

    private func otherPartyId(_ edge: SimplifiedSettlement) -> String {
        edge.fromId == member.id ? edge.toId : edge.fromId
    }

    private func name(for memberId: String) -> String {
        groupMembers.first { $0.id == memberId }?.displayName ?? "Someone"
    }

    /// Every expense/settlement in this group where both me and this member
    /// are involved — an expense counts if both appear among its payers or
    /// its splits (so it still counts even if one of us didn't personally
    /// pay), a settlement if we're its two parties either direction. Newest
    /// first, same shape as `GroupHomeView`'s own activity feed.
    private var sharedHistory: [ActivityItem] {
        guard let myMemberId else { return [] }
        let sharedExpenses = expenses.filter { expense in
            let involved = Set(expense.payers.map(\.memberId) + expense.splits.map(\.memberId))
            return involved.contains(myMemberId) && involved.contains(member.id)
        }
        let sharedSettlements = settlements.filter {
            ($0.fromId == myMemberId && $0.toId == member.id) ||
            ($0.fromId == member.id && $0.toId == myMemberId)
        }
        let items = sharedExpenses.map { ActivityItem(expense: $0, members: groupMembers) }
            + sharedSettlements.map { ActivityItem(settlement: $0, members: groupMembers) }
        return items.sorted { $0.date > $1.date }
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
                    // The breakdown first — every other member's own edge
                    // with this one ("Priya owes ₹500", "Ana is owed ₹200")
                    // — then the net total each edge adds up to, visually
                    // set apart so the two never read as the same kind of
                    // line.
                    ForEach(allEdges, id: \.self) { edge in
                        let theyOweMe = edge.toId == member.id
                        let amount = MoneyFormat.string(minorUnits: edge.amountMinor, currency: edge.currency)
                        HStack {
                            Text("\(name(for: otherPartyId(edge))) \(theyOweMe ? "owes" : "is owed")")
                            Spacer()
                            Text(amount).foregroundStyle(theyOweMe ? .green : .red)
                        }
                    }
                    ForEach(balances, id: \.currency) { balance in
                        let amount = MoneyFormat.string(minorUnits: abs(balance.netMinor), currency: balance.currency)
                        HStack {
                            Text("Total").fontWeight(.semibold)
                            Spacer()
                            Text(amount)
                                .fontWeight(.semibold)
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
                    if let remindError {
                        Text(remindError).foregroundStyle(.red).font(.footnote)
                    }
                }
            }

            if myMemberId != nil, !sharedHistory.isEmpty {
                Section("Together in This Group") {
                    ForEach(sharedHistory) { item in
                        ActivityRow(item: item)
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
            // Opposite direction of `BalanceAgingScheduler` (`CHECKLIST.md`
            // "Remind button"): they owe me, so let me nudge them instead of
            // waiting for the scheduler to nudge me about what I owe.
            if !iPay {
                remindButton(edge)
            }
        }
        .padding(.vertical, 2)
    }

    private func edgeKey(_ edge: SimplifiedSettlement) -> String {
        "\(edge.fromId)-\(edge.toId)-\(edge.currency)"
    }

    @ViewBuilder
    private func remindButton(_ edge: SimplifiedSettlement) -> some View {
        let key = edgeKey(edge)
        if remindSent.contains(key) {
            Label("Reminder sent", systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Button {
                Task { await sendRemind(edge) }
            } label: {
                if remindingEdge == edge {
                    ProgressView()
                } else {
                    Label("Remind", systemImage: "bell")
                }
            }
            .font(.subheadline)
            .disabled(remindingEdge != nil)
        }
    }

    private func sendRemind(_ edge: SimplifiedSettlement) async {
        guard let myMemberId else { return }
        remindingEdge = edge
        remindError = nil
        defer { remindingEdge = nil }
        do {
            let response = try await client.remind(
                groupId: groupId, memberId: member.id, fromMemberId: myMemberId, accessToken: accessToken
            )
            if response.sent {
                remindSent.insert(edgeKey(edge))
            } else {
                remindError = "\(member.displayName) hasn't signed in yet, so there's no device to notify."
            }
        } catch {
            remindError = friendlyMessage(for: error)
        }
    }
}

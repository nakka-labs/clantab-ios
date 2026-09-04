import SwiftUI
import ClanTabKit

/// "Settle Across Groups" — the net owed to/from each linked person across every
/// group you share (`FEATURE_BACKLOG.md`). Signed-in only; reached from Settings.
struct PeopleView: View {
    let auth: AuthViewModel
    let client: ClanTabClient

    @State private var people: [CrossGroupPerson]?
    @State private var loadError: String?
    @State private var flash: String?

    var body: some View {
        List {
            if let flash {
                Section { Text(flash).font(.callout).foregroundStyle(.orange) }
            }

            if let people {
                if people.isEmpty {
                    ContentUnavailableView(
                        "Nothing to settle",
                        systemImage: "checkmark.circle",
                        description: Text("You have no open balances with anyone across your groups.")
                    )
                } else {
                    ForEach(people) { person in
                        NavigationLink {
                            PersonSettleView(person: person, auth: auth, client: client) { failed in
                                flash = failed > 0
                                    ? "\(failed) group\(failed == 1 ? "" : "s") couldn't be settled — try again."
                                    : nil
                                await reload()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(person.displayName).font(.headline)
                                Text(Self.summary(person.net, name: person.displayName))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if let loadError {
                Section { Text(loadError).foregroundStyle(.red) }
            } else {
                Section { HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) } }
            }
        }
        .navigationTitle("Across Groups")
        .navigationBarTitleDisplayMode(.inline)
        .task { if people == nil { await reload() } }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard let token = auth.session?.token else {
            loadError = "You're signed out."
            return
        }
        do {
            people = try await client.peopleAcrossGroups(token: token).people
            loadError = nil
        } catch {
            loadError = friendlyMessage(for: error)
        }
    }

    /// "You owe Bob ₹1,200 · $15" / "Bob owes you ₹300" / mixed directions.
    static func summary(_ net: [CrossGroupNet], name: String) -> String {
        let youOwe = net.filter { $0.netMinor > 0 }
        let theyOwe = net.filter { $0.netMinor < 0 }

        func list(_ items: [CrossGroupNet]) -> String {
            items.map { MoneyFormat.string(minorUnits: abs($0.netMinor), currency: $0.currency) }
                .joined(separator: " · ")
        }

        switch (youOwe.isEmpty, theyOwe.isEmpty) {
        case (false, true): return "You owe \(name) \(list(youOwe))"
        case (true, false): return "\(name) owes you \(list(theyOwe))"
        case (false, false): return "You owe \(list(youOwe)); \(name) owes you \(list(theyOwe))"
        case (true, true): return "Settled up"
        }
    }
}

/// One person's per-group breakdown + a one-tap "settle everything".
struct PersonSettleView: View {
    let person: CrossGroupPerson
    let auth: AuthViewModel
    let client: ClanTabClient
    /// Called after a settle attempt with the number of groups that failed.
    let onSettled: (_ failed: Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSettling = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Net") {
                ForEach(person.net, id: \.currency) { line in
                    Text(PeopleView.summary([line], name: person.displayName))
                }
            }

            Section("By group") {
                ForEach(person.groups) { edge in
                    HStack {
                        Text(edge.groupName)
                        Spacer()
                        Text(directionText(edge))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Button {
                    Task { await settleAll() }
                } label: {
                    if isSettling { ProgressView() } else { Text("Settle All") }
                }
                .disabled(isSettling || person.groups.isEmpty)
            } footer: {
                Text("Records a settlement in each group. This can't be undone from here.")
            }
        }
        .navigationTitle(person.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func directionText(_ edge: CrossGroupEdge) -> String {
        let amount = MoneyFormat.string(minorUnits: edge.amountMinor, currency: edge.currency)
        return edge.youPay ? "you pay \(amount)" : "pays you \(amount)"
    }

    private func settleAll() async {
        guard let token = auth.session?.token else { return }
        _ = token // settlements use groupId possession, not the session — but require sign-in to be here
        isSettling = true
        errorMessage = nil
        defer { isSettling = false }

        var failed = 0
        for edge in person.groups {
            let from = edge.youPay ? edge.myMemberId : edge.theirMemberId
            let to = edge.youPay ? edge.theirMemberId : edge.myMemberId
            do {
                _ = try await client.addSettlement(
                    groupId: edge.groupId,
                    AddSettlementRequest(
                        id: UUID().uuidString,
                        fromId: from, toId: to,
                        amountMinor: edge.amountMinor, currency: edge.currency
                    )
                )
            } catch {
                failed += 1
            }
        }
        await onSettled(failed)
        dismiss()
    }
}

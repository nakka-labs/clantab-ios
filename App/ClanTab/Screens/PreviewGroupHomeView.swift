import SwiftUI
import ClanTabKit

/// A static, offline "See how ClanTab works" preview shown pre-auth
/// (`CHECKLIST.md` UX audit [1]) — real layout, realistic sample data, no
/// network. Every interactive element routes to `onRequiresSignIn` instead of
/// doing anything, so sign-in becomes required at the point of the first real
/// action rather than before anyone can see the app at all.
///
/// Deliberately not `GroupHomeView` itself fed fake data — `ClanTabClient` is
/// a concrete `actor` and `GroupViewModel` always hits the network in
/// `load()`, so making that path fakeable would mean threading test-only
/// seams through production networking code for one pre-auth screen. This
/// reuses the same row components (`BalanceHeroView`, `MemberBalanceRow`,
/// `ActivityRow`) over static data instead — the visual is identical, only
/// the data source differs.
struct PreviewGroupHomeView: View {
    let onRequiresSignIn: () -> Void
    let onDone: () -> Void

    @State private var isShowingSignInPrompt = false

    var body: some View {
        List {
            Section {
                Label("This is a sample group — nothing here is real.", systemImage: "eye")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                BalanceHeroView(
                    balances: Self.myBalances,
                    accent: GroupColor.color(forId: Self.groupId),
                    wash: GroupColor.wash(forId: Self.groupId),
                    onSettleUp: prompt
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section("Members") {
                ForEach(Self.members) { member in
                    Button(action: prompt) {
                        MemberBalanceRow(member: member, balances: Self.balances(forMember: member.id))
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Activity") {
                ForEach(Self.activity) { item in
                    ActivityRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: prompt)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Surface.canvas)
        .navigationTitle("🏖️ \(Self.groupName)")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done", action: onDone)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: prompt) {
                    Label("Add Expense", systemImage: "plus")
                }
            }
        }
        .alert("Sign In to Continue", isPresented: $isShowingSignInPrompt) {
            Button("Sign In") { onRequiresSignIn() }
            Button("Keep Looking Around", role: .cancel) {}
        } message: {
            Text("This sample group is read-only. Sign in to create or join a real one.")
        }
    }

    private func prompt() {
        isShowingSignInPrompt = true
    }

    // MARK: - Sample data — internally consistent (every balance actually
    // derives from the sample expenses via the same pure `Balances.compute`
    // every real group uses), not just plausible-looking numbers.

    private static let groupId = "preview-goa-trip"
    private static let groupName = "Goa Trip"
    private static let currency = "INR"

    private static let alex = Member(id: "preview-alex", displayName: "Alex")
    private static let priya = Member(id: "preview-priya", displayName: "Priya")
    private static let rohan = Member(id: "preview-rohan", displayName: "Rohan")
    private static let members = [alex, priya, rohan]

    private static func equalSplit(_ amountMinor: Int64) -> [ExpenseSplit] {
        // Each of the 3 sample expenses divides evenly with no remainder —
        // real equal splits absorb a remainder onto the payer
        // (`Validation.equalSplit`), deliberately not needed for this
        // illustrative set.
        members.map { ExpenseSplit(memberId: $0.id, amountMinor: amountMinor / 3) }
    }

    private static let expenses: [Expense] = [
        Expense(
            id: "preview-hotel", payerId: alex.id, amountMinor: 450_000, currency: currency,
            description: "Beach resort, 2 nights", date: daysAgo(6),
            splitType: .equal, splits: equalSplit(450_000),
            category: "Lodging", categoryIcon: "bed.double"
        ),
        Expense(
            id: "preview-dinner", payerId: priya.id, amountMinor: 180_000, currency: currency,
            description: "Seafood dinner", date: daysAgo(5),
            splitType: .equal, splits: equalSplit(180_000),
            category: "Dining", categoryIcon: "fork.knife"
        ),
        Expense(
            id: "preview-cabs", payerId: rohan.id, amountMinor: 90_000, currency: currency,
            description: "Airport cabs", date: daysAgo(4),
            splitType: .equal, splits: equalSplit(90_000),
            category: "Transport", categoryIcon: "car"
        ),
    ]

    private static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    private static let balances = Balances.compute(members: members, expenses: expenses, settlements: [])

    private static var myBalances: [Balance] {
        balances(forMember: alex.id)
    }

    private static func balances(forMember memberId: String) -> [Balance] {
        balances.filter { $0.memberId == memberId }
    }

    private static let activity: [ActivityItem] = expenses
        .map { ActivityItem(expense: $0, members: members) }
        .sorted { $0.date > $1.date }
}

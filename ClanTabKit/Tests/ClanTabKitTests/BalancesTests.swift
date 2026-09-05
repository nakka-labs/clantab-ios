import Testing
import Foundation
@testable import ClanTabKit

@Suite("Balances")
struct BalancesTests {
    let alice = Member(id: "alice", displayName: "Alice")
    let bob = Member(id: "bob", displayName: "Bob")
    let carol = Member(id: "carol", displayName: "Carol")

    private func expense(
        id: String = "e1",
        payer: String,
        amount: Int64,
        currency: String = "USD",
        splits: [ExpenseSplit]
    ) -> Expense {
        Expense(
            id: id, payerId: payer, amountMinor: amount, currency: currency,
            description: "x", date: Date(), splitType: .exact, splits: splits
        )
    }

    private func settlement(
        id: String = "s1", from: String, to: String, amount: Int64, currency: String = "USD"
    ) -> Settlement {
        Settlement(id: id, fromId: from, toId: to, amountMinor: amount, currency: currency, date: Date())
    }

    private func byId(_ balances: [Balance]) -> [String: Int64] {
        Dictionary(balances.map { ($0.memberId, $0.netMinor) }, uniquingKeysWith: { a, _ in a })
    }

    @Test("Single payer covering an equal split owes nothing, is owed by everyone else")
    func testSinglePayerEqualSplit() {
        let e = expense(payer: alice.id, amount: 300, splits: [
            ExpenseSplit(memberId: alice.id, amountMinor: 100),
            ExpenseSplit(memberId: bob.id, amountMinor: 100),
            ExpenseSplit(memberId: carol.id, amountMinor: 100),
        ])
        let balances = Balances.compute(members: [alice, bob, carol], expenses: [e], settlements: [])

        #expect(balances.allSatisfy { $0.currency == "USD" })
        #expect(byId(balances)["alice"] == 200)
        #expect(byId(balances)["bob"] == -100)
        #expect(byId(balances)["carol"] == -100)
        #expect(balances.reduce(0) { $0 + $1.netMinor } == 0)
    }

    @Test("A settlement moves balance from the payer toward the recipient")
    func testSettlementMovesBalance() {
        let balances = Balances.compute(
            members: [alice, bob], expenses: [],
            settlements: [settlement(from: bob.id, to: alice.id, amount: 100)]
        )
        #expect(byId(balances)["bob"] == 100)
        #expect(byId(balances)["alice"] == -100)
    }

    @Test("Expenses fully offset by settlements drop out (only nonzero balances are returned)")
    func testZeroBalanceAlreadySettled() {
        let e = expense(payer: alice.id, amount: 200, splits: [
            ExpenseSplit(memberId: alice.id, amountMinor: 100),
            ExpenseSplit(memberId: bob.id, amountMinor: 100),
        ])
        let balances = Balances.compute(
            members: [alice, bob], expenses: [e],
            settlements: [settlement(from: bob.id, to: alice.id, amount: 100)]
        )
        #expect(balances.isEmpty)
    }

    @Test("Empty event history yields no balances at all")
    func testEmptyHistory() {
        #expect(Balances.compute(members: [alice, bob, carol], expenses: [], settlements: []).isEmpty)
    }

    @Test("Computing balances twice from the same input is idempotent")
    func testIdempotency() {
        let e = expense(payer: alice.id, amount: 300, splits: [
            ExpenseSplit(memberId: alice.id, amountMinor: 100),
            ExpenseSplit(memberId: bob.id, amountMinor: 100),
            ExpenseSplit(memberId: carol.id, amountMinor: 100),
        ])
        let members = [alice, bob, carol]
        #expect(
            Balances.compute(members: members, expenses: [e], settlements: [])
                == Balances.compute(members: members, expenses: [e], settlements: [])
        )
    }

    @Test("Within a currency, nonzero balances follow members order")
    func testResultOrderMatchesMembers() {
        let e = expense(payer: carol.id, amount: 300, splits: [
            ExpenseSplit(memberId: alice.id, amountMinor: 100),
            ExpenseSplit(memberId: bob.id, amountMinor: 100),
            ExpenseSplit(memberId: carol.id, amountMinor: 100),
        ])
        let balances = Balances.compute(members: [carol, alice, bob], expenses: [e], settlements: [])
        #expect(balances.map(\.memberId) == ["carol", "alice", "bob"])
    }

    @Test("Two currencies are kept in separate buckets, each summing to zero")
    func testMultiCurrency() {
        let usd = expense(id: "e1", payer: alice.id, amount: 200, currency: "USD", splits: [
            ExpenseSplit(memberId: alice.id, amountMinor: 100),
            ExpenseSplit(memberId: bob.id, amountMinor: 100),
        ])
        let eur = expense(id: "e2", payer: bob.id, amount: 500, currency: "EUR", splits: [
            ExpenseSplit(memberId: alice.id, amountMinor: 250),
            ExpenseSplit(memberId: bob.id, amountMinor: 250),
        ])
        let balances = Balances.compute(members: [alice, bob], expenses: [usd, eur], settlements: [])

        // USD bucket first (first-appearance order), then EUR.
        #expect(balances.map { "\($0.currency):\($0.memberId)=\($0.netMinor)" }
            == ["USD:alice=100", "USD:bob=-100", "EUR:alice=-250", "EUR:bob=250"])

        for currency in ["USD", "EUR"] {
            let sum = balances.filter { $0.currency == currency }.reduce(Int64(0)) { $0 + $1.netMinor }
            #expect(sum == 0)
        }
    }

    // MARK: - headline (FEATURE_BACKLOG.md "Home-screen widget")

    @Test("headline picks the largest-magnitude nonzero balance")
    func testHeadlinePicksLargestMagnitude() {
        let balances = [
            Balance(memberId: "m1", currency: "INR", netMinor: 500),
            Balance(memberId: "m1", currency: "USD", netMinor: -2000),
        ]
        #expect(Balances.headline(balances) == Balance(memberId: "m1", currency: "USD", netMinor: -2000))
    }

    @Test("headline is nil for an empty or all-zero list")
    func testHeadlineNilWhenSettled() {
        #expect(Balances.headline([]) == nil)
        #expect(Balances.headline([Balance(memberId: "m1", currency: "INR", netMinor: 0)]) == nil)
    }

    @Test("headline ignores zero entries alongside a real one")
    func testHeadlineIgnoresZeroEntries() {
        let balances = [
            Balance(memberId: "m1", currency: "INR", netMinor: 0),
            Balance(memberId: "m1", currency: "USD", netMinor: 100),
        ]
        #expect(Balances.headline(balances) == Balance(memberId: "m1", currency: "USD", netMinor: 100))
    }
}

import Testing
@testable import ClanTabKit

@Suite("Simplify")
struct SimplifyTests {
    @Test("A fully-cancelling triangle of debts collapses to zero transactions")
    func testFullyCancellingTriangleCollapses() {
        // A owes B 10, B owes C 10, C owes A 10 -> every net balance is already zero.
        let balances = [
            Balance(memberId: "A", currency: "USD", netMinor: 0),
            Balance(memberId: "B", currency: "USD", netMinor: 0),
            Balance(memberId: "C", currency: "USD", netMinor: 0),
        ]
        let result = Simplify.simplify(balances: balances)
        #expect(result.isEmpty)
    }

    @Test("A triangle with a net imbalance collapses to at most N-1 transactions")
    func testImbalancedTriangleCollapses() {
        // A owes B 30, B owes C 20, C owes A 10 -> nets: A -20, B +10, C +10.
        let balances = [
            Balance(memberId: "A", currency: "USD", netMinor: -20),
            Balance(memberId: "B", currency: "USD", netMinor: 10),
            Balance(memberId: "C", currency: "USD", netMinor: 10),
        ]
        let result = Simplify.simplify(balances: balances)

        #expect(result.count <= 2) // N-1 for 3 nonzero balances
        #expect(applyAndVerifyZeroed(original: balances, result: result))
    }

    @Test("A single payer scenario simplifies to N-1 direct payments to the payer")
    func testSinglePayerSimplifiesToDirectPayments() {
        // Payer fronted for 3 others; each owes the payer 100 directly.
        let balances = [
            Balance(memberId: "payer", currency: "USD", netMinor: 300),
            Balance(memberId: "m1", currency: "USD", netMinor: -100),
            Balance(memberId: "m2", currency: "USD", netMinor: -100),
            Balance(memberId: "m3", currency: "USD", netMinor: -100),
        ]
        let result = Simplify.simplify(balances: balances)

        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.toId == "payer" })
        #expect(applyAndVerifyZeroed(original: balances, result: result))
    }

    @Test("An already-settled group produces zero transactions")
    func testAlreadySettledProducesNoTransactions() {
        let balances = [
            Balance(memberId: "A", currency: "USD", netMinor: 0),
            Balance(memberId: "B", currency: "USD", netMinor: 0),
        ]
        #expect(Simplify.simplify(balances: balances).isEmpty)
    }

    @Test("An empty balance list produces zero transactions")
    func testEmptyBalancesProducesNoTransactions() {
        #expect(Simplify.simplify(balances: []).isEmpty)
    }

    @Test("Running simplify twice on identical balances is idempotent")
    func testIdempotency() {
        let balances = [
            Balance(memberId: "A", currency: "USD", netMinor: -20),
            Balance(memberId: "B", currency: "USD", netMinor: 10),
            Balance(memberId: "C", currency: "USD", netMinor: 10),
        ]
        let first = Simplify.simplify(balances: balances)
        let second = Simplify.simplify(balances: balances)
        #expect(first == second)
    }

    @Test("Each currency is simplified independently and never nets across currencies")
    func testMultiCurrencyIndependence() {
        let balances = [
            Balance(memberId: "A", currency: "USD", netMinor: 300),
            Balance(memberId: "B", currency: "USD", netMinor: -300),
            Balance(memberId: "A", currency: "EUR", netMinor: -100),
            Balance(memberId: "C", currency: "EUR", netMinor: 100),
        ]
        let result = Simplify.simplify(balances: balances)

        #expect(result == [
            SimplifiedSettlement(fromId: "B", toId: "A", amountMinor: 300, currency: "USD"),
            SimplifiedSettlement(fromId: "A", toId: "C", amountMinor: 100, currency: "EUR"),
        ])
    }

    @Test("Random fuzz: every simplification zeroes the group and never exceeds N-1 transactions")
    func testRandomFuzz() {
        var generator = SeededGenerator(seed: 42)

        for _ in 0..<200 {
            let memberCount = Int.random(in: 2...10, using: &generator)
            let balances = randomZeroSumBalances(memberCount: memberCount, generator: &generator)
            let result = Simplify.simplify(balances: balances)

            let nonZeroCount = balances.filter { $0.netMinor != 0 }.count
            #expect(result.count <= max(nonZeroCount - 1, 0))
            #expect(applyAndVerifyZeroed(original: balances, result: result))

            // Sum of all payments made equals the sum of all positive balances.
            let totalPaid = result.reduce(Int64(0)) { $0 + $1.amountMinor }
            let totalCredit = balances.reduce(Int64(0)) { $0 + max($1.netMinor, 0) }
            #expect(totalPaid == totalCredit)
        }
    }
}

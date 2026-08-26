import Testing
import Foundation
@testable import SquareKit

@Suite("Balances")
struct BalancesTests {
    let alice = Member(id: "alice", displayName: "Alice")
    let bob = Member(id: "bob", displayName: "Bob")
    let carol = Member(id: "carol", displayName: "Carol")

    @Test("Single payer covering an equal split owes nothing, is owed by everyone else")
    func testSinglePayerEqualSplit() {
        // Alice pays 300 for a meal shared equally three ways (100 each).
        let expense = Expense(
            id: "e1",
            payerId: alice.id,
            amountMinor: 300,
            description: "Dinner",
            date: Date(),
            splitType: .equal,
            splits: [
                ExpenseSplit(memberId: alice.id, amountMinor: 100),
                ExpenseSplit(memberId: bob.id, amountMinor: 100),
                ExpenseSplit(memberId: carol.id, amountMinor: 100),
            ]
        )

        let balances = Balances.compute(members: [alice, bob, carol], expenses: [expense], settlements: [])
        let byId = Dictionary(uniqueKeysWithValues: balances.map { ($0.memberId, $0.netMinor) })

        #expect(byId["alice"] == 200)
        #expect(byId["bob"] == -100)
        #expect(byId["carol"] == -100)
        #expect(balances.reduce(0) { $0 + $1.netMinor } == 0)
    }

    @Test("A settlement moves balance from the payer toward the recipient")
    func testSettlementMovesBalance() {
        let settlement = Settlement(id: "s1", fromId: bob.id, toId: alice.id, amountMinor: 100, date: Date())
        let balances = Balances.compute(members: [alice, bob], expenses: [], settlements: [settlement])
        let byId = Dictionary(uniqueKeysWithValues: balances.map { ($0.memberId, $0.netMinor) })

        #expect(byId["bob"] == 100)
        #expect(byId["alice"] == -100)
    }

    @Test("Expenses fully offset by settlements produce an already-settled zero state")
    func testZeroBalanceAlreadySettled() {
        let expense = Expense(
            id: "e1",
            payerId: alice.id,
            amountMinor: 200,
            description: "Groceries",
            date: Date(),
            splitType: .equal,
            splits: [
                ExpenseSplit(memberId: alice.id, amountMinor: 100),
                ExpenseSplit(memberId: bob.id, amountMinor: 100),
            ]
        )
        let settlement = Settlement(id: "s1", fromId: bob.id, toId: alice.id, amountMinor: 100, date: Date())

        let balances = Balances.compute(members: [alice, bob], expenses: [expense], settlements: [settlement])
        #expect(balances.allSatisfy { $0.netMinor == 0 })
    }

    @Test("Empty event history yields zero balances for every member")
    func testEmptyHistory() {
        let balances = Balances.compute(members: [alice, bob, carol], expenses: [], settlements: [])
        #expect(balances.count == 3)
        #expect(balances.allSatisfy { $0.netMinor == 0 })
    }

    @Test("Computing balances twice from the same input is idempotent")
    func testIdempotency() {
        let expense = Expense(
            id: "e1",
            payerId: alice.id,
            amountMinor: 300,
            description: "Dinner",
            date: Date(),
            splitType: .equal,
            splits: [
                ExpenseSplit(memberId: alice.id, amountMinor: 100),
                ExpenseSplit(memberId: bob.id, amountMinor: 100),
                ExpenseSplit(memberId: carol.id, amountMinor: 100),
            ]
        )
        let members = [alice, bob, carol]
        let first = Balances.compute(members: members, expenses: [expense], settlements: [])
        let second = Balances.compute(members: members, expenses: [expense], settlements: [])
        #expect(first == second)
    }

    @Test("Result order and completeness always matches the members array")
    func testResultOrderMatchesMembers() {
        let balances = Balances.compute(members: [carol, alice, bob], expenses: [], settlements: [])
        #expect(balances.map(\.memberId) == ["carol", "alice", "bob"])
    }
}

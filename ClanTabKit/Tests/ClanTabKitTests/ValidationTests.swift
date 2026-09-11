import Testing
@testable import ClanTabKit

@Suite("Validation")
struct ValidationTests {
    @Test("Splits summing exactly to the expense amount pass validation")
    func testValidSplitsSumPasses() throws {
        let splits = [
            ExpenseSplit(memberId: "a", amountMinor: 50),
            ExpenseSplit(memberId: "b", amountMinor: 50),
        ]
        try Validation.validateSplitsSum(amountMinor: 100, splits: splits)
    }

    @Test("Splits that don't sum to the expense amount throw splitMismatch")
    func testMismatchedSplitsThrow() {
        let splits = [
            ExpenseSplit(memberId: "a", amountMinor: 40),
            ExpenseSplit(memberId: "b", amountMinor: 50),
        ]
        #expect(throws: ValidationError.splitMismatch(expected: 100, actual: 90)) {
            try Validation.validateSplitsSum(amountMinor: 100, splits: splits)
        }
    }

    @Test("An empty splits array throws emptySplits")
    func testEmptySplitsThrows() {
        #expect(throws: ValidationError.emptySplits) {
            try Validation.validateSplitsSum(amountMinor: 100, splits: [])
        }
    }

    @Test("A member id outside the group throws unknownMember")
    func testUnknownMemberThrows() {
        #expect(throws: ValidationError.unknownMember("ghost")) {
            try Validation.validateMembersExist(memberIds: ["a", "ghost"], validMemberIds: ["a", "b"])
        }
    }

    @Test("All members present in the group passes validation")
    func testKnownMembersPass() throws {
        try Validation.validateMembersExist(memberIds: ["a", "b"], validMemberIds: ["a", "b", "c"])
    }

    @Test("Zero and negative amounts throw invalidAmount", arguments: [0, -1, -500])
    func testNonPositiveAmountThrows(amount: Int64) {
        #expect(throws: ValidationError.invalidAmount(amount)) {
            try Validation.validatePositiveAmount(amount)
        }
    }

    @Test("A positive amount passes validation")
    func testPositiveAmountPasses() throws {
        try Validation.validatePositiveAmount(1)
    }

    @Test("100 split 3 ways deterministically allocates the remainder to the payer")
    func testRemainderAllocation100SplitThreeWays() throws {
        let splits = Validation.equalSplit(amountMinor: 100, memberIds: ["payer", "b", "c"], remainderRecipient: "payer")

        let byId = Dictionary(uniqueKeysWithValues: splits.map { ($0.memberId, $0.amountMinor) })
        #expect(byId["payer"] == 34)
        #expect(byId["b"] == 33)
        #expect(byId["c"] == 33)

        // The invariant that actually matters: the sum always matches exactly.
        try Validation.validateSplitsSum(amountMinor: 100, splits: splits)
    }

    @Test("Equal split with no remainder divides evenly with no adjustment")
    func testEvenSplitNoRemainder() throws {
        let splits = Validation.equalSplit(amountMinor: 300, memberIds: ["a", "b", "c"], remainderRecipient: "a")
        #expect(splits.allSatisfy { $0.amountMinor == 100 })
        try Validation.validateSplitsSum(amountMinor: 300, splits: splits)
    }

    @Test("Equal split falls back to the first member when the recipient isn't in the group")
    func testRemainderFallsBackWhenRecipientMissing() throws {
        let splits = Validation.equalSplit(amountMinor: 100, memberIds: ["a", "b", "c"], remainderRecipient: "nobody")
        let byId = Dictionary(uniqueKeysWithValues: splits.map { ($0.memberId, $0.amountMinor) })
        #expect(byId["a"] == 34)
        try Validation.validateSplitsSum(amountMinor: 100, splits: splits)
    }

    @Test("Random fuzz: equal splits never gain or lose a minor unit across many divisors")
    func testEqualSplitFuzzNeverDriftsSum() throws {
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<200 {
            let memberCount = Int.random(in: 1...12, using: &generator)
            let amount = Int64.random(in: 1...1_000_000, using: &generator)
            let memberIds = (0..<memberCount).map { "m\($0)" }
            let splits = Validation.equalSplit(amountMinor: amount, memberIds: memberIds, remainderRecipient: memberIds[0])
            try Validation.validateSplitsSum(amountMinor: amount, splits: splits)
        }
    }

    @Test("50/30/20 percentage split resolves to exact minor-unit shares")
    func testPercentageSplitBasic() throws {
        let splits = Validation.percentageSplit(
            amountMinor: 10_000,
            weights: [("a", 50), ("b", 30), ("c", 20)],
            remainderRecipient: "a"
        )
        let byId = Dictionary(uniqueKeysWithValues: splits.map { ($0.memberId, $0.amountMinor) })
        #expect(byId["a"] == 5_000)
        #expect(byId["b"] == 3_000)
        #expect(byId["c"] == 2_000)
        try Validation.validateSplitsSum(amountMinor: 10_000, splits: splits)
    }

    @Test("A rounding remainder from percentages lands on the payer")
    func testPercentageSplitRemainderToPayer() throws {
        // Three equal thirds of 1000: floor gives 333/333/333 = 999, 1 left over,
        // which must land on the remainder recipient ("payer").
        let splits = Validation.percentageSplit(
            amountMinor: 1_000,
            weights: [("b", 1), ("payer", 1), ("c", 1)],
            remainderRecipient: "payer"
        )
        let byId = Dictionary(uniqueKeysWithValues: splits.map { ($0.memberId, $0.amountMinor) })
        #expect(byId["payer"] == 334)
        #expect(byId["b"] == 333)
        #expect(byId["c"] == 333)
        try Validation.validateSplitsSum(amountMinor: 1_000, splits: splits)
    }

    @Test("A zero-weight member is included with a zero share")
    func testPercentageSplitZeroWeight() throws {
        let splits = Validation.percentageSplit(
            amountMinor: 900,
            weights: [("a", 100), ("b", 0)],
            remainderRecipient: "a"
        )
        let byId = Dictionary(uniqueKeysWithValues: splits.map { ($0.memberId, $0.amountMinor) })
        #expect(byId["a"] == 900)
        #expect(byId["b"] == 0)
        try Validation.validateSplitsSum(amountMinor: 900, splits: splits)
    }

    @Test("Weights need not sum to 100 — the split is proportional to their total")
    func testPercentageSplitProportionalToWeightTotal() throws {
        let splits = Validation.percentageSplit(
            amountMinor: 1_200,
            weights: [("a", 1), ("b", 2), ("c", 3)],
            remainderRecipient: "a"
        )
        let byId = Dictionary(uniqueKeysWithValues: splits.map { ($0.memberId, $0.amountMinor) })
        #expect(byId["a"] == 200)
        #expect(byId["b"] == 400)
        #expect(byId["c"] == 600)
        try Validation.validateSplitsSum(amountMinor: 1_200, splits: splits)
    }

    @Test("Random fuzz: percentage splits never gain or lose a minor unit")
    func testPercentageSplitFuzzNeverDriftsSum() throws {
        var generator = SeededGenerator(seed: 11)
        for _ in 0..<200 {
            let memberCount = Int.random(in: 1...12, using: &generator)
            let amount = Int64.random(in: 1...1_000_000, using: &generator)
            let weights = (0..<memberCount).map { (memberId: "m\($0)", weight: Int.random(in: 0...100, using: &generator)) }
            guard weights.contains(where: { $0.weight > 0 }) else { continue }
            let splits = Validation.percentageSplit(amountMinor: amount, weights: weights, remainderRecipient: "m0")
            try Validation.validateSplitsSum(amountMinor: amount, splits: splits)
        }
    }

    // MARK: - Itemized split

    private func item(_ id: String, _ amount: Int64, _ people: [String]) -> LineItem {
        LineItem(id: id, name: id, amountMinor: amount, participantIds: people)
    }

    @Test("Itemized: each line splits equally among its own people, summed per member")
    func testItemizedSplitBasic() throws {
        // Pizza 900 shared a/b/c (300 each); Beer 400 shared a/b (200 each).
        let items = [item("pizza", 900, ["a", "b", "c"]), item("beer", 400, ["a", "b"])]
        let splits = Validation.itemizedSplit(items: items, remainderRecipient: "a")
        let byId = Dictionary(uniqueKeysWithValues: splits.map { ($0.memberId, $0.amountMinor) })
        #expect(byId["a"] == 500)
        #expect(byId["b"] == 500)
        #expect(byId["c"] == 300)
        try Validation.validateSplitsSum(amountMinor: 1300, splits: splits)
    }

    @Test("Itemized: a per-item rounding remainder lands on the payer when they share the item")
    func testItemizedSplitRemainderToPayer() throws {
        // 100 split 3 ways → 34/33/33, remainder to the payer "b".
        let splits = Validation.itemizedSplit(items: [item("x", 100, ["a", "b", "c"])], remainderRecipient: "b")
        let byId = Dictionary(uniqueKeysWithValues: splits.map { ($0.memberId, $0.amountMinor) })
        #expect(byId["b"] == 34)
        #expect(byId["a"] == 33)
        #expect(byId["c"] == 33)
    }

    @Test("Itemized: members on no item are left out entirely")
    func testItemizedSplitOmitsUninvolved() {
        let splits = Validation.itemizedSplit(items: [item("x", 100, ["a", "b"])], remainderRecipient: "a")
        #expect(Set(splits.map(\.memberId)) == ["a", "b"])
    }

    @Test("Itemized: member order follows first appearance across items")
    func testItemizedSplitOrder() {
        let items = [item("x", 100, ["c", "a"]), item("y", 100, ["a", "b"])]
        let splits = Validation.itemizedSplit(items: items, remainderRecipient: "a")
        #expect(splits.map(\.memberId) == ["c", "a", "b"])
    }

    @Test("validateItems accepts a well-formed itemization")
    func testValidateItemsPasses() throws {
        let items = [item("x", 600, ["a", "b"]), item("y", 400, ["a"])]
        try Validation.validateItems(amountMinor: 1000, items: items, validMemberIds: ["a", "b", "c"])
    }

    @Test("validateItems: no items throws emptyItems")
    func testValidateItemsEmpty() {
        #expect(throws: ValidationError.emptyItems) {
            try Validation.validateItems(amountMinor: 0, items: [], validMemberIds: ["a"])
        }
    }

    @Test("validateItems: an item with no participants throws")
    func testValidateItemsNoParticipants() {
        #expect(throws: ValidationError.itemWithoutParticipants) {
            try Validation.validateItems(amountMinor: 100, items: [item("x", 100, [])], validMemberIds: ["a"])
        }
    }

    @Test("validateItems: an unknown participant throws unknownMember")
    func testValidateItemsUnknownMember() {
        #expect(throws: ValidationError.unknownMember("ghost")) {
            try Validation.validateItems(amountMinor: 100, items: [item("x", 100, ["a", "ghost"])], validMemberIds: ["a"])
        }
    }

    @Test("validateItems: items not summing to the amount throw itemSumMismatch")
    func testValidateItemsSumMismatch() {
        #expect(throws: ValidationError.itemSumMismatch(expected: 1000, actual: 900)) {
            try Validation.validateItems(
                amountMinor: 1000,
                items: [item("x", 600, ["a"]), item("y", 300, ["a"])],
                validMemberIds: ["a"]
            )
        }
    }

    @Test("validateItems: a non-positive item amount throws invalidAmount")
    func testValidateItemsNonPositive() {
        #expect(throws: ValidationError.invalidAmount(0)) {
            try Validation.validateItems(amountMinor: 100, items: [item("x", 0, ["a"])], validMemberIds: ["a"])
        }
    }

    @Test("Random fuzz: a validated itemization always resolves to splits summing to the amount")
    func testItemizedSplitFuzzNeverDriftsSum() throws {
        var generator = SeededGenerator(seed: 23)
        for _ in 0..<200 {
            let memberCount = Int.random(in: 1...8, using: &generator)
            let members = (0..<memberCount).map { "m\($0)" }
            let itemCount = Int.random(in: 1...6, using: &generator)
            var items: [LineItem] = []
            var total: Int64 = 0
            for i in 0..<itemCount {
                let amount = Int64.random(in: 1...200_000, using: &generator)
                let people = members.filter { _ in Bool.random(using: &generator) }
                let participants = people.isEmpty ? [members[0]] : people
                items.append(LineItem(id: "i\(i)", name: "i\(i)", amountMinor: amount, participantIds: participants))
                total += amount
            }
            try Validation.validateItems(amountMinor: total, items: items, validMemberIds: Set(members))
            let splits = Validation.itemizedSplit(items: items, remainderRecipient: members[0])
            try Validation.validateSplitsSum(amountMinor: total, splits: splits)
        }
    }

    // MARK: - Shares split

    @Test("Shares: 4:2:1:3 divides the amount by the weight total")
    func testSharesSplitBasic() throws {
        let splits = Validation.sharesSplit(
            amountMinor: 1_000,
            weights: [("a", 4), ("b", 2), ("c", 1), ("d", 3)],
            remainderRecipient: "a"
        )
        let byId = Dictionary(uniqueKeysWithValues: splits.map { ($0.memberId, $0.amountMinor) })
        #expect(byId["a"] == 400)
        #expect(byId["b"] == 200)
        #expect(byId["c"] == 100)
        #expect(byId["d"] == 300)
        try Validation.validateSplitsSum(amountMinor: 1_000, splits: splits)
    }

    @Test("Shares: an indivisible amount nudges the remainder onto the payer")
    func testSharesSplitRemainder() throws {
        let splits = Validation.sharesSplit(
            amountMinor: 100,
            weights: [("a", 1), ("b", 1), ("c", 1)],
            remainderRecipient: "b"
        )
        let byId = Dictionary(uniqueKeysWithValues: splits.map { ($0.memberId, $0.amountMinor) })
        #expect(byId["b"] == 34)
        #expect(byId["a"] == 33)
        #expect(byId["c"] == 33)
    }

    @Test("validateShares accepts non-negative weights with a positive total")
    func testValidateSharesOK() throws {
        try Validation.validateShares(
            weights: [ShareWeight(memberId: "a", weight: 2), ShareWeight(memberId: "b", weight: 0)],
            validMemberIds: ["a", "b"]
        )
    }

    @Test("validateShares: no weights throws emptyShares")
    func testValidateSharesEmpty() {
        #expect(throws: ValidationError.emptyShares) {
            try Validation.validateShares(weights: [], validMemberIds: ["a"])
        }
    }

    @Test("validateShares: all-zero weights throw invalidShareWeight")
    func testValidateSharesAllZero() {
        #expect(throws: ValidationError.invalidShareWeight) {
            try Validation.validateShares(
                weights: [ShareWeight(memberId: "a", weight: 0)],
                validMemberIds: ["a"]
            )
        }
    }

    @Test("validateShares: a negative weight throws invalidShareWeight")
    func testValidateSharesNegative() {
        #expect(throws: ValidationError.invalidShareWeight) {
            try Validation.validateShares(
                weights: [ShareWeight(memberId: "a", weight: -1), ShareWeight(memberId: "b", weight: 2)],
                validMemberIds: ["a", "b"]
            )
        }
    }

    @Test("validateShares: an unknown member throws unknownMember")
    func testValidateSharesUnknownMember() {
        #expect(throws: ValidationError.unknownMember("ghost")) {
            try Validation.validateShares(
                weights: [ShareWeight(memberId: "ghost", weight: 1)],
                validMemberIds: ["a"]
            )
        }
    }

    @Test("Random fuzz: a validated shares split always sums to the amount")
    func testSharesSplitFuzzNeverDriftsSum() throws {
        var generator = SeededGenerator(seed: 41)
        for _ in 0..<200 {
            let memberCount = Int.random(in: 1...12, using: &generator)
            let amount = Int64.random(in: 1...1_000_000, using: &generator)
            let weights = (0..<memberCount).map { (memberId: "m\($0)", weight: Int.random(in: 0...20, using: &generator)) }
            guard weights.contains(where: { $0.weight > 0 }) else { continue }
            let splits = Validation.sharesSplit(amountMinor: amount, weights: weights, remainderRecipient: "m0")
            try Validation.validateSplitsSum(amountMinor: amount, splits: splits)
        }
    }

    // MARK: - Payers (CHECKLIST.md "Multiple payers on one expense")

    @Test("validatePayersSum accepts payers summing exactly to the amount")
    func testValidatePayersSumOK() throws {
        try Validation.validatePayersSum(
            amountMinor: 1_000,
            payers: [ExpensePayment(memberId: "a", amountMinor: 700), ExpensePayment(memberId: "b", amountMinor: 300)]
        )
    }

    @Test("validatePayersSum: no payers throws emptyPayers")
    func testValidatePayersSumEmpty() {
        #expect(throws: ValidationError.emptyPayers) {
            try Validation.validatePayersSum(amountMinor: 100, payers: [])
        }
    }

    @Test("validatePayersSum: a mismatched total throws payerSumMismatch")
    func testValidatePayersSumMismatch() {
        #expect(throws: ValidationError.payerSumMismatch(expected: 1_000, actual: 900)) {
            try Validation.validatePayersSum(
                amountMinor: 1_000,
                payers: [ExpensePayment(memberId: "a", amountMinor: 900)]
            )
        }
    }
}

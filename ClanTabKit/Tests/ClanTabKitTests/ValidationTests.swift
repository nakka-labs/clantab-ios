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
}

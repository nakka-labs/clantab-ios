import Foundation
@testable import ClanTabKit

/// Deterministic RNG (xorshift64) so fuzz tests are reproducible across runs and CI
/// platforms — no dependency on Swift's default (unseedable) `SystemRandomNumberGenerator`.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xdead_beef : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Applies a simplified settlement plan on top of the original balances (the same
/// effect a `Settlement` has in `Balances.compute`: `fromId` credited, `toId`
/// debited) and asserts every member lands at exactly zero — i.e. the plan actually
/// settles the group, regardless of how many transactions it took.
func applyAndVerifyZeroed(
    original: [Balance],
    result: [SimplifiedSettlement]
) -> Bool {
    var net: [String: Int64] = [:]
    for balance in original {
        net[balance.memberId] = balance.netMinor
    }
    for transaction in result {
        guard transaction.amountMinor > 0 else { return false }
        net[transaction.fromId, default: 0] += transaction.amountMinor
        net[transaction.toId, default: 0] -= transaction.amountMinor
    }
    return net.values.allSatisfy { $0 == 0 }
}

/// Generates a set of member balances that sum to exactly zero, using a seeded RNG.
func randomZeroSumBalances(memberCount: Int, generator: inout SeededGenerator) -> [Balance] {
    precondition(memberCount >= 2)
    var amounts: [Int64] = []
    var runningSum: Int64 = 0
    for _ in 0..<(memberCount - 1) {
        let amount = Int64.random(in: -5_000...5_000, using: &generator)
        amounts.append(amount)
        runningSum += amount
    }
    amounts.append(-runningSum)

    return (0..<memberCount).map { index in
        Balance(memberId: "member-\(index)", currency: "USD", netMinor: amounts[index])
    }
}

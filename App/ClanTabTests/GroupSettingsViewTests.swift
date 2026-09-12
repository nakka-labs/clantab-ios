import XCTest
import ClanTabKit
@testable import ClanTab

/// `GroupSettingsView.isRemovable` (`CHECKLIST.md` UX audit [21]) — the
/// client-side half of "Remove Member fails silently after the swipe":
/// don't even offer the swipe action for a case we can already tell will
/// be rejected.
final class GroupSettingsViewTests: XCTestCase {

    private func member(_ id: String) -> Member {
        Member(id: id, displayName: id)
    }

    private func expense(payerId: String, splitMemberIds: [String]) -> Expense {
        Expense(
            id: "e-\(payerId)", payerId: payerId, amountMinor: 1000, currency: "INR",
            description: "Test", date: Date(), splitType: .equal,
            splits: splitMemberIds.map { ExpenseSplit(memberId: $0, amountMinor: 1000 / Int64(splitMemberIds.count)) }
        )
    }

    private func settlement(from: String, to: String) -> Settlement {
        Settlement(id: "s-\(from)-\(to)", fromId: from, toId: to, amountMinor: 500, currency: "INR", date: Date())
    }

    func testRemovableWithNoActivity() {
        XCTAssertTrue(GroupSettingsView.isRemovable(member("m1"), myMemberId: "m2", expenses: [], settlements: []))
    }

    func testNotRemovableWhenItsYourOwnClaim() {
        XCTAssertFalse(GroupSettingsView.isRemovable(member("m1"), myMemberId: "m1", expenses: [], settlements: []))
    }

    func testNotRemovableAsAPayer() {
        let expenses = [expense(payerId: "m1", splitMemberIds: ["m2"])]
        XCTAssertFalse(GroupSettingsView.isRemovable(member("m1"), myMemberId: nil, expenses: expenses, settlements: []))
    }

    func testNotRemovableAsASplitParticipant() {
        let expenses = [expense(payerId: "m2", splitMemberIds: ["m1", "m2"])]
        XCTAssertFalse(GroupSettingsView.isRemovable(member("m1"), myMemberId: nil, expenses: expenses, settlements: []))
    }

    func testNotRemovableAsANonPrimaryPayer() {
        let expense = Expense(
            id: "e1", payers: [ExpensePayment(memberId: "m2", amountMinor: 500), ExpensePayment(memberId: "m1", amountMinor: 500)],
            amountMinor: 1000, currency: "INR", description: "Split bill", date: Date(),
            splitType: .equal, splits: [ExpenseSplit(memberId: "m1", amountMinor: 500), ExpenseSplit(memberId: "m2", amountMinor: 500)]
        )
        XCTAssertFalse(GroupSettingsView.isRemovable(member("m1"), myMemberId: nil, expenses: [expense], settlements: []))
    }

    func testNotRemovableOnASettlement() {
        let settlements = [settlement(from: "m1", to: "m2")]
        XCTAssertFalse(GroupSettingsView.isRemovable(member("m1"), myMemberId: nil, expenses: [], settlements: settlements))
    }

    func testRemovableWhenOnlyOtherMembersHaveActivity() {
        let expenses = [expense(payerId: "m2", splitMemberIds: ["m2", "m3"])]
        let settlements = [settlement(from: "m2", to: "m3")]
        XCTAssertTrue(GroupSettingsView.isRemovable(member("m1"), myMemberId: nil, expenses: expenses, settlements: settlements))
    }
}

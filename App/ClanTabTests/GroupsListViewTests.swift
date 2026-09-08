import XCTest
import ClanTabKit
@testable import ClanTab

@MainActor
final class GroupsListViewTests: XCTestCase {

    private func group(myBalances: [Balance]?) -> KnownGroup {
        KnownGroup(groupId: "g1", name: "Flatmates", lastOpenedAt: Date(), myBalances: myBalances)
    }

    private func named(_ name: String) -> KnownGroup {
        KnownGroup(groupId: "g1", name: name, lastOpenedAt: Date())
    }

    // MARK: - initial(for:)

    func testInitialIsTheFirstLetterUppercased() {
        XCTAssertEqual(GroupsListView.initial(for: named("flatmates")), "F")
    }

    func testInitialSkipsLeadingEmoji() {
        XCTAssertEqual(GroupsListView.initial(for: named("🏝️ Bali trip")), "B")
    }

    func testInitialSkipsLeadingDigits() {
        XCTAssertEqual(GroupsListView.initial(for: named("42 nomads")), "N")
    }

    func testInitialFallsBackToHashForEmojiOnlyName() {
        XCTAssertEqual(GroupsListView.initial(for: named("🎉🎊")), "#")
    }

    func testInitialFallsBackToHashForSymbolOnlyName() {
        XCTAssertEqual(GroupsListView.initial(for: named("!!!")), "#")
    }

    func testInitialFallsBackToHashForEmptyName() {
        XCTAssertEqual(GroupsListView.initial(for: named("")), "#")
    }

    func testNilUntilFetched() {
        XCTAssertNil(GroupsListView.balanceLine(for: group(myBalances: nil)))
    }

    func testSettledUpWhenFetchedAndEmpty() {
        XCTAssertEqual(GroupsListView.balanceLine(for: group(myBalances: [])), "Settled up")
    }

    func testYouOwe() {
        let line = GroupsListView.balanceLine(for: group(myBalances: [Balance(memberId: "me", currency: "INR", netMinor: -50000)]))
        XCTAssertEqual(line, "You owe ₹500") // round amount → no trailing .00
    }

    func testYoureOwed() {
        let line = GroupsListView.balanceLine(for: group(myBalances: [Balance(memberId: "me", currency: "INR", netMinor: 12550)]))
        XCTAssertEqual(line, "You're owed ₹125.50")
    }

    func testPicksTheLargestMagnitudeCurrency() {
        let line = GroupsListView.balanceLine(for: group(myBalances: [
            Balance(memberId: "me", currency: "INR", netMinor: 100),
            Balance(memberId: "me", currency: "USD", netMinor: -2000),
        ]))
        XCTAssertEqual(line, "You owe $20")
    }
}

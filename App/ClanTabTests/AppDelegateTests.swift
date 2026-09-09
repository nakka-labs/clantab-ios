import XCTest
import ClanTabKit
@testable import ClanTab

@MainActor
final class AppDelegateTests: XCTestCase {

    // MARK: - applyCarriedBalance (CHECKLIST.md "iOS: push handler writes the carried balance")

    private func delegate(with groups: [KnownGroup]) -> (AppDelegate, InMemoryKnownGroupsStore) {
        let store = InMemoryKnownGroupsStore(groups)
        let appDelegate = AppDelegate()
        appDelegate.knownGroups = store
        return (appDelegate, store)
    }

    private func push(groupId: String, currency: String, netMinor: String) -> [AnyHashable: Any] {
        ["groupId": groupId, "kind": "expense", "balanceCurrency": currency, "balanceNetMinor": netMinor]
    }

    func testWritesTheCarriedBalanceIntoAKnownGroupsCache() {
        let (appDelegate, store) = delegate(with: [
            KnownGroup(groupId: "g1", name: "Trip", lastOpenedAt: .now),
        ])

        let applied = appDelegate.applyCarriedBalance(from: push(groupId: "g1", currency: "INR", netMinor: "-2500"))

        XCTAssertTrue(applied)
        XCTAssertEqual(store.all().first?.myBalances, [Balance(memberId: "", currency: "INR", netMinor: -2500)])
    }

    func testMergesWithoutClobberingOtherCurrencies() {
        var group = KnownGroup(groupId: "g1", name: "Trip", lastOpenedAt: .now)
        group.myBalances = [
            Balance(memberId: "me", currency: "INR", netMinor: -500),
            Balance(memberId: "me", currency: "USD", netMinor: 200),
        ]
        let (appDelegate, store) = delegate(with: [group])

        appDelegate.applyCarriedBalance(from: push(groupId: "g1", currency: "USD", netMinor: "900"))

        XCTAssertEqual(store.all().first?.myBalances, [
            Balance(memberId: "me", currency: "INR", netMinor: -500),
            Balance(memberId: "me", currency: "USD", netMinor: 900),
        ])
    }

    func testIsANoOpForAnUnknownGroup() {
        let (appDelegate, store) = delegate(with: [
            KnownGroup(groupId: "g1", name: "Trip", lastOpenedAt: .now),
        ])

        let applied = appDelegate.applyCarriedBalance(from: push(groupId: "other", currency: "INR", netMinor: "100"))

        XCTAssertFalse(applied)
        XCTAssertNil(store.all().first?.myBalances)
    }

    func testIsANoOpWhenThePayloadCarriesNoBalance() {
        let (appDelegate, store) = delegate(with: [
            KnownGroup(groupId: "g1", name: "Trip", lastOpenedAt: .now),
        ])

        let applied = appDelegate.applyCarriedBalance(from: ["groupId": "g1", "kind": "settlement"])

        XCTAssertFalse(applied)
        XCTAssertNil(store.all().first?.myBalances)
    }

    func testIsANoOpBeforeTheStoreIsWired() {
        let appDelegate = AppDelegate()
        XCTAssertFalse(appDelegate.applyCarriedBalance(from: push(groupId: "g1", currency: "INR", netMinor: "100")))
    }
}

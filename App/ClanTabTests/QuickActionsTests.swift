import XCTest
import UIKit
import ClanTabKit
@testable import ClanTab

/// The Home Screen quick action (`CHECKLIST.md` "Home Screen quick action").
final class QuickActionsTests: XCTestCase {

    private func group(_ id: String, name: String, opened: TimeInterval) -> KnownGroup {
        KnownGroup(groupId: id, name: name, lastOpenedAt: Date(timeIntervalSince1970: opened))
    }

    func testPrimaryGroupIsTheMostRecentNamedOne() {
        // `KnownGroupsStoring.all()` hands them back most-recent-first.
        let groups = [
            group("g2", name: "Flatmates", opened: 200),
            group("g1", name: "Goa Trip", opened: 100),
        ]
        XCTAssertEqual(QuickActions.primaryGroup(groups)?.groupId, "g2")
    }

    func testPrimaryGroupSkipsUnnamedGroups() {
        let groups = [
            group("g3", name: "", opened: 300),          // joined, never opened
            group("g1", name: "Goa Trip", opened: 100),
        ]
        XCTAssertEqual(QuickActions.primaryGroup(groups)?.groupId, "g1")
    }

    func testNoPrimaryGroupWhenNoneAreNamed() {
        XCTAssertNil(QuickActions.primaryGroup([]))
        XCTAssertNil(QuickActions.primaryGroup([group("g3", name: "", opened: 1)]))
    }

    func testShortcutItemCarriesTheGroupNameAndId() {
        let item = QuickActions.shortcutItem([group("g1", name: "Goa Trip", opened: 1)])
        XCTAssertEqual(item?.type, QuickActions.addExpenseType)
        XCTAssertEqual(item?.localizedSubtitle, "Goa Trip")
        XCTAssertEqual(item.flatMap(QuickActions.targetGroupId(from:)), "g1")
    }

    func testShortcutItemIsNilWithoutAGroup() {
        XCTAssertNil(QuickActions.shortcutItem([]))
    }

    func testTargetGroupIdRejectsAForeignShortcutType() {
        let foreign = UIApplicationShortcutItem(
            type: "com.example.other", localizedTitle: "x",
            localizedSubtitle: nil, icon: nil, userInfo: [QuickActions.groupIdKey: "g1" as NSString]
        )
        XCTAssertNil(QuickActions.targetGroupId(from: foreign))
    }
}

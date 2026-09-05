import XCTest
import ClanTabKit
@testable import ClanTab

final class AddExpenseIntentLogicTests: XCTestCase {

    func testMinorUnitsRoundsToTheNearestPaisa() {
        XCTAssertEqual(AddExpenseIntentLogic.minorUnits(from: 500), 50000)
        XCTAssertEqual(AddExpenseIntentLogic.minorUnits(from: 12.5), 1250)
        XCTAssertEqual(AddExpenseIntentLogic.minorUnits(from: 0.01), 1)
    }

    func testBuildRequestSplitsEquallyAmongCurrentMembers() {
        let request = AddExpenseIntentLogic.buildRequest(
            payerId: "m1",
            memberIds: ["m1", "m2", "m3"],
            amountMinor: 100,
            currency: "INR",
            description: "Dinner",
            date: Date(timeIntervalSince1970: 0),
            id: "fixed-id"
        )

        XCTAssertEqual(request.id, "fixed-id")
        XCTAssertEqual(request.payerId, "m1")
        XCTAssertEqual(request.amountMinor, 100)
        XCTAssertEqual(request.currency, "INR")
        XCTAssertEqual(request.description, "Dinner")
        XCTAssertEqual(request.splitType, .equal)
        // 100 / 3 = 33 each, remainder 1 to the payer (m1).
        XCTAssertEqual(request.splits.sorted { $0.memberId < $1.memberId }, [
            ExpenseSplit(memberId: "m1", amountMinor: 34),
            ExpenseSplit(memberId: "m2", amountMinor: 33),
            ExpenseSplit(memberId: "m3", amountMinor: 33),
        ])
    }

    func testBuildRequestFallsBackToAPlaceholderDescription() {
        let blank = AddExpenseIntentLogic.buildRequest(
            payerId: "m1", memberIds: ["m1"], amountMinor: 100, currency: "INR",
            description: "   ", date: Date(), id: "id"
        )
        XCTAssertEqual(blank.description, "Expense")

        let trimmed = AddExpenseIntentLogic.buildRequest(
            payerId: "m1", memberIds: ["m1"], amountMinor: 100, currency: "INR",
            description: "  Groceries  ", date: Date(), id: "id"
        )
        XCTAssertEqual(trimmed.description, "Groceries")
    }
}

final class GroupEntityQueryTests: XCTestCase {

    func testNamedGroupsExcludesGroupsWithNoNameYet() {
        let groups = [
            KnownGroup(groupId: "g1", name: "Flatmates", lastOpenedAt: Date()),
            KnownGroup(groupId: "g2", name: "", lastOpenedAt: Date()), // never opened yet
            KnownGroup(groupId: "g3", name: "Goa Trip", lastOpenedAt: Date()),
        ]

        let entities = GroupEntityQuery.namedGroups(groups)

        XCTAssertEqual(entities.map(\.id), ["g1", "g3"])
        XCTAssertEqual(entities.map(\.name), ["Flatmates", "Goa Trip"])
    }

    func testNamedGroupsIsEmptyForNoKnownGroups() {
        XCTAssertTrue(GroupEntityQuery.namedGroups([]).isEmpty)
    }
}

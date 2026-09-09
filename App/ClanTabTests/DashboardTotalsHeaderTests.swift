import XCTest
import ClanTabKit
@testable import ClanTab

final class DashboardTotalsHeaderTests: XCTestCase {

    // MARK: - line(for:) — CHECKLIST.md "Currency-bucketed totals header"

    func testNegativeBucketReadsAsYouOwe() {
        let line = DashboardTotalsHeader.line(for: .init(currency: "INR", netMinor: -50000))
        XCTAssertEqual(line, "You owe ₹500")
    }

    func testLargeAmountGroupsByThrees() {
        let line = DashboardTotalsHeader.line(for: .init(currency: "INR", netMinor: -1_00_00_000))
        XCTAssertEqual(line, "You owe ₹100,000")
    }

    func testPositiveBucketReadsAsYoureOwed() {
        let line = DashboardTotalsHeader.line(for: .init(currency: "USD", netMinor: 2000))
        XCTAssertEqual(line, "You're owed $20")
    }

    func testNonRoundAmountKeepsBothDecimalPlaces() {
        let line = DashboardTotalsHeader.line(for: .init(currency: "USD", netMinor: 1550))
        XCTAssertEqual(line, "You're owed $15.50")
    }
}

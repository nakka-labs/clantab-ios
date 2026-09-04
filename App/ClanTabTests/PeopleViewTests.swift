import XCTest
import ClanTabKit
@testable import ClanTab

final class PeopleViewTests: XCTestCase {

    private func net(_ currency: String, _ minor: Int64) -> CrossGroupNet {
        CrossGroupNet(currency: currency, netMinor: minor)
    }

    func testSummaryYouOwe() {
        let s = PeopleView.summary([net("INR", 120_000)], name: "Bob")
        XCTAssertTrue(s.hasPrefix("You owe Bob "), s)
        XCTAssertTrue(s.contains("1") && s.contains("200"))  // ₹1,200.00, locale-independent digits
    }

    func testSummaryTheyOweYou() {
        let s = PeopleView.summary([net("USD", -1500)], name: "Bob")
        XCTAssertTrue(s.hasPrefix("Bob owes you "), s)
        XCTAssertTrue(s.contains("15"))
    }

    func testSummaryMultiCurrencySameDirection() {
        let s = PeopleView.summary([net("INR", 50000), net("USD", 1000)], name: "Sam")
        XCTAssertTrue(s.hasPrefix("You owe Sam "))
        XCTAssertTrue(s.contains("·"))
    }

    func testSummaryMixedDirections() {
        let s = PeopleView.summary([net("INR", 20000), net("USD", -500)], name: "Priya")
        XCTAssertTrue(s.contains("You owe"))
        XCTAssertTrue(s.contains("Priya owes you"))
    }

    func testSummaryEmpty() {
        XCTAssertEqual(PeopleView.summary([], name: "Bob"), "Settled up")
    }
}

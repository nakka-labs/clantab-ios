import XCTest
@testable import ClanTab

final class BalanceHeroViewTests: XCTestCase {

    // MARK: - spacingCurrencySymbol

    func testInsertsThinSpaceAfterAPrefixSymbol() {
        XCTAssertEqual(BalanceHeroView.spacingCurrencySymbol("₹1,200"), "₹\u{2009}1,200")
        XCTAssertEqual(BalanceHeroView.spacingCurrencySymbol("$5"), "$\u{2009}5")
        // A leading minus sign still counts as "preceded by a symbol".
        XCTAssertEqual(BalanceHeroView.spacingCurrencySymbol("-₹500"), "-₹\u{2009}500")
    }

    func testLeavesASuffixSymbolFormatUntouched() {
        XCTAssertEqual(BalanceHeroView.spacingCurrencySymbol("1 200 kr"), "1 200 kr")
    }

    func testLeavesAnAlreadySpacedInputUntouched() {
        XCTAssertEqual(BalanceHeroView.spacingCurrencySymbol("₹ 1,200"), "₹ 1,200")
    }
}

import XCTest
import SwiftUI
@testable import ClanTab

final class AppThemeTests: XCTestCase {

    func testColorSchemeMapping() {
        XCTAssertNil(AppTheme.system.colorScheme)
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }

    /// `@AppStorage` round-trips an enum through its `rawValue` — a typo'd
    /// case name here would silently fall back to `.system` at runtime.
    func testRawValuesMatchCaseNames() {
        XCTAssertEqual(AppTheme.system.rawValue, "system")
        XCTAssertEqual(AppTheme.light.rawValue, "light")
        XCTAssertEqual(AppTheme.dark.rawValue, "dark")
    }

    func testAllCasesHaveDistinctLabels() {
        let labels = Set(AppTheme.allCases.map(\.label))
        XCTAssertEqual(labels.count, AppTheme.allCases.count)
    }
}

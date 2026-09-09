import XCTest
import ClanTabKit
@testable import ClanTab

final class SettingsViewTests: XCTestCase {

    // MARK: - launchLabel (CHECKLIST.md "Settings: launch-screen preference")

    private func group(name: String, emoji: String? = nil) -> KnownGroup {
        KnownGroup(groupId: "G", name: name, lastOpenedAt: Date(), emoji: emoji)
    }

    func testLaunchLabelIsThePlainNameWithNoEmoji() {
        XCTAssertEqual(SettingsView.launchLabel(for: group(name: "Goa trip")), "Goa trip")
    }

    func testLaunchLabelPrefixesTheEmoji() {
        XCTAssertEqual(SettingsView.launchLabel(for: group(name: "Goa trip", emoji: "🏖️")), "🏖️ Goa trip")
    }

    func testLaunchLabelFallsBackToGroupForAnUnnamedGroup() {
        XCTAssertEqual(SettingsView.launchLabel(for: group(name: "")), "Group")
        XCTAssertEqual(SettingsView.launchLabel(for: group(name: "", emoji: "🎉")), "🎉 Group")
    }
}

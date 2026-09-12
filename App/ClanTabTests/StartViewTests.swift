import XCTest
import ClanTabKit
@testable import ClanTab

/// `StartView.isShowingWelcomeBackTotals` (`CHECKLIST.md` UX audit [31]) —
/// the header hides only when the welcome-back card is genuinely about to
/// say the same number.
final class StartViewTests: XCTestCase {

    private func group(netMinor: Int64) -> KnownGroup {
        KnownGroup(
            groupId: "g1", name: "Trip", lastOpenedAt: Date(),
            myBalances: [Balance(memberId: "me", currency: "INR", netMinor: netMinor)]
        )
    }

    func testHidesHeaderWhenWelcomeBackShowsANumber() {
        XCTAssertTrue(StartView.isShowingWelcomeBackTotals(showWelcomeBack: true, groups: [group(netMinor: -500)]))
    }

    func testKeepsHeaderWhenWelcomeBackCardIsNotShowing() {
        XCTAssertFalse(StartView.isShowingWelcomeBackTotals(showWelcomeBack: false, groups: [group(netMinor: -500)]))
    }

    func testKeepsHeaderWhenFullySettledEvenIfWelcomeBackIsShowing() {
        // WelcomeBackCard itself renders nothing here (totals.isEmpty) — the
        // header staying up is the only summary on screen, not a duplicate.
        XCTAssertFalse(StartView.isShowingWelcomeBackTotals(showWelcomeBack: true, groups: [group(netMinor: 0)]))
    }
}

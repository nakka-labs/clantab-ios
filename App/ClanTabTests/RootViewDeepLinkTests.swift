import XCTest
@testable import ClanTab

/// Deep-link parsing and routing (`RootView`) — the pure pieces behind
/// `.onOpenURL`, split out so they can be tested without a hosting view.
final class RootViewDeepLinkTests: XCTestCase {

    // MARK: - extractGroupId

    func testExtractsGroupIdFromDevScheme() {
        XCTAssertEqual(RootView.extractGroupId(from: url("clantab://g/ABC123")), "ABC123")
    }

    func testExtractsGroupIdFromDevSchemeWithTrailingSlash() {
        XCTAssertEqual(RootView.extractGroupId(from: url("clantab://g/ABC123/")), "ABC123")
    }

    func testExtractsGroupIdFromUniversalLinkShape() {
        XCTAssertEqual(RootView.extractGroupId(from: url("https://clantab.example.com/g/XYZ789")), "XYZ789")
    }

    func testExtractsGroupIdWhenLinkHasTrailingPath() {
        XCTAssertEqual(RootView.extractGroupId(from: url("https://clantab.example.com/g/XYZ789/expenses")), "XYZ789")
    }

    func testExtractsGroupIdWhenGIsNotTheFirstPathSegment() {
        XCTAssertEqual(RootView.extractGroupId(from: url("https://host.example/app/g/GID42")), "GID42")
    }

    func testReturnsNilWhenNoGroupSegment() {
        XCTAssertNil(RootView.extractGroupId(from: url("https://clantab.example.com/about")))
    }

    func testReturnsNilWhenGroupSegmentHasNoId() {
        XCTAssertNil(RootView.extractGroupId(from: url("clantab://g/")))
        XCTAssertNil(RootView.extractGroupId(from: url("https://clantab.example.com/g")))
    }

    func testReturnsNilForUnrelatedCustomSchemeHost() {
        XCTAssertNil(RootView.extractGroupId(from: url("clantab://settings/ABC123")))
    }

    // MARK: - resolveDeepLink

    func testResolvesToOpenGroupWhenIdentityExists() {
        // A local membership always wins, signed in or not.
        for signedIn in [true, false] {
            let resolution = RootView.resolveDeepLink(
                url("clantab://g/ABC123"), hasIdentity: { $0 == "ABC123" }, isSignedIn: signedIn
            )
            XCTAssertEqual(resolution, .openGroup("ABC123"))
        }
    }

    func testResolvesToJoinGroupWhenNoIdentityAndGuest() {
        let resolution = RootView.resolveDeepLink(
            url("clantab://g/ABC123"), hasIdentity: { _ in false }, isSignedIn: false
        )
        XCTAssertEqual(resolution, .joinGroup("ABC123"))
    }

    func testResolvesToChooseJoinWhenNoIdentityButSignedIn() {
        let resolution = RootView.resolveDeepLink(
            url("clantab://g/ABC123"), hasIdentity: { _ in false }, isSignedIn: true
        )
        XCTAssertEqual(resolution, .chooseJoin("ABC123"))
    }

    func testResolvesToNilForUnparseableURL() {
        XCTAssertNil(RootView.resolveDeepLink(
            url("https://clantab.example.com/"), hasIdentity: { _ in true }, isSignedIn: true
        ))
    }

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }
}

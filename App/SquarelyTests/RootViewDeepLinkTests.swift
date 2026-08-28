import XCTest
@testable import Squarely

/// Deep-link parsing and routing (`RootView`) — the pure pieces behind
/// `.onOpenURL`, split out so they can be tested without a hosting view.
final class RootViewDeepLinkTests: XCTestCase {

    // MARK: - extractGroupId

    func testExtractsGroupIdFromDevScheme() {
        XCTAssertEqual(RootView.extractGroupId(from: url("squarely://g/ABC123")), "ABC123")
    }

    func testExtractsGroupIdFromDevSchemeWithTrailingSlash() {
        XCTAssertEqual(RootView.extractGroupId(from: url("squarely://g/ABC123/")), "ABC123")
    }

    func testExtractsGroupIdFromUniversalLinkShape() {
        XCTAssertEqual(RootView.extractGroupId(from: url("https://squarely.example.com/g/XYZ789")), "XYZ789")
    }

    func testExtractsGroupIdWhenLinkHasTrailingPath() {
        XCTAssertEqual(RootView.extractGroupId(from: url("https://squarely.example.com/g/XYZ789/expenses")), "XYZ789")
    }

    func testExtractsGroupIdWhenGIsNotTheFirstPathSegment() {
        XCTAssertEqual(RootView.extractGroupId(from: url("https://host.example/app/g/GID42")), "GID42")
    }

    func testReturnsNilWhenNoGroupSegment() {
        XCTAssertNil(RootView.extractGroupId(from: url("https://squarely.example.com/about")))
    }

    func testReturnsNilWhenGroupSegmentHasNoId() {
        XCTAssertNil(RootView.extractGroupId(from: url("squarely://g/")))
        XCTAssertNil(RootView.extractGroupId(from: url("https://squarely.example.com/g")))
    }

    func testReturnsNilForUnrelatedCustomSchemeHost() {
        XCTAssertNil(RootView.extractGroupId(from: url("squarely://settings/ABC123")))
    }

    // MARK: - resolveDeepLink

    func testResolvesToOpenGroupWhenIdentityExists() {
        let resolution = RootView.resolveDeepLink(url("squarely://g/ABC123"), hasIdentity: { $0 == "ABC123" })
        XCTAssertEqual(resolution, .openGroup("ABC123"))
    }

    func testResolvesToJoinGroupWhenNoIdentity() {
        let resolution = RootView.resolveDeepLink(url("squarely://g/ABC123"), hasIdentity: { _ in false })
        XCTAssertEqual(resolution, .joinGroup("ABC123"))
    }

    func testResolvesToNilForUnparseableURL() {
        XCTAssertNil(RootView.resolveDeepLink(url("https://squarely.example.com/"), hasIdentity: { _ in true }))
    }

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }
}

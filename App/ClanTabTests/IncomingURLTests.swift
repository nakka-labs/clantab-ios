import XCTest
@testable import ClanTab

/// `IncomingURL` — the buffer/notify funnel `SceneDelegate` routes every
/// incoming link through (`CHECKLIST.md` "Custom domain + Universal Links").
@MainActor
final class IncomingURLTests: XCTestCase {

    override func tearDown() {
        _ = IncomingURL.consumePending() // don't leak a buffered URL into the next test
        super.tearDown()
    }

    func testHandleBuffersTheURLForAColdLaunchReader() {
        let url = URL(string: "https://clantab.nakka.dev/g/ABC123?token=t1")!
        IncomingURL.handle(url)
        XCTAssertEqual(IncomingURL.pending, url)
    }

    func testConsumePendingReturnsThenClears() {
        let url = URL(string: "clantab://g/XYZ")!
        IncomingURL.handle(url)
        XCTAssertEqual(IncomingURL.consumePending(), url)
        XCTAssertNil(IncomingURL.consumePending())
    }

    func testHandlePostsUrlOpenedForALiveListener() {
        let url = URL(string: "https://clantab.nakka.dev/g/GID42")!
        let posted = expectation(forNotification: .urlOpened, object: nil) { note in
            (note.userInfo?["url"] as? URL) == url
        }
        IncomingURL.handle(url)
        wait(for: [posted], timeout: 1)
    }
}

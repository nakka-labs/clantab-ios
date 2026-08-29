import Testing
@testable import ClanTabKit

@Suite("ClanTabKit Baseline Tests")
struct ClanTabKitTests {
    @Test("ClanTabKit version is defined")
    func testVersion() {
        #expect(ClanTabKitVersion.current == "0.1.0")
    }
}

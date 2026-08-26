import Testing
@testable import SquareKit

@Suite("SquareKit Baseline Tests")
struct SquareKitTests {
    @Test("SquareKit version is defined")
    func testVersion() {
        #expect(SquareKitVersion.current == "0.1.0")
    }
}

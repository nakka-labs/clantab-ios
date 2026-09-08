import Foundation
import Testing
@testable import ClanTabKit

@Suite("GroupColor")
struct GroupColorTests {
    @Test("hue is deterministic per group id and different ids very likely differ")
    func testHue() {
        #expect(GroupColor.hue(forId: "abc123") == GroupColor.hue(forId: "abc123"))
        #expect(GroupColor.hue(forId: "abc123") != GroupColor.hue(forId: "xyz789"))
        for id in ["abc123", "", "a-longer-group-id_42"] {
            let h = GroupColor.hue(forId: id)
            #expect(h >= 0 && h < 360)
        }
    }

    @Test("rgb is in-gamut sRGB across the hue circle and matches the id's hue")
    func testRgb() {
        for hue in stride(from: 0.0, to: 360.0, by: 15.0) {
            let (r, g, b) = OKLCH.sRGB(hue: hue, lightness: GroupColor.lightness, chroma: GroupColor.chroma)
            #expect(r >= 0 && r <= 1 && g >= 0 && g <= 1 && b >= 0 && b <= 1)
        }
        let byId = GroupColor.rgb(forId: "g1")
        let byHue = OKLCH.sRGB(hue: GroupColor.hue(forId: "g1"), lightness: GroupColor.lightness, chroma: GroupColor.chroma)
        #expect(byId.red == byHue.red && byId.green == byHue.green && byId.blue == byHue.blue)
    }
}

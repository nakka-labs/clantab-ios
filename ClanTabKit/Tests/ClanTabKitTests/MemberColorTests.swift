import Foundation
import Testing
@testable import ClanTabKit

@Suite("MemberColor")
struct MemberColorTests {
    /// A handful of fixed names, pinned so a change to the hash or the band
    /// shows up as a test diff rather than silently reshuffling everyone's
    /// color. Values are the sRGB swatch as 0–255 ints.
    @Test("swatch is stable for a set of fixed names")
    func testFixedNames() {
        let expected: [String: (Int, Int, Int)] = [
            "Alex": (175, 40, 67),
            "Sam": (7, 121, 0),
            "Priya": (166, 63, 0),
            "Jordan": (112, 102, 0),
            "Taylor": (0, 106, 184),
        ]
        for (name, rgb) in expected {
            let c = MemberColor.rgb(for: name)
            #expect(Int((c.red * 255).rounded()) == rgb.0, "\(name) red")
            #expect(Int((c.green * 255).rounded()) == rgb.1, "\(name) green")
            #expect(Int((c.blue * 255).rounded()) == rgb.2, "\(name) blue")
        }
    }

    @Test("hue is deterministic and case-insensitive for the same name")
    func testHueDeterministic() {
        #expect(MemberColor.hue(for: "Priya") == MemberColor.hue(for: "Priya"))
        #expect(MemberColor.hue(for: "Priya") == MemberColor.hue(for: "priya"))
        #expect(MemberColor.hue(for: "Priya") == MemberColor.hue(for: "PRIYA"))
    }

    @Test("hue always lands in [0, 360)")
    func testHueRange() {
        for name in ["Alex", "Sam", "Priya", "Jordan", "Taylor", "", "a longer display name", "李雷"] {
            let hue = MemberColor.hue(for: name)
            #expect(hue >= 0)
            #expect(hue < 360)
        }
    }

    @Test("different names very likely produce different hues")
    func testDifferentNamesDifferentHues() {
        #expect(MemberColor.hue(for: "Alex") != MemberColor.hue(for: "Sam"))
    }

    @Test("rgb components are always valid, in-gamut sRGB across the hue circle")
    func testRgbInGamut() {
        for hue in stride(from: 0.0, to: 360.0, by: 5.0) {
            let (r, g, b) = OKLCH.sRGB(hue: hue, lightness: MemberColor.lightness, chroma: MemberColor.chroma)
            #expect(r >= 0 && r <= 1)
            #expect(g >= 0 && g <= 1)
            #expect(b >= 0 && b <= 1)
        }
    }

    @Test("rgb(for:) matches the OKLCH conversion at the name's hue and the member band")
    func testRgbForNameMatchesExplicitHue() {
        let byName = MemberColor.rgb(for: "Jordan")
        let byHue = OKLCH.sRGB(hue: MemberColor.hue(for: "Jordan"), lightness: MemberColor.lightness, chroma: MemberColor.chroma)
        #expect(byName.red == byHue.red)
        #expect(byName.green == byHue.green)
        #expect(byName.blue == byHue.blue)
    }

    @Test("the member band is a higher-chroma band than the category pastel")
    func testHigherChromaThanCategory() {
        #expect(MemberColor.chroma > CategoryColor.chroma)
        // ...and meaningfully more saturated, not a rounding-error nudge.
        #expect(MemberColor.chroma >= CategoryColor.chroma * 2)
    }

    @Test("white text clears WCAG AA on the swatch for every hue")
    func testWhiteTextIsLegible() {
        for hue in stride(from: 0.0, to: 360.0, by: 5.0) {
            let (r, g, b) = OKLCH.sRGB(hue: hue, lightness: MemberColor.lightness, chroma: MemberColor.chroma)
            let contrast = 1.05 / (relativeLuminance(r, g, b) + 0.05)
            #expect(contrast >= 4.5, "white on hue \(hue) is only \(contrast):1")
        }
    }

    /// WCAG 2.x relative luminance of a gamma-encoded sRGB triple.
    private func relativeLuminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}

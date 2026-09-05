import Testing
@testable import ClanTabKit

@Suite("CategoryColor")
struct CategoryColorTests {
    @Test("hue is deterministic and case-insensitive for the same name")
    func testHueDeterministic() {
        let h1 = CategoryColor.hue(for: "Groceries")
        let h2 = CategoryColor.hue(for: "Groceries")
        let h3 = CategoryColor.hue(for: "groceries")
        let h4 = CategoryColor.hue(for: "GROCERIES")
        #expect(h1 == h2)
        #expect(h1 == h3)
        #expect(h1 == h4)
    }

    @Test("hue always lands in [0, 360)")
    func testHueRange() {
        for name in ExpenseCategory.defaults.map(\.name) + ["Uncategorized", "", "a custom category name"] {
            let hue = CategoryColor.hue(for: name)
            #expect(hue >= 0)
            #expect(hue < 360)
        }
    }

    @Test("most default categories land on distinct hues")
    func testDefaultsAreMostlyDistinct() {
        let hues = ExpenseCategory.defaults.map { CategoryColor.hue(for: $0.name) }
        // A hash collision between two of ten names is possible in principle
        // but shouldn't wipe out the whole palette — assert "no worse than
        // one collision" rather than pinning exact hue values to the hash
        // implementation.
        #expect(Set(hues).count >= hues.count - 1)
    }

    @Test("different names very likely produce different hues")
    func testDifferentNamesDifferentHues() {
        #expect(CategoryColor.hue(for: "Groceries") != CategoryColor.hue(for: "Dining"))
    }

    @Test("rgb components are always valid, in-gamut sRGB")
    func testRgbInGamut() {
        for hue in stride(from: 0.0, to: 360.0, by: 15.0) {
            let (r, g, b) = CategoryColor.rgb(hue: hue, lightness: CategoryColor.lightness, chroma: CategoryColor.chroma)
            #expect(r >= 0 && r <= 1)
            #expect(g >= 0 && g <= 1)
            #expect(b >= 0 && b <= 1)
        }
    }

    @Test("the pastel formula is visibly lighter than a mid-gray, i.e. actually pastel")
    func testPastelIsLight() {
        let (r, g, b) = CategoryColor.rgb(for: "Groceries")
        #expect((r + g + b) / 3 > 0.6)
    }

    @Test("rgb(for:) matches rgb(hue:lightness:chroma:) using the name's hue")
    func testRgbForNameMatchesExplicitHue() {
        let byName = CategoryColor.rgb(for: "Dining")
        let byHue = CategoryColor.rgb(hue: CategoryColor.hue(for: "Dining"), lightness: CategoryColor.lightness, chroma: CategoryColor.chroma)
        #expect(byName.red == byHue.red)
        #expect(byName.green == byHue.green)
        #expect(byName.blue == byHue.blue)
    }
}

import Foundation
import Testing
@testable import ClanTabKit

@Suite("CirclePack")
struct CirclePackTests {
    private func pack(_ items: [(String, Double)], w: Double = 300, h: Double = 220) -> [PackedCircle] {
        CirclePack.layout(items.map { (id: $0.0, weight: $0.1) }, width: w, height: h)
    }

    @Test("empty / degenerate input yields nothing")
    func testEmpty() {
        #expect(CirclePack.layout([], width: 100, height: 100).isEmpty)
        #expect(CirclePack.layout([(id: "a", weight: 1)], width: 0, height: 100).isEmpty)
    }

    @Test("a single circle sits at the box centre with the max radius")
    func testSingle() {
        let c = pack([("a", 500)])
        #expect(c.count == 1)
        #expect(c[0].id == "a")
        #expect(c[0].radius == 68)
        #expect(abs(c[0].x - 150) < 0.001)
        #expect(abs(c[0].y - 110) < 0.001)
    }

    @Test("radius tracks sqrt(weight); a zero weight is the minimum dot")
    func testRadii() {
        // A box large enough that no scale-to-fit shrink kicks in.
        let c = pack([("big", 400), ("quarter", 100), ("zero", 0)], w: 900, h: 700)
        let byId = Dictionary(uniqueKeysWithValues: c.map { ($0.id, $0.radius) })
        #expect(byId["big"] == 68)
        // sqrt(100/400) = 0.5 → 12 + (68-12)*0.5 = 40
        #expect(byId["quarter"] == 40)
        #expect(byId["zero"] == 12)
    }

    @Test("the packed cluster fits inside the target box")
    func testFitsBox() {
        let c = pack([("a", 900), ("b", 400), ("c", 250), ("d", 100), ("e", 50)], w: 300, h: 190)
        for circle in c {
            #expect(circle.x - circle.radius >= -1)
            #expect(circle.x + circle.radius <= 301)
            #expect(circle.y - circle.radius >= -1)
            #expect(circle.y + circle.radius <= 191)
        }
    }

    @Test("circles never overlap — every pair clears the gap")
    func testNoOverlap() {
        let c = pack([("a", 900), ("b", 400), ("c", 250), ("d", 100), ("e", 50), ("f", 0)])
        for i in c.indices {
            for j in (i + 1)..<c.count {
                let d = ((c[i].x - c[j].x) * (c[i].x - c[j].x) + (c[i].y - c[j].y) * (c[i].y - c[j].y)).squareRoot()
                #expect(d >= c[i].radius + c[j].radius - 1.5, "\(c[i].id)/\(c[j].id) overlap: d=\(d)")
            }
        }
    }

    @Test("minNonZeroRadius floors a tiny nonzero weight but leaves a real zero a dot")
    func testNonZeroFloor() {
        let c = CirclePack.layout(
            [(id: "big", weight: 10_000), (id: "tiny", weight: 1), (id: "zero", weight: 0)],
            width: 900, height: 700,
            minRadius: 11, minNonZeroRadius: 20
        )
        let byId = Dictionary(uniqueKeysWithValues: c.map { ($0.id, $0.radius) })
        #expect(byId["tiny"]! >= 20)
        #expect(byId["zero"] == 11)
    }

    @Test("deterministic — input order doesn't change the layout")
    func testDeterministic() {
        let a = pack([("y", 100), ("x", 100), ("z", 100)])
        let b = pack([("z", 100), ("y", 100), ("x", 100)])
        #expect(a == b)
        #expect(Set(a.map(\.radius)).count == 1) // equal weights → equal radius
    }
}

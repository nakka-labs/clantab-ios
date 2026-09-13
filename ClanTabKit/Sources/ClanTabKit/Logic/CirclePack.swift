import Foundation

/// One laid-out circle from `CirclePack.layout` — `x`/`y` is the centre, all
/// in the same point space as the `width`/`height` passed in.
public struct PackedCircle: Equatable, Sendable, Identifiable {
    public let id: String
    public let x: Double
    public let y: Double
    public let radius: Double

    public init(id: String, x: Double, y: Double, radius: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.radius = radius
    }
}

/// Approximate circle packing for the balance-bubble view (`FEATURE_BACKLOG.md`
/// "Balance bubble/circle-pack view") — no charting library, just an
/// Archimedean-spiral placement: the heaviest item centred, the rest spiralled
/// out and dropped at the first spot that doesn't overlap. Not an optimal
/// packing; it reads fine and it's deterministic (ties broken by `id`).
///
/// Pure: takes and returns plain numbers, so it's testable without a view.
public enum CirclePack {
    /// - Parameters:
    ///   - items: `(id, weight)` pairs; `weight` is a magnitude (≥ 0). A
    ///     zero-weight item becomes a `minRadius` dot.
    ///   - width/height: the box to lay out in; the result is re-centred to
    ///     sit in the middle of it.
    ///   - radius: `minRadius…maxRadius`, scaled by `sqrt(weight / maxWeight)`
    ///     so **area** tracks weight.
    ///   - minNonZeroRadius: a legibility floor applied only to items with a
    ///     *nonzero* weight — so a tiny-but-real balance still renders big
    ///     enough to carry a label, while a genuine zero stays a `minRadius`
    ///     dot. `0` (the default) disables it: every item floors at
    ///     `minRadius`, the historical behaviour. Applied as a uniform
    ///     *shift* to every below-floor circle (see below), not a hard
    ///     clamp — a real-device report (`CHECKLIST.md` "Real-device
    ///     findings") found two visibly different small balances rendering
    ///     as identically-sized circles, because the previous clamp rounded
    ///     everything under the floor to the exact same constant.
    ///   - gap: clear space kept between circles.
    public static func layout(
        _ items: [(id: String, weight: Double)],
        width: Double,
        height: Double,
        minRadius: Double = 12,
        maxRadius: Double = 68,
        minNonZeroRadius: Double = 0,
        gap: Double = 6
    ) -> [PackedCircle] {
        guard !items.isEmpty, width > 0, height > 0 else { return [] }

        let sorted = items.sorted { a, b in
            a.weight != b.weight ? a.weight > b.weight : a.id < b.id
        }
        let maxWeight = sorted.first!.weight
        let nonZeroIds = Set(items.filter { $0.weight > 0 }.map(\.id))

        // Pure sqrt-area scaling, no floor applied here — flooring this
        // early would place circles for the spiral-packing step using an
        // already-inflated size, which is fine, but baking the floor in as
        // a hard clamp (rather than the shift below) is what collapsed
        // distinct small balances to one identical radius.
        func rawRadius(for weight: Double) -> Double {
            guard maxWeight > 0, weight > 0 else { return minRadius }
            let t = (weight / maxWeight).squareRoot()
            return minRadius + (maxRadius - minRadius) * t
        }

        var placed: [PackedCircle] = []
        for item in sorted {
            let r = rawRadius(for: item.weight)
            let center = placed.isEmpty
                ? (x: 0.0, y: 0.0)
                : spiralSpot(radius: r, gap: gap, avoiding: placed)
            placed.append(PackedCircle(id: item.id, x: center.x, y: center.y, radius: r))
        }

        // Scale the whole cluster down (never up) so its bounding box fits the
        // target box, then re-centre it there. Without this the spiral can spill
        // past the edges and the view clips it.
        let minX = placed.map { $0.x - $0.radius }.min() ?? 0
        let maxX = placed.map { $0.x + $0.radius }.max() ?? 0
        let minY = placed.map { $0.y - $0.radius }.min() ?? 0
        let maxY = placed.map { $0.y + $0.radius }.max() ?? 0
        let spanX = maxX - minX
        let spanY = maxY - minY
        let scale = min(1, min(spanX > 0 ? width / spanX : 1, spanY > 0 ? height / spanY : 1))

        let dx = width / 2 - scale * (minX + maxX) / 2
        let dy = height / 2 - scale * (minY + maxY) / 2

        // The legibility floor, applied once, here, as a *shift* rather
        // than a clamp: find the smallest post-scale nonzero radius, and if
        // it's under the floor, raise every below-floor circle by exactly
        // enough that the smallest one reaches the floor. Each circle keeps
        // its size *relative to the others* (their point-difference is
        // unchanged) instead of every below-floor circle collapsing to the
        // identical constant. A circle already at or above the floor (the
        // common case) is untouched — this only ever nudges the genuinely
        // tiny ones, same "may nudge into a slight overlap" trade the old
        // clamp already accepted for this rare case.
        let nonZeroScaled = placed.filter { nonZeroIds.contains($0.id) }.map { $0.radius * scale }
        let smallestNonZeroScaled = nonZeroScaled.min() ?? minNonZeroRadius
        let subFloorShift = max(0, minNonZeroRadius - smallestNonZeroScaled)

        return placed.map {
            let scaled = $0.radius * scale
            let boosted = nonZeroIds.contains($0.id) && scaled < minNonZeroRadius
            return PackedCircle(
                id: $0.id,
                x: $0.x * scale + dx,
                y: $0.y * scale + dy,
                radius: (boosted ? scaled + subFloorShift : scaled).rounded()
            )
        }
    }

    /// Walk an Archimedean spiral out from the origin; return the first point
    /// where a circle of `radius` clears every already-`placed` circle by
    /// `gap`.
    private static func spiralSpot(
        radius: Double,
        gap: Double,
        avoiding placed: [PackedCircle]
    ) -> (x: Double, y: Double) {
        let step = 0.35
        var angle = 0.0
        while angle < 200 {
            let dist = 6 * angle
            let x = dist * Foundation.cos(angle)
            let y = dist * Foundation.sin(angle)
            let clears = placed.allSatisfy { other in
                let d = ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
                return d >= radius + other.radius + gap
            }
            if clears { return (x, y) }
            angle += step
        }
        return (0, 0) // pathological fallback — everything overlaps at centre
    }
}

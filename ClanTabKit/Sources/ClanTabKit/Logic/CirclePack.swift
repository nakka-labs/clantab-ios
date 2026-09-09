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
    ///   - gap: clear space kept between circles.
    public static func layout(
        _ items: [(id: String, weight: Double)],
        width: Double,
        height: Double,
        minRadius: Double = 12,
        maxRadius: Double = 68,
        gap: Double = 6
    ) -> [PackedCircle] {
        guard !items.isEmpty, width > 0, height > 0 else { return [] }

        let sorted = items.sorted { a, b in
            a.weight != b.weight ? a.weight > b.weight : a.id < b.id
        }
        let maxWeight = sorted.first!.weight

        func radius(for weight: Double) -> Double {
            guard maxWeight > 0, weight > 0 else { return minRadius }
            let t = (weight / maxWeight).squareRoot()
            return (minRadius + (maxRadius - minRadius) * t).rounded()
        }

        var placed: [PackedCircle] = []
        for item in sorted {
            let r = radius(for: item.weight)
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

        return placed.map {
            PackedCircle(
                id: $0.id,
                x: $0.x * scale + dx,
                y: $0.y * scale + dy,
                radius: ($0.radius * scale).rounded()
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

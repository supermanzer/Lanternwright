import simd

/// A vertical cylinder obstacle (lighthouse tower, standing stones, tree trunks).
struct CylinderCollider {
    var center: SIMD2<Float>
    var radius: Float
    var minY: Float
    var maxY: Float
}

/// Pushes a circular player out of obstacles. Only horizontal position is corrected.
struct Colliders {
    var cylinders: [CylinderCollider] = []

    mutating func addCylinder(center: SIMD2<Float>, radius: Float, minY: Float, maxY: Float) {
        cylinders.append(CylinderCollider(center: center, radius: radius, minY: minY, maxY: maxY))
    }

    /// Resolve overlaps for a player circle of `radius` whose body spans [feetY, feetY + height].
    /// Two passes, so being pushed out of one obstacle into a neighbour is corrected as well.
    func resolve(position p: inout SIMD2<Float>, radius: Float, feetY: Float, height: Float) {
        for _ in 0..<2 {
            for c in cylinders where feetY < c.maxY && feetY + height > c.minY {
                let d = p - c.center
                let dist = length(d)
                let minDist = c.radius + radius
                if dist < minDist {
                    let n = dist > 1e-5 ? d / dist : SIMD2<Float>(1, 0)
                    p = c.center + n * minDist
                }
            }
        }
    }
}

/// A flat-topped strip you can walk on that is independent of the terrain (the dock, the causeway).
/// The surface height runs linearly from y0 at `a` to y1 at `b`.
struct Walkable {
    var a: SIMD2<Float>
    var b: SIMD2<Float>
    var halfWidth: Float
    var y0: Float
    var y1: Float
    var enabled = true
    var surface: SurfaceKind = .wood

    /// Surface height at p, or nil if p is outside the strip.
    func height(at p: SIMD2<Float>) -> Float? {
        guard enabled else { return nil }
        let ab = b - a
        let t = dot(p - a, ab) / dot(ab, ab)
        guard t >= 0, t <= 1 else { return nil }
        let closest = a + ab * t
        guard length(p - closest) <= halfWidth else { return nil }
        return y0 + (y1 - y0) * t
    }
}

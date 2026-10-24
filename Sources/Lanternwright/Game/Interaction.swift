import simd

/// Something the player can look at and click: an axis-aligned box in the world plus a prompt.
struct Interactable {
    var id: String
    var min: SIMD3<Float>
    var max: SIMD3<Float>
    var prompt: String
    var reach: Float = 3.5          // metres from the eye
    var enabled = true
}

enum Interaction {
    /// Distance along the ray to the box (slab method), or nil if it misses. A ray starting inside returns 0.
    static func rayBox(origin o: SIMD3<Float>, dir d: SIMD3<Float>, min lo: SIMD3<Float>, max hi: SIMD3<Float>) -> Float? {
        var tNear: Float = 0, tFar: Float = .infinity
        for axis in 0..<3 {
            if abs(d[axis]) < 1e-8 {
                if o[axis] < lo[axis] || o[axis] > hi[axis] { return nil }      // parallel to this slab and outside it
            } else {
                var t0 = (lo[axis] - o[axis]) / d[axis], t1 = (hi[axis] - o[axis]) / d[axis]
                if t0 > t1 { swap(&t0, &t1) }
                tNear = Swift.max(tNear, t0); tFar = Swift.min(tFar, t1)
                if tNear > tFar { return nil }
            }
        }
        return tNear
    }

    /// The nearest enabled interactable hit by the ray within its reach.
    static func pick(origin: SIMD3<Float>, dir: SIMD3<Float>, in list: [Interactable]) -> Interactable? {
        var best: (Interactable, Float)?
        for item in list where item.enabled {
            if let t = rayBox(origin: origin, dir: dir, min: item.min, max: item.max), t <= item.reach {
                if best == nil || t < best!.1 { best = (item, t) }
            }
        }
        return best?.0
    }
}

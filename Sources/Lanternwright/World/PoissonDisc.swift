import simd

/// Bridson's Poisson-disc sampling with a spacing that varies across the plane: points are never closer than the local
/// radius (blue noise: even without rows or clumps of its own), while a density field makes the radius small in groves and
/// large in clearings. Deterministic for a given seed. Candidate points must pass `accept` (the placement rules).
enum PoissonDisc {
    struct Rng {
        var state: UInt64
        mutating func next() -> Float {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Float(z >> 40) / Float(1 << 24)
        }
    }

    /// - Parameters:
    ///   - radius: minimum distance to other points around a place (metres); must lie in `rMin...rMax`.
    ///   - accept: placement rules (terrain, exclusion zones...).
    ///   - seedSpacing: spacing of the coarse grid used to start a fresh chain in every separate accepted region.
    static func sample(min lo: SIMD2<Float>, max hi: SIMD2<Float>, rMin: Float, rMax: Float, radius: (SIMD2<Float>) -> Float,
                       accept: (SIMD2<Float>) -> Bool, seed: UInt64, seedSpacing: Float = 40, attempts: Int = 24) -> [SIMD2<Float>] {
        var rng = Rng(state: seed)
        let cell = rMin / Float(2).squareRoot()
        let nx = Int(ceil((hi.x - lo.x) / cell)), ny = Int(ceil((hi.y - lo.y) / cell))
        var grid = [Int32](repeating: -1, count: nx * ny)
        var points: [SIMD2<Float>] = []
        var active: [Int] = []
        let reach = Int(ceil(rMax / cell))

        func cellOf(_ p: SIMD2<Float>) -> (Int, Int) { (Int((p.x - lo.x) / cell), Int((p.y - lo.y) / cell)) }
        func fits(_ p: SIMD2<Float>) -> Bool {
            guard p.x >= lo.x, p.x < hi.x, p.y >= lo.y, p.y < hi.y, accept(p) else { return false }
            let r = radius(p)
            let (cx, cy) = cellOf(p)
            for j in max(0, cy - reach)...min(ny - 1, cy + reach) {
                for i in max(0, cx - reach)...min(nx - 1, cx + reach) {
                    let q = grid[j * nx + i]
                    if q >= 0 {
                        let other = points[Int(q)]
                        let need = 0.5 * (r + radius(other))
                        if simd_length_squared(other - p) < need * need { return false }
                    }
                }
            }
            return true
        }
        func add(_ p: SIMD2<Float>) {
            let (cx, cy) = cellOf(p)
            grid[cy * nx + cx] = Int32(points.count)
            active.append(points.count)
            points.append(p)
        }

        // Chains start from a coarse grid of accepted places, so every separate region of the island gets points.
        var sy = lo.y
        while sy < hi.y {
            var sx = lo.x
            while sx < hi.x {
                let p = SIMD2(sx + rng.next() * seedSpacing, sy + rng.next() * seedSpacing)
                if fits(p) { add(p) }
                // grow this chain fully before the next seed
                while !active.isEmpty {
                    let ai = Int(rng.next() * Float(active.count)) % active.count
                    let base = points[active[ai]]
                    let r = radius(base)
                    var found = false
                    for _ in 0..<attempts {
                        let a = rng.next() * 2 * .pi, d = r * (1 + rng.next())
                        let cand = base + SIMD2(cos(a), sin(a)) * d
                        if fits(cand) { add(cand); found = true; break }
                    }
                    if !found { active.swapAt(ai, active.count - 1); active.removeLast() }
                }
                sx += seedSpacing
            }
            sy += seedSpacing
        }
        return points
    }
}

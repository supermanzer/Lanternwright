import simd

/// F03 P1 (note #43: "the pedestals for the note pages appear too deliberate. Resume the dropped pages approach... players should be able to overlook these and struggle for a
/// bit. It instructed the player to pay attention to details"; note #51: the lectern at the altar was set INTO the dais, not on it). The journal pages are loose sheets that
/// lie where the story says they fell: on the ground, a plank, a step of the dais, tilted a little by whatever they rest on, a pebble on a corner. F04 P1 (notes #53-#55: "duplicate pages that I cannot interact with"): the extra
/// loose sheets are gone; each page is ONE object, and nothing else near it looks like paper. No lectern, glow, light thread, motes, chime, banner or marker: a page is found by looking where a page would be.
///
/// A sheet is SETTLED onto the surface under it: it is turned to follow the ground's slope (at most 18 degrees), tilted by its own lean, and lowered until its lowest
/// vertex is `clearance` (3 mm) above the ground under that vertex, so it lies ON the surface, never in it and never floating (SelfTestPages asserts it at every vertex).
enum DroppedPages {
    /// How a page lies: its yaw (radians), how far its far end is lifted by what it is caught on (radians). Page 3 (the wind stone's) is blown into the grass and leans hard; page 4's lies against the step.
    struct Spec { var yaw: Float; var lean: Float }
    static func spec(_ n: Int) -> Spec {
        switch n {
        case 1: return Spec(yaw: 0.45, lean: 0.04)          // along the boards: a sheet beside it would hang over the edge
        case 2: return Spec(yaw: 2.10, lean: 0.07)
        case 3: return Spec(yaw: -0.70, lean: 0.30)
        case 4: return Spec(yaw: 1.10, lean: 0.12)
        case 5: return Spec(yaw: 0.50, lean: 0.06)           // inside the band between the plate's inlaid rings, clear of both and of the edge
        case 6: return Spec(yaw: -2.00, lean: 0.22)
        case 7: return Spec(yaw: 2.60, lean: 0.09)
        case 9: return Spec(yaw: -0.55, lean: 0.03)           // along the boards, like page 1, at the other end of the dock
        default: return Spec(yaw: 0.90, lean: 0.10)
        }
    }

    static let clearance: Float = 0.003
    static let maxFollow: Float = 0.314                                        // 18 degrees: the steepest slope a sheet is turned to follow

    /// Where a sheet of `vertices` (the shared paper mesh) lies when dropped at (x, z) with this yaw and lean on `ground`: the model matrix and the sheet origin's world position.
    static func settle(vertices: [SIMD3<Float>], x: Float, z: Float, yaw: Float, lean: Float, ground: (Float, Float) -> Float) -> (model: float4x4, origin: SIMD3<Float>) {
        // Follow the ground: its gradient over about half a metre turns the sheet's up axis (capped).
        let e: Float = 0.25
        let gx = (ground(x + e, z) - ground(x - e, z)) / (2 * e), gz = (ground(x, z + e) - ground(x, z - e)) / (2 * e)
        var up = simd_normalize(SIMD3(-gx, 1, -gz))
        let tiltAngle = acos(min(1, max(-1, up.y)))
        if tiltAngle > maxFollow { up = simd_normalize(SIMD3(0, 1, 0) + (up - SIMD3(0, 1, 0)) * (maxFollow / tiltAngle)) }
        let R = rotation(aligningYTo: up) * rotationY(yaw) * rotationX(lean)
        var worldY: Float = -.infinity
        for v in vertices {
            let w = R * SIMD4(v, 0)
            worldY = max(worldY, ground(x + w.x, z + w.z) - w.y + clearance)       // the sheet rests on the highest ground under any part of it
        }
        let origin = SIMD3(x, worldY, z)
        return (translation(origin) * R, origin)
    }

    /// The lowest vertex's height above the ground under it (metres) for a placed sheet: what the selftest bounds between 0 and 5 mm.
    static func lowestClearance(vertices: [SIMD3<Float>], model: float4x4, ground: (Float, Float) -> Float) -> Float {
        vertices.map { v -> Float in let w = model * SIMD4(v, 1); return w.y - ground(w.x, w.z) }.min() ?? 0
    }

    /// Where a page lies. `base(n)` is the page's spot on the ground in the layout (World/Layout or the puzzle props);
    /// `ground` is the world's own ground height (terrain, boards, platforms): Scene.groundHeight.
    struct Lie { var origin: SIMD3<Float>; var model: float4x4 }
    static func lie(page n: Int, base: SIMD2<Float>, sheet: [SIMD3<Float>], ground: (Float, Float) -> Float) -> Lie {
        let s = spec(n)
        let m = settle(vertices: sheet, x: base.x, z: base.y, yaw: s.yaw, lean: s.lean, ground: ground)
        return Lie(origin: m.origin, model: m.model)
    }

    /// A very faint clue that is allowed (note #43: "a loose sheet moves slightly in the wind gust"): in a gust the main sheet lifts a degree or two at one edge and settles
    /// again. Nothing outlines it and nothing glows. `gust` is Wind.strength at the page.
    static func flutter(model: float4x4, page n: Int, time t: Float, gust: Float) -> float4x4 {
        let a = max(0, gust - 0.35) * 0.075 * (0.6 + 0.4 * sin(t * 6.1 + Float(n) * 1.7)) * (0.5 + 0.5 * sin(t * 2.3 + Float(n)))
        return model * rotationX(a)
    }
}

import simd

/// Every landmark position lives here (docs/TASKS.md §0). Terrain flattens a pad around each landmark
/// so props sit on solid ground. Units are metres; +Y up, north = -Z, east = +X.
enum Layout {
    struct Pad {
        var center: SIMD3<Float>    // y is the exact ground height at the centre
        var radius: Float           // flat radius
        var blend: Float = Terrain.padBlend   // terrain eases back to its natural shape over this many metres beyond it
    }

    // Landmarks
    static let dockEnd = SIMD3<Float>(175, 0.8, 205)        // spawn: walking surface at the dock's seaward end
    static let dockShore = SIMD3<Float>(150, 1.5, 172)      // where the dock meets the beach
    static let tideStone = SIMD3<Float>(118, 3, 118)
    static let windStone = SIMD3<Float>(40, 34, 55)
    static let summitStone = SIMD3<Float>(-5, 66, -18)
    static let lighthouse = SIMD3<Float>(-30, 68, -48)
    static let causewayStart = SIMD3<Float>(-35, 1.5, -225)
    static let isletCenter = SIMD3<Float>(-40, 5, -320)
    /// A bell buoy out at sea, east of the dock (sound only, plus a small floating mesh). y = the waterline.
    static let buoy = SIMD3<Float>(262, 0, 222)
    /// Faces along the dock toward the shore (north-west), so walking forward stays on the planks.
    /// = atan2(dx, -dz) for dockEnd -> dockShore.
    static let spawnYaw: Float = -0.65

    static let pads: [Pad] = [
        Pad(center: dockShore, radius: 5, blend: 8),       // short ramp: the beach must end near here so the dock reaches water
        Pad(center: tideStone, radius: 6),
        Pad(center: windStone, radius: 6),
        Pad(center: summitStone, radius: 6),
        Pad(center: lighthouse, radius: 14),
        Pad(center: causewayStart, radius: 8),
        Pad(center: isletCenter, radius: 30),
    ]

    /// The dock's walkable strip: dockShore -> dockEnd, extended 1.5 m landward and 2 m seaward so that the spawn
    /// point (exactly at dockEnd) is safely inside it rather than on a floating-point knife edge.
    static func dockStrip() -> (a: SIMD2<Float>, b: SIMD2<Float>, y0: Float, y1: Float) {
        let s = SIMD2(dockShore.x, dockShore.z), e = SIMD2(dockEnd.x, dockEnd.z)
        let len = simd_length(e - s), dir = (e - s) / len
        let slope = (dockEnd.y - dockShore.y) / len
        return (s - dir * 1.5, e + dir * 2, dockShore.y - slope * 1.5, dockEnd.y + slope * 2)
    }

    /// Lantern path, in walking order.
    static let lanternPath: [SIMD3<Float>] = [dockShore, tideStone, windStone, summitStone, lighthouse]
    /// The lit route the player is led along (F01 W5): the stones' path plus a graded descent from the lighthouse to the causeway's start on the north shore, whose
    /// hillside is a cliff (a 1.0 grade) that the 40 degree walking limit no longer lets anyone climb. The terrain cuts a graded bench along it and lanterns follow it.
    static let route: [SIMD3<Float>] = lanternPath + [causewayStart]

    // Terrain shape. The island is the union of three lobes (see Terrain.height):
    //  - a hill: radial profile about `hillCenter` out to `hillRadius`;
    //  - a low shelf along the spine hillCenter -> spineEnd, which carries the south-east shore and the dock;
    //  - the islet, a small hill about isletCenter.
    static let hillCenter = SIMD2<Float>(-15, -35)
    static let hillRadius: Float = 215
    static let hillPeak: Float = 72
    static let spineEnd = SIMD2<Float>(125, 125)
    static let shelfRadius: Float = 75
    static let shelfHeight: Float = 3.5
    static let isletRadius: Float = 42
    static let isletPeak: Float = 7
    static let seaFloor: Float = -24
}

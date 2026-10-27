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

// MARK: Navigation (M10.3, builder B)
// The soft corridors each world confines the player to (see Game/Navigation.swift for the model and M10.4 for what happens at the edge). The routes are the
// worlds' own paths: Varrow's graded lantern route (the same polyline the terrain cuts its bench along, so the trail follows the path weight) and the Glass Wood's
// walking route, plus the dock, the causeway, and the pool's rim. Every number below is built from the landmark constants above or `GlassLayout`'s; there are no new
// positions here. Widths: trails are 9 to 11 m wide, plazas 20 m round the landmarks (the plan asks for corridors that never feel like rails).
extension Layout {
    enum Navigation {
        static let trailHalfWidth: Float = 5.5
        private static func xz(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x, p.z) }

        static func network(for kind: WorldKind) -> NavNetwork {
            switch kind {
            case .varrow: return varrow
            case .glassWood: return glassWood
            }
        }

        /// M10.7: the loose versions (trails and plazas 1.6x wider), built once (a network builds its graph when it is made: never per tick).
        static let varrowLoose = varrow.widened(by: Guidance.looseWidth)
        static let glassWoodLoose = glassWood.widened(by: Guidance.looseWidth)

        /// The network for a guidance setting (nil in free roam).
        static func network(for kind: WorldKind, guidance: Guidance) -> NavNetwork? {
            switch guidance {
            case .free: return nil
            case .guided: return network(for: kind)
            case .loose: return kind == .varrow ? varrowLoose : glassWoodLoose
            }
        }
        /// What the player is confined to right now (`Player.guidance`): nil in free roam.
        static func active(for kind: WorldKind) -> NavNetwork? { network(for: kind, guidance: Player.guidance) }

        /// Varrow: dock -> beach -> shore path -> tide stone -> ridge -> wind stone -> summit route -> lighthouse -> north descent -> causeway -> islet.
        static let varrow: NavNetwork = {
            let r = Layout.route.map(xz)                       // dockShore, tide, wind, summit, lighthouse, causewayStart
            let w = trailHalfWidth
            let trails = [
                NavNetwork.Trail("dock", [xz(dockEnd), xz(dockShore)], halfWidth: 4.5),
                NavNetwork.Trail("shore path", [r[0], r[1]], halfWidth: w),
                NavNetwork.Trail("ridge path", [r[1], r[2]], halfWidth: w),
                NavNetwork.Trail("summit route", [r[2], r[3], r[4]], halfWidth: w),
                NavNetwork.Trail("north descent", [r[4], r[5]], halfWidth: w),
                NavNetwork.Trail("causeway", [r[5], xz(isletCenter)], halfWidth: 5),
            ]
            let plazas = [
                NavNetwork.Plaza(name: "beach landing", center: r[0], radius: 14),
                NavNetwork.Plaza(name: "tide stone plaza", center: r[1], radius: 20),
                NavNetwork.Plaza(name: "wind stone plaza", center: r[2], radius: 20),
                NavNetwork.Plaza(name: "summit stone plaza", center: r[3], radius: 20),
                NavNetwork.Plaza(name: "lighthouse plaza", center: r[4], radius: 26),
                NavNetwork.Plaza(name: "causeway landing", center: r[5], radius: 16),
                NavNetwork.Plaza(name: "lens islet", center: xz(isletCenter), radius: 36),
            ]
            let vantages = [
                NavNetwork.Vantage(name: "lighthouse from the dock", position: xz(dockEnd), target: lighthouse + SIMD3(0, 24, 0), tolerance: 4),
                NavNetwork.Vantage(name: "the lens from the causeway", position: xz(causewayStart), target: SIMD3(isletCenter.x - 1.2, isletCenter.y + 2.3, isletCenter.z), tolerance: 4),   // aimed 1.2 m west of the ring's centre: a trunk 7 m before the lens stands exactly on the line from the causeway (found by --nav-audit)
                // The stones pilot (M10.5; see docs/plans/M10-puzzle-notes.md). The hill is convex, so only the DOWNHILL direction shows more than one stone:
                // the climb station stands 14 m before the tide stone and frames the stone, the lantern path and the lighthouse above it; the descent station stands 10 m
                // past the summit stone and frames the wind stone and, beyond it on the beach, the tide stone (the target is halfway between their capstones).
                NavNetwork.Vantage(name: "the climb: the tide stone and the way up", position: xz(tideStone) - normalize(xz(tideStone) - xz(dockShore)) * 14, target: lighthouse + SIMD3(0, 24, 0), tolerance: 4),
                NavNetwork.Vantage(name: "the descent: the wind and tide stones, then the sea", position: xz(summitStone) + normalize(xz(windStone) - xz(summitStone)) * 10,
                                   target: (windStone + tideStone) / 2 + SIMD3(0, 3, 0), tolerance: 4),
            ]
            // The player arrives from the Glass Wood beside the lens (Game.travel).
            return NavNetwork(trails: trails, plazas: plazas, vantages: vantages, spawn: xz(dockEnd), arrivals: [xz(isletCenter) + SIMD2(0, 5)])
        }()

        /// The Glass Wood: arrival -> western path -> mirror court -> junction -> chime ring, junction -> altar path -> altar, and a rim path round the pool's north bank.
        static let glassWood: NavNetwork = {
            let p = GlassLayout.path.map(xz)           // arrival, ., ., ., court, ., junction, ., ring, ., junction, altar
            let w = trailHalfWidth
            // The rim path: an arc 4 m beyond the pool's radius (the lip of its bank, which its 9 m width covers), round the pool's north side, from the mirror court to the chime ring.
            let pool = GlassTerrain.pool, rimR = GlassTerrain.poolRadius + 4
            let arc = stride(from: Float.pi, through: 2 * .pi + 0.001, by: .pi / 6).map { pool + SIMD2(cos($0), sin($0)) * rimR }
            let rim = [xz(GlassLayout.mirrorCourt)] + arc + [xz(GlassLayout.chimeRing)]
            let trails = [
                NavNetwork.Trail("western path", Array(p[0...6]), halfWidth: w),
                NavNetwork.Trail("chime path", Array(p[6...8]), halfWidth: w),
                NavNetwork.Trail("altar path", [p[10], p[11]], halfWidth: w),
                NavNetwork.Trail("pool rim path", rim, halfWidth: 4.5),
            ]
            let plazas = [
                NavNetwork.Plaza(name: "arrival pad", center: p[0], radius: 14),
                NavNetwork.Plaza(name: "mirror court", center: xz(GlassLayout.mirrorCourt), radius: 26),
                NavNetwork.Plaza(name: "junction", center: xz(GlassLayout.junction), radius: 12),
                NavNetwork.Plaza(name: "chime ring", center: xz(GlassLayout.chimeRing), radius: 22),
                NavNetwork.Plaza(name: "altar", center: xz(GlassLayout.altar), radius: 20),
            ]
            let vantages = [
                NavNetwork.Vantage(name: "the pool from its rim", position: pool + SIMD2(0, -(GlassTerrain.poolRadius + 2)), target: SIMD3(pool.x, 0, pool.y), tolerance: 4),   // the dome hides the pool from the altar path (checked): from the rim you look down into the bowl
                NavNetwork.Vantage(name: "the court from its approach", position: p[3], target: GlassLayout.mirrorCourt + SIMD3(0, 1.5, 0), tolerance: 4),
                NavNetwork.Vantage(name: "the altar from the junction", position: xz(GlassLayout.junction) + SIMD2(0, -10), target: GlassLayout.altar + SIMD3(0, 2, 0), tolerance: 4),
            ]
            return NavNetwork(trails: trails, plazas: plazas, vantages: vantages, spawn: xz(GlassLayout.arrival), arrivals: [xz(GlassLayout.arrival)])
        }()
    }
}

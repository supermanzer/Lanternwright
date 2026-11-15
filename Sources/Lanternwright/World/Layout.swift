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
    /// F09.8: how much the seabed of the strait between the north shore and the lens islet is lowered (see `TerrainSpec.varrow`).
    static let strait: Float = 2.2
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
            case .tideArchive: return tideArchive
            }
        }

        /// M10.7: the loose versions (trails and plazas 1.6x wider), built once (a network builds its graph when it is made: never per tick).
        static let varrowLoose = varrow.widened(by: Guidance.looseWidth)
        static let glassWoodLoose = glassWood.widened(by: Guidance.looseWidth)
        static let tideArchiveLoose = tideArchive.widened(by: Guidance.looseWidth)

        /// The network for a guidance setting (nil in free roam).
        static func network(for kind: WorldKind, guidance: Guidance) -> NavNetwork? {
            switch guidance {
            case .free: return nil
            case .guided: return network(for: kind)
            case .loose: return kind == .varrow ? varrowLoose : (kind == .glassWood ? glassWoodLoose : tideArchiveLoose)
            }
        }
        /// What the player is confined to right now (`Player.guidance`): nil in free roam.
        static func active(for kind: WorldKind) -> NavNetwork? { network(for: kind, guidance: Player.guidance) }

        /// S03.4a: where the lighthouse signal points once the altar is solved (builder A draws it from these, so nothing is spelled out twice): along the way the player comes up from the
        /// lens islet (the causeway's start), and at the door (its south face).
        static var signalTrailPoint: SIMD3<Float> { causewayStart }
        /// P02.3 (the plates' answer): after the sweeps and the rest, the beam flashes THREE GROUPS of distinct lengths at the door heading, read from the dock approach at dusk. The durations
        /// are here and nowhere else (builder B maps them to plates by RANK: the longest group = stone, the middle = wind, the shortest = tide; the order they are flashed in is the order the plates are struck).
        /// `BeamSignal.groupWindows` gives the exact clock windows; the whole cycle repeats every `BeamSignal.period`.
        enum SignalPattern {
            /// Seconds each group is lit, in the order flashed: long, short, middle (so the answer is stone, tide, wind, not the old tide, wind, stone).
            static let groupSeconds: [Float] = [2.6, 0.7, 1.5]
            /// Dark between groups (long enough that two groups never read as one), dark before the first group (after the rest), and dark after the last before the sweeps begin again.
            static let gapSeconds: Float = 1.4, leadSeconds: Float = 0.8, tailSeconds: Float = 2.6
            /// The ranks of the groups by length (0 = shortest): the plates read lengths, not positions.
            static var ranks: [Int] { groupSeconds.map { g in groupSeconds.filter { $0 < g }.count } }
        }
        static var signalDoorPoint: SIMD3<Float> { lighthouse + SIMD3(0, 0, Lighthouse.wallR(2.0) + 1) }

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

        /// The Tide Archive (S04.1, builder A's minimal network for the new world: builder B's S04.5 / S04.8 refine it): the route from the lamp end up to the prism chamber, the east quay's approach,
        /// and a plaza at each landmark.
        static let tideArchive: NavNetwork = {
            let p = ArchiveLayout.path.map(xz)
            let w = trailHalfWidth
            let trails = [
                NavNetwork.Trail("the terraces", p, halfWidth: w),
                NavNetwork.Trail("the east quay", ArchiveLayout.eastApproach.map(xz), halfWidth: w),
                NavNetwork.Trail("the sluice walk", ArchiveLayout.sluiceWalk.map(xz), halfWidth: 4.5),
            ]
            let plazas = [
                NavNetwork.Plaza(name: "lamp end quay", center: xz(ArchiveLayout.lampEnd), radius: 16),
                NavNetwork.Plaza(name: "open end quay", center: xz(ArchiveLayout.openEnd), radius: 16),
                NavNetwork.Plaza(name: "landing", center: xz(ArchiveLayout.landing), radius: 18),
                NavNetwork.Plaza(name: "the stacks", center: xz(ArchiveLayout.stacks), radius: 24),
                NavNetwork.Plaza(name: "the gallery and its sluices", center: xz(ArchiveLayout.greatLedger), radius: 36),
                NavNetwork.Plaza(name: "the upper lamp", center: xz(ArchiveLayout.upperLamp), radius: 16),
                NavNetwork.Plaza(name: "the dome", center: xz(ArchiveLayout.dome), radius: 24),
                NavNetwork.Plaza(name: "the prism chamber", center: xz(ArchiveLayout.prismChamber), radius: 18),
            ]
            return NavNetwork(trails: trails, plazas: plazas, vantages: [], spawn: xz(ArchiveLayout.lampEnd), arrivals: [xz(ArchiveLayout.lampEnd), xz(ArchiveLayout.openEnd)])
        }()
    }
}

// MARK: The Tide Archive (S04.1, builder A)
/// Landmark positions of the Tide Archive (S04: a half-drowned observatory of ledger terraces; docs/plans/S04-phase2-tide-archive.md). Like the Glass Wood's, every height is read from the world's own base
/// terrain function (`ArchiveTerrain.base`), so a landmark sits at the natural height of the ground round it. The world runs from the SOUTH QUAYS (where the player arrives) up four terraces to the
/// brass dome and the prism chamber at the north end; the Great Ledger gallery is a sunken court on the second terrace's east side, behind the three sluices along its west wall.
enum ArchiveLayout {
    static let noise = Noise(seed: 20_26)
    static func groundY(_ x: Float, _ z: Float) -> Float { ArchiveTerrain.base(noise, x, z) }
    static func point(_ x: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x, groundY(x, z), z) }

    /// Where the two routes land (S02 section 3: the lamp end for Ilse, the open end for Oren): two quays at the south edge, either side of the tide steps.
    static let lampEnd = point(-46, 128)
    static let openEnd = point(46, 128)
    /// The first plaza, above the quays' landing: the tide steps start here.
    static let landing = point(0, 92)
    /// The shelves of ledgers on the second terrace, west.
    static let stacks = point(-58, 30)
    /// The Great Ledger gallery's floor (a sunken court on the second terrace, east). The three SLUICE ROOMS are sunken stone chambers on the lowest terrace, open to the sea: the tide floods them by
    /// depth, so each can be reached only while the water in it is wadeable (S04.2): the tide room's floor is just under the terrace (reachable most of the cycle), the wind room's lower, the stone room's lowest
    /// (reachable only near low tide). `sluiceFloors` are their floor heights (the ground there is flat at that height: pads with a short blend).
    static let greatLedgerXZ = SIMD2<Float>(70, -30)
    static let greatLedger = point(greatLedgerXZ.x, greatLedgerXZ.y)
    static let sluiceFloors: [Float] = [0.8, -0.2, -0.9]      // the source of truth: `Tide.windows` (B's Q33) are derived from these
    /// A sluice room is flat to `sluiceFlat` m round its centre and eases back into the terrace over `sluiceBlend` m more (the pad and the terrain's pit use the same two numbers: walls under 0.5).
    static let sluiceFlat: Float = 6, sluiceBlend: Float = 10
    static let sluiceSites: [SIMD2<Float>] = [SIMD2(-72, 108), SIMD2(72, 108), SIMD2(0, 118)]
    static let sluices: [SIMD3<Float>] = zip(sluiceSites, sluiceFloors).map { SIMD3($0.x, $1, $0.y) }      // not read from the terrain: the terrain is sunk to these heights
    /// S04.3 follow-up: where builder B's interactables stand (the Pending-A items): the six pages (10-15) in the order the route meets them, the chain map's plinth, the shadow-play wall and the lantern at
    /// each side of it (`tableauLantern[0]` Ilse's side, west; `[1]` Oren's, east), the two tools lying in the world, and the prism ring (the prism's own position).
    /// F09.1: every spot is ON the guided route (within ~3 m of its centreline) and in story order: 10 landing, 11 lectern at the stacks, 12 the Roll of Keepers' desk on the way to the gallery, 13 outside the prism chamber,
    /// 14 under the dome, 15 on the Great Ledger gallery's floor (appears once the water is down). `TideSpots` derives the interaction boxes from these, so a prop and its box cannot drift apart again.
    static let pageSpots: [SIMD3<Float>] = [besideRoute(9, 98), besideRoute(-54, 27), besideRoute(35, -23), besideRoute(3, -120), besideRoute(-9, -94), point(greatLedgerXZ.x - 4, greatLedgerXZ.y)]
    /// The spot on the route's graded strip nearest (x, z), then `offset` m across it from the centreline (towards the original spot): grass does not grow within 1.2 m of the route (`Terrain.pathWeight`), so a page lying
    /// there has no blade through it (#95), and the player passes it at arm's length.
    static func besideRoute(_ x: Float, _ z: Float, offset: Float = 0.8) -> SIMD3<Float> {
        let p = SIMD2<Float>(x, z)
        var best = (d: Float.infinity, q: p)
        for k in 0..<(path.count - 1) {
            let a = SIMD2(path[k].x, path[k].z), b = SIMD2(path[k + 1].x, path[k + 1].z), ab = b - a
            let t = min(max(simd_dot(p - a, ab) / max(simd_dot(ab, ab), 1e-6), 0), 1), q = a + ab * t
            if simd_length(p - q) < best.d { best = (simd_length(p - q), q) }
        }
        let away = p - best.q, d = simd_length(away)
        let q = d > 1e-3 ? best.q + away / d * offset : best.q + SIMD2(offset, 0)
        return point(q.x, q.y)
    }
    static let chainMap = besideRoute(-11, -100, offset: 2.4)
    static let tableauWall = point(44, -44), tableauHalfWidth: Float = 4.0
    static let tableauLantern: [SIMD3<Float>] = [point(44 - 5.6, -42), point(44 + 5.6, -42)]
    static let findFork = point(-42, 43), findLens = point(-27, -62)
    static let prismRing = prismChamber + SIMD3(0, 1.75, 0)
    /// The third terrace's lamp stand and the way up to the dome.
    static let upperLamp = point(-36, -56)
    static let dome = point(0, -104)
    static let prismChamber = point(0, -132)

    /// The walking route, in order: either quay -> landing -> the stacks -> the sluices' approach -> the gallery -> the third terrace -> the dome -> the prism chamber.
    static let path: [SIMD3<Float>] = [
        lampEnd, point(-24, 110), landing, point(-30, 60), stacks, point(-14, 0), point(20, -20), point(44, -30), greatLedger, point(44, -30), point(10, -44), upperLamp, point(-12, -80), dome, prismChamber,
    ]
    /// The east quay's approach joins the route at the landing.
    static let eastApproach: [SIMD3<Float>] = [openEnd, point(24, 110), landing]
    /// The sluice walk: the three sluice rooms in a loop off the landing (tide room west, wind room east, stone room between, a little up the first rise).
    static let sluiceWalk: [SIMD3<Float>] = [landing, sluices[0], sluices[2], sluices[1], landing]

    static let pads: [Layout.Pad] = [
        Layout.Pad(center: lampEnd, radius: 9), Layout.Pad(center: openEnd, radius: 9), Layout.Pad(center: landing, radius: 12),
        Layout.Pad(center: stacks, radius: 16), Layout.Pad(center: greatLedger, radius: 22), Layout.Pad(center: upperLamp, radius: 9),
        Layout.Pad(center: dome, radius: 18), Layout.Pad(center: prismChamber, radius: 12),
    ] + sluices.map { Layout.Pad(center: $0, radius: sluiceFlat, blend: sluiceBlend) }
}

/// S05.1 (builder A): Ilse's site in the Tide Archive, the landmarks the props and builder B's interaction boxes both read (nothing is spelled out twice). The SHELF BAYS are the five units of the
/// stacks' first row (the row that faces the route: `ArchiveProps.addStacks` puts row 0 at `stacks.x - 9`, five units `stackSpacing` apart); the LEDGER ROOM is a small walled room off the route
/// on the stacks' pad north-west of the bays, where the ground is flat and clear of the walked route, its door in the south wall (towards the bays and the route); the three PIPES stand in the sluice rooms, in front of the gate and clear of the wheel, the lamp and the walking line.
extension ArchiveLayout {
    static let bayCount = 5
    static let stackSpacing: Float = 2.6
    /// Bay k's unit centre on the ground (x, z); the unit faces east (toward the route).
    static func bayXZ(_ k: Int) -> SIMD2<Float> { SIMD2(stacks.x - 9, stacks.z + (Float(k) - Float(bayCount - 1) / 2) * stackSpacing) }
    static func bay(_ k: Int) -> SIMD3<Float> { let p = bayXZ(k); return point(p.x, p.y) }
    /// The ledger room: centre of its floor, half sizes (x, z), the door's half width. The door is in the south wall (+z).
    static let ledgerRoom = point(-63, 16)
    static let ledgerHalf = SIMD2<Float>(2.6, 2.1)
    static let ledgerDoorHalf: Float = 0.9
    /// The middle of the door's opening on the floor, and the two things inside: the page on its desk and the sluice-room key's stand.
    static var ledgerDoor: SIMD3<Float> { ledgerRoom + SIMD3(0, 0, ledgerHalf.y) }
    static var ledgerPage: SIMD3<Float> { ledgerRoom + SIMD3(0, 1.0, -1.2) }
    static var ledgerKey: SIMD3<Float> { ledgerRoom + SIMD3(1.2, 0.95, -1.3) }
    /// Where pipe k stands in its sluice room (the gate faces south; the wheel is east, the lamp west, so the pipe is in front of the gate's west side).
    static let pipeOffset = SIMD3<Float>(-1.9, 0, 3.2)
    static func pipe(_ k: Int) -> SIMD3<Float> { sluices[k] + pipeOffset }
}

/// S05.2 (builder A): Oren's site in the Tide Archive. The ORRERY stands on the dome's pad, in front of the dome's south face (the door side), off the walked route (the route's last leg runs about 13 m to its
/// west); the three dome WINDOWS are portholes in the drum above the door, at the bearings below (radians from south, + east), 9.2 m from the dome's axis (`ArchiveProps.addDome`'s drum radius).
extension ArchiveLayout {
    static let orrery = point(5, -88)
    static let domeDrum: Float = 9.2
    static let domeWindowBearing: [Float] = [-0.46, 0, 0.46]
    /// Window k's (x, z) on the drum's surface.
    static func domeWindowXZ(_ k: Int) -> SIMD2<Float> { let b = domeWindowBearing[k]; return SIMD2(dome.x + sin(b) * domeDrum, dome.z + cos(b) * domeDrum) }
}

/// S05.4 (start, builder A): the DORMANT MODELS each route sees of the other's site from its own quay. Ilse's site is the stacks (the east quay, Oren's, looks across the terraces at them): a tall BELL MAST
/// stands behind the bays, an unlit lantern and a bell at its top. Oren's site is the dome (the west quay, Ilse's, sees the brass dome on the third terrace): a slender dark glass SPIRE stands beside it, the prism
/// chamber's glass in miniature, and it glows as the dome's windows light (`DomeWindows.set`). Both stand clear of every walked line.
extension ArchiveLayout {
    static let bellMast = point(-72, 36)
    static let prismSpire = point(18, -114)
}

extension ArchiveLayout {
    /// Grass-free discs beyond the pads' own (`Renderer`'s terrain texture reads them): the ledger room's floor (S05.2: grass came up through the slab, Q62) with a short soft edge.
    static var bareDiscs: [(center: SIMD2<Float>, radius: Float)] { [(SIMD2(ledgerRoom.x, ledgerRoom.z), simd_length(ledgerHalf) + 0.6)] }
}

/// S05.4 (A5, builder A): the two VANTAGE STATIONS, one for each route, where the other route's site can be read across the island's terraces (Q91). Station 0 is Ilse's: where the way to the dome climbs onto the third terrace's rim,
/// the first place on the walked line from which the WHOLE orrery (its dial's edge, the highest arm's tip) and the dome's three windows clear the rim by 0.3 m, 30 m off (from the plain below, the orrery's hub is in sight at 80 m but the machine is hidden by the rim); station 1 is Oren's: on the landing's way up to the stacks,
/// where the five shelf bays and the bell mast are in line of sight (about 45 m off). `vantageStand` is the walked line; the post (a stone pedestal with a brass far-glass aimed at the target) stands `vantageSide` m
/// to the side that faces the target. Both numbers are checked by a terrain ray test in the selftest (`vantage`), so a change to the terraces cannot silently close a view.
extension ArchiveLayout {
    static let vantageStand: [SIMD3<Float>] = [point(-21.3, -70.7), point(-34, 55.7)]
    static let vantageSide: Float = 2.3, vantageAhead: Float = 3.0       // beside the walked line and a little ahead along the sight line, so the post is in the picture when the player looks at the target
    /// What station k looks at: the orrery's arms, and the middle of the five bays.
    static var vantageAim: [SIMD3<Float>] {
        return [SIMD3(orrery.x, orrery.y + 1.3, orrery.z), bay(2) + SIMD3(0, 2.0, 0)]
    }
    /// The post's centre on the ground: `vantageSide` m from the stand, at right angles to the walked line there, on the side that faces the target (so the glass points across the post, not back over the path).
    static func vantagePost(_ k: Int) -> SIMD3<Float> {
        let s = vantageStand[k], p = SIMD2(s.x, s.z), a = vantageAim[k]
        var best = (d: Float.infinity, dir: SIMD2<Float>(1, 0))
        for i in 0..<(path.count - 1) {
            let u = SIMD2(path[i].x, path[i].z), v = SIMD2(path[i + 1].x, path[i + 1].z), uv = v - u
            let t = min(max(simd_dot(p - u, uv) / max(simd_dot(uv, uv), 1e-6), 0), 1), d = simd_length(p - (u + uv * t))
            if d < best.d { best = (d, simd_normalize(uv)) }
        }
        var perp = SIMD2<Float>(-best.dir.y, best.dir.x)
        if simd_dot(perp, SIMD2(a.x, a.z) - p) < 0 { perp = -perp }
        let sight = simd_normalize(SIMD2(a.x, a.z) - p)
        return point(p.x + perp.x * vantageSide + sight.x * vantageAhead, p.y + perp.y * vantageSide + sight.y * vantageAhead)
    }
}

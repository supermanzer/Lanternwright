import Foundation
import simd

/// The tuned look of the game (T1.18). Everything an art pass touches lives here so it can be adjusted in one place.
enum LookDefaults {
    static let sunElevation: Float = 8
    static let sunAzimuth: Float = 250
    static let exposure: Float = 1.15
    static let bloomStrength: Float = 0.06
    static let fogDensity: Float = 0.0016
    static let fogHeightFalloff: Float = 0.010
    static let waveStrength: Float = 1.0
    static let grassRadius: Float = 42
    static let godRayStrength: Float = 0.32
    static let aoStrength: Float = 0.9
    static let aoRadius: Float = 1.6
    static let grassCell: Float = 0.29
}

/// Command-line options. Parsed once in main.swift.
struct LaunchOptions {
    var screenshotPath: String?
    var viewName: String?
    var camera: Camera?
    var width = 1600
    var height = 900
    var frames = 3
    /// Eye adaptation is always on in the game; screenshots keep a fixed exposure (deterministic) unless this is set.
    var autoExposure = false
    /// Sun elevation / azimuth in degrees (azimuth measured clockwise from north).
    var sunElevation: Float = LookDefaults.sunElevation
    var sunAzimuth: Float = LookDefaults.sunAzimuth
    var selftest: String?
    var dumpLUTPath: String?
    var debugView: String?
    var dumpAudioPath: String?
    var showFPS = false
    var state: String?
    var world: WorldKind?
    var newGame = false
    var showFeedback = false
    var showFeedbackDir = false
    var dumpOverlayBase: String?
    var benchFrames: Int?
    var auditPropsOut: String?
    var auditProps = false
    var listPages = false
    var clock: Float = 12
    var auditSlopes = false
    var approachTarget: String?
    var approachRange: (start: Float, min: Float, factor: Float)?
    var hardLOD = false
    var approachOut: String?

    static let usage = """
    Lanternwright: an exploration and puzzle game.

    Usage: Lanternwright [options]
      --screenshot <path.png>      Render headless to a PNG and exit (no window)
      --view <name>                Viewpoint: dock overview summit shore islet; gw-arrival gw-overview gw-court gw-court-high gw-chimes gw-altar
      --camera x,y,z,yaw,pitch     Explicit camera (radians for yaw/pitch)
      --size WxH                   Output size for --screenshot (default 1600x900)
      --auto-exposure              Let screenshots adapt their exposure to the scene (default: fixed)
      --frames N                   Frames rendered before capture (default 3)
      --sun elevDeg,azimuthDeg     Sun position (default 8,250)
      --debug <name>               Debug view: depth, shadow, albedo, ambient, cascade, ao, noao
      --dump-audio <path.wav>      Render 24 s of the soundscape to a WAV (play with afplay) and exit
      --world <name>               World to render: varrow, glass (views named gw-* imply glass)
      --state <name>               World state: solved, mirrors, chimes, both, mirrorswrong, tide, tidewind
      --dump-overlay <base>        Render crosshair/journal/end/intro overlays to <base>-*.png and exit
      --approach <target|all> <out>  Continuous-detail measurement: walk toward a target, write a contact sheet and luma/high-frequency numbers
      --approach-range <start> <min> <factor>  with --approach: override the distances (e.g. 90 30 0.97 to walk through the tree LOD band)
      --hard-lod                   Debug: switch tree LODs instantly (the pre-R09 behaviour), for before/after measurements
      --clock T                    Screenshot clock in seconds (default 12): the wind, the grass and the trees depend on it
      --list-pages                 Print where each of the eight journal pages stands (world, lectern foot, what makes it appear)
      --audit-props [out.md]       List every scene item with its materials and flag large props drawn flat (docs/PROPS.md)
      --controls-md                Print the README controls table, generated from App/Controls.swift
      --feedback                   Print all saved player feedback and exit
      --feedback-dir               Print the feedback folder and exit
      --new                        Start a new game, ignoring (and later overwriting) the save
      --fps                        Show frames per second in the window title
      --bench N                    Render N offscreen frames at --size and report GPU time
      --dump-lut <path.png>        Write the baked sky LUT (256x128) to a PNG and exit
      --selftest [name]            Run internal checks and exit
      --help                       Show this text
    """

    static func parse(_ args: [String]) -> LaunchOptions {
        var o = LaunchOptions()
        var i = 1
        func next() -> String {
            i += 1
            guard i < args.count else { fail("missing value for \(args[i - 1])") }
            return args[i]
        }
        while i < args.count {
            switch args[i] {
            case "--screenshot": o.screenshotPath = next()
            case "--view": o.viewName = next()
            case "--camera":
                let v = next().split(separator: ",").compactMap { Float($0) }
                guard v.count == 5 else { fail("--camera expects x,y,z,yaw,pitch") }
                o.camera = Camera(position: SIMD3(v[0], v[1], v[2]), yaw: v[3], pitch: v[4])
            case "--size":
                let v = next().lowercased().split(separator: "x").compactMap { Int($0) }
                guard v.count == 2, v[0] > 0, v[1] > 0 else { fail("--size expects WxH") }
                (o.width, o.height) = (v[0], v[1])
            case "--frames":
                guard let n = Int(next()), n > 0 else { fail("--frames expects a positive integer") }
                o.frames = n
            case "--sun":
                let v = next().split(separator: ",").compactMap { Float($0) }
                guard v.count == 2 else { fail("--sun expects elevationDeg,azimuthDeg") }
                (o.sunElevation, o.sunAzimuth) = (v[0], v[1])
            case "--debug": o.debugView = next()
            case "--auto-exposure": o.autoExposure = true
            case "--dump-audio": o.dumpAudioPath = next()
            case "--state": o.state = next()
            case "--world":
                let w = next()
                guard let k = (w == "glass" ? WorldKind.glassWood : WorldKind(rawValue: w)) else { fail("--world expects varrow or glass") }
                o.world = k
            case "--new": o.newGame = true
            case "--feedback": o.showFeedback = true
            case "--feedback-dir": o.showFeedbackDir = true
            case "--dump-overlay": o.dumpOverlayBase = next()
            case "--audit-slopes": o.auditSlopes = true
            case "--list-pages": o.listPages = true
            case "--clock":
                guard let t = Float(next()) else { fail("--clock expects seconds") }
                o.clock = t
            case "--audit-props": o.auditProps = true; if i + 1 < args.count, !args[i + 1].hasPrefix("--") { o.auditPropsOut = next() }
            case "--approach": o.approachTarget = next(); o.approachOut = next()
            case "--approach-range": o.approachRange = (Float(next()) ?? 80, Float(next()) ?? 30, Float(next()) ?? 0.97)
            case "--hard-lod": o.hardLOD = true
            case "--controls-md": print(Controls.markdownTable()); exit(0)
            case "--fps": o.showFPS = true
            case "--bench":
                guard let n = Int(next()), n > 0 else { fail("--bench expects a positive integer") }
                o.benchFrames = n
            case "--dump-lut": o.dumpLUTPath = next()
            case "--selftest":
                if i + 1 < args.count, !args[i + 1].hasPrefix("--") { o.selftest = next() } else { o.selftest = "all" }
            case "--help", "-h":
                print(usage); exit(0)
            default:
                fail("unknown option \(args[i])")
            }
            i += 1
        }
        return o
    }

    private static func fail(_ msg: String) -> Never {
        FileHandle.standardError.write(Data("error: \(msg)\n\n\(usage)\n".utf8))
        exit(2)
    }
}

/// Named viewpoints used for screenshots and acceptance checks (see docs/TASKS.md §0).
/// Positions are placeholders until the terrain exists (T1.5); refine them in T1.18.
enum Viewpoints {
    /// `tree-close`: eye height, 4.5 m from a real conifer on the lower slope (the nearest site to the dock that is at least 25 m inland),
    /// looking at its crown. Needs the terrain, so it is not a fixed viewpoint.
    static func treeClose(terrain: Terrain) -> Camera {
        let sites = Island.treeSites(terrain: terrain).prefix(420).filter { terrain.sampleHeight(x: $0.x, z: $0.y) > 6 && terrain.sampleHeight(x: $0.x, z: $0.y) < 26 }
        let from = SIMD2(Layout.dockShore.x, Layout.dockShore.z)
        let tree = sites.filter { simd_length($0 - from) > 25 }.min { simd_length($0 - from) < simd_length($1 - from) } ?? SIMD2(Layout.tideStone.x, Layout.tideStone.z)
        let toward = simd_normalize(from - tree)                     // stand on the dock side of the tree so the light reaches the crown
        let cam = tree + toward * 5.5
        let g = terrain.sampleHeight(x: cam.x, z: cam.y)
        let d = SIMD2(tree.x - cam.x, tree.y - cam.y)
        let cam3 = Camera(position: SIMD3(cam.x, g + 1.7, cam.y), yaw: atan2(d.x, -d.y), pitch: 0.55)
        return cam3
    }

    /// `tree-base-up` / `tree-base-down` (+ `-2m`): the foot of the conifer on the steepest ground (at most about 35 degrees), seen from 0.5 m (or 2 m) clear
    /// of the trunk's surface, on the uphill or the downhill side, at knee height, looking at the trunk's base (F02 G1: no collar, no gap).
    static func treeBase(terrain t: Terrain, name: String) -> Camera? {
        guard name.hasPrefix("tree-base-") else { return nil }
        let up = name.hasPrefix("tree-base-up"), far = name.hasSuffix("-2m")
        let sites = Island.treeSites(terrain: t).prefix(420).filter { t.normal(x: $0.x, z: $0.y).y > 0.80 && t.sampleHeight(x: $0.x, z: $0.y) > 3 }
        guard let tree = sites.min(by: { t.normal(x: $0.x, z: $0.y).y < t.normal(x: $1.x, z: $1.y).y }) else { return nil }
        let n = t.normal(x: tree.x, z: tree.y)
        let down = simd_normalize(SIMD2(n.x, n.z) + SIMD2(1e-5, 0))               // the horizontal part of the normal points downhill
        let dist: Float = (far ? 2.0 : 0.5) + 0.5
        let cam = tree + down * (up ? -dist : dist)
        let eye = t.sampleHeight(x: cam.x, z: cam.y) + (far ? 0.9 : 0.45)
        let target = SIMD3(tree.x, t.sampleHeight(x: tree.x, z: tree.y) + 0.1, tree.y)
        let d = target - SIMD3(cam.x, eye, cam.y)
        return Camera(position: SIMD3(cam.x, eye, cam.y), yaw: atan2(d.x, -d.z), pitch: asin(d.y / simd_length(d)))
    }

    /// `pillar-close` / `pillar-far`: the islet's broken pillar, its stump and fallen drum, from the lens side at 0.9 m (or 3 m) from the break (F02 G2).
    static func pillarClose(terrain t: Terrain, far: Bool) -> Camera {
        let c = Layout.isletCenter
        let a = Float(3) / 5 * 2 * .pi + 0.3
        let out = SIMD3<Float>(cos(a), 0, sin(a)), side = SIMD3<Float>(-sin(a), 0, cos(a))
        let focus = c + out * 7.4 + SIMD3(0, 0.3, 0)
        let cam = focus + out * (far ? 2.6 : 0.6) - side * (far ? 3.0 : 1.9)
        let eye = SIMD3(cam.x, t.sampleHeight(x: cam.x, z: cam.z) + (far ? 1.5 : 0.9), cam.z)
        let d = focus - eye
        return Camera(position: eye, yaw: atan2(d.x, -d.z), pitch: asin(d.y / simd_length(d)))
    }

    /// `page-stand-N` / `page-far-N` (home pages 1-4) and `gw-page-stand-N` / `gw-page-far-N` (Glass Wood pages 5-8): the page's lectern seen from 3 m or 14 m
    /// on the side it faces, at eye height (F02 P0: could a player walking past miss it?).
    static func pageView(scene: Scene, name: String) -> Camera? {
        var n = name
        if n.hasPrefix("gw-") { n.removeFirst(3) }
        guard n.hasPrefix("page-stand-") || n.hasPrefix("page-far-"), let number = Int(n.split(separator: "-").last ?? "") else { return nil }
        let far = n.hasPrefix("page-far-")
        let home = number <= 4
        let base = home ? PuzzleProps.pageBase(number, terrain: scene.terrain) : GlassPuzzleProps.pageBase(number)
        let face = home ? PuzzleProps.pageFacing(number, terrain: scene.terrain) : GlassPuzzleProps.pageFacing(number)
        let yaw = PageStands.yaw(from: base, toward: face)
        let out = SIMD3<Float>(sin(yaw), 0, cos(yaw))
        let d: Float = far ? 14 : 3
        let cam = base + out * d
        let eye = SIMD3(cam.x, scene.groundHeight(x: cam.x, z: cam.z) + 1.7, cam.z)
        let target = base + SIMD3(0, PageStands.pageHeight, 0)
        let v = target - eye
        return Camera(position: eye, yaw: atan2(v.x, -v.z), pitch: asin(v.y / simd_length(v)))
    }

    /// `fallen-close`: 4 m from the first fallen log (a conifer lying on its side), looking at its root end (F02 G1 follow-up: no buried stub may stick out of it).
    static func fallenClose(terrain t: Terrain) -> Camera? {
        let sites = Island.treeSites(terrain: t).prefix(420)
        guard let (_, p) = sites.enumerated().first(where: { Island.noise.unit(Int32($0.offset), 83) > 0.985 }) else { return nil }
        let g = t.sampleHeight(x: p.x, z: p.y)
        let cam = SIMD3(p.x + 3.0, g + 1.4, p.y + 3.0), target = SIMD3(p.x, g + 0.3, p.y)
        let d = target - cam
        return Camera(position: cam, yaw: atan2(d.x, -d.z), pitch: asin(d.y / simd_length(d)))
    }

    /// The Glass Wood's pool (F02 G3, note #29): `gw-pool-user` is the user's own spot and view (4.7, -3.4, looking down at the waterline), `gw-pool` stands on the bank
    /// 4 m from the water looking across it, `gw-pool-shelf` stands in the shallows looking along the shore, `gw-pool-far` is the view from the path to the pool.
    static func poolView(terrain t: Terrain, name: String) -> Camera? {
        func ground(_ x: Float, _ z: Float) -> Float { t.sampleHeight(x: x, z: z) }
        let c = GlassTerrain.pool
        switch name {
        case "gw-pool-user": return Camera(position: SIMD3(4.7, ground(4.7, -3.4) + Player.eyeHeight, -3.4), yaw: -2.94, pitch: -1.09)
        case "gw-pool":
            let p = SIMD2(c.x, c.y) + SIMD2(0, -33)
            return Camera(position: SIMD3(p.x, ground(p.x, p.y) + Player.eyeHeight, p.y), yaw: .pi, pitch: -0.42)
        case "gw-pool-shelf":
            let p = SIMD2(c.x, c.y) + SIMD2(0, -26)
            return Camera(position: SIMD3(p.x, ground(p.x, p.y) + 1.4, p.y), yaw: -1.2, pitch: -0.35)
        case "gw-pool-far":
            let p = SIMD2(c.x, c.y) + SIMD2(-12, -70)
            return Camera(position: SIMD3(p.x, ground(p.x, p.y) + 3.0, p.y), yaw: 2.9, pitch: -0.12)
        default: return nil
        }
    }

    /// `page-close`: 0.8 m above the journal page on the tide stone's plinth, looking down at it (R06).
    static func pageClose(terrain: Terrain) -> Camera {
        let p = PuzzleProps.pagePosition(2, terrain: terrain)
        return Camera(position: p + SIMD3(0.0, 0.8, 0.45), yaw: 0, pitch: -1.0)
    }

    /// `lantern-close`: 1.6 m from the stone lantern that stands on the steepest ground, at eye height, looking at its base (F01 W3.5).
    static func lanternClose(scene: Scene) -> Camera {
        let t = scene.terrain!
        let lanterns = scene.placed.filter { $0.kind == "lantern" }.map { p -> SIMD2<Float> in
            let n = Float(p.low.count); return SIMD2(p.low.map(\.x).reduce(0, +) / n, p.low.map(\.z).reduce(0, +) / n)
        }
        let c = lanterns.min { t.normal(x: $0.x, z: $0.y).y < t.normal(x: $1.x, z: $1.y).y } ?? SIMD2(0, 0)
        let down = simd_normalize(SIMD2(-t.normal(x: c.x, z: c.y).x, -t.normal(x: c.x, z: c.y).z) + SIMD2(1e-4, 0))       // the way the ground falls away
        let cam = c + down * 1.7
        let y = t.sampleHeight(x: cam.x, z: cam.y) + 1.1
        let target = SIMD3<Float>(c.x, t.sampleHeight(x: c.x, z: c.y) + 0.3, c.y)
        let d = target - SIMD3(cam.x, y, cam.y)
        return Camera(position: SIMD3(cam.x, y, cam.y), yaw: atan2(d.x, -d.z), pitch: asin(d.y / simd_length(d)))
    }

    /// `ground-grass`, `ground-sand`, `ground-edge` (the grass-sand interface), `ground-slope`, `ground-islet`, each optionally followed by `-1m` or `-5m`
    /// (default: eye 0.3 m above the ground looking down). F01 W0/W1: the user lies close to things, so the ground is judged at 0.3, 1 and 5 m.
    static func ground(_ name: String, terrain t: Terrain) -> Camera? {
        guard name.hasPrefix("ground-") else { return nil }
        var kind = String(name.dropFirst(7)), h: Float = 0.3, pitch: Float = -0.95
        if kind.hasSuffix("-1m") { kind = String(kind.dropLast(3)); h = 1.0; pitch = -0.62 }
        else if kind.hasSuffix("-5m") { kind = String(kind.dropLast(3)); h = 5.0; pitch = -0.30 }
        func find(near: SIMD2<Float>, radius: Float, _ ok: (Float, Float, Float, Float) -> Bool) -> SIMD2<Float> {
            var best = near, bestD = Float.infinity
            var x = near.x - radius
            while x <= near.x + radius {
                var z = near.y - radius
                while z <= near.y + radius {
                    let d = simd_length(SIMD2(x, z) - near)
                    if d < bestD, ok(x, z, t.sampleHeight(x: x, z: z), t.normal(x: x, z: z).y) { bestD = d; best = SIMD2(x, z) }
                    z += 2
                }
                x += 2
            }
            return best
        }
        let p: SIMD2<Float>
        switch kind {
        case "grass": p = find(near: SIMD2(20, 40), radius: 150) { x, z, y, ny in y > 8 && y < 30 && ny > 0.96 && t.pathDistance(x: x, z: z) > 10 && t.duffAt(x: x, z: z) < 0.01 }
        case "sand": p = find(near: SIMD2(Layout.dockShore.x - 25, Layout.dockShore.z - 12), radius: 80) { x, z, y, ny in y > 0.5 && y < 1.4 && ny > 0.985 && t.pathDistance(x: x, z: z) > 6 }
        case "edge": p = find(near: SIMD2(Layout.dockShore.x - 30, Layout.dockShore.z - 25), radius: 90) { x, z, y, ny in y > 2.2 && y < 2.5 && ny > 0.97 && t.pathDistance(x: x, z: z) > 6 }
        case "slope": p = find(near: SIMD2(-60, -10), radius: 200) { x, z, y, ny in y > 10 && ny > 0.55 && ny < 0.75 && t.pathDistance(x: x, z: z) > 6 }
        case "islet": p = SIMD2(Layout.isletCenter.x + 6, Layout.isletCenter.z + 4)
        default: return nil
        }
        let y = t.sampleHeight(x: p.x, z: p.y) + h
        return Camera(position: SIMD3(p.x, y, p.y), yaw: 0.6, pitch: pitch)
    }

    /// `rock-close`: 2.2 m from the biggest-looking rock nearest the dock path, at 1.2 m height (F01 W3.2).
    static func rockClose(scene: Scene) -> Camera {
        let t = scene.terrain!
        let from = SIMD2(Layout.dockShore.x, Layout.dockShore.z)
        let rocks = scene.placed.filter { $0.kind == "rock" }.map { p -> (c: SIMD2<Float>, w: Float) in
            let xs = p.low.map(\.x), zs = p.low.map(\.z)
            return (SIMD2((xs.min()! + xs.max()!) / 2, (zs.min()! + zs.max()!) / 2), (xs.max()! - xs.min()!) + (zs.max()! - zs.min()!))
        }.filter { $0.w > 1.2 }
        let r = rocks.min { simd_length($0.c - from) < simd_length($1.c - from) }?.c ?? from
        let away = simd_normalize(from - r + SIMD2(1e-3, 0))
        let cam = r + away * 3.2
        let y = t.sampleHeight(x: cam.x, z: cam.y) + 1.3
        let d = SIMD3(r.x, t.sampleHeight(x: r.x, z: r.y) + 0.5, r.y) - SIMD3(cam.x, y, cam.y)
        return Camera(position: SIMD3(cam.x, y, cam.y), yaw: atan2(d.x, -d.z), pitch: asin(d.y / simd_length(d)))
    }

    static func named(_ name: String) -> Camera? {
        switch name {
        case "dock":     return Camera(position: SIMD3(175, 2.5, 205), yaw: -0.75, pitch: 0.02)
        // Lighthouse close-ups (R03). The tower stands at Layout.lighthouse with its door on the +Z (south) side; ground y = 68.
        case "lh-door":  return Camera(position: SIMD3(-30, 70.75, -41.0), yaw: 0, pitch: 0.06)        // 2.8 m back from the door, on the approach: the arch, jambs, threshold and steps in frame (R06; the 0.8 m view showed only planks)
        case "lh-arch":  return Camera(position: SIMD3(-30, 69.7, -40.0), yaw: 0, pitch: 0.12)         // 3.8 m back: the whole arched doorway
        case "lh-base":  return Camera(position: SIMD3(-25.85, 69.4, -43.85), yaw: -0.38, pitch: 0.05)
        case "lh-mid":   return Camera(position: SIMD3(-30, 69.7, -32), yaw: 0, pitch: 0.55)
        case "lh-top":   return Camera(position: SIMD3(-12, 69.7, -20), yaw: -0.57, pitch: 0.65)
        case "lh-glass": return Camera(position: SIMD3(-24, 95.5, -42), yaw: -0.785, pitch: -0.07)
        // A resonance stone seen from 3 m, at the height of its glyph (R04-7).
        case "stone-close": return Camera(position: Layout.tideStone + SIMD3(1.2, 1.9, 3.2), yaw: -0.3, pitch: -0.12)
        case "material-sheet": return Camera(position: Props.sheetOrigin + SIMD3(10.5, 0.25, 12.5), yaw: 0, pitch: 0, fovY: 38 * .pi / 180)     // every material, a sphere and a slab (F01 W0)
        // The dock for F01 W2: 1 m above the planks looking down, low from the beach, and from the water under the deck.
        case "dock-close": return Camera(position: SIMD3(168.5, 1.9, 198.0), yaw: -0.74, pitch: -0.75)
        case "dock-side":  return Camera(position: SIMD3(150, 1.0, 196), yaw: 1.08, pitch: 0.03)
        case "dock-under": return Camera(position: SIMD3(170.5, -0.1, 199.5), yaw: -0.74, pitch: 0.28)
        case "overview": return Camera(position: SIMD3(330, 150, 330), yaw: -0.76, pitch: -0.19)
        case "summit":   return Camera(position: SIMD3(-30, 70, -32), yaw: .pi, pitch: -0.05)
        case "shore":    return Camera(position: SIMD3(150, 3.2, 172), yaw: -1.95, pitch: 0.03)
        case "islet":    return Camera(position: SIMD3(-35, 3.5, -222), yaw: 0.0, pitch: 0.0)
        case "gw-arrival":  return Camera(position: GlassLayout.arrival + SIMD3(0, Player.eyeHeight, 4), yaw: 0, pitch: 0.06)
        case "gw-overview": return Camera(position: SIMD3(0, 70, 330), yaw: 0, pitch: -0.2)
        case "gw-court":    return Camera(position: GlassLayout.mirrorCourt + SIMD3(26, 3.0, 30), yaw: -0.8, pitch: -0.05)
        case "gw-court-high": return Camera(position: GlassLayout.mirrorCourt + SIMD3(0, 22, 20), yaw: 0.0, pitch: -1.05)
        case "gw-mirrors":  return Camera(position: GlassPuzzleProps.mirrorPosition(1) + SIMD3(4.0, 1.4, 4.5), yaw: -0.727, pitch: -0.04)   // a mirror stand from 6 m (R06)
        case "gw-chimes":   return Camera(position: GlassLayout.chimeRing + SIMD3(-22, 3.0, -24), yaw: 2.4, pitch: -0.02)
        case "gw-altar":    return Camera(position: GlassLayout.altar + SIMD3(0, 3.0, 28), yaw: 0, pitch: 0.05)
        default:         return nil
        }
    }
}

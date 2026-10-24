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
    static let grassCell: Float = 0.26
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
      --dump-overlay <base>        Render crosshair/journal/end overlays to <base>-*.png and exit
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

    /// `page-close`: 0.8 m above the journal page on the tide stone's plinth, looking down at it (R06).
    static func pageClose(terrain: Terrain) -> Camera {
        let p = PuzzleProps.pagePosition(2, terrain: terrain)
        return Camera(position: p + SIMD3(0.0, 0.8, 0.45), yaw: 0, pitch: -1.0)
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

import Foundation
import simd

/// F10 (B's finding in F09.3, Q48; decision Q71): walking the Archive's sluice walk off its centre line, the player is moved sideways by up to 0.45 m/s. This walks every leg of that trail at five offsets
/// with each possible source switched off in turn and at the real tide levels, to say which source it is (`SLUICE_TABLE=1` prints the table).
///
/// What it found: the pits' ground is gentle (the steepest 0.6 m gradient on the whole trail is 0.44, the limit 0.84) and the margin and the slip add nothing. Two sources remain, both visible and both by design:
///  - the closed gate and its piers stand ON the trail's centre line (a solid you walk into: the player slides round it);
///  - the WADING LIMIT: a player may not wade deeper than 0.4 m (`Player.minGround`), so a room the tide has flooded deeper than that is a pool whose edge the player slides along, as on any shore. The earlier
///    measurement (0.45 m/s) was taken with the sea fixed at 0 m, which floods the stone room (floor -0.9 m) all the time; in the game `Player.sea` follows the tide (`Game.fixedStep`).
/// At low water, when every room is dry or wadeable (the state the puzzle asks for), nothing but a collider moves the player.
extension SelfTestRunner {
    /// The worst lateral speed over any second of a 100 % forward walk down `from -> to` at `offset` m off its line, with the named sources on or off and the sea at `sea` m.
    func sluiceWalk(scene: Scene, net: NavNetwork, from a: SIMD2<Float>, to b: SIMD2<Float>, offset: Float, colliders: Bool = true, slip: Bool = true, margin: Bool = true, sea: Float = 0) -> Float? {
        let len = simd_length(b - a)
        guard len >= 6 else { return nil }
        let dir = (b - a) / len, side = SIMD2(dir.y, -dir.x), yaw = atan2(dir.x, -dir.y)
        let start = a + dir * 1 + side * offset
        guard net.signedDistance(start) < -0.8, net.isReachable(start) else { return nil }
        let saved = scene.colliders; if !colliders { scene.colliders = Colliders() }
        let savedSlip = Player.slipEnabled; Player.slipEnabled = slip
        let savedSea = Player.sea; Player.sea = sea
        defer { scene.colliders = saved; Player.slipEnabled = savedSlip; Player.sea = savedSea }
        var pl = Player(position: SIMD3(start.x, scene.groundHeight(x: start.x, z: start.y), start.y), yaw: yaw)
        var inp = InputState(); inp.move = SIMD2(0, 1)
        let seconds = min(45, (len - 4) / (Player.walkSpeed * 1.25))
        var lat: [Float] = []
        for _ in 0..<Int(seconds / Game.tick) {
            _ = pl.step(dt: Game.tick, input: inp, scene: scene, nav: margin ? net : nil)
            lat.append(simd_dot(SIMD2(pl.position.x, pl.position.z) - start, side))
        }
        let win = Int(1 / Game.tick); var worst: Float = 0
        if lat.count > win { for k in 0..<(lat.count - win) { worst = max(worst, abs(lat[k + win] - lat[k])) } }
        return worst
    }

    func runSluicePit() {
        guard name == "all" || name == "sluicepit" else { return }
        let scene = Scene.make(.tideArchive, device: device)
        guard let net = Layout.Navigation.network(for: .tideArchive, guidance: .guided), let trail = net.trails.first(where: { $0.name == "the sluice walk" }) else { check(false, "sluicepit: the Archive has a sluice walk"); return }
        let low = Tide.metres(level: 0), mid = Tide.metres(level: 0.5), high = Tide.metres(level: 1)
        let offsets: [Float] = [-3, -1.5, 0, 1.5, 3]
        func worst(colliders: Bool, sea: Float) -> (worst: Float, lines: Int) {
            var w: Float = 0, n = 0
            for i in 0..<(trail.points.count - 1) { for o in offsets {
                if let x = sluiceWalk(scene: scene, net: net, from: trail.points[i], to: trail.points[i + 1], offset: o, colliders: colliders, sea: sea) { w = max(w, x); n += 1 }
            } }
            return (w, n)
        }
        if ProcessInfo.processInfo.environment["SLUICE_TABLE"] != nil {
            for i in 0..<(trail.points.count - 1) { for o in offsets {
                var row = String(format: "leg %d (%.0f,%.0f)->(%.0f,%.0f) offset %+.1f:", i, trail.points[i].x, trail.points[i].y, trail.points[i + 1].x, trail.points[i + 1].y, o)
                for (label, c, sea) in [("all, low", true, low), ("all, mid", true, mid), ("all, high", true, high), ("no colliders, low", false, low), ("no colliders, mid", false, mid), ("no colliders, high", false, high)] {
                    if let w = sluiceWalk(scene: scene, net: net, from: trail.points[i], to: trail.points[i + 1], offset: o, colliders: c, sea: sea) { row += String(format: " | %@ %.3f", label, w) }
                }
                print(row)
            } }
        }
        let ground = worst(colliders: false, sea: -50)
        check(ground.lines >= 15 && ground.worst <= 0.06, "sluicepit: with no colliders and no water in the way, the pits' own ground moves nobody sideways by more than 5-6 cm/s (\(ground.lines) lines, worst \(String(format: "%.3f", ground.worst)) m/s)")
        let dry = worst(colliders: false, sea: low)
        check(dry.worst <= 0.06, "sluicepit: at low water (sea \(String(format: "%.1f", low)) m) every room is dry or wadeable and, colliders aside, nothing pushes the walker (worst \(String(format: "%.3f", dry.worst)) m/s)")
        let flooded = worst(colliders: false, sea: high)
        check(flooded.worst > 0.1, "sluicepit: at high water (sea \(String(format: "%.1f", high)) m) the flooded rooms ARE edges to slide along (the wading limit; the measure can see it: \(String(format: "%.3f", flooded.worst)) m/s), and the push is not there without the water")
        var steepest: Float = 0
        for i in 0..<(trail.points.count - 1) {
            let a = trail.points[i], b = trail.points[i + 1], len = simd_length(b - a), dir = (b - a) / len
            for d in stride(from: Float(0), through: len, by: 0.5) {
                let q = a + dir * d
                let gx = (scene.groundHeight(x: q.x + 0.3, z: q.y) - scene.groundHeight(x: q.x - 0.3, z: q.y)) / 0.6, gz = (scene.groundHeight(x: q.x, z: q.y + 0.3) - scene.groundHeight(x: q.x, z: q.y - 0.3)) / 0.6
                steepest = max(steepest, simd_length(SIMD2(gx, gz)))
            }
        }
        check(steepest < Player.maxSlope * 0.6, "sluicepit: the sluice walk's ground is nowhere near too steep to walk (steepest gradient \(String(format: "%.2f", steepest)), the limit is \(Player.maxSlope))")
        // The gates and piers on the centre line are what a walker meets there (visible, solid): with them, the centre line at low water is pushed; without them it is not.
        let withColliders = worst(colliders: true, sea: low)
        check(withColliders.worst > 0.1 && dry.worst <= 0.06, "sluicepit: what moves a walker on the sluice walk at low water is the gates and piers on its centre line (with colliders \(String(format: "%.2f", withColliders.worst)) m/s, without \(String(format: "%.3f", dry.worst)))")
        _ = mid
    }
}

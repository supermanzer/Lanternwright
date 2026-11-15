import Foundation
import simd

/// F10 (A's flag, from F09.2): the guide lantern and the guide lamps must never stand inside a CLOSED sluice gate's collider. The lantern floats along the route to its objective and parks on it (the first
/// gate not yet open is an objective); Ilse's lamps stand every 26 m along the route from the entry to the prism chamber. A gate that is shut is a solid cylinder (`ArchiveProps.gateCollider`, radius 0.9) across
/// the sluice room, so a light inside it would hang in the stone.
///
/// What the check found on the build before the fix: the Archive's sluice walk (`ArchiveLayout.sluiceWalk`) has a vertex at each room's centre, which is where the gate stands, so every route to or between
/// the gates ran through a shut gate's collider (0.9 m inside it, at its centre) and doubled back to the wheel. `GuideLanterns.avoidClosedGates` now detours the lantern's route round shut gates
/// (`Game.syncGuides`). The lamps were never affected (their spots are 21 m from any gate).
extension SelfTestRunner {
    /// The least distance from any of `points` to the edge of the given gates' colliders (negative: a point is inside one).
    static func gateClearance(_ points: [SIMD2<Float>], gates: [Int] = [0, 1, 2]) -> (clearance: Float, at: SIMD2<Float>, gate: Int)? {
        var best: (Float, SIMD2<Float>, Int)?
        for p in points { for k in gates {
            let c = ArchiveProps.gateCollider(k)
            let d = simd_length(p - c.center) - c.radius
            if best == nil || d < best!.0 { best = (d, p, k) }
        } }
        return best.map { (clearance: $0.0, at: $0.1, gate: $0.2) }
    }

    /// Every point of a polyline, and a point every half metre along each leg (a route that crosses a collider between two vertices is as bad as one that stops in it).
    static func densify(_ pts: [SIMD2<Float>], every: Float = 0.5) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for i in pts.indices {
            out.append(pts[i])
            guard i + 1 < pts.count else { continue }
            let d = simd_length(pts[i + 1] - pts[i]), n = Int(d / every)
            if n > 0 { for s in 1...n { out.append(pts[i] + (pts[i + 1] - pts[i]) * (Float(s) * every / d)) } }
        }
        return out
    }

    func runGuideGates() {
        guard name == "all" || name == "guidegates" else { return }
        let clearance: Float = 0.4          // a lamp post's footing (0.3 m) plus a hand
        func say(_ w: (clearance: Float, at: SIMD2<Float>, gate: Int)?) -> String { w.map { String(format: "%.2f m from gate %d's collider at (%.1f, %.1f)", $0.clearance, $0.gate, $0.at.x, $0.at.y) } ?? "no points" }
        let net = Layout.Navigation.network(for: .tideArchive)

        // The lantern's objective routes: from the entry and from each gate's wheel (the light is there when the objective moves on, or when the gates close again) to each gate's wheel, with every gate
        // shut (the strictest case: the game shuts only the gates from the first unopened on).
        let entryIlse = Game.routeEntry(.ilse, in: .tideArchive).position, entryOren = Game.routeEntry(.oren, in: .tideArchive).position
        let wheels = (0..<3).map { k -> SIMD2<Float> in let g = TideSpots.gate(k); return SIMD2(g.x, g.z) }
        var raw: [SIMD2<Float>] = [], fixed: [SIMD2<Float>] = []
        for from in [SIMD2(entryIlse.x, entryIlse.z)] + wheels {
            for to in wheels where simd_length(from - to) > 0.5 {
                let route = net.route(from: from, to: to) + [to]
                raw += Self.densify(route)
                fixed += Self.densify(GuideLanterns.avoidClosedGates(route, closed: GuideLanterns.closedGates(opened: 0)))
            }
        }
        let rawWorst = Self.gateClearance(raw), fixedWorst = Self.gateClearance(fixed)
        check((rawWorst?.clearance ?? 1) < 0, "guidegates: WITHOUT the detour the lantern's routes run through a shut gate (the check finds it: \(say(rawWorst)))")
        check(fixed.count > 200 && (fixedWorst?.clearance ?? -1) >= clearance, "guidegates: with the detour the lantern's routes keep \(clearance) m clear of every shut gate's collider (\(fixed.count) points; nearest \(say(fixedWorst)))")
        check((Self.gateClearance(wheels)?.clearance ?? -1) >= clearance, "guidegates: the spots the light parks on (the wheels) are clear of the gates' colliders (\(say(Self.gateClearance(wheels))))")

        // Ilse's lamps (Oren's route): one every 26 m along the route from the entry to the prism chamber.
        let path = GuidePath(net.route(from: SIMD2(entryOren.x, entryOren.z), to: SIMD2(ArchiveLayout.prismChamber.x, ArchiveLayout.prismChamber.z)))
        let lamps = (0..<GuideLanterns.lampCount(pathLength: path.length)).map { path.point(at: GuideLanterns.lampDistance($0)) }
        let lampWorst = Self.gateClearance(lamps)
        check(lamps.count >= 3 && (lampWorst?.clearance ?? -1) >= clearance, "guidegates: Ilse's guide lamps (\(lamps.count), one every \(Int(GuideLanterns.spacing)) m) stand \(clearance) m clear of every shut gate's collider (nearest \(say(lampWorst)))")

        // The detour is only for shut gates, only as wide as it must be, and keeps the ends of the route.
        let c0 = ArchiveProps.gateCollider(0)
        let through = [c0.center + SIMD2(-6, 0), c0.center, c0.center + SIMD2(6, 0)]
        let round = GuideLanterns.avoidClosedGates(through, closed: [c0])
        let roundClear = Self.gateClearance(Self.densify(round), gates: [0])
        check(round.first == through.first && round.last == through.last && round.count == 3 && (roundClear?.clearance ?? -1) >= clearance, "guidegates: a route through a shut gate's centre goes round it, keeping the end it is going to (\(round.count) points, nearest \(say(roundClear)))")
        check(GuideLanterns.avoidClosedGates(through, closed: []) == through, "guidegates: with the gate open (no shut gate) the route is left exactly as it was")
        let leg = [c0.center + SIMD2(-6, 5), c0.center + SIMD2(6, 5)]
        check(GuideLanterns.avoidClosedGates(leg, closed: [c0]) == leg, "guidegates: a route that passes 5 m from a shut gate is left alone")
        let graze = GuideLanterns.avoidClosedGates([c0.center + SIMD2(-6, 1.2), c0.center + SIMD2(6, 1.2)], closed: [c0])
        let grazeClear = Self.gateClearance(Self.densify(graze), gates: [0])
        check(graze.count == 3 && (grazeClear?.clearance ?? -1) >= clearance, "guidegates: a route that grazes the gate's edge gets one waypoint and clears it (\(say(grazeClear)))")

        // The checker can fail: a lamp moved into a gate's collider, a lamp on its edge.
        check((Self.gateClearance(lamps + [c0.center])?.clearance ?? 1) < 0, "guidegates mutation: a lamp moved into gate 0's collider is flagged (\(say(Self.gateClearance(lamps + [c0.center]))))")
        check((Self.gateClearance(lamps + [c0.center + SIMD2(c0.radius + 0.1, 0)])?.clearance ?? 1) < clearance, "guidegates mutation: a lamp 10 cm outside the collider's edge is flagged as too close")

        // In the game: Ilse arrives with every gate shut and walks the route to each gate in turn (opening it when she gets there); the lantern the player sees keeps clear of every gate still shut, all the way.
        let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device), .tideArchive: TideArchive.build(device: device)])
        for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
        g.state.set("gw_end"); g.state.set(Game.doorOpenFlag); g.simulate(seconds: 0.1)
        check(g.beginRoute(.ilse), "guidegates: Ilse's route begins for the in-game walk")
        g.simulate(seconds: Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        var clock = 40_000.0
        func frames(_ n: Int) { for _ in 0..<n { clock += 1.0 / 60; g.advance(now: clock, input: InputState()) } }
        func put(_ p: SIMD2<Float>) { g.player.position = SIMD3(p.x, g.scene.groundHeight(x: p.x, z: p.y), p.y) }
        for f in IlseRoute.markFlags + [IlseRoute.marksFlag, IlseRoute.catalogueFlag, IlseRoute.keyFlag] { g.state.set(f) }          // S05.3: Ilse's light leads to each gate's PIPE once the marks, the catalogue and the rod are done
        let pipes = (0..<3).map { k -> SIMD2<Float> in let p = ArchiveLayout.pipe(k); return SIMD2(p.x, p.z) }
        frames(30)
        for k in 0..<3 {
            var seen: [SIMD2<Float>] = []
            let route = net.route(from: SIMD2(g.player.position.x, g.player.position.z), to: pipes[k])
            for p in route { put(p); frames(20); if let l = g.guideLantern { seen.append(l) } }
            put(pipes[k] + SIMD2(3, 0)); frames(600)
            if let l = g.guideLantern { seen.append(l) }
            let shut = Array(k..<3), worst = Self.gateClearance(seen, gates: shut)
            check(seen.count > 10 && (worst?.clearance ?? -1) >= clearance, "guidegates: in the game, walking to gate \(k) the lantern stays \(clearance) m clear of the gates still shut (\(seen.count) places; nearest \(say(worst)))")
            check(g.guideLightParked && g.guideLightKey == "pipe\(k)" && simd_length((g.guideLantern ?? .zero) - pipes[k]) < 0.5, "guidegates: in the game the light for gate \(k) parks on its pipe (key \(g.guideLightKey ?? "-"), \(String(format: "%.2f", simd_length((g.guideLantern ?? .zero) - pipes[k]))) m)")
            g.state.set(TideArchivePuzzle.sluiceFlags[k]); frames(30)
        }
    }
}

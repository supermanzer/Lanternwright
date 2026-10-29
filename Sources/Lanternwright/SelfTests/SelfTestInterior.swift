import Foundation
import Metal
import simd

/// Self-tests: the inside of the lighthouse (S03.5a): the feet-aware floors, the hollow wall that replaces the solid tower when the door is open, and the stair climbed with the real controller.
extension SelfTestRunner {
    func runInterior() {
        guard name == "all" || name == "interior" || name == "story" else { return }
        typealias I = LighthouseInterior
        let lh = Layout.lighthouse
        let o = LighthouseInterior()
        func pt(_ a: Float, _ r: Float) -> (x: Float, z: Float) { (lh.x + cos(a) * r, lh.z + sin(a) * r) }
        func band(_ phi: Float) -> Float { let h = I.stairY(phi); return (I.stairInner(h) + I.innerR(h)) / 2 }      // the middle of the stair at that angle

        // The numbers the design rests on (fixed): a 24 m climb in six turns, floors 0.9 and 24.8 above the ground at the foot.
        check(abs(I.floorY - 0.9) < 1e-4 && abs(I.lensFloorY - 24.8) < 1e-4 && I.turns == 6, "interior: the room's floor is the plinth's top (0.9 m), the lens room's 24.8 m, six turns between")
        let perTurn = (I.lensFloorY - I.floorY) / I.turns
        check(perTurn > 3.9 && perTurn < 4.05 && I.rate > 0.62 && I.rate < 0.65, "interior: each turn rises about 4 m (headroom for a 1.7 m eye under the next turn), \(perTurn) m")

        // The floor under the feet.
        check(o.height(x: lh.x + 5, z: lh.z, feetY: lh.y + 0.9) == nil && o.height(x: lh.x, z: lh.z + 3.6, feetY: lh.y + 0.9) == nil, "interior: outside the inner wall the scene's own ground applies (no floor from the interior)")
        check(abs((o.height(x: lh.x, z: lh.z, feetY: lh.y + 0.9) ?? -9) - (lh.y + 0.9)) < 1e-3, "interior: in the middle of the ground room the floor is the plinth's top")
        var worst: Float = 0, prev = lh.y + I.floorY, monotone = true
        var phi = I.startAngle
        while phi < I.endAngle {
            let q = pt(phi, band(phi))
            guard let h = o.height(x: q.x, z: q.z, feetY: prev) else { monotone = false; break }
            if h < prev - 1e-3 || h - prev > 0.06 { monotone = false }
            worst = max(worst, h - prev); prev = h; phi += 0.05
        }
        check(monotone && worst < 0.06, "interior: along the stair's middle the floor rises smoothly, never more than \(String(format: "%.3f", worst)) m between points 0.05 rad apart")
        check(abs(prev - (lh.y + I.lensFloorY)) < 0.07, "interior: and it arrives at the lens room's floor (\(prev - lh.y) m)")
        // Stacked surfaces: at one spot the answer depends on the feet.
        let foot = pt(I.startAngle, 2.15)                                                    // a radius that is on the stair at every height: the shaft narrows as it rises
        var stacked: [Float] = []
        for k in 0..<Int(I.turns) {
            let feet = lh.y + I.floorY + Float(k) * perTurn
            stacked.append((o.height(x: foot.x, z: foot.z, feetY: feet) ?? -99) - feet)
        }
        check(stacked.allSatisfy { abs($0) < 0.06 }, "interior: at one spot each of the six turns gives its own floor to feet standing on it (\(stacked.map { String(format: "%.2f", $0) }))")
        let under = pt(I.startAngle + .pi, band(I.startAngle + .pi))
        check(abs((o.height(x: under.x, z: under.z, feetY: lh.y + I.floorY) ?? -9) - (lh.y + I.floorY)) < 1e-3, "interior: under the stair the floor is still the room's, the turn 2 m above is not stepped onto")
        // The lens room's floor, and the hatch the stair comes up through.
        let lensAt = pt(I.endAngle + 1.0, 1.4)
        check(abs((o.height(x: lensAt.x, z: lensAt.z, feetY: lh.y + I.lensFloorY) ?? -9) - (lh.y + I.lensFloorY)) < 1e-3, "interior: in the lens room the floor is 24.8 m up, away from the hatch")
        let inHatch = pt(I.endAngle - 1.5, band(I.endAngle - 1.5))
        let hatchH = (o.height(x: inHatch.x, z: inHatch.z, feetY: lh.y + I.stairY(I.endAngle - 1.5)) ?? -9) - lh.y
        check(abs(hatchH - I.stairY(I.endAngle - 1.5)) < 1e-3 && hatchH < I.lensFloorY - 0.5, "interior: in the hatch the floor is the stair's, below the lens room's (\(hatchH) m at 1.5 rad before the top)")
        let well = pt(I.endAngle - 1.5, 0.4)
        check(abs((o.height(x: well.x, z: well.z, feetY: lh.y + I.lensFloorY) ?? -9) - (lh.y + I.lensFloorY)) < 1e-3, "interior: the well is closed by the lens room's floor")

        // Closed, the tower is the solid core and the player is not given the interior (the game passes nil until door_open).
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        var idle = InputState(); idle.move = .zero
        var clock = 3000.0
        func step(_ g: Game, _ n: Int = 2) { for _ in 0..<n { clock += 0.05; g.advance(now: clock, input: idle) } }
        let g = twoWorlds()
        let solid = { (g: Game) in g.scene.colliders.cylinders.filter { $0.center == SIMD2(lh.x, lh.z) && abs($0.radius - Lighthouse.colliderRadius) < 1e-4 }.count }
        let count0 = g.scene.colliders.cylinders.count
        step(g)
        check(!g.interiorApplied && solid(g) == 1 && g.scene.colliders.cylinders.count == count0, "interior: with the door shut nothing changes: the solid core stays, no colliders are added")
        check(g.scene.items.filter { $0.name == I.wallName || $0.name == I.stairName }.allSatisfy { $0.hidden }, "interior: and the inside is not drawn")
        g.state.set(Game.doorOpenFlag); step(g)
        check(g.interiorApplied && solid(g) == 0 && g.scene.colliders.cylinders.count > count0 + 100, "interior: with the door open the solid core is gone and the wall is a ring of colliders (\(g.scene.colliders.cylinders.count - count0) added)")
        check(g.scene.items.filter { $0.name == I.wallName || $0.name == I.stairName }.allSatisfy { !$0.hidden }, "interior: and the inside is drawn")
        g.state.set(Game.doorOpenFlag, false); step(g)
        check(!g.interiorApplied && solid(g) == 1 && g.scene.colliders.cylinders.count == count0 && g.scene.items.filter { $0.name == I.wallName }.allSatisfy { $0.hidden }, "interior: shutting it again restores the core exactly and hides the inside")

        // Walk it with the real controller: in through the door, up the stair to the lens room. (The corridors lead to the door; inside, the bot steers by waypoints.)
        let w = twoWorlds()
        w.state.set(Game.doorOpenFlag); step(w)
        w.player = Player(position: SIMD3(lh.x, lh.y + I.floorY, lh.z + 8), yaw: .pi)
        w.player.position.y = w.scene.groundHeight(x: lh.x, z: lh.z + 8)
        let bot = PlaythroughBot(w)
        let t0 = bot.elapsed
        let inside = bot.walk(to: SIMD3(lh.x, 0, lh.z + 5), within: 0.5, straight: true) && bot.walk(to: SIMD3(lh.x, 0, lh.z + 3.0), within: 0.5, straight: true) && bot.walk(to: SIMD3(lh.x - 0.9, 0, lh.z + 2.3), within: 0.5, straight: true)
        let tDoor = bot.elapsed - t0
        check(inside && simd_length(SIMD2(bot.feet.x - lh.x, bot.feet.z - lh.z)) < 3.3, "interior: the player walks in through the open door (\(String(format: "%.1f", tDoor)) s from 8 m out, feet \(bot.feet))")
        var climbed = inside
        var p = I.startAngle
        let climbStart = bot.elapsed
        while climbed && p < I.endAngle + 0.5 {
            let r = band(min(p, I.endAngle)), q = pt(p, r)
            climbed = bot.walk(to: SIMD3(q.x, 0, q.z), within: 0.55, straight: true)
            p += 0.3
        }
        let climbSeconds = bot.elapsed - climbStart
        // Onto the lens room's floor.
        let top = pt(I.endAngle + 1.2, 1.2)
        let reached = climbed && bot.walk(to: SIMD3(top.x, 0, top.z), within: 0.5, straight: true)
        let total = bot.elapsed - t0
        if name == "interior" { print("interior: door to lens room: \(String(format: "%.0f", total)) s (climb \(String(format: "%.0f", climbSeconds)) s), feet \(bot.feet), climbed \(climbed) reached \(reached)") }
        check(reached && abs(bot.feet.y - (lh.y + I.lensFloorY)) < 0.1, "interior: the player climbs the stair to the lens room with the real controller and stands on its floor (y \(bot.feet.y - lh.y) of \(I.lensFloorY))")
        check(total < 60, "interior: from 8 m outside the door to the lens room takes \(String(format: "%.0f", total)) s (accept: under 60 s at the default pace)")
        // And they cannot walk under the low treads (the rail stops them), nor off the stair into the well.
        let u = twoWorlds()
        u.state.set(Game.doorOpenFlag); step(u)
        u.player = Player(position: SIMD3(lh.x, lh.y + I.floorY, lh.z), yaw: 0)
        u.player.position.y = u.scene.groundHeight(x: lh.x, z: lh.z)
        let ub = PlaythroughBot(u)
        let lowPhi = I.startAngle + 2.0                                                      // 2 rad up the stair: the treads are 1.3 m above the floor there
        let lowAt = pt(lowPhi, I.innerR(I.stairY(lowPhi)) - 0.5)                            // under them, near the wall
        let walked = ub.walk(to: SIMD3(lowAt.x, 0, lowAt.z), within: 0.5, timeout: 8, straight: true)
        let rNow = simd_length(SIMD2(ub.feet.x - lh.x, ub.feet.z - lh.z))
        check(!walked && rNow < I.stairInner(I.stairY(lowPhi)) + 0.05 && abs(ub.feet.y - (lh.y + I.floorY)) < 0.01, "interior: the room's floor under the low treads cannot be walked to: the rail stops the player at radius \(String(format: "%.2f", rNow)) (the stair's inner edge there is \(String(format: "%.2f", I.stairInner(I.stairY(lowPhi)))))")
        let rails = w.scene.colliders.cylinders.filter { $0.radius == 0.14 }.count
        check(rails == I.treadsPerTurn * Int(I.turns) - I.openTreads, "interior: the inner rail has a post for every tread but the first \(I.openTreads) (\(rails))")
    }
}

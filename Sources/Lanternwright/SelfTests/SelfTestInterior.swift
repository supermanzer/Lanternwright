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
        // F07 B-rail (#82): the lens room's open edges have a railing: arcs round the floor's outer edge that leave the north window's doorway free, inside the wall, and never across the hatch.
        let arcs = I.railArcs
        func inArcs(_ ang: Float) -> Bool { arcs.contains { a in var x = ang; while x < a.0 { x += 2 * .pi }; while x > a.0 + 2 * .pi { x -= 2 * .pi }; return x >= a.0 && x <= a.1 } }
        let covered = arcs.reduce(Float(0)) { $0 + ($1.1 - $1.0) }
        check(arcs.count == 2 && covered > 2.0 && covered < 2 * .pi - I.hatch, "interior: the rail's arcs cover the floor outside the hatch (\(String(format: "%.2f", covered)) rad of \(String(format: "%.2f", 2 * .pi - I.hatch)))")
        check(!inArcs(I.portalAngle) && !inArcs(I.portalAngle + 0.3) && !inArcs(I.portalAngle - 0.3) && inArcs(I.portalAngle + 0.6) && inArcs(I.portalAngle - 0.6), "interior: and they leave the north window's doorway free")
        check(!inArcs(I.endAngle - I.hatch / 2) && I.railRadius < I.innerR(I.lensFloorY) && I.railRadius > 1.77 + 0.1, "interior: none stands across the hatch, and the rail is inside the wall and beyond where a player's feet stop (1.77 m)")
        check(w.scene.items.first { $0.name == I.fittingsName } != nil, "interior: the rails are part of the fittings (drawn with the open lighthouse)")
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
        check(rails == I.treadsPerTurn * Int(I.turns) - I.openTreads + 5, "interior: the inner rail has a post for every tread but the first \(I.openTreads), and 5 posts close the hatch's far edge (\(rails))")

        // Running and walking, up and down, with the real controller and the stair's own steering (a bot that holds forward toward each waypoint; `run` holds Shift).
        func trip(_ g: Game, _ points: [(x: Float, z: Float)], run: Bool, timeout: Float = 90) -> (ok: Bool, seconds: Float, maxJump: Float) {
            let b = PlaythroughBot(g)
            var worst: Float = 0, lastY = g.player.position.y, t: Float = 0
            for q in points {
                while simd_length(SIMD2(q.x - g.player.position.x, q.z - g.player.position.z)) > 0.5 {
                    if t > timeout { return (false, t, worst) }
                    let d = SIMD2(q.x - g.player.position.x, q.z - g.player.position.z)
                    g.player.yaw = atan2(d.x, -d.y); g.player.pitch = 0
                    var inp = InputState(); inp.move = SIMD2(0, 1); inp.run = run
                    b.tick(inp); t += 1.0 / 60
                    worst = max(worst, abs(g.player.position.y - lastY)); lastY = g.player.position.y
                }
            }
            return (true, t, worst)
        }
        let upPoints = stride(from: I.startAngle, to: I.endAngle + 0.5, by: 0.3).map { pt($0, band(min($0, I.endAngle))) } + [pt(I.endAngle + 1.2, 1.2)]
        let downPoints = Array(upPoints.reversed())
        func freshOpen(at p: (x: Float, z: Float), y: Float) -> Game {
            let g = twoWorlds(); g.state.set(Game.doorOpenFlag); step(g)
            g.player = Player(position: SIMD3(p.x, y, p.z), yaw: 0)
            return g
        }
        let runUp = trip(freshOpen(at: pt(I.startAngle, band(I.startAngle)), y: lh.y + I.floorY), upPoints, run: true)
        check(runUp.ok && runUp.maxJump < 0.08, "interior: running up the stair works: \(String(format: "%.0f", runUp.seconds)) s, largest height change in one tick \(String(format: "%.3f", runUp.maxJump)) m")
        let topStart = pt(I.endAngle + 1.2, 1.2)
        let dg = freshOpen(at: topStart, y: lh.y + I.lensFloorY)
        let down = trip(dg, downPoints, run: false)
        check(down.ok && abs(dg.player.position.y - (lh.y + I.floorY)) < 0.25 && down.maxJump < 0.08, "interior: walking down from the lens room to the room's floor works: \(String(format: "%.0f", down.seconds)) s, ends at \(dg.player.position.y - lh.y) m, r \(String(format: "%.2f", simd_length(SIMD2(dg.player.position.x - lh.x, dg.player.position.z - lh.z)))), angle \(String(format: "%.2f", atan2(dg.player.position.z - lh.z, dg.player.position.x - lh.x)))")

        // The lens room's space, measured (S03.7 builds the ring and the portal here): the floor a player's feet can stand on, with the lens ring's footprint kept clear, and the floor in front of the north window.
        let lg = twoWorlds(); lg.state.set(Game.doorOpenFlag); step(lg)
        var standable = 0, frontOfWindow = 0
        let cell: Float = 0.05
        var gx = lh.x - 2.2
        while gx <= lh.x + 2.2 {
            var gz = lh.z - 2.2
            while gz <= lh.z + 2.2 {
                let r = simd_length(SIMD2(gx - lh.x, gz - lh.z))
                if r >= I.ringOuter + Player.radius, let h = o.height(x: gx, z: gz, feetY: lh.y + I.lensFloorY), abs(h - (lh.y + I.lensFloorY)) < 1e-3 {
                    var p = SIMD2(gx, gz)
                    lg.scene.colliders.resolve(position: &p, radius: Player.radius, feetY: lh.y + I.lensFloorY, height: Player.eyeHeight)
                    if simd_length(p - SIMD2(gx, gz)) < 1e-3 {
                        standable += 1
                        let a = atan2(gz - lh.z, gx - lh.x)
                        var da = abs(a - I.portalAngle).truncatingRemainder(dividingBy: 2 * .pi); if da > .pi { da = 2 * .pi - da }
                        if da < 0.5 { frontOfWindow += 1 }
                    }
                }
                gz += cell
            }
            gx += cell
        }
        let area = Float(standable) * cell * cell, windowArea = Float(frontOfWindow) * cell * cell
        if name == "interior" { print("interior: the lens room has \(String(format: "%.2f", area)) m2 of standable floor outside the ring's radius, \(String(format: "%.2f", windowArea)) m2 of it within 0.5 rad of the north window") }
        check(area > 2.0, "interior: the lens room has room to stand outside the ring: \(String(format: "%.2f", area)) m2 of standable floor beyond a ring \(I.ringOuter) m in radius (S03.7: the lens ring and portal are built inside this)")
        check(windowArea > 0.55, "interior: and the floor reaches the north window, where the portal opens: \(String(format: "%.2f", windowArea)) m2 within 0.5 rad of it")
        // A player can stand 0.4 m from the glass, in front of the window, with the doorway's width clear to either side.
        let atGlass = SIMD2(lh.x + cos(I.portalAngle) * 1.6, lh.z + sin(I.portalAngle) * 1.6)
        var standing = atGlass
        lg.scene.colliders.resolve(position: &standing, radius: Player.radius, feetY: lh.y + I.lensFloorY, height: Player.eyeHeight)
        check(simd_length(standing - atGlass) < 1e-3 && abs((o.height(x: atGlass.x, z: atGlass.y, feetY: lh.y + I.lensFloorY) ?? -9) - (lh.y + I.lensFloorY)) < 1e-3, "interior: a player can stand in front of the north window, 1.6 m from the axis")

        // A save made inside the tower (the lens room) loads back there, not at the islet.
        let sv = twoWorlds(); sv.state.set(Game.doorOpenFlag); step(sv)
        sv.player = Player(position: SIMD3(lh.x - 1.2, lh.y + I.lensFloorY, lh.z - 0.5), yaw: 1.0)
        let saved = sv.makeSave()
        let back = twoWorlds(); back.restore(saved)
        check(back.world == .varrow && abs(back.player.position.y - (lh.y + I.lensFloorY)) < 0.1 && abs(back.player.position.x - (lh.x - 1.2)) < 0.3, "interior: a game saved in the lens room loads back in the lens room (\(back.player.position))")

        // S03.5b: the footstep surface, the fittings (hidden while the door is shut, drawn when it is open) and what they block.
        check(o.surface(x: lh.x, z: lh.z, feetY: lh.y + I.floorY) == .stone && o.surface(x: foot.x, z: foot.z, feetY: lh.y + I.floorY + 3 * perTurn) == .wood && o.surface(x: lensAt.x, z: lensAt.z, feetY: lh.y + I.lensFloorY) == .wood && o.surface(x: lh.x + 6, z: lh.z, feetY: lh.y) == nil,
              "interior: the foot is on stone flags in the ground room, on boards on the stair and in the lens room, and on nothing of the tower's outside")
        let names = [I.fittingsName, I.ringName]
        check(names.allSatisfy { n in g.scene.items.contains { $0.name == n } }, "interior: the fittings and the lens ring exist as scene items of their own (the ring so that S03.7 can turn it)")
        let shutGame = twoWorlds(); step(shutGame)
        check(names.allSatisfy { n in shutGame.scene.items.first { $0.name == n }?.hidden == true }, "interior: and they are not drawn while the door is shut")
        let openGame = twoWorlds(); openGame.state.set(Game.doorOpenFlag); step(openGame)
        check(names.allSatisfy { n in openGame.scene.items.first { $0.name == n }?.hidden == false }, "interior: and are drawn once it is open")
        // They block: the bench's ends and the lens's footprint (a player's centre cannot get inside 0.9 m of the axis in the lens room, nor through the bench).
        var inRing = SIMD2(lh.x + 0.5, lh.z + 0.1)
        openGame.scene.colliders.resolve(position: &inRing, radius: Player.radius, feetY: lh.y + I.lensFloorY, height: Player.eyeHeight)
        check(simd_length(inRing - SIMD2(lh.x, lh.z)) >= I.ringOuter - 1e-3, "interior: the lens's footprint keeps a player 0.9 m from the axis in the lens room (\(simd_length(inRing - SIMD2(lh.x, lh.z))))")
        var atBench = SIMD2(lh.x + I.benchEnds[1].x, lh.z + I.benchEnds[1].y)
        openGame.scene.colliders.resolve(position: &atBench, radius: Player.radius, feetY: lh.y + I.floorY, height: Player.eyeHeight)
        check(simd_length(atBench - SIMD2(lh.x + I.benchEnds[1].x, lh.z + I.benchEnds[1].y)) >= 0.6, "interior: the bench is solid")

        // With the fittings in place the stair is still walkable (nothing displaces a player on its centre line, at the tread's own height), and the workshop clears the treads above it.
        var displaced = 0, samples = 0
        var ph = I.startAngle
        while ph < I.endAngle {
            let q = pt(ph, band(ph)), startPos = SIMD2(q.x, q.z)
            var pos = startPos
            openGame.scene.colliders.resolve(position: &pos, radius: Player.radius, feetY: lh.y + I.stairY(ph), height: Player.eyeHeight)
            if simd_length(pos - startPos) > 1e-3 { displaced += 1 }
            samples += 1; ph += 0.1
        }
        check(displaced == 0 && samples > 300, "interior: with the fittings in, no collider touches a player on the stair's centre line, at the tread's height, all the way up (\(displaced) of \(samples) points)")
        var tightest: Float = .infinity
        let along = I.benchTangent, c0 = I.benchCentre
        for u in stride(from: Float(-0.7), through: 0.7, by: 0.1) {
            for v in stride(from: Float(-0.3), through: 0.3, by: 0.1) {
                let toAxis = -SIMD2(cos(I.workshopAngle), sin(I.workshopAngle))
                let p2 = c0 + along * u + toAxis * v
                let fl = o.height(x: lh.x + p2.x, z: lh.z + p2.y, feetY: lh.y + I.floorY + 2.0) ?? 0       // a head's height: is there a tread overhead?
                _ = fl
                // The lowest tread overhead at this spot: the stair's surface at each turn, less its thickness, if the spot is on the band at that height.
                let ang = atan2(p2.y, p2.x), rr = simd_length(p2)
                var uu = (ang - I.startAngle).truncatingRemainder(dividingBy: 2 * .pi); if uu < 0 { uu += 2 * .pi }
                for k in 0..<Int(I.turns) {
                    let h = I.stairY(I.startAngle + uu + 2 * .pi * Float(k))
                    if rr >= I.stairInner(h) && rr <= I.innerR(h) { tightest = min(tightest, h - I.treadThickness - (I.floorY + I.benchTopY)); break }
                }
            }
        }
        check(tightest > 0.9, "interior: the bench's top is at least 0.9 m below the underside of the stair over every point of it (tightest \(String(format: "%.2f", tightest)) m), and the plates and charts (top 1.8 m) sit below the tread too")
    }
}

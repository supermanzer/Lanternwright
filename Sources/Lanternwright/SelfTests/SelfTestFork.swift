import Foundation
import Metal
import simd

/// Self-tests: the fork (S03.8): both routes from the lighthouse, the other exit sealed (dimmed and dead), the gate, and permanence across a save.
extension SelfTestRunner {
    func runFork() {
        guard name == "all" || name == "fork" || name == "story" else { return }
        typealias P = LensPortalProps
        typealias I = LighthouseInterior
        let lh = Layout.lighthouse
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        var clock = 6000.0
        func step(_ g: Game, _ n: Int = 2) { for _ in 0..<n { clock += 0.05; g.advance(now: clock, input: InputState()) } }
        /// The player in the lens room with the lighthouse open: the gate ready or not.
        func lensGame(ready: Bool = true) -> Game {
            let g = twoWorlds()
            if ready { for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }; g.state.set("gw_end") }
            g.state.set(Game.doorOpenFlag); step(g)
            g.player = Player(position: SIMD3(lh.x - 0.2, lh.y + I.lensFloorY, lh.z - 1.45), yaw: .pi)
            _ = g.drainEvents()
            return g
        }
        func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ r: Float) -> Bool { simd_length(SIMD2(a.x - b.x, a.z - b.z)) < r }
        func tint(_ g: Game, _ name: String) -> Float { g.scene.items.first { $0.name == name }?.uniforms.tint.x ?? -1 }
        func wait(_ g: Game, _ s: Float) { g.simulate(seconds: s); step(g) }

        // Picking: from where a player stands in the lens room, a ray at the ring picks the ring and a ray at the lens picks the lens (the lens's box must not stand in front of the ring's).
        let pk = lensGame()
        let eye = SIMD3(lh.x - 0.2, lh.y + I.lensFloorY + Player.eyeHeight, lh.z - 1.45)
        var ringPicks: [String?] = [], lensPicks: [String?] = []
        for dx: Float in [-0.3, 0, 0.3] { for dz: Float in [-1.55, -1.35, -1.7] {
            let e = SIMD3(lh.x + dx, eye.y, lh.z + dz)
            ringPicks.append(Interaction.pick(origin: e, dir: simd_normalize(lh + SIMD3(0, P.ringY, 0) - e), in: pk.interactables)?.id)
            lensPicks.append(Interaction.pick(origin: e, dir: simd_normalize(Landmarks.lensPosition - e), in: pk.interactables)?.id)
        } }
        check(ringPicks.allSatisfy { $0 == "lens_ring" } && lensPicks.allSatisfy { $0 == Game.lampLensName }, "fork: from the places a player stands in the lens room, a ray at the ring picks the ring and a ray at the lens picks the lens (\(Set(ringPicks.map { $0 ?? "-" })), \(Set(lensPicks.map { $0 ?? "-" })))")

        // Ilse's route: touch the lens above the ring (a real click): the route begins, Oren's exit is sealed, the player fades to the Glass Wood's arrival pad.
        let a = lensGame()
        let abot = PlaythroughBot(a)
        check(abot.click(Game.lampLensName) && a.chosenPath == .ilse && a.isTraveling, "fork: touching the lens in the lens room begins Ilse's route")
        abot.wait(Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        check(a.world == .glassWood && near(a.player.position, GlassLayout.arrival, 1.5) && a.pendingEntry == nil, "fork: and the player arrives in the Glass Wood at its arrival pad (\(a.player.position))")
        check(a.state.has(Game.pathIlseFlag) && !a.state.has(Game.pathOrenFlag), "fork: path_ilse is set and path_oren is not")
        // Oren's exit is sealed for good: back on Varrow, the ring does not turn, the beam on the receiver opens nothing, the receiver and its lamps are dark.
        a.travel(to: .varrow); step(a, 3)
        a.player = Player(position: SIMD3(lh.x - 0.2, lh.y + I.lensFloorY, lh.z - 1.45), yaw: .pi)
        let ringBefore = a.lensPortal.ringAngle
        a.lensPortal.turn(2)
        check(a.lensPortal.ringAngle == ringBefore, "fork: after Ilse's route the ring no longer turns (Oren's exit is sealed)")
        a.lensPortal.setAngle(P.receiverAngle); wait(a, 6)
        check(!a.state.has(Game.portalOpenFlag), "fork: and the beam on the receiver opens nothing, however long")
        check(P.lampNames.allSatisfy { lamp in a.scene.items.first { $0.name == lamp }?.uniforms.emissive.w == 0 } && tint(a, P.receiverName) < 0.5, "fork: the receiver is dimmed and its lamps are dark: the sealing is seen, not said")
        check(!a.beginRoute(.oren) && a.chosenPath == .ilse, "fork: the other route cannot be begun")
        let pathBefore = a.state.has(Game.pathIlseFlag)
        a.touchLampLens()
        check(a.chosenPath == .ilse && a.state.has(Game.pathIlseFlag) == pathBefore && !a.isTraveling, "fork: touching the lens again changes nothing")

        // Oren's route: turn the ring onto the receiver with real touches, the portal opens, step into the doorway: the route begins, Ilse's exit is sealed, the player is at the altar end.
        let o = lensGame()
        let obot = PlaythroughBot(o)
        var ok = true
        for _ in 0..<3 { ok = ok && obot.click("lens_ring"); obot.wait(0.3) }
        obot.wait(P.holdSeconds + 0.6)
        check(ok && o.state.has(Game.portalOpenFlag) && o.chosenPath == nil, "fork: the portal opens by the ring and does not by itself begin the route")
        let door = (lh.x + cos(I.portalAngle) * 1.72, lh.z + sin(I.portalAngle) * 1.72)
        check(o.chosenPath == nil && !o.isTraveling, "fork: a player standing at the ring (1.45 m out, in front of the window) is not in the doorway")
        let walked = obot.walk(to: SIMD3(door.0, 0, door.1), within: 0.25, straight: true)
        obot.wait(0.3)
        check(walked && o.chosenPath == .oren && o.isTraveling, "fork: stepping into the open doorway begins Oren's route")
        obot.wait(Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        let entry = Game.routeEntry(.oren).position
        check(o.world == .glassWood && near(o.player.position, entry, 1.5), "fork: and the player arrives at the open end of the Glass Wood, by the altar (\(o.player.position))")
        // Ilse's exit is sealed: on Varrow the plates only ring, the door stays shut, the plates are dimmed.
        o.travel(to: .varrow); step(o, 3)
        let q = twoWorlds()
        for n in [1, 2, 3, 5, 6, 7] { q.restorePage(n) }
        q.state.set("gw_end"); q.state.set(Game.pathOrenFlag); step(q)
        for k in [0, 1, 2] { q.activate(TonePlates.names[k]) }
        wait(q, 6)
        check(!q.state.has(Game.doorOpenFlag) && q.tonePlates.sequence.isEmpty && tint(q, "tone_plates") < 0.5, "fork: after Oren's route the plates only ring: the door stays shut and the plates are dimmed")
        check(!q.beginRoute(.ilse) && q.chosenPath == .oren, "fork: and Ilse's route cannot be begun")

        // The gate rules the fork: with it not ready neither route begins.
        let n = lensGame(ready: false)
        n.state.set("gw_end"); n.restorePage(1)
        n.touchLampLens()
        check(n.chosenPath == nil && !n.isTraveling && n.banner == GateState.cueTooLittle, "fork: with too little read touching the lens begins nothing and says the gate's line (\(n.banner ?? "no banner"))")
        check(!n.beginRoute(.oren) && !n.beginRoute(.ilse), "fork: and neither route can be begun")
        let early = lensGame(ready: false); early.touchLampLens()
        check(early.chosenPath == nil && early.banner == nil, "fork: before the Glass Wood the lens does nothing and says nothing")

        // Permanence: a save keeps the route and the seal; the sealed exit still cannot be opened after loading.
        let sIlse = twoWorlds(); sIlse.restore(a.makeSave()); step(sIlse, 3)
        check(sIlse.chosenPath == .ilse && sIlse.portalSealed && !sIlse.platesSealed, "fork: a game saved after Ilse's route loads with the route and the seal")
        sIlse.lensPortal.setAngle(P.receiverAngle); wait(sIlse, 6)
        check(!sIlse.state.has(Game.portalOpenFlag) && tint(sIlse, P.receiverName) < 0.5, "fork: and the sealed portal still cannot be opened, and is dimmed")
        check(!sIlse.beginRoute(.oren), "fork: nor the other route begun")
        let sOren = twoWorlds(); sOren.restore(o.makeSave()); step(sOren, 3)
        check(sOren.chosenPath == .oren && sOren.platesSealed && tint(sOren, "tone_plates") < 0.5, "fork: a game saved after Oren's route loads with the route, and the plates dimmed")
        check(sOren.state.has(Game.portalOpenFlag), "fork: and the portal that was opened stays open")
    }
}

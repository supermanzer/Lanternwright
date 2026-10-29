import Foundation
import Metal
import simd

/// Self-tests: the lens ring and Oren's lens portal (S03.7).
extension SelfTestRunner {
    func runPortal() {
        guard name == "all" || name == "portal" || name == "story" else { return }
        typealias P = LensPortalProps
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        var clock = 5000.0
        func step(_ g: Game, _ n: Int = 2) { for _ in 0..<n { clock += 0.05; g.advance(now: clock, input: InputState()) } }
        /// A game with the door open, in the lens room, with the gate ready (or not).
        func lensGame(ready: Bool = true) -> Game {
            let g = twoWorlds()
            if ready { for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }; g.state.set("gw_end") }
            g.state.set(Game.doorOpenFlag); step(g)
            _ = g.drainEvents()
            return g
        }
        func deg(_ r: Float) -> Float { r * 180 / .pi }
        func item(_ g: Game, _ name: String) -> DrawItem? { g.scene.items.first { $0.name == name } }

        // The numbers: a twelfth of a turn a click, the receiver three clicks clockwise of the start, 3 degrees, 2 seconds. Fixed, not read back.
        check(abs(deg(P.ringStep) - 15) < 1e-3 && abs(deg(P.receiverAngle) + 45) < 1e-3 && abs(deg(P.initialRingAngle) + 90) < 1e-3 && abs(deg(P.tolerance) - 3) < 1e-3 && P.holdSeconds == 2, "portal: a click turns 15 degrees; the ring starts pointing north (-90), the receiver is at -45; tolerance 3 degrees; hold 2 s")

        // Dormant until the door is open: nothing to turn, nothing drawn.
        let shut = twoWorlds(); step(shut)
        check(shut.interactables.first { $0.id == "lens_ring" }?.enabled == false && [P.receiverName, P.beamName, P.portalName].allSatisfy { item(shut, $0)?.hidden == true }, "portal: with the lighthouse door shut the ring cannot be turned and nothing of it is drawn")

        // Turning: a click is 15 degrees clockwise; the arrow keys turn either way; the ring and its beam follow.
        let g = lensGame()
        check(g.interactables.first { $0.id == "lens_ring" }?.enabled == true && abs(deg(g.lensPortal.ringAngle) + 90) < 1e-3, "portal: with the door open the ring can be turned, and it starts pointing north")
        g.activate("lens_ring")
        check(abs(deg(g.lensPortal.ringAngle) + 75) < 1e-3, "portal: one touch turns it 15 degrees clockwise (to -75)")
        g.lensPortal.turn(-2)
        check(abs(deg(g.lensPortal.ringAngle) + 105) < 1e-3, "portal: the other way, two steps back (-105)")
        g.lensPortal.setAngle(.pi - 0.01); g.lensPortal.turn(1)
        check(g.lensPortal.ringAngle > -.pi && g.lensPortal.ringAngle < -.pi + 0.3, "portal: it wraps round (\(deg(g.lensPortal.ringAngle)) degrees)")
        check(item(g, LighthouseInterior.ringName) != nil && abs(item(g, P.beamName)!.uniforms.model.columns.0.x - cos(-g.lensPortal.ringAngle)) < 1e-3, "portal: the beam preview is turned with the ring")
        // The arrow keys while the ring is under the crosshair.
        let ak = lensGame()
        ak.player = Player(position: SIMD3(Layout.lighthouse.x, Layout.lighthouse.y + LighthouseInterior.lensFloorY, Layout.lighthouse.z - 1.4), yaw: .pi)
        ak.player.pitch = -0.45
        step(ak, 6)
        var flip = InputState(); flip.pageFlip = 1
        clock += 0.05; ak.advance(now: clock, input: flip)
        let after = deg(ak.lensPortal.ringAngle)
        check(ak.hovered?.id == "lens_ring" && abs(after + 75) < 1e-3, "portal: the right arrow key turns the ring while it is under the crosshair (hovered \(ak.hovered?.id ?? "nothing"), \(after))")

        // The gate rules: aligned with the gate ready, 2 s opens; too soon does not; moving off resets the count; the tolerance is 3 degrees.
        let open = lensGame()
        open.lensPortal.setAngle(P.receiverAngle)
        open.simulate(seconds: 1.9)
        check(!open.state.has(Game.portalOpenFlag) && open.lensPortal.held > 1.8, "portal: on the receiver for 1.9 s is not enough")
        open.simulate(seconds: 0.3)
        check(open.state.has(Game.portalOpenFlag) && item(open, P.portalName)?.hidden == false, "portal: after 2 s the portal opens and the doorway is drawn")
        check(chimesOf(open.drainEvents()).contains(.lens), "portal: and the lamp answers (the lens's chime)")
        let ringBefore = open.lensPortal.ringAngle
        open.lensPortal.turn(3)
        check(open.lensPortal.ringAngle == ringBefore, "portal: once it is open the ring stays where it is")
        let reset = lensGame()
        reset.lensPortal.setAngle(P.receiverAngle); reset.simulate(seconds: 1.5)
        reset.lensPortal.turn(1); reset.simulate(seconds: 0.2); reset.lensPortal.setAngle(P.receiverAngle)
        reset.simulate(seconds: 1.5)
        check(!reset.state.has(Game.portalOpenFlag) && reset.lensPortal.held > 1.4, "portal: turning off the receiver and back starts the count again")
        let near = lensGame(); near.lensPortal.setAngle(P.receiverAngle + 2.9 * .pi / 180); near.simulate(seconds: 2.2)
        let far = lensGame(); far.lensPortal.setAngle(P.receiverAngle + 3.1 * .pi / 180); far.simulate(seconds: 5)
        check(near.state.has(Game.portalOpenFlag) && !far.state.has(Game.portalOpenFlag), "portal: 2.9 degrees off still counts, 3.1 does not (the receiver's tolerance is 3 degrees)")

        // The gate not ready: the beam may rest on the receiver for ever and nothing opens; the gate's line is said once; the lamps tell which parts are true.
        let dormant = lensGame(ready: false)
        dormant.state.set("gw_end"); dormant.restorePage(1); dormant.restorePage(5)
        dormant.lensPortal.setAngle(P.receiverAngle); dormant.simulate(seconds: 4)
        check(!dormant.state.has(Game.portalOpenFlag) && dormant.banner == GateState.cueTooLittle, "portal: with too little read the portal stays dormant and the gate's line is said (\(dormant.banner ?? "no banner"))")
        dormant.simulate(seconds: 0.1)
        let lamps = P.lampNames.map { item(dormant, $0)?.uniforms.emissive.w ?? -1 }
        check(lamps[0] > 0 && lamps[1] == 0 && lamps[2] == 0, "portal: the lamps show the altar solved and neither sibling's pages enough (\(lamps))")
        for k in [2, 3, 6, 7] { dormant.restorePage(k) }
        dormant.lensPortal.turn(1); dormant.lensPortal.setAngle(P.receiverAngle); dormant.simulate(seconds: 2.3)
        check(dormant.state.has(Game.portalOpenFlag), "portal: once the gate is ready the same alignment opens it")
        let before = twoWorlds(); before.state.set(Game.doorOpenFlag); step(before)
        before.lensPortal.setAngle(P.receiverAngle); before.simulate(seconds: 5)
        check(!before.state.has(Game.portalOpenFlag) && before.banner == nil, "portal: before the Glass Wood the beam on the receiver does nothing and says nothing")

        // Save and load: the portal stays open, the ring at the receiver.
        let back = twoWorlds(); back.restore(open.makeSave()); step(back)
        check(back.state.has(Game.portalOpenFlag) && abs(back.lensPortal.ringAngle - P.receiverAngle) < 1e-4 && item(back, P.portalName)?.hidden == false, "portal: a game saved with the portal open loads with it open and the ring at the receiver")

        // Real picking and a bot: stand in the lens room facing the ring and touch it three times: the beam reaches the receiver; two seconds later the portal opens.
        let lh = Layout.lighthouse
        let pk = lensGame()
        let ringC = lh + SIMD3(0, P.ringY, 0)
        let eye = SIMD3(lh.x - 0.2, lh.y + LighthouseInterior.lensFloorY + 1.7, lh.z - 1.45)
        check(Interaction.pick(origin: eye, dir: simd_normalize(ringC - eye), in: pk.interactables)?.id == "lens_ring", "portal: a ray from where a player stands in the lens room picks the ring")
        let b = lensGame()
        b.player = Player(position: SIMD3(lh.x - 0.2, lh.y + LighthouseInterior.lensFloorY, lh.z - 1.45), yaw: .pi)
        let bot = PlaythroughBot(b)
        var ok = true
        for _ in 0..<3 { ok = ok && bot.click("lens_ring"); bot.wait(0.3) }
        check(ok && b.lensPortal.aligned, "portal: three real touches turn the ring onto the receiver (\(deg(b.lensPortal.ringAngle)) degrees)")
        bot.wait(P.holdSeconds + 0.6)
        check(b.state.has(Game.portalOpenFlag), "portal: and the portal opens")
        let bw = lensGame(ready: false)
        let wbot = PlaythroughBot(bw)
        bw.player = Player(position: SIMD3(lh.x - 0.2, lh.y + LighthouseInterior.lensFloorY, lh.z - 1.45), yaw: .pi)
        for _ in 0..<3 { _ = wbot.click("lens_ring"); wbot.wait(0.3) }
        wbot.wait(5)
        check(!bw.state.has(Game.portalOpenFlag), "portal: the same touches with the gate not ready open nothing")

        func chimesOf(_ evs: [GameEvent]) -> [ChimeKind] { evs.compactMap { if case .chime(let c) = $0 { return c }; return nil } }
    }
}

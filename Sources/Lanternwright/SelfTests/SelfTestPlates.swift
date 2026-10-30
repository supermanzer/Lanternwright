import Foundation
import Metal
import simd

/// Self-tests: the tone plates beside the lighthouse door (S03.6): the order, a wrong strike, a partial set, repeats, the gate, a save, real picking and a bot.
extension SelfTestRunner {
    func runPlates() {
        guard name == "all" || name == "plates" || name == "story" else { return }
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        func readyGame() -> Game {
            let g = twoWorlds()
            for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
            g.state.set("gw_end")
            _ = g.drainEvents()
            return g
        }
        let names = TonePlates.names
        var clock = 4000.0
        func step(_ g: Game) { for _ in 0..<2 { clock += 0.05; g.advance(now: clock, input: InputState()) } }
        func strike(_ g: Game, _ ks: [Int]) { for k in ks { g.activate(names[k]) } }
        func chimes(_ evs: [GameEvent]) -> [ChimeKind] { evs.compactMap { if case .chime(let c) = $0 { return c }; return nil } }

        // The right order, with the gate ready: the tones are held, the chord blooms, the lamp answers, the door opens.
        let g = readyGame()
        strike(g, [0, 1, 2])
        let evs = g.drainEvents()
        check(chimes(evs) == [.tide, .wind, .stone] && evs.contains(.droneBloom) && evs.contains(.drone(0, true)) && evs.contains(.drone(1, true)) && evs.contains(.drone(2, true)), "plates: tide, wind, stone in order: each rings and is held, and the chord blooms")
        check(!g.state.has(Game.doorOpenFlag), "plates: the door is not open at the third strike: the lamp has yet to answer")
        g.simulate(seconds: TonePlatePuzzle.Timing.answerDelay + 0.3)
        check(chimes(g.drainEvents()).contains(.lens) && !g.state.has(Game.doorOpenFlag), "plates: then the lamp answers (the lens's chime), and the door is not yet open")
        g.simulate(seconds: TonePlatePuzzle.Timing.openDelay + 0.3)
        check(g.state.has(Game.doorOpenFlag), "plates: and then the door is open")
        step(g)
        check(g.interiorApplied && g.interactables.first { $0.id == "lh_door" }?.enabled == false, "plates: the inside is real, and the door is no longer there to try")
        // After it is open the plates only ring.
        _ = g.drainEvents(); strike(g, [2, 0])
        check(chimes(g.drainEvents()) == [.stone, .tide] && g.tonePlates.sequence.isEmpty, "plates: once the door is open the plates only ring")

        // F05 S1 (#67): the user's own state: pages 1, 2, 3, 4, 6, 7, 8, 9 (page 5 never found), the altar solved, no contradiction settled, back on Varrow (through a save and a load).
        let u0 = twoWorlds()
        for n in [1, 2, 3, 4, 6, 7, 8, 9] { u0.restorePage(n) }
        u0.state.set("gw_end")
        let u = twoWorlds(); u.restore(u0.makeSave()); _ = u.drainEvents()
        step(u)
        check(u.world == .varrow && u.hasReturned && u.gate.ready && u.gate.cue == nil && u.story.contradictionsResolved.isEmpty, "plates: the user's save (pages 1 2 3 4 6 7 8 9, altar solved, nothing settled): the gate is ready, with no contradiction")
        check(u.interactables.first { $0.id == DoorNote.itemName }?.enabled == true, "plates: the door note can be picked there")
        u.activate(DoorNote.itemName)
        check(u.reading == Story.doorNote && !u.journal.isOpen && u.story.notes == ["door_note"], "plates: reading the door note shows its words on a card, logs it in the Notebook, and does not open the Notebook")
        var click = InputState(); click.click = true
        u.advance(now: 5000, input: InputState())
        check(u.reading == Story.doorNote, "plates: the card stays while the player does nothing")
        u.advance(now: 5000.1, input: click)
        check(u.reading == nil, "plates: a click puts the card away")
        u.activate(DoorNote.itemName); var esc = InputState(); esc.escapePressed = true
        u.advance(now: 5000.2, input: esc)
        check(u.reading == nil, "plates: so does Esc")
        u.activate(DoorNote.itemName); u.player.position += SIMD3(0, 0, 4)
        u.advance(now: 5000.3, input: InputState())
        check(u.reading == nil, "plates: and so does walking away from it")
        strike(u, [0, 1, 2]); u.simulate(seconds: TonePlatePuzzle.Timing.answerDelay + TonePlatePuzzle.Timing.openDelay + 1)
        check(u.state.has(Game.doorOpenFlag), "plates: and from that save the plates answer and the door opens (nothing else is asked for)")
        // The same state with the gate asking for a contradiction again (the constant turned back on) is NOT ready: the test above would then fail, so the waiver is what lets this player in.
        check(!GateState.evaluate(altarSolved: true, pages: [1, 2, 3, 4, 6, 7, 8, 9], resolved: [], waived: false).ready, "plates: only the waiver lets that save in (with the constant off it is not ready)")

        // F06 B2b (Q22): the plates glint, faintly, only while they would be answered; the locked door says the stones are listening once back; a click on the ring turns it toward the side aimed at.
        func glint(_ g: Game) -> Float? { g.scene.items.first { $0.name == "tone_plates" }?.uniforms.emissive.w }
        let gl = twoWorlds(); step(gl)
        check(glint(gl) == 0, "plates: in a new game they do not glint")
        for n in [1, 2, 3, 5, 6, 7] { gl.restorePage(n) }
        step(gl)
        check(glint(gl) == 0, "plates: with the pages but no altar they do not glint")
        gl.state.set("gw_end"); for _ in 0..<40 { step(gl) }
        check((glint(gl) ?? 0) > 0 && (glint(gl) ?? 9) <= Game.plateGlintPeak, "plates: with the altar solved and the gate ready they glint, within the peak (\(glint(gl) ?? -1))")
        let thin = twoWorlds(); thin.restorePage(1); thin.state.set("gw_end"); for _ in 0..<40 { step(thin) }
        check(glint(thin) == 0, "plates: with the altar solved but the gate not ready they do not glint (too little read)")
        let sealed = twoWorlds(); for n in [1, 2, 3, 5, 6, 7] { sealed.restorePage(n) }; sealed.state.set("gw_end"); sealed.state.set(Game.pathOrenFlag); for _ in 0..<40 { step(sealed) }
        check(glint(sealed) == 0, "plates: after Oren's route (the plates sealed) they do not glint")
        gl.simulate(seconds: 0.2); strike(gl, [0, 1, 2]); gl.simulate(seconds: 6); step(gl)
        check(gl.state.has(Game.doorOpenFlag) && glint(gl) == 0, "plates: once the door is open the glint is gone")
        let lk = twoWorlds(); lk.state.set("gw_end"); step(lk)
        lk.activate("lh_door"); check(lk.banner == Story.doorLockedReturned, "plates: back with the altar solved the locked door says the stones beside it are listening (\(lk.banner ?? "-"))")
        let nl = twoWorlds(); nl.activate("lh_door"); check(nl.banner == "Locked. The keeper took the key with her.", "plates: before the altar the door's line is the keeper's")
        // The ring: the crosshair on the left half turns it one way, the right half the other, the centre as before.
        let rg = twoWorlds(); for n in [1, 2, 3, 5, 6, 7] { rg.restorePage(n) }; rg.state.set("gw_end"); rg.state.set(Game.doorOpenFlag); step(rg)
        let ring = rg.interactables.first { $0.id == "lens_ring" }!, rc = (ring.min + ring.max) * 0.5
        // A player stands where the lens room's ring is reached (north of it, facing south), and the crosshair is aimed `dx` metres to the right of the ring's centre as THEY see it.
        func aimed(_ dx: Float) -> Int {
            rg.player = Player(position: SIMD3(Layout.lighthouse.x - 0.2, Layout.lighthouse.y + LighthouseInterior.lensFloorY, Layout.lighthouse.z - 1.45), yaw: .pi)
            var d = rc - rg.camera.position
            rg.player.yaw = atan2(d.x, -d.z); rg.player.pitch = asin(d.y / simd_length(d))
            let right = simd_normalize(simd_cross(rg.camera.forward, SIMD3<Float>(0, 1, 0)))
            d = rc + right * dx - rg.camera.position
            rg.player.yaw = atan2(d.x, -d.z); rg.player.pitch = asin(d.y / simd_length(d))
            return rg.ringClickSteps()
        }
        check(aimed(0) == 1 && aimed(-0.4) == -1 && aimed(0.4) == 1, "plates: a click on the ring's left half turns it the Left arrow's way (-1), on its right half and its centre the Right arrow's way (+1)")
        // The direction the ring REALLY turns (signed angle change), for a left-aimed click, a right-aimed click and each arrow key (the key works while the ring is under the crosshair).
        func signedTurn(_ act: () -> Void) -> Float { let b = rg.lensPortal.ringAngle; act(); var d = rg.lensPortal.ringAngle - b; if d > .pi { d -= 2 * .pi }; if d < -.pi { d += 2 * .pi }; return d }
        func clickAt(_ dx: Float) -> Float { _ = aimed(dx); return signedTurn { rg.activate("lens_ring") } }
        func keyAt(_ flip: Int) -> Float { _ = aimed(0); step(rg); return signedTurn { var i = InputState(); i.pageFlip = flip; rg.advance(now: { clock += 0.05; return clock }(), input: i) } }
        let leftClick = clickAt(-0.4), rightClick = clickAt(0.4), leftKey = keyAt(-1), rightKey = keyAt(1)
        check(leftClick < -0.1 && rightClick > 0.1 && leftKey < -0.1 && rightKey > 0.1, "plates: the ring really turns the same way for the left half and the Left arrow (\(leftClick), \(leftKey)), and for the right half and the Right arrow (\(rightClick), \(rightKey))")
        check(rg.interactables.first { $0.id == "lens_ring" }?.prompt.contains("\u{2039}") == true, "plates: and the ring's prompt carries the small arrows")

        // A wrong strike resets softly, and the set can then be done.
        let w = readyGame()
        strike(w, [1])
        let wevs = w.drainEvents()
        check(chimes(wevs) == [.wind, .fail] && wevs.contains(.droneSour) && w.tonePlates.sequence.isEmpty, "plates: wind first is wrong: a soft fail, the tones sour, nothing is held")
        strike(w, [0])
        check(w.tonePlates.sequence.isEmpty, "plates: while the reset is under way a strike only rings")
        w.simulate(seconds: TonePlatePuzzle.Timing.wrongResetDelay + 0.2)
        strike(w, [0, 1, 2]); w.simulate(seconds: 5)
        check(w.state.has(Game.doorOpenFlag), "plates: after the reset the right order opens the door")
        // Out of order half way.
        let h = readyGame()
        strike(h, [0, 2]); h.simulate(seconds: 1.2)
        strike(h, [0, 1, 2]); h.simulate(seconds: 5)
        check(h.state.has(Game.doorOpenFlag), "plates: tide then stone is wrong half way; after the reset the order is whole again")

        // A partial set stays (no time limit), and completes later.
        let p = readyGame()
        strike(p, [0, 1]); p.simulate(seconds: 30)
        check(p.tonePlates.sequence == [0, 1] && !p.state.has(Game.doorOpenFlag), "plates: two plates struck and left for 30 s: still two, no door")
        strike(p, [2]); p.simulate(seconds: 5)
        check(p.state.has(Game.doorOpenFlag), "plates: the third, much later, completes it")
        // Repeating a plate is a wrong strike.
        let r = readyGame()
        strike(r, [0, 0])
        check(chimes(r.drainEvents()).contains(.fail), "plates: the same plate twice is wrong (a soft fail)")
        r.simulate(seconds: TonePlatePuzzle.Timing.wrongResetDelay + 0.2)
        check(r.tonePlates.sequence.isEmpty, "plates: and the set starts again")

        // The gate: the chord blooms, but the lamp does not answer until the gate is ready; the cue says what kind of thing is missing, and the plates reset.
        let n = twoWorlds()
        n.state.set("gw_end"); n.restorePage(1); n.restorePage(5)
        _ = n.drainEvents()
        strike(n, [0, 1, 2])
        let nevs = n.drainEvents()
        check(nevs.contains(.droneBloom), "plates: with too little read, the right order still blooms the chord")
        n.simulate(seconds: TonePlatePuzzle.Timing.answerDelay + 0.3)
        check(n.banner == GateState.cueTooLittle && !n.state.has(Game.doorOpenFlag), "plates: and the gate's quiet line is shown, the door stays shut (\(n.banner ?? "no banner"))")
        n.simulate(seconds: TonePlatePuzzle.Timing.unansweredResetDelay + 0.5)
        check(n.tonePlates.sequence.isEmpty && !n.state.has(Game.doorOpenFlag), "plates: unanswered, they reset")
        for k in [2, 3, 6, 7] { n.restorePage(k) }
        n.story.contradictionsResolved = ["who-left"]
        strike(n, [0, 1, 2]); n.simulate(seconds: 5)
        check(n.state.has(Game.doorOpenFlag), "plates: once the gate is ready the same order opens the door")
        let early = twoWorlds()                                                          // before the Glass Wood: no altar, nothing said
        strike(early, [0, 1, 2]); early.simulate(seconds: 6)
        check(!early.state.has(Game.doorOpenFlag) && early.banner == nil, "plates: before the Glass Wood the right order does nothing and says nothing")

        // The door note goes with the door when it opens.
        let nn = readyGame()
        step(nn)
        check(nn.scene.items.first { $0.name == DoorNote.itemName }?.hidden == false, "plates: the note is on the door while it is shut")
        strike(nn, [0, 1, 2]); nn.simulate(seconds: 5); step(nn)
        check(nn.scene.items.first { $0.name == DoorNote.itemName }?.hidden == true, "plates: and gone when the door is open")

        // The door swings: shut before, swinging after (the leaf's own model turns about its hinge), wide open at the end; a game loaded with it open shows it open at once.
        let sw = readyGame(); step(sw)
        func leafModel(_ g: Game) -> float4x4? { g.scene.items.first { $0.name == "lh_door_leaf" }?.uniforms.model }
        func same(_ a: float4x4?, _ b: float4x4) -> Bool { a.map { m in simd_length(m.columns.0 - b.columns.0) < 1e-4 && simd_length(m.columns.1 - b.columns.1) < 1e-4 && simd_length(m.columns.2 - b.columns.2) < 1e-4 && simd_length(m.columns.3 - b.columns.3) < 1e-4 } ?? false }
        check(same(leafModel(sw), Lighthouse.doorLeafModel(open: 0)) && sw.doorAngle == 0, "plates: the door leaf is shut while the door is")
        strike(sw, [0, 1, 2]); sw.simulate(seconds: TonePlatePuzzle.Timing.answerDelay + TonePlatePuzzle.Timing.openDelay + 0.3)
        step(sw); sw.simulate(seconds: Game.doorSwingSeconds / 2)
        let mid = sw.doorAngle
        check(sw.state.has(Game.doorOpenFlag) && mid > 0.1 && mid < Game.doorSwing - 0.1, "plates: when the door opens the leaf starts to swing (\(mid) of \(Game.doorSwing) rad)")
        sw.simulate(seconds: Game.doorSwingSeconds + 0.5)
        check(abs(sw.doorAngle - Game.doorSwing) < 1e-3 && same(leafModel(sw), Lighthouse.doorLeafModel(open: Game.doorSwing)), "plates: and ends wide open (about 80 degrees)")
        let loaded = twoWorlds(); loaded.restore(sw.makeSave())
        check(abs(loaded.doorAngle - Game.doorSwing) < 1e-3 && same(leafModel(loaded), Lighthouse.doorLeafModel(open: Game.doorSwing)), "plates: a game loaded with the door open shows it open at once")

        // Saved open, loaded open.
        let back = twoWorlds(); back.restore(g.makeSave()); step(back)
        check(back.state.has(Game.doorOpenFlag) && back.interiorApplied, "plates: a game saved with the door open loads with it open")

        // The plates are on the wall east of the door in the order of altitude, and a ray on each picks it (not the door).
        let lh = Layout.lighthouse
        let xs = (0..<3).map { TonePlates.world($0).x - lh.x }
        check(xs == xs.sorted() && xs[0] > 1.4 && xs[2] < 3.0, "plates: they are east of the door in order, tide nearest (\(xs))")
        let pg = readyGame(); step(pg)
        var picks: [String?] = []
        for k in 0..<3 {
            let c = TonePlates.world(k)
            for d: Float in [0.8, 1.5, 3.0] {
                let eye = SIMD3(c.x + 0.0, c.y, c.z + d)
                picks.append(Interaction.pick(origin: eye, dir: SIMD3(0, 0, -1), in: pg.interactables)?.id)
            }
        }
        check(picks == (0..<3).flatMap { k in [String?](repeating: names[k], count: 3) }, "plates: a ray at each plate picks that plate from 0.8, 1.5 and 3 m (\(picks))")
        check(TonePlates.names.allSatisfy { pg.scene.has($0) == false } && pg.scene.has("tone_plates"), "plates: they are one scene item, and need no hidden pieces")

        // The bot: walks to the plates, touches them in order with real clicks, and the door opens.
        let b = readyGame()
        let bot = PlaythroughBot(b)
        b.player = Player(position: SIMD3(lh.x + 2.1, lh.y + 0.9, lh.z + 9), yaw: .pi)
        b.player.position.y = b.scene.groundHeight(x: b.player.position.x, z: b.player.position.z)
        var ok = bot.walk(to: SIMD3(lh.x + 2.1, 0, lh.z + 5.4), within: 0.7, straight: true)
        for k in 0..<3 { ok = ok && bot.click(names[k]); bot.wait(0.4) }
        bot.wait(TonePlatePuzzle.Timing.answerDelay + TonePlatePuzzle.Timing.openDelay + 1)
        check(ok && b.state.has(Game.doorOpenFlag), "plates: a bot walks up, touches tide, wind, stone with real clicks, and the door opens")
        let bw = readyGame()
        let bbot = PlaythroughBot(bw)
        bw.player = Player(position: SIMD3(lh.x + 2.1, lh.y + 0.9, lh.z + 9), yaw: .pi)
        bw.player.position.y = bw.scene.groundHeight(x: bw.player.position.x, z: bw.player.position.z)
        _ = bbot.walk(to: SIMD3(lh.x + 2.1, 0, lh.z + 5.4), within: 0.7, straight: true)
        for k in [1, 0, 1, 2] { _ = bbot.click(names[k]); bbot.wait(0.4) }
        bbot.wait(6)
        check(!bw.state.has(Game.doorOpenFlag), "plates: a bot touching them wrongly (wind, tide, wind, stone) does not open the door")
    }
}

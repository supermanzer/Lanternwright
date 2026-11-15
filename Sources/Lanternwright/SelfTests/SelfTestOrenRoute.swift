import Foundation
import Metal
import simd

/// S05.3 (builder B, B5): Oren's route through the Archive: A0 the tide marks (shared), O1 the orrery, O2 the prism ring fed by the dome's windows (Game/OrenRoute.swift). Rules on the data; then a bot that
/// arrives at the open quay and plays O1 by real walking and clicks (no teleport), watching only what is in view (an arm's bead brightens as it lines up), with a save and a load in the middle; then the ring.
extension SelfTestRunner {
    /// Is arm k's bead bright now (what the player sees: the arm is lined up with its window)?
    func armHot(_ g: Game, _ k: Int) -> Bool { (g.scenes[.tideArchive]?.items.first { $0.name == Orrery.armName(k) }?.uniforms.emissive.w ?? 0) > 0.5 }

    /// A0 and O1 by real walking and clicks from the open quay: wait at the quay for the marks, walk to the orrery, and for each arm (the first `upTo`) turn the collar to the notch before its own, watch for the
    /// bead, and turn the last notch as it brightens. Returns whether that many windows are lit.
    func orenPrerequisites(_ g: Game, _ bot: PlaythroughBot, upTo: Int = 3) -> Bool {
        guard let r = g.orenRoute else { return false }
        var w: Float = 0
        while !(g.ilseRoute?.marksDone ?? false) && w < 100 { bot.wait(1); w += 1 }
        let o = ArchiveLayout.orrery
        guard bot.walk(to: SIMD3(o.x - 2.6, 0, o.z), within: 1.2, timeout: 400) else { print("orenPrerequisites: could not walk to the orrery: ended \(bot.feet) for \(o)"); return false }
        for k in 0..<upTo where !r.lit(k) {
            var clicks = 0
            while (r.notch + 1) % Orrery.collarDetents != OrenRoute.notch(forArm: k) && clicks < 8 { _ = bot.click(OrenRoute.collarName); bot.wait(0.1); clicks += 1 }
            var s: Float = 0
            while !armHot(g, k) && s < 100 { bot.wait(0.1); s += 0.1 }
            _ = bot.click(OrenRoute.collarName); bot.wait(0.2)
        }
        bot.wait(OrenRoute.windowSeconds + 0.5)
        return r.litCount >= upTo
    }

    func runOrenRoute() {
        guard name == "all" || name == "orenroute" else { return }
        typealias R = OrenRoute
        let fade = Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.8

        // ---- The data. The notch of each arm follows the beam's rhythm ranks; the other notches catch nothing; the arms' alignments are far enough apart to turn one notch between them.
        check(Orrery.collarDetents == 6 && (0..<3).map(R.notch(forArm:)) == [1, 2, 3] && (0..<Orrery.collarDetents).map(R.arm(atNotch:)) == [nil, 0, 1, 2, nil, nil], "orenroute: notches 1, 2, 3 catch the tide's, wind's and stone's arms; 0, 4 and 5 catch nothing")
        let al = (0..<3).map(Orrery.alignmentClock)
        check(al[0] < al[1] && al[1] < al[2] && (al[1] - al[0]) > 8 && (al[2] - al[1]) > 8, "orenroute: the arms line up in the stones' order, at least 8 s apart (\(al.map { String(format: "%.1f", $0) }))")
        let width = 2 * Orrery.alignTolerance / (2 * .pi) * Tide.period
        check(width > 2 && width < 6, "orenroute: an arm stays lined up for \(String(format: "%.1f", width)) s (long enough to turn a notch, short enough to be a moment)")
        check(R.windowFlags.count == 3 && Set(R.collarFlags).count == Orrery.collarDetents && R.windowsFlag == "ti_windows", "orenroute: the flags")

        // ---- A game on Oren's route in the Archive.
        func world3() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device), .tideArchive: TideArchive.build(device: device)]) }
        func arrive() -> (Game, PlaythroughBot)? {
            let g = world3()
            for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
            g.state.set("gw_end"); g.state.set(Game.doorOpenFlag); g.simulate(seconds: 0.1)
            guard g.beginRoute(.oren) else { return nil }
            g.simulate(seconds: fade)
            let bot = PlaythroughBot(g); bot.wait(0.5)
            return (g, bot)
        }
        guard let (g, bot) = arrive(), let route = g.orenRoute, let tide = g.tideArchive else { check(false, "orenroute: Oren's route could not begin"); return }
        let arch = { g.scenes[.tideArchive]!.archive }
        check(g.world == .tideArchive && route.isActive && tide.hasLens && route.litCount == 0, "orenroute: Oren arrives in the Archive with the lens, and no window lit")
        check(arch().prismLit == [false, false, false] && (0..<3).allSatisfy { !tide.componentLit($0) }, "orenroute: with the dome dark the prism has no components (dim ghosts: \(arch().prismLit))")
        check(g.interactables.first { $0.id == R.collarName }?.enabled == true && g.orenRoute?.persistentFlags.contains("ti_windows") == true, "orenroute: the collar can be touched")

        // The walk to the orrery from the quay, with no teleport; before the marks are counted the collar clicks and nothing is asked of it, and the light is nudged.
        let o = ArchiveLayout.orrery
        let walked = bot.walk(to: SIMD3(o.x - 2.6, 0, o.z), within: 1.2, timeout: 400)
        check(walked, "orenroute: the bot walks from the open quay to the orrery by the world's own paths (ended \(bot.feet))")
        check(!(g.ilseRoute?.marksDone ?? true), "orenroute: the marks are not counted yet (the bot left the quay at the start)")
        check(g.guideFlare == 1, "orenroute: the guide light is steady before anything is tried too early")
        _ = bot.click(R.collarName); bot.wait(0.2)
        check(route.notch == 1 && route.litCount == 0 && g.guideFlare > 1, "orenroute: the collar turns to the first notch before the marks are counted: no window lights, and the guide light flares (\(g.guideFlare))")
        bot.wait(Game.nudgeSeconds + 0.5)
        check(g.guideFlare == 1, "orenroute: the flare is over after \(Game.nudgeSeconds) s")

        // A0 at the open quay (Oren's own), then back.
        let atQuay = bot.walk(to: SIMD3(ArchiveLayout.openEnd.x - 3, 0, ArchiveLayout.openEnd.z - 4), within: 3, timeout: 400)
        var waited: Float = 0
        while !(g.ilseRoute?.marksDone ?? false) && waited < 100 { bot.wait(1); waited += 1 }
        check(atQuay && g.ilseRoute?.marksDone == true, "orenroute: A0: standing at Oren's quay the three marks are counted (\(Int(waited)) s)")
        check(bot.walk(to: SIMD3(o.x - 2.6, 0, o.z), within: 1.2, timeout: 400), "orenroute: and back to the orrery")

        // O1: a notch turned to at the wrong moment catches nothing; at the right moment the arm is caught and its window lights.
        var clicks = 0
        while (route.notch + 1) % Orrery.collarDetents != R.notch(forArm: 0) && clicks < 8 { _ = bot.click(R.collarName); bot.wait(0.1); clicks += 1 }
        var s: Float = 0
        while armHot(g, 0) && s < 30 { bot.wait(0.1); s += 0.1 }
        _ = bot.click(R.collarName); bot.wait(0.2)
        check(route.notch == 1 && !route.lit(0) && arch().armStops[0] == nil, "orenroute: O1: the collar turned to the tide's notch while its arm is NOT lined up catches nothing (the arm runs on)")
        for _ in 0..<(Orrery.collarDetents - 1) { _ = bot.click(R.collarName); bot.wait(0.1) }
        check(orenPrerequisites(g, bot, upTo: 1) && route.lit(0) && !route.lit(1) && route.litCount == 1, "orenroute: O1: caught at the right moment, the tide's arm lights its window")
        let held0 = arch().armStops[0]
        let windowGlow = { (g: Game, k: Int) in g.scenes[.tideArchive]?.items.first { $0.name == DomeWindows.name(k) }?.uniforms.emissive.w ?? -1 }
        check(held0 != nil && abs(Orrery.wrap(Orrery.armAngle(0, clock: held0!) - Orrery.bearing(0))) < 0.01 && windowGlow(g, 0) > 1 && windowGlow(g, 1) < 0.1, "orenroute: the caught arm stands at its window and the window glows (\(String(format: "%.2f", windowGlow(g, 0)))), the others are dark")
        check(arch().prismLit == [true, false, false] && tide.componentLit(0) && !tide.componentLit(1), "orenroute: the prism has the first component only")
        bot.wait(1)
        check(arch().armStops[0] == held0, "orenroute: the caught arm stays caught as the tide goes on")

        // A save with one window lit, loaded in a fresh game: arms, windows, collar and the prism come back.
        _ = orenPrerequisites(g, bot, upTo: 2)
        check(route.litCount == 2 && !route.windowsDone, "orenroute: two windows lit")
        let saved = g.makeSave()
        guard let (g3, bot3) = arrive(), let r3 = g3.orenRoute else { check(false, "orenroute: a second game could not begin"); return }
        g3.restore(saved); bot3.wait(0.6)
        let a3 = g3.scenes[.tideArchive]!.archive
        check(r3.lit(0) && r3.lit(1) && !r3.lit(2) && r3.notch == route.notch, "orenroute: a save with two windows lit loads with them lit and the collar where it was (notch \(r3.notch))")
        check(a3.armStops[0] != nil && a3.armStops[1] != nil && a3.armStops[2] == nil && a3.prismLit == [true, true, false] && windowGlow(g3, 0) > 1 && windowGlow(g3, 1) > 1 && windowGlow(g3, 2) < 0.1, "orenroute: and the held arms, the windows and the prism's components are put back on the new scene")
        // The third, from the loaded game.
        let finished = orenPrerequisites(g3, bot3, upTo: 3)
        check(finished && r3.windowsDone && g3.state.has(R.windowsFlag) && g3.scenes[.tideArchive]!.archive.prismLit == [true, true, true], "orenroute: from the loaded game the third arm is caught: three windows lit, the prism whole (\(r3.litCount))")

        // O2: the ring rests on a component only while its window is lit (a rule test on a game with the flags set).
        if let (g2, _) = arrive(), let t2 = g2.tideArchive {
            let steps = { (k: Int) in Int(((TideArchivePuzzle.beamTargets[k] - t2.ringAngle) / TideArchivePuzzle.ringStep).rounded()) }
            t2.turn(steps(2))
            check(t2.aimedSluice == nil, "orenroute: O2: the ring turned onto the stone's mark with its window dark rests on nothing")
            g2.state.set(R.windowFlags[2]); g2.simulate(seconds: 0.2)
            check(t2.aimedSluice == 2, "orenroute: O2: once that window is lit the same ring angle is the stone's mark")
        }
        // Ilse's route does not see the windows: all components, as before S05.
        if let ilse = Optional(world3()) {
            if let sc = ilse.scenes[.tideArchive] { DomeWindows.set(sc, 1, lit: 1); Orrery.hold(sc, 1, at: 10) }          // set from outside BEFORE the game's first tick (as `--state` does: a check made after that tick is blind to a reset on it)
            for n in [1, 2, 3, 5, 6, 7] { ilse.restorePage(n) }
            ilse.state.set("gw_end"); ilse.state.set(Game.doorOpenFlag); ilse.simulate(seconds: 0.1)
            if ilse.beginRoute(.ilse) { ilse.simulate(seconds: fade); check(ilse.scenes[.tideArchive]!.archive.prismLit == [true, true, true] && ilse.tideArchive!.componentLit(1), "orenroute: on Ilse's route the prism keeps all three components")
                // Off Oren's route this file leaves A's scene alone (a window A's own state lit stays lit; found reading the frame of `--state orreryheld`).
                if let sc = ilse.scenes[.tideArchive] { ilse.simulate(seconds: 0.5)
                    check(sc.archive.windowLit[1] == 1 && sc.archive.armStops[1] == 10, "orenroute: off Oren's route a window or a held arm set from outside is not reset") } }
        }
    }
}

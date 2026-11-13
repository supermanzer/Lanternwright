import Foundation
import simd

/// F09.8: the Varrow opening (#112 the water to the lens is a barrier only the quay crosses; #113 the stones are off the main route; #114 what to do after the lighthouse is lit).
extension SelfTestRunner {
    func runVarrowOpening() {
        guard name == "all" || name == "varrow-opening" else { return }
        let scene = Scene.makeWorld(device: device)
        let t = scene.terrain!
        let a = SIMD2(Layout.causewayStart.x, Layout.causewayStart.z), b = SIMD2(Layout.isletCenter.x, Layout.isletCenter.z)
        // The channel: on the causeway's line the seabed between the shores is at least 1.4 m under the sea at its centre.
        var deepest: Float = 0, deepAt: Float = 0
        for i in 0...200 { let p = a + (b - a) * (Float(i) / 200); let h = t.sampleHeight(x: p.x, z: p.y); if h < deepest { deepest = h; deepAt = Float(i) / 200 * simd_length(b - a) } }
        check(deepest <= -1.4, "varrow opening: the strait is at least 1.4 m deep at its centre (\(String(format: "%.2f", deepest)) m at \(Int(deepAt)) m from the landing)")
        // No ford anywhere: flood the ground a player can wade (not deeper than 0.4 m under the sea) from the causeway's landing; the islet must stay out of reach.
        let lo = SIMD2<Float>(-260, -400), hi = SIMD2<Float>(200, -190), cell: Float = 3
        let nx = Int((hi.x - lo.x) / cell) + 1, nz = Int((hi.y - lo.y) / cell) + 1
        func wadeable(_ i: Int, _ j: Int) -> Bool { t.sampleHeight(x: lo.x + Float(i) * cell, z: lo.y + Float(j) * cell) > Player.sea + Player.minGround }
        func index(_ p: SIMD2<Float>) -> (Int, Int) { (Int(((p.x - lo.x) / cell).rounded()), Int(((p.y - lo.y) / cell).rounded())) }
        func flood(from start: SIMD2<Float>) -> (Set<Int>, Bool) {
            var seen = Set<Int>(), stack = [index(start)], reachedIslet = false
            let (ti, tj) = index(b)
            while let (i, j) = stack.popLast() {
                guard i >= 0, j >= 0, i < nx, j < nz, wadeable(i, j), seen.insert(j * nx + i).inserted else { continue }
                if abs(i - ti) <= 2 && abs(j - tj) <= 2 { reachedIslet = true }
                for di in -1...1 { for dj in -1...1 where di != 0 || dj != 0 { stack.append((i + di, j + dj)) } }
            }
            return (seen, reachedIslet)
        }
        let (reach, islet) = flood(from: a)
        check(reach.count > 500 && !islet, "varrow opening: no wadeable ford: from the north landing a player can wade over \(reach.count) cells of the shore (3 m grid) but never reaches the islet's lens (reached: \(islet))")
        // Mutation: with the strait left as it was (a 0.4 m wading limit lowered to a shoal), the same flood reaches the islet.
        let shoal = Player.minGround - 2.4
        func wadeShoal(_ i: Int, _ j: Int) -> Bool { t.sampleHeight(x: lo.x + Float(i) * cell, z: lo.y + Float(j) * cell) > shoal + Player.sea }
        var sSeen = Set<Int>(), sStack = [index(a)], sReached = false
        let (ti, tj) = index(b)
        while let (i, j) = sStack.popLast() {
            guard i >= 0, j >= 0, i < nx, j < nz, wadeShoal(i, j), sSeen.insert(j * nx + i).inserted else { continue }
            if abs(i - ti) <= 2 && abs(j - tj) <= 2 { sReached = true }
            for di in -1...1 { for dj in -1...1 where di != 0 || dj != 0 { sStack.append((i + di, j + dj)) } }
        }
        check(sReached, "varrow opening mutation: if a player could wade 2.8 m (the old shoal was under that) the flood WOULD reach the islet, so the check can fail")
        // The quay still crosses: with the causeway up a bot walks from the landing to the lens; before, it cannot.
        let g = Game(scenes: [.varrow: Scene.makeWorld(device: device)])
        g.restorePage(1); g.simulate(seconds: 0.2)
        let landing = SIMD3(Layout.causewayStart.x, 0, Layout.causewayStart.z), lens = SIMD3(Layout.isletCenter.x, 0, Layout.isletCenter.z + 6)
        g.player = Player(position: SIMD3(landing.x, g.scene.groundHeight(x: landing.x, z: landing.z), landing.z), yaw: 0)
        let bot = PlaythroughBot(g); bot.wait(0.3)
        let before = bot.walk(to: lens, within: 4, timeout: 60, straight: true)
        check(!before, "varrow opening: before the causeway is up the bot walking straight at the lens does not get there (ended \(Int(bot.feet.x)), \(Int(bot.feet.z)))")
        g.state.set("causewayUp"); g.scene.walkables[g.scene.causewayIndex!].enabled = true
        g.player = Player(position: SIMD3(landing.x, g.scene.groundHeight(x: landing.x, z: landing.z), landing.z), yaw: 0)
        bot.forgetStray(); bot.wait(0.3)
        let after = bot.walk(to: lens, within: 4, timeout: 120, straight: true)
        check(after, "varrow opening: with the causeway up the bot walks across to the lens (ended \(Int(bot.feet.x)), \(Int(bot.feet.z)))")
        // #113: the order is the quay, "it does not rise", then the search. A fresh game: the stones ring but do not wake; the quay's own lamp is dark and says the quay is not raised; standing at the quay
        // wakes the stones; solving them lights the quay's lamp.
        var clock = 50_000.0
        func item(_ g: Game, _ n: String) -> DrawItem? { g.scene.items.first { $0.name == n } }
        func adv(_ g: Game, _ seconds: Float) { for _ in 0..<Int(seconds * 60) { clock += 1.0 / 60; g.advance(now: clock, input: InputState()) } }          // render frames: the game's syncs (note, lamp, quay) run there
        let fresh = Game(scenes: [.varrow: Scene.makeWorld(device: device)])
        adv(fresh, 0.2)
        fresh.activate("stone_tide")
        check(!fresh.state.has("lit_tide") && fresh.state.has(Notebook.struckFlag(.tide)) && !fresh.state.has(Game.quaySeenFlag), "varrow opening: before the quay has been seen the tide stone rings (and the Notebook hears it) but does not wake")
        fresh.activate("stone_wind"); fresh.activate("stone_tide"); fresh.activate("stone_summit"); fresh.simulate(seconds: 3)
        check(!fresh.state.has("solved") && !fresh.state.has("lit_wind"), "varrow opening: the three stones struck in the right order from the start solve nothing")
        let lamp0 = fresh.scene.items.first { $0.name == QuayMarker.lampName }!.uniforms.emissive.w
        check(lamp0 == 0 && fresh.interactables.first { $0.id == QuayMarker.interactableName }?.enabled == true && fresh.interactables.first { $0.id == QuayMarker.interactableName }?.prompt == "The quay is not raised", "varrow opening: the quay's lamp is dark and its prompt says the quay is not raised")
        let qs = Layout.causewayStart
        fresh.player = Player(position: SIMD3(qs.x, fresh.scene.groundHeight(x: qs.x, z: qs.z), qs.z + 6), yaw: 0)
        adv(fresh, 0.3)
        check(fresh.state.has(Game.quaySeenFlag), "varrow opening: standing at the unfinished quay wakes the stones")
        fresh.activate(QuayMarker.interactableName)
        check(fresh.banner?.contains("Nothing answers") == true, "varrow opening: touching the quay's lamp: \"\(fresh.banner ?? "")\"")
        for id in LighthousePuzzle.order { fresh.activate("stone_\(id.name)"); fresh.simulate(seconds: 0.7) }
        adv(fresh, LighthousePuzzle.Timing.total + 1)
        check(fresh.state.has("solved") && fresh.state.has("causewayUp"), "varrow opening: after the quay, the stones solve the puzzle as before and the causeway rises")
        check((fresh.scene.items.first { $0.name == QuayMarker.lampName }?.uniforms.emissive.w ?? 0) > 1 && fresh.interactables.first { $0.id == QuayMarker.interactableName }?.enabled == false, "varrow opening: the quay's lamp is lit once the quay is up")
        let kept = Game(scenes: [.varrow: Scene.makeWorld(device: device)]); kept.restore(fresh.makeSave()); adv(kept, 0.2)
        check(kept.state.has(Game.quaySeenFlag), "varrow opening: a save keeps that the quay has been seen")

        // #114: with the quay up, a guide light leads to Oren's lens and parks there; it stays when the player turns round, and goes when the lens has been touched.
        let vg = Game(scenes: [.varrow: Scene.makeWorld(device: device)]); adv(vg, 0.2)
        check(vg.varrowGuide == nil && item(vg, GuideLanterns.lanternName)?.hidden == true, "varrow guide: before the quay is up there is no guide light on Varrow")
        vg.state.set("causewayUp"); vg.state.set("solved")
        let lensXZ = SIMD2(PuzzleProps.lensRestPosition.x, PuzzleProps.lensRestPosition.z + 2.5)
        let net = Layout.Navigation.active(for: .varrow)!
        let spot = SIMD2(Layout.lighthouse.x, Layout.lighthouse.z)
        vg.player = Player(position: SIMD3(spot.x, vg.scene.groundHeight(x: spot.x, z: spot.y), spot.y + 8), yaw: 0); adv(vg, 0.3)
        check(vg.varrowGuide != nil && item(vg, GuideLanterns.lanternName)?.hidden == false, "varrow guide: with the quay up the light appears ahead of the player")
        let walk = net.route(from: SIMD2(vg.player.position.x, vg.player.position.z), to: lensXZ)
        var guideOK = true, prevS: Float = 0; let along = GuidePath(walk)
        for q in walk { vg.player.position = SIMD3(q.x, vg.scene.groundHeight(x: q.x, z: q.y), q.y); adv(vg, 0.6); let s2 = along.progress(of: vg.varrowGuide!); guideOK = guideOK && s2 >= prevS - 0.05; prevS = s2 }
        adv(vg, 25)
        check(guideOK && simd_length(vg.varrowGuide! - lensXZ) < 0.6, "varrow guide: walking the route it only ever goes forward and parks at the lens (\(String(format: "%.1f", simd_length(vg.varrowGuide! - lensXZ))) m off)")
        let parkedAt = vg.varrowGuide!; var drift: Float = 0
        for k in 0..<20 { let q = k % 2 == 0 ? spot : lensXZ + SIMD2(0, 4); vg.player.position = SIMD3(q.x, vg.scene.groundHeight(x: q.x, z: q.y), q.y); adv(vg, 1); drift = max(drift, simd_length(vg.varrowGuide! - parkedAt)) }
        check(drift < 0.1, "varrow guide: the player turns round and walks away and back for 20 s: the light stays within 0.1 m of the lens (\(String(format: "%.3f", drift)) m)")
        vg.state.set("lensTouched"); adv(vg, 0.3)
        check(vg.varrowGuide == nil && item(vg, GuideLanterns.lanternName)?.hidden == true, "varrow guide: the lens touched, the light is gone")

        // #114: the first note on the door, Ilse's two lines; the return note takes over once the player is back through the lens.
        let nf = Game(scenes: [.varrow: Scene.makeWorld(device: device)]); adv(nf, 0.2)
        check(item(nf, DoorNote.firstItemName)?.hidden == false && nf.interactables.first { $0.id == DoorNote.firstItemName }?.enabled == true && item(nf, DoorNote.itemName)?.hidden == true, "varrow opening: in a new game the first note is on the door and the return note is not")
        nf.activate(DoorNote.firstItemName)
        check(nf.reading == Story.doorNoteFirst && Story.doorNoteFirst.split(separator: "\n").count == 2 && !Story.doorNoteFirst.lowercased().contains("stone") && nf.story.notes == ["door_note_first"], "varrow opening: reading it shows Ilse's two lines on the card (no stone named) and logs it: \"\(Story.doorNoteFirst.replacingOccurrences(of: "\n", with: " / "))\"")
        nf.putAwayReading(); nf.state.set("gw_end"); adv(nf, 0.3)
        check(item(nf, DoorNote.firstItemName)?.hidden == true && nf.interactables.first { $0.id == DoorNote.firstItemName }?.enabled == false && item(nf, DoorNote.itemName)?.hidden == false, "varrow opening: back through the lens the first note is gone and the return note is there")
    }
}

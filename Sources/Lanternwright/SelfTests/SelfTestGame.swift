import Foundation
import Metal
import simd

/// Self-tests: game.
extension SelfTestRunner {
    func runGame() {
        if name == "all" || name == "journal" {
            // F01 W7: reading a page opens the journal on the Pages tab, on that page, even if the Notebook was the last tab open.
            let jg = Game(scene: Scene.makeWorld(device: device))
            jg.journal.tab = .notebook
            jg.activate("page_2")
            check(jg.journal.isOpen && jg.journal.tab == .ilse && jg.journal.tabPages[jg.journal.current].number == 2, "reading a new page opens the journal on its author's tab at that page (was the Notebook)")
            jg.activate("page_1")
            check(jg.journal.tab == .ilse && jg.journal.tabPages[jg.journal.current].number == 1, "reading another page shows that page")
            jg.toggleJournal(); jg.toggleJournal()
            check(jg.journal.isOpen && jg.journal.tabPages[jg.journal.current].number == 1 && jg.journal.tab == .ilse, "J closes and reopens on the page just read")
            jg.journal.tab = .notebook; jg.toggleJournal(); jg.toggleJournal()
            check(jg.journal.tab == .notebook, "plain J reopens on the last used tab")
            var j = JournalState()
            check(j.collectedPages.isEmpty, "journal starts empty")
            j.collect(3); j.collect(1)
            check(j.collectedPages.map(\.number) == [1, 3] && j.tabPages[j.current].number == 1, "pages are ordered by number and the newest collected page is shown")
            j.flip(1); check(j.tabPages[j.current].number == 3, "flip forward")
            j.flip(1); check(j.tabPages[j.current].number == 3, "flipping past the end stays on the last page")
            j.flip(-5); check(j.current == 0, "flipping past the start stays on the first page")
            check(JournalContent.pages.count == 9 && JournalContent.pages.map(\.number) == Array(1...9) && JournalContent.pages.allSatisfy { !$0.text.isEmpty }, "all nine journal pages (5 Ilse, 4 Oren) exist, numbered 1-9, with text")
        }
        if name == "all" || name == "puzzle" {
            func freshGame() -> Game { Game(scene: Scene.makeWorld(device: device)) }
            func chimes(_ events: [GameEvent]) -> [ChimeKind] { events.compactMap { if case .chime(let k) = $0 { return k } else { return nil } } }
            func lit(_ g: Game) -> [Bool] { StoneID.allCases.map { g.state.has("lit_\($0.name)") } }

            // 1. Wrong first stone: fail chime, nothing lights, and after the delay everything is reset.
            var g = freshGame()
            g.puzzle.strike(.wind)
            check(chimes(g.drainEvents()) == [.wind, .fail] && lit(g) == [false, false, false], "striking the wind stone first rings, then fails; nothing lights")
            g.simulate(seconds: 1)
            g.puzzle.strike(.tide)
            check(lit(g) == [true, false, false], "after the reset delay the puzzle accepts the right first stone")

            // 2. Right then wrong: everything resets after 0.8 s.
            g = freshGame()
            g.puzzle.strike(.tide); g.simulate(seconds: 1)
            g.puzzle.strike(.summit)
            check(lit(g) == [true, false, false], "a wrong stone does not light, but the earlier one stays lit until the reset")
            g.simulate(seconds: 0.5)
            g.puzzle.strike(.wind)                              // during the reset delay: ignored
            check(g.puzzle.sequence == [.tide], "strikes during the reset delay are ignored")
            g.simulate(seconds: 0.5)
            check(lit(g) == [false, false, false] && g.puzzle.sequence.isEmpty, "0.8 s after a mistake all stones dim and the sequence clears")

            // 3. Striking the same stone twice is wrong.
            g = freshGame()
            g.puzzle.strike(.tide); g.puzzle.strike(.tide)
            check(g.puzzle.sequence == [.tide] && chimes(g.drainEvents()).suffix(1) == [.fail], "striking the same stone twice fails")

            // 3b. The stone drone: each right strike adds a voice, a wrong strike sours it, the solution blooms.
            func drones(_ events: [GameEvent]) -> [String] { events.compactMap {
                switch $0 { case .drone(let i, let on): return "d\(i)\(on ? "+" : "-")"; case .droneSour: return "sour"; case .droneBloom: return "bloom"; default: return nil } } }
            g = freshGame()
            g.puzzle.strike(.tide); g.puzzle.strike(.wind)
            check(drones(g.drainEvents()) == ["d0+", "d1+"], "each correct strike switches on its drone voice")
            g.puzzle.strike(.tide)
            check(drones(g.drainEvents()) == ["sour"], "a wrong strike sours the drone")
            g = freshGame()
            for id in LighthousePuzzle.order { g.puzzle.strike(id); g.simulate(seconds: 0.7) }
            check(drones(g.drainEvents()) == ["d0+", "d1+", "d2+", "bloom"], "the full order builds the chord and blooms it")
            // the synth renders the drone: it adds audible energy when on, and the mix never clips
            func droneBlock(_ on: Bool) -> [Float] {
                let synth = AmbienceSynth(sampleRate: 44100)
                if on { for i in 0..<3 { synth.setDrone(i, on: true) } }
                var l = [Float](repeating: 0, count: 44100 * 3), r = l
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    var done = 0
                    while done < 44100 * 3 { synth.render(frames: 512, left: lp.baseAddress! + done, right: rp.baseAddress! + done); done += 512 }
                } }
                return Array(l[(44100 * 2)...])
            }
            func rmsOf(_ a: [Float]) -> Float { (a.reduce(0) { $0 + $1 * $1 } / Float(a.count)).squareRoot() }
            let bOff = droneBlock(false), bOn = droneBlock(true)
            let droneRms = rmsOf(zip(bOn, bOff).map { $0 - $1 })     // the synth noise is seeded, so the difference is the drone alone
            check(droneRms > 0.02 && (bOn.map { abs($0) }.max() ?? 2) < 1.0, "the drone is clearly audible and the mix never clips (drone rms \(String(format: "%.4f", droneRms)) over a bed of \(String(format: "%.4f", rmsOf(bOff))))")

            // 3c. The notebook: stones are *seen* by walking up to them, *struck* by striking, and only struck ones can be tapped to hear.
            g = freshGame()
            check(Notebook.flags.allSatisfy { !g.state.has($0) }, "a new game has an empty notebook")
            g.player = Player(position: StoneID.wind.position + SIMD3(0, 0, 5), yaw: 0)
            g.simulate(seconds: 0.2)
            check(g.state.has("seen_wind") && !g.state.has("seen_tide") && !g.state.has("struck_wind"), "walking up to the wind stone notes its glyph as seen (not struck)")
            _ = g.drainEvents(); g.playNotebookTone(1)
            check(g.drainEvents().isEmpty, "a seen-but-unstruck glyph makes no sound when tapped")
            g.puzzle.strike(.tide)
            check(g.state.has("struck_tide") && g.state.has("seen_tide"), "striking a stone enters it in the notebook")
            _ = g.drainEvents(); g.playNotebookTone(0)
            check(chimes(g.drainEvents()) == [.tide], "tapping a struck glyph plays that stone's tone")
            var tabIn = InputState(); tabIn.tabPressed = true
            g.journal.isOpen = true
            g.advance(now: 100, input: tabIn)
            check(g.journal.tab == .notebook, "Tab switches the journal to the notebook")
            g.advance(now: 100.1, input: tabIn)
            check(g.journal.tab == .ilse, "Tab switches back to the pages")
            g.journal.isOpen = false
            let nbSave = g.makeSave()
            let nbGame = freshGame(); nbGame.restore(nbSave)
            check(nbGame.state.has("struck_tide") && nbGame.state.has("seen_wind") && !nbGame.state.has("struck_wind"), "the notebook survives a save and restore")

            // 3d. One shared vocabulary: the Glass Wood's murals, pane colours and chime pitches all restate Varrow's stones.
            check(LighthousePuzzle.order == StoneID.allCases, "Varrow's solution order is the stones' own order (tide, wind, stone)")
            check(MirrorCourt.solutionPanes.map { GlassPuzzleProps.color($0) } == LighthousePuzzle.order.map(\.color), "the mirror court's pane colours, in order, are the stones' colours in solution order")
            check(GlassWoodLogic.chimeSolution.map { ToneTable.glassHz[$0] } == LighthousePuzzle.order.map { ToneTable.stoneHz[$0.rawValue] }, "the chime puzzle's solution pitches are the stones' tones in solution order")
            check(zip(ToneTable.droneHz, ToneTable.stoneHz).allSatisfy { abs($0 * 2 - $1) < 0.01 }, "the stone drone is exactly an octave under the stones' tones")
            check(ToneTable.stoneHz == [293.66, 440.00, 587.33] && ToneTable.stoneHz[0] < ToneTable.stoneHz[1] && ToneTable.stoneHz[1] < ToneTable.stoneHz[2], "the stones' tones rise in solution order")

            // 3e. WorldPuzzle: the save's flag list is derived from the registered puzzles, and clicks route to the owning puzzle.
            let archiveWas = Game.tideArchiveEnabled; Game.tideArchiveEnabled = false                          // (S04.9: the Archive's puzzle is on by default; these three count the base game's puzzles)
            g = freshGame()
            check(g.puzzles.count == 3 && g.puzzles[0].world == .varrow, "Varrow-only games register their three puzzles: the stones, the tone plates and the lens portal")
            check(Set(g.persistentFlags) == Set(["solved", "lighthouseLit", "causewayUp", "lensTouched", "route_solved", "path_ilse", "path_oren", "door_open", "portal_open"] + Notebook.flags), "persistent flags come from the puzzles (+ the game's own flags, S03: the two route flags, the lighthouse door and the portal are saved)")
            g.activate("stone_tide")
            check(g.state.has("lit_tide"), "activating a stone id routes to the lighthouse puzzle")
            let both = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
            check(both.puzzles.map(\.world) == [.varrow, .varrow, .varrow, .glassWood], "a game with both worlds registers its puzzles: Varrow's stones, tone plates and lens portal, then the Glass Wood's")
            check(Set(["gw_mirrors", "gw_chimes", "gw_altar", "gw_end"]).isSubset(of: Set(both.persistentFlags)), "the Glass Wood's flags appear in the derived save list")
            check(!both.puzzles[3].handles("gw_return") && both.puzzles[3].handles("gw_mirror_0") && !both.puzzles[0].handles("gw_mirror_0"), "ownership: the return ring is the game's, mirrors are the Glass Wood's")
            Game.tideArchiveEnabled = archiveWas

            // 3f. The link changes the home island: the beam fades in once the lamp is lit; the mist thins after the first trip through the lens.
            g = freshGame()
            check(g.mistScale == 1 && g.beamAmount == 0, "a fresh island has full mist and no beam")
            g.simulate(seconds: 10)
            check(g.mistScale == 1 && g.beamAmount == 0, "nothing changes by itself")
            g.puzzle.forceSolved(); g.simulate(seconds: 1)
            check(g.beamAmount > 0.05 && g.beamAmount < 0.9 && g.mistScale == 1, "once the lamp is lit the beam fades in gradually (\(g.beamAmount)); the mist is unchanged")
            g.simulate(seconds: 13)
            check(g.beamAmount > 0.95 && g.mistScale == 1, "the beam reaches full strength; the mist is still untouched before the trip")
            g.state.set("lensTouched"); g.simulate(seconds: 3)
            check(g.mistScale < 1 && g.mistScale > Game.thinMist + 0.05, "after the first trip through the lens the mist begins to thin slowly (\(g.mistScale))")
            g.simulate(seconds: 70)
            check(abs(g.mistScale - Game.thinMist) < 0.01 && g.mistScale >= Game.thinMist - 1e-4, "the mist settles at its thinner level and never below it")
            let atm = freshGame(); atm.puzzle.forceSolved(); atm.state.set("lensTouched"); atm.settleAtmosphere()
            check(atm.mistScale == Game.thinMist && atm.beamAmount == 1, "loading a travelled, solved game starts with the island already changed")
            let atm2 = freshGame(); atm2.restore(atm.makeSave())
            check(atm2.mistScale == Game.thinMist && atm2.beamAmount == 1, "restoring a save settles the atmosphere instantly")

            // 4. The right order solves it and runs the whole sequence.
            g = freshGame()
            for id in LighthousePuzzle.order { g.puzzle.strike(id); g.simulate(seconds: 0.7) }
            check(g.state.has("solved") && lit(g) == [true, true, true], "tide -> wind -> stone solves the puzzle")
            let evs = chimes(g.drainEvents())
            check(evs.prefix(4) == [.tide, .wind, .stone, .ignite], "success chimes: tide, wind, stone, then the ignition chord (\(evs))")
            check(!g.state.has("lighthouseLit") && !g.state.has("causewayUp"), "the lighthouse is not lit the instant you solve it")
            g.simulate(seconds: LighthousePuzzle.Timing.total + 1)
            check(g.state.has("lighthouseLit") && g.state.has("causewayUp"), "within \(Int(LighthousePuzzle.Timing.total) + 1) s the lighthouse is lit and the causeway is up")
            check(chimes(g.drainEvents()).contains(.rumble), "the causeway raised with a rumble")
            check(StoneID.allCases.allSatisfy { id in g.scene.items.first { $0.name == "beam_\(id.name)" }.map { !$0.hidden } ?? false }, "all three beams are visible")
            check((g.scene.items.first { $0.name == "lighthouse_lens" }?.uniforms.emissive.w ?? 0) > 39, "the lens blazes (emissive \(g.scene.items.first { $0.name == "lighthouse_lens" }?.uniforms.emissive.w ?? 0))")

            // 5. Solved is permanent: more strikes only ring.
            g.puzzle.strike(.summit); g.puzzle.strike(.tide); g.simulate(seconds: 2)
            check(lit(g) == [true, true, true] && g.state.has("solved") && chimes(g.drainEvents()).filter { $0 == .fail }.isEmpty, "after solving, further strikes never un-solve it")

            // 6. The causeway is walkable only once it has risen.
            func walkNorth(_ game: Game) -> Float {
                let plan = PuzzleProps.causewayPlan(terrain: game.scene.terrain)
                game.player = Player(position: SIMD3(plan.start.x, 1.5, plan.start.y), yaw: atan2(plan.dir.x, -plan.dir.y))   // player yaw: forward = (sin, -cos)
                game.player.position.y = game.scene.groundHeight(x: plan.start.x, z: plan.start.y)
                var input = InputState(); input.move = SIMD2(0, 1)
                game.simulate(seconds: 38, input: input)          // was 30 s at 3.2 m/s; the same walk takes about 37 s at 2.6 m/s (longer overshoots the islet's centre)
                return distance(SIMD2(game.player.position.x, game.player.position.z), SIMD2(Layout.isletCenter.x, Layout.isletCenter.z))
            }
            let before = walkNorth(freshGame()), after = walkNorth(g)
            check(before > 50, "before solving, you cannot walk out to the islet (still \(Int(before)) m from it)")
            check(after < 12 && g.player.position.y > 1.0, "after solving, you walk the causeway onto the islet (\(Int(after)) m from its centre, standing at y \(String(format: "%.1f", g.player.position.y)))")
        }
        if name == "all" || name == "feedback" {
            let tmp = NSTemporaryDirectory() + "lw-feedback-\(getpid())"
            setenv("LANTERNWRIGHT_FEEDBACK_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_FEEDBACK_DIR") }
            check(FeedbackStore.loadAll().isEmpty, "feedback store starts empty")
            try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
            try? Data([1, 2, 3]).write(to: FeedbackStore.pendingScreenshotURL)
            let game = Game(scene: Scene.makeWorld(device: device))
            game.puzzle.strike(.tide)
            let first = try? FeedbackStore.save(text: "  The surf is much better!  ", context: game.feedbackContext(extra: ["note": "test"]))
            let second = try? FeedbackStore.save(text: "second, \"quoted\" and\nmultiline", context: ["k": "v"])
            let all = FeedbackStore.loadAll()
            check(all.count == 2 && all[0].text == "The surf is much better!" && all[1].text.contains("\"quoted\"") && all[1].text.contains("\n"), "entries round-trip through the JSONL file (trimmed, quotes and newlines intact)")
            check(first?.screenshot != nil && FileManager.default.fileExists(atPath: FeedbackStore.screenshotURL(id: first!.id).path) && second?.screenshot == nil, "the pending screenshot is attached to the next entry only")
            check(all[0].context["puzzle flags"]?.contains("lit_tide") == true && all[0].context["position"] != nil && all[0].context["note"] == "test", "context carries position and puzzle flags")
            check(first?.id != second?.id, "entries saved in the same second still get distinct ids")
            let listing = FeedbackStore.formatted(all)
            check(listing.contains("The surf is much better!") && listing.contains("puzzle flags") && listing.contains(".png"), "--feedback listing shows text, context and screenshot path")
            check(!game.drainEvents().contains(.feedbackRequested), "no feedback event unless F is pressed")
            var pressF = InputState(); pressF.feedbackPressed = true
            game.advance(now: 5, input: InputState()); game.advance(now: 5.01, input: pressF)
            check(game.drainEvents().contains(.feedbackRequested), "pressing F emits feedbackRequested")
        }
        if name == "all" || name == "save" {
            let tmp = NSTemporaryDirectory() + "lw-save-\(getpid())"
            setenv("LANTERNWRIGHT_SAVE_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_SAVE_DIR") }
            check(SaveStore.load() == nil, "no save at first")
            let g = Game(scene: Scene.makeWorld(device: device))
            g.activate("page_1"); g.activate("page_3"); g.toggleJournal()
            g.puzzle.forceSolved(); g.state.set("lensTouched")
            g.player = Player(position: SIMD3(Layout.tideStone.x + 3, Layout.tideStone.y, Layout.tideStone.z + 3), yaw: 1.25)
            g.player.position.y = g.scene.groundHeight(x: g.player.position.x, z: g.player.position.z)
            g.player.pitch = -0.2
            try? SaveStore.save(g.makeSave())
            check(FileManager.default.fileExists(atPath: SaveStore.url.path) && !FileManager.default.fileExists(atPath: SaveStore.directory.appendingPathComponent("save.json.tmp").path), "saving writes save.json and leaves no temp file")

            let h = Game(scene: Scene.makeWorld(device: device))
            if let s = SaveStore.load() { h.restore(s) }
            check(h.state.has("solved") && h.state.has("lighthouseLit") && h.state.has("causewayUp") && h.state.has("lensTouched"), "puzzle progress is restored")
            check(h.journal.collectedPages.map(\.number) == [1, 3], "collected pages are restored")
            check(h.scene.items.first { $0.name == "page_1" }?.hidden == true && h.scene.items.first { $0.name == "page_2" }?.hidden == false, "collected pages are gone from the world, others remain")
            check(distance(h.player.position, g.player.position) < 0.05 && abs(h.player.yaw - 1.25) < 1e-4 && abs(h.player.pitch + 0.2) < 1e-4, "position and view direction are restored")
            check(!h.journal.isOpen && h.whiteout == 0, "loading does not reopen the journal or replay the ending")
            check(h.scene.walkables[h.scene.causewayIndex!].enabled, "the causeway is walkable again after loading a solved game")
            check((h.scene.items.first { $0.name == "lighthouse_lens" }?.uniforms.emissive.w ?? 0) > 39, "the lens is blazing after loading")

            // Robustness: corrupt, future-version and out-of-world saves must never crash or strand the player.
            try? "{ not json".write(to: SaveStore.url, atomically: true, encoding: .utf8)
            check(SaveStore.load() == nil, "a corrupt save is ignored")
            var future = g.makeSave(); future.version = 99
            try? SaveStore.save(future)
            check(SaveStore.load() == nil, "a save from a newer version is ignored")
            var sea = g.makeSave(); sea.position = [175, 0.8, 330]       // open sea
            let k = Game(scene: Scene.makeWorld(device: device)); k.restore(sea)
            check(distance(SIMD2(k.player.position.x, k.player.position.z), SIMD2(Layout.dockEnd.x, Layout.dockEnd.z)) < 1, "a saved position in the open sea falls back to the spawn")
            // Version 2: puzzle flags per world; version 1 (one flat list) migrates on load.
            let v2 = g.makeSave()
            check(v2.version == 2 && v2.worldFlags["varrow"]?.contains("solved") == true && v2.worldFlags["game"] == ["lensTouched"] && v2.worldFlags["glassWood"] == nil, "a v2 save files flags under their world (solved -> varrow, lensTouched -> game)")
            let v1json = """
            {"version":1,"flags":["solved","lighthouseLit","causewayUp","lensTouched","gw_mirrors","gw_end","struck_tide"],"pages":[1,5],
             "position":[175,0.8,205],"yaw":0.5,"pitch":0,"playTime":42,"world":"varrow"}
            """
            try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
            try? v1json.write(to: SaveStore.url, atomically: true, encoding: .utf8)
            let mig = SaveStore.load()
            check(mig?.version == 2 && mig?.worldFlags["varrow"]?.sorted() == ["causewayUp", "lighthouseLit", "solved", "struck_tide"] && mig?.worldFlags["glassWood"]?.sorted() == ["gw_end", "gw_mirrors"] && mig?.worldFlags["game"] == ["lensTouched"], "a v1 save loads and its flat flags are sorted into worlds")
            let migGame = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
            if let m = mig { migGame.restore(m) }
            check(migGame.state.has("solved") && migGame.state.has("lensTouched") && migGame.state.has("gw_mirrors") && migGame.state.has("struck_tide") && migGame.journal.collectedPages.map(\.number) == [1, 5], "a migrated v1 save restores its progress and pages")
            try? SaveStore.save(mig!)
            let rewritten = (try? String(contentsOf: SaveStore.url, encoding: .utf8)) ?? ""
            check(rewritten.contains("\"worldFlags\"") && !rewritten.contains("\"flags\"") && SaveStore.load() == mig, "saving a migrated game writes v2 and it reads back identically")
            // A flag in the wrong bucket is ignored by a puzzle that does not own that world: no cross-world leakage.
            var leaky = g.makeSave(); leaky.worldFlags["glassWood"] = ["solved"]
            let leakGame = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]); leakGame.restore(leaky)
            check(leakGame.state.has("solved"), "(Varrow's own bucket still restores) ...")
            var onlyGlass = g.makeSave(); onlyGlass.worldFlags["varrow"] = nil
            let og = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]); og.restore(onlyGlass)
            check(!og.state.has("solved"), "...and a world's flags come only from that world's bucket")
            SaveStore.delete(); check(SaveStore.load() == nil, "delete removes the save")
        }
        if name == "all" || name == "settings" {
            var bad = Settings()
            bad.sensitivity = .nan; bad.volume = 7; bad.renderScale = 0.01
            let c = bad.clamped()
            check(c.sensitivity == 0.0022 && c.volume == 1 && c.renderScale == 0.5, "non-finite and out-of-range settings are clamped to legal values")
            var s = Settings(); s.sensitivity = 0.004; s.invertY = true; s.volume = 0.25; s.renderScale = 0.75
            let back = (try? JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s)))
            check(back == s, "settings round-trip through JSON")
            check(Settings().clamped() == Settings(), "the defaults are already within range")
        }
    }
}

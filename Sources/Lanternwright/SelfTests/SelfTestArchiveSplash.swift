import Foundation
import Metal
import simd

/// F09.4 (#108: "I am standing at least partway in the water but my footsteps sound like they are on dry sand. This should be splashing"): in the Tide Archive the splash is decided by the depth of water at the
/// foot first, from the same surfaces the water pass draws (the sea's tide in the channels AND the Great Ledger gallery's own water), then the material is whatever the floor is (stone stays stone).
/// The spot of the note, (52.3, 11.0, -27.0), is inside the gallery's court, whose water `Game.archiveWaterDepth` did not read. Checked at three tide levels. Untested by ear.
extension SelfTestRunner {
    func runArchiveSplash() {
        guard name == "all" || name == "archivesplash" else { return }
        let flagWas = Game.tideArchiveEnabled, confWas = Player.confinementEnabled
        Game.tideArchiveEnabled = true; Player.confinementEnabled = false
        defer { Game.tideArchiveEnabled = flagWas; Player.confinementEnabled = confWas; Player.galleryWater = nil }
        let archive = TideArchive.build(device: device)
        let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device), .tideArchive: archive])
        for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
        g.state.set("gw_end"); g.state.set(Game.doorOpenFlag)
        g.simulate(seconds: 0.1)
        guard g.beginRoute(.ilse) else { check(false, "archivesplash: the route begins"); return }
        g.simulate(seconds: Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5)
        _ = g.drainEvents()
        check(g.archiveActive, "archivesplash: the Archive is the active world")
        let court = ArchiveTerrain.gallery
        for (target, label) in [(Float(0.05), "low tide"), (0.5, "mid tide"), (0.95, "high tide")] {
            var guardSteps = 0
            while abs(Tide.level(g.time) - target) > 0.03 && guardSteps < 400 { g.simulate(seconds: 0.5); guardSteps += 1 }
            func spot(_ lo: Float, _ hi: Float) -> SIMD3<Float>? {
                guard let w = Player.galleryWater else { return nil }
                var best: SIMD3<Float>?
                var x = court.centre.x - court.half.x + 0.5
                while x < court.centre.x + court.half.x - 0.5 {
                    var z = court.centre.y - court.half.y + 0.5
                    while z < court.centre.y + court.half.y - 0.5 {
                        let ground = g.scene.groundHeight(x: x, z: z), depth = max(0, w.level - ground)
                        if depth >= lo && depth <= hi { best = SIMD3(x, ground, z); if lo == 0 && hi == 0 { return best } }
                        z += 1
                    }
                    x += 1
                }
                return best
            }
            func read(_ p: SIMD3<Float>) -> (depth: Float, splash: Float, mix: StepMix, oldDepth: Float) {
                g.player.position = p
                g.simulate(seconds: 0.05)
                let ground = g.scene.groundHeight(x: p.x, z: p.z)
                return (g.archiveWaterDepth, AudioEngine.stepSplash(game: g), g.surfaceMix.mix, Tide.depth(ground: ground, time: g.time))
            }
            guard let ankle = spot(0.04, 0.065), let shin = spot(0.25, 0.38), let dry = spot(0, 0) else { check(false, "archivesplash: \(label): found an ankle-deep, a shin-deep and a dry spot in the gallery's court (\(spot(0.04, 0.065) != nil), \(spot(0.25, 0.38) != nil), \(spot(0, 0) != nil))"); continue }
            let a = read(ankle), s = read(shin), d = read(dry)
            let expectA = ArchiveStory.galleryDepth(at: SIMD2(ankle.x, ankle.z), ground: ankle.y)
            check(abs(a.depth - expectA) < 0.02 && a.depth > 0.03, "archivesplash: \(label): at an ankle-deep spot of the gallery the game reads \(String(format: "%.3f", a.depth)) m of water (the gallery's own surface gives \(String(format: "%.3f", expectA)))")
            check(a.oldDepth < 0.001, "archivesplash: \(label): mutation: the tide alone, which is all the game read before F09.4, saw \(String(format: "%.3f", a.oldDepth)) m there (dry): that is #108")
            check(a.splash > 0.35 && a.splash < 0.95 && s.splash >= 0.95 && d.splash == 0 && d.depth == 0, "archivesplash: \(label): splash is a partial at the ankle (\(String(format: "%.2f", a.splash))), full at the shin (\(String(format: "%.2f", s.splash))), none dry (\(String(format: "%.2f", d.splash)))")
            check(a.mix[StepMaterial.stone.rawValue] > 0.99 && a.mix[StepMaterial.wetSand.rawValue] == 0 && a.mix[StepMaterial.drySand.rawValue] == 0, "archivesplash: \(label): the floor underfoot stays stone (no sand grains in the mix: stone \(String(format: "%.2f", a.mix[StepMaterial.stone.rawValue])))")
        }
        // The note's own spot is in the court, so it is the gallery's water that applies there.
        check(abs(52.3 - court.centre.x) < court.half.x && abs(-27.0 - court.centre.y) < court.half.y, "archivesplash: the spot of #108 (52.3, -27.0) is inside the gallery's court, where the gallery's own water is")
        // The depth map itself is monotone and ordered ankle < shin, and the sound has the splash in it: a stone step with the ankle's splash carries more mid-band energy than the dry one.
        let depths: [Float] = [0, 0.01, 0.03, 0.08, 0.15, 0.3]
        let sp = depths.map { AudioEngine.stepSplash(depth: $0) }
        check(zip(sp, sp.dropFirst()).allSatisfy { $1 >= $0 } && sp[0] == 0 && sp[4] >= 0.99 && sp.last! >= 0.99, "archivesplash: the splash grows with depth and is whole by 8 cm: \(sp.map { String(format: "%.2f", $0) })")
        func energy(_ splash: Float) -> Float {
            let f = Footsteps(sampleRate: 44100)
            f.start(mix: FootstepRecipe.pure(.stone), run: false, pan: 0, splash: splash)
            var x: [Float] = []
            for _ in 0..<Int(0.6 * 44100) { let v = f.render(dt: 1 / 44100); x.append(v.0 + v.1) }
            return FootstepAnalysis.band(FootstepAnalysis.spectrum(x), 150, 3000)
        }
        let dryE = energy(0), ankleE = energy(AudioEngine.stepSplash(depth: 0.04)), shinE = energy(1)
        check(ankleE > 2 * dryE && shinE > ankleE, "archivesplash: a stone step in ankle-deep water carries \(String(format: "%.1f", ankleE / max(dryE, 1e-12))) times the dry step's energy at 150 Hz-3 kHz (the splash), and a shin-deep one more (\(String(format: "%.1f", shinE / max(dryE, 1e-12))))")
    }
}

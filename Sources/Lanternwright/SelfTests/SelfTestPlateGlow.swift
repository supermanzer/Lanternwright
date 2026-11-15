import Foundation
import Metal
import simd

/// B6 (G7, the door plates' sight): the plates are one mesh, so each right strike held raises the whole set's glow a step and a wrong strike drops it back to the quiet glint. Before this the plates answered the eye with nothing
/// but a binary glint and the graph counted them as sound-only feedback.
extension SelfTestRunner {
    func runPlateGlow() {
        guard name == "all" || name == "plateglow" else { return }
        let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
        for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }
        var clock = 6000.0
        func run(_ seconds: Double) { for _ in 0..<Int(seconds * 20) { clock += 0.05; g.advance(now: clock, input: InputState()) } }
        g.state.set("gw_end"); run(2)
        func glow() -> Float { g.scene.items.first { $0.name == "tone_plates" }?.uniforms.emissive.w ?? -1 }
        let order = TonePlatePuzzle.order
        let wrong = (0..<3).first { $0 != order[0] }!
        let rest = glow()
        check(rest > 0 && rest <= Game.plateGlintPeak + 0.001, "plateglow: ready, the plates glint quietly (\(rest))")
        g.activate(TonePlates.names[order[0]]); run(0.15)
        let one = glow()
        g.activate(TonePlates.names[order[1]]); run(0.15)
        let two = glow()
        check(one > rest + 0.05 && two > one + 0.05, "plateglow: each right strike held raises the glow a step (\(rest) -> \(one) -> \(two))")
        g.activate(TonePlates.names[wrong == order[2] ? order[0] : wrong]); run(Double(TonePlatePuzzle.Timing.wrongResetDelay) + 0.4)
        let after = glow()
        check(after <= Game.plateGlintPeak + 0.001, "plateglow: a wrong strike resets it: the glow drops back to the glint (\(after))")
        // Once the door is open the plates only ring: no held glow.
        g.state.set(Game.doorOpenFlag); run(0.4)
        check(glow() <= 0.001, "plateglow: with the door open the plates are dark again (\(glow()))")
        // B6 (G7, Q97): a counted tide mark stays lit on the quay's gauge (A's `TideMarks.set`), on both routes, and again after a load.
        for route in [PageAuthor.ilse, .oren] {
            let a = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device), .tideArchive: TideArchive.build(device: device)])
            for n in [1, 2, 3, 5, 6, 7] { a.restorePage(n) }
            a.state.set("gw_end"); a.state.set(Game.doorOpenFlag); a.simulate(seconds: 0.1)
            guard a.beginRoute(route) else { check(false, "plateglow: \(route) could not begin"); continue }
            a.simulate(seconds: Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.8)
            let held = { (k: Int) in a.scenes[.tideArchive]!.archive.markHeld[route == .ilse ? 0 : 1][k] }
            check((0..<3).allSatisfy { held($0) == 0 }, "plateglow: \(route): no mark is held lit before one is counted")
            a.state.set(IlseRoute.markFlags[1]); a.simulate(seconds: 0.2)
            check(held(1) == 1 && held(0) == 0 && held(2) == 0, "plateglow: \(route): the counted mark (and only it) is held lit on the gauge (\((0..<3).map(held)))")
        }
    }
}

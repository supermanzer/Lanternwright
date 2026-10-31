import Foundation
import simd

/// Self-tests (F08.1, Q35): at the fork each exit's hover prompt names the sibling whose way it is, and only then: before the gate is ready and after a route is chosen the plain words show. A ray at the open
/// doorway picks its hint without stealing the ring or the lens.
extension SelfTestRunner {
    func runForkPrompts() {
        guard name == "all" || name == "fork" || name == "forkprompts" else { return }
        typealias I = LighthouseInterior
        let lh = Layout.lighthouse
        func twoWorlds() -> Game { Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]) }
        var clock = 7000.0
        func step(_ g: Game, _ n: Int = 2) { for _ in 0..<n { clock += 0.05; g.advance(now: clock, input: InputState()) } }
        func lensGame(ready: Bool) -> Game {
            let g = twoWorlds()
            if ready { for n in [1, 2, 3, 5, 6, 7] { g.restorePage(n) }; g.state.set("gw_end"); g.story.contradictionsResolved = ["who-left"] }
            g.state.set(Game.doorOpenFlag); step(g)
            g.player = Player(position: SIMD3(lh.x - 0.2, lh.y + I.lensFloorY, lh.z - 1.45), yaw: .pi)
            _ = g.drainEvents(); step(g)
            return g
        }
        /// The prompt a player sees looking from their eye at `target`.
        func prompt(_ g: Game, at target: SIMD3<Float>) -> String? {
            let eye = g.player.position + SIMD3(0, Player.eyeHeight, 0)
            g.player.yaw = atan2(target.x - eye.x, -(target.z - eye.z)); g.player.pitch = asin((target.y - eye.y) / simd_length(target - eye))
            step(g)
            return g.hoverPrompt
        }
        let lens = Landmarks.lensPosition, ring = lh + SIMD3(0, LensPortalProps.ringY, 0)
        let doorway = lh + SIMD3(cos(I.portalAngle) * 2.0, I.lensFloorY + 1.1, sin(I.portalAngle) * 2.0)
        // Pre-choice, gate ready: each exit names its sibling.
        let r = lensGame(ready: true)
        check(r.exitLightsOn, "fork prompts: with the gate ready and no route chosen the exits are lit")
        let pl = prompt(r, at: lens), pr = prompt(r, at: ring)
        check(pl == "Ilse\u{2019}s way: touch the lens" && pr?.hasPrefix("Oren\u{2019}s way:") == true, "fork prompts: the lens says \"\(pl ?? "-")\" and the ring \"\(pr ?? "-")\": each names its sibling")
        let rbot = PlaythroughBot(r)
        for _ in 0..<3 { _ = rbot.click("lens_ring"); rbot.wait(0.3) }
        r.simulate(seconds: LensPortalProps.holdSeconds + 0.6); step(r)
        let dp = prompt(r, at: doorway)
        check(r.lensPortal.isOpen && dp == "Oren\u{2019}s way: step into the light", "fork prompts: with the portal open, its doorway says Oren's way: step into the light (\(dp ?? "-"), open \(r.lensPortal.isOpen))")
        check(prompt(r, at: lens) == "Ilse\u{2019}s way: touch the lens" && prompt(r, at: ring)?.hasPrefix("Oren\u{2019}s way:") == true, "fork prompts: and the open doorway's hint does not steal the lens or the ring")
        // Gate not ready: the plain words, nothing named.
        let n = lensGame(ready: false)
        let nl = prompt(n, at: lens), nr = prompt(n, at: ring)
        check(!n.exitLightsOn && nl == "Touch the lens" && nr == "Turn the ring  \u{2039} \u{203A}", "fork prompts: with the gate not ready the plain words show (\(nl ?? "-"), \(nr ?? "-"))")
        // After the choice: no sibling name anywhere on the exits.
        let c = lensGame(ready: true)
        check(PlaythroughBot(c).click(Game.lampLensName) && c.chosenPath == .ilse, "fork prompts: touching the lens begins Ilse's route")
        c.simulate(seconds: Game.fadeOutSeconds + Game.holdSeconds + Game.fadeInSeconds + 0.5); c.travel(to: .varrow); step(c, 3)
        c.player = Player(position: SIMD3(lh.x - 0.2, lh.y + I.lensFloorY, lh.z - 1.45), yaw: .pi); step(c)
        let cl = prompt(c, at: lens), cr = prompt(c, at: ring)
        check(!c.exitLightsOn && cl?.contains("Ilse") != true && cl?.contains("Oren") != true && cr?.contains("Oren") != true && cr?.contains("Ilse") != true, "fork prompts: once a route is chosen no prompt names a sibling (\(cl ?? "-"), \(cr ?? "-"))")
    }
}

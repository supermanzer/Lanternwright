import Foundation
import simd

/// A scripted player. It drives the real `Game.advance` loop with real input (walk keys, camera aim, mouse clicks on the
/// interactable under the crosshair), so a bot that finishes a world proves the world can be finished: stones reachable, clicks
/// land, puzzles solvable by their rules, lens transitions work. It knows only what a player could deduce (the puzzle rules),
/// never the game's private state.
final class PlaythroughBot {
    let game: Game
    private var now = 1000.0
    /// Game seconds the bot has played so far (60 ticks a second), waits included: how long this run took a player who never hesitates.
    private(set) var elapsed: Float = 0
    init(_ game: Game) { self.game = game }

    func tick(_ input: InputState = InputState()) {
        now += 1.0 / 60; elapsed += 1.0 / 60; game.advance(now: now, input: input)
        if let net = Layout.Navigation.active(for: game.world) { strayed = max(strayed, net.signedDistance(SIMD2(game.player.position.x, game.player.position.z))) }
    }
    /// M10.6: the furthest the feet have been beyond a corridor edge since the last `forgetStray()` (negative: always inside; the margin is `Player.marginWidth`).
    private(set) var strayed: Float = -.infinity
    func forgetStray() { strayed = -.infinity }
    func wait(_ seconds: Float) { for _ in 0..<Int(seconds * 60) { tick() } }

    var feet: SIMD3<Float> { game.player.position }
    private func flat(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x, p.z) }

    /// Face a point in the world (yaw and pitch from the eye).
    func aim(at p: SIMD3<Float>) {
        let d = p - game.camera.position
        game.player.yaw = atan2(d.x, -d.z)
        game.player.pitch = asin(max(-1, min(1, d.y / simd_length(d))))
    }

    /// Walk toward a spot until within `r` metres (horizontally). Gives up after `timeout` seconds in all, or when stuck (less than 0.5 m of progress in 4 s).
    /// M10.6: with guidance on (`Player.confinementEnabled`) the bot follows the navigation network the way a player on the trails would: along the centre lines (the shortest
    /// route between the nearest centre-line nodes, `NavNetwork.route`), then straight to the spot from the last node. `straight: true` (or guidance off) walks the old
    /// straight line.
    @discardableResult
    func walk(to target: SIMD3<Float>, within r: Float, timeout: Float = 150, straight: Bool = false) -> Bool {
        var legs: [SIMD2<Float>] = []
        if !straight, let net = Layout.Navigation.active(for: game.world), simd_length(flat(target) - flat(feet)) >= r {
            // Route nodes that lie inside, or hard against, a collider (the lighthouse's axis is a plaza centre) cannot be walked to: skip them.
            let cylinders = game.scene.colliders.cylinders
            legs = net.route(from: flat(feet), to: flat(target))
                .filter { n in !cylinders.contains { simd_length(n - $0.center) < $0.radius + Player.radius + 0.8 } }
        }
        legs.append(flat(target))
        var elapsed: Float = 0
        for (i, leg) in legs.enumerated() {
            let radius = i == legs.count - 1 ? r : 3
            var mark = flat(feet), markTime = elapsed
            while true {
                if simd_length(flat(target) - flat(feet)) < r { return true }                    // arrived, whichever leg this is (the last route nodes can lie inside a collider)
                let d = leg - flat(feet)
                if simd_length(d) < radius { break }
                if elapsed >= timeout { return false }
                game.player.yaw = atan2(d.x, -d.y)
                game.player.pitch = 0
                var input = InputState(); input.move = SIMD2(0, 1)
                tick(input); elapsed += 1.0 / 60
                if elapsed - markTime > 4 {
                    if simd_length(flat(feet) - mark) < 0.5 { return false }
                    mark = flat(feet); markTime = elapsed
                }
            }
        }
        return true
    }

    /// Follow waypoints in order, ending within `r` of the last.
    @discardableResult
    func follow(_ points: [SIMD3<Float>], within r: Float = 2.5) -> Bool {
        for (i, p) in points.enumerated() where !walk(to: p, within: i == points.count - 1 ? r : 3) { return false }
        return true
    }

    /// The interactable's id, if it exists in the current world.
    func interactable(_ id: String) -> Interactable? { game.interactables.first { $0.id == id } }

    /// Look at an interactable and click it. Returns false if it is not there, not enabled, or not under the crosshair.
    @discardableResult
    func click(_ id: String) -> Bool {
        guard let it = interactable(id), it.enabled else { return false }
        aim(at: (it.min + it.max) * 0.5)
        var input = InputState(); input.click = true
        game.advance(now: { now += 1.0 / 60; return now }(), input: input)
        return true
    }

    /// Close the journal (J) after reading a page.
    func closeJournal() {
        guard game.journal.isOpen else { return }
        var input = InputState(); input.journalPressed = true
        tick(input)
    }

    /// F01 W4.1: what a stuck detector sees while the bot holds a direction. `stuck` counts one-second windows in which the player, with forward held,
    /// moved less than `minProgress` of the distance it should have.
    struct HoldReport { var stuck = 0; var seconds = 0; var worstProgress: Float = .infinity; var stuckAt: SIMD2<Float>? }

    /// Walk around `centre` at `radius`, holding the circle with a little radial correction (so a wall pushes back and the bot slides along it), for `seconds`.
    func circle(around centre: SIMD2<Float>, radius: Float, clockwise: Bool, run: Bool, seconds: Float, startAngle: Float = 0) -> HoldReport {
        var rep = HoldReport()
        let sgn: Float = clockwise ? -1 : 1
        game.player.position = SIMD3(centre.x + cos(startAngle) * radius, game.scene.groundHeight(x: centre.x + cos(startAngle) * radius, z: centre.y + sin(startAngle) * radius), centre.y + sin(startAngle) * radius)
        wait(0.3)
        var windowStart = flat(feet), t: Float = 0, windowT: Float = 0
        while t < seconds {
            let p = flat(feet), rel = p - centre, dist = max(simd_length(rel), 1e-3)
            let radial = rel / dist, tangent = SIMD2(-radial.y, radial.x) * sgn
            let want = simd_normalize(tangent + radial * (radius - dist) * 0.8)
            game.player.yaw = atan2(want.x, -want.y); game.player.pitch = 0
            var input = InputState(); input.move = SIMD2(0, 1); input.run = run
            tick(input); t += 1.0 / 60; windowT += 1.0 / 60
            if windowT >= 1 {
                let moved = simd_length(flat(feet) - windowStart)
                let expected = (run ? Player.runSpeed : Player.walkSpeed) * Player.minPace
                rep.worstProgress = min(rep.worstProgress, moved / expected)
                if moved < 0.3 * expected { rep.stuck += 1; rep.stuckAt = rep.stuckAt ?? flat(feet) }
                rep.seconds += 1; windowStart = flat(feet); windowT = 0
            }
        }
        return rep
    }

    /// Walk straight at `point` from where the player stands; reports stuck windows the same way.
    func approach(_ point: SIMD2<Float>, seconds: Float, run: Bool = false) -> HoldReport {
        var rep = HoldReport()
        var windowStart = flat(feet), t: Float = 0, windowT: Float = 0
        while t < seconds {
            let d = point - flat(feet)
            game.player.yaw = atan2(d.x, -d.y); game.player.pitch = 0
            var input = InputState(); input.move = SIMD2(0, 1); input.run = run
            tick(input); t += 1.0 / 60; windowT += 1.0 / 60
            if windowT >= 1 {
                let moved = simd_length(flat(feet) - windowStart)
                rep.worstProgress = min(rep.worstProgress, moved / ((run ? Player.runSpeed : Player.walkSpeed) * Player.minPace))
                rep.seconds += 1; windowStart = flat(feet); windowT = 0
            }
        }
        return rep
    }

    /// A bot that wanders at random (a new heading every 0.4-2 s, sometimes running, sometimes strafing) inside `radius` of `centre`, and after every stall
    /// tries all eight directions for half a second each: if none of them gets anywhere the player is TRAPPED (a real stuck, not a wall faced on purpose).
    func wander(around centre: SIMD2<Float>, radius: Float, seconds: Float, seed: UInt32) -> (trapped: [SIMD2<Float>], stalls: Int) {
        let noise = Noise(seed: seed)
        var trapped: [SIMD2<Float>] = [], stalls = 0
        var t: Float = 0, heading = noise.unit(0, 1) * 2 * .pi, nextTurn: Float = 0, k: Int32 = 1
        var run = false
        var windowStart = flat(feet), windowT: Float = 0
        while t < seconds {
            if t >= nextTurn {
                k += 1
                heading = noise.unit(k, 1) * 2 * .pi; run = noise.unit(k, 2) > 0.6; nextTurn = t + 0.4 + 1.6 * noise.unit(k, 3)
            }
            let to = centre - flat(feet)
            if simd_length(to) > radius { heading = atan2(to.x, -to.y) + (noise.unit(k, 4) - 0.5) }            // turn back toward the tower when straying
            game.player.yaw = heading; game.player.pitch = 0
            var input = InputState(); input.move = SIMD2((noise.unit(k, 5) - 0.5) * 0.6, 1); input.run = run
            tick(input); t += 1.0 / 60; windowT += 1.0 / 60
            if windowT >= 1.2 {
                let moved = simd_length(flat(feet) - windowStart)
                if moved < 0.25 {
                    stalls += 1
                    // Escape test: eight headings, half a second each.
                    let from = flat(feet)
                    var best: Float = 0
                    for e in 0..<8 {
                        game.player.position = SIMD3(from.x, game.player.position.y, from.y)
                        let a = Float(e) / 8 * 2 * .pi
                        for _ in 0..<30 { game.player.yaw = a; var i = InputState(); i.move = SIMD2(0, 1); tick(i) }
                        best = max(best, simd_length(flat(feet) - from))
                    }
                    game.player.position = SIMD3(from.x, game.player.position.y, from.y)
                    if best < 0.6 { trapped.append(from) }
                    nextTurn = 0
                }
                windowStart = flat(feet); windowT = 0
            }
        }
        return (trapped, stalls)
    }
}

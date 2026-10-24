import Foundation
import simd

/// A scripted player. It drives the real `Game.advance` loop with real input (walk keys, camera aim, mouse clicks on the
/// interactable under the crosshair), so a bot that finishes a world proves the world can be finished: stones reachable, clicks
/// land, puzzles solvable by their rules, lens transitions work. It knows only what a player could deduce (the puzzle rules),
/// never the game's private state.
final class PlaythroughBot {
    let game: Game
    private var now = 1000.0
    init(_ game: Game) { self.game = game }

    func tick(_ input: InputState = InputState()) { now += 1.0 / 60; game.advance(now: now, input: input) }
    func wait(_ seconds: Float) { for _ in 0..<Int(seconds * 60) { tick() } }

    var feet: SIMD3<Float> { game.player.position }
    private func flat(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(p.x, p.z) }

    /// Face a point in the world (yaw and pitch from the eye).
    func aim(at p: SIMD3<Float>) {
        let d = p - game.camera.position
        game.player.yaw = atan2(d.x, -d.z)
        game.player.pitch = asin(max(-1, min(1, d.y / simd_length(d))))
    }

    /// Walk straight toward a spot until within `r` metres (horizontally). Gives up after `timeout` seconds or when stuck
    /// (less than 0.5 m of progress in 4 s).
    @discardableResult
    func walk(to target: SIMD3<Float>, within r: Float, timeout: Float = 150) -> Bool {
        var elapsed: Float = 0, mark = flat(feet), markTime: Float = 0
        while elapsed < timeout {
            let d = flat(target) - flat(feet)
            if simd_length(d) < r { return true }
            game.player.yaw = atan2(d.x, -d.y)
            game.player.pitch = 0
            var input = InputState(); input.move = SIMD2(0, 1)
            tick(input); elapsed += 1.0 / 60
            if elapsed - markTime > 4 {
                if simd_length(flat(feet) - mark) < 0.5 { return false }
                mark = flat(feet); markTime = elapsed
            }
        }
        return false
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
}

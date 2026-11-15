import Foundation
import simd

/// B6 (P02.7 groundwork): what a player can PERCEIVE of the game, and the keys and the feet a player has. It is the only handle the no-knowledge bot (`BlindPlayer`) holds: that file never sees `Game`, a puzzle class,
/// a layout constant or a flag, and a selftest reads its text to prove it (`nokbot`: the forbidden-names check). Everything here is something on the screen, in the speakers or under the feet:
///  - **sight**: the interactables within sight (a box with its prompt, in front of the camera or close behind it), the glow of the things near a point (what is lit), the guide light and the lamps (their places
///    and brightness), the trails (the lantern-lit paths, as points), the banner, the journal being open, a crosshair that looks "quieter" on a thing that is done;
///  - **sound**: each game event, reduced to what an ear tells apart: a tone (by identity, never by what it "means"), a sour note, a held tone, a bloom, a gate's rumble;
///  - **hands and feet**: walk along the trails, face a point, click, press the arrow keys, wait. All through the real `Game.advance` input.
/// The prompt the player reads is the one the game shows under the crosshair (`inspect`), so the exits at the fork read as they do on screen.
final class Perception {
    /// One thing in sight. `handle` is an opaque name for clicking it; the bot never reads anything into it.
    struct Seen: Equatable { let handle: String; let prompt: String; let at: SIMD3<Float>; let distance: Float }
    /// What an ear tells apart.
    enum Sound: Equatable {
        case tone(String)          // a struck note, by identity (two strikes of the same thing sound the same)
        case sour                  // a wrong-sounding note: a sour chime, a cracked bell, a drone detuning
        case held(Bool)            // a tone that stays (a drone or a fork's tone) starting or stopping
        case bloom                 // a full chord: something finished
        case rumble(Bool)          // a gate or a heavy thing moving
        case tick                  // a small mechanical click
        case page                  // a page picked up
        case arrival               // the whiteout of a crossing
        case dull                  // one dull, quiet tick: "not yours" (a dormant machine)
        case other
    }

    private let game: Game
    /// For the harness only (the referee helps a stalled player on): the brain must not use it.
    let harnessHands: PlaythroughBot
    private var bot: PlaythroughBot { harnessHands }
    init(_ game: Game) { self.game = game; harnessHands = PlaythroughBot(game) }

    // MARK: Time and place
    /// Seconds of play so far.
    var clock: Float { bot.elapsed }
    var feet: SIMD3<Float> { bot.feet }
    var place: Int { switch game.world { case .varrow: return 0; case .glassWood: return 1; case .tideArchive: return 2 } }
    var crossing: Bool { game.isTraveling }
    var journalOpen: Bool { game.journal.isOpen }
    var banner: String? { game.banner }
    var pagesInHand: Int { game.journal.collectedPages.count }

    // MARK: Sight
    /// Interactables in sight: enabled, within `range`, and in front of the camera (within 70 degrees of where it faces) or within 5 m (a player turns round to what is at their back).
    func visible(range: Float = 250) -> [Seen] {
        let cam = game.camera, f = cam.forward
        var out: [Seen] = []
        for it in game.interactables where it.enabled {
            let c = (it.min + it.max) * 0.5, d = c - cam.position, dist = simd_length(d)
            guard dist < range, dist < 5 || simd_dot(simd_normalize(d), f) > 0.34 else { continue }
            out.append(Seen(handle: it.id, prompt: game.displayPrompt(for: it) ?? it.prompt, at: c, distance: dist))
        }
        return out
    }
    /// Look straight at something and read what the crosshair says: the prompt as shown, and whether it looks quieter (done). Nil when it is not under the crosshair (too far, or hidden behind something).
    func inspect(_ s: Seen) -> (prompt: String, done: Bool)? {
        face(s.at); bot.tick()
        guard game.hovered?.id == s.handle else { return nil }
        return (game.hoverPrompt ?? s.prompt, game.hoveredFinished)
    }
    /// How brightly the things within `radius` of `p` glow: the sum of the drawn glow of every visible item whose centre is that close (each capped, so one blazing thing is not the whole answer).
    func glow(near p: SIMD3<Float>, radius: Float) -> Float {
        var sum: Float = 0
        for it in game.scene.items where !it.hidden && it.uniforms.emissive.w > 0.02 {
            let b = it.worldBounds, c = (b.min + b.max) * 0.5
            if simd_length(c - p) <= radius { sum += min(it.uniforms.emissive.w, 4) }
        }
        return sum
    }
    /// How many separate things are glowing within `radius` of `p` (a count, not a sum: a thing that lights is one more).
    func lit(near p: SIMD3<Float>, radius: Float, above: Float = 0.5) -> Int {
        game.scene.items.filter { it in
            guard !it.hidden, it.uniforms.emissive.w > above else { return false }
            let b = it.worldBounds; return simd_length((b.min + b.max) * 0.5 - p) <= radius
        }.count
    }
    /// The guide light (a floating lantern) if one is drawn, and the lamps that are lit.
    var guideLight: SIMD3<Float>? { (game.guideLantern ?? game.varrowGuide).map { SIMD3($0.x, feet.y, $0.y) } }
    /// The points of the trails in this world, in the order they are laid: where the lanterns' path goes.
    func trailPoints() -> [SIMD2<Float>] { (Layout.Navigation.active(for: game.world)?.trails ?? []).flatMap { $0.points } }

    // MARK: Sound
    /// Everything that sounded since the last call.
    func listen() -> [Sound] {
        var out: [Sound] = []
        for e in game.drainEvents() {
            switch e {
            case .chime(let k): out.append(Self.sound(of: k))
            case .doorTry: out.append(.tick)
            case .pageCollected: out.append(.page)
            case .whiteoutStarted: out.append(.arrival)
            case .drone(_, let on): out.append(.held(on))
            case .droneSour: out.append(.sour)
            case .droneBloom: out.append(.bloom)
            case .sluice(_, let open): out.append(.rumble(open))
            case .forkTone(let i, let on): out.append(on ? .tone("fork\(i)") : .held(false)); if on { out.append(.held(true)) }
            case .bell(let bay, let sour): out.append(sour ? .sour : .tone("bell\(bay)"))
            case .orreryTick(let k, _): out.append(.tone("brass\(k)"))
            case .dormant: out.append(.dull)
            default: out.append(.other)
            }
        }
        return out
    }
    private static func sound(of k: ChimeKind) -> Sound {
        switch k {
        case .fail: return .sour
        case .glassTick, .ringTurn: return .tick
        case .lens: return .tone("answer")
        case .tide, .wind, .stone, .glass0, .glass1, .glass2, .glass3, .glass4: return .tone("\(k)")
        case .rumble: return .rumble(true)
        default: return .other
        }
    }

    // MARK: Hands and feet
    func wait(_ seconds: Float) { bot.wait(seconds) }
    /// Walk the trails toward a point, stopping within `within` metres. False if the way is blocked or it takes too long.
    @discardableResult func walk(to p: SIMD3<Float>, within: Float, timeout: Float = 150) -> Bool { bot.walk(to: p, within: within, timeout: timeout) }
    /// Walk straight at a point (the last few metres, indoors).
    @discardableResult func step(to p: SIMD3<Float>, within: Float, timeout: Float = 20) -> Bool { bot.walk(to: p, within: within, timeout: timeout, straight: true) }
    func face(_ p: SIMD3<Float>) { bot.aim(at: p) }
    func turnHead(to yaw: Float) { game.player.yaw = yaw; game.player.pitch = 0; bot.tick() }
    var heading: Float { game.player.yaw }
    /// Click the thing: look at it and press. False if it is not there or not enabled.
    @discardableResult func click(_ s: Seen) -> Bool { bot.click(s.handle) }
    @discardableResult func click(handle: String) -> Bool { bot.click(handle) }
    /// Arrow keys on a ring under the crosshair.
    @discardableResult func arrows(_ s: Seen, steps: Int) -> Bool { bot.pressArrows(on: s.handle, steps: steps) }
    func closeJournal() { bot.closeJournal() }
    /// Any key or click, to put a card away.
    func dismiss() { var i = InputState(); i.click = true; bot.tick(i) }
    /// Walk straight ahead for `seconds` (into something, as a player does at a lit doorway).
    func walkOn(seconds: Float) { for _ in 0..<Int(seconds * 60) { var i = InputState(); i.move = SIMD2(0, 1); bot.tick(i) } }
}

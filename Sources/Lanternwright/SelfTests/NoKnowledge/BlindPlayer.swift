import Foundation
import simd

/// B6: a player who knows nothing. It holds a `Perception` and nothing else: no game, no puzzle class, no layout constant, no flag, no answer. It looks round, walks the trails to what it sees, and works each machine
/// from its feedback with three generic hands (a selftest reads this file's text and fails if it names any of the game's puzzles or layout; see `nokbot`):
///  - **a row of presses** (strike, ring, hold, touch): try each in turn, keep what rings true and stays lit, and when a press sours (everything resets) learn that it was wrong *there* and start again from the
///    part that held; a press that does nothing at all is ruled out too. A single press is just pressed.
///  - **a dial** (turn, change): for each element click round the whole cycle, watching how bright the place grows, settle on the brightest, then go round again (a hill climb on what is lit).
///  - **waiting and watching** where nothing can be pressed (the sea at a quay): stand by the guide light and listen.
/// It never reads a page (a page is opened and shut: the text is not read), a diagram, or the beam's rhythm (it has no way to time a light); where a machine needs those it stalls, and says so.
/// A stall is a stretch of `stallSeconds` of play in which nothing new appears, nothing new sounds and nothing new lights; the bot reports it through `onStall` (the harness may then help it on, and counts that help).
final class BlindPlayer {
    typealias Seen = Perception.Seen
    /// How a machine ended for this player.
    enum Outcome: String { case solvedByTrial = "solved by trial", stalled = "stalled", pressed = "pressed once", waitedFor = "waited for", transit = "crossed" }
    /// One machine (a site: things within reach of each other that are worked together), as the player worked it.
    struct Record {
        var handles: [String]; var prompt: String; var hand: String
        var manipulations = 0; var seconds: Float = 0; var started: Float = 0
        var outcome = Outcome.stalled
        var note = ""
        var helped = false
    }
    struct Stall { var at: SIMD3<Float>; var clock: Float; var handles: [String]; var reason: String }

    let eyes: Perception
    init(_ eyes: Perception) { self.eyes = eyes }
    /// Seconds with nothing new before it is called a stall.
    var stallSeconds: Float = 150
    /// Things the player chooses not to touch (by the words under the crosshair): the other sibling's way.
    var avoid: [String] = []
    /// Called on a stall; true means someone helped (the bot treats the site as done and goes on).
    var onStall: (Stall, [String]) -> Bool = { _, _ in false }
    private(set) var records: [Record] = []
    private(set) var stalls: [Stall] = []
    private(set) var presses = 0
    /// Called after each machine has been worked, with the record (the harness judges it against the game's own flags).
    var onRecord: (Record) -> Void = { _ in }
    var trace = false

    private var everSeen = Set<String>()
    private var memory = [String: Seen]()                // what the player remembers standing in this place, where it was last seen
    private var memoryPlace = -1
    private var finished = Set<String>()                 // things the crosshair showed as done
    private var worked = [String: Int]()                 // handle -> times its site was worked
    private var workedWhen = [String: Int]()             // handle -> what the player knew (`knowledge`) when it was last worked
    private var knowledge = 0                            // grows when something new comes into sight or a new line of words appears
    private var wordsSeen = Set<String>()
    private var visitedTrail = Set<Int>()
    private var lastNew: Float = 0
    private var lastPlace = -1
    private var current: Record?
    private(set) var gaveUp: String?
    private var stallStreak = 0
    private var watched = [String: Int]()
    private var exploreFails = 0                        // walks to unvisited ground that could not be made, since the last thing worked
    private var stallMark = -1

    // MARK: The loop
    /// Play until `done()` says the game has been won or `limit` seconds of play have passed.
    func play(until done: () -> Bool, limit: Float) {
        lastNew = eyes.clock
        while !done() && eyes.clock < limit && gaveUp == nil {
            if eyes.crossing { eyes.wait(0.5); lastNew = eyes.clock; continue }
            if eyes.journalOpen { eyes.closeJournal(); continue }
            if eyes.place != lastPlace { lastPlace = eyes.place; visitedTrail = []; lastNew = eyes.clock }
            let seen = scan()
            noteProgress(listen: [])
            if let site = chooseSite(seen) { work(site); continue }
            // Nothing to press in sight: follow the guide light, else go to the nearest trail point not yet visited, else wait and listen.
            if let g = eyes.guideLight, simd_length(SIMD2(g.x - eyes.feet.x, g.z - eyes.feet.z)) > 6 { eyes.walk(to: g, within: 3, timeout: 120); continue }
            if exploreFrontier() { continue }
            listenAround(seconds: 10)
            checkStall(handles: [], reason: "nothing in sight to press, nowhere new to walk")
        }
    }

    // MARK: Looking
    /// Turn through a full circle and gather what is in sight.
    private func scan() -> [Seen] {
        var found: [String: Seen] = [:]
        let h0 = eyes.heading
        for k in 0..<6 { eyes.turnHead(to: h0 + Float(k) * .pi / 3); for s in eyes.visible() { found[s.handle] = s } }
        eyes.turnHead(to: h0)
        if memoryPlace != eyes.place { memory = [:]; memoryPlace = eyes.place }
        for (h, s) in found { memory[h] = s }
        for (h, s) in memory where found[h] == nil && simd_length(SIMD2(s.at.x - eyes.feet.x, s.at.z - eyes.feet.z)) < 25 { memory[h] = nil }          // close enough to see it is not there (or not to be pressed) now
        found = memory
        for h in found.keys where !everSeen.contains(h) { everSeen.insert(h); lastNew = eyes.clock; knowledge += 1 }
        if let b = eyes.banner, !wordsSeen.contains(b) { wordsSeen.insert(b); knowledge += 1; lastNew = eyes.clock }
        return found.values.sorted { $0.distance < $1.distance }
    }
    private func noteProgress(listen sounds: [Perception.Sound]) {
        for s in sounds + eyes.listen() { switch s { case .tone, .bloom, .rumble, .page, .held(true): lastNew = eyes.clock; if s == .bloom || s == .rumble(true) { visitedTrail = [] }; default: break } }
    }
    private func listenAround(seconds: Float) {
        var t: Float = 0
        while t < seconds { eyes.wait(1); t += 1; noteProgress(listen: []) }
    }
    private func checkStall(handles: [String], reason: String) {
        guard eyes.clock - lastNew > stallSeconds else { return }
        _ = reportStall(handles: handles, reason: reason)
        let mark = everSeen.count + presses
        stallStreak = mark == stallMark ? stallStreak + 1 : 1
        stallMark = mark
        if stallStreak >= 3 { gaveUp = reason }
        visitedTrail = []
    }
    /// A stall: record it and ask for help. True when it came (the machine counts as done and the player goes on).
    private func reportStall(handles: [String], reason: String) -> Bool {
        let st = Stall(at: eyes.feet, clock: eyes.clock, handles: handles, reason: reason)
        stalls.append(st)
        lastNew = eyes.clock
        let helped = onStall(st, handles)
        if helped { for h in handles { finished.insert(h) }; visitedTrail = []; knowledge += 1 }
        current?.helped = helped
        return helped
    }

    // MARK: Choosing what to work
    private func shunned(_ words: String) -> Bool { let l = words.lowercased(); return avoid.contains { l.contains($0.lowercased()) } }
    private func isTravel(_ p: String) -> Bool { let l = p.lowercased(); return l.contains("lens") || l.contains("return") || l.contains("step into") }
    private func isRead(_ p: String) -> Bool { p.lowercased().hasPrefix("read") }
    private func isDial(_ p: String) -> Bool { var l = p.lowercased(); if let r = l.range(of: ": ") { l = String(l[r.upperBound...]) }; return l.hasPrefix("turn") || l.hasPrefix("change") }          // "Oren\u{2019}s way: turn the ring" is a dial

    /// A site is the things of one kind within 45 m of each other; the nearest to the guide light (or to the feet) first; crossings last.
    private func chooseSite(_ seen: [Seen]) -> [Seen]? {
        let live = seen.filter { s in !finished.contains(s.handle) && ((worked[s.handle] ?? 0) < 2 || (workedWhen[s.handle] ?? -1) < knowledge) && !shunned(s.prompt) }
        guard !live.isEmpty else { return nil }
        let anchor = eyes.guideLight ?? eyes.feet
        func near(_ s: Seen) -> Float { simd_length(s.at - anchor) }
        let work = live.filter { !isTravel($0.prompt) }
        if work.isEmpty && frontierRemains() { return nil }                       // a player looks round the place before they leave it
        let pool = work.isEmpty ? live : work
        // Stand-alone reads first (cheap, and a player reads what lies about), then machines.
        let reads = pool.filter { isRead($0.prompt) }.sorted { near($0) < near($1) }
        if let r = reads.first, simd_length(r.at - eyes.feet) < 25 { return [r] }
        let machines = pool.filter { !isRead($0.prompt) }.sorted { near($0) < near($1) }
        guard let head = machines.first else { return pool.sorted { near($0) < near($1) }.first.map { [$0] } }
        let kind = isDial(head.prompt)
        // Dials work together (a mirror and a pane make one picture); presses are a row when their words are the same (three stones that all say "Touch the stone"), however far apart they stand.
        let site = kind ? machines.filter { isDial($0.prompt) && simd_length($0.at - head.at) < 28 } : machines.filter { $0.prompt == head.prompt && simd_length($0.at - head.at) < 400 }
        return site
    }

    // MARK: Working a site
    private func work(_ site: [Seen]) {
        guard let head = site.first else { return }
        exploreFails = 0
        for s in site { worked[s.handle, default: 0] += 1; workedWhen[s.handle] = knowledge }
        go(head); aim(at: head)
        if let seenPrompt = eyes.inspect(head)?.prompt, shunned(seenPrompt) { for s in site { finished.insert(s.handle) }; return }          // the words under the crosshair name the other sibling's way: not mine
        let handles = site.map { $0.handle }
        let above = abs(head.at.y - eyes.feet.y)
        let hand = isRead(head.prompt) ? "read" : isDial(head.prompt) ? "dial" : (head.prompt.lowercased().hasPrefix("hold") ? "hold" : "press")
        current = Record(handles: handles, prompt: head.prompt, hand: hand, started: eyes.clock)
        let before = everSeen.count
        if above > 15 && !eyes.crossing {                                                                  // in sight and far overhead: no trail goes up to it, and no number of presses from here reaches it
            current?.note = "in sight \(Int(above)) m overhead; no trail leads up to it"
            _ = reportStall(handles: handles, reason: current!.note)
            current!.seconds = eyes.clock - current!.started; records.append(current!); onRecord(current!); current = nil
            return
        }
        switch hand {
        case "read": readOne(head)
        case "dial": dial(site)
        case "hold": hold(head)
        default: row(site)
        }
        current!.seconds = eyes.clock - current!.started
        if current!.outcome == .solvedByTrial || current!.outcome == .waitedFor { visitedTrail = [] }          // something changed in the world: ground that was closed may be open
        if current!.outcome == .stalled {
            if current!.manipulations >= 4 { _ = reportStall(handles: handles, reason: current!.note) } else { checkStall(handles: handles, reason: "no progress working \(site.count) \(hand) machine(s)") }
        }
        if everSeen.count > before { current!.note += " (new things came into sight)" }
        records.append(current!); onRecord(current!); current = nil
    }

    private func go(_ s: Seen, within: Float = 2.4) {
        if simd_length(SIMD2(s.at.x - eyes.feet.x, s.at.z - eyes.feet.z)) > within { eyes.walk(to: s.at, within: within, timeout: 150) }
    }
    /// Several things in a row can hide each other from a shallow angle: if the crosshair is not on this one, step to where it is (a pace to either side, then closer). True when it is under the crosshair.
    @discardableResult private func aim(at s: Seen) -> Bool {
        if eyes.inspect(s) != nil { return true }
        let d0 = SIMD2(s.at.x - eyes.feet.x, s.at.z - eyes.feet.z), dir = simd_length(d0) > 0.01 ? simd_normalize(d0) : SIMD2<Float>(0, 1), side = SIMD2(-dir.y, dir.x)
        for off: Float in [0.8, -0.8, 1.6, -1.6, 2.4, -2.4] {
            let p = SIMD2(s.at.x, s.at.z) - dir * 1.7 + side * off
            eyes.step(to: SIMD3(p.x, eyes.feet.y, p.y), within: 0.3, timeout: 8)
            if eyes.inspect(s) != nil { return true }
        }
        return false
    }
    private struct Reaction { var sour = false; var sounded = false; var done = false; var rise: Float = 0; var heard: [Perception.Sound] = [] }
    /// One manipulation: go there, click, listen and watch for `dwell` seconds, and ask the crosshair whether it is done.
    private func press(_ s: Seen, dwell: Float = 0.9, glowAround: SIMD3<Float>? = nil, radius: Float = 12) -> Reaction {
        go(s)
        aim(at: s)
        let gap = simd_length(SIMD2(s.at.x - eyes.feet.x, s.at.z - eyes.feet.z))
        if gap > 4 { current?.note += " [could not get closer than \(Int(gap)) m]" }
        let g0 = eyes.glow(near: glowAround ?? s.at, radius: radius)
        _ = eyes.listen()
        eyes.click(s); presses += 1; current?.manipulations += 1
        eyes.wait(dwell)
        var r = Reaction(); r.heard = eyes.listen()
        if let b = eyes.banner, !wordsSeen.contains(b) { wordsSeen.insert(b); knowledge += 1; lastNew = eyes.clock }
        for h in r.heard { switch h { case .sour: r.sour = true; case .tone, .held(true), .bloom, .rumble, .page: r.sounded = true; lastNew = eyes.clock; default: break } }
        if eyes.journalOpen { eyes.closeJournal() }
        r.rise = eyes.glow(near: glowAround ?? s.at, radius: radius) - g0
        if let i = eyes.inspect(s), i.done { r.done = true; finished.insert(s.handle) }
        if r.rise > 0.3 { lastNew = eyes.clock }
        if trace { print("      press \(s.handle) t=\(Int(eyes.clock)) sour \(r.sour) sounded \(r.sounded) rise \(r.rise) done \(r.done) heard \(r.heard)") }
        return r
    }

    private func readOne(_ s: Seen) {
        _ = press(s); eyes.closeJournal()
        finished.insert(s.handle); current?.outcome = .pressed
    }

    /// Hold something against a slow change (the sea at a pipe): press, then wait for the thing to say it is done, up to a tide's worth.
    private func hold(_ s: Seen) {
        var r = press(s)
        var t: Float = 0
        while !r.done && t < 150 {
            eyes.wait(2); t += 2
            let heard = eyes.listen()
            for h in heard { if case .rumble = h { r.done = true }; if case .bloom = h { r.done = true } }
            if let i = eyes.inspect(s), i.done { r.done = true }
            if heard.contains(where: { if case .tone = $0 { return true }; return false }) { lastNew = eyes.clock }
        }
        if r.done { finished.insert(s.handle); current?.outcome = .waitedFor } else { current?.note = "held \(Int(t)) s, nothing answered" }
    }

    /// A row of presses learned from feedback (see the type's note).
    private func row(_ site: [Seen]) {
        var order = site
        var confirmed: [Seen] = []
        var ruled: [Int: Set<String>] = [:]
        var budget = 6 * site.count * site.count + 10
        var unsure = true                                                                          // the row may be half played from an earlier visit: a first sour note says nothing about the thing pressed
        var alone = site.count == 1 && memory.values.filter { $0.prompt == site[0].prompt }.count == 1          // the only thing of its kind: pressing it once is all there is to do
        while budget > 0 {
            budget -= 1
            let pos = confirmed.count
            let here = eyes.feet
            order.sort { simd_length($0.at - here) < simd_length($1.at - here) }
            guard let c = order.first(where: { cand in !confirmed.contains { $0.handle == cand.handle } && !(ruled[pos]?.contains(cand.handle) ?? false) }) else {
                current?.note = "every press was ruled out at position \(pos + 1)"; return
            }
            let r = press(c)
            if r.done { finished.formUnion(site.map { $0.handle }); current?.outcome = alone ? .pressed : .solvedByTrial; return }
            if alone { let answered = r.sounded || r.rise > 0.3 || eyes.crossing; if answered { finished.insert(c.handle) }; current?.outcome = answered ? .pressed : .stalled; if !answered { current?.note = "pressed, nothing answered" }; return }
            if r.sour && unsure && pos == 0 { unsure = false; eyes.wait(1.6); continue }
            unsure = false
            if r.sour {
                ruled[pos, default: []].insert(c.handle)
                eyes.wait(1.6)                                                                    // a sour note takes a moment to die away; a player waits it out
                for p in confirmed { _ = press(p, dwell: 0.9) }                                  // everything reset: play the held part again
            } else if r.sounded || r.rise > 0.3 {
                confirmed.append(c)
                if confirmed.count == site.count { _ = eyes.listen(); eyes.wait(3.5); let after = eyes.listen(); if after.contains(.tone("answer")) { finished.formUnion(site.map { $0.handle }); current?.outcome = .solvedByTrial } else if let i = eyes.inspect(c), i.done { finished.formUnion(site.map { $0.handle }); current?.outcome = .solvedByTrial } else { current?.note = "the whole row rang true and nothing said it was done" }; return }
            } else {
                ruled[pos, default: []].insert(c.handle)                                          // nothing happened at all
            }
            alone = false
        }
        current?.note = "gave up after \(current?.manipulations ?? 0) presses with \(confirmed.count) held"
    }

    /// A dial, or several: click each round its cycle, keep the brightest, and go round again.
    private func dial(_ site: [Seen]) {
        let centre = site.reduce(SIMD3<Float>.zero) { $0 + $1.at } / Float(site.count)
        let spread: Float = site.map { simd_length($0.at - centre) }.max() ?? 0
        let radius: Float = max(14, spread + 10)
        let dwell: Float = 2.3                                                                   // long enough for a thing that must be held still to be held
        func level() -> Float { eyes.glow(near: centre, radius: radius) }
        var passes = 0
        let t0 = eyes.clock
        while passes < 6 && eyes.clock - t0 < 400 {
            passes += 1
            var improved = false
            for e in site where !finished.contains(e.handle) {
                go(e)
                _ = eyes.listen(); eyes.wait(dwell)
                let base = level()
                var best: (steps: Int, v: Float) = (0, base)
                var cycle = 12
                for s in 1...12 {
                    let r = press(e, dwell: dwell, glowAround: centre, radius: radius)
                    let v = level()
                    if r.heard.contains(where: { if case .rumble = $0 { return true }; return $0 == .bloom }) { knowledge += 1; current?.outcome = .solvedByTrial; current?.note = "something big moved while it was turned" }
                    if r.done { finished.insert(e.handle); current?.outcome = .solvedByTrial; return }
                    if v > best.v + 0.05 { best = (s, v); improved = true }
                    if s >= 2 && abs(v - base) < 0.02 { cycle = s; break }
                }
                if best.steps > 0 { for _ in 0..<best.steps { _ = press(e, dwell: dwell, glowAround: centre, radius: radius) } }
                _ = cycle
                let before = Set(memory.keys); _ = eyes.listen(); eyes.wait(3)
                let after = scan()
                if after.contains(where: { !before.contains($0.handle) && !isRead($0.prompt) }) { current?.outcome = .solvedByTrial; finished.formUnion(site.map { $0.handle }); return }
                if site.contains(where: { finished.contains($0.handle) }) { current?.outcome = .solvedByTrial; return }
            }
            if !improved { break }
        }
        if current?.outcome != .solvedByTrial && site.count == 1 && watched[site[0].handle, default: 0] < 3 { watched[site[0].handle, default: 0] += 1; watchAndPress(site[0], centre: centre) }
        if current?.outcome != .solvedByTrial { current?.note = "went round \(passes) time(s), \(current?.manipulations ?? 0) clicks; the light never settled" }
    }

    /// A single dial that nothing answered by going round: watch the place, and press at the moment something there brightens (what a player does with a thing that has a time to it). Counts as an answer when more
    /// of the place stays lit than before.
    private func watchAndPress(_ e: Seen, centre: SIMD3<Float>) {
        let litBefore = eyes.lit(near: centre, radius: 40)
        var baseline = eyes.glow(near: centre, radius: 14), sincePress: Float = 99, t: Float = 0, pressed = 0
        while t < 400 {
            eyes.wait(0.1); t += 0.1; sincePress += 0.1
            let g = eyes.glow(near: centre, radius: 14)
            if g > baseline + 0.4 && sincePress > 1.0 { _ = press(e, dwell: 0.2, glowAround: centre, radius: 14); pressed += 1; sincePress = 0 }
            baseline += (g - baseline) * 0.02
            if pressed > 0 && eyes.lit(near: centre, radius: 40) >= litBefore + 3 { eyes.wait(3); if eyes.lit(near: centre, radius: 40) >= litBefore + 3 { current?.outcome = .solvedByTrial; current?.note = "watched and pressed as it brightened: \(pressed) presses in \(Int(t)) s"; return } }
        }
        current?.note += " (watched \(Int(t)) s, pressed \(pressed) times as it brightened)"
    }

    // MARK: Walking about
    private func frontierRemains() -> Bool {
        if exploreFails >= 3 { return false }
        let here = SIMD2(eyes.feet.x, eyes.feet.z)
        return eyes.trailPoints().enumerated().contains { !visitedTrail.contains($0.offset) && simd_length($0.element - here) >= 12 }
    }
    /// Walk to the nearest trail point not yet visited (at least 12 m off). False when every point has been visited.
    private func exploreFrontier() -> Bool {
        let pts = eyes.trailPoints()
        let here = SIMD2(eyes.feet.x, eyes.feet.z)
        for (i, p) in pts.enumerated() where simd_length(p - here) < 12 { visitedTrail.insert(i) }
        let next = pts.enumerated().filter { !visitedTrail.contains($0.offset) }.min { simd_length($0.element - here) < simd_length($1.element - here) }
        guard let n = next else { return false }
        let ok = eyes.walk(to: SIMD3(n.element.x, eyes.feet.y, n.element.y), within: 8, timeout: 90)
        visitedTrail.insert(n.offset)
        if !ok { exploreFails += 1; eyes.wait(2) }
        return true
    }
}

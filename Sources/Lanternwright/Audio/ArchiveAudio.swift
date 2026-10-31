import Foundation

/// S04.4: the Tide Archive's sound (S04 plan; S02 section 3 lever 5 "mood"): its own drone from its own base tones, the tide's wash that follows the water's level and its distance, drips off the ledger
/// shelves, the sluice gates' creak and the tuning fork's held tone. Everything is built here and mixed in AFTER the main synth (`AudioEngine`: one line in the render callback), so nothing in the
/// ambience mixer changes. All pitches come from `ToneTable` (pillar 5); water is bubbles (F03 A4: never filtered noise); the sluice has the door's weight rules (F07 A-door): real harmonics in
/// 150-900 Hz, a low thud under them, a level guard against a stone run step.
///
/// Inputs are values the Archive world feeds each frame (`Inputs`: the tide level from `Tide.level(clock)`, its rate, the distance to the water, the route); events arrive from the game
/// (`GameEvent.sluice`, `.forkTone`). The module has no idea what a Game is: the selftests drive exactly what the engine drives.
enum ArchiveTones {
    /// The Archive's own base tones (F02 answer 2: each world has its own): D3 (the stones' D an octave down), G3 (the bell buoy's G an octave down: the fourth) and A3 (the stones' A an octave down): an open
    /// stack of fifths and fourths with no third in it, the sound of a place that keeps its books and has not been answered.
    static let baseHz: [Float] = [ToneTable.stoneHz[0] / 2, ToneTable.buoyHz / 2, ToneTable.stoneHz[1] / 2]
    /// The drips ring at the stones' tones two octaves up and one above: A5, D6 and the next D, and a high A (880, 1175, 1175 x 1.5 is not used: only ToneTable's own pitches and their octaves).
    static let dripHz: [Float] = [ToneTable.stoneHz[1] * 2, ToneTable.stoneHz[2] * 2, ToneTable.stoneHz[0] * 4, ToneTable.stoneHz[1] * 4]
    /// The room's own resonances under the tide: the stones' D, G and A two octaves below (73, 98, 110 Hz) with their 2nd and 3rd harmonics, so a small speaker still has them.
    static let hallHz: [Float] = [ToneTable.stoneHz[0] / 4, ToneTable.buoyHz / 4, ToneTable.stoneHz[1] / 4]
}

final class ArchiveAudio {
    struct Inputs: Equatable {
        /// True while the player is in the Archive (the layers fade in and out with it).
        var active = false
        /// The route: the drone's character (Ilse's: ordered pulses on the base tones; Oren's: a drift between them).
        var route: PageAuthor? = nil
        /// `Tide.level(clock)`, 0 low ... 1 high, and its rate per second (`Tide.rate(clock)`).
        var tide: Float = 0
        var tideRate: Float = 0
        /// Metres from the listener to the nearest water the tide moves (the galleries' surface): the wash is loud near it and gone far from it.
        var waterDistance: Float = 60
    }

    /// An event the game sends: a sluice gate opening or closing, the tuning fork's tone held or let go.
    enum Event: Equatable { case sluice(Int, opening: Bool), fork(Int, on: Bool) }

    let sampleRate: Float
    private let lock = NSLock()
    private var inputs = Inputs()
    private var queued: [Event] = []
    private var noise: FoleyNoise
    private let bubbles: BubbleSynth

    // Smoothed state
    private var act: Float = 0
    private var level: Float = 0, rate: Float = 0, wg: Float = 0
    private var t: Double = 0
    private var baseGain: [Float] = [0, 0, 0]
    /// Per-voice phases, ACCUMULATED each sample (2 pi f dt): a frequency that wanders (Oren's drift, the hall's lean) would otherwise smear the pitch by f' x t after minutes of play.
    private var dronePhase: [Double] = [0, 0, 0], hallPhase: [Double] = [0, 0, 0]
    // Drips
    private struct Drip { var f0: Float; var age: Float; var delay: Float; var amp: Float; var pan: Float }
    private var drips: [Drip] = []
    /// Drips started (not their echoes): for the selftests.
    private(set) var dripsStarted = 0
    // Fork
    private var forkTarget: [Float] = [0, 0, 0], forkLevel: [Float] = [0, 0, 0], forkStruck: [Float] = [0, 0, 0]
    // Sluice voices (precomputed buffers)
    private struct Voice { var buf: [Float]; var pos = 0; var gain: Float; var pan: Float }
    private var voices: [Voice] = []
    private let openBuf: [Float], closeBuf: [Float]

    /// `startTime` seeds the slow clocks (the pulses and drifts): the selftests start late to prove nothing depends on how long the game has been running.
    init(sampleRate: Float, seed: UInt32 = 0xA2C1, startTime: Double = 0) {
        t = startTime
        self.sampleRate = sampleRate
        noise = FoleyNoise(seed: seed)
        bubbles = BubbleSynth(sampleRate: sampleRate, seed: seed ^ 0x5EED)
        openBuf = ArchiveFoley.sluice(opening: true, sampleRate: sampleRate)
        closeBuf = ArchiveFoley.sluice(opening: false, sampleRate: sampleRate)
    }

    func setInputs(_ i: Inputs) { lock.lock(); inputs = i; lock.unlock() }
    func handle(_ e: Event) { lock.lock(); queued.append(e); lock.unlock() }

    /// Add the Archive's layers to `left` / `right` (it adds, it does not overwrite).
    /// `master` is the synth's own master gain (the main mix runs at 0.5 in the game): the Archive's layers are scaled by it so they stand to the stones' drone, the chimes and the footsteps as they were tuned to.
    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, master: Float = 1) {
        lock.lock(); let inp = inputs; let events = queued; queued.removeAll(); lock.unlock()
        for e in events {
            switch e {
            case .sluice(_, let opening): if voices.count < 4 { voices.append(Voice(buf: opening ? openBuf : closeBuf, gain: ArchiveFoley.sluiceGain, pan: 0.15 * noise.next())) }
            case .fork(let k, let on) where (0..<3).contains(k): forkTarget[k] = on ? 1 : 0; if on { forkStruck[k] = 1 }
            case .fork: break
            }
        }
        let dt = 1 / sampleRate
        for i in 0..<frames {
            t += Double(dt)
            let tf = Float(t)
            // Smooth the inputs (about 1.5 s for presence, 0.3 s for the water's level).
            act += ((inp.active ? 1 : 0) - act) * dt / 1.5
            level += (inp.tide - level) * dt / 0.3
            rate += (inp.tideRate - rate) * dt / 0.3
            let target = 1 / (1 + (inp.waterDistance / 6) * (inp.waterDistance / 6))               // loud at the water, a tenth of it 18 m away
            wg += (target - wg) * dt / 0.4
            var l: Float = 0, r: Float = 0
            if act > 1e-4 {
                // --- the drone: three base tones, each with a soft octave and a slow detune, by route key
                var drone: Float = 0
                for v in 0..<3 {
                    let f = ArchiveTones.baseHz[v]
                    var g: Float, cents: Float = 0
                    if inp.route == .oren {                                                           // a drift: incommensurate slow swells, a few cents of wander
                        let rates: [Float] = [0.037, 0.053, 0.071]
                        g = 0.55 + 0.45 * sin(2 * .pi * rates[v] * tf + Float(v) * 2.1)
                        cents = 6 * sin(2 * .pi * 0.043 * tf + Float(v))
                    } else {                                                                          // ordered pulses, a twelfth of a minute apart, the stones' order
                        let ph = tf / 12 - Float(v) / 3
                        let pulse = max(0, sin(2 * .pi * ph)); g = 0.35 + 0.65 * pulse * pulse
                    }
                    baseGain[v] += (g - baseGain[v]) * dt / 0.4
                    let fr = f * pow(2, cents / 1200)
                    dronePhase[v] += 2 * Double.pi * Double(fr) * Double(dt); if dronePhase[v] > 2 * Double.pi { dronePhase[v] -= 2 * Double.pi }
                    let ph = dronePhase[v]
                    drone += Float(sin(ph) + 0.5 * sin(ph * 1.0007 + 0.4) + 0.22 * sin(2 * ph)) * baseGain[v] * ArchiveFoley.droneGain
                }
                l += drone; r += drone
                // --- the tide: laps (bubbles) that quicken with the water's rate, a hall hum that swells with its level and leans with its direction
                let movement = min(1, abs(rate) / 0.035)
                let lapRate = wg * (1.5 + 20 * movement)
                let b = bubbles.next(washRate: lapRate, washLevel: 0.25 + 0.5 * wg * (0.4 + 0.6 * movement))
                l += b.0 * wg; r += b.1 * wg
                var hum: Float = 0
                for v in 0..<3 {
                    let f = ArchiveTones.hallHz[v] * (1 + 0.004 * (rate / 0.035))                    // rising water leans the room a few cents sharp, falling a few flat
                    hallPhase[v] += 2 * Double.pi * Double(f) * Double(dt); if hallPhase[v] > 2 * Double.pi { hallPhase[v] -= 2 * Double.pi }
                    let ph = hallPhase[v]
                    hum += Float(sin(ph) + 0.55 * sin(2 * ph + 0.3) + 0.35 * sin(3 * ph + 0.9)) * (0.4 + 0.6 * level) * 0.010
                }
                hum *= wg * 0.5 + 0.12
                l += hum; r += hum
                // --- the drips: the ledgers drip more as the water falls and leaves them (a drip every few seconds when it is still)
                let falling = max(0, -rate / 0.035)
                let dripRate = 0.22 + 1.1 * falling
                if noise.unit() < dripRate * dt && drips.count < 14 {
                    let f = ArchiveTones.dripHz[min(3, Int(noise.unit() * 4))]
                    let pan = 0.8 * noise.next()
                    dripsStarted += 1
                    drips.append(Drip(f0: f, age: 0, delay: 0, amp: 0.05 * (0.6 + 0.4 * noise.unit()), pan: pan))
                    drips.append(Drip(f0: f, age: 0, delay: 0.19, amp: 0.016, pan: -pan))          // the gallery's echo
                }
            }
            // drips ring while they ring out, whether or not the layers have faded
            for k in drips.indices {
                if drips[k].delay > 0 { drips[k].delay -= dt; continue }
                let a = drips[k].age
                let f = drips[k].f0 * (1 + 0.14 * min(1, a / 0.03))
                let x = sin(2 * .pi * f * a) * drips[k].amp * exp(-a / 0.028) * min(1, a / 0.0008)
                l += x * (0.5 - 0.5 * drips[k].pan); r += x * (0.5 + 0.5 * drips[k].pan)
                drips[k].age += dt
            }
            drips.removeAll { $0.delay <= 0 && $0.age > 0.25 }
            // --- the tuning fork's held tone (it sounds wherever the player stands: it is in their hand)
            for k in 0..<3 where forkTarget[k] > 0 || forkLevel[k] > 1e-4 {
                forkLevel[k] += (forkTarget[k] - forkLevel[k]) * dt / (forkTarget[k] > forkLevel[k] ? 0.03 : 0.25)
                let f = ToneTable.stoneHz[k]
                let beat = 0.6                                                                       // two tines a little apart beat slowly, as a real fork's do
                let ph = 2 * Double.pi * Double(f) * t
                var x = Float(sin(ph) + 0.8 * sin(2 * Double.pi * Double(f + Float(beat)) * t + 0.7)) * 0.5
                x += 0.16 * forkStruck[k] * Float(sin(2 * Double.pi * Double(f * 6.27) * t))                  // the fork's bright clang (its first overtone, 6.27 x) just after the strike, gone in 0.12 s
                forkStruck[k] = max(0, forkStruck[k] - dt / 0.12)
                let s = x * forkLevel[k] * ArchiveFoley.forkGain
                l += s * 0.9; r += s * 0.9
            }
            // --- the sluice gates
            for k in voices.indices where voices[k].pos < voices[k].buf.count {
                let x = voices[k].buf[voices[k].pos] * voices[k].gain
                l += x * (0.5 - 0.5 * voices[k].pan); r += x * (0.5 + 0.5 * voices[k].pan)
                voices[k].pos += 1
            }
            left[i] += l * master; right[i] += r * master
        }
        voices.removeAll { $0.pos >= $0.buf.count }
    }
}

enum ArchiveFoley {
    /// A sluice gate (an oak and iron slab on a rack, lifting out of or dropping into its stone frame): the F07 door's weight rules. Opening: a soft unseating thud, a stick-slip CREAK whose real
    /// harmonics (n x f0 with f0 rising 128 to 170 Hz as the gate climbs, only the partials inside 150-900 Hz), the water through the gap (a stream of bubbles that quickens, quiet), a long low ease at
    /// the end. Closing: the same creak falling, and a HEAVY thud at the end as the gate seats (the door's modes, 72 to 138 Hz with their overtones). About 2.3 s. Deterministic.
    static let sluiceGain: Float = 0.96, forkGain: Float = 0.14, droneGain: Float = 0.075

    static func sluice(opening: Bool, sampleRate sr: Float, seed: UInt32 = 0x51A1) -> [Float] {
        var n = FoleyNoise(seed: seed ^ (opening ? 1 : 2))
        let dur: Float = 2.3, len = Int(dur * sr)
        var out = [Float](repeating: 0, count: len)
        let bubbles = BubbleSynth(sampleRate: sr, seed: seed ^ 0xB0B)
        // the creak's stick-slip: slips at 7-13 Hz, irregular, each a fast attack and a ~45 ms decay of random height
        var nextSlip: Float = 0.12, slipAge: Float = 99, slipAmp: Float = 0
        var friction = Biquad.bandpass(520, q: 0.8, sampleRate: sr), frictionLow = Biquad.bandpass(280, q: 0.9, sampleRate: sr)
        let modes: [(f: Float, tau: Float, a: Float)] = [(72, 0.085, 1.0), (96, 0.07, 0.85), (118, 0.06, 0.6), (138, 0.05, 0.45)]
        let harmonics: [(n: Float, a: Float, decay: Float)] = [(2, 0.75, 0.8), (3, 0.6, 0.6), (4, 0.42, 0.5), (6, 0.22, 0.35)]
        var bodyA = Biquad.lowpass(150, sampleRate: sr), bodyB = Biquad.lowpass(150, sampleRate: sr)
        var phases = [Float](repeating: 0, count: 9)             // by harmonic number, so a partial that crosses the band edge keeps its own phase
        let thudAt: Float = opening ? 0 : 1.95                                                          // closing: it seats at the end
        let thudAmp: Float = opening ? 0.55 : 1.0
        let creakStart: Float = opening ? 0.12 : 0.05, creakEnd: Float = opening ? 1.85 : 1.9
        for i in 0..<len {
            let ts = Float(i) / sr
            // --- the thud
            var thud: Float = 0
            let u = ts - thudAt
            if u >= 0 {
                let attack = min(1, u / 0.006), att = attack * attack * (3 - 2 * attack)
                for m in modes {
                    thud += m.a * sin(2 * .pi * m.f * u) * exp(-u / m.tau)
                    for h in harmonics { thud += m.a * h.a * sin(2 * .pi * m.f * h.n * u) * exp(-u / (m.tau * h.decay)) }
                }
                thud += bodyB.process(bodyA.process(n.next())) * 5.0 * exp(-u / 0.05)
                thud *= att * thudAmp * 0.2
            }
            // --- the creak: a harmonic stack gated by the slips
            var creak: Float = 0
            if ts >= creakStart && ts < creakEnd {
                let p = (ts - creakStart) / (creakEnd - creakStart)
                if ts >= nextSlip { slipAge = 0; slipAmp = 0.45 + 0.55 * n.unit(); nextSlip = ts + 1 / (7 + 6 * n.unit()) }
                let slip = slipAge < 0.3 ? min(1, slipAge / 0.006) * exp(-slipAge / 0.045) * slipAmp : 0
                slipAge += 1 / sr
                let f0: Float = opening ? 128 + 42 * p : 170 - 42 * p
                let env = min(1, (ts - creakStart) / 0.15) * min(1, (creakEnd - ts) / 0.25)
                var stack: Float = 0
                for h in 1...7 {
                    let f = Float(h) * f0
                    phases[h] += 2 * .pi * f / sr; if phases[h] > 2 * .pi { phases[h] -= 2 * .pi }
                    let edge = min(1, max(0, (f - 150) / 40)) * min(1, max(0, (900 - f) / 60))          // a partial fades in over 150-190 Hz and out over 840-900 Hz: no hard on and off
                    if edge > 0 { stack += sin(phases[h]) * edge / pow(Float(h), 0.8) }
                }
                let x = n.next()
                creak = (stack * 0.55 + (friction.process(x) + frictionLow.process(x)) * 0.35) * (0.25 + 0.75 * slip) * env
            }
            // --- the water through the gap
            var water: Float = 0
            let wStart: Float = opening ? 0.3 : 0.1, wEnd: Float = opening ? 2.1 : 1.8
            if ts >= wStart && ts < wEnd {
                let p = (ts - wStart) / (wEnd - wStart)
                let rate = 6 + 30 * (opening ? sin(.pi * p) : 1 - p)
                let b = bubbles.next(washRate: rate, washLevel: 0.5)
                water = (b.0 + b.1) * 0.5 * 0.35
            } else if bubbles.isActive { let b = bubbles.next(); water = (b.0 + b.1) * 0.5 * 0.35 }
            out[i] = thud + creak * 0.34 + water
        }
        // fade the very last samples so the buffer ends clean
        for i in 0..<Int(0.02 * sr) { out[len - 1 - i] *= Float(i) / (0.02 * sr) }
        return out
    }
}

extension ArchiveAudio {
    /// What the game feeds the Archive's sound each frame: present while the player is in the route world with its puzzle switched on, the tide from the same function the gates and the water use. Static so
    /// the selftests drive what the engine drives.
    static func inputs(game: Game) -> Inputs {
        let inArchive = game.tideArchive != nil && game.world == game.routeWorld && game.chosenPath != nil
        return Inputs(active: inArchive, route: game.chosenPath, tide: Tide.level(game.time), tideRate: Tide.rate(game.time), waterDistance: game.archiveWaterDistance)
    }
}

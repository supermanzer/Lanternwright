import Foundation

/// All of Lanternwright's sound is synthesised, with no sample files. This class is plain DSP with no AVFoundation,
/// so it can be rendered offline and tested; `AudioEngine` just feeds it to the speakers.
///
/// - Wind: pink noise (equal energy per octave, like real wind) through a low-pass whose cutoff rides a slow "gust".
/// - Surf: three overlapping swells of low-passed brown noise (a soft wash and a rumble) with only a faint foam fizz
///   as the water drains, since real surf is mostly low-mid energy and white-ish noise sounds like TV static.
///   and draining away.
/// - Footsteps: softly attacked, varied bursts of filtered noise tuned per surface; walking is a heel-then-toe pair,
///   running a single harder impact with a low thump.
///
/// Parameters are plain Floats written from the main thread and read on the audio thread. A torn read of an aligned
/// Float is harmless here (it can only produce a momentarily slightly wrong volume).
/// The sounds the puzzle makes. Pitches are tuned to D: tide D4, wind A4, stone D5 (a rising open fifth/octave).
enum ChimeKind: Int, Equatable {
    case tide, wind, stone, fail, ignite, rumble, lens
    /// The five glass chimes at the Glass Wood's pool: D4, F#4, A4, C5, D5. Three of them (D4, A4, D5) are the Varrow stones' tones.
    case glass0, glass1, glass2, glass3, glass4
    case glassTick       // a small bright click for turning a mirror or changing a pane
    case glassAmbient    // a quiet random shimmer, as if the wind brushed the crystal trees
}

final class AmbienceSynth {
    var windGain: Float = 0.3
    var surfGain: Float = 0.0
    var master: Float = 0.5

    /// Footstep requests: the main thread bumps `stepCounter` and sets `stepSurface`.
    var stepCounter = 0
    var stepSurface: SurfaceKind = .grass
    var stepRun = false
    var stepPan: Float = 0
    private var seenSteps = 0

    // Chimes come from the main thread through a small locked queue (try-lock on the audio side, so it never blocks).
    private let chimeLock = NSLock()
    private var pendingChimes: [ChimeKind] = []
    func play(_ kind: ChimeKind) { chimeLock.lock(); pendingChimes.append(kind); chimeLock.unlock() }

    private struct Partial { var ratio: Float; var gain: Float; var decay: Float }
    private struct ChimeVoice {
        var delay: Float          // seconds until it starts (lets a "chord" arpeggiate)
        var age: Float = 0
        var f0: Float
        var gain: Float
        var partials: [Partial]
        var pan: Float            // -1 left ... 1 right
    }
    private var chimes: [ChimeVoice] = []
    private var rumbleLeft: Float = 0
    private var rumbleLP: Float = 0
    private var rumbleBrown: Float = 0

    // The stone drone: one sustained voice per Varrow stone, tuned an octave below the stone's own tone in just intonation
    // (D3 : A3 : D4 = 1 : 3/2 : 2; the values come from ToneTable), so the puzzle's progress is audible as a chord that builds. A wrong strike detunes the
    // voices and fades them; the solved puzzle blooms a major third on top (F#4 = 5/4 over D3... a D major chord).
    static let droneHz = ToneTable.droneHz
    static let droneThirdHz = ToneTable.droneThirdHz
    private var droneTarget: [Float] = [0, 0, 0]
    private var droneGain: [Float] = [0, 0, 0]
    private var droneSour: Float = 0
    private var droneBloomLeft: Float = 0
    private var droneThirdGain: Float = 0
    private let droneLock = NSLock()
    func setDrone(_ index: Int, on: Bool) { droneLock.lock(); droneTarget[index] = on ? 1 : 0; droneLock.unlock() }
    func sourDrone() { droneLock.lock(); droneTarget = [0, 0, 0]; droneSour = 1; droneBloomLeft = 0; droneLock.unlock() }
    func bloomDrone() { droneLock.lock(); droneTarget = [1, 1, 1]; droneBloomLeft = 9; droneLock.unlock() }

    // A simple stereo feedback-delay "reverb" for the chime bus: two taps with damped feedback.
    private var revL: [Float] = []
    private var revR: [Float] = []
    private var revPos = 0
    private var revDamp: [Float] = [0, 0]

    private let sampleRate: Float
    private var time: Float = 0

    // Per-channel noise and filter state (index 0 = left, 1 = right, decorrelated for stereo width).
    private var rng: [UInt32] = [0x1234567, 0x7654321]
    private var pink = [[Float]](repeating: [0, 0, 0], count: 2)
    private var windLP: [Float] = [0, 0]
    private var brown: [Float] = [0, 0]
    private var surfLP1: [Float] = [0, 0]
    private var surfLP2: [Float] = [0, 0]
    private var surfRumble: [Float] = [0, 0]
    private var fizzA: [Float] = [0, 0]
    private var fizzB: [Float] = [0, 0]
    private var stepRng: UInt32 = 0x2468ACE

    private struct StepVoice {
        var age: Float                 // starts negative for a delayed voice (the toe after the heel)
        var attack: Float
        var decay: Float
        var gain: Float
        var cutoff: Float
        var toneHz: Float
        var toneGain: Float
        var pan: Float
        var lp: Float = 0
        var seed: UInt32
    }
    private var steps: [StepVoice] = []

    init(sampleRate: Float = 44100) {
        self.sampleRate = sampleRate
        revL = [Float](repeating: 0, count: Int(sampleRate * 0.37))
        revR = [Float](repeating: 0, count: Int(sampleRate * 0.43))
    }

    /// Inharmonic partials (ratios 2.76, 5.40, 8.93) are what make a struck bell or glass sound like metal and not a
    /// flute: a bar's overtones are not whole multiples of its fundamental. Higher partials die faster, so the
    /// tone starts bright and mellows as it rings out.
    private func bell(_ f: Float, gain: Float, decayScale: Float = 1, delay: Float = 0, pan: Float = 0) -> ChimeVoice {
        ChimeVoice(delay: delay, f0: f, gain: gain, partials: [
            Partial(ratio: 1.0, gain: 1.0, decay: 3.2 * decayScale), Partial(ratio: 2.76, gain: 0.42, decay: 2.2 * decayScale),
            Partial(ratio: 5.40, gain: 0.18, decay: 1.4 * decayScale), Partial(ratio: 8.93, gain: 0.07, decay: 0.7 * decayScale),
        ], pan: pan)
    }

    /// Glass rings higher and thinner than a bell: partial ratios 1, 2.32, 4.25, 6.63 and a shorter decay.
    private func glassVoice(_ f: Float, gain: Float, decayScale: Float = 1, delay: Float = 0, pan: Float = 0) -> ChimeVoice {
        ChimeVoice(delay: delay, f0: f, gain: gain, partials: [
            Partial(ratio: 1.0, gain: 1.0, decay: 2.6 * decayScale), Partial(ratio: 2.32, gain: 0.38, decay: 1.5 * decayScale),
            Partial(ratio: 4.25, gain: 0.16, decay: 0.8 * decayScale), Partial(ratio: 6.63, gain: 0.06, decay: 0.4 * decayScale),
        ], pan: pan)
    }

    private static let glassPitches = ToneTable.glassHz

    private func startChime(_ kind: ChimeKind) {
        switch kind {
        case .glass0, .glass1, .glass2, .glass3, .glass4:
            let i = kind.rawValue - ChimeKind.glass0.rawValue
            chimes.append(glassVoice(AmbienceSynth.glassPitches[i], gain: 0.28, pan: Float(i) * 0.3 - 0.6))
        case .glassTick: chimes.append(glassVoice(1174.66, gain: 0.12, decayScale: 0.04))
        case .glassAmbient:
            let pitches: [Float] = [587.33, 739.99, 880.0, 1174.66]
            chimes.append(glassVoice(pitches[Int(stepRandom() * 3.999)], gain: 0.05, decayScale: 2.2, pan: stepRandom() * 2 - 1))
        case .tide:  chimes.append(bell(ToneTable.stoneHz[0], gain: 0.30, pan: -0.2))
        case .wind:  chimes.append(bell(ToneTable.stoneHz[1], gain: 0.28, pan: 0.0))
        case .stone: chimes.append(bell(ToneTable.stoneHz[2], gain: 0.26, pan: 0.2))
        case .fail:  // a soft falling minor third
            chimes.append(bell(311.13, gain: 0.16, decayScale: 0.45))
            chimes.append(bell(261.63, gain: 0.14, decayScale: 0.5, delay: 0.22))
        case .ignite: // the three tones together, then a high shimmer: the lamp catching
            for (i, f) in [Float(293.66), 440.0, 587.33, 739.99, 880.0].enumerated() {
                chimes.append(bell(f, gain: 0.17, decayScale: 1.8, delay: Float(i) * 0.14, pan: Float(i % 3) * 0.4 - 0.4))
            }
        case .lens:
            for (i, f) in [Float(880.0), 1318.5, 1760.0, 2217.5].enumerated() {
                chimes.append(bell(f, gain: 0.12, decayScale: 2.2, delay: Float(i) * 0.09, pan: Float(i) * 0.3 - 0.45))
            }
        case .rumble: rumbleLeft = 5.5
        }
        if chimes.count > 14 { chimes.removeFirst(chimes.count - 14) }
    }


    @inline(__always)
    private func white(_ ch: Int) -> Float {
        // xorshift32 -> -1...1. Cheap and good enough for noise.
        var x = rng[ch]
        x ^= x << 13; x ^= x >> 17; x ^= x << 5
        rng[ch] = x
        return Float(Int32(bitPattern: x)) / Float(Int32.max)
    }

    private func stepRandom() -> Float {      // 0...1
        stepRng ^= stepRng << 13; stepRng ^= stepRng >> 17; stepRng ^= stepRng << 5
        return Float(stepRng >> 8) / Float(1 << 24)
    }

    /// A footstep. Per surface: (decay s, gain, low-pass Hz, thump Hz, thump gain). Decays are long enough (0.1-0.2 s)
    /// and the 5 ms attack soft enough that a step reads as a footfall, not a click. Walking is two hits, heel then toe
    /// 75 ms later (about 40 % as loud and brighter); running is one harder, shorter impact plus a low thump, because
    /// a runner lands on the ball of the foot with more force and spends less time in contact.
    private func startStep(_ kind: SurfaceKind, run: Bool, pan: Float) {
        let (decay, gain, cutoff, tone, toneGain): (Float, Float, Float, Float, Float)
        switch kind {
        case .grass: (decay, gain, cutoff, tone, toneGain) = (0.17, 0.22, 650, 0, 0)
        case .sand:  (decay, gain, cutoff, tone, toneGain) = (0.21, 0.20, 850, 0, 0)
        case .earth: (decay, gain, cutoff, tone, toneGain) = (0.10, 0.30, 2100, 0, 0)
        case .rock:  (decay, gain, cutoff, tone, toneGain) = (0.08, 0.34, 3400, 170, 0.18)
        case .stone: (decay, gain, cutoff, tone, toneGain) = (0.09, 0.34, 2900, 140, 0.25)
        case .wood:  (decay, gain, cutoff, tone, toneGain) = (0.15, 0.36, 1500, 215, 0.40)
        }
        let vary = 0.85 + 0.3 * stepRandom()          // no two steps identical: repetition is what sounds mechanical
        let bright = 0.9 + 0.2 * stepRandom()
        let seed = UInt32(truncatingIfNeeded: Int(stepRandom() * 1e6) &+ 1)
        if run {
            steps.append(StepVoice(age: 0, attack: 0.003, decay: decay * 0.7, gain: gain * 1.55 * vary, cutoff: cutoff * 1.5 * bright,
                                   toneHz: tone > 0 ? tone : 95, toneGain: max(toneGain, 0.30) * vary, pan: pan, seed: seed))
        } else {
            steps.append(StepVoice(age: 0, attack: 0.006, decay: decay, gain: gain * vary, cutoff: cutoff * bright,
                                   toneHz: tone, toneGain: toneGain * vary, pan: pan, seed: seed))
            steps.append(StepVoice(age: -0.075, attack: 0.008, decay: decay * 0.8, gain: gain * 0.26 * vary, cutoff: cutoff * 1.25 * bright,
                                   toneHz: 0, toneGain: 0, pan: pan, seed: seed &+ 7))
        }
        if steps.count > 8 { steps.removeFirst(steps.count - 8) }
    }

    /// Render `frames` stereo samples (one-pole filters are cheap, so this is far under the audio deadline).
    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        if stepCounter != seenSteps { seenSteps = stepCounter; startStep(stepSurface, run: stepRun, pan: stepPan) }
        if chimeLock.try() {
            let queued = pendingChimes
            pendingChimes.removeAll()
            chimeLock.unlock()
            for k in queued { startChime(k) }
        }
        let dt = 1 / sampleRate
        let wind = windGain, surf = surfGain, m = master

        for i in 0..<frames {
            let t = time
            // Gust: slow, irregular 0...1 built from three incommensurate sines.
            let gust = 0.5 + 0.5 * (0.55 * sin(t * 0.43) + 0.3 * sin(t * 0.81 + 1.3) + 0.15 * sin(t * 1.9 + 2.1))
            // Surf: three swells of different periods drift in and out of phase, so the sea never repeats audibly.
            // Each swell takes ~40 % of its period to build, then drains slowly.
            let swell: (Float, Float) -> Float = { period, phase in
                let x = t / period + phase
                let f = x - floor(x)
                return smoothstep(0, 0.42, f) * exp(-max(f - 0.42, 0) * 2.6)
            }
            var out = [Float](repeating: 0, count: 2)
            for ch in 0..<2 {
                // --- wind
                let w = white(ch)
                pink[ch][0] = 0.99765 * pink[ch][0] + w * 0.0990460        // Paul Kellet's pink-noise filter
                pink[ch][1] = 0.96300 * pink[ch][1] + w * 0.2965164
                pink[ch][2] = 0.57000 * pink[ch][2] + w * 1.0526913
                let p = (pink[ch][0] + pink[ch][1] + pink[ch][2] + w * 0.1848) * 0.11
                let cutoff = 250 + 1700 * gust * gust
                let a = 1 - exp(-2 * .pi * cutoff / sampleRate)
                windLP[ch] += a * (p - windLP[ch])
                let windOut = windLP[ch] * (0.25 + 0.75 * gust) * wind * 3.2

                // --- surf. Right channel's swells are offset in phase for width.
                let o: Float = ch == 1 ? 0.07 : 0
                let e1 = swell(7.3, 0.00 + o), e2 = swell(10.1, 0.37 + o), e3 = swell(13.7, 0.71 + o)
                let env = min(1, 0.12 + 0.55 * e1 + 0.40 * e2 + 0.30 * e3)
                func drainOf(_ period: Float, _ phase: Float, _ e: Float) -> Float {
                    let x = t / period + phase + o
                    return e * smoothstep(0.45, 0.7, x - floor(x))
                }
                let drain = 0.5 * (drainOf(7.3, 0, e1) + drainOf(10.1, 0.37, e2))
                brown[ch] = 0.997 * brown[ch] + 0.03 * white(ch)
                // Body: two cascaded one-pole low-passes (12 dB/oct). The cutoff stays under 1 kHz: real surf is a
                // low-mid wash, and the bright hiss of a high cutoff is exactly what sounds like static.
                let sc = 260 + 700 * env
                let sa = 1 - exp(-2 * .pi * sc / sampleRate)
                surfLP1[ch] += sa * (brown[ch] * 2.2 - surfLP1[ch])
                surfLP2[ch] += sa * (surfLP1[ch] - surfLP2[ch])
                // Rumble: the sub-bass of mass moving.
                surfRumble[ch] += 0.012 * (brown[ch] * 3.0 - surfRumble[ch])
                // Foam fizz: a narrow, quiet band (about 1.2-3 kHz), only while the water drains back.
                let fw = white(ch)
                fizzA[ch] += 0.35 * (fw - fizzA[ch]); fizzB[ch] += 0.15 * (fw - fizzB[ch])
                let fizz = (fizzA[ch] - fizzB[ch]) * drain * 0.10
                let body = surfLP2[ch] * (0.15 + 0.85 * env) * 2.6
                let rumble = surfRumble[ch] * env * env * 1.1
                let surfOut = (body + rumble + fizz) * surf * 0.42
                out[ch] = windOut + surfOut
            }

            // --- footsteps (panned per foot)
            var stepL: Float = 0, stepR: Float = 0
            for k in 0..<steps.count {
                var v = steps[k]
                if v.age >= 0 {
                    let env = (1 - exp(-v.age / v.attack)) * exp(-v.age / v.decay)    // soft attack, then ring out
                    if env > 0.002 {
                        v.seed ^= v.seed << 13; v.seed ^= v.seed >> 17; v.seed ^= v.seed << 5
                        let n = Float(Int32(bitPattern: v.seed)) / Float(Int32.max)
                        let a = 1 - exp(-2 * .pi * v.cutoff / sampleRate)
                        v.lp += a * (n - v.lp)
                        var smp = v.lp * v.gain
                        if v.toneHz > 0 { smp += sin(2 * .pi * v.toneHz * v.age) * v.toneGain * 0.5 }
                        smp *= env
                        stepL += smp * (0.5 - 0.5 * v.pan); stepR += smp * (0.5 + 0.5 * v.pan)
                    }
                }
                v.age += dt
                steps[k] = v
            }
            steps.removeAll { $0.age > $0.decay * 8 }
            let stepOut = (stepL + stepR) * 0.5
            // --- stone drone (mono, centred, quiet): two slightly detuned sines + a soft octave per voice
            var drone: Float = 0
            if droneGain[0] > 1e-4 || droneGain[1] > 1e-4 || droneGain[2] > 1e-4 || droneThirdGain > 1e-4 || droneTarget[0] + droneTarget[1] + droneTarget[2] > 0 {
                let bloomOn: Float = droneBloomLeft > 0 ? 1 : 0
                for v in 0..<3 {
                    let rate: Float = droneTarget[v] > droneGain[v] ? 0.00006 : 0.00012           // slow in (~0.4 s), slower out
                    droneGain[v] += (droneTarget[v] * (droneBloomLeft > 0 ? 1.5 : 1) - droneGain[v]) * (droneSour > 0 ? 0.0004 : rate)
                    if droneGain[v] > 1e-5 {
                        let f = AmbienceSynth.droneHz[v] * (1 - 0.018 * droneSour)               // sour = sliding flat
                        let ph = 2 * Float.pi * f * t
                        let s1 = sin(ph) + sin(ph * 1.0007 + 0.4) + 0.25 * sin(2 * ph)
                        drone += s1 * 0.5 * droneGain[v] * 0.12
                    }
                }
                droneThirdGain += (bloomOn - droneThirdGain) * 0.00005
                if droneThirdGain > 1e-5 { drone += sin(2 * Float.pi * AmbienceSynth.droneThirdHz * t) * droneThirdGain * 0.08 }
                if droneSour > 0 { droneSour = max(0, droneSour - dt / 1.6) }
                if droneBloomLeft > 0 {
                    droneBloomLeft -= dt
                    if droneBloomLeft <= 0 { droneLock.lock(); droneTarget = [0, 0, 0]; droneLock.unlock() }   // release after the bloom
                }
            }
            out[0] += drone; out[1] += drone

            // --- chimes (through the reverb) and the causeway rumble
            var bellL: Float = 0, bellR: Float = 0
            for k in 0..<chimes.count {
                var v = chimes[k]
                if v.delay > 0 { v.delay -= dt; chimes[k] = v; continue }
                var sum: Float = 0
                for p in v.partials {
                    let e = exp(-v.age / p.decay)
                    if e > 0.001 { sum += sin(2 * .pi * v.f0 * p.ratio * v.age) * p.gain * e }
                }
                sum *= v.gain
                bellL += sum * (0.5 - 0.5 * v.pan); bellR += sum * (0.5 + 0.5 * v.pan)
                v.age += dt
                chimes[k] = v
            }
            chimes.removeAll { $0.delay <= 0 && $0.age > $0.partials[0].decay * 3 }
            let rl = revL[revPos % revL.count], rr = revR[revPos % revR.count]
            revDamp[0] += 0.35 * (rl - revDamp[0]); revDamp[1] += 0.35 * (rr - revDamp[1])
            revL[revPos % revL.count] = bellL + revDamp[1] * 0.42      // cross-feed left/right for width
            revR[revPos % revR.count] = bellR + revDamp[0] * 0.42
            revPos += 1
            var rumble: Float = 0
            if rumbleLeft > 0 {
                rumbleBrown = 0.998 * rumbleBrown + 0.04 * white(0)
                rumbleLP += 0.012 * (rumbleBrown * 6 - rumbleLP)
                let e = min(1, (5.5 - rumbleLeft) / 0.6) * min(1, rumbleLeft / 1.2)
                rumble = rumbleLP * e * 1.6
                rumbleLeft -= dt
            }
            out[0] += bellL + rl * 0.35 + rumble
            out[1] += bellR + rr * 0.35 + rumble

            // Soft clip: tanh keeps any pile-up of sounds from ever hard-clipping the speakers.
            left[i] = tanh((out[0] + stepL * 1.4) * m)
            right[i] = tanh((out[1] + stepR * 1.4) * m)
            time += dt
        }
    }
}

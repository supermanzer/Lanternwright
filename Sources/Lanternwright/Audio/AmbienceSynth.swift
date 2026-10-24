import Foundation

/// All of Lanternwright's sound is synthesised, with no sample files. This class is plain DSP with no AVFoundation,
/// so it can be rendered offline and tested; `AudioEngine` just feeds it to the speakers.
///
/// - Wind: pink noise (equal energy per octave, like real wind) through a low-pass whose cutoff rides a slow "gust".
/// - Surf: brown noise (rumble) whose loudness and brightness swell and decay every ~8 s, like a wave arriving
///   and draining away.
/// - Footsteps: short decaying bursts of filtered noise, tuned per surface.
///
/// Parameters are plain Floats written from the main thread and read on the audio thread. A torn read of an aligned
/// Float is harmless here (it can only produce a momentarily slightly wrong volume).
/// The sounds the puzzle makes. Pitches are tuned to D: tide D4, wind A4, stone D5 (a rising open fifth/octave).
enum ChimeKind: Int, Equatable {
    case tide, wind, stone, fail, ignite, rumble, lens
}

final class AmbienceSynth {
    var windGain: Float = 0.3
    var surfGain: Float = 0.0
    var master: Float = 0.5

    /// Footstep requests: the main thread bumps `stepCounter` and sets `stepSurface`.
    var stepCounter = 0
    var stepSurface: SurfaceKind = .grass
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
    private var surfLP: [Float] = [0, 0]

    private struct StepVoice {
        var age: Float = 0
        var decay: Float
        var gain: Float
        var cutoff: Float
        var toneHz: Float
        var toneGain: Float
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

    private func startChime(_ kind: ChimeKind) {
        switch kind {
        case .tide:  chimes.append(bell(293.66, gain: 0.30, pan: -0.2))
        case .wind:  chimes.append(bell(440.00, gain: 0.28, pan: 0.0))
        case .stone: chimes.append(bell(587.33, gain: 0.26, pan: 0.2))
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

    private func startStep(_ kind: SurfaceKind) {
        let v: StepVoice
        switch kind {
        case .grass: v = StepVoice(decay: 0.09, gain: 0.30, cutoff: 700,  toneHz: 0,   toneGain: 0,    seed: 11)
        case .sand:  v = StepVoice(decay: 0.13, gain: 0.26, cutoff: 1100, toneHz: 0,   toneGain: 0,    seed: 23)
        case .earth: v = StepVoice(decay: 0.06, gain: 0.38, cutoff: 2600, toneHz: 0,   toneGain: 0,    seed: 37)
        case .rock:  v = StepVoice(decay: 0.045, gain: 0.45, cutoff: 4200, toneHz: 170, toneGain: 0.25, seed: 41)
        case .stone: v = StepVoice(decay: 0.05, gain: 0.45, cutoff: 3800, toneHz: 140, toneGain: 0.35, seed: 53)
        case .wood:  v = StepVoice(decay: 0.10, gain: 0.45, cutoff: 1800, toneHz: 215, toneGain: 0.55, seed: 67)
        }
        steps.append(v)
        if steps.count > 6 { steps.removeFirst() }
    }

    /// Render `frames` stereo samples (one-pole filters are cheap, so this is far under the audio deadline).
    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        if stepCounter != seenSteps { seenSteps = stepCounter; startStep(stepSurface) }
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
            // Surf: x walks 0...1 once per swell. Fast rise as the wave arrives, slow exponential drain.
            let swell: (Float) -> Float = { phase in
                let x = phase - floor(phase)
                return x < 0.3 ? smoothstep(0, 0.3, x) : exp(-(x - 0.3) * 3.2)
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

                // --- surf (right channel's wave is 0.45 s late)
                let env = swell(t / 8.3 + (ch == 1 ? 0.0 : 0.054))
                brown[ch] = 0.995 * brown[ch] + 0.05 * white(ch)
                let sc = 500 + 3500 * env
                let sa = 1 - exp(-2 * .pi * sc / sampleRate)
                surfLP[ch] += sa * (brown[ch] * 1.4 - surfLP[ch])
                let surfOut = surfLP[ch] * (0.08 + 0.92 * env) * surf * 1.8
                out[ch] = windOut + surfOut
            }

            // --- footsteps (mono, centred)
            var stepOut: Float = 0
            for k in 0..<steps.count {
                var v = steps[k]
                let env = exp(-v.age / v.decay)
                if env > 0.002 {
                    v.seed ^= v.seed << 13; v.seed ^= v.seed >> 17; v.seed ^= v.seed << 5
                    let n = Float(Int32(bitPattern: v.seed)) / Float(Int32.max)
                    let a = 1 - exp(-2 * .pi * v.cutoff / sampleRate)
                    v.lp += a * (n - v.lp)
                    var s = v.lp * v.gain
                    if v.toneHz > 0 { s += sin(2 * .pi * v.toneHz * v.age) * v.toneGain * 0.5 }
                    stepOut += s * env
                }
                v.age += dt
                steps[k] = v
            }
            steps.removeAll { $0.age > $0.decay * 8 }

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
            left[i] = tanh((out[0] + stepOut) * m)
            right[i] = tanh((out[1] + stepOut) * m)
            time += dt
        }
    }
}

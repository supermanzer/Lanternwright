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
    case pageAppears     // a journal page has come loose (F02 P0): three soft rising bell notes, D5 A5 D6, unlike any puzzle chime
    case doorLocked      // the lighthouse door: a latch rattles and the weight of the door thumps against its bolt
    case buoy            // the bell buoy; loudness and pan come from `buoyGain` / `buoyPan` at the moment it rings
}

final class AmbienceSynth {
    var windGain: Float = 0.3
    var surfGain: Float = 0.0
    var master: Float = 0.5

    /// Footstep requests: the main thread bumps `stepCounter` and sets `stepSurface`.
    var stepCounter = 0
    var stepSurface: SurfaceKind = .grass
    /// Weighted surface mix at the foot (when set, it replaces `stepSurface`), the dock plank index and the pebble level underfoot.
    var stepMix: StepMix?
    var stepPlank = 0
    var stepHollow: Float = 1
    /// 0...1: how deep the foot is in the water (ankle-deep and wading): adds the splash voice.
    var stepSplash: Float = 0
    var stepPebble: Float = 0
    let feet: Footsteps
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

    // The soft pad (F02 A4, see PadScore): a few sustained, slowly crossfading sines from the world's own score.
    /// 0...1: how present the pad is here (AudioSpace.padLevel), and which world's score it plays.
    var padGain: Float = 0
    var padScore: PadScore = .varrow
    /// Linear amplitude of the pad at padGain 1 (calibrated by `--selftest pad` so the plateau is AudioSpace.padPlateauDB under the wind lull).
    static let padUnit: Float = 0.00081
    private struct PadVoice { var hz: Float; var level: Float = 0; var target: Float = 1; var p1: Float = 0, p2: Float = 0, p3: Float = 0 }
    private var padVoices: [PadVoice] = []
    private var padChord = -1, padSm: Float = 0
    /// Selftests only: the pad's sounding notes and their levels.
    var padDebug: [(hz: Float, level: Float, target: Float)] { padVoices.map { ($0.hz, $0.level, $0.target) } }

    // Sonic landmarks (see SonicLandmarks): set by the main thread, smoothed here so nothing zippers.
    var humGain = SIMD4<Float>(repeating: 0)        // stones 0-2 and the lit lighthouse
    var humPan = SIMD4<Float>(repeating: 0)
    var buoyGain: Float = 0, buoyPan: Float = 0
    var galleryGain: Float = 0
    private var humSmooth = SIMD4<Float>(repeating: 0)
    private var gallerySmooth: Float = 0
    private var gallerySinePhase: Float = 0
    private var whistleRng: UInt32 = 0x2545F491      // its own noise, so adding the whistle never shifts the wind and surf noise
    private func whistleNoise() -> Float {
        whistleRng ^= whistleRng << 13; whistleRng ^= whistleRng >> 17; whistleRng ^= whistleRng << 5
        return Float(Int32(bitPattern: whistleRng)) / Float(Int32.max)
    }

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
    private var reverb: FDNReverb
    /// Set by the engine from the listener's surroundings (see AudioSpace).
    var reverbSeconds: Float = 1.6 { didSet { if abs(reverbSeconds - reverbApplied) > 0.05 { reverbApplied = reverbSeconds; reverb.setDecay(reverbSeconds) } } }
    private var reverbApplied: Float = 1.6
    var surfPan: Float = 0
    var surfOcclusion: Float = 0
    /// Distance shaping of the surf (AudioSpace.SurfField): `surfFar` 0...1 (near the shore ... far inland), `surfAirCutoff` the air-absorption low-pass.
    var surfFar: Float = 0
    var surfAirCutoff: Float = 8000
    /// The wind at the listener's feet, 0...1: `Wind.strength(at: player, time: game.time)`, pushed in every frame by the engine (F02 A3). The wind's level and its
    /// brightness are functions of this and of nothing else; a still wind is quiet and a gust is loud. Offline renders set `windSource` instead (a function of the
    /// synth's own clock), which is evaluated every 64 samples.
    var windStrength: Float = 0
    var windSource: ((Float) -> Float)?
    /// 0...1: how much leaf and grass there is underfoot; the wind rustles only where there is something to rustle.
    var vegetation: Float = 0
    /// Linear amplitude of the wind at `windStrength` 1 and `windGain` 1 relative to the unit the level targets are measured in (calibrated by `--selftest wind`).
    static let windUnit: Float = 0.5
    /// Level in dB against the surf at the waterline: a lull and a full gust (A3: the lull at most -6 dB, a gust peak at most +2 dB, so at least 12 dB between them).
    static let windLullDB: Float = -14, windGustDB: Float = -2
    private var windSm: Float = 0, windTargetSm: Float = 0
    private var windBrown = [Float](repeating: 0, count: 2), windLP1 = [Float](repeating: 0, count: 2), windLP2 = [Float](repeating: 0, count: 2)
    private var windW1 = [Float](repeating: 0, count: 2), windW2 = [Float](repeating: 0, count: 2)      // low-passed WHITE noise: the mid-range body that speakers can reproduce
    private var rustleA = [Float](repeating: 0, count: 2), rustleB = [Float](repeating: 0, count: 2)
    private var windA: Float = 0.1, windF: Float = 0.1, windAmp: Float = 0
    private var gallLow: Float = 0, gallBand: Float = 0
    private var farSmooth: Float = 0, airSmooth: Float = 8000
    private var waveNow = SurfWaves.State(), waveSm = SurfWaves.State(), swellNow: Float = 0.5
    // One gentle formant (Q about 1.2: a broad bump, never a whistle), a state-variable band-pass (low, band) per channel.
    private var howlLow = [[Float]](repeating: [0, 0], count: 2), howlBand = [[Float]](repeating: [0, 0], count: 2)
    private var panSmooth: Float = 0, occlusionSmooth: Float = 0
    private var surfMuffle: [Float] = [0, 0]
    /// How far the ambient bed is ducked right now (0 = not at all): a chime rings over the wind and surf.
    private(set) var duckAmount: Float = 0
    private var chimeFollow: Float = 0

    private let sampleRate: Float
    /// Seconds since the synth started. A DOUBLE: a Float clock stepped by 1/44100 s stops advancing at 507 s (its spacing outgrows the step), which froze the
    /// wind's gusts, the surf's waves and every drone and hum phase after about eight and a half minutes of play (F02 A1/A3).
    private var time: Double = 0
    /// Selftests only: jump the clock (so a render can start ten minutes in without rendering ten minutes first).
    func setClock(seconds: Double) { time = seconds }

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


    init(sampleRate: Float = 44100) {
        self.sampleRate = sampleRate
        reverb = FDNReverb(sampleRate: sampleRate)
        feet = Footsteps(sampleRate: sampleRate)
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
        case .pageAppears:
            for (i, f) in [Float(587.33), 880.0, 1174.66].enumerated() {
                chimes.append(bell(f, gain: 0.11, decayScale: 1.9, delay: Float(i) * 0.17, pan: 0.15 * Float(i) - 0.15))
            }
            chimes.append(ChimeVoice(delay: 0.0, f0: 3520, gain: 0.025, partials: [Partial(ratio: 1, gain: 1, decay: 0.5)], pan: 0))      // a thin paper-bright shimmer on top
        case .doorLocked:
            chimes.append(ChimeVoice(delay: 0, f0: 74, gain: 0.34, partials: [Partial(ratio: 1, gain: 1, decay: 0.16), Partial(ratio: 2.1, gain: 0.5, decay: 0.09)], pan: 0))            // the weight of the door against the bolt
            for (i, hz) in [Float(1850), 2400, 1650, 2750].enumerated() {                                                                                                    // the latch: four small iron ticks
                chimes.append(ChimeVoice(delay: 0.03 + Float(i) * 0.055 + 0.015 * Float(i % 2), f0: hz, gain: 0.07, partials: [Partial(ratio: 1, gain: 1, decay: 0.035), Partial(ratio: 3.1, gain: 0.4, decay: 0.02)], pan: 0))
            }
        case .rumble: rumbleLeft = 5.5
        case .buoy: if buoyGain > 0.004 { chimes.append(bell(ToneTable.buoyHz, gain: 0.5 * buoyGain, decayScale: 1.6, pan: buoyPan)) }
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

    /// Render `frames` stereo samples (one-pole filters are cheap, so this is far under the audio deadline).
    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        if stepCounter != seenSteps { seenSteps = stepCounter; feet.start(mix: stepMix ?? FootstepRecipe.pure(FootstepRecipe.material(for: stepSurface)), run: stepRun, pan: stepPan, plank: stepPlank, pebble: stepPebble, hollow: stepHollow, splash: stepSplash) }
        if chimeLock.try() {
            let queued = pendingChimes
            pendingChimes.removeAll()
            chimeLock.unlock()
            for k in queued { startChime(k) }
        }
        let dt = 1 / sampleRate
        let wind = windGain, surf = surfGain, m = master
        let panTarget = surfPan, occTarget = surfOcclusion

        for i in 0..<frames {
            let td = time, t = Float(td)                    // `t` for the slow functions (gusts, waves); `td` for anything that is an audio-rate phase
            panSmooth += (panTarget - panSmooth) * 0.0004
            occlusionSmooth += (occTarget - occlusionSmooth) * 0.0004
            farSmooth += (surfFar - farSmooth) * 0.0003; airSmooth += (surfAirCutoff - airSmooth) * 0.0003
            // Wind (F02 A3): the level and brightness follow the shared wind strength at the listener (smoothed over about 40 ms).
            if let src = windSource { if i & 63 == 0 { windTargetSm = src(t) } } else { windTargetSm = windStrength }
            windSm += (windTargetSm - windSm) * 0.0006
            let ws = min(max(windSm, 0), 1)
            if i & 15 == 0 {
                windA = 1 - exp(-2 * .pi * (200 + 700 * ws) / sampleRate)                     // the body's corner rides the gust: 200 Hz in a lull, 900 Hz in a gust
                windF = 2 * sin(.pi * (280 + 420 * ws) / sampleRate)
                windAmp = windGain * AmbienceSynth.windUnit * pow(10, (AmbienceSynth.windLullDB + (AmbienceSynth.windGustDB - AmbienceSynth.windLullDB) * pow(ws, 0.9)) / 20)
            }
            // Surf (F02 A1): discrete waves from SurfWaves (a swash, a crest, a drain, a quiet gap), evaluated every 32 samples and smoothed. Far inland the waves
            // give way to a slow smooth swell (lower level and darker, by the level law and the air-absorption cutoff, not by adding sub-bass).
            if i & 31 == 0 { waveNow = SurfWaves.state(time: t); swellNow = SurfWaves.farSwell(time: t) }
            waveSm.body += (waveNow.body - waveSm.body) * 0.02; waveSm.hiss += (waveNow.hiss - waveSm.hiss) * 0.02
            waveSm.cutoff += (waveNow.cutoff - waveSm.cutoff) * 0.02; waveSm.sweep += (waveNow.sweep - waveSm.sweep) * 0.01
            let far = farSmooth
            let env = max(0.04, (1 - far) * min(waveSm.body, 1) + far * (0.12 + 0.88 * swellNow))
            let sweepPan = 0.35 * waveSm.sweep * (1 - far)                  // each wave travels along the shore
            var out = [Float](repeating: 0, count: 2)
            for ch in 0..<2 {
                // --- wind: brown noise (about -12 dB/octave, with a 40 Hz floor), low-passed at a corner that rides the gust, one broad formant that only a strong gust
                // opens (Q 1.2), and a faint high rustle where there is grass or leaf. No narrow resonance anywhere: a high-Q band-pass is a boiling kettle.
                let w = white(ch)
                windBrown[ch] = 0.990 * windBrown[ch] + 0.06 * w
                windLP1[ch] += windA * (windBrown[ch] - windLP1[ch]); windLP2[ch] += windA * (windLP1[ch] - windLP2[ch])
                windW1[ch] += windA * (w - windW1[ch]); windW2[ch] += windA * (windW1[ch] - windW2[ch])
                howlLow[ch][0] += windF * howlBand[ch][0]; let hi1 = w * 0.4 - howlLow[ch][0] - howlBand[ch][0] / 1.2; howlBand[ch][0] += windF * hi1
                let wr = white(ch)                                                            // its own noise: independent of the body
                rustleA[ch] += 0.35 * (wr - rustleA[ch]); rustleB[ch] += 0.15 * (wr - rustleB[ch])
                let rustle = (rustleA[ch] - rustleB[ch]) * ws * ws * vegetation * 2.4
                let windOut = ((windLP2[ch] * 1.1 + windW2[ch] * 1.4) + howlBand[ch][0] * ws * ws * 0.5 + rustle) * windAmp

                // --- surf. The two channels have independent noise, so the wash has width.
                brown[ch] = 0.997 * brown[ch] + 0.03 * white(ch)
                // Body: two cascaded one-pole low-passes (12 dB/oct). The cutoff stays under 1 kHz: real surf is a low-mid wash, and the bright hiss of a high
                // cutoff is exactly what sounds like static. As a wave drains back its low-pass falls (waveSm.cutoff).
                let sc = (260 + 700 * env) * (0.4 + 0.6 * waveSm.cutoff)
                let sa = 1 - exp(-2 * .pi * sc / sampleRate)
                surfLP1[ch] += sa * (brown[ch] * 2.2 - surfLP1[ch])
                surfLP2[ch] += sa * (surfLP1[ch] - surfLP2[ch])
                // Rumble: the sub-bass of mass moving (not raised with distance: far away the sea is quieter, never boomier).
                surfRumble[ch] += 0.012 * (brown[ch] * 3.0 - surfRumble[ch])
                // Foam fizz: a narrow, quiet band (about 1.2-3 kHz), only at the crest of each wave.
                let fw = white(ch)
                fizzA[ch] += 0.35 * (fw - fizzA[ch]); fizzB[ch] += 0.15 * (fw - fizzB[ch])
                let fizz = (fizzA[ch] - fizzB[ch]) * waveSm.hiss * 0.14 * (1 - far)
                let body = surfLP2[ch] * (0.15 + 0.85 * env) * 2.6
                let rumble = surfRumble[ch] * env * env * 1.1
                var surfOut = (body + rumble + fizz) * surf * 0.42
                // A hill between you and the sea muffles the surf (one-pole low-pass, 8 kHz open down to ~400 Hz behind a ridge) and
                // thins it; the surf is placed left or right toward the nearest shore.
                let muffleCut = min(8000 - 7750 * occlusionSmooth, airSmooth)           // a hill and the distance (air absorption) both darken the surf
                surfMuffle[ch] += (1 - exp(-2 * .pi * muffleCut / sampleRate)) * (surfOut - surfMuffle[ch])
                surfOut = surfMuffle[ch] * (1 - 0.4 * occlusionSmooth) * (1 + (ch == 0 ? -0.55 : 0.55) * max(-1, min(1, panSmooth + sweepPan)))
                out[ch] = windOut + surfOut
            }

            // --- the pad: sustained notes from this world's score, each crossfading in and out over several seconds (a note that stays in the next chord just stays)
            if i & 2047 == 0 {
                let c = padScore.chord(at: td)
                if c.number != padChord {
                    padChord = c.number
                    for k in 0..<padVoices.count { padVoices[k].target = c.notes.contains { abs($0 - padVoices[k].hz) < 0.01 } ? 1 : 0 }
                    for n in c.notes where !padVoices.contains(where: { abs($0.hz - n) < 0.01 && $0.target > 0 }) { padVoices.append(PadVoice(hz: n, level: 0, target: 1)) }
                }
            }
            padSm += (padGain - padSm) * 0.00005
            var pad: Float = 0
            if padSm > 1e-5 || !padVoices.isEmpty {
                let tau = 1 / (4.0 * sampleRate)                                                  // about a 4 s time constant: long attacks and releases
                for k in 0..<padVoices.count {
                    padVoices[k].level += (padVoices[k].target - padVoices[k].level) * tau
                    let v = padVoices[k]
                    if v.level < 1e-4 { continue }
                    let w = 2 * Float.pi * v.hz / sampleRate
                    padVoices[k].p1 += w; padVoices[k].p2 += w * 1.0017; padVoices[k].p3 += w * 0.9980        // a slow chorus: +3 and -3 cents
                    if padVoices[k].p1 > 2 * .pi { padVoices[k].p1 -= 2 * .pi }
                    if padVoices[k].p2 > 2 * .pi { padVoices[k].p2 -= 2 * .pi }
                    if padVoices[k].p3 > 2 * .pi { padVoices[k].p3 -= 2 * .pi }
                    let breathe = 0.85 + 0.15 * sin(t * (0.09 + 0.013 * Float(k)) + Float(k))
                    pad += (sin(padVoices[k].p1) + 0.8 * sin(padVoices[k].p2) + 0.8 * sin(padVoices[k].p3) + 0.12 * sin(2 * padVoices[k].p1)) * v.level * breathe
                }
                padVoices.removeAll { $0.target == 0 && $0.level < 1e-4 }
                pad *= padSm * AmbienceSynth.padUnit
            }
            out[0] += pad; out[1] += pad

            // --- footsteps: impact + body + grains per surface (see Footsteps.swift)
            let (stepL, stepR) = feet.render(dt: dt)
            // --- stone drone (mono, centred, quiet): two slightly detuned sines + a soft octave per voice
            var drone: Float = 0
            if droneGain[0] > 1e-4 || droneGain[1] > 1e-4 || droneGain[2] > 1e-4 || droneThirdGain > 1e-4 || droneTarget[0] + droneTarget[1] + droneTarget[2] > 0 {
                let bloomOn: Float = droneBloomLeft > 0 ? 1 : 0
                for v in 0..<3 {
                    let rate: Float = droneTarget[v] > droneGain[v] ? 0.00006 : 0.00012           // slow in (~0.4 s), slower out
                    droneGain[v] += (droneTarget[v] * (droneBloomLeft > 0 ? 1.5 : 1) - droneGain[v]) * (droneSour > 0 ? 0.0004 : rate)
                    if droneGain[v] > 1e-5 {
                        let f = AmbienceSynth.droneHz[v] * (1 - 0.018 * droneSour)               // sour = sliding flat
                        let ph = 2 * Double.pi * Double(f) * td
                        let s1 = Float(sin(ph) + sin(ph * 1.0007 + 0.4) + 0.25 * sin(2 * ph))
                        drone += s1 * 0.5 * droneGain[v] * 0.12
                    }
                }
                droneThirdGain += (bloomOn - droneThirdGain) * 0.00005
                if droneThirdGain > 1e-5 { drone += Float(sin(2 * Double.pi * Double(AmbienceSynth.droneThirdHz) * td)) * droneThirdGain * 0.08 }
                if droneSour > 0 { droneSour = max(0, droneSour - dt / 1.6) }
                if droneBloomLeft > 0 {
                    droneBloomLeft -= dt
                    if droneBloomLeft <= 0 { droneLock.lock(); droneTarget = [0, 0, 0]; droneLock.unlock() }   // release after the bloom
                }
            }
            out[0] += drone; out[1] += drone

            // --- sonic landmarks: stone hums, the lit lighthouse's tone, wind singing round the gallery (all quiet, all located)
            humSmooth += (humGain - humSmooth) * 0.0006
            gallerySmooth += (galleryGain - gallerySmooth) * 0.0006
            var lmL: Float = 0, lmR: Float = 0
            if humSmooth.max() > 1e-4 || gallerySmooth > 1e-4 {
                for v in 0..<3 where humSmooth[v] > 1e-4 {
                    let f = ToneTable.stoneHz[v] * 0.5
                    let trem = 0.75 + 0.25 * sin(t * (0.21 + 0.05 * Float(v)) + Float(v))
                    let s = Float(sin(2 * Double.pi * Double(f) * td) + 0.35 * sin(2 * Double.pi * Double(f) * 2.003 * td + 1)) * humSmooth[v] * trem * 0.022
                    let pn = humPan[v]; lmL += s * (1 - pn) * 0.5 * 1.4; lmR += s * (1 + pn) * 0.5 * 1.4
                }
                if humSmooth.w > 1e-4 {         // the lit lighthouse: a slow open fifth, D3 + A3, with a gentle vibrato
                    let vib = 1 + 0.002 * sin(t * 0.7)
                    let s = Float(sin(2 * Double.pi * Double(ToneTable.stoneHz[0] * 0.5 * vib) * td) + 0.7 * sin(2 * Double.pi * Double(ToneTable.stoneHz[1] * 0.5 * vib) * td + 0.5)) * humSmooth.w * 0.028
                    let pn = humPan.w; lmL += s * (1 - pn) * 0.5 * 1.4; lmR += s * (1 + pn) * 0.5 * 1.4
                }
                if gallerySmooth > 1e-4 {       // wind round the gallery: a soft, broad band of noise (Q 1.5) whose centre rides the gust, never a pure tone
                    let f = 2 * sin(.pi * (520 + 260 * ws) / sampleRate)
                    gallLow += f * gallBand; let hi = whistleNoise() * 0.5 - gallLow - gallBand / 1.5; gallBand += f * hi
                    let s = gallBand * gallerySmooth * ws * ws * windGain * 0.12
                    lmL += s * 0.7; lmR += s * 0.7
                }
            }
            out[0] += lmL; out[1] += lmR

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
            let (rl, rr) = reverb.process(left: bellL + feet.sendL * 1.4, right: bellR + feet.sendR * 1.4)
            // Ducking: while a chime rings, the wind and surf (and the drone, hums) make way for it by up to 35 %.
            let level = max(abs(bellL), abs(bellR))
            chimeFollow += (level > chimeFollow ? 0.01 : 0.00006) * (level - chimeFollow)       // fast attack, ~0.4 s release
            duckAmount = 0.35 * min(chimeFollow * 14, 1)
            var rumble: Float = 0
            if rumbleLeft > 0 {
                rumbleBrown = 0.998 * rumbleBrown + 0.04 * white(0)
                rumbleLP += 0.012 * (rumbleBrown * 6 - rumbleLP)
                let e = min(1, (5.5 - rumbleLeft) / 0.6) * min(1, rumbleLeft / 1.2)
                rumble = rumbleLP * e * 1.6
                rumbleLeft -= dt
            }
            out[0] = out[0] * (1 - duckAmount) + bellL + rl * 0.4 + rumble
            out[1] = out[1] * (1 - duckAmount) + bellR + rr * 0.4 + rumble

            // Soft clip: tanh keeps any pile-up of sounds from ever hard-clipping the speakers.
            left[i] = tanh((out[0] + stepL * 1.4) * m)
            right[i] = tanh((out[1] + stepR * 1.4) * m)
            time += 1.0 / Double(sampleRate)
        }
    }
}

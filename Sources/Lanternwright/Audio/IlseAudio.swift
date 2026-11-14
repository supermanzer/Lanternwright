import Foundation

/// S05.1 (builder A): the sound of Ilse's site, the pitches and the shapes, as pure functions so builder B's logic and the selftests read the same numbers the synth plays. Laptop speakers do not
/// reproduce bass (the F09 wind lesson): every voice here has its energy in 300-1200 Hz, and the one pitch that sits just under (the stones' D4, 293.7 Hz) carries its 2nd and 3rd harmonics.
/// Nothing here has been HEARD: it is judged by numbers (`SelfTestIlseSite`).
///
/// The two things B plays:
///   - a BELL strike: `ArchiveAudio.handle(.bell(k, sour: Bool))`. Bell k is the Glass Wood pillar k's pitch (`ToneTable.glassHz[k]`, so bays 0, 2 and 4 ring the stones' own tones: that is how "the stones'
///     tones identify the bells" works), a struck-bell spectrum (hum, prime, tierce, nominal) that dies in about 2 s. SOUR is the same bell cracked: 45 cents flat, stretched partials, a detuned twin
///     beating at 5.5 Hz, and gone in half the time.
///   - the PIPE: `ArchiveAudio.Inputs.pipe = .init(hz:, gain:)` while the fork is held at a pipe (hz from `IlseTones.pipeHz`, gain from `IlseTones.pipeGain(distance:)`). The pipe sounds as a plain pipe's
///     tone beside the fork's held tone (`.fork(k, on:)`), and the BEATS are the two meeting in the air: |pipe - fork| per second, slowing to nothing as the water reaches the gate's level.
enum IlseTones {
    static func bellHz(_ k: Int) -> Float { ToneTable.glassHz[min(max(k, 0), ToneTable.glassHz.count - 1)] }
    /// A struck bell's partials (ratio to the prime), their strengths and decay times (s). Sour: stretched, with a twin beating against the prime.
    static let bellRatios: [Float] = [1, 2, 2.4, 3], bellAmps: [Float] = [1, 0.6, 0.32, 0.18], bellDecays: [Float] = [1.5, 1.0, 0.7, 0.5]
    static let sourRatios: [Float] = [1, 2.07, 2.52, 3.31], sourAmps: [Float] = [1, 0.7, 0.5, 0.3], sourDecayScale: Float = 0.5
    static let sourCents: Float = -45, sourTwinHz: Float = 5.5
    static let bellGain: Float = 0.09

    /// The pipe's tone at water level `level` (0...1): pipe k is tuned so it matches the fork (the stones' tone k) when the water stands in the middle of gate k's window (`Tide.windows`); a rising
    /// level shortens the air column and raises the pitch, `octavesPerLevel` of an octave for the whole range.
    static let octavesPerLevel: Float = 0.5
    static func matchLevel(_ k: Int) -> Float { let w = Tide.windows[min(max(k, 0), 2)]; return (w.lowerBound + w.upperBound) / 2 }
    static func pipeHz(_ k: Int, level: Float) -> Float { ToneTable.stoneHz[min(max(k, 0), 2)] * pow(2, (min(max(level, 0), 1) - matchLevel(k)) * octavesPerLevel) }
    /// How near two tones are to agreeing, 0...1: 1 inside `agreeHz`, falling to 0 at `agreeHz + spanHz` apart. B feeds it to `BellPipes.set(... agree:)`.
    static let agreeHz: Float = 1.0, spanHz: Float = 7.0
    static func agreement(pipeHz: Float, forkHz: Float) -> Float { max(0, 1 - max(0, abs(pipeHz - forkHz) - agreeHz) / spanHz) }
    /// How loud the pipe is at `distance` m from the held fork to the pipe: full inside 1.5 m, gone by 5 m.
    static func pipeGain(distance d: Float) -> Float { let t = min(max((5 - d) / 3.5, 0), 1); return t * t * (3 - 2 * t) }
    static let pipeGainScale: Float = 0.1
}

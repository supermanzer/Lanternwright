import Foundation

/// The soft pad that grows inland (F02 A4, user note #22: "a slow melodic droning, very soft, as we leave the shore"). Not a tune: a few sustained notes whose
/// voicing changes every 25 to 50 s, so that one slow phrase of three to five notes (the top voice) takes about two minutes. Every pitch comes from `ToneTable`
/// (or an octave or a fifth of one), and each world has its own score (the user's decision): the home island sits in the stones' own D, the Glass Wood in the
/// glass pillars' key. A future Refraction adds a score here and nothing else.
struct PadScore {
    let name: String
    let chords: [[Float]]                    // Hz, lowest first
    static let chordSeconds: ClosedRange<Float> = 25...50

    /// The home island: the stones' D (tide D4, wind A4, stone D5, their drone an octave below, the just third F#4 over D4). The top voice walks D4, F#4, A4, F#4.
    static let varrow = PadScore(name: "varrow", chords: [
        [ToneTable.droneHz[0], ToneTable.droneHz[1], ToneTable.stoneHz[0]],                 // D3 A3 D4: an open fifth
        [ToneTable.droneHz[0], ToneTable.droneHz[1], ToneTable.droneThirdHz],               // D3 A3 F#4: the third arrives
        [ToneTable.droneHz[0], ToneTable.stoneHz[0], ToneTable.stoneHz[1]],                 // D3 D4 A4
        [ToneTable.droneHz[0], ToneTable.droneHz[1], ToneTable.droneThirdHz],               // back to the third
    ])
    /// The Glass Wood: the five glass pillars D4 F#4 A4 C5 D5 (equal-tempered F#, and a C that makes the chord glassy and unresolved). The top voice walks F#4, A4, C5, A4.
    static let glassWood = PadScore(name: "glassWood", chords: [
        [ToneTable.glassHz[0] / 2, ToneTable.glassHz[2] / 2, ToneTable.glassHz[1]],        // D3 A3 F#4
        [ToneTable.glassHz[0] / 2, ToneTable.glassHz[1], ToneTable.glassHz[2]],            // D3 F#4 A4
        [ToneTable.glassHz[0] / 2, ToneTable.glassHz[2], ToneTable.glassHz[3]],            // D3 A4 C5
        [ToneTable.glassHz[2] / 2, ToneTable.glassHz[1], ToneTable.glassHz[2]],            // A3 F#4 A4
    ])
    /// The Tide Archive's slow chords (S04.1 placeholder until S04.4's own drone): the stones' tones an octave down, so it is the island's voice in a low register.
    static let tideArchive = PadScore(name: "tideArchive", chords: [
        [ToneTable.stoneHz[0] / 2, ToneTable.stoneHz[1] / 2, ToneTable.stoneHz[2] / 2],    // D3 A3 D4
        [ToneTable.stoneHz[0] / 2, ToneTable.stoneHz[2] / 2, ToneTable.stoneHz[1]],        // D3 D4 A4
    ])
    static func score(for world: WorldKind) -> PadScore {
        switch world { case .varrow: return .varrow; case .glassWood: return .glassWood; case .tideArchive: return .tideArchive }
    }

    @inline(__always) private static func h(_ n: Int) -> Float {
        var x = UInt32(truncatingIfNeeded: n) &* 0x9E3779B1 &+ 0x7F4A7C15
        x ^= x >> 15; x = x &* 0x2C1B3C6D; x ^= x >> 12; x = x &* 0x297A2D39; x ^= x >> 15
        return Float(x >> 8) / Float(1 << 24)
    }
    /// How long chord number `n` (counting from the start, round and round the score) lasts: 25 to 50 s, from a fixed hash.
    func duration(of n: Int) -> Float { PadScore.chordSeconds.lowerBound + (PadScore.chordSeconds.upperBound - PadScore.chordSeconds.lowerBound) * PadScore.h(n) }
    /// The number (counting from the start of play) of the chord sounding at `time`, and the notes of it.
    func chord(at time: Double) -> (number: Int, notes: [Float]) {
        var t = time, n = 0
        while true {
            let d = Double(duration(of: n))
            if t < d { return (n, chords[n % chords.count]) }
            t -= d; n += 1
            if n > 200_000 { return (n, chords[n % chords.count]) }
        }
    }
    /// Mean chord length and the time one trip round the score takes (about two minutes).
    var phraseSeconds: Float { (0..<chords.count).reduce(0) { $0 + duration(of: $1) } }
}

extension ToneTable {
    /// Is `hz` one of the game's tones, or an octave or a fifth of one (within 5 cents)? Every pitch the pad plays must be.
    static func isFamilyTone(_ hz: Float) -> Bool {
        let tones = stoneHz + glassHz + droneHz + [droneThirdHz, buoyHz]
        for t in tones { for m: Float in [0.25, 0.5, 1, 2, 4, 1.5, 3, 0.75, 1 / 1.5] where abs(1200 * log2(hz / (t * m))) <= 5 { return true } }
        return false
    }
}

extension AudioSpace {
    /// The pad's presence against the distance to the nearest water: silent within 25 m of the shore, fading in over the next 60 m, then steady.
    static func padLevel(shoreDistance d: Float) -> Float { smoothstep(25, 85, d) }
    /// The pad's plateau in dB against the wind lull. The plan asked for -34 dB ("noticed only when it stops"); with the wind at its lull masking a tone that far down
    /// the pad would be inaudible, so the plateau is -24 dB: still far under the lull, a single constant to turn (INSPECT.md).
    static let padPlateauDB: Float = -24
}

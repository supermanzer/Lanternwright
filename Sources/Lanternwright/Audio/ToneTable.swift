/// The one place the game's pitches live. Varrow's three stones, the Glass Wood's five pillars and the stone drone all
/// read from here, so "the chimes at the pool are the stones' tones" is a fact of the code, not a coincidence (and a
/// selftest fails if it ever stops being true).
enum ToneTable {
    /// Tide, wind, stone: D4, A4, D5, indexed by `StoneID.rawValue`.
    static let stoneHz: [Float] = [293.66, 440.00, 587.33]
    /// The five Glass Wood pillars, low to high: D4, F#4, A4, C5, D5. Pillars 0, 2, 4 are the stones' tones.
    static let glassHz: [Float] = [293.66, 369.99, 440.00, 523.25, 587.33]
    /// The bell buoy's note: G4, the fourth above the stones' D, so it sounds like a different, further thing.
    static let buoyHz: Float = 392.00
    /// S03.4: the lamp's answer, four notes made only of the stones' tones (so it is the island's own voice): A4, D5, A4, then home to D4, struck at `answerDelays` seconds.
    static let answerHz: [Float] = [stoneHz[1], stoneHz[2], stoneHz[1], stoneHz[0]]
    static let answerDelays: [Float] = [0, 0.55, 1.1, 1.9]
    /// The stone drone sits an octave below the stones' own tones.
    static let droneHz: [Float] = stoneHz.map { $0 / 2 }
    /// F#4 (5/4 over D4... in just intonation over D4 = 367.08) is the third that blooms on the solved chord.
    static let droneThirdHz: Float = 367.08
}

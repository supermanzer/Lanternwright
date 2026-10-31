import Foundation

/// S04.2 / S04.6: the Tide Archive's tide, a pure function of the game clock (about 90 s for a full rise and fall, deterministic, so frames, saves and tests agree). 0 is low water, 1 high.
/// The water in the galleries (builder A's `ti_gallery_water`, the shore physics) reads `Tide.level(clock)`; the sluice puzzle reads the same function, so what the player sees is what the gate hears.
enum Tide {
    static let period: Float = 90
    /// Low water at clock 0, high at half a period.
    static func level(_ t: Float) -> Float { 0.5 - 0.5 * cos(2 * .pi * t / period) }

    /// How fast the level is changing now, per second (positive: rising): the derivative of `level`. The sound of the water follows it.
    static func rate(_ t: Float) -> Float { .pi / period * sin(2 * .pi * t / period) }

    /// The water levels at which each sluice (tide, wind, stone) answers: tide at low water, wind at mid water, stone at high water. They overlap a little so a patient player is never shut out
    /// between two of them. In one rise (low to high, 45 s) the three come in the order the stones are struck in: that is the cue, written into the water, not in a page.
    static let windows: [ClosedRange<Float>] = [0.0...0.4, 0.35...0.65, 0.6...1.0]
    static func inWindow(_ sluice: Int, level: Float) -> Bool { windows.indices.contains(sluice) && windows[sluice].contains(level) }
    /// Seconds from `t` until the sluice's window next opens (0 if it is open now): for tests and tools.
    static func wait(for sluice: Int, from t: Float) -> Float {
        var d: Float = 0
        while d < period && !inWindow(sluice, level: level(t + d)) { d += 0.25 }
        return d
    }
}

import Foundation

/// S04.2 / S04.6: the Tide Archive's tide, a pure function of the game clock (about 90 s for a full rise and fall, deterministic, so frames, saves and tests agree). 0 is low water, 1 high.
/// The water in the galleries (builder A's `ti_gallery_water`, the shore physics) reads `Tide.level(clock)`; the sluice puzzle reads the same function, so what the player sees is what the gate hears.
enum Tide {
    static let period: Float = 90
    /// Low water at clock 0, high at half a period.
    static func level(_ t: Float) -> Float { 0.5 - 0.5 * cos(2 * .pi * t / period) }

    /// How fast the level is changing now, per second (positive: rising): the derivative of `level`. The sound of the water follows it.
    static func rate(_ t: Float) -> Float { .pi / period * sin(2 * .pi * t / period) }

    /// The water levels at which each sluice (tide, wind, stone) answers (S04 wiring, Q33): a gate is in a sunken sluice room (`ArchiveLayout.sluiceFloors`: 0.8, -0.2, -0.9 m) that can only be
    /// WADED when the water over its floor is under knee depth, and the gate hears the player only while the room is wadeable or at most 0.2 m dry: the room's depth between -0.2 m and `Tide.wadeDepth`.
    /// So the stone room (the lowest) answers only near low water, the wind room at mid water, the tide room (the highest) up to high water. They fall in the stones' order on a FALLING tide
    /// (tide, wind, stone), which is the cue written in the water; on a rising one they come the other way round.
    static func window(forFloor floor: Float) -> ClosedRange<Float> {
        let range = highSea - lowSea
        return max(0, (floor - 0.2 - lowSea) / range)...min(1, (floor + wadeDepth - lowSea) / range)
    }
    static let windows: [ClosedRange<Float>] = ArchiveLayout.sluiceFloors.map(window(forFloor:))
    static func inWindow(_ sluice: Int, level: Float) -> Bool { windows.indices.contains(sluice) && windows[sluice].contains(level) }
    /// Seconds from `t` until the sluice's window next opens (0 if it is open now): for tests and tools.
    static func wait(for sluice: Int, from t: Float) -> Float {
        var d: Float = 0
        while d < period && !inWindow(sluice, level: level(t + d)) { d += 0.25 }
        return d
    }
}

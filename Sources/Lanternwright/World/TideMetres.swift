import Foundation

/// S04.2 (builder A): the tide in METRES, on top of builder B's `Tide` (Game/Tide.swift: the same function of the game clock, normalised 0 = low water ... 1 = high, `rate`, the sluices' `windows`). The sea in the Tide Archive
/// stands at `Tide.metres(clock)` above the ground datum, from `lowSea` (-1.0 m, low at t = 0) to `highSea` (+1.4 m, high at half a period). The water pass lifts the ocean plane to it (`Renderer.tideLevel`), the shore physics
/// read the ground RELATIVE to it, the player wades relative to it (`Player.sea`), and the game asks `depth` / `isWadeable` where it must know whether a place can be reached now.
extension Tide {
    static let lowSea: Float = -1.0, highSea: Float = 1.4
    static func metres(_ t: Float) -> Float { lowSea + (highSea - lowSea) * level(t) }
    /// How deep water over a place may be (m) for the player to wade it: knee deep. Deeper and it cannot be reached.
    static var wadeDepth: Float { -Player.minGround }          // the same rule the movement uses (`Player.sea`)
    /// The lowest the sea ever stands in `kind` (the Archive's low tide; 0 elsewhere): a place is reachable at SOME time when its ground is above this less the wading depth.
    static func lowestSea(for kind: WorldKind) -> Float { kind == .tideArchive ? lowSea : 0 }
    /// Water over ground at height `ground` (m) at time `t`: 0 when dry.
    static func depth(ground: Float, time t: Float) -> Float { max(metres(t) - ground, 0) }
    static func isWadeable(ground: Float, time t: Float) -> Bool { depth(ground: ground, time: t) <= wadeDepth }
    /// The share of the tide cycle in which a place whose floor is at `ground` can be waded (numerically, 0...1).
    static func wadeableShare(ground: Float) -> Float {
        let n = 900
        return Float((0..<n).filter { isWadeable(ground: ground, time: Float($0) / Float(n) * period) }.count) / Float(n)
    }
    /// The next time at or after `t` that a place at `ground` becomes wadeable (0 if it is now), searched over two periods in 0.5 s steps; nil if it never is.
    static func nextWadeable(ground: Float, after t: Float) -> Float? {
        for k in 0...Int(period * 2) { let s = t + Float(k) * 0.5; if isWadeable(ground: ground, time: s) { return s - t } }
        return nil
    }
}

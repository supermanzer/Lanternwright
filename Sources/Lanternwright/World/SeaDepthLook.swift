import simd

/// F10.1: the CPU mirror of the sea's depth look in `Render/Shaders/Water.swift` (`colDepth`, `dk`, `absorb`, `transmit`, `deep`). The selftest pins the look here; the shader uses the same
/// numbers, so a change to one must change the other. Depth is the vertical water column (sea level minus seabed height) under the pixel.
enum SeaDepthLook {
    static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }
    /// 0 on the shelf (column <= 0.3 m) to 1 in the channel (>= 2.2 m).
    static func depthMix(_ column: Float) -> Float { smooth(0.3, 2.2, max(column, 0)) }
    static func absorb(column: Float) -> SIMD3<Float> {
        let k = depthMix(column); return SIMD3(0.45, 0.09, 0.06) * (1 - k) + SIMD3(1.05, 0.36, 0.27) * k
    }
    /// The fraction of the seabed's light that survives a view path of `path` metres through a column of `column` metres.
    static func transmit(path: Float, column: Float) -> SIMD3<Float> {
        let a = absorb(column: column), hide = 1 - smooth(1.4, 2.6, max(column, 0))
        return SIMD3(exp(-path * a.x), exp(-path * a.y), exp(-path * a.z)) * hide
    }
    /// The light scattered back up out of the water, before the sky-light factor.
    static func scatter(column: Float) -> SIMD3<Float> {
        let k = depthMix(column); return SIMD3(0.02, 0.10, 0.12) * (1 - k) + SIMD3(0.004, 0.028, 0.042) * k
    }
    /// Luminance of what the water shows for a seabed of luminance `bed` looked at straight down (path = column) under sky-light `light`.
    static func lumaStraightDown(column: Float, bed: Float, light: Float) -> Float {
        let t = transmit(path: column, column: column), s = scatter(column: column) * light * 1.5
        let c = SIMD3(bed, bed, bed) * t + s * (SIMD3<Float>(repeating: 1) - t)
        return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
    }
}

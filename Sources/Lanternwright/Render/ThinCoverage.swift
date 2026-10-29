import simd

/// The CPU mirror of the shared MSL minimum-footprint rule in `Shaders/Common.swift` (`pixel_world_size`, `thin_coverage`; G10.2.2). The selftest pins the rule here; the shader
/// uses the same two formulas, so a change to one must change the other. Builder B reuses the MSL helper for the grass (G10.G.2).
enum ThinCoverage {
    /// Metres covered by one pixel at `worldPos`: 2 * view depth / (projection scale * render height).
    static func pixelWorldSize(viewProj m: float4x4, worldPos p: SIMD3<Float>, screenHeight: Float) -> Float {
        let viewDepth = m[0][3] * p.x + m[1][3] * p.y + m[2][3] * p.z + m[3][3]
        let scaleY = simd_length(SIMD3(m[0][1], m[1][1], m[2][1]))
        return 2 * max(viewDepth, 0) / max(scaleY * screenHeight, 1e-4)
    }
    /// The width to draw (never below `footprint * minPixels`) and the coverage (the true width over the drawn width, 0...1).
    static func thinCoverage(worldWidth: Float, footprint: Float, minPixels: Float = 1) -> (width: Float, coverage: Float) {
        let w = max(worldWidth, footprint * minPixels)
        return (w, worldWidth / max(w, 1e-6))
    }
}

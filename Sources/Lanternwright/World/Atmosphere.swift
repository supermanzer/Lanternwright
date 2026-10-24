import Foundation
import simd

/// CPU mirror of the atmosphere constants in Render/Shaders/Sky.swift (keep them in sync).
/// Used for quantities that are constant per frame, so the shaders don't integrate them per pixel.
enum Atmosphere {
    static let earthRadius = 6360e3
    static let atmosphereRadius = 6420e3
    static let betaR = SIMD3<Double>(5.8e-6, 13.5e-6, 33.1e-6)
    static let betaM = 21e-6
    static let heightR = 7994.0
    static let heightM = 1200.0
    static let viewerHeight = 10.0                // matches LUT_CAM_HEIGHT
    /// Sun irradiance constant shared with the shaders (FrameUniforms.sunColor.w).
    static let sunIrradiance: Float = 22

    /// Fraction of sunlight reaching the viewer: the long path at low sun removes blue first, hence orange.
    static func sunTransmittance(elevationDeg: Float) -> SIMD3<Float> {
        let el = Double(elevationDeg) * .pi / 180
        let o = SIMD2(0.0, earthRadius + viewerHeight)
        let d = SIMD2(cos(el), sin(el))

        func hit(_ radius: Double) -> (near: Double, far: Double)? {
            let b = simd_dot(o, d)
            let lo = simd_length(o)
            let disc = b * b - (lo - radius) * (lo + radius)
            if disc < 0 { return nil }
            let s = disc.squareRoot()
            return (-b - s, -b + s)
        }
        if let g = hit(earthRadius), g.near > 0 { return .zero }       // sun is below the horizon
        guard let top = hit(atmosphereRadius) else { return SIMD3(repeating: 1) }

        let n = 64
        var odR = 0.0, odM = 0.0
        for i in 0..<n {
            let a = Double(i) / Double(n), b = Double(i + 1) / Double(n)
            let t0 = top.far * a * a, t1 = top.far * b * b
            let p = o + d * (0.5 * (t0 + t1))
            let h = max(simd_length(p) - earthRadius, 0)
            odR += exp(-h / heightR) * (t1 - t0)
            odM += exp(-h / heightM) * (t1 - t0)
        }
        let tau = betaR * odR + SIMD3(repeating: betaM * 1.1 * odM)
        return SIMD3(Float(exp(-tau.x)), Float(exp(-tau.y)), Float(exp(-tau.z)))
    }
}

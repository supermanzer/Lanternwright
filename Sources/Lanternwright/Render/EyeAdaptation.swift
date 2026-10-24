import Foundation

/// Eye adaptation: scales the world's authored exposure toward a mid-grey average, slowly, the way eyes adjust when you walk
/// from the bright shore into a shaded hollow. Pure and testable; the renderer feeds it the measured average luminance.
struct EyeAdaptation {
    /// Multiplier on the world's exposure (1 = as authored).
    private(set) var exposure: Float = 1
    static let key: Float = 0.18               // the average scene luminance the eye settles toward
    static let strength: Float = 0.4           // only a fraction of the correction is applied: scenes keep their authored mood
    static let range: ClosedRange<Float> = 0.75...1.35
    static let secondsToBrighten: Float = 1.5  // dark scene: exposure rises slowly (eyes take time to dark-adapt)
    static let secondsToDarken: Float = 0.5    // bright scene: exposure falls quickly (squinting is fast)

    static func target(averageLuminance l: Float) -> Float {
        min(max(pow(key / max(l, 1e-3), strength), range.lowerBound), range.upperBound)
    }

    mutating func update(averageLuminance l: Float, dt: Float) {
        let t = EyeAdaptation.target(averageLuminance: l)
        let tau = t > exposure ? EyeAdaptation.secondsToBrighten : EyeAdaptation.secondsToDarken
        exposure += (t - exposure) * (1 - exp(-max(dt, 0) / tau))
    }

    /// Start at the right exposure for this luminance (a new world, or a screenshot that must not wait for adaptation).
    mutating func snap(averageLuminance l: Float) { exposure = EyeAdaptation.target(averageLuminance: l) }
}

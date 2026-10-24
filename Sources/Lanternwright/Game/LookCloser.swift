import Foundation

/// "Look closer": hold the right mouse button (or Z) to narrow the field of view, eased in and out, like peering at something
/// far away. The zoom is pure optics (the camera does not move), and look sensitivity shrinks with the field of view so a
/// tiny hand movement does not swing the narrow view wildly.
enum LookCloser {
    static let baseFov: Float = 60 * .pi / 180
    /// Fully zoomed: the image is magnified about 2.9x (tan of the half-angle scales by 0.35).
    static let zoomedScale: Float = 0.35
    static let easeRate: Float = 7          // per second; about 0.3 s to settle

    /// Field of view for a zoom amount 0...1, interpolated in tan-space so the magnification changes evenly.
    static func fov(zoom: Float) -> Float {
        let z = min(max(zoom, 0), 1)
        let s = z * z * (3 - 2 * z)                    // smoothstep on top of the exponential ease: no snap at either end
        return 2 * atan(tan(baseFov / 2) * (1 + (zoomedScale - 1) * s))
    }

    /// How much to scale mouse look so the on-screen angular speed stays the same: tan(fov/2) ratio.
    static func lookScale(zoom: Float) -> Float { tan(fov(zoom: zoom) / 2) / tan(baseFov / 2) }

    static func ease(_ current: Float, held: Bool, dt: Float) -> Float {
        let target: Float = held ? 1 : 0
        let next = current + (target - current) * (1 - exp(-easeRate * dt))
        return abs(next - target) < 0.0005 ? target : next
    }
}

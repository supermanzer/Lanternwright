import Metal
import simd
import Foundation

/// S03.6: the three tone plates beside the lighthouse door (Ilse's exit; S02 section 2.2): small stone plates set into the tower's wall, east of the door, in the order of altitude (tide,
/// wind, stone), each carrying its stone's own mark in iron (waves: three bars; wind: two slanting bars; stone: a square), so a player who has read the stones knows them. Nothing
/// glows: they are struck like the stones, by touch.
enum TonePlates {
    static let names = ["plate_tide", "plate_wind", "plate_stone"]
    /// Where each plate is, in the tower's frame: lateral offset from the door's axis (east), height above the plinth's top, on the wall's surface there.
    static let offsets: [Float] = [1.55, 2.1, 2.65]
    static let heightAbovePlinth: Float = 1.4
    static let size = SIMD2<Float>(0.34, 0.44)

    /// The centre of plate k on the wall's face, in the tower's frame, and the angle that turns a plate facing +Z to face outward there.
    static func local(_ k: Int) -> (position: SIMD3<Float>, facing: Float) {
        let y = Lighthouse.baseY + heightAbovePlinth
        let r = Lighthouse.wallR(y)
        let x = offsets[k]
        let z = max(r * r - x * x, 0).squareRoot()
        return (SIMD3(x, y, z), atan2(x, z))
    }
    static func world(_ k: Int) -> SIMD3<Float> { Layout.lighthouse + local(k).position }

    static func build(into scene: Scene, device: MTLDevice) {
        let stone = Surface(color: SIMD3(0.40, 0.38, 0.35), roughness: 0.9, material: .dressed)
        let iron = Surface(color: SIMD3(0.05, 0.055, 0.07), roughness: 0.5, material: .iron)
        var m = MeshBuilder()
        for k in 0..<3 {
            let l = local(k)
            let frame = translation(Layout.lighthouse + l.position) * rotationY(l.facing)       // local z = out of the wall
            m.chamferBox(size: SIMD3(size.x, size.y, 0.1), chamfer: 0.012, surface: stone, transform: frame * translation(SIMD3(0, 0, -0.01)))
            let face = frame * translation(SIMD3(0, 0, 0.045))
            switch k {
            case 0:                                                                          // tide: waves, three offset bars
                for (i, dx) in ([-0.03, 0.03, -0.03] as [Float]).enumerated() { m.box(size: SIMD3(0.2, 0.035, 0.012), surface: iron, transform: face * translation(SIMD3(dx, (Float(i) - 1) * 0.1, 0))) }
            case 1:                                                                          // wind: two slanting bars
                for dx: Float in [-0.06, 0.06] { m.box(size: SIMD3(0.035, 0.26, 0.012), surface: iron, transform: face * translation(SIMD3(dx, 0, 0)) * rotationZ(-0.5)) }
            default:                                                                         // stone: a square
                m.box(size: SIMD3(0.2, 0.2, 0.012), surface: iron, transform: face)
            }
        }
        scene.add("tone_plates", mesh: m.build(device: device, label: "tone plates"), uniforms: ObjectUniforms(model: matrix_identity_float4x4))
    }
}

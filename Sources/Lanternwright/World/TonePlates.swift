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
    /// A5 (Q79, Q91): each plate carries a SIGNAL-LENGTH BAR under its stone's mark: brass, short for the tide's plate, middle for the wind's, long for the stone's, so the beam's three flash lengths can be matched
    /// without a page. The lengths are the beam's own group seconds sorted (plate k takes the k-th shortest: the stones' altitude order, which is `SignalPattern.ranks`), scaled to the plate; one place, read by the mesh and the test.
    static var barScale: Float { size.x / Layout.Navigation.SignalPattern.groupSeconds.max()! }   // m of bar per second of flash: the LONGEST group is as wide as the plate (A6: the cue must read from the walk)
    static let barY: Float = -0.185              // below the plate's centre (the marks above it stay within +-0.15)
    static let barH: Float = 0.07                // thick enough to read at 8 m (A6)
    static let barEmissive = SIMD4<Float>(1.0, 0.9, 0.62, 0.55)   // a pale bar that keeps its brightness in shade
    static func barLength(_ k: Int) -> Float { Layout.Navigation.SignalPattern.groupSeconds.sorted()[k] * barScale }
    static func world(_ k: Int) -> SIMD3<Float> { Layout.lighthouse + local(k).position }

    static func build(into scene: Scene, device: MTLDevice) {
        let stone = Surface(color: SIMD3(0.40, 0.38, 0.35), roughness: 0.9, material: .dressed)
        let iron = Surface(color: SIMD3(0.05, 0.055, 0.07), roughness: 0.5, material: .iron)
        var m = MeshBuilder(), bars = MeshBuilder()
        let pale = Surface(color: SIMD3(0.93, 0.89, 0.76), roughness: 0.8, material: .dressed)
        for k in 0..<3 {
            let l = local(k)
            let frame = translation(Layout.lighthouse + l.position) * rotationY(l.facing)       // local z = out of the wall
            m.chamferBox(size: SIMD3(size.x, size.y, 0.1), chamfer: 0.012, surface: stone, transform: frame * translation(SIMD3(0, 0, -0.01)))
            let face = frame * translation(SIMD3(0, 0, 0.045))
            bars.box(size: SIMD3(barLength(k), barH, 0.02), surface: pale, transform: face * translation(SIMD3(0, barY, 0.004)))      // the signal-length mark (A5, A6: pale, emissive, 1 : 2.1 : 3.7)
            switch k {
            case 0:                                                                          // tide: waves, three offset bars
                for (i, dx) in ([-0.03, 0.03, -0.03] as [Float]).enumerated() { m.box(size: SIMD3(0.2, 0.035, 0.012), surface: iron, transform: face * translation(SIMD3(dx, (Float(i) - 1) * 0.1, 0))) }
            case 1:                                                                          // wind: two slanting bars
                for dx: Float in [-0.06, 0.06] { m.box(size: SIMD3(0.035, 0.26, 0.012), surface: iron, transform: face * translation(SIMD3(dx, 0, 0)) * rotationZ(-0.5)) }
            default:                                                                         // stone: a square
                m.box(size: SIMD3(0.2, 0.2, 0.012), surface: iron, transform: face)
            }
        }
        scene.add("tone_plate_bars", mesh: bars.build(device: device, label: "plate bars"), uniforms: ObjectUniforms(model: matrix_identity_float4x4, emissive: barEmissive))
        // Debug: LW_PLATE_GLINT=1 sets the glint's starting strength, for frame tools that do not run the game (once the game runs it drives the glint itself: `Game.plateGlint`).
        let glint: Float = ProcessInfo.processInfo.environment["LW_PLATE_GLINT"] == "1" ? Game.plateGlintPeak * 0.8 : 0
        scene.add("tone_plates", mesh: m.build(device: device, label: "tone plates"), uniforms: ObjectUniforms(model: matrix_identity_float4x4, emissive: SIMD4<Float>(1.0, 0.82, 0.5, glint)))
    }
}

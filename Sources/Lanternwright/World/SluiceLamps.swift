import Foundation
import Metal
import simd

/// S04 wiring: the lantern in each sluice room, so the player who turns the prism's ring far away SEES the answer in the room it is for. Each is the route lanterns' stone body with its own lamp core, coloured like its beam
/// component out of the prism (`ArchiveProps.beamColours`: tide, wind, stone); `TideArchivePuzzle` brightens it while the component rests on that gate and keeps it lit once the gate is open. The lamps stand
/// opposite the gate's wheel, inside the room's flat pad.
enum SluiceLamps {
    static func name(_ k: Int) -> String { "ta_sluice_lamp_\(k)" }
    static let bodyName = "ta_sluice_lamp_bodies"
    /// Emissive strengths: lit by nothing in particular (a dim pilot), the component resting on this gate, the gate open.
    static let idle: Float = 0.8, aimed: Float = 7, open: Float = 4
    /// Where lamp k stands: across the room from the gate's wheel (the wheel is 3.5 m east of the gate's centre).
    static func position(_ k: Int) -> SIMD3<Float> { ArchiveLayout.sluices[k] + SIMD3(-3.5, 0, 1.2) }

    static func build(into scene: Scene, device: MTLDevice) {
        let (bodyProto, coreProto) = Props.stoneLantern()
        var bodies = MeshBuilder()
        for k in 0..<3 { bodies.append(bodyProto, transform: translation(position(k))) }
        scene.add(bodyName, mesh: bodies.build(device: device, label: "sluice lamp bodies"))
        for k in 0..<3 {
            var core = MeshBuilder()
            core.append(coreProto, transform: translation(position(k)))
            let c = ArchiveProps.beamColours[k]
            scene.add(name(k), mesh: core.build(device: device, label: "sluice lamp \(k)"), uniforms: ObjectUniforms(model: matrix_identity_float4x4, tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(c, idle)))
        }
    }
}

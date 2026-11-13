import Metal
import simd

/// F09.8 (#113): the unfinished quay's own lamp. A stone lantern at the north landing, dark while the quay is under the water: the player who walks down to the shore finds a quay that is not there and a lamp that is
/// not lit, touches it ("The quay is not raised"), and so learns that something else on the island has to raise it. The lamp comes on when the causeway is up. It is also what "wakes" the stones: seeing it sets
/// `Game.quaySeenFlag` (see `Game.syncQuay`).
enum QuayMarker {
    static let lampName = "quay_lamp", bodyName = "quay_lamp_body", interactableName = "quay_lamp"
    /// West of the first slab, on the landing's flat pad.
    static var position: SIMD3<Float> { Layout.causewayStart + SIMD3(-3.2, 0, 2.4) }
    static let lit: Float = 2.4

    static func build(into scene: Scene, device: MTLDevice) {
        let p = SIMD3(position.x, scene.groundHeight(x: position.x, z: position.z), position.z)
        let (bodyProto, coreProto) = Props.stoneLantern()
        scene.add(bodyName, mesh: bodyProto.build(device: device, label: "quay lamp"), uniforms: ObjectUniforms(model: translation(p)))
        scene.add(lampName, mesh: coreProto.build(device: device, label: "quay lamp core"), uniforms: ObjectUniforms(model: translation(p), tint: SIMD4(1, 1, 1, 1), emissive: SIMD4(1.0, 0.72, 0.3, 0)))
        scene.colliders.addCylinder(center: SIMD2(p.x, p.z), radius: 0.35, minY: p.y - 1, maxY: p.y + 2.2)
    }
    static func interactable(scene: Scene) -> Interactable {
        let p = SIMD3(position.x, scene.groundHeight(x: position.x, z: position.z), position.z)
        return Interactable(id: interactableName, min: p + SIMD3(-0.45, 0.1, -0.45), max: p + SIMD3(0.45, 2.0, 0.45), prompt: "The quay is not raised", reach: 3.4)
    }
}

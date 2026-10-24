import Metal
import simd

/// The sea: one disc mesh that follows the camera. Rings are spaced exponentially (dense near the viewer where
/// waves are visible, sparse toward the horizon) so 130 rings x 256 segments reach 7.8 km. Wave shape is
/// computed in the vertex shader from *world* position, so moving the disc doesn't move the waves.
final class Ocean {
    static let radius: Float = 7800            // just inside the 8000 m far plane
    static let rings = 128
    static let segments = 256
    static let snap: Float = 8          // snap the disc to a coarse grid so vertices don't crawl as you walk
    let mesh: Mesh

    init(device: MTLDevice) {
        let N = Ocean.rings, S = Ocean.segments
        let k: Float = 7
        var verts: [Vertex] = []
        verts.reserveCapacity((N + 1) * S)
        for i in 0...N {
            let t = Float(i) / Float(N)
            let r = Ocean.radius * (exp(k * t) - 1) / (exp(k) - 1)
            for j in 0..<S {
                let a = Float(j) / Float(S) * 2 * .pi
                verts.append(Vertex(position: SIMD4(r * cos(a), 0, r * sin(a), 1),
                                    normal: SIMD4(0, 1, 0, 0), color: SIMD4(1, 1, 1, 1)))
            }
        }
        var idx: [UInt32] = []
        idx.reserveCapacity(N * S * 6)
        for i in 0..<N {
            for j in 0..<S {
                let a = UInt32(i * S + j), b = UInt32(i * S + (j + 1) % S)
                let c = UInt32((i + 1) * S + j), d = UInt32((i + 1) * S + (j + 1) % S)
                idx.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        mesh = Mesh(device: device, vertices: verts, indices: idx, label: "ocean")
    }

    func uniforms(camera: Camera, level: Float = 0) -> ObjectUniforms {
        let x = (camera.position.x / Ocean.snap).rounded() * Ocean.snap
        let z = (camera.position.z / Ocean.snap).rounded() * Ocean.snap
        return ObjectUniforms(model: translation(SIMD3(x, level, z)))
    }
}

import Metal
import simd

/// An indexed triangle mesh on the GPU. Winding is counter-clockwise seen from outside.
final class Mesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
    let boundsMin: SIMD3<Float>
    let boundsMax: SIMD3<Float>

    init(device: MTLDevice, vertices: [Vertex], indices: [UInt32], label: String = "mesh") {
        precondition(!vertices.isEmpty && !indices.isEmpty, "empty mesh \(label)")
        vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count,
                                         options: .storageModeShared)!
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * indices.count,
                                        options: .storageModeShared)!
        vertexBuffer.label = label + ".vertices"
        indexBuffer.label = label + ".indices"
        indexCount = indices.count
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for v in vertices {
            let p = SIMD3(v.position.x, v.position.y, v.position.z)
            lo = simd_min(lo, p); hi = simd_max(hi, p)
        }
        boundsMin = lo
        boundsMax = hi
    }
}

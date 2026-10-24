import simd

// Swift mirrors of the structs in Shaders/Common.swift. Only float4 / float4x4 members:
// SIMD3 is 16 bytes in Swift but packed_float3 is 12 in MSL, and that mismatch fails silently.

struct Vertex {
    var position: SIMD4<Float>   // xyz, w = 1
    var normal: SIMD4<Float>     // xyz, w = material id
    var color: SIMD4<Float>      // rgb albedo (linear), a = roughness
    static let expectedStride = 48
}

struct FrameUniforms {
    var viewProj = matrix_identity_float4x4
    var invViewProj = matrix_identity_float4x4
    var sunViewProj = matrix_identity_float4x4
    var cameraPos = SIMD4<Float>(0, 0, 0, 0)   // w = time
    var sunDir = SIMD4<Float>(0, 1, 0, 1)      // toward sun, w = illuminance
    var sunColor = SIMD4<Float>(1, 1, 1, 0)
    var fogParams = SIMD4<Float>(LookDefaults.fogDensity, LookDefaults.fogHeightFalloff, LookDefaults.exposure, LookDefaults.bloomStrength)
    var screen = SIMD4<Float>(1, 1, 1, 1)
    var misc = SIMD4<Float>(0, LookDefaults.waveStrength, 0, 0)
    static let expectedStride = 288
}

struct ObjectUniforms {
    var model = matrix_identity_float4x4
    var tint = SIMD4<Float>(1, 1, 1, 1)
    var emissive = SIMD4<Float>(0, 0, 0, 0)
    static let expectedStride = 96
}

enum MaterialID: Float {
    case standard = 0, terrain = 1, emissiveGlass = 2, foliage = 3
}

enum GPUTypes {
    static func validateLayouts() {
        precondition(MemoryLayout<Vertex>.stride == Vertex.expectedStride, "Vertex stride mismatch")
        precondition(MemoryLayout<FrameUniforms>.stride == FrameUniforms.expectedStride, "FrameUniforms stride mismatch")
        precondition(MemoryLayout<ObjectUniforms>.stride == ObjectUniforms.expectedStride, "ObjectUniforms stride mismatch")
    }
}

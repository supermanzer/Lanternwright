import Metal
import simd

/// Gulls. Six circle the lighthouse, four glide over open sea well east of the island. Paths are a pure function of time
/// (no simulation state), so they are deterministic and testable; the wing flap happens in the vertex shader.
enum Birds {
    static let count = 10

    struct Path {
        var center: SIMD3<Float>
        var radius: Float
        var angularSpeed: Float      // rad/s, sign = direction
        var phase: Float
        var bobAmp: Float
    }

    static let paths: [Path] = {
        var p: [Path] = []
        let lh = Layout.lighthouse
        for k in 0..<6 {
            let dir: Float = k % 2 == 0 ? 1 : -1
            p.append(Path(center: SIMD3(lh.x, lh.y + 31 + 10 + Float(k) * 3.5, lh.z), radius: 24 + Float(k) * 7,
                          angularSpeed: dir * (0.20 - Float(k) * 0.012), phase: Float(k) * 1.1, bobAmp: 1.2))
        }
        for k in 0..<4 {
            p.append(Path(center: SIMD3(285 + Float(k) * 14, 16 + Float(k) * 5, 40 + Float(k) * 38), radius: 34 + Float(k) * 9,
                          angularSpeed: (k % 2 == 0 ? 1 : -1) * (0.10 + Float(k) * 0.012), phase: Float(k) * 1.7 + 0.4, bobAmp: 2.0))
        }
        return p
    }()

    /// Position and heading (yaw so that local +Z points along the flight direction) of bird k at time t.
    static func pose(_ k: Int, time t: Float) -> (position: SIMD3<Float>, heading: Float, bank: Float) {
        let p = paths[k]
        let a = p.phase + p.angularSpeed * t
        let dir: Float = p.angularSpeed >= 0 ? 1 : -1
        let pos = p.center + SIMD3(p.radius * cos(a), p.bobAmp * sin(t * 0.45 + Float(k)), p.radius * sin(a))
        let tangent = SIMD2(-sin(a) * dir, cos(a) * dir)
        return (pos, atan2(tangent.x, tangent.y), -dir * 0.32)     // bank into the turn
    }

    static func populate(_ scene: Scene, device: MTLDevice) {
        var b = MeshBuilder()
        let white = Surface(color: SIMD3(0.88, 0.88, 0.85), roughness: 0.7, material: .bird)
        let grey = Surface(color: SIMD3(0.55, 0.57, 0.60), roughness: 0.7, material: .bird)
        let tip = Surface(color: SIMD3(0.10, 0.10, 0.11), roughness: 0.7, material: .bird)
        b.sphere(radius: 0.12, segments: 8, surface: white, transform: scaling(SIMD3(1.0, 0.85, 2.6)))
        b.sphere(radius: 0.07, segments: 6, surface: white, transform: translation(SIMD3(0, 0.03, 0.30)))
        b.cone(radius: 0.05, height: 0.10, segments: 5, surface: Surface(color: SIMD3(0.8, 0.55, 0.15), roughness: 0.6, material: .bird),
               transform: translation(SIMD3(0, 0.02, 0.36)) * rotationX(.pi / 2))
        for side: Float in [-1, 1] {
            b.box(size: SIMD3(0.5, 0.018, 0.26), surface: grey, transform: translation(SIMD3(side * 0.33, 0.02, -0.02)))
            b.box(size: SIMD3(0.45, 0.016, 0.20), surface: white, transform: translation(SIMD3(side * 0.80, 0.02, -0.05)))
            b.box(size: SIMD3(0.16, 0.014, 0.16), surface: tip, transform: translation(SIMD3(side * 1.10, 0.02, -0.07)))
        }
        let mesh = b.build(device: device, label: "gull")
        for k in 0..<count {
            let pose = pose(k, time: 0)
            scene.add("bird_\(k)", mesh: mesh,
                      uniforms: ObjectUniforms(model: translation(pose.position) * rotationY(pose.heading),
                                               tint: SIMD4(1, 1, 1, Float(k) * 1.9), emissive: .zero))
        }
    }

    static func update(_ scene: Scene, time t: Float) {
        for k in 0..<count {
            let p = pose(k, time: t)
            scene.update("bird_\(k)") { $0.uniforms.model = translation(p.position) * rotationY(p.heading) * rotationZ(p.bank) * scaling(SIMD3(repeating: 1.15)) }
        }
    }
}

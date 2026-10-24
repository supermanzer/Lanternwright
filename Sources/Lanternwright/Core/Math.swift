import simd

typealias float3 = SIMD3<Float>
typealias float4 = SIMD4<Float>
typealias float4x4 = simd_float4x4

/// First-person camera. Conventions are in docs/TASKS.md §0:
/// yaw 0 looks north (-Z), positive yaw turns right, pitch positive looks up.
struct Camera {
    var position: SIMD3<Float>
    var yaw: Float
    var pitch: Float
    var fovY: Float = 60 * .pi / 180
    var near: Float = 0.1
    var far: Float = 8000

    var forward: SIMD3<Float> {
        SIMD3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    var view: float4x4 { lookAt(eye: position, target: position + forward, up: SIMD3(0, 1, 0)) }

    func proj(aspect: Float) -> float4x4 {
        perspective(fovY: fovY, aspect: aspect, near: near, far: far)
    }
}

/// Right-handed perspective projection mapping view-space depth to Metal's 0..1 clip range.
func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
    let ys = 1 / tan(fovY * 0.5)
    let xs = ys / aspect
    let zs = far / (near - far)
    return float4x4(columns: (
        float4(xs, 0, 0, 0),
        float4(0, ys, 0, 0),
        float4(0, 0, zs, -1),
        float4(0, 0, zs * near, 0)))
}

/// Right-handed orthographic projection (0..1 depth). Used for the sun shadow map.
func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> float4x4 {
    float4x4(columns: (
        float4(2 / (right - left), 0, 0, 0),
        float4(0, 2 / (top - bottom), 0, 0),
        float4(0, 0, 1 / (near - far), 0),
        float4(-(right + left) / (right - left), -(top + bottom) / (top - bottom), near / (near - far), 1)))
}

func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
    let f = normalize(target - eye)
    let s = normalize(cross(f, up))
    let u = cross(s, f)
    return float4x4(columns: (
        float4(s.x, u.x, -f.x, 0),
        float4(s.y, u.y, -f.y, 0),
        float4(s.z, u.z, -f.z, 0),
        float4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)))
}

func translation(_ t: SIMD3<Float>) -> float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = float4(t, 1)
    return m
}

func scaling(_ s: SIMD3<Float>) -> float4x4 {
    float4x4(diagonal: float4(s, 1))
}

func rotationY(_ a: Float) -> float4x4 {
    let c = cos(a), s = sin(a)
    return float4x4(columns: (float4(c, 0, -s, 0), float4(0, 1, 0, 0), float4(s, 0, c, 0), float4(0, 0, 0, 1)))
}

func rotationX(_ a: Float) -> float4x4 {
    let c = cos(a), s = sin(a)
    return float4x4(columns: (float4(1, 0, 0, 0), float4(0, c, s, 0), float4(0, -s, c, 0), float4(0, 0, 0, 1)))
}

func rotationZ(_ a: Float) -> float4x4 {
    let c = cos(a), s = sin(a)
    return float4x4(columns: (float4(c, s, 0, 0), float4(-s, c, 0, 0), float4(0, 0, 1, 0), float4(0, 0, 0, 1)))
}

func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

/// Six clip planes extracted from a view-projection matrix (Gribb-Hartmann), for culling boxes.
/// Works for perspective and orthographic cameras and for Metal's 0...1 depth range.
struct Frustum {
    private var planes: [SIMD4<Float>] = []

    init(viewProj m: float4x4) {
        func row(_ i: Int) -> SIMD4<Float> {
            SIMD4(m.columns.0[i], m.columns.1[i], m.columns.2[i], m.columns.3[i])
        }
        let r0 = row(0), r1 = row(1), r2 = row(2), r3 = row(3)
        let raw = [r3 + r0, r3 - r0, r3 + r1, r3 - r1, r2, r3 - r2]     // left, right, bottom, top, near (z >= 0), far
        planes = raw.map { p in p / max(simd_length(SIMD3(p.x, p.y, p.z)), 1e-6) }
    }

    /// False only if the box is entirely outside one plane (conservative: may keep a few invisible boxes).
    func intersects(min lo: SIMD3<Float>, max hi: SIMD3<Float>) -> Bool {
        for p in planes {
            // The box corner furthest along the plane normal; if even that is behind the plane, the box is outside.
            let v = SIMD3(p.x >= 0 ? hi.x : lo.x, p.y >= 0 ? hi.y : lo.y, p.z >= 0 ? hi.z : lo.z)
            if p.x * v.x + p.y * v.y + p.z * v.z + p.w < 0 { return false }
        }
        return true
    }
}

/// A rotation that turns the +Y axis into direction `d` (for orienting beams and rods along an arbitrary line).
func rotation(aligningYTo d: SIMD3<Float>) -> float4x4 {
    let y = normalize(d)
    let helper: SIMD3<Float> = abs(y.y) > 0.99 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
    let x = normalize(cross(helper, y))
    let z = cross(x, y)
    return float4x4(columns: (SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(0, 0, 0, 1)))
}

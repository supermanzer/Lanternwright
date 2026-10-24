import simd

/// First-person walker. Position is the feet; the camera sits `eyeHeight` above, plus a gentle head bob.
struct Player {
    static let eyeHeight: Float = 1.7
    static let radius: Float = 0.35
    static let walkSpeed: Float = 3.2
    static let runSpeed: Float = 6.5
    /// Highest ledge that can be stepped onto in one move (dock edge, kerb), and the steepest walkable slope
    /// (rise/run; 1.19 is about 50 degrees).
    static let maxStep: Float = 0.5
    static let maxSlope: Float = 1.19
    /// The sea is a soft wall: you may not wade where the ground is deeper than this below the surface.
    static let minGround: Float = -0.4

    var position: SIMD3<Float>
    var yaw: Float
    var pitch: Float = 0
    private(set) var velocity = SIMD2<Float>(0, 0)
    private(set) var bobPhase: Float = 0
    private var bobAmount: Float = 0
    /// Increments once per footfall; audio watches it.
    private(set) var stepCount = 0

    init(position: SIMD3<Float>, yaw: Float) {
        self.position = position
        self.yaw = yaw
    }

    var speed: Float { length(velocity) }

    var camera: Camera {
        let bob = sin(bobPhase * 2) * 0.03 * bobAmount
        return Camera(position: position + SIMD3(0, Player.eyeHeight + bob, 0), yaw: yaw, pitch: pitch)
    }

    /// Mouse look is applied once per rendered frame, not per fixed step, so it feels immediate.
    mutating func applyLook(_ look: SIMD2<Float>) {
        yaw += look.x
        if yaw > .pi { yaw -= 2 * .pi } else if yaw < -.pi { yaw += 2 * .pi }
        pitch = min(max(pitch + look.y, -1.45), 1.45)
    }

    /// Can the feet move from `from` to `to`? Rejects wading too deep, ledges that are too tall, slopes that are too steep.
    private func canMove(from: SIMD2<Float>, to: SIMD2<Float>, scene: Scene) -> Bool {
        let g0 = scene.groundHeight(x: from.x, z: from.y)
        let g1 = scene.groundHeight(x: to.x, z: to.y)
        if g1 < Player.minGround && g1 < g0 { return false }       // never wade deeper (but allow retreating)
        let rise = g1 - g0
        if rise > Player.maxStep { return false }
        let run = max(length(to - from), 1e-4)
        if rise / run > Player.maxSlope && rise > 0.02 { return false }
        return true
    }

    /// Advance one fixed step. Returns true on the tick a foot lands (for footstep sounds).
    @discardableResult
    mutating func step(dt: Float, input: InputState, scene: Scene) -> Bool {
        // Wish velocity in world space. Yaw 0 faces north (-Z); positive yaw turns toward +X.
        let forward = SIMD2(sin(yaw), -cos(yaw))
        let right = SIMD2(cos(yaw), sin(yaw))
        let wishSpeed = input.run ? Player.runSpeed : Player.walkSpeed
        let wish = (right * input.move.x + forward * input.move.y) * wishSpeed
        // Exponential approach to the wish velocity: a soft start/stop (time constant ~ 0.1 s).
        velocity += (wish - velocity) * min(1, dt * 10)
        if length(velocity) < 0.01 && length(wish) == 0 { velocity = .zero }

        // Move, sliding along blockers: try the full move, then each axis alone.
        let from = SIMD2(position.x, position.z)
        let delta = velocity * dt
        var pos = from
        for candidate in [from + delta, from + SIMD2(delta.x, 0), from + SIMD2(0, delta.y)] where candidate != from {
            if canMove(from: from, to: candidate, scene: scene) { pos = candidate; break }
        }
        scene.colliders.resolve(position: &pos, radius: Player.radius, feetY: position.y, height: Player.eyeHeight)
        // The push-out must not shove us into the sea or up a cliff either.
        if !canMove(from: from, to: pos, scene: scene) { pos = from }
        position.x = pos.x; position.z = pos.y

        // Follow the ground: smooth vertical motion so stairs and dock edges don't snap the camera.
        let ground = scene.groundHeight(x: pos.x, z: pos.y)
        position.y += (ground - position.y) * min(1, dt * 18)
        if abs(ground - position.y) < 0.001 { position.y = ground }

        // Head bob and footfalls: one stride (two steps) per 1.5 m walked.
        let moving = speed > 0.3
        bobAmount += ((moving ? min(speed / Player.walkSpeed, 1.6) : 0) - bobAmount) * min(1, dt * 8)
        var footfall = false
        if moving {
            let before = Int(floor(bobPhase / .pi))
            bobPhase += speed * dt / 1.5 * 2 * .pi
            if Int(floor(bobPhase / .pi)) != before { footfall = true; stepCount += 1 }
        }
        return footfall
    }
}

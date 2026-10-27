import simd

/// First-person walker. Position is the feet; the camera sits `eyeHeight` above, plus a gentle head bob.
struct Player {
    static let eyeHeight: Float = 1.7
    static let radius: Float = 0.35
    static let walkSpeed: Float = 3.2
    static let runSpeed: Float = 6.5
    /// Highest ledge that can be stepped onto in one move (dock edge, kerb), and the steepest walkable slope
    /// (rise/run; 0.84 is about 40 degrees).
    /// The highest single step up the player will take: 0.5 m (a knee-high kerb, a stair; the lighthouse door steps rise 0.45 at their highest edge). Higher is refused as a wall.
    /// F03 M1 (#35) found the limit was NOT the fault (it was already above the plan's 0.35-0.4 m): the fault was the slope rule below, which refused any rise over 2 cm onto
    /// anything that was not a `Platform`, such as the dock's first board.
    static let maxStep: Float = 0.5
    static let maxSlope: Float = 0.84
    /// F01 W5.4: an OPTIONAL soft slip (the user's idea, default off, a setting): on ground steeper than `maxSlope` you slide gently downhill, never any harm.
    nonisolated(unsafe) static var slipEnabled = false
    static let slipSpeed: Float = 1.6
    /// The sea is a soft wall: you may not wade where the ground is deeper than this below the surface.
    static let minGround: Float = -0.4

    /// Walking pace by slope (rise over run in the direction of travel): steep climbs slow you toward 55 % of your pace, a gentle
    /// descent speeds you up by a little (8 %), and the ground you can walk (see `maxSlope`) never stops you. Cadence follows
    /// because the step length is a function of speed.
    static let minPace: Float = 0.40
    static func paceFactor(slope: Float) -> Float {
        // Full pace up to ~25 degrees (0.47), then a smooth taper to ~40 % at ~38 degrees (0.78): steep ground guides you without a gimmick (F01 W5.3).
        if slope >= 0 { return max(minPace, (1 - 0.45 * min(slope / 0.8, 1)) * (1 - 0.45 * smoothstep(0.47, 0.78, slope))) }
        return 1 + 0.08 * min(-slope / 0.5, 1)
    }

    var position: SIMD3<Float>
    var yaw: Float
    var pitch: Float = 0
    private(set) var velocity = SIMD2<Float>(0, 0)
    /// Gait phase: +1 per footfall (left, right, left...). Bob and sway are functions of it.
    private(set) var stepPhase: Float = 0
    private var bobAmount: Float = 0
    /// F02 M1: the eye's vertical offset from where the feet put it (m). A step up of 18 cm leaves it at -0.18 (it never lags more than `maxEyeLag`: 0.35 m, because the lighthouse plinth has 0.3 m risers and a 15 cm cap would pop the eye 15 cm in one frame) and a critically
    /// damped spring (omega 22 rad/s: about 0.09 s) brings it back to 0; a drop does the reverse. Slopes and flat ground do not use it.
    private(set) var eyeLag: Float = 0
    private var eyeVel: Float = 0
    static let eyeOmega: Float = 22
    static let maxEyeLag: Float = 0.35
    /// A ground change of more than this in one fixed tick (7 cm in 1/120 s: even the steepest walkable slope at a run is 4.6 cm) is a step, not a slope.
    static let stepJump: Float = 0.07
    /// Where the eye is before the head bob: feet + eyeHeight + the spring's offset (what the step selftest watches).
    var eyeBase: Float { position.y + Player.eyeHeight + eyeLag }
    /// Increments once per footfall; audio watches it.
    private(set) var stepCount = 0
    /// Whether the latest footfall was a run step (a harder, shorter impact).
    private(set) var lastStepWasRun = false

    /// Distance between footfalls. Walking at 3.2 m/s with 1.45 m steps is about 2.2 steps/s, a brisk natural
    /// cadence; running lengthens the step (2.2 m at 6.5 m/s, about 3 steps/s) instead of just stepping twice as
    /// fast, which is what makes a run read as a different gait and not as walking on fast-forward.
    static func stepLength(speed: Float) -> Float { 1.45 + 0.75 * runFactor(speed: speed) }
    static func runFactor(speed: Float) -> Float { min(max((speed - walkSpeed) / (runSpeed - walkSpeed), 0), 1) }

    init(position: SIMD3<Float>, yaw: Float) {
        self.position = position
        self.yaw = yaw
    }

    var speed: Float { length(velocity) }
    /// 0...1: how hard the ground is giving way under the feet right now (0 on footing that holds). The slide sound follows it (F03 A3).
    private(set) var slipAmount: Float = 0

    var camera: Camera {
        // The head dips as each foot lands (phase = whole number) and rises between; it also sways side to side
        // as weight shifts from foot to foot. Both grow when running.
        let run = Player.runFactor(speed: speed)
        let bob = -cos(stepPhase * 2 * .pi) * (0.026 + 0.04 * run) * bobAmount
        let sway = sin(stepPhase * .pi) * (0.012 + 0.016 * run) * bobAmount
        let right = SIMD3<Float>(cos(yaw), 0, sin(yaw))
        return Camera(position: position + SIMD3(0, Player.eyeHeight + eyeLag + bob, 0) + right * sway, yaw: yaw, pitch: pitch)
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
        if rise / run > Player.maxSlope && rise > 0.02 && !scene.isOnStep(to) { return false }       // stairs and decks are steps, not slopes (F03 #35: the dock's first board was refused as a 'slope')
        return true
    }

    /// Advance one fixed step. Returns true on the tick a foot lands (for footstep sounds).
    @discardableResult
    mutating func step(dt: Float, input: InputState, scene: Scene) -> Bool {
        // Wish velocity in world space. Yaw 0 faces north (-Z); positive yaw turns toward +X.
        let forward = SIMD2(sin(yaw), -cos(yaw))
        let right = SIMD2(cos(yaw), sin(yaw))
        var wishDir = right * input.move.x + forward * input.move.y
        // Pace follows the ground ahead of the feet (1 m look-ahead along the direction of travel).
        var pace: Float = 1
        // Ankle-deep wading: in the shallows (ground below ~10 cm above the waterline) the water drags at you, down to 60 %.
        let here = scene.groundHeight(x: position.x, z: position.z)
        let wading = 1 - 0.4 * smoothstep(0.1, -0.3, here)
        if length(wishDir) > 0.01 {
            wishDir = normalize(wishDir) * min(length(wishDir), 1)
            let dir = normalize(wishDir)
            let g0 = scene.groundHeight(x: position.x, z: position.z)
            let g1 = scene.groundHeight(x: position.x + dir.x, z: position.z + dir.y)
            if g0 > Player.minGround || g1 > Player.minGround { pace = Player.paceFactor(slope: g1 - g0) }
        }
        let wishSpeed = (input.run ? Player.runSpeed : Player.walkSpeed) * pace * wading
        let wish = wishDir * wishSpeed
        // Exponential approach to the wish velocity: a soft start/stop (time constant ~ 0.1 s).
        velocity += (wish - velocity) * min(1, dt * 10)
        if length(velocity) < 0.01 && length(wish) == 0 { velocity = .zero }

        // Move, sliding along blockers: try the full move, then each axis alone.
        let from = SIMD2(position.x, position.z)
        let delta = velocity * dt
        var pos = from
        // Ground too steep to climb behaves like a wall (F01 W4.1): the uphill part of the move is removed and the player slides along the contour,
        // instead of stopping dead. The old fall-backs (each axis alone) remain for ledges and the sea's edge.
        var slide = delta
        let gx = scene.groundHeight(x: from.x + 0.3, z: from.y) - scene.groundHeight(x: from.x - 0.3, z: from.y)
        let gz = scene.groundHeight(x: from.x, z: from.y + 0.3) - scene.groundHeight(x: from.x, z: from.y - 0.3)
        let grad = SIMD2(gx, gz) / 0.6
        if length(grad) > 1e-4 {
            let uphill = normalize(grad)
            slide -= uphill * max(dot(delta, uphill), 0)
        }
        for candidate in [from + delta, from + slide, from + SIMD2(delta.x, 0), from + SIMD2(0, delta.y)] where candidate != from {
            if canMove(from: from, to: candidate, scene: scene) { pos = candidate; break }
        }
        var slipNow: Float = 0
        if Player.slipEnabled, length(grad) > Player.maxSlope {                      // too steep to stand on: slide down the fall line (a metre or two, no inertia)
            let down = -normalize(grad) * Player.slipSpeed * dt
            if canMove(from: pos, to: pos + down, scene: scene) || scene.groundHeight(x: pos.x + down.x, z: pos.y + down.y) < scene.groundHeight(x: pos.x, z: pos.y) { pos += down; slipNow = 0.55 + 0.45 * min(1, length(velocity) / Player.walkSpeed) }
        }
        slipAmount = slipNow
        scene.colliders.resolve(position: &pos, radius: Player.radius, feetY: position.y, height: Player.eyeHeight)
        // The push-out must not shove us into the sea or up a cliff either.
        if !canMove(from: from, to: pos, scene: scene) { pos = from }
        position.x = pos.x; position.z = pos.y

        // F02 M1: the FEET are physical, always on the ground that is drawn (Scene.groundHeight: terrain, boards, platforms). The CAMERA's vertical offset
        // is what is smoothed: a riser or a drop moves the feet at once and the eye follows with a critically damped spring (see `eyeLag`).
        let ground = scene.groundHeight(x: pos.x, z: pos.y)
        let dy = ground - position.y
        position.y = ground
        if abs(dy) > Player.stepJump { eyeLag = min(max(eyeLag - dy, -Player.maxEyeLag), Player.maxEyeLag) }      // a step: the eye stays where it was
        let decay = exp(-Player.eyeOmega * dt)
        let c2 = eyeVel + Player.eyeOmega * eyeLag
        eyeLag = (eyeLag + c2 * dt) * decay
        eyeVel = (eyeVel - Player.eyeOmega * c2 * dt) * decay
        if abs(eyeLag) < 0.0002 && abs(eyeVel) < 0.002 { eyeLag = 0; eyeVel = 0 }

        // Gait: advance the step phase by distance walked / step length; a footfall happens at each whole number.
        let moving = speed > 0.3
        bobAmount += ((moving ? min(speed / Player.walkSpeed, 1.0) : 0) - bobAmount) * min(1, dt * 8)
        var footfall = false
        if moving {
            let before = Int(floor(stepPhase))
            stepPhase += speed * dt / Player.stepLength(speed: speed)
            if Int(floor(stepPhase)) != before {
                footfall = true
                stepCount += 1
                lastStepWasRun = Player.runFactor(speed: speed) > 0.5
            }
        }
        return footfall
    }
}

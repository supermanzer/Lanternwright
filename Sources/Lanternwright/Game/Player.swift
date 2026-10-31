import simd

/// First-person walker. Position is the feet; the camera sits `eyeHeight` above, plus a gentle head bob.
struct Player {
    static let eyeHeight: Float = 1.7
    static let radius: Float = 0.35
    /// M10.2: a stroll, not a march (the island is a few hundred metres across: a minute or two between landmarks), and a brisk run, not a sprint. The setting `pace` (0.7...1.3) scales both.
    static let walkSpeed: Float = 2.6
    /// F07 B-pace (#81, "running 25 % faster in ground covered"): 4.4 -> 5.5 m/s; the walk is unchanged. The stride lengthens with it (`stepLength`) so the cadence stays about 3.2 steps/s, not a flurry.
    static let runSpeed: Float = 5.5
    /// Velocity time constants (s): how long the player takes to reach 63 % of a new wish velocity (ease-in) and to lose 63 % of it when the keys are released (ease-out).
    static let accelTau: Float = 0.12
    static let decelTau: Float = 0.16
    /// The player's `pace` setting, applied by the app (the same pattern as `slipEnabled`).
    nonisolated(unsafe) static var paceScale: Float = 1
    static var scaledWalkSpeed: Float { walkSpeed * paceScale }
    static var scaledRunSpeed: Float { runSpeed * paceScale }
    /// (`maxSlope` below: the steepest walkable slope, rise/run; 0.84 is about 40 degrees.)
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
    /// S04.2: the sea's height (m) where the player is: 0 everywhere but the Tide Archive, whose tide the game writes here every tick (`Game.fixedStep`). Wading depth is the ground's depth under THIS: a place is
    /// too deep when the ground is more than `-minGround` (0.4 m) under the sea, whatever the sea's height.
    nonisolated(unsafe) static var sea: Float = 0
    /// S04.3: the Great Ledger gallery's water (a body of its own, higher than the sea): where it is and how high its surface stands now (`ArchiveProps.update` writes it every tick; nil elsewhere). The player
    /// does not wade into it deeper than `-minGround`, as into the sea, and it is empty (the drained gallery) once its surface is at the floor.
    nonisolated(unsafe) static var galleryWater: (centre: SIMD2<Float>, half: SIMD2<Float>, level: Float)?
    static func tooDeepInGallery(_ p: SIMD2<Float>, ground: Float) -> Bool {
        guard let g = galleryWater else { return false }
        let d = simd_abs(p - g.centre)
        return d.x < g.half.x && d.y < g.half.y && g.level - ground > -minGround
    }

    /// Walking pace by slope (rise over run in the direction of travel): steep climbs slow you toward 55 % of your pace, a gentle
    /// descent speeds you up by a little (8 %), and the ground you can walk (see `maxSlope`) never stops you. Cadence follows
    /// because the step length is a function of speed.
    static let minPace: Float = 0.40
    static func paceFactor(slope: Float) -> Float {
        // Full pace up to ~25 degrees (0.47), then a smooth taper to ~40 % at ~38 degrees (0.78): steep ground guides you without a gimmick (F01 W5.3).
        if slope >= 0 { return max(minPace, (1 - 0.45 * min(slope / 0.8, 1)) * (1 - 0.45 * smoothstep(0.47, 0.78, slope))) }
        return 1 + 0.08 * min(-slope / 0.5, 1)
    }

    // M10.4: soft confinement to the world's navigation corridors (Game/Navigation.swift, authored in Layout.Navigation).
    /// Beyond a corridor's edge there is a margin of this many metres: it slows the way out, steers you back, and its far side is a hard limit.
    static let marginWidth: Float = 4
    /// At the far side of the margin the OUTWARD part of your motion is down to 25 % (a factor of `1 - marginSlow`); walking along the edge or back in is not slowed.
    static let marginSlow: Float = 0.75
    /// While you are moving in the margin you are also steered back toward the trail, up to this fast (m/s), in proportion to how deep in you are.
    static let driftSpeed: Float = 0.8
    /// A player further than this beyond the margin got there some other way (a teleport, a load, a world change): they are moved to the nearest connected inside point.
    static let strandedSlack: Float = 0.5
    /// Off for tools and free roam (M10.7 turns this into the Guided / Loose / Free setting).
    nonisolated(unsafe) static var guidance: Guidance = .guided
    /// True unless in free roam. (Setting it is for tests and tools: true means Guided.)
    static var confinementEnabled: Bool { get { guidance != .free } set { guidance = newValue ? .guided : .free } }
    /// The margin in force: `marginWidth`, doubled in Loose.
    static var margin: Float { guidance == .loose ? marginWidth * Guidance.looseMargin : marginWidth }
    /// 0 inside a corridor, rising smoothly to 1 at the hard limit: the ambient cue (a faint closing-in of the fog and the ambience, builder A's G10.3.9) reads this.
    private(set) var marginPressure: Float = 0

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

    /// Distance between footfalls. Walking at 2.6 m/s with 1.2 m steps is about 2.2 steps/s, an unhurried natural
    /// cadence; running lengthens the step (1.7 m at 5.5 m/s, about 3.2 steps/s) as well as quickening it,
    /// which is what makes a run read as a different gait and not as walking on fast-forward. Both follow the `pace` setting.
    static func stepLength(speed: Float) -> Float { 1.2 + 0.5 * runFactor(speed: speed) }
    static func runFactor(speed: Float) -> Float { min(max((speed - scaledWalkSpeed) / (scaledRunSpeed - scaledWalkSpeed), 0), 1) }

    /// Ankle-deep wading: in the shallows (ground below ~10 cm above the waterline) the water drags at you, down to 60 %.
    static func wading(ground: Float) -> Float { 1 - 0.4 * smoothstep(0.1, -0.3, ground - Player.sea) }
    /// The speed the player is aiming for (m/s): walk or run, times the `pace` setting, the slope factor (`paceFactor`) and wading.
    static func wishSpeed(run: Bool, pace: Float, wading: Float) -> Float { (run ? runSpeed : walkSpeed) * paceScale * pace * wading }

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

    /// M10.1: the view cannot tilt past 65 degrees, up or down (a calmer, more composed frame).
    static let maxPitch: Float = 65 * .pi / 180
    var lookFilter = LookFilter()
    /// M10.5: the framing assist at vantage stations (Game/FramingAssist.swift).
    var framing = FramingAssist()

    /// Mouse look is applied once per rendered frame, not per fixed step, so it feels immediate. `dt` is the frame time: the look filter smooths and soft-limits by time, never by frame count.
    /// With a network, a vantage station the player stands at may also draw the camera a few degrees toward its composed view (`FramingAssist`); `assistScale` is the look-closer factor.
    mutating func applyLook(_ raw: SIMD2<Float>, dt: Float, nav: NavNetwork? = nil, assistScale: Float = 1) {
        var look = lookFilter.filter(raw, dt: dt, calm: LookFilter.calm)
        if let nav, !nav.vantages.isEmpty {
            // The raw look decides whether the player is steering (it is the input, not the filter's smoothed tail).
            look += framing.step(dt: dt, eye: position + SIMD3(0, Player.eyeHeight, 0), feet: SIMD2(position.x, position.z), yaw: yaw, pitch: pitch,
                                 rawLook: raw, scale: assistScale, vantages: nav.vantages)
        }
        yaw += look.x
        if yaw > .pi { yaw -= 2 * .pi } else if yaw < -.pi { yaw += 2 * .pi }
        pitch = min(max(pitch + look.y, -Player.maxPitch), Player.maxPitch)
    }

    /// Can the feet move from `from` to `to`? Rejects wading too deep, ledges that are too tall, slopes that are too steep.
    private func canMove(from: SIMD2<Float>, to: SIMD2<Float>, scene: Scene, ground: (Float, Float) -> Float) -> Bool {
        let g0 = ground(from.x, from.y)
        let g1 = ground(to.x, to.y)
        if Player.tooDeepInGallery(to, ground: g1) && !(Player.tooDeepInGallery(from, ground: g0) && g1 > g0) { return false }                  // S04.3: not down into the gallery's water
        if g1 - Player.sea < Player.minGround && g1 < g0 { return false }       // never wade deeper (but allow retreating)
        let rise = g1 - g0
        if rise > Player.maxStep { return false }
        let run = max(length(to - from), 1e-4)
        if rise / run > Player.maxSlope && rise > 0.02 && !scene.isOnStep(to) { return false }       // stairs and decks are steps, not slopes (F03 #35: the dock's first board was refused as a 'slope')
        return true
    }

    /// Advance one fixed step. Returns true on the tick a foot lands (for footstep sounds).
    @discardableResult
    mutating func step(dt: Float, input: InputState, scene: Scene, nav: NavNetwork? = nil, interior: LighthouseInterior? = nil) -> Bool {
        // S03.5: inside the open lighthouse the floor is the feet-aware stair/room query; everywhere else it is the scene's ground (one height per spot).
        let feetY = position.y
        let ground: (Float, Float) -> Float = { x, z in interior?.height(x: x, z: z, feetY: feetY) ?? scene.groundHeight(x: x, z: z) }
        // M10.4: if the feet stand beyond the margin (a teleport, a load, a world change) they are put on the nearest connected inside point. The vertical
        // difference goes through the eye spring below, so the camera settles instead of popping.
        var sdHere: Float = -1
        if let nav {
            let feet = SIMD2(position.x, position.z)
            sdHere = nav.signedDistance(feet)
            if sdHere > Player.margin + Player.strandedSlack {
                let landing = nav.nearestReachable(feet)
                position.x = landing.x; position.z = landing.y
                velocity = .zero
                sdHere = nav.signedDistance(landing)
            }
            marginPressure = smoothstep(0, Player.margin, max(sdHere, 0))
        } else { marginPressure = 0 }
        // Wish velocity in world space. Yaw 0 faces north (-Z); positive yaw turns toward +X.
        let forward = SIMD2(sin(yaw), -cos(yaw))
        let right = SIMD2(cos(yaw), sin(yaw))
        var wishDir = right * input.move.x + forward * input.move.y
        // Pace follows the ground ahead of the feet (1 m look-ahead along the direction of travel).
        var pace: Float = 1
        let here = ground(position.x, position.z)
        let wading = Player.wading(ground: here)
        if length(wishDir) > 0.01 {
            wishDir = normalize(wishDir) * min(length(wishDir), 1)
            let dir = normalize(wishDir)
            let g0 = ground(position.x, position.z)
            let g1 = ground(position.x + dir.x, position.z + dir.y)
            if g0 - Player.sea > Player.minGround || g1 - Player.sea > Player.minGround { pace = Player.paceFactor(slope: g1 - g0) }
        }
        var wish = wishDir * Player.wishSpeed(run: input.run, pace: pace, wading: wading)
        if let nav, sdHere > 0, length(wish) > 0 {
            // In the margin: the outward part of the wish is slowed (to 25 % at the hard limit) and a drift steers the player back toward the trail.
            // Neither applies to walking along the edge or back in, and the drift only acts while the player is moving (no ghost-walking when standing still).
            let feet = SIMD2(position.x, position.z)
            let outward = normalize(feet - nav.nearestInside(feet))
            wish -= outward * max(dot(wish, outward), 0) * Player.marginSlow * marginPressure
            wish -= outward * Player.driftSpeed * marginPressure
        }
        // Exponential approach to the wish velocity: a soft start/stop (M10.2: 0.12 s to speed up, 0.16 s to ease to a stop).
        let tau = length(wish) < length(velocity) ? Player.decelTau : Player.accelTau
        velocity += (wish - velocity) * (1 - exp(-dt / tau))
        if length(velocity) < 0.01 && length(wish) == 0 { velocity = .zero }

        // Move, sliding along blockers: try the full move, then each axis alone.
        let from = SIMD2(position.x, position.z)
        let delta = velocity * dt
        var pos = from
        // Ground too steep to climb behaves like a wall (F01 W4.1): the uphill part of the move is removed and the player slides along the contour,
        // instead of stopping dead. The old fall-backs (each axis alone) remain for ledges and the sea's edge.
        var slide = delta
        let gx = ground(from.x + 0.3, from.y) - ground(from.x - 0.3, from.y)
        let gz = ground(from.x, from.y + 0.3) - ground(from.x, from.y - 0.3)
        let grad = SIMD2(gx, gz) / 0.6
        if length(grad) > 1e-4 {
            let uphill = normalize(grad)
            slide -= uphill * max(dot(delta, uphill), 0)
        }
        for candidate in [from + delta, from + slide, from + SIMD2(delta.x, 0), from + SIMD2(0, delta.y)] where candidate != from {
            if canMove(from: from, to: candidate, scene: scene, ground: ground) { pos = candidate; break }
        }
        var slipNow: Float = 0
        if Player.slipEnabled, length(grad) > Player.maxSlope {                      // too steep to stand on: slide down the fall line (a metre or two, no inertia)
            let down = -normalize(grad) * Player.slipSpeed * dt
            if canMove(from: pos, to: pos + down, scene: scene, ground: ground) || ground(pos.x + down.x, pos.y + down.y) < ground(pos.x, pos.y) { pos += down; slipNow = 0.55 + 0.45 * min(1, length(velocity) / Player.walkSpeed) }
        }
        slipAmount = slipNow
        scene.colliders.resolve(position: &pos, radius: Player.radius, feetY: position.y, height: Player.eyeHeight)
        // M10.4: the hard limit is the margin's far edge. The feet are projected back onto it (along the gradient of the distance, so a curved edge is slid along,
        // never stuck on); if that cannot be walked, the player stays where they were, which is inside by induction.
        if let nav {
            let sd = nav.signedDistance(pos)
            if sd > Player.margin {
                let outward = normalize(pos - nav.nearestInside(pos))
                pos -= outward * (sd - Player.margin)
            }
        }
        // The push-out must not shove us into the sea or up a cliff either.
        if !canMove(from: from, to: pos, scene: scene, ground: ground) { pos = from }
        // The backstop: whatever happened above (a player placed just past the limit where the projection cannot be walked), the feet never end a tick beyond it.
        if let nav, nav.signedDistance(pos) > Player.margin + 1e-3 { pos = nav.nearestReachable(pos) }
        position.x = pos.x; position.z = pos.y

        // F02 M1: the FEET are physical, always on the ground that is drawn (Scene.groundHeight: terrain, boards, platforms). The CAMERA's vertical offset
        // is what is smoothed: a riser or a drop moves the feet at once and the eye follows with a critically damped spring (see `eyeLag`).
        let floorHere = ground(pos.x, pos.y)
        let dy = floorHere - position.y
        position.y = floorHere
        if abs(dy) > Player.stepJump { eyeLag = min(max(eyeLag - dy, -Player.maxEyeLag), Player.maxEyeLag) }      // a step: the eye stays where it was
        let decay = exp(-Player.eyeOmega * dt)
        let c2 = eyeVel + Player.eyeOmega * eyeLag
        eyeLag = (eyeLag + c2 * dt) * decay
        eyeVel = (eyeVel - Player.eyeOmega * c2 * dt) * decay
        if abs(eyeLag) < 0.0002 && abs(eyeVel) < 0.002 { eyeLag = 0; eyeVel = 0 }

        // Gait: advance the step phase by distance walked / step length; a footfall happens at each whole number.
        let moving = speed > 0.3
        bobAmount += ((moving ? min(speed / Player.scaledWalkSpeed, 1.0) : 0) - bobAmount) * min(1, dt * 8)
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

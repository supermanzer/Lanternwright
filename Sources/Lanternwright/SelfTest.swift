import Foundation
import Metal
import simd

/// `--selftest [name]`: fast, headless checks that tasks extend with their own cases.
enum SelfTest {
    static func run(_ name: String, device: MTLDevice) -> Bool {
        var ok = true
        func check(_ cond: Bool, _ label: String) {
            print("\(cond ? "PASS" : "FAIL")  \(label)")
            ok = ok && cond
        }
        if name == "all" || name == "shaders" {
            _ = ShaderLibrary.make(device: device)  // exits on failure
            check(true, "shader library compiles")
        }
        if name == "all" || name == "layout" {
            check(MemoryLayout<Vertex>.stride == 48, "Vertex stride 48")
            check(MemoryLayout<FrameUniforms>.stride == 512, "FrameUniforms stride 512")
            check(MemoryLayout<ObjectUniforms>.stride == 96, "ObjectUniforms stride 96")
        }
        if name == "all" || name == "math" {
            let cam = Camera(position: SIMD3(10, 5, 3), yaw: 0.6, pitch: 0.2)
            let p = cam.position + cam.forward * 10
            let clip = cam.proj(aspect: 16 / 9) * cam.view * float4(p, 1)
            let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
            check(abs(ndc.x) < 1e-4 && abs(ndc.y) < 1e-4 && ndc.z > 0 && ndc.z < 1, "point ahead projects to NDC centre, z in 0..1 (z=\(ndc.z))")
            let north = Camera(position: .zero, yaw: 0, pitch: 0).forward
            check(abs(north.z + 1) < 1e-5 && abs(north.x) < 1e-5, "yaw 0 looks north (-Z)")
            let east = Camera(position: .zero, yaw: .pi / 2, pitch: 0).forward
            check(abs(east.x - 1) < 1e-5, "positive yaw turns toward +X")
            let nearClip = cam.proj(aspect: 1) * cam.view * float4(cam.position + cam.forward * cam.near, 1)
            let farClip = cam.proj(aspect: 1) * cam.view * float4(cam.position + cam.forward * cam.far, 1)
            check(abs(nearClip.z / nearClip.w) < 1e-3 && abs(farClip.z / farClip.w - 1) < 1e-3, "near maps to 0, far maps to 1")
        }
        if name == "all" || name == "mesh" {
            let surf = Surface(color: SIMD3(0.5, 0.5, 0.5))
            func geometryOK(_ b: MeshBuilder, _ label: String, outwardFrom center: SIMD3<Float>?) {
                var unit = true, inRange = true, outward = true
                for v in b.vertices where abs(length(SIMD3(v.normal.x, v.normal.y, v.normal.z)) - 1) > 1e-3 { unit = false }
                if b.indices.contains(where: { Int($0) >= b.vertices.count }) { inRange = false }
                if let c = center {
                    for t in stride(from: 0, to: b.indices.count, by: 3) {
                        func p(_ k: Int) -> SIMD3<Float> {
                            let v = b.vertices[Int(b.indices[t + k])].position; return SIMD3(v.x, v.y, v.z)
                        }
                        let gn = cross(p(1) - p(0), p(2) - p(0))
                        if dot(gn, (p(0) + p(1) + p(2)) / 3 - c) <= 0 { outward = false }
                    }
                }
                check(unit && inRange && outward, "\(label): \(b.vertices.count) verts, \(b.indices.count / 3) tris, unit normals=\(unit), winding outward=\(outward)")
            }
            var m = MeshBuilder(); m.box(size: SIMD3(2, 3, 4), surface: surf); geometryOK(m, "box", outwardFrom: .zero)
            m = MeshBuilder(); m.sphere(radius: 1, segments: 24, surface: surf); geometryOK(m, "sphere smooth", outwardFrom: .zero)
            m = MeshBuilder(); m.sphere(radius: 1, segments: 12, smooth: false, surface: surf); geometryOK(m, "sphere flat", outwardFrom: .zero)
            m = MeshBuilder(); m.cylinder(radiusTop: 0.5, radiusBottom: 1, height: 2, surface: surf); geometryOK(m, "cylinder", outwardFrom: SIMD3(0, 1, 0))
            m = MeshBuilder(); m.cone(radius: 1, height: 2, surface: surf); geometryOK(m, "cone", outwardFrom: SIMD3(0, 0.5, 0))
            m = MeshBuilder(); m.torus(major: 2, minor: 0.5, surface: surf); geometryOK(m, "torus", outwardFrom: nil)
            m = MeshBuilder(); m.plane(width: 4, depth: 4, grid: 4, surface: surf); geometryOK(m, "plane", outwardFrom: nil)
            // Torus winding: tube-centre-relative check (the torus is not star-shaped about the origin).
            var tor = MeshBuilder(); tor.torus(major: 2, minor: 0.5, surface: surf)
            var torusOut = true
            for t in stride(from: 0, to: tor.indices.count, by: 3) {
                func p(_ k: Int) -> SIMD3<Float> { let v = tor.vertices[Int(tor.indices[t + k])].position; return SIMD3(v.x, v.y, v.z) }
                let c = (p(0) + p(1) + p(2)) / 3
                let ringCentre = normalize(SIMD3(c.x, 0, c.z)) * 2
                if dot(cross(p(1) - p(0), p(2) - p(0)), c - ringCentre) <= 0 { torusOut = false }
            }
            check(torusOut, "torus winding outward from tube centre")
            var pl = MeshBuilder(); pl.plane(width: 4, depth: 4, grid: 2, surface: surf)
            let up = cross(SIMD3<Float>(pl.vertices[Int(pl.indices[1])].position.x - pl.vertices[Int(pl.indices[0])].position.x,
                                        pl.vertices[Int(pl.indices[1])].position.y - pl.vertices[Int(pl.indices[0])].position.y,
                                        pl.vertices[Int(pl.indices[1])].position.z - pl.vertices[Int(pl.indices[0])].position.z),
                           SIMD3<Float>(pl.vertices[Int(pl.indices[2])].position.x - pl.vertices[Int(pl.indices[0])].position.x,
                                        pl.vertices[Int(pl.indices[2])].position.y - pl.vertices[Int(pl.indices[0])].position.y,
                                        pl.vertices[Int(pl.indices[2])].position.z - pl.vertices[Int(pl.indices[0])].position.z))
            check(up.y > 0, "plane winding faces +Y")
        }
        if name == "all" || name == "noise" {
            let n = Noise(seed: 42)
            var sum: Double = 0, lo: Float = 9, hi: Float = -9
            for i in 0..<20000 {
                let v = n.fbm(Float(i % 200) * 0.37, Float(i / 200) * 0.41)
                sum += Double(v); lo = min(lo, v); hi = max(hi, v)
            }
            // Continuity must be judged at a step far below the finest octave's wavelength (1/16 here).
            var maxStep: Float = 0, prev = n.fbm(0, 3.3)
            for i in 1..<5000 {
                let v = n.fbm(Float(i) * 0.002, 3.3)
                maxStep = max(maxStep, abs(v - prev)); prev = v
            }
            print("noise checksum \(String(format: "%.6f", sum)) fbm range \(lo)...\(hi)")
            check(lo > -1.1 && hi < 1.1 && hi - lo > 0.6, "fbm stays within about -1..1 and uses the range")
            check(maxStep < 0.05, "fbm is continuous (max step \(maxStep))")
            check(Noise(seed: 1).perlin(3.3, 4.4) != Noise(seed: 2).perlin(3.3, 4.4), "different seeds differ")
            check(Noise(seed: 7).value(1.5, 2.5) == Noise(seed: 7).value(1.5, 2.5), "same seed repeats")
            let r = n.ridged(10.2, 5.5), vv = n.value(10.2, 5.5)
            check(r >= 0 && r <= 1.01 && vv >= 0 && vv <= 1, "ridged and value noise in 0..1")
        }
        if name == "all" || name == "terrain" || name == "terrain-map" {
            let t = Terrain()
            for (label, p) in [("tideStone", Layout.tideStone), ("windStone", Layout.windStone), ("summitStone", Layout.summitStone),
                               ("lighthouse", Layout.lighthouse), ("causewayStart", Layout.causewayStart), ("isletCenter", Layout.isletCenter),
                               ("dockShore", Layout.dockShore)] {
                let h = t.sampleHeight(x: p.x, z: p.z)
                check(abs(h - p.y) < 1, "\(label) ground \(String(format: "%.2f", h)) vs layout y \(p.y)")
            }
            let de = t.sampleHeight(x: Layout.dockEnd.x, z: Layout.dockEnd.z)
            check(de < -0.5, "dock end is over water (\(String(format: "%.2f", de)) m)")
            check(abs(t.sampleHeight(x: 33.3, z: -71.7) - t.height(x: 33.3, z: -71.7)) < 1.0, "cache agrees with analytic height")
            if ProcessInfo.processInfo.environment["TERRAIN_DEBUG"] != nil {
                let a = SIMD2(Layout.dockShore.x, Layout.dockShore.z), b = SIMD2(Layout.dockEnd.x, Layout.dockEnd.z)
                let dir = normalize(b - a), side = SIMD2(-dir.y, dir.x)
                for k in stride(from: 0, through: 40, by: 5) {
                    let c = a + dir * Float(k)
                    print("along dock +\(k) m: centre \(String(format: "%.2f", t.sampleHeight(x: c.x, z: c.y)))  left 6m \(String(format: "%.2f", t.sampleHeight(x: c.x + side.x * 6, z: c.y + side.y * 6)))  right 6m \(String(format: "%.2f", t.sampleHeight(x: c.x - side.x * 6, z: c.y - side.y * 6)))")
                }
            }
            let nrm = t.normal(x: 40, z: 55)
            check(abs(length(nrm) - 1) < 1e-4 && nrm.y > 0.3, "normal is unit and points upward on the ridge (y=\(nrm.y))")
            var maxSlopeOnPath: Float = 0, worstAt = ""
            for k in 0..<(Layout.lanternPath.count - 1) {
                let a = Layout.lanternPath[k], b = Layout.lanternPath[k + 1]
                var prev = t.sampleHeight(x: a.x, z: a.z)
                for s in 1...100 {
                    let q = a + (b - a) * (Float(s) / 100)
                    let h = t.sampleHeight(x: q.x, z: q.z)
                    let sl = abs(h - prev) / (length(SIMD2(b.x - a.x, b.z - a.z)) / 100)
                    if sl > maxSlopeOnPath { maxSlopeOnPath = sl; worstAt = "leg \(k) step \(s) at (\(Int(q.x)), \(Int(q.z))) h \(String(format: "%.1f", h))" }
                    prev = h
                }
            }
            print("steepest slope along the straight-line lantern path: \(String(format: "%.2f", maxSlopeOnPath)) (rise/run) \(worstAt)")
            check(maxSlopeOnPath < 1.0, "lantern path stays walkable (steepest < 1.0 rise/run; player limit is 1.19)")
            if name == "terrain-map" {
                // ASCII overview, 4 m per column: ' ' deep, '.' shallow, '~' awash, then land bands by height.
                for j in stride(from: -400, to: 260, by: 10) {
                    var row = ""
                    for i in stride(from: -300, to: 280, by: 5) {
                        let h = t.sampleHeight(x: Float(i), z: Float(j))
                        row.append(h < -8 ? " " : h < -1 ? "." : h < 0.3 ? "~" : h < 4 ? "," : h < 15 ? ":" : h < 35 ? "o" : h < 55 ? "O" : "@")
                    }
                    print(row)
                }
            }
        }
        if name == "all" || name == "input" {
            let input = Input()
            input.keyDown(Input.Key.w); input.keyDown(Input.Key.d)
            let s1 = input.sample(captured: true)
            check(abs(length(s1.move) - 1) < 1e-5 && s1.move.x > 0 && s1.move.y > 0, "W+D is a unit-length diagonal (no faster diagonal)")
            input.addMouse(dx: 100, dy: -50)
            let s2 = input.sample(captured: true)
            check(s2.look.x > 0 && s2.look.y > 0, "mouse right turns right, mouse up looks up")
            check(input.sample(captured: true).look == .zero, "mouse delta is consumed once")
            input.keyDown(Input.Key.j)
            check(input.sample(captured: false).journalPressed, "J edge is reported even when the mouse is released")
            check(input.sample(captured: false).journalPressed == false, "edge fires once")
            check(input.sample(captured: false).move == .zero, "no movement while the mouse is released")
            input.releaseAll()
            check(input.sample(captured: true).move == .zero, "releaseAll clears held keys")
        }
        if name == "all" || name == "player" {
            let scene = Scene.makeWorld(device: device)
            let dt = Game.tick
            func ground(_ p: Player) -> Float { scene.groundHeight(x: p.position.x, z: p.position.z) }
            func flat(_ v: SIMD3<Float>) -> SIMD2<Float> { SIMD2(v.x, v.z) }

            // 1. Spawn on the dock and walk forward: we end up on the beach, never in the water.
            var p = Player(position: Layout.dockEnd, yaw: Layout.spawnYaw)
            var lowest: Float = 99
            for i in 0..<(14 * 120) {       // 41 m of dock at 3.2 m/s = 13 s
                p.step(dt: dt, input: InputState(move: SIMD2(0, 1)), scene: scene)
                lowest = min(lowest, ground(p))
                if ProcessInfo.processInfo.environment["PLAYER_DEBUG"] != nil, i % 120 == 0 {
                    print("t=\(i / 120) pos=(\(p.position.x), \(p.position.y), \(p.position.z)) speed=\(p.speed) ground=\(ground(p))")
                }
            }
            check(lowest > -0.1 && distance(flat(p.position), flat(Layout.dockShore)) < 12,
                  "walking forward from spawn follows the dock to the beach without falling in (lowest ground \(String(format: "%.2f", lowest)), \(String(format: "%.1f", distance(flat(p.position), flat(Layout.dockShore)))) m from the dock's landward end)")

            // 2. The sea is a wall: from the end of the dock walk straight out to sea.
            p = Player(position: Layout.dockEnd, yaw: Layout.spawnYaw + .pi)
            lowest = 99
            for _ in 0..<(20 * 120) {
                p.step(dt: dt, input: InputState(move: SIMD2(0, 1)), scene: scene)
                lowest = min(lowest, ground(p))
            }
            check(lowest > Player.minGround - 0.05, "cannot wade out to sea (lowest ground \(String(format: "%.2f", lowest)) m)")

            // 3. A bot walks the whole lantern path and reaches the lighthouse.
            p = Player(position: Layout.dockShore, yaw: 0)
            var path = Layout.lanternPath
            path.removeFirst()
            var reachedAll = true
            var worstLeg = ""
            for (i, wp) in path.enumerated() {
                let reach: Float = (i == path.count - 1) ? 8 : 2.5     // the lighthouse is solid: stop beside it
                var t: Float = 0
                var arrived = false
                while t < 150 {
                    let d = flat(wp) - flat(p.position)
                    if length(d) < reach { arrived = true; break }
                    p.yaw = atan2(d.x, -d.y)
                    p.step(dt: dt, input: InputState(move: SIMD2(0, 1)), scene: scene)
                    t += dt
                }
                if !arrived { reachedAll = false; worstLeg = "leg \(i) stuck at (\(Int(p.position.x)), \(Int(p.position.z)))"; break }
            }
            check(reachedAll, "bot walks dock shore -> tide -> wind -> summit stone -> lighthouse \(worstLeg)")

            // 4. Walk straight at the lighthouse: stopped by the tower, not inside it.
            let lh = flat(Layout.lighthouse)
            p = Player(position: SIMD3(lh.x, Layout.lighthouse.y, lh.y + 14), yaw: 0)   // 14 m south, facing north
            p.position.y = ground(p)
            for _ in 0..<(8 * 120) { p.step(dt: dt, input: InputState(move: SIMD2(0, 1)), scene: scene) }
            let dLH = distance(flat(p.position), lh)
            check(dLH > 5.5 + Player.radius - 0.1 && dLH < 5.5 + Player.radius + 0.5, "lighthouse is solid (stopped \(String(format: "%.2f", dLH)) m from its axis)")

            // 5. Speeds: walking settles at 3.2 m/s, running at 6.5 m/s.
            p = Player(position: SIMD3(40, 34, 55), yaw: 0)
            for _ in 0..<(3 * 120) { p.step(dt: dt, input: InputState(move: SIMD2(1, 0)), scene: scene) }
            let walk = p.speed
            var r = InputState(); r.move = SIMD2(1, 0); r.run = true
            for _ in 0..<(3 * 120) { p.step(dt: dt, input: r, scene: scene) }
            check(abs(walk - 3.2) < 0.4 && abs(p.speed - 6.5) < 0.8, "walk \(String(format: "%.2f", walk)) m/s, run \(String(format: "%.2f", p.speed)) m/s (on a slope)")

            // 5b. Gait: walking is a natural ~2.2 steps/s; running lengthens the stride so cadence rises only ~1.4x, not 2x.
            func cadence(run: Bool) -> Float {
                let q = Player(position: SIMD3(Layout.dockShore.x, Layout.dockShore.y, Layout.dockShore.z), yaw: 3.0)
                var pl = q
                var input = InputState(); input.move = SIMD2(0, 1); input.run = run
                pl.position.y = scene.groundHeight(x: pl.position.x, z: pl.position.z)
                for _ in 0..<(2 * 120) { pl.step(dt: dt, input: input, scene: scene) }          // settle to full speed
                let start = pl.stepCount
                var travelled: Float = 0, last = SIMD2(pl.position.x, pl.position.z)
                for _ in 0..<(6 * 120) {
                    pl.step(dt: dt, input: input, scene: scene)
                    let now = SIMD2(pl.position.x, pl.position.z); travelled += distance(now, last); last = now
                }
                _ = travelled
                return Float(pl.stepCount - start) / 6
            }
            let walkCadence = cadence(run: false), runCadence = cadence(run: true)
            check(walkCadence > 1.8 && walkCadence < 2.6, "walking cadence is natural (\(String(format: "%.2f", walkCadence)) steps/s)")
            check(runCadence / walkCadence > 1.2 && runCadence / walkCadence < 1.6, "running is a different gait, not 2x walking (\(String(format: "%.2f", runCadence)) vs \(String(format: "%.2f", walkCadence)) steps/s = \(String(format: "%.2f", runCadence / walkCadence))x)")
            check(Player.stepLength(speed: Player.runSpeed) > 1.4 * Player.stepLength(speed: Player.walkSpeed), "the run stride is much longer than the walk stride")

            // 6. Frame-rate independence: the same 4 s of "walk forward" at 30, 60 and 144 fps covers the same ground.
            var distances: [Float] = []
            for fps in [30.0, 60.0, 144.0] {
                let g = Game(scene: scene)
                g.player = Player(position: SIMD3(Layout.dockShore.x, Layout.dockShore.y, Layout.dockShore.z), yaw: 3.0)
                var input = InputState(); input.move = SIMD2(0, 1)
                var now = 1000.0
                let start = SIMD2(g.player.position.x, g.player.position.z)
                for _ in 0..<Int(fps * 4) { now += 1 / fps; g.advance(now: now, input: input) }
                distances.append(distance(SIMD2(g.player.position.x, g.player.position.z), start))
            }
            check((distances.max()! - distances.min()!) / distances.max()! < 0.03, "movement is frame-rate independent (30/60/144 fps: \(distances.map { String(format: "%.2f", $0) }) m)")
        }
        if name == "all" || name == "audio" {
            let sr: Float = 44100
            let n = Int(sr) * 10
            func renderSeconds(_ setup: (AmbienceSynth) -> Void) -> [Float] {
                let synth = AmbienceSynth(sampleRate: sr)
                setup(synth)
                var l = [Float](repeating: 0, count: n), r = [Float](repeating: 0, count: n)
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    // Render in 512-frame blocks like the real audio callback does.
                    var done = 0
                    while done < n {
                        let c = min(512, n - done)
                        synth.render(frames: c, left: lp.baseAddress! + done, right: rp.baseAddress! + done)
                        done += c
                    }
                } }
                return l
            }
            func rms(_ a: ArraySlice<Float>) -> Float { (a.reduce(0) { $0 + $1 * $1 } / Float(a.count)).squareRoot() }
            let wind = renderSeconds { $0.windGain = 0.6; $0.surfGain = 0 }
            let surf = renderSeconds { $0.windGain = 0; $0.surfGain = 0.8 }
            let everything = renderSeconds { $0.windGain = 1; $0.surfGain = 1; $0.master = 1; $0.stepSurface = .wood; $0.stepCounter = 1 }
            check(!wind.contains { !$0.isFinite } && !surf.contains { !$0.isFinite }, "wind and surf contain no NaN/inf")
            check(rms(wind[...]) > 0.005 && rms(wind[...]) < 0.4, "wind level is audible but not loud (rms \(String(format: "%.3f", rms(wind[...]))))")
            check(rms(surf[...]) > 0.005 && rms(surf[...]) < 0.4, "surf level is audible but not loud (rms \(String(format: "%.3f", rms(surf[...]))))")
            check((everything.map { abs($0) }.max() ?? 2) < 1.0, "everything at full volume never clips (peak \(String(format: "%.2f", everything.map { abs($0) }.max() ?? 0)))")
            // Surf should swell: compare the loudest and quietest second.
            let secs = (0..<10).map { rms(surf[($0 * Int(sr))..<(($0 + 1) * Int(sr))]) }
            check(secs.max()! > 1.5 * secs.min()!, "surf swells and recedes (loudest second \(String(format: "%.3f", secs.max()!)) vs quietest \(String(format: "%.3f", secs.min()!)))")
            // Surf must not sound like static. White noise has |x[n]-x[n-1]| / |x[n]| of about 1.41; a signal whose energy
            // sits under ~1 kHz has about 0.14. (The old surf, with a cutoff up to 4 kHz, was far hissier.)
            let surfTone = renderSeconds { $0.windGain = 0; $0.surfGain = 0.8 }
            var dSq: Float = 0, xSq: Float = 0
            for i in 1..<surfTone.count { let d = surfTone[i] - surfTone[i - 1]; dSq += d * d; xSq += surfTone[i] * surfTone[i] }
            let hiss = (dSq / xSq).squareRoot()
            check(hiss < 0.35, "surf is a low wash, not static (hissiness \(String(format: "%.2f", hiss)); white noise is about 1.41)")

            // Footsteps.
            func step(_ surface: SurfaceKind, run: Bool, count: Int = 1) -> [Float] {
                let synth = AmbienceSynth(sampleRate: sr)
                synth.windGain = 0; synth.surfGain = 0; synth.master = 1
                var l = [Float](repeating: 0, count: Int(sr) * 2 * count), r = l
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    for k in 0..<count {
                        synth.stepSurface = surface; synth.stepRun = run; synth.stepCounter += 1
                        synth.render(frames: Int(sr) * 2, left: lp.baseAddress! + k * Int(sr) * 2, right: rp.baseAddress! + k * Int(sr) * 2)
                    }
                } }
                return l
            }
            func peak(_ x: ArraySlice<Float>) -> Float { x.map { abs($0) }.max() ?? 0 }
            /// Seconds until the envelope (peak per 5 ms window) falls below 15 % of the loudest window.
            func ringOut(_ x: [Float]) -> Float {
                let w = Int(sr * 0.005)
                let env = stride(from: 0, to: x.count - w, by: w).map { peak(x[$0..<$0 + w]) }
                let top = env.max() ?? 1
                let iTop = env.firstIndex(of: top) ?? 0
                let end = (iTop..<env.count).first { env[$0] < 0.15 * top } ?? env.count
                return Float(end) * 0.005
            }
            for surface in [SurfaceKind.grass, .sand, .earth, .rock, .stone, .wood] {
                let walk = step(surface, run: false)
                check(peak(walk[0..<Int(sr * 0.001)]) < 0.3 * peak(walk[0..<Int(sr * 0.4)]) && !walk.contains { !$0.isFinite }, "\(surface) step has a soft attack (first millisecond is not the peak) and is finite")
                check(peak(walk[Int(sr * 1.5)...]) < 1e-4, "\(surface) step dies away completely")
            }
            let walkGrass = step(.grass, run: false), runGrass = step(.grass, run: true)
            check(ringOut(walkGrass) >= 0.12, "a grass footstep rings out for at least 0.12 s, not a click (\(String(format: "%.2f", ringOut(walkGrass))) s)")
            let walkStone = step(.stone, run: false), runStone = step(.stone, run: true)
            check(peak(runStone[...]) > 1.2 * peak(walkStone[...]) && ringOut(runStone) < ringOut(walkStone),
                  "a run step is harder and shorter than a walk step (peak \(String(format: "%.2f", peak(walkStone[...]))) -> \(String(format: "%.2f", peak(runStone[...]))), ring-out \(String(format: "%.2f", ringOut(walkStone))) -> \(String(format: "%.2f", ringOut(runStone))) s)")
            // The walk has a second, softer hit (the toe) after the heel.
            let heel = peak(walkGrass[0..<Int(sr * 0.06)]), toe = peak(walkGrass[Int(sr * 0.075)..<Int(sr * 0.2)])
            check(toe > 0.15 * heel && toe < heel, "walking is heel then toe (toe is \(Int(100 * toe / heel)) % of the heel)")
            // Consecutive steps differ.
            let two = step(.grass, run: false, count: 2)
            let first = peak(two[0..<Int(sr * 2)]), second = peak(two[Int(sr * 2)...])
            check(abs(first - second) / max(first, second) > 0.01, "consecutive steps are not identical (peaks \(String(format: "%.3f", first)) vs \(String(format: "%.3f", second)))")
        }
        if name == "all" || name == "surface" {
            let scene = Scene.makeWorld(device: device)
            check(scene.surface(x: Layout.dockEnd.x, z: Layout.dockEnd.z) == .wood, "dock is wood")
            check(scene.surface(x: Layout.summitStone.x, z: Layout.summitStone.z + 30) != .wood, "hillside is not wood")
            let shoreNear = scene.shoreDistance(x: Layout.tideStone.x, z: Layout.tideStone.z)
            let shoreFar = scene.shoreDistance(x: Layout.lighthouse.x, z: Layout.lighthouse.z)
            check(shoreNear < 120 && shoreFar >= 159, "shore distance: tide stone \(Int(shoreNear)) m, lighthouse \(Int(shoreFar)) m (capped at 160)")
        }
        if name == "all" || name == "frustum" {
            let cam = Camera(position: .zero, yaw: 0, pitch: 0)      // looking north (-Z)
            let f = Frustum(viewProj: cam.proj(aspect: 16 / 9) * cam.view)
            check(f.intersects(min: SIMD3(-1, -1, -21), max: SIMD3(1, 1, -19)), "box 20 m ahead is visible")
            check(!f.intersects(min: SIMD3(-1, -1, 19), max: SIMD3(1, 1, 21)), "box behind the camera is culled")
            check(!f.intersects(min: SIMD3(100, -1, -11), max: SIMD3(102, 1, -9)), "box far off to the side is culled")
            check(!f.intersects(min: SIMD3(-1, -1, -9000), max: SIMD3(1, 1, -8500)), "box beyond the far plane is culled")
            check(f.intersects(min: SIMD3(-50, -50, -50), max: SIMD3(50, 50, 50)), "a box containing the camera is visible")
            let ortho = Frustum(viewProj: orthographic(left: -10, right: 10, bottom: -10, top: 10, near: 0, far: 100)
                                * lookAt(eye: SIMD3(0, 0, 0), target: SIMD3(0, 0, -1), up: SIMD3(0, 1, 0)))
            check(ortho.intersects(min: SIMD3(-1, -1, -51), max: SIMD3(1, 1, -49)) && !ortho.intersects(min: SIMD3(11, 0, -50), max: SIMD3(13, 1, -49)),
                  "orthographic (sun) frustum culls by box edges")
        }
        if name == "all" || name == "props" {
            var ico = MeshBuilder()
            ico.icosphere(subdivisions: 2, radius: { _ in 1 }, surface: Surface(color: SIMD3(0.5, 0.5, 0.5)))
            var outward = true
            for t in stride(from: 0, to: ico.indices.count, by: 3) {
                func q(_ k: Int) -> SIMD3<Float> { let v = ico.vertices[Int(ico.indices[t + k])].position; return SIMD3(v.x, v.y, v.z) }
                if dot(cross(q(1) - q(0), q(2) - q(0)), q(0) + q(1) + q(2)) <= 0 { outward = false }
            }
            check(ico.indices.count / 3 == 320 && outward, "icosphere level 2 has 320 triangles, all wound outward (\(ico.indices.count / 3))")
            let r1 = Props.rock(seed: 5, size: 1), r2 = Props.rock(seed: 5, size: 1), r3 = Props.rock(seed: 6, size: 1)
            check(r1.vertices.first?.position == r2.vertices.first?.position && r1.vertices.first?.position != r3.vertices.first?.position,
                  "rocks are deterministic per seed and differ between seeds")
            let lantern = Props.stoneLantern()
            var top: Float = 0
            for v in lantern.body.vertices { top = max(top, v.position.y) }
            check(top > 1.9 && top < 2.2 && !lantern.core.isEmpty, "stone lantern is about 2 m tall with a separate core (top \(String(format: "%.2f", top)) m)")
            let tree = Props.cypress(seed: 3, height: 10)
            var treeTop: Float = 0
            for v in tree.vertices { treeTop = max(treeTop, v.position.y) }
            check(treeTop > 9 && treeTop < 13, "cypress of height 10 is about 10 m tall (top \(String(format: "%.1f", treeTop)) m)")
        }
        if name == "all" || name == "interaction" {
            let lo = SIMD3<Float>(-1, 0, -1), hi = SIMD3<Float>(1, 3, 1)
            check(Interaction.rayBox(origin: SIMD3(0, 1.5, 5), dir: SIMD3(0, 0, -1), min: lo, max: hi).map { abs($0 - 4) < 1e-4 } ?? false, "ray straight at a box hits its near face (4 m)")
            check(Interaction.rayBox(origin: SIMD3(3, 1.5, 5), dir: SIMD3(0, 0, -1), min: lo, max: hi) == nil, "ray passing beside the box misses")
            check(Interaction.rayBox(origin: SIMD3(0, 1.5, 5), dir: SIMD3(0, 0, 1), min: lo, max: hi) == nil, "ray pointing away misses (no hits behind the origin)")
            check(Interaction.rayBox(origin: SIMD3(0, 1.5, 0), dir: SIMD3(1, 0, 0), min: lo, max: hi) == 0, "ray starting inside the box reports distance 0")
            check(Interaction.rayBox(origin: SIMD3(0, 5, 5), dir: SIMD3(0, 0, -1), min: lo, max: hi) == nil, "axis-parallel ray above the box misses")
            let near = Interactable(id: "near", min: lo, max: hi, prompt: "n")
            var far = Interactable(id: "far", min: SIMD3(-1, 0, -11), max: SIMD3(1, 3, -9), prompt: "f"); far.reach = 20
            check(Interaction.pick(origin: SIMD3(0, 1.5, 4), dir: SIMD3(0, 0, -1), in: [far, near])?.id == "near", "pick returns the nearest of two boxes on the ray (near is 3 m away, far is 13 m)")
            var tooFar = near; tooFar.reach = 2
            check(Interaction.pick(origin: SIMD3(0, 1.5, 5), dir: SIMD3(0, 0, -1), in: [tooFar]) == nil, "an object beyond its reach is not hoverable")
            var off = near; off.enabled = false
            check(Interaction.pick(origin: SIMD3(0, 1.5, 5), dir: SIMD3(0, 0, -1), in: [off]) == nil, "disabled interactables are ignored")
        }
        if name == "all" || name == "animator" {
            let a = Animator()
            var value: Float = -1, done = false
            a.tween(delay: 0.5, duration: 1, ease: .linear, apply: { value = $0 }, completion: { done = true })
            for _ in 0..<60 { a.update(1 / 120) }              // 0.5 s: still in the delay
            check(value == -1, "tween has not started during its delay")
            for _ in 0..<60 { a.update(1 / 120) }              // 1.0 s: 0.5 s into the tween
            check(abs(value - 0.5) < 0.02 && !done, "tween is halfway after delay + half its duration (value \(String(format: "%.2f", value)))")
            for _ in 0..<70 { a.update(1 / 120) }
            check(value == 1 && done && a.isIdle, "tween ends exactly at 1 and calls completion once")
            var order: [Int] = []
            a.after(0.3) { order.append(2) }
            a.after(0.1) { order.append(1) }
            a.after(0.1) { a.after(0.1) { order.append(3) }; order.append(11) }     // a completion can schedule more work
            for _ in 0..<60 { a.update(1 / 120) }
            check(order == [1, 11, 3, 2], "after() actions fire in time order (0.1, 0.1, nested 0.2, 0.3), nested ones included: \(order)")
            check(Ease.inOutCubic.apply(0) == 0 && Ease.inOutCubic.apply(1) == 1 && abs(Ease.inOutCubic.apply(0.5) - 0.5) < 1e-6, "ease curve fixes its endpoints and midpoint")
        }
        if name == "all" || name == "journal" {
            var j = JournalState()
            check(j.collectedPages.isEmpty, "journal starts empty")
            j.collect(3); j.collect(1)
            check(j.collectedPages.map(\.number) == [1, 3] && j.collectedPages[j.current].number == 1, "pages are ordered by number and the newest collected page is shown")
            j.flip(1); check(j.collectedPages[j.current].number == 3, "flip forward")
            j.flip(1); check(j.collectedPages[j.current].number == 3, "flipping past the end stays on the last page")
            j.flip(-5); check(j.current == 0, "flipping past the start stays on the first page")
            check(JournalContent.pages.count == 8 && JournalContent.pages.map(\.number) == Array(1...8) && JournalContent.pages.allSatisfy { !$0.text.isEmpty }, "all eight journal pages (4 Ilse, 4 Oren) exist, numbered 1-8, with text")
        }
        if name == "all" || name == "chimes" {
            let sr: Float = 44100
            func render(_ kind: ChimeKind, seconds: Float) -> [Float] {
                let synth = AmbienceSynth(sampleRate: sr)
                synth.windGain = 0; synth.surfGain = 0; synth.master = 1
                synth.play(kind)
                let n = Int(sr * seconds)
                var l = [Float](repeating: 0, count: n), r = [Float](repeating: 0, count: n)
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    var d = 0
                    while d < n { let c = min(512, n - d); synth.render(frames: c, left: lp.baseAddress! + d, right: rp.baseAddress! + d); d += c }
                } }
                return l
            }
            /// Goertzel: the signal's energy at one frequency (a one-bin DFT).
            func energy(_ x: [Float], hz: Float, range: Range<Int>) -> Float {
                let w = 2 * Float.pi * hz / sr, c = 2 * cos(w)
                var s1: Float = 0, s2: Float = 0
                for i in range { let s0 = x[i] + c * s1 - s2; s2 = s1; s1 = s0 }
                return s1 * s1 + s2 * s2 - c * s1 * s2
            }
            for (kind, hz, label) in [(ChimeKind.tide, Float(293.66), "tide D4"), (.wind, 440.0, "wind A4"), (.stone, 587.33, "stone D5")] {
                let x = render(kind, seconds: 3)
                let atNote = energy(x, hz: hz, range: 0..<Int(sr))
                let off = energy(x, hz: hz * 1.12, range: 0..<Int(sr))
                check(atNote > 20 * off, "\(label) rings at its pitch (energy ratio vs a whole tone off: \(Int(atNote / max(off, 1e-9)))x)")
                let early = x[0..<Int(sr * 0.5)].map { abs($0) }.max() ?? 0
                let late = x[Int(sr * 2.8)...].map { abs($0) }.max() ?? 0
                check(early < 0.95 && late < early * 0.5 && !x.contains { !$0.isFinite }, "\(label) decays and stays finite (peak \(String(format: "%.2f", early)) -> \(String(format: "%.3f", late)))")
            }
            let fail = render(.fail, seconds: 2), tide = render(.tide, seconds: 2)
            check((fail.map { abs($0) }.max() ?? 1) < (tide.map { abs($0) }.max() ?? 0), "the fail chime is quieter than a success chime")
            let rumble = render(.rumble, seconds: 6)
            check((rumble.map { abs($0) }.max() ?? 0) > 0.02 && !rumble.contains { !$0.isFinite }, "rumble is audible and finite")
            let ignite = render(.ignite, seconds: 4)
            check((ignite.map { abs($0) }.max() ?? 2) < 1.0 && (ignite.map { abs($0) }.max() ?? 0) > 0.1, "ignite chord is clearly audible and never clips (peak \(String(format: "%.2f", ignite.map { abs($0) }.max() ?? 0)))")
        }
        if name == "all" || name == "puzzle" {
            func freshGame() -> Game { Game(scene: Scene.makeWorld(device: device)) }
            func chimes(_ events: [GameEvent]) -> [ChimeKind] { events.compactMap { if case .chime(let k) = $0 { return k } else { return nil } } }
            func lit(_ g: Game) -> [Bool] { StoneID.allCases.map { g.state.has("lit_\($0.name)") } }

            // 1. Wrong first stone: fail chime, nothing lights, and after the delay everything is reset.
            var g = freshGame()
            g.puzzle.strike(.wind)
            check(chimes(g.drainEvents()) == [.wind, .fail] && lit(g) == [false, false, false], "striking the wind stone first rings, then fails; nothing lights")
            g.simulate(seconds: 1)
            g.puzzle.strike(.tide)
            check(lit(g) == [true, false, false], "after the reset delay the puzzle accepts the right first stone")

            // 2. Right then wrong: everything resets after 0.8 s.
            g = freshGame()
            g.puzzle.strike(.tide); g.simulate(seconds: 1)
            g.puzzle.strike(.summit)
            check(lit(g) == [true, false, false], "a wrong stone does not light, but the earlier one stays lit until the reset")
            g.simulate(seconds: 0.5)
            g.puzzle.strike(.wind)                              // during the reset delay: ignored
            check(g.puzzle.sequence == [.tide], "strikes during the reset delay are ignored")
            g.simulate(seconds: 0.5)
            check(lit(g) == [false, false, false] && g.puzzle.sequence.isEmpty, "0.8 s after a mistake all stones dim and the sequence clears")

            // 3. Striking the same stone twice is wrong.
            g = freshGame()
            g.puzzle.strike(.tide); g.puzzle.strike(.tide)
            check(g.puzzle.sequence == [.tide] && chimes(g.drainEvents()).suffix(1) == [.fail], "striking the same stone twice fails")

            // 4. The right order solves it and runs the whole sequence.
            g = freshGame()
            for id in LighthousePuzzle.order { g.puzzle.strike(id); g.simulate(seconds: 0.7) }
            check(g.state.has("solved") && lit(g) == [true, true, true], "tide -> wind -> stone solves the puzzle")
            let evs = chimes(g.drainEvents())
            check(evs.prefix(4) == [.tide, .wind, .stone, .ignite], "success chimes: tide, wind, stone, then the ignition chord (\(evs))")
            check(!g.state.has("lighthouseLit") && !g.state.has("causewayUp"), "the lighthouse is not lit the instant you solve it")
            g.simulate(seconds: LighthousePuzzle.Timing.total + 1)
            check(g.state.has("lighthouseLit") && g.state.has("causewayUp"), "within \(Int(LighthousePuzzle.Timing.total) + 1) s the lighthouse is lit and the causeway is up")
            check(chimes(g.drainEvents()).contains(.rumble), "the causeway raised with a rumble")
            check(StoneID.allCases.allSatisfy { id in g.scene.items.first { $0.name == "beam_\(id.name)" }.map { !$0.hidden } ?? false }, "all three beams are visible")
            check((g.scene.items.first { $0.name == "lighthouse_lens" }?.uniforms.emissive.w ?? 0) > 39, "the lens blazes (emissive \(g.scene.items.first { $0.name == "lighthouse_lens" }?.uniforms.emissive.w ?? 0))")

            // 5. Solved is permanent: more strikes only ring.
            g.puzzle.strike(.summit); g.puzzle.strike(.tide); g.simulate(seconds: 2)
            check(lit(g) == [true, true, true] && g.state.has("solved") && chimes(g.drainEvents()).filter { $0 == .fail }.isEmpty, "after solving, further strikes never un-solve it")

            // 6. The causeway is walkable only once it has risen.
            func walkNorth(_ game: Game) -> Float {
                let plan = PuzzleProps.causewayPlan(terrain: game.scene.terrain)
                game.player = Player(position: SIMD3(plan.start.x, 1.5, plan.start.y), yaw: atan2(plan.dir.x, -plan.dir.y))   // player yaw: forward = (sin, -cos)
                game.player.position.y = game.scene.groundHeight(x: plan.start.x, z: plan.start.y)
                var input = InputState(); input.move = SIMD2(0, 1)
                game.simulate(seconds: 30, input: input)
                return distance(SIMD2(game.player.position.x, game.player.position.z), SIMD2(Layout.isletCenter.x, Layout.isletCenter.z))
            }
            let before = walkNorth(freshGame()), after = walkNorth(g)
            check(before > 50, "before solving, you cannot walk out to the islet (still \(Int(before)) m from it)")
            check(after < 12 && g.player.position.y > 1.0, "after solving, you walk the causeway onto the islet (\(Int(after)) m from its centre, standing at y \(String(format: "%.1f", g.player.position.y)))")
        }
        if name == "all" || name == "interact" {
            func freshGame() -> Game { Game(scene: Scene.makeWorld(device: device)) }
            // Hover: stand where the tide stone is faced and look at it.
            var g = freshGame()
            let id = StoneID.tide
            let toward = normalize(SIMD2(id.approachFrom.x - id.position.x, id.approachFrom.z - id.position.z))
            let stand = SIMD2(id.position.x, id.position.z) + toward * 2.6
            let look = SIMD2(-toward.x, -toward.y)
            g.player = Player(position: SIMD3(stand.x, id.position.y, stand.y), yaw: atan2(look.x, -look.y))
            g.player.pitch = 0.05
            g.updateHover()
            check(g.hovered?.id == "stone_tide", "looking at the tide stone from 2.6 m hovers it (\(g.hovered?.id ?? "nothing"))")
            g.player.yaw += 1.2; g.updateHover()
            check(g.hovered == nil, "looking away un-hovers it")
            g.player.yaw -= 1.2
            g.player = Player(position: SIMD3(stand.x + toward.x * 6, id.position.y, stand.y + toward.y * 6), yaw: atan2(look.x, -look.y))
            g.updateHover()
            check(g.hovered == nil, "from 8.6 m away the stone is out of reach")

            // Clicking through the real input path strikes the stone.
            g = freshGame()
            g.player = Player(position: SIMD3(stand.x, id.position.y, stand.y), yaw: atan2(look.x, -look.y)); g.player.pitch = 0.05
            var click = InputState(); click.click = true
            g.advance(now: 100, input: InputState()); g.advance(now: 100.02, input: click)
            check(g.state.has("lit_tide"), "a click on the hovered stone strikes it")

            // Pages: collecting hides the page, opens the journal, disables the interactable.
            g = freshGame()
            g.activate("page_1")
            check(g.journal.isOpen && g.journal.collectedPages.map(\.number) == [1], "collecting page 1 opens the journal on it")
            check(g.scene.items.first { $0.name == "page_1" }?.hidden == true && g.interactables.first { $0.id == "page_1" }?.enabled == false, "the collected page disappears from the world")
            check(g.drainEvents().contains(.pageCollected(1)), "a pageCollected event is emitted")
            g.updateHover(); check(g.hovered == nil, "nothing is hoverable while the journal is open")
            g.toggleJournal(); check(!g.journal.isOpen, "J closes the journal")

            // The lens does nothing until the causeway is up (the full world-travel tests are in `worlds`).
            g = freshGame()
            g.activate("lens"); g.simulate(seconds: 2.5)
            check(!g.state.has("lensTouched") && g.whiteout == 0 && g.world == .varrow, "the lens is inert before the puzzle is solved")

            // Page positions are on the ground and reachable.
            g = freshGame()
            for n in 1...4 {
                let p = PuzzleProps.pagePosition(n, terrain: g.scene.terrain)
                let gnd = g.scene.groundHeight(x: p.x, z: p.z)
                check(p.y >= gnd - 0.01 && p.y - gnd < 0.7, "page \(n) lies on the ground (\(String(format: "%.2f", p.y - gnd)) m above it)")
            }
        }
        if name == "all" || name == "feedback" {
            let tmp = NSTemporaryDirectory() + "lw-feedback-\(getpid())"
            setenv("LANTERNWRIGHT_FEEDBACK_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_FEEDBACK_DIR") }
            check(FeedbackStore.loadAll().isEmpty, "feedback store starts empty")
            try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
            try? Data([1, 2, 3]).write(to: FeedbackStore.pendingScreenshotURL)
            let game = Game(scene: Scene.makeWorld(device: device))
            game.puzzle.strike(.tide)
            let first = try? FeedbackStore.save(text: "  The surf is much better!  ", context: game.feedbackContext(extra: ["note": "test"]))
            let second = try? FeedbackStore.save(text: "second, \"quoted\" and\nmultiline", context: ["k": "v"])
            let all = FeedbackStore.loadAll()
            check(all.count == 2 && all[0].text == "The surf is much better!" && all[1].text.contains("\"quoted\"") && all[1].text.contains("\n"), "entries round-trip through the JSONL file (trimmed, quotes and newlines intact)")
            check(first?.screenshot != nil && FileManager.default.fileExists(atPath: FeedbackStore.screenshotURL(id: first!.id).path) && second?.screenshot == nil, "the pending screenshot is attached to the next entry only")
            check(all[0].context["puzzle flags"]?.contains("lit_tide") == true && all[0].context["position"] != nil && all[0].context["note"] == "test", "context carries position and puzzle flags")
            check(first?.id != second?.id, "entries saved in the same second still get distinct ids")
            let listing = FeedbackStore.formatted(all)
            check(listing.contains("The surf is much better!") && listing.contains("puzzle flags") && listing.contains(".png"), "--feedback listing shows text, context and screenshot path")
            check(!game.drainEvents().contains(.feedbackRequested), "no feedback event unless F is pressed")
            var pressF = InputState(); pressF.feedbackPressed = true
            game.advance(now: 5, input: InputState()); game.advance(now: 5.01, input: pressF)
            check(game.drainEvents().contains(.feedbackRequested), "pressing F emits feedbackRequested")
        }
        if name == "all" || name == "save" {
            let tmp = NSTemporaryDirectory() + "lw-save-\(getpid())"
            setenv("LANTERNWRIGHT_SAVE_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_SAVE_DIR") }
            check(SaveStore.load() == nil, "no save at first")
            let g = Game(scene: Scene.makeWorld(device: device))
            g.activate("page_1"); g.activate("page_3"); g.toggleJournal()
            g.puzzle.forceSolved(); g.state.set("lensTouched")
            g.player = Player(position: SIMD3(Layout.tideStone.x + 3, Layout.tideStone.y, Layout.tideStone.z + 3), yaw: 1.25)
            g.player.position.y = g.scene.groundHeight(x: g.player.position.x, z: g.player.position.z)
            g.player.pitch = -0.2
            try? SaveStore.save(g.makeSave())
            check(FileManager.default.fileExists(atPath: SaveStore.url.path) && !FileManager.default.fileExists(atPath: SaveStore.directory.appendingPathComponent("save.json.tmp").path), "saving writes save.json and leaves no temp file")

            let h = Game(scene: Scene.makeWorld(device: device))
            if let s = SaveStore.load() { h.restore(s) }
            check(h.state.has("solved") && h.state.has("lighthouseLit") && h.state.has("causewayUp") && h.state.has("lensTouched"), "puzzle progress is restored")
            check(h.journal.collectedPages.map(\.number) == [1, 3], "collected pages are restored")
            check(h.scene.items.first { $0.name == "page_1" }?.hidden == true && h.scene.items.first { $0.name == "page_2" }?.hidden == false, "collected pages are gone from the world, others remain")
            check(distance(h.player.position, g.player.position) < 0.05 && abs(h.player.yaw - 1.25) < 1e-4 && abs(h.player.pitch + 0.2) < 1e-4, "position and view direction are restored")
            check(!h.journal.isOpen && h.whiteout == 0, "loading does not reopen the journal or replay the ending")
            check(h.scene.walkables[h.scene.causewayIndex!].enabled, "the causeway is walkable again after loading a solved game")
            check((h.scene.items.first { $0.name == "lighthouse_lens" }?.uniforms.emissive.w ?? 0) > 39, "the lens is blazing after loading")

            // Robustness: corrupt, future-version and out-of-world saves must never crash or strand the player.
            try? "{ not json".write(to: SaveStore.url, atomically: true, encoding: .utf8)
            check(SaveStore.load() == nil, "a corrupt save is ignored")
            var future = g.makeSave(); future.version = 99
            try? SaveStore.save(future)
            check(SaveStore.load() == nil, "a save from a newer version is ignored")
            var sea = g.makeSave(); sea.position = [175, 0.8, 330]       // open sea
            let k = Game(scene: Scene.makeWorld(device: device)); k.restore(sea)
            check(distance(SIMD2(k.player.position.x, k.player.position.z), SIMD2(Layout.dockEnd.x, Layout.dockEnd.z)) < 1, "a saved position in the open sea falls back to the spawn")
            SaveStore.delete(); check(SaveStore.load() == nil, "delete removes the save")
        }
        if name == "all" || name == "settings" {
            var bad = Settings()
            bad.sensitivity = .nan; bad.volume = 7; bad.renderScale = 0.01
            let c = bad.clamped()
            check(c.sensitivity == 0.0022 && c.volume == 1 && c.renderScale == 0.5, "non-finite and out-of-range settings are clamped to legal values")
            var s = Settings(); s.sensitivity = 0.004; s.invertY = true; s.volume = 0.25; s.renderScale = 0.75
            let back = (try? JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s)))
            check(back == s, "settings round-trip through JSON")
            check(Settings().clamped() == Settings(), "the defaults are already within range")
        }
        if name == "all" || name == "birds" {
            let scene = Scene.makeWorld(device: device)
            check((0..<Birds.count).allSatisfy { scene.has("bird_\($0)") }, "all \(Birds.count) gulls exist in the scene")
            var lowest: Float = 1e9, worstHeading: Float = 0
            for k in 0..<Birds.count {
                for step in 0..<400 {
                    let t = Float(step) * 0.5
                    let p = Birds.pose(k, time: t), q = Birds.pose(k, time: t + 0.05)
                    lowest = min(lowest, p.position.y - scene.groundHeight(x: p.position.x, z: p.position.z))
                    let v = SIMD2(q.position.x - p.position.x, q.position.z - p.position.z)
                    var diff = abs(atan2(v.x, v.y) - p.heading)
                    if diff > .pi { diff = 2 * .pi - diff }
                    worstHeading = max(worstHeading, diff)
                }
            }
            check(lowest > 6, "no gull ever flies lower than 6 m above ground or sea (lowest \(String(format: "%.1f", lowest)) m)")
            check(worstHeading < 0.12, "every gull faces the way it flies (worst heading error \(String(format: "%.3f", worstHeading)) rad)")
            check(Birds.pose(3, time: 17.5).position == Birds.pose(3, time: 17.5).position, "flight paths are deterministic")
            let g = Game(scene: scene)
            let before = scene.items.first { $0.name == "bird_0" }!.uniforms.model
            g.simulate(seconds: 2)
            check(scene.items.first { $0.name == "bird_0" }!.uniforms.model != before, "gulls move as the game runs")
        }
        if name == "all" || name == "worlds" {
            let scenes = Dictionary(uniqueKeysWithValues: WorldKind.allCases.map { ($0, Scene.make($0, device: device)) })
            check(scenes.count == WorldKind.allCases.count && scenes.values.allSatisfy { !$0.items.isEmpty }, "every world builds a non-empty scene")
            let glass = scenes[.glassWood]!

            // The Glass Wood's ground.
            let arrival = GlassLayout.arrival
            check(abs(glass.terrain.sampleHeight(x: arrival.x, z: arrival.z) - arrival.y) < 0.6 && arrival.y > 2, "the arrival pad is dry land at its layout height (\(String(format: "%.1f", arrival.y)) m)")
            let poolDepth = glass.terrain.sampleHeight(x: GlassTerrain.pool.x, z: GlassTerrain.pool.y)
            check(poolDepth < -1, "the pool in the middle is a water-filled hollow (\(String(format: "%.1f", poolDepth)) m)")
            var lowestOnPath: Float = 99, steepest: Float = 0
            for k in 0..<(GlassLayout.path.count - 1) {
                let a = GlassLayout.path[k], b = GlassLayout.path[k + 1]
                let len = length(SIMD2(b.x - a.x, b.z - a.z))
                var prev = glass.terrain.sampleHeight(x: a.x, z: a.z)
                for i in 1...80 {
                    let q = a + (b - a) * (Float(i) / 80)
                    let h = glass.terrain.sampleHeight(x: q.x, z: q.z)
                    lowestOnPath = min(lowestOnPath, h)
                    steepest = max(steepest, abs(h - prev) / (len / 80)); prev = h
                }
            }
            check(lowestOnPath > 1.0, "the whole route stays on dry land (lowest \(String(format: "%.1f", lowestOnPath)) m)")
            check(steepest < 1.0, "the route is walkable (steepest \(String(format: "%.2f", steepest)) rise/run)")
            for (label, pad) in [("mirror court", GlassLayout.mirrorCourt), ("chime ring", GlassLayout.chimeRing), ("altar", GlassLayout.altar), ("junction", GlassLayout.junction)] {
                check(abs(glass.terrain.sampleHeight(x: pad.x, z: pad.z) - pad.y) < 0.6 && pad.y > 1.5, "\(label) sits on level dry ground at \(String(format: "%.1f", pad.y)) m")
            }

            // Travelling: lens -> Glass Wood -> return -> Varrow.
            let g = Game(scenes: scenes)
            g.puzzle.forceSolved()
            check(g.world == .varrow && g.interactables.contains { $0.id == "lens" }, "the game starts in Varrow with its own interactables")
            g.activate("lens")
            check(g.isTraveling && g.world == .varrow, "touching the lens starts the fade, still in Varrow")
            var input = InputState(); input.move = SIMD2(0, 1)
            let startPos = g.player.position
            g.simulate(seconds: 0.5, input: input)
            check(distance(g.player.position, startPos) < 0.05, "the player stands still while the world folds")
            g.simulate(seconds: Game.fadeOutSeconds - 0.4)
            check(g.world == .glassWood && g.whiteout > 0.99, "at full white the world has changed to the Glass Wood (whiteout \(String(format: "%.2f", g.whiteout)))")
            check(distance(SIMD2(g.player.position.x, g.player.position.z), SIMD2(arrival.x, arrival.z)) < 0.01 && abs(g.player.position.y - arrival.y) < 0.6, "you arrive on the arrival pad")
            check(g.interactables.map(\.id) == ["gw_return"] && g.drainEvents().contains(.worldChanged(.glassWood)), "the Glass Wood has its own interactables and a worldChanged event was emitted")
            g.simulate(seconds: Game.holdSeconds + Game.fadeInSeconds + 0.2)
            check(g.whiteout == 0 && !g.isTraveling && g.whiteCaption == nil, "the white fades away and control returns")
            g.simulate(seconds: 2, input: input)
            check(distance(g.player.position, arrival) > 3, "you can walk in the Glass Wood")

            g.player = Player(position: GlassLayout.returnLens - SIMD3(0, 2.3, 0) + SIMD3(0, 0, 3), yaw: 0)     // 3 m south of the ring, facing it
            g.player.pitch = 0.0
            g.player.position.y = g.scene.groundHeight(x: g.player.position.x, z: g.player.position.z)
            g.updateHover()
            check(g.hovered?.id == "gw_return", "standing before the return ring, it is hoverable (\(g.hovered?.id ?? "nothing"))")
            g.activate("gw_return")
            g.simulate(seconds: Game.fadeOutSeconds + 0.1)
            check(g.world == .varrow && distance(SIMD2(g.player.position.x, g.player.position.z), SIMD2(Layout.isletCenter.x, Layout.isletCenter.z + 5)) < 0.1, "the return ring takes you back to the islet in Varrow")
            g.simulate(seconds: 3)
            check(g.state.has("solved") && g.whiteout == 0, "Varrow's progress is intact after the round trip")

            // Without the Glass Wood scene (Varrow-only games) the lens simply does nothing.
            let lone = Game(scene: scenes[.varrow]!)
            lone.puzzle.forceSolved(); lone.activate("lens"); lone.simulate(seconds: 3)
            check(lone.world == .varrow && lone.whiteout == 0, "a Varrow-only game ignores the lens rather than breaking")

            // Saving in the second world.
            let tmp = NSTemporaryDirectory() + "lw-worlds-\(getpid())"
            setenv("LANTERNWRIGHT_SAVE_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_SAVE_DIR") }
            let h = Game(scenes: scenes); h.puzzle.forceSolved(); h.travel(to: .glassWood)
            h.player = Player(position: GlassLayout.point(-20, 120), yaw: 0.7)
            h.player.position.y = h.scene.groundHeight(x: -20, z: 120)
            try? SaveStore.save(h.makeSave())
            let k = Game(scenes: scenes)
            if let save = SaveStore.load() { k.restore(save) }
            check(k.world == .glassWood && abs(k.player.position.x + 20) < 0.01 && k.state.has("solved"), "a save made in the Glass Wood resumes there")
            let old = SaveData(flags: ["solved"], pages: [], position: [175, 0.8, 205], yaw: 0, pitch: 0, playTime: 1, world: nil)
            let m = Game(scenes: scenes); m.restore(old)
            check(m.world == .varrow, "a save without a world field (from before the second world) resumes in Varrow")
        }
        if name == "all" || name == "mirrors" {
            let sol = MirrorCourt.trace(mirrors: MirrorCourt.solutionMirrors, panes: MirrorCourt.solutionPanes)
            check(sol.solved && sol.panesMet == [0, 1, 2], "the intended arrangement solves it (panes met \(sol.panesMet))")
            let start = MirrorCourt.trace(mirrors: MirrorCourt.initialMirrors, panes: MirrorCourt.initialPanes)
            check(!start.solved && !start.reachedReceiver, "the starting arrangement is not solved and the beam misses the receiver")
            check(sol.points.count >= 6 && sol.segmentColor.count == sol.points.count - 1, "a trace has one colour per segment (\(sol.points.count) points)")
            check(sol.segmentColor.first == -1 && sol.segmentColor.last == 2, "the light starts as plain moonlight and ends amber (the last pane is stone)")

            // Exhaustive: all 4^3 mirror states x 3^3 pane colours terminate, and exactly ONE of the 1728 solves it.
            var solutions: [([Int], [Int])] = [], reached = 0
            for a in 0..<4 { for b in 0..<4 { for c in 0..<4 {
                for x in 0..<3 { for y in 0..<3 { for z in 0..<3 {
                    let t = MirrorCourt.trace(mirrors: [a, b, c], panes: [x, y, z])
                    if t.reachedReceiver { reached += 1 }
                    if t.solved { solutions.append(([a, b, c], [x, y, z])) }
                } } }
            } } }
            check(solutions.count == 1 && solutions[0].0 == MirrorCourt.solutionMirrors && solutions[0].1 == MirrorCourt.solutionPanes,
                  "exactly one of the 1728 arrangements solves it (\(solutions.count) found); the beam reaches the receiver in \(reached) of them")
            check(reached > 1 && reached < 400, "reaching the receiver is possible with wrong colours, so the colour order really matters (\(reached) arrangements reach it)")

            // Any single click away from the solution is not solved (so there are no cheap near-misses).
            var oneAway = 0
            for k in 0..<3 {
                var m = MirrorCourt.solutionMirrors; m[k] = (m[k] + 1) % 4
                if MirrorCourt.trace(mirrors: m, panes: MirrorCourt.solutionPanes).solved { oneAway += 1 }
                var p = MirrorCourt.solutionPanes; p[k] = (p[k] + 1) % 3
                if MirrorCourt.trace(mirrors: MirrorCourt.solutionMirrors, panes: p).solved { oneAway += 1 }
            }
            check(oneAway == 0, "no arrangement one click from the solution also solves it")
            // Reflection rules.
            check(MirrorCourt.reflect((1, 0), state: 3) == (0, -1) && MirrorCourt.reflect((0, -1), state: 1) == (-1, 0) && MirrorCourt.reflect((-1, 0), state: 3) == (0, 1), "the three solution mirrors turn the beam east->north->west->south")
            check(MirrorCourt.reflect((1, 0), state: 0) == (1, 0) && MirrorCourt.reflect((1, 0), state: 2) == (-1, 0), "an axis mirror passes a parallel beam and bounces a perpendicular one back")
            // Geometry: the whole court fits on the flat pad.
            let corners = [MirrorCourt.world((0, 0)), MirrorCourt.world((4, 4)), MirrorCourt.world((0, 4)), MirrorCourt.world((4, 0))]
            let farthest = corners.map { distance(SIMD2($0.x, $0.z), SIMD2(GlassLayout.mirrorCourt.x, GlassLayout.mirrorCourt.z)) }.max()!
            check(farthest < GlassLayout.pads[1].radius - 4, "the court fits inside its flat pad (corner \(String(format: "%.1f", farthest)) m from the centre, pad radius \(GlassLayout.pads[1].radius))")
        }
        if name == "all" || name == "mirrorgame" {
            // Each game gets freshly built scenes, because the puzzle mutates scene items.
            func fresh() -> Game {
                let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
                g.travel(to: .glassWood); _ = g.drainEvents()
                return g
            }
            func item(_ g: Game, _ name: String) -> DrawItem { g.scenes[.glassWood]!.items.first { $0.name == name }! }
            func visibleBeams(_ g: Game) -> Int { (0..<GlassPuzzleProps.beamSegments).filter { !item(g, "gw_beam_\($0)").hidden }.count }
            func chimes(_ e: [GameEvent]) -> [ChimeKind] { e.compactMap { if case .chime(let k) = $0 { return k } else { return nil } } }

            var g = fresh()
            let ids = g.interactables.map(\.id)
            check(["gw_mirror_0", "gw_mirror_1", "gw_mirror_2", "gw_pane_0", "gw_pane_1", "gw_pane_2", "gw_return"].allSatisfy(ids.contains), "the court's mirrors, panes and the return ring are interactable")
            check(g.interactables.first { $0.id == "page_5" }?.enabled == true && ["page_6", "page_7", "page_8"].allSatisfy { id in g.interactables.first { $0.id == id }?.enabled == false }, "page 5 is readable at once; 6-8 wait to be earned")
            check(item(g, "page_6").hidden && item(g, "page_7").hidden && item(g, "page_8").hidden && !item(g, "page_5").hidden, "pages 6-8 are not visible in the world yet")
            check(visibleBeams(g) >= 1, "a beam is already visible in the court at the start (\(visibleBeams(g)) segment(s))")

            // A wrong arrangement that nonetheless reaches the receiver: panes in the wrong order do not solve it.
            g.glass!.click("gw_mirror_0"); g.glass!.click("gw_mirror_0"); g.glass!.click("gw_mirror_0")     // M1: 0 -> 3
            for _ in 0..<3 { g.glass!.click("gw_mirror_1") }                                                  // M2: 2 -> 1
            for _ in 0..<2 { g.glass!.click("gw_mirror_2") }                                                  // M3: 1 -> 3
            check(g.glass!.mirrors == MirrorCourt.solutionMirrors && !g.state.has("gw_mirrors"), "right mirrors, wrong glass: not solved")
            check(MirrorCourt.trace(mirrors: g.glass!.mirrors, panes: g.glass!.panes).reachedReceiver, "...but the beam does reach the receiver, which shows the wrong colour instead of the win")
            g.glass!.click("gw_pane_0")                                                                         // A: 2 -> 0 (tide)
            check(!g.state.has("gw_mirrors"), "one pane right is still not enough")
            g.glass!.click("gw_pane_1")                                                                         // B: 0 -> 1 (wind)
            g.glass!.click("gw_pane_2")                                                                         // C: 1 -> 2 (stone)
            check(g.state.has("gw_mirrors") && g.glass!.panes == MirrorCourt.solutionPanes, "tide, wind, stone in the right order solves the mirror court")

            // The reward plays out over a few seconds.
            check(item(g, "page_6").hidden, "the page does not appear in the same instant")
            g.simulate(seconds: 4)
            check(chimes(g.drainEvents()).filter { [.tide, .wind, .stone, .ignite].contains($0) }.prefix(4) == [.tide, .wind, .stone, .ignite], "the wood answers with tide, wind, stone, then the chord")
            check(!item(g, "page_6").hidden && g.interactables.first { $0.id == "page_6" }?.enabled == true, "Oren's page 6 appears at the receiver")
            check(!item(g, "gw_column").hidden && item(g, "gw_column").uniforms.model.columns.1.y > 40, "a tall column of light rises from the receiver (height \(String(format: "%.0f", item(g, "gw_column").uniforms.model.columns.1.y)) m)")

            // Solved is permanent.
            let before = g.glass!.mirrors
            g.glass!.click("gw_mirror_0"); g.glass!.click("gw_pane_1")
            check(g.glass!.mirrors == before && g.state.has("gw_mirrors") && chimes(g.drainEvents()).filter { $0 == .glassTick }.count == 2, "after solving, clicks only tick; the solution stays")

            // Saving and restoring keeps it solved and reveals the page again.
            let tmp = NSTemporaryDirectory() + "lw-mirror-\(getpid())"
            setenv("LANTERNWRIGHT_SAVE_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_SAVE_DIR") }
            try? SaveStore.save(g.makeSave())
            let h = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
            if let save = SaveStore.load() { h.restore(save) }
            check(h.world == .glassWood && h.state.has("gw_mirrors") && h.glass!.panes == MirrorCourt.solutionPanes && !h.scenes[.glassWood]!.items.first { $0.name == "page_6" }!.hidden, "a save resumes with the mirror court solved and page 6 available")

            // Collecting a revealed page works and hides it everywhere.
            g.activate("page_6")
            check(g.journal.collectedPages.map(\.number) == [6] && g.journal.isOpen && item(g, "page_6").hidden, "reading page 6 opens the journal on it and removes it from the world")
        }
        return ok
    }
}

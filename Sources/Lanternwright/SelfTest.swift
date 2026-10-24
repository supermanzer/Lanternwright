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
            // The sampler is the mesh: compare against the triangles actually uploaded to the GPU at 5000 seeded random points.
            do {
                let chunks = TerrainMesh.buildChunks(terrain: t, device: device)
                var byName: [String: DrawItem] = [:]; for c in chunks { byName[c.name] = c }
                let per = (Terrain.gridCount - 1) / TerrainMesh.chunksPerSide
                var seed: UInt64 = 0x9E3779B97F4A7C15
                func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(seed >> 40) / Float(1 << 24) }
                var worst: Float = 0, worstNormal: Float = 1, tested = 0
                for _ in 0..<5000 {
                    let x = -400 + rnd() * 800, z = -400 + rnd() * 800
                    let gx = (x - Terrain.origin) / Terrain.spacing, gz = (z - Terrain.origin) / Terrain.spacing
                    let ci = Int(gx) / per, cj = Int(gz) / per
                    guard let item = byName["terrain_\(ci)_\(cj)"] else { continue }
                    let li = Int(gx) - ci * per, lj = Int(gz) - cj * per
                    let verts = item.mesh.vertexBuffer.contents().assumingMemoryBound(to: Vertex.self)
                    let idx = item.mesh.indexBuffer.contents().assumingMemoryBound(to: UInt32.self)
                    let base = (lj * per + li) * 6
                    for tri in 0..<2 {
                        let p = (0..<3).map { SIMD3(verts[Int(idx[base + tri * 3 + $0])].position.x, verts[Int(idx[base + tri * 3 + $0])].position.y, verts[Int(idx[base + tri * 3 + $0])].position.z) }
                        // barycentric weights of (x, z) in this triangle's footprint
                        let d = (p[1].z - p[2].z) * (p[0].x - p[2].x) + (p[2].x - p[1].x) * (p[0].z - p[2].z)
                        let w0 = ((p[1].z - p[2].z) * (x - p[2].x) + (p[2].x - p[1].x) * (z - p[2].z)) / d
                        let w1 = ((p[2].z - p[0].z) * (x - p[2].x) + (p[0].x - p[2].x) * (z - p[2].z)) / d
                        let w2 = 1 - w0 - w1
                        if w0 >= -1e-4 && w1 >= -1e-4 && w2 >= -1e-4 {
                            let meshY = w0 * p[0].y + w1 * p[1].y + w2 * p[2].y
                            worst = max(worst, abs(meshY - t.sampleHeight(x: x, z: z)))
                            let fn = normalize(cross(p[1] - p[0], p[2] - p[0])); let fnUp = fn.y < 0 ? -fn : fn
                            worstNormal = min(worstNormal, dot(fnUp, t.faceNormal(x: x, z: z)))
                            tested += 1
                            break
                        }
                    }
                }
                check(tested > 4500 && worst < 0.001, "terrain sampleHeight equals the mesh triangle height at \(tested) random points (worst difference \(worst * 1000) mm)")
                check(worstNormal > 0.9999, "faceNormal equals the mesh triangle's normal (worst dot \(worstNormal))")
            }
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
        if name == "all" || name == "sonic" {
            typealias SL = SonicLandmarks
            let tide = StoneID.tide.position
            check(SL.falloff(0, ref: 8, range: 60) > 0.99 && SL.falloff(8, ref: 8, range: 60) > 0.4 && SL.falloff(60, ref: 8, range: 60) == 0 && SL.falloff(500, ref: 8, range: 60) == 0, "falloff: full at the source, about half at the reference distance, exactly zero at and beyond the range")
            var prev: Float = 2; var monotone = true
            for d in stride(from: Float(0), through: 70, by: 0.5) { let f = SL.falloff(d, ref: 8, range: 60); if f > prev + 1e-6 { monotone = false }; prev = f }
            check(monotone, "falloff never increases with distance")
            let near = SL.levels(listener: tide + SIMD3(3, 0, 0), yaw: 0, world: .varrow, lighthouseLit: false)
            let far = SL.levels(listener: tide + SIMD3(40, 0, 0), yaw: 0, world: .varrow, lighthouseLit: false)
            check(near.hum.x > far.hum.x && near.hum.x > 0.5 && near.hum.y == 0 && near.hum.z == 0, "the tide stone hums loud beside it and faintly at 40 m; the other stones are silent from here")
            check(near.hum.w == 0 && SL.levels(listener: tide, yaw: 0, world: .varrow, lighthouseLit: true).hum.w > 0.01 && SL.levels(listener: Layout.dockEnd, yaw: 0, world: .varrow, lighthouseLit: true).hum.w > 0.001, "the lighthouse carries a tone only once lit, and it reaches the dock")
            let dock = SL.levels(listener: Layout.dockEnd, yaw: Layout.spawnYaw, world: .varrow, lighthouseLit: false)
            check(dock.buoy > 0.05 && SL.levels(listener: Layout.summitStone, yaw: 0, world: .varrow, lighthouseLit: false).buoy == 0, "the bell buoy is audible from the dock and gone from the summit")
            check(SL.levels(listener: Layout.dockEnd, yaw: 0, world: .glassWood, lighthouseLit: true) == SL.Levels(), "no Varrow sounds in the Glass Wood")
            // Panning: facing north (yaw 0), a source to the east is on the right, to the west on the left, ahead is centred.
            check(SL.pan(listener: .zero, yaw: 0, source: SIMD3(10, 0, 0)) > 0.8 && SL.pan(listener: .zero, yaw: 0, source: SIMD3(-10, 0, 0)) < -0.8 && abs(SL.pan(listener: .zero, yaw: 0, source: SIMD3(0, 0, -10))) < 0.01, "pan: east is right, west is left, straight ahead is centred (facing north)")
            check(SL.pan(listener: .zero, yaw: .pi / 2, source: SIMD3(0, 0, -10)) < -0.8, "pan follows the head: facing east, north is on the left")
            let galleryNear = SL.levels(listener: Layout.lighthouse + SIMD3(8, 0, 0), yaw: 0, world: .varrow, lighthouseLit: false).gallery
            check(galleryNear > 0.3 && SL.levels(listener: Layout.lighthouse + SIMD3(80, 0, 0), yaw: 0, world: .varrow, lighthouseLit: false).gallery == 0, "wind sings round the lighthouse close to it and not 80 m away")
            let intervals = (0..<20).map { SL.buoyInterval(strike: $0) }
            check(intervals.allSatisfy { $0 >= 5.2 && $0 <= 8.3 } && Set(intervals.map { Int($0 * 100) }).count > 10, "the buoy rings every 5-8 s, irregularly")
            check(Scene.makeWorld(device: device).groundHeight(x: Layout.buoy.x, z: Layout.buoy.z) < -3, "the buoy floats in deep water (ground \(Scene.makeWorld(device: device).groundHeight(x: Layout.buoy.x, z: Layout.buoy.z)) m)")
            // Offline render: located hums add audible energy and the mix never clips; a buoy strike is audible and decays.
            func render(_ setup: (AmbienceSynth) -> Void, seconds: Int = 4) -> [Float] {
                let synth = AmbienceSynth(sampleRate: 44100)
                setup(synth)
                let n = 44100 * seconds
                var l = [Float](repeating: 0, count: n), r = l
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    var done = 0
                    while done < n { synth.render(frames: 512, left: lp.baseAddress! + done, right: rp.baseAddress! + done); done += 512 }
                } }
                return l
            }
            func rmsOf(_ a: ArraySlice<Float>) -> Float { (a.reduce(0) { $0 + $1 * $1 } / Float(a.count)).squareRoot() }
            let base = render { _ in }
            let hums = render { $0.humGain = SIMD4(1, 1, 1, 1); $0.galleryGain = 1 }
            let humRms = rmsOf(zip(hums, base).map { $0 - $1 }[88200...])
            check(humRms > 0.003 && humRms < 0.06 && (hums.map { abs($0) }.max() ?? 2) < 1, "the hums and gallery whistle are audible, faint and never clip (added rms \(String(format: "%.4f", humRms)))")
            let bell = render({ $0.buoyGain = 0.8; $0.play(.buoy) }, seconds: 10)
            let bellDiff = zip(bell, render({ _ in }, seconds: 10)).map { $0 - $1 }
            check(rmsOf(bellDiff[0..<22050]) > rmsOf(bellDiff[(44100 * 9)...]) * 2 && rmsOf(bellDiff[0..<22050]) > 0.003, "a bell-buoy strike is audible and decays")
            let silentBell = render({ $0.buoyGain = 0; $0.play(.buoy) })
            check(zip(silentBell, base).allSatisfy { abs($0 - $1) < 1e-6 }, "a buoy too far away to hear adds nothing")
        }
        if name == "all" || name == "wind" {
            var lo: Float = 1, hi: Float = 0, deterministic = true
            for k in 0..<4000 {
                let tt = Float(k) * 0.05, p = SIMD3<Float>(Float(k % 37) * 7 - 120, Float(k % 70), Float(k % 53) * 5 - 100)
                let s = Wind.strength(at: p, time: tt)
                if s != Wind.strength(at: p, time: tt) { deterministic = false }
                lo = min(lo, s); hi = max(hi, s)
                if !(Wind.gust(time: tt) >= 0 && Wind.gust(time: tt) <= 1) { deterministic = false }
            }
            check(deterministic && lo >= 0 && hi <= 1 && hi - lo > 0.4, "wind is deterministic and stays in 0...1 while genuinely gusting (range \(lo)...\(hi))")
            check(abs(simd_length(Wind.direction) - 1) < 1e-5 && abs(simd_length(Wind.vector(at: .zero, time: 3)) - Wind.strength(at: .zero, time: 3)) < 1e-5, "the wind direction is a unit vector and the velocity is direction x strength")
            let up = (0..<400).map { Wind.strength(at: SIMD3(0, 70, 0), time: Float($0) * 0.5) }.reduce(0, +)
            let low = (0..<400).map { Wind.strength(at: SIMD3(0, 0, 0), time: Float($0) * 0.5) }.reduce(0, +)
            check(up > low * 1.2, "the wind is stronger on the summit than at the shore on average")
            // A gust travels downwind: the same gust reaches a point 90 m downwind 10 s later.
            let there = SIMD3<Float>(Wind.direction.x * 90, 0, Wind.direction.y * 90)
            check(abs(Wind.strength(at: there, time: 25 + 10) - Wind.strength(at: .zero, time: 25)) < 1e-4, "gusts travel downwind at 9 m/s")
        }
        if name == "all" || name == "pace" {
            check(Player.paceFactor(slope: 0) == 1 && Player.paceFactor(slope: 0.3) < 1 && Player.paceFactor(slope: 0.3) > Player.paceFactor(slope: 0.6) && Player.paceFactor(slope: -0.2) > 1 && Player.paceFactor(slope: -0.2) < 1.09, "pace: uphill slower than flat slower than gentle downhill (flat 1, +0.3 \(Player.paceFactor(slope: 0.3)), -0.2 \(Player.paceFactor(slope: -0.2)))")
            check((-3...3).map { Player.paceFactor(slope: Float($0) * 0.5) }.allSatisfy { $0 >= Player.minPace - 1e-6 && $0 <= 1.081 }, "pace never drops below 55 % nor exceeds 108 %")
            // On the real hill: walk straight uphill and straight downhill from the same spot and compare distances in 3 s.
            let sc = Scene.makeWorld(device: device)
            func walked(from p: SIMD3<Float>, yaw: Float, run: Bool) -> Float {
                var pl = Player(position: p, yaw: yaw); pl.position.y = sc.groundHeight(x: p.x, z: p.z)
                var inp = InputState(); inp.move = SIMD2(0, 1); inp.run = run
                let start = SIMD2(pl.position.x, pl.position.z)
                for _ in 0..<360 { pl.step(dt: Game.tick, input: inp, scene: sc) }
                return length(SIMD2(pl.position.x, pl.position.z) - start)
            }
            let spot = SIMD3<Float>(60, 0, 80)                       // on the south-east slope of the hill
            let toward = Layout.lighthouse - spot
            let upYaw = atan2(toward.x, -toward.z)
            let up = walked(from: spot, yaw: upYaw, run: false), down = walked(from: spot, yaw: upYaw + .pi, run: false)
            let flat = walked(from: SIMD3(150, 0, 172) , yaw: Layout.spawnYaw, run: false)
            check(up < down && up >= Player.walkSpeed * 3 * Player.minPace * 0.9, "walking uphill covers less ground in 3 s than walking down (up \(up) m, down \(down) m)")
            check(up < Player.walkSpeed * 3 * 0.97, "the climb is visibly slower than the flat pace (\(up) m vs \(Player.walkSpeed * 3) m)")
            _ = flat
        }
        if name == "all" || name == "clutter" {
            let sc = Scene.makeWorld(device: device)
            let clutter = sc.items.filter { $0.name.hasPrefix("clutter_") }
            check(clutter.count >= 3, "shore and path clutter exists (\(clutter.count) batches)")
            let tris = clutter.reduce(0) { $0 + $1.mesh.indexCount / 3 }
            check(tris > 500 && tris < 60000, "clutter is a modest triangle budget (\(tris))")
            // Everything sits on the ground, off the path itself and off the pads.
            var bad = 0, total = 0
            for item in clutter {
                let verts = item.mesh.vertexBuffer.contents().assumingMemoryBound(to: Vertex.self)
                let n = item.mesh.vertexBuffer.length / MemoryLayout<Vertex>.stride
                for i in stride(from: 0, to: n, by: 7) {
                    let v = verts[i].position
                    total += 1
                    let g = sc.terrain.sampleHeight(x: v.x, z: v.z)
                    if v.y < g - 0.45 || v.y > g + 1.4 { bad += 1 }   // driftwood ends can overhang a slope
                }
            }
            check(total > 0 && bad == 0, "clutter vertices all rest on the ground (\(bad) of \(total) floating or buried)")
            let again = Scene.makeWorld(device: device).items.filter { $0.name.hasPrefix("clutter_") }.map { "\($0.name):\($0.mesh.indexCount)" }
            check(again == clutter.map { "\($0.name):\($0.mesh.indexCount)" }, "clutter placement is deterministic")
            var mb = MeshBuilder(); mb.bevelBox(size: SIMD3(1, 1, 1), bevel: 0.1, surface: Surface(color: SIMD3(1, 1, 1), roughness: 0.5))
            check(mb.vertices.count > 0 && mb.vertices.allSatisfy { abs($0.position.x) <= 0.5 + 1e-5 && abs($0.position.y) <= 0.5 + 1e-5 && abs($0.position.z) <= 0.5 + 1e-5 }, "a bevelled box stays inside its nominal size (\(mb.vertices.count) vertices)")
        }
        if name == "all" || name == "exposure" {
            check(EyeAdaptation.target(averageLuminance: 0.18) == 1 && EyeAdaptation.target(averageLuminance: 0.01) > 1 && EyeAdaptation.target(averageLuminance: 5) < 1, "a mid-grey scene keeps its exposure; a dark scene brightens, a bright one darkens")
            check((0..<40).allSatisfy { let l = pow(Float(10), Float($0) / 10 - 3); let t = EyeAdaptation.target(averageLuminance: l); return t >= 0.75 && t <= 1.35 }, "the correction is always within 0.75...1.35")
            var eye = EyeAdaptation(); var secondsUp: Float = 0
            while abs(eye.exposure - EyeAdaptation.target(averageLuminance: 0.01)) > 0.02 && secondsUp < 30 { eye.update(averageLuminance: 0.01, dt: 1 / 60); secondsUp += 1 / 60 }
            var down = EyeAdaptation(); down.snap(averageLuminance: 0.01); var secondsDown: Float = 0
            while abs(down.exposure - EyeAdaptation.target(averageLuminance: 5)) > 0.02 && secondsDown < 30 { down.update(averageLuminance: 5, dt: 1 / 60); secondsDown += 1 / 60 }
            check(secondsUp > 1.5 && secondsUp < 8 && secondsDown < secondsUp && secondsDown > 0.2, "exposure converges, slower brightening (\(secondsUp) s) than darkening (\(secondsDown) s)")
            var steady = EyeAdaptation(); steady.update(averageLuminance: 0.18, dt: 5)
            check(steady.exposure == 1, "a steady mid-grey scene stays at exactly the authored exposure")
            var frozen = EyeAdaptation(); frozen.update(averageLuminance: 0.01, dt: 0)
            check(frozen.exposure == 1, "no time passing means no adaptation")
            check(LaunchOptions.parse(["lanternwright", "--screenshot", "x.png", "--auto-exposure"]).autoExposure == true && LaunchOptions.parse(["lanternwright", "--screenshot", "x.png"]).autoExposure == false, "screenshots are fixed-exposure unless --auto-exposure is passed")
        }
        if name == "all" || name == "space" {
            // FDN reverb: stable, silent after its decay, decay time as asked, never louder than the input.
            func tail(_ rt: Float) -> [Float] {
                var r = FDNReverb(sampleRate: 44100); r.setDecay(rt)
                var out: [Float] = []
                for i in 0..<(44100 * 8) { out.append(r.process(left: i == 0 ? 1 : 0, right: 0).0) }
                return out
            }
            func rmsWindow(_ a: [Float], _ from: Float, _ to: Float) -> Float {
                let s = a[Int(from * 44100)..<Int(to * 44100)]; return (s.reduce(0) { $0 + $1 * $1 } / Float(s.count)).squareRoot()
            }
            let short = tail(0.8), long = tail(3.0)
            check((short + long).allSatisfy { $0.isFinite && abs($0) < 1 }, "the FDN reverb is stable and never louder than a unit impulse")
            check(rmsWindow(short, 7, 8) < 1e-4 && rmsWindow(long, 7, 8) < 1e-3, "and it falls silent after its decay (\(rmsWindow(long, 7, 8)))")
            // Decay measured: the energy envelope should drop ~60 dB over rt60 (within a generous factor: it is a statistical tail).
            func dbDrop(_ a: [Float], _ rt: Float) -> Float { 20 * log10(max(rmsWindow(a, 0.1, 0.3), 1e-9) / max(rmsWindow(a, 0.1 + rt * 0.6, 0.3 + rt * 0.6), 1e-9)) }
            let dShort = dbDrop(short, 0.8), dLong = dbDrop(long, 3.0)
            check(dShort > 20 && dShort < 70 && dLong > 20 && dLong < 70, "decay follows rt60: both fall tens of dB over 60 % of their rt60 (\(dShort) dB, \(dLong) dB)")
            check(rmsWindow(long, 1.0, 2.0) > rmsWindow(short, 1.0, 2.0) * 3, "a longer rt60 keeps ringing after a shorter one has died")
            var loud = FDNReverb(sampleRate: 44100); loud.setDecay(6)
            var peak: Float = 0
            for i in 0..<(44100 * 4) { let x = Float(sin(Double(i) * 0.05)); let o = loud.process(left: x, right: -x); peak = max(peak, abs(o.0), abs(o.1)) }
            check(peak.isFinite && peak < 12, "even fed a continuous full-scale tone it stays finite and bounded (peak \(peak)); the synth's tanh limiter takes it from there")
            // The space probe.
            let sc = Scene.makeWorld(device: device)
            let ground: (Float, Float) -> Float = { sc.groundHeight(x: $0, z: $1) }
            var opens: [Float] = []
            for k in 0..<60 { let x = -150 + Float(k % 10) * 28, z = -150 + Float(k / 10) * 40; if ground(x, z) > 2 { opens.append(AudioSpace.openness(at: SIMD3(x, ground(x, z), z), ground: ground)) } }
            check(opens.count > 10 && ((opens.max() ?? 0) - (opens.min() ?? 1)) > 0.25, "openness varies across the island (min \(opens.min() ?? -1), max \(opens.max() ?? -1) over \(opens.count) places)")
            check(AudioSpace.reverbTime(openness: 1) < AudioSpace.reverbTime(openness: 0) && AudioSpace.reverbTime(openness: 0) <= 3.2 && AudioSpace.reverbTime(openness: 1) >= 0.7, "an enclosed place rings longer than an open one")
            let dock = AudioSpace.read(listener: Layout.dockEnd, yaw: Layout.spawnYaw, ground: ground)
            let dockFlip = AudioSpace.read(listener: Layout.dockEnd, yaw: Layout.spawnYaw + .pi, ground: ground)
            check(dock.shoreDistance < 40 && abs(dock.surfPan) > 0.05 && dock.surfPan * dockFlip.surfPan < 0, "surf pans toward the nearest shore and flips when you turn round (\(dock.surfPan) / \(dockFlip.surfPan))")
            check(dock.surfOcclusion < 0.2, "the dock has a clear line to the sea (occlusion \(dock.surfOcclusion))")
            // Behind the hill: a lee-side spot whose nearest shoreline lies across the ridge should be occluded, the beach not.
            // A synthetic coast: sea for x < 0, a ridge 40 m high at x 10...20, low land beyond. Standing behind the ridge muffles the sea.
            let coast: (Float, Float) -> Float = { x, _ in x < 0 ? -5 : ((x >= 10 && x <= 20) ? 40 : 5) }
            let lee = AudioSpace.read(listener: SIMD3(50, 5, 0), yaw: 0, ground: coast), front = AudioSpace.read(listener: SIMD3(6, 5, 0), yaw: 0, ground: coast)
            check(lee.surfOcclusion > 0.8 && front.surfOcclusion < 0.1, "behind a ridge the sea is occluded; on the near side it is not (\(lee.surfOcclusion) vs \(front.surfOcclusion))")
            // Ducking and the muffled/panned surf, measured offline.
            let synth = AmbienceSynth(sampleRate: 44100)
            var l = [Float](repeating: 0, count: 512), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in synth.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!) } }
            check(synth.duckAmount == 0, "no chime, no ducking")
            synth.play(.stone)
            var maxDuck: Float = 0
            for _ in 0..<40 { l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in synth.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!) } }; maxDuck = max(maxDuck, synth.duckAmount) }
            check(maxDuck > 0.1 && maxDuck <= 0.351, "a chime ducks the ambient bed (peak \(maxDuck))")
            for _ in 0..<(44100 * 12 / 512) { l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in synth.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!) } } }
            check(synth.duckAmount < 0.02, "and the ducking releases once the chime has gone")
            func surfEnergy(pan: Float, occ: Float) -> (Float, Float, Float) {
                let sy = AmbienceSynth(sampleRate: 44100); sy.windGain = 0; sy.surfGain = 1; sy.surfPan = pan; sy.surfOcclusion = occ
                var a = [Float](repeating: 0, count: 44100 * 6), b = a
                a.withUnsafeMutableBufferPointer { ap in b.withUnsafeMutableBufferPointer { bp in var d = 0; while d < 44100 * 6 { sy.render(frames: 512, left: ap.baseAddress! + d, right: bp.baseAddress! + d); d += 512 } } }
                func rm(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot() }
                // brightness: energy of the sample-to-sample difference relative to the signal
                let diff = zip(a.dropFirst(), a).map { $0 - $1 }
                return (rm(a[88200...]), rm(b[88200...]), rm(diff[88200...]) / max(rm(a[88200...]), 1e-6))
            }
            let centre = surfEnergy(pan: 0, occ: 0), right = surfEnergy(pan: 1, occ: 0), muffled = surfEnergy(pan: 0, occ: 1)
            check(right.1 > right.0 * 1.2 && abs(centre.0 - centre.1) / max(centre.0, 1e-6) < 0.3, "surf from the right is louder in the right ear (\(right.0) / \(right.1)); centred stays balanced")
            check(muffled.2 < centre.2 * 0.85 && muffled.0 < centre.0, "behind a hill the surf is darker and quieter (brightness \(muffled.2) vs \(centre.2))")
        }
        if name == "all" || name == "poisson" {
            let sc = Scene.makeWorld(device: device)
            let sites = Island.treeSites(terrain: sc.terrain)
            check(sites.count > 150 && sites.count < 900, "Poisson-disc tree sites exist in a sensible number (\(sites.count))")
            // Blue noise: no two sites closer than the smaller local radius allows (half the mean of the two radii).
            var tooClose = 0
            for i in 0..<sites.count { for j in (i + 1)..<sites.count {
                let d = simd_length(sites[i] - sites[j])
                if d < 6 { tooClose += 1 } else if d < 22 {
                    let need = 0.5 * ((22 - 16 * Island.treeDensity(terrain: sc.terrain, x: sites[i].x, z: sites[i].y)) + (22 - 16 * Island.treeDensity(terrain: sc.terrain, x: sites[j].x, z: sites[j].y)))
                    if d < need - 1e-3 { tooClose += 1 }
                } } }
            check(tooClose == 0, "no two trees closer than the local spacing (\(tooClose) violations)")
            check(sites.allSatisfy { Island.treeAllowed(terrain: sc.terrain, x: $0.x, z: $0.y) }, "every site obeys the rules: altitude band, slope, clear of path, pads and dock")
            check(sites == Island.treeSites(terrain: sc.terrain), "placement is deterministic")
            // Groves vs clearings: nearest-neighbour distances span a wide range (a grid or jitter would not).
            let nn = sites.map { p in sites.filter { $0 != p }.map { simd_length($0 - p) }.min() ?? 0 }.sorted()
            check(nn[nn.count / 10] < 9 && nn[nn.count * 9 / 10] > 11, "spacing varies: tight in groves (p10 \(nn[nn.count / 10]) m), open in clearings (p90 \(nn[nn.count * 9 / 10]) m)")
            // No rows: a regular lattice has a nearly constant nearest-neighbour distance; require real spread.
            let mean = nn.reduce(0, +) / Float(nn.count)
            let sd = (nn.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(nn.count)).squareRoot()
            check(sd > 1.5, "nearest-neighbour spacing is irregular, not a lattice (sd \(sd) m)")
            check(sc.items.contains { $0.name.hasPrefix("trees_") }, "trees were built into the scene")
        }
        if name == "all" || name == "zoom" {
            check(abs(LookCloser.fov(zoom: 0) - LookCloser.baseFov) < 1e-6 && LookCloser.fov(zoom: 1) < LookCloser.baseFov * 0.45 && LookCloser.fov(zoom: 1) > 0.2, "zoom 0 is the normal 60 degrees; full zoom narrows to about 22 degrees")
            var z: Float = 0, steps = 0
            var monotone = true, prev: Float = 0
            while z < 1 && steps < 2000 { z = LookCloser.ease(z, held: true, dt: Game.tick); if z < prev { monotone = false }; prev = z; steps += 1 }
            check(monotone && z == 1 && Float(steps) * Game.tick > 0.3 && Float(steps) * Game.tick < 2, "holding zoom eases in smoothly over about a second (\(Float(steps) * Game.tick) s) and settles exactly")
            var out = z; steps = 0
            while out > 0 && steps < 2000 { out = LookCloser.ease(out, held: false, dt: Game.tick); steps += 1 }
            check(out == 0 && Float(steps) * Game.tick < 2, "releasing eases back to the normal view")
            var fovs: [Float] = []; for k in 0...20 { fovs.append(LookCloser.fov(zoom: Float(k) / 20)) }
            check(zip(fovs, fovs.dropFirst()).allSatisfy { $0 >= $1 }, "the field of view only ever narrows as zoom grows")
            check(LookCloser.lookScale(zoom: 0) == 1 && LookCloser.lookScale(zoom: 1) < 0.4 && LookCloser.lookScale(zoom: 1) > 0.3, "mouse look slows with the zoom (scale \(LookCloser.lookScale(zoom: 1)))")
            let g = Game(scene: Scene.makeWorld(device: device))
            var held = InputState(); held.zoom = true
            g.simulate(seconds: 1.5, input: held)
            check(g.zoomAmount == 1 && g.camera.fovY < LookCloser.baseFov * 0.45, "the game's camera narrows while zoom is held")
            g.simulate(seconds: 1.5)
            check(g.zoomAmount == 0 && abs(g.camera.fovY - LookCloser.baseFov) < 1e-6, "and returns to normal when released")
            g.toggleJournal(); g.simulate(seconds: 1, input: held)
            check(g.zoomAmount == 0, "zoom is ignored while the journal is open")
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

            // 3b. The stone drone: each right strike adds a voice, a wrong strike sours it, the solution blooms.
            func drones(_ events: [GameEvent]) -> [String] { events.compactMap {
                switch $0 { case .drone(let i, let on): return "d\(i)\(on ? "+" : "-")"; case .droneSour: return "sour"; case .droneBloom: return "bloom"; default: return nil } } }
            g = freshGame()
            g.puzzle.strike(.tide); g.puzzle.strike(.wind)
            check(drones(g.drainEvents()) == ["d0+", "d1+"], "each correct strike switches on its drone voice")
            g.puzzle.strike(.tide)
            check(drones(g.drainEvents()) == ["sour"], "a wrong strike sours the drone")
            g = freshGame()
            for id in LighthousePuzzle.order { g.puzzle.strike(id); g.simulate(seconds: 0.7) }
            check(drones(g.drainEvents()) == ["d0+", "d1+", "d2+", "bloom"], "the full order builds the chord and blooms it")
            // the synth renders the drone: it adds audible energy when on, and the mix never clips
            func droneBlock(_ on: Bool) -> [Float] {
                let synth = AmbienceSynth(sampleRate: 44100)
                if on { for i in 0..<3 { synth.setDrone(i, on: true) } }
                var l = [Float](repeating: 0, count: 44100 * 3), r = l
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    var done = 0
                    while done < 44100 * 3 { synth.render(frames: 512, left: lp.baseAddress! + done, right: rp.baseAddress! + done); done += 512 }
                } }
                return Array(l[(44100 * 2)...])
            }
            func rmsOf(_ a: [Float]) -> Float { (a.reduce(0) { $0 + $1 * $1 } / Float(a.count)).squareRoot() }
            let bOff = droneBlock(false), bOn = droneBlock(true)
            let droneRms = rmsOf(zip(bOn, bOff).map { $0 - $1 })     // the synth noise is seeded, so the difference is the drone alone
            check(droneRms > 0.02 && (bOn.map { abs($0) }.max() ?? 2) < 1.0, "the drone is clearly audible and the mix never clips (drone rms \(String(format: "%.4f", droneRms)) over a bed of \(String(format: "%.4f", rmsOf(bOff))))")

            // 3c. The notebook: stones are *seen* by walking up to them, *struck* by striking, and only struck ones can be tapped to hear.
            g = freshGame()
            check(Notebook.flags.allSatisfy { !g.state.has($0) }, "a new game has an empty notebook")
            g.player = Player(position: StoneID.wind.position + SIMD3(0, 0, 5), yaw: 0)
            g.simulate(seconds: 0.2)
            check(g.state.has("seen_wind") && !g.state.has("seen_tide") && !g.state.has("struck_wind"), "walking up to the wind stone notes its glyph as seen (not struck)")
            _ = g.drainEvents(); g.playNotebookTone(1)
            check(g.drainEvents().isEmpty, "a seen-but-unstruck glyph makes no sound when tapped")
            g.puzzle.strike(.tide)
            check(g.state.has("struck_tide") && g.state.has("seen_tide"), "striking a stone enters it in the notebook")
            _ = g.drainEvents(); g.playNotebookTone(0)
            check(chimes(g.drainEvents()) == [.tide], "tapping a struck glyph plays that stone's tone")
            var tabIn = InputState(); tabIn.tabPressed = true
            g.journal.isOpen = true
            g.advance(now: 100, input: tabIn)
            check(g.journal.tab == .notebook, "Tab switches the journal to the notebook")
            g.advance(now: 100.1, input: tabIn)
            check(g.journal.tab == .pages, "Tab switches back to the pages")
            g.journal.isOpen = false
            let nbSave = g.makeSave()
            let nbGame = freshGame(); nbGame.restore(nbSave)
            check(nbGame.state.has("struck_tide") && nbGame.state.has("seen_wind") && !nbGame.state.has("struck_wind"), "the notebook survives a save and restore")

            // 3d. One shared vocabulary: the Glass Wood's murals, pane colours and chime pitches all restate Varrow's stones.
            check(LighthousePuzzle.order == StoneID.allCases, "Varrow's solution order is the stones' own order (tide, wind, stone)")
            check(MirrorCourt.solutionPanes.map { GlassPuzzleProps.color($0) } == LighthousePuzzle.order.map(\.color), "the mirror court's pane colours, in order, are the stones' colours in solution order")
            check(GlassWoodLogic.chimeSolution.map { ToneTable.glassHz[$0] } == LighthousePuzzle.order.map { ToneTable.stoneHz[$0.rawValue] }, "the chime puzzle's solution pitches are the stones' tones in solution order")
            check(zip(ToneTable.droneHz, ToneTable.stoneHz).allSatisfy { abs($0 * 2 - $1) < 0.01 }, "the stone drone is exactly an octave under the stones' tones")
            check(ToneTable.stoneHz == [293.66, 440.00, 587.33] && ToneTable.stoneHz[0] < ToneTable.stoneHz[1] && ToneTable.stoneHz[1] < ToneTable.stoneHz[2], "the stones' tones rise in solution order")

            // 3e. WorldPuzzle: the save's flag list is derived from the registered puzzles, and clicks route to the owning puzzle.
            g = freshGame()
            check(g.puzzles.count == 1 && g.puzzles[0].world == .varrow, "Varrow-only games register one puzzle")
            check(Set(g.persistentFlags) == Set(["solved", "lighthouseLit", "causewayUp", "lensTouched"] + Notebook.flags), "persistent flags come from the puzzles (+ lensTouched)")
            g.activate("stone_tide")
            check(g.state.has("lit_tide"), "activating a stone id routes to the lighthouse puzzle")
            let both = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
            check(both.puzzles.map(\.world) == [.varrow, .glassWood], "a game with both worlds registers both puzzles")
            check(Set(["gw_mirrors", "gw_chimes", "gw_altar", "gw_end"]).isSubset(of: Set(both.persistentFlags)), "the Glass Wood's flags appear in the derived save list")
            check(!both.puzzles[1].handles("gw_return") && both.puzzles[1].handles("gw_mirror_0") && !both.puzzles[0].handles("gw_mirror_0"), "ownership: the return ring is the game's, mirrors are the Glass Wood's")

            // 3f. The link changes the home island: the beam fades in once the lamp is lit; the mist thins after the first trip through the lens.
            g = freshGame()
            check(g.mistScale == 1 && g.beamAmount == 0, "a fresh island has full mist and no beam")
            g.simulate(seconds: 10)
            check(g.mistScale == 1 && g.beamAmount == 0, "nothing changes by itself")
            g.puzzle.forceSolved(); g.simulate(seconds: 1)
            check(g.beamAmount > 0.05 && g.beamAmount < 0.9 && g.mistScale == 1, "once the lamp is lit the beam fades in gradually (\(g.beamAmount)); the mist is unchanged")
            g.simulate(seconds: 13)
            check(g.beamAmount > 0.95 && g.mistScale == 1, "the beam reaches full strength; the mist is still untouched before the trip")
            g.state.set("lensTouched"); g.simulate(seconds: 3)
            check(g.mistScale < 1 && g.mistScale > Game.thinMist + 0.05, "after the first trip through the lens the mist begins to thin slowly (\(g.mistScale))")
            g.simulate(seconds: 70)
            check(abs(g.mistScale - Game.thinMist) < 0.01 && g.mistScale >= Game.thinMist - 1e-4, "the mist settles at its thinner level and never below it")
            let atm = freshGame(); atm.puzzle.forceSolved(); atm.state.set("lensTouched"); atm.settleAtmosphere()
            check(atm.mistScale == Game.thinMist && atm.beamAmount == 1, "loading a travelled, solved game starts with the island already changed")
            let atm2 = freshGame(); atm2.restore(atm.makeSave())
            check(atm2.mistScale == Game.thinMist && atm2.beamAmount == 1, "restoring a save settles the atmosphere instantly")

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
            // Version 2: puzzle flags per world; version 1 (one flat list) migrates on load.
            let v2 = g.makeSave()
            check(v2.version == 2 && v2.worldFlags["varrow"]?.contains("solved") == true && v2.worldFlags["game"] == ["lensTouched"] && v2.worldFlags["glassWood"] == nil, "a v2 save files flags under their world (solved -> varrow, lensTouched -> game)")
            let v1json = """
            {"version":1,"flags":["solved","lighthouseLit","causewayUp","lensTouched","gw_mirrors","gw_end","struck_tide"],"pages":[1,5],
             "position":[175,0.8,205],"yaw":0.5,"pitch":0,"playTime":42,"world":"varrow"}
            """
            try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
            try? v1json.write(to: SaveStore.url, atomically: true, encoding: .utf8)
            let mig = SaveStore.load()
            check(mig?.version == 2 && mig?.worldFlags["varrow"]?.sorted() == ["causewayUp", "lighthouseLit", "solved", "struck_tide"] && mig?.worldFlags["glassWood"]?.sorted() == ["gw_end", "gw_mirrors"] && mig?.worldFlags["game"] == ["lensTouched"], "a v1 save loads and its flat flags are sorted into worlds")
            let migGame = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
            if let m = mig { migGame.restore(m) }
            check(migGame.state.has("solved") && migGame.state.has("lensTouched") && migGame.state.has("gw_mirrors") && migGame.state.has("struck_tide") && migGame.journal.collectedPages.map(\.number) == [1, 5], "a migrated v1 save restores its progress and pages")
            try? SaveStore.save(mig!)
            let rewritten = (try? String(contentsOf: SaveStore.url, encoding: .utf8)) ?? ""
            check(rewritten.contains("\"worldFlags\"") && !rewritten.contains("\"flags\"") && SaveStore.load() == mig, "saving a migrated game writes v2 and it reads back identically")
            // A flag in the wrong bucket is ignored by a puzzle that does not own that world: no cross-world leakage.
            var leaky = g.makeSave(); leaky.worldFlags["glassWood"] = ["solved"]
            let leakGame = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]); leakGame.restore(leaky)
            check(leakGame.state.has("solved"), "(Varrow's own bucket still restores) ...")
            var onlyGlass = g.makeSave(); onlyGlass.worldFlags["varrow"] = nil
            let og = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)]); og.restore(onlyGlass)
            check(!og.state.has("solved"), "...and a world's flags come only from that world's bucket")
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
            check(g.interactables.map(\.id).contains("gw_return") && !g.interactables.map(\.id).contains("lens") && g.drainEvents().contains(.worldChanged(.glassWood)), "the Glass Wood has its own interactables (and not Varrow's) and a worldChanged event was emitted")
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
            let old = SaveData(worldFlags: ["varrow": ["solved"]], pages: [], position: [175, 0.8, 205], yaw: 0, pitch: 0, playTime: 1, world: nil)
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
        if name == "all" || name == "chimegame" {
            func fresh() -> Game {
                let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
                g.travel(to: .glassWood); _ = g.drainEvents(); return g
            }
            func item(_ g: Game, _ name: String) -> DrawItem { g.scenes[.glassWood]!.items.first { $0.name == name }! }
            func chimes(_ e: [GameEvent]) -> [ChimeKind] { e.compactMap { if case .chime(let k) = $0 { return k } else { return nil } } }

            var g = fresh()
            check((0..<5).allSatisfy { g.interactables.map(\.id).contains("gw_chime_\($0)") }, "all five glass chimes are interactable")
            check(GlassPuzzleProps.chimeHeights == GlassPuzzleProps.chimeHeights.sorted(by: >), "taller chimes are lower in pitch (heights fall as pitch rises)")
            let ringDist = (0..<5).map { distance(SIMD2(GlassPuzzleProps.chimePosition($0).x, GlassPuzzleProps.chimePosition($0).z), SIMD2(GlassLayout.chimeRing.x, GlassLayout.chimeRing.z)) }
            check(ringDist.allSatisfy { abs($0 - GlassPuzzleProps.chimeRadius) < 0.01 } && ringDist.max()! < GlassLayout.pads[3].radius - 2, "the chimes stand on a ring inside the flat pad")

            // A decoy first: fail, reset after 0.8 s.
            g.glass!.strikeChime(1)
            check(chimes(g.drainEvents()) == [.glass1, .fail] && g.glass!.chimeSequence.isEmpty, "a decoy chime rings and fails")
            g.simulate(seconds: 1)
            g.glass!.strikeChime(0)
            check(g.glass!.chimeSequence == [0], "after the reset the right first tone (D4 = tide) is accepted")
            g.simulate(seconds: 0.2)
            g.glass!.strikeChime(3)                                                  // decoy in the middle
            check(g.glass!.chimeSequence == [0], "a decoy mid-sequence fails without adding to it")
            g.glass!.strikeChime(2)                                                  // during the reset delay: ignored
            check(g.glass!.chimeSequence == [0], "strikes during the reset delay are ignored")
            g.simulate(seconds: 1)
            check(g.glass!.chimeSequence.isEmpty, "the whole sequence resets after a mistake")

            // The right order: D4, A4, D5 (tide, wind, stone tones).
            _ = g.drainEvents()
            for k in GlassWoodLogic.chimeSolution { g.glass!.strikeChime(k); g.simulate(seconds: 0.6) }
            check(g.state.has("gw_chimes"), "D4, A4, D5 in order solves the chimes")
            g.simulate(seconds: 4)
            let evs = chimes(g.drainEvents())
            check(evs.prefix(3) == [.glass0, .glass2, .glass4] && evs.contains(.ignite) && evs.filter { $0 == .glass0 }.count == 2, "each strike rings, then the three tones sound together and the shimmer follows (\(evs.prefix(8)))")
            check(!item(g, "page_7").hidden && g.interactables.first { $0.id == "page_7" }?.enabled == true, "Oren's page 7 appears at the chime ring")
            check(!item(g, "gw_column_chimes").hidden && item(g, "gw_column_chimes").uniforms.model.columns.1.y > 40, "an amber column of light rises from the ring")
            g.glass!.strikeChime(1)
            check(g.state.has("gw_chimes") && g.glass!.chimeSequence == GlassWoodLogic.chimeSolution, "solved stays solved; later strikes just ring")

            // Persistence.
            let tmp = NSTemporaryDirectory() + "lw-chime-\(getpid())"
            setenv("LANTERNWRIGHT_SAVE_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_SAVE_DIR") }
            try? SaveStore.save(g.makeSave())
            let h = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
            if let save = SaveStore.load() { h.restore(save) }
            check(h.state.has("gw_chimes") && !h.scenes[.glassWood]!.items.first { $0.name == "page_7" }!.hidden && !h.state.has("gw_mirrors"), "a save keeps the chimes solved (and the mirrors unsolved)")

            // The three solution chimes really are the Varrow stones' pitches.
            let sr: Float = 44100
            func render(_ kind: ChimeKind) -> [Float] {
                let synth = AmbienceSynth(sampleRate: sr); synth.windGain = 0; synth.surfGain = 0; synth.master = 1; synth.play(kind)
                var l = [Float](repeating: 0, count: Int(sr)), r = l
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    var d = 0; while d < Int(sr) { let c = min(512, Int(sr) - d); synth.render(frames: c, left: lp.baseAddress! + d, right: rp.baseAddress! + d); d += c }
                } }
                return l
            }
            func energy(_ x: [Float], hz: Float) -> Float {
                let w = 2 * Float.pi * hz / sr, c = 2 * cos(w); var s1: Float = 0, s2: Float = 0
                for v in x { let s0 = v + c * s1 - s2; s2 = s1; s1 = s0 }
                return s1 * s1 + s2 * s2 - c * s1 * s2
            }
            for (glassKind, hz, name) in [(ChimeKind.glass0, Float(293.66), "D4"), (.glass1, 369.99, "F#4"), (.glass2, 440.0, "A4"), (.glass3, 523.25, "C5"), (.glass4, 587.33, "D5")] {
                let x = render(glassKind)
                check(energy(x, hz: hz) > 15 * energy(x, hz: hz * 1.12), "glass chime \(name) rings at its pitch")
            }
            let a = render(.glass0), b = render(.tide)
            check(energy(a, hz: 293.66) > 15 * energy(a, hz: 440) && energy(b, hz: 293.66) > 15 * energy(b, hz: 440), "chime 0 and Varrow's tide stone share the pitch D4 (so the player's memory of the stone is the key)")
            check(energy(render(.glass2), hz: 440) > 15 * energy(render(.wind), hz: 440 * 1.12) && energy(render(.wind), hz: 440) > 15 * energy(render(.wind), hz: 440 * 1.12), "chime 2 and the wind stone share A4")
            let tick = render(.glassTick)
            // The chime bus is an 8-line FDN reverb: no discrete echo, a faint wash from ~25 ms. The tick must leave only that.
            let early = tick[0..<4000].map { abs($0) }.max() ?? 0, dryLate = tick[Int(sr * 0.26)..<Int(sr * 0.35)].map { abs($0) }.max() ?? 1
            check(early > 0.02 && dryLate < early * 0.15, "the mirror tick is short: only a faint reverb wash is left at 0.3 s (peak \(String(format: "%.2f", early)) -> \(String(format: "%.4f", dryLate)) at 0.3 s)")
        }
        if name == "all" || name == "altar" {
            func fresh() -> Game {
                let g = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
                g.travel(to: .glassWood); _ = g.drainEvents(); return g
            }
            func item(_ g: Game, _ name: String) -> DrawItem { g.scenes[.glassWood]!.items.first { $0.name == name }! }
            func enabled(_ g: Game, _ id: String) -> Bool { g.interactables.first { $0.id == id }?.enabled == true }

            var g = fresh()
            check(item(g, "gw_altar_ilse").hidden && item(g, "gw_altar_oren").hidden && !enabled(g, "gw_altar_ilse") && !enabled(g, "gw_altar_oren"), "the altar's pedestals are hidden and inert at the start")
            g.glass!.touchAltar(0)
            check(g.banner == nil && !g.state.has("gw_ilse_heard"), "touching a dormant altar does nothing")

            // One puzzle is not enough, in either order.
            g.glass!.forceMirrorsSolved(); g.glass!.checkAltar(); g.simulate(seconds: 6)
            check(!g.state.has("gw_altar") && item(g, "gw_altar_ilse").hidden, "solving only the mirrors does not wake the altar")
            g = fresh()
            g.glass!.forceChimesSolved(); g.glass!.checkAltar(); g.simulate(seconds: 6)
            check(!g.state.has("gw_altar"), "solving only the chimes does not wake it either")

            // Both, by really playing the second puzzle: chimes first, then the mirrors.
            g = fresh()
            for k in GlassWoodLogic.chimeSolution { g.glass!.strikeChime(k); g.simulate(seconds: 0.6) }
            g.simulate(seconds: 5)
            check(g.state.has("gw_chimes") && !g.state.has("gw_altar"), "chimes solved first: the altar is still asleep")
            g.glass!.setArrangement(mirrors: MirrorCourt.solutionMirrors, panes: MirrorCourt.solutionPanes)
            g.simulate(seconds: 5)
            check(g.state.has("gw_mirrors") && g.state.has("gw_altar"), "then the mirrors: the altar wakes (either order works)")
            check(g.banner?.contains("woken") == true, "a line of text announces it (\"\(g.banner ?? "")\")")
            check(!item(g, "gw_altar_ilse").hidden && !item(g, "gw_altar_oren").hidden && !item(g, "gw_column_altar").hidden, "the pedestals and a column of light appear")
            check(!enabled(g, "gw_altar_ilse") && item(g, "page_8").hidden, "…but they are not touchable until they have finished rising")
            g.simulate(seconds: 5)
            check(enabled(g, "gw_altar_ilse") && enabled(g, "gw_altar_oren") && !item(g, "page_8").hidden && enabled(g, "page_8"), "once risen, both lights can be touched and Oren's last page (8) appears")
            let sunk = item(g, "gw_altar_ilse").uniforms.model.columns.3.y
            check(abs(sunk - GlassLayout.altar.y) < 0.05, "the pedestals have risen to ground level (y \(String(format: "%.2f", sunk)) vs \(String(format: "%.2f", GlassLayout.altar.y)))")

            // Hearing the two accounts.
            g.activate("gw_altar_ilse")
            check(g.state.has("gw_ilse_heard") && g.banner?.hasPrefix("Ilse:") == true && !g.state.has("gw_end"), "Ilse's account is shown; the end is not reached with only one")
            g.activate("gw_altar_oren")
            check(g.state.has("gw_oren_heard") && g.banner?.hasPrefix("Oren:") == true && g.state.has("gw_end"), "Oren's account is shown; hearing both reaches the end of the second world")
            g.simulate(seconds: 8)
            check(g.banner?.contains("choose") == true, "after a pause the closing line sets up the choice (\"\(g.banner ?? "")\")")
            g.simulate(seconds: 12)
            check(g.banner == nil, "banners clear themselves")

            // A save keeps all of it; returning to Varrow acknowledges it.
            let tmp = NSTemporaryDirectory() + "lw-altar-\(getpid())"
            setenv("LANTERNWRIGHT_SAVE_DIR", tmp, 1)
            defer { try? FileManager.default.removeItem(atPath: tmp); unsetenv("LANTERNWRIGHT_SAVE_DIR") }
            try? SaveStore.save(g.makeSave())
            let h = Game(scenes: [.varrow: Scene.makeWorld(device: device), .glassWood: GlassWood.build(device: device)])
            if let save = SaveStore.load() { h.restore(save) }
            check(h.state.has("gw_altar") && h.state.has("gw_end") && enabled(h, "gw_altar_oren") && !h.scenes[.glassWood]!.items.first { $0.name == "page_8" }!.hidden, "a save restores the awakened altar and the story flags")
            h.activate("gw_return"); h.simulate(seconds: Game.fadeOutSeconds + 0.1)
            check(h.world == .varrow && h.banner?.contains("two accounts") == true, "returning to Varrow after the end acknowledges it (\"\(h.banner ?? "")\")")
        }
        return ok
    }
}

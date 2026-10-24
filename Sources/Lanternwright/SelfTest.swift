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
            check(MemoryLayout<FrameUniforms>.stride == 288, "FrameUniforms stride 288")
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
            check(secs.max()! > 2 * secs.min()!, "surf swells and recedes (loudest second \(String(format: "%.3f", secs.max()!)) vs quietest \(String(format: "%.3f", secs.min()!)))")
            // A footstep adds a transient on top of silence.
            let step = renderSeconds { $0.windGain = 0; $0.surfGain = 0; $0.stepSurface = .stone; $0.stepCounter = 1 }
            check(rms(step[0..<2000]) > 0.01 && rms(step[Int(sr)...]) < 1e-4, "a footstep is a short burst that dies away (first 45 ms rms \(String(format: "%.3f", rms(step[0..<2000]))))")
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
            check(JournalContent.pages.count == 4 && JournalContent.pages.allSatisfy { !$0.text.isEmpty }, "all four journal pages have text")
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

            // The lens does nothing until the causeway is up, then starts the fade to white.
            g = freshGame()
            g.activate("lens"); g.simulate(seconds: 2.5)
            check(!g.state.has("lensTouched") && g.whiteout == 0, "the lens is inert before the puzzle is solved")
            g.puzzle.forceSolved(); g.activate("lens"); g.simulate(seconds: 2.2)
            check(g.state.has("lensTouched") && g.whiteout == 1, "touching the lens fades the world to white over 2 s")

            // Page positions are on the ground and reachable.
            g = freshGame()
            for n in 1...4 {
                let p = PuzzleProps.pagePosition(n, terrain: g.scene.terrain)
                let gnd = g.scene.groundHeight(x: p.x, z: p.z)
                check(p.y >= gnd - 0.01 && p.y - gnd < 0.7, "page \(n) lies on the ground (\(String(format: "%.2f", p.y - gnd)) m above it)")
            }
        }
        return ok
    }
}

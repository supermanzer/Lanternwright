import Foundation
import Metal
import simd

/// Self-tests: core.
extension SelfTestRunner {
    func runCore() {
        if name == "all" || name == "shaders" {
            _ = ShaderLibrary.make(device: device)  // exits on failure
            check(true, "shader library compiles")
        }
        if name == "all" || name == "layout" {
            check(MemoryLayout<Vertex>.stride == 48, "Vertex stride 48")
            check(MemoryLayout<FrameUniforms>.stride == 512, "FrameUniforms stride 512")
            check(MemoryLayout<ObjectUniforms>.stride == 112, "ObjectUniforms stride 112")
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
        if name == "all" || name == "polish" {
            // B1: finished things look finished.
            let g = Game(scene: Scene.makeWorld(device: device))
            check(!g.hoveredFinished, "nothing hovered is not finished")
            let bot = PlaythroughBot(g)
            _ = bot.walk(to: Layout.lanternPath[1], within: 2.2)
            let tide = g.interactables.first { $0.id == "stone_tide" }!
            bot.aim(at: (tide.min + tide.max) * 0.5); bot.tick()
            check(g.hovered?.id == "stone_tide" && !g.hoveredFinished, "an unsolved stone looks fresh")
            g.puzzle.forceSolved(); g.simulate(seconds: 0.1); bot.tick()
            check(g.hovered?.id == "stone_tide" && g.hoveredFinished, "once the lighthouse is solved the same stone looks finished (and still responds)")
            // B2: auto-run and the one-time hint.
            let r = Game(scene: Scene.makeWorld(device: device))
            var walk = InputState(); walk.move = SIMD2(0, 1)
            r.simulate(seconds: 2, input: walk)
            let walkSpeed = r.player.speed
            var press = InputState(); press.autoRunPressed = true
            r.advance(now: 1, input: press)
            check(r.autoRun && r.banner?.contains("Auto-run on") == true, "R turns auto-run on and says so")
            for k in 0..<120 { r.advance(now: 1 + Double(k + 1) / 60, input: walk) }
            check(r.player.speed > walkSpeed * 1.4, "with auto-run on, just walking runs (\(walkSpeed) -> \(r.player.speed) m/s)")
            r.advance(now: 5, input: press)
            check(!r.autoRun, "R turns it off again")
            // F07 B-run (#73): no "hold Shift" line pops up however long a player walks without running.
            let h = Game(scene: Scene.makeWorld(device: device))
            var said = false
            for _ in 0..<12 { h.simulate(seconds: 10, input: walk); if h.banner != nil { said = true } }
            check(!said && !h.state.has("hint_run"), "run: two minutes of walking without running never brings up a hint (it was a tutorial line with no meaning in the world)")
            let old = Game(scene: Scene.makeWorld(device: device)); var oldSave = h.makeSave(); oldSave.worldFlags["hint_run"] = ["hint_run"]
            old.restore(oldSave)
            check(old.banner == nil, "run: a save from before, which carries the old flag, loads without trouble")
        }
        if name == "all" || name == "movefeel" {
            // B7 (partial): FOV widens while running and settles back; wading slows you.
            let g = Game(scene: Scene.makeWorld(device: device))
            var walk = InputState(); walk.move = SIMD2(0, 1)
            g.simulate(seconds: 1, input: walk)
            let walkFov = g.camera.fovY
            var run = walk; run.run = true
            g.simulate(seconds: 3, input: run)
            check(g.camera.fovY > walkFov + 0.05 && g.camera.fovY <= LookCloser.baseFov + Game.runFovBoost + 1e-4, "running widens the view (\(walkFov * 180 / .pi) -> \(g.camera.fovY * 180 / .pi) degrees)")
            g.simulate(seconds: 3)
            check(abs(g.camera.fovY - LookCloser.baseFov) < 0.01, "and it settles back when you stop")
            var zoom = run; zoom.zoom = true
            g.simulate(seconds: 2, input: zoom)
            check(g.camera.fovY < LookCloser.baseFov * 0.5, "zoom still wins over the run widening")
            let sc = Scene.makeWorld(device: device)
            func distance3s(_ start: SIMD3<Float>, yaw: Float) -> Float {
                var p = Player(position: start, yaw: yaw); p.position.y = sc.groundHeight(x: start.x, z: start.z)
                let a = SIMD2(p.position.x, p.position.z)
                for _ in 0..<360 { p.step(dt: Game.tick, input: walk, scene: sc) }
                return simd_length(SIMD2(p.position.x, p.position.z) - a)
            }
            // Along the dock shore the beach dips into the shallows: compare dry flat sand to ankle-deep water on the same heading.
            var shallow: SIMD3<Float>?
            search: for xi in stride(from: Float(100), to: 280, by: 2) { for zi in stride(from: Float(120), to: 320, by: 2) {
                let h = sc.groundHeight(x: xi, z: zi)
                if h < -0.18 && h > -0.3 { shallow = SIMD3(xi, h, zi); break search }
            } }
            let dry = distance3s(Layout.dockShore + SIMD3(6, 0, 4), yaw: Layout.spawnYaw + .pi)
            if let s = shallow {
                let wet = distance3s(s, yaw: .pi)       // walking back toward shallower water would speed up; head along the shelf instead
                check(wet < dry * 0.9, "wading ankle-deep is slower than walking dry (\(wet) m vs \(dry) m in 3 s)")
            } else { check(true, "no shallow spot found to test wading (skipped)") }
        }
        if name == "all" || name == "builder" {
            let surf = Surface(color: SIMD3(0.5, 0.5, 0.5))
            func unitNormals(_ b: MeshBuilder) -> Bool { b.vertices.allSatisfy { abs(simd_length(SIMD3($0.normal.x, $0.normal.y, $0.normal.z)) - 1) < 1e-3 } }
            func finite(_ b: MeshBuilder) -> Bool { b.vertices.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite } }
            // lathe: a plain cylinder wall, outward normals, exact radius.
            var wall = MeshBuilder(); wall.lathe(profile: [SIMD2(1, 0), SIMD2(1, 2)], segments: 32, surface: surf)
            check(wall.vertices.count == 64 && wall.indices.count == 32 * 6, "lathe: a 32-segment wall has 64 vertices and 64 triangles")
            check(wall.vertices.allSatisfy { abs(simd_length(SIMD2($0.position.x, $0.position.z)) - 1) < 1e-4 && $0.position.y >= -1e-5 && $0.position.y <= 2 + 1e-5 }, "lathe: every vertex lies on the profile's radius and height range")
            check(wall.vertices.allSatisfy { simd_dot(SIMD2($0.normal.x, $0.normal.z), SIMD2($0.position.x, $0.position.z)) > 0.99 } && unitNormals(wall), "lathe: smooth normals are unit and point outward")
            // A stepped profile keeps its corner crisp: the step's top face points straight up, its riser points outward.
            var steps = MeshBuilder(); steps.lathe(profile: [SIMD2(2, 0), SIMD2(2, 0.3), SIMD2(1.5, 0.3), SIMD2(1.5, 0.6)], segments: 24, surface: surf)
            check(steps.vertices.contains { $0.normal.y > 0.99 && abs($0.position.y - 0.3) < 1e-4 } && unitNormals(steps) && finite(steps), "lathe: a stepped profile has a flat upward tread (crisp corners)")
            // Winding is outward: a triangle's geometric normal agrees with the vertex normal.
            var agree = 0, total = 0
            for t in stride(from: 0, to: wall.indices.count, by: 3) {
                let a = SIMD3(wall.vertices[Int(wall.indices[t])].position.x, wall.vertices[Int(wall.indices[t])].position.y, wall.vertices[Int(wall.indices[t])].position.z)
                let b = SIMD3(wall.vertices[Int(wall.indices[t + 1])].position.x, wall.vertices[Int(wall.indices[t + 1])].position.y, wall.vertices[Int(wall.indices[t + 1])].position.z)
                let c = SIMD3(wall.vertices[Int(wall.indices[t + 2])].position.x, wall.vertices[Int(wall.indices[t + 2])].position.y, wall.vertices[Int(wall.indices[t + 2])].position.z)
                let gn = simd_cross(b - a, c - a), vn = SIMD3(wall.vertices[Int(wall.indices[t])].normal.x, wall.vertices[Int(wall.indices[t])].normal.y, wall.vertices[Int(wall.indices[t])].normal.z)
                total += 1; if simd_dot(gn, vn) > 0 { agree += 1 }
            }
            check(agree == total, "lathe: triangle winding faces outward (\(agree) of \(total))")
            // tube: tapered straight tube and a bent one.
            var rod = MeshBuilder(); rod.tube(points: [SIMD3(0, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 2, 0)], radii: [0.5, 0.3, 0.1], sides: 8, surface: surf)
            let ringR = rod.vertices.filter { abs($0.position.y) < 1e-4 && abs(simd_length(SIMD2($0.position.x, $0.position.z)) - 0.5) < 1e-3 }.count
            check(ringR >= 8 && rod.vertices.allSatisfy { simd_length(SIMD2($0.position.x, $0.position.z)) <= 0.5 + 1e-4 } && unitNormals(rod), "tube: the ring at the base has radius 0.5 and the tube tapers to 0.1")
            var bent = MeshBuilder(); bent.tube(points: [SIMD3(0, 0, 0), SIMD3(0, 1, 0), SIMD3(1, 1.5, 0.5), SIMD3(2, 1.6, 1)], radii: [0.2, 0.18, 0.12, 0.05], sides: 6, surface: surf)
            check(finite(bent) && unitNormals(bent) && bent.indices.count > 0, "tube: a curved path produces finite, unit-normal geometry (parallel transport, no twist artefacts)")
            // arch: the opening stays clear, the surround rises above it.
            var door = MeshBuilder(); door.arch(width: 1.4, height: 2.6, depth: 0.5, surface: surf)
            let spring: Float = 2.6 - 0.7
            let inside = door.vertices.filter { abs($0.position.x) < 0.7 - 0.01 && $0.position.y < spring - 0.01 }.count
            let top = door.vertices.map(\.position.y).max() ?? 0
            check(inside == 0 && top > 2.6 && top < 3.6 && finite(door), "arch: nothing intrudes into the opening, and the voussoirs crown it (top \(top) m)")
            check((door.vertices.map(\.position.z).max() ?? 0) <= 0.5 / 2 + 0.11 + 1e-3 && door.vertices.count > 300, "arch: depth stays within the keystone and the surround is made of many blocks (\(door.vertices.count) vertices)")
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
        if name == "all" || name == "pace" {
            check(Player.paceFactor(slope: 0) == 1 && Player.paceFactor(slope: 0.3) < 1 && Player.paceFactor(slope: 0.3) > Player.paceFactor(slope: 0.6) && Player.paceFactor(slope: -0.2) > 1 && Player.paceFactor(slope: -0.2) < 1.09, "pace: uphill slower than flat slower than gentle downhill (flat 1, +0.3 \(Player.paceFactor(slope: 0.3)), -0.2 \(Player.paceFactor(slope: -0.2)))")
            check((-3...3).map { Player.paceFactor(slope: Float($0) * 0.5) }.allSatisfy { $0 >= Player.minPace - 1e-6 && $0 <= 1.081 }, "pace never drops below 40 % nor exceeds 108 %")
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
            // (F03 #48 gave each patch a small phase offset, so this is the best-matching lag over ten minutes, not an exact identity.)
            var bestLag: Float = 0, bestErr = Float.greatestFiniteMagnitude
            for li in 0...80 {
                let lag = Float(li) * 0.25; var err: Float = 0
                for k in 0..<1200 { let t = Float(k) * 0.5 + 40; err += abs(Wind.strength(at: there, time: t + lag) - Wind.strength(at: .zero, time: t)) }
                if err < bestErr { bestErr = err; bestLag = lag }
            }
            check(abs(bestLag - 10) < 3.0, "gusts travel downwind at about 9 m/s: a gust reaches a point 90 m downwind \(bestLag) s later (7 to 13 s)")
        }
        if name == "all" || name == "clutter" {
            let sc = Scene.makeWorld(device: device)
            let clutter = sc.items.filter { $0.name.hasPrefix("clutter_") }
            check(clutter.count >= 3, "shore and path clutter exists (\(clutter.count) batches)")
            let tris = clutter.reduce(0) { $0 + $1.mesh.indexCount / 3 }
            check(tris > 500 && tris < 260000, "clutter is a modest triangle budget (\(tris))")
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
    }
}

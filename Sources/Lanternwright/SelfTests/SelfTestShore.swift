import Foundation
import Metal
import simd

/// Self-tests: waves meeting the island (F03 G2, note #34). The functions in World/Shore.swift are the ones the water and terrain shaders run (generated as Metal), so they are
/// tested here on the real terrain: crests slow and shoal toward the shore, the sheet at the contact line is a film that thins to nothing and does not rise vertically, the swash
/// runs up fast and drains slowly in groups, and the sheltered side of the island is reached later and by smaller waves than the windward side.
extension SelfTestRunner {
    func runShore() {
        guard name == "all" || name == "shore" else { return }
        let verbose = name == "shore"
        // The functions.
        check(Shore.delay(depth: 6, slope: 0.1) == 0 && Shore.delay(depth: 1, slope: 0.1) > Shore.delay(depth: 3, slope: 0.1) && Shore.delay(depth: 0.1, slope: 0.05) > Shore.delay(depth: 0.1, slope: 0.2),
              "crests slow in shallow water: no delay at 6 m, more the shallower and the gentler the beach (0.1 m deep: \(String(format: "%.1f", Shore.delay(depth: 0.1, slope: 0.05))) s on a 5 % beach, \(String(format: "%.1f", Shore.delay(depth: 0.1, slope: 0.2))) s on a 20 % one)")
        check(Shore.amplitudeScale(depth: 8) == 1 && Shore.amplitudeScale(depth: 2) > 1.1 && Shore.amplitudeScale(depth: 2) <= 1.5 && Shore.amplitudeScale(depth: 0.02) < 0.002 && Shore.amplitudeScale(depth: -0.3) == 0,
              "waves shoal (x\(String(format: "%.2f", Shore.amplitudeScale(depth: 2))) at 2 m, Green's law, at most 1.5) and die at the contact line (x\(String(format: "%.4f", Shore.amplitudeScale(depth: 0.02))) at 2 cm deep, none over land)")
        var tRise: Float = 0, tDrain: Float = 0
        tRise = (0...1000).map { Float($0) / 1000 }.first { Shore.runup(phase: $0) >= 0.99 } ?? 1
        for k in stride(from: 1000, through: 0, by: -1) { let u = Float(k) / 1000; if u > 0.28 && Shore.runup(phase: u) > 0.01 { tDrain = max(tDrain, u) } }
        check(tRise < 0.30 && Shore.runup(phase: 0) == 0 && abs(Shore.runup(phase: 0.28) - 1) < 1e-3 && tDrain > 0.9 && tRise < 0.4 * 0.72 + 0.1, "the swash runs up fast and drains slowly: up in \(String(format: "%.0f", tRise * 100)) % of the \(Shore.swashPeriod) s cycle, down over the other \(String(format: "%.0f", (1 - 0.28) * 100)) %")
        var lo: Float = 9, hi: Float = -9
        for k in 0..<4000 { let g = Shore.group(x: 100, z: 150, time: Float(k) * 0.5); lo = min(lo, g); hi = max(hi, g) }
        check(hi - lo > 0.4 && lo >= 0.29 && hi <= 1.0001, "wave groups: the run-up swings between \(String(format: "%.2f", lo)) and \(String(format: "%.2f", hi)) of its largest over half an hour")
        let msl = ShaderLibrary.sources.joined(separator: "\n")
        check(msl.contains(Shore.mslSource) && msl.contains("shore_swash(xz, t, shDepth, shSlope)") && msl.contains("shore_wet_reach(P.xz, clock)") && msl.contains("float th = k * dot(d, xz) - omega * shTime;"), "the water vertex stage and the terrain shader use these functions (generated from the same constants)")
        // On the real terrain: shoreline points all round the island.
        let scene = Scene.makeWorld(device: device)
        let t = scene.terrain!
        let centre = SIMD2<Float>(Layout.hillCenter.x, Layout.hillCenter.y)
        var shore: [(p: SIMD2<Float>, slope: Float, up: SIMD2<Float>)] = []
        for a in stride(from: Float(0), to: 360, by: 6) {
            let dir = SIMD2(cos(a * .pi / 180), sin(a * .pi / 180))
            var r: Float = 20, prev = t.sampleHeight(x: centre.x + dir.x * r, z: centre.y + dir.y * r)
            while r < 700 {
                r += 1
                let h = t.sampleHeight(x: centre.x + dir.x * r, z: centre.y + dir.y * r)
                if prev > 0 && h <= 0 {
                    let p = centre + dir * r
                    let gx = (t.sampleHeight(x: p.x + 1, z: p.y) - t.sampleHeight(x: p.x - 1, z: p.y)) / 2, gz = (t.sampleHeight(x: p.x, z: p.y + 1) - t.sampleHeight(x: p.x, z: p.y - 1)) / 2
                    let g = SIMD2(gx, gz), s = simd_length(g)
                    if s > 0.01 { shore.append((p, s, g / s)) }
                    break
                }
                prev = h
            }
        }
        check(shore.count >= 40, "\(shore.count) shoreline transects round the island")
        // The contact line: for each transect and half a minute of swash, the film's thickness 2 cm seaward of the contact, and whether the waves have died there.
        var worstThick: Float = 0, worstWave: Float = 0, checked = 0, steep = 0, maxRise: Float = 0
        for sh in shore {
            if sh.slope > 0.25 { steep += 1; continue }
            var prevL = Shore.swashLevel(x: sh.p.x, z: sh.p.y, time: 0, depth: 0, slope: sh.slope)
            for k in 0..<240 {
                let tm = Float(k) * 0.25
                let level = Shore.swashLevel(x: sh.p.x, z: sh.p.y, time: tm, depth: 0, slope: sh.slope)
                if level > 0.002 {
                    var r: Float = 0                                                          // walk up the real beach, 1 cm at a time, to where the ground meets the sheet
                    while r < 60 && t.sampleHeight(x: sh.p.x + sh.up.x * r, z: sh.p.y + sh.up.y * r) < level { r += 0.01 }
                    let q = sh.p + sh.up * r
                    let seaward = q - sh.up * 0.01
                    let thick = level - t.sampleHeight(x: seaward.x, z: seaward.y)
                    worstThick = max(worstThick, thick); checked += 1
                    worstWave = max(worstWave, Shore.amplitudeScale(depth: -t.sampleHeight(x: q.x, z: q.y)))        // the ground's depth under the sea at the contact point
                }
                maxRise = max(maxRise, abs(level - prevL) / 0.25); prevL = level
            }
        }
        if verbose { print(String(format: "contact line: %d samples on %d transects (%d steeper than 25 %% skipped): film %.1f mm thick 1 cm seaward of the contact at worst; sheet rises at most %.2f m/s", checked, shore.count - steep, steep, worstThick * 1000, maxRise)) }
        check(checked > 500 && worstThick < 0.005, "the sheet at the contact line is a film: its thickness 1 cm seaward of the contact is at most \(String(format: "%.1f", worstThick * 1000)) mm (under 5 mm) over \(checked) samples on beaches up to 25 % steep")
        check(worstWave < 0.002, "and the waves have died there: the open-sea wave height is scaled by \(String(format: "%.4f", worstWave)) at the contact line (it was a full-size wave at any steepness)")
        // The lee: crests reach the sheltered side later and smaller.
        let d = SIMD2<Float>(cos(Shore.waveDirection), sin(Shore.waveDirection))
        var rows: [(Float, Float, Float)] = []                                     // (position along the swell, total delay, lee amplitude)
        for sh in shore {
            let m = Shore.shadow(x: sh.p.x, z: sh.p.y, ground: { t.sampleHeight(x: $0, z: $1) })
            rows.append((simd_dot(d, sh.p - centre), Shore.delay(depth: 0, slope: sh.slope) * 0 + Shore.leeDelay(shadow: m), Shore.leeAmplitude(shadow: m)))
        }
        rows.sort { $0.0 < $1.0 }
        let third = rows.count / 3
        let windward = rows.prefix(third), lee = rows.suffix(third)
        func mean(_ a: ArraySlice<(Float, Float, Float)>, _ f: ((Float, Float, Float)) -> Float) -> Float { a.map(f).reduce(0, +) / Float(max(a.count, 1)) }
        let dW = mean(windward) { $0.1 }, dL = mean(lee) { $0.1 }, aW = mean(windward) { $0.2 }, aL = mean(lee) { $0.2 }
        if verbose { print(String(format: "lee: extra delay windward third %.1f s, lee third %.1f s; wave height windward %.2f, lee %.2f of the open sea's", dW, dL, aW, aL)) }
        check(dL > dW + 2.0 && aL < aW - 0.15, "the lee is reached later and by smaller waves: the sheltered third of the coast gets its crests \(String(format: "%.1f", dL - dW)) s after the windward third (at least 2 s) at \(String(format: "%.0f", aL * 100)) % of the height against \(String(format: "%.0f", aW * 100)) %")
        // The delay along each beach spreads the arrival over seconds: crests do not strike the whole coast together.
        let delays = shore.map { Shore.delay(depth: 0, slope: $0.slope) }
        check((delays.max() ?? 0) - (delays.min() ?? 0) > 3, "beaches of different slope are reached at different times (the shallow-water delay at the contact line spans \(String(format: "%.1f", delays.min() ?? 0)) to \(String(format: "%.1f", delays.max() ?? 0)) s around the island)")
        // ---- G1 (#33): the sand's ripples and the planks' grain, pinned by the numbers in the shaders (the player: "too pronounced... coarse grain... the waves have a longer wavelength").
        func number(_ source: String, after marker: String) -> Float? {
            guard let r = source.range(of: marker) else { return nil }
            let tail = source[r.upperBound...].prefix(24)
            let digits = tail.drop { !"0123456789.".contains($0) }.prefix { "0123456789.".contains($0) }
            return Float(digits)
        }
        let lit = LitShaders.source, ground = GroundShaders.source, mat = MaterialShaders.source, water = WaterShaders.source
        let k = number(lit, after: "float ph = dot(P.xz, float2(0.86, 0.5)) * ") ?? 99
        let wavelength = 2 * Float.pi / k
        check(wavelength >= 1.0 && wavelength <= 3.0 && lit.contains("(1.0 - smoothstep(0.4, 3.0, P.y))") && lit.contains("featVis(1.3, fpix)"), "sand swells are \(String(format: "%.1f", wavelength)) m crest to crest (1 to 3 m), broken up by slow noise, faded from the waterline (gone by 3 m above the sea) and band-limited by pixel footprint")
        let fineRows = ground.contains("* 105.0") || ground.contains("* 85.0)")
        let swellK = number(ground, after: "rfbm3(P * 0.9, 2) - 0.5)) * ") ?? 99
        let albedoAmp = number(ground, after: "o.albedo = col * (1.0 + ") ?? 9
        check(!fineRows && 2 * Float.pi / swellK >= 0.4 && albedoAmp <= 0.01, "the 6 cm rows are gone from the sand: what is left is a swell \(String(format: "%.2f", 2 * Float.pi / swellK)) m across (at least 0.4 m) at \(String(format: "%.1f", albedoAmp * 100)) % contrast (at most 1 %)")
        let ring = number(mat, after: "float ringPos = (r + warp) * ") ?? 999
        let fibreAmp = number(mat, after: "wood *= mix(0.93, 1.04, mix(0.5, late, vGrain)) * (0.95 + ") ?? 9
        check(2 * Float.pi / ring >= 0.10 && fibreAmp <= 0.12, "planks show wide soft figure, not dense lines: growth rings \(String(format: "%.0f", 2 * 100 * Float.pi / ring)) cm apart (at least 10 cm; was 4 cm), fibre streak contrast \(String(format: "%.0f", fibreAmp * 100)) % (at most 12 %; was 24 %)")
        let caustic = number(water, after: "sceneCol += float3(0.9, 1.0, 1.1) * caustic * shallow * ") ?? 9
        check(caustic <= 0.04, "the shallow-water caustics are a faint hint (\(String(format: "%.1f", caustic * 100)) % of the bed's brightness; was 13 %, which read as drawn lines on the sand under thin water)")
    }
}

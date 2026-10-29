import Foundation
import Metal
import simd

/// Self-tests: light casts no shadow (F04 L1, note #57: the white column at the Glass Wood altar threw a hard shadow on the plinth).
extension SelfTestRunner {
    func runLight() {
        guard name == "all" || name == "light" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "light: no Metal device"); return }
        let glass = Scene.make(.glassWood, device: device), home = Scene.makeWorld(device: device)
        // The shadow pass draws an item when `!hidden && castsShadow && lod.w < 0.5` (Passes/ShadowPass.swift). Show a lit column, as it is once the altar is lit.
        var lit = glass
        lit.update("gw_column_altar") { $0.hidden = false }
        let drawn = (lit.items + home.items).filter { !$0.hidden && $0.castsShadow && $0.uniforms.lod.w < 0.5 }
        let glowing = drawn.filter { $0.lightOnly || $0.uniforms.emissive.w >= 3 }.map(\.name)
        check(glowing.isEmpty, "light: no light-only item and no blazing emitter is in the shadow draw list (offenders: \(glowing.prefix(5)))")
        let silent = Set((lit.items + home.items).filter { !$0.castsShadow }.map(\.name))
        let mustBe = ["gw_column_altar", "gw_column", "gw_column_chimes", "gw_altar_glow", "gw_beam_0", "beam_tide", "beam_wind", "beam_stone", "lantern_cores", "lens_core", "lens_ring", "gw_return_core", "gw_source"]
        check(mustBe.allSatisfy { silent.contains($0) }, "light: the beams, columns of light, altar glow, lantern cores, lens and rings are among the \(silent.count) non-casting items (missing: \(mustBe.filter { !silent.contains($0) }))")
        // The solid things around them still cast: the altar's dais and the pillars, the lighthouse, the stones, the dock.
        let casters = Set((lit.items + home.items).filter { $0.castsShadow }.map(\.name))
        let mustCast = ["gw_altar_dais", "gw_arrival_plate", "gw_chime_base", "lighthouse", "dock", "stone_tide", "stone_wind", "stone_stone", "stone_tide_face", "stone_wind_face", "stone_stone_face", "gw_mirror_0", "gw_chime_0", "cap_tide"]
        check(mustCast.allSatisfy { casters.contains($0) }, "light: the plinth, dais, lighthouse, dock, the stones (bodies with their faint glyph glow included), mirrors, chimes and caps still cast their own shadows (missing: \(mustCast.filter { !casters.contains($0) }))")
        let pass = (try? String(contentsOfFile: "Sources/Lanternwright/Render/Passes/ShadowPass.swift", encoding: .utf8)) ?? ""
        check(pass.contains("item.castsShadow"), "light: the shadow pass asks each item whether it casts")
    }
}

extension SelfTestRunner {
    /// G10.2.2: the shared minimum-footprint rule (a thin thing is drawn at least a pixel wide and its coverage is scaled to keep its energy).
    func runThinCoverage() {
        guard name == "all" || name == "thin" else { return }
        // Pixel size from a real camera: 1600 x 900, 60 degrees vertical: one pixel at d metres is 2 d tan(30 deg) / 900.
        let cam = Camera(position: SIMD3(0, 2, 0), yaw: 0.7, pitch: -0.2)
        let vp = cam.proj(aspect: 1600.0 / 900.0) * cam.view
        let target = cam.position + cam.forward * 40
        let px = ThinCoverage.pixelWorldSize(viewProj: vp, worldPos: target, screenHeight: 900)
        let want = 2 * 40 * tan(cam.fovY / 2) / 900
        check(abs(px - want) < 0.02 * want, "thin: one pixel at 40 m is \(String(format: "%.4f", px)) m (expected \(String(format: "%.4f", want)))")
        // A 1 cm twig at 40 m (a pixel is about 5 cm): drawn one pixel wide, a fifth of the coverage. A 20 cm trunk is left alone. Energy (width x coverage) is always the true width.
        let twig = ThinCoverage.thinCoverage(worldWidth: 0.01, footprint: px)
        let trunk = ThinCoverage.thinCoverage(worldWidth: 0.20, footprint: px)
        check(abs(twig.width - px) < 1e-6 && abs(twig.coverage - 0.01 / px) < 1e-5 && trunk.width == 0.20 && trunk.coverage == 1,
              "thin: a 1 cm twig is drawn one pixel wide at coverage \(String(format: "%.2f", twig.coverage)); a 20 cm trunk is untouched")
        var energyOK = true
        for w in [0.0005, 0.003, 0.01, 0.05, 0.3] as [Float] { let c = ThinCoverage.thinCoverage(worldWidth: w, footprint: 0.05, minPixels: 1.5); if abs(c.width * c.coverage - w) > 1e-6 || c.coverage > 1 || c.width < 0.075 - 1e-6 && w < 0.075 { energyOK = false } }
        check(energyOK, "thin: width x coverage equals the true width for every width, coverage never exceeds 1, nothing is drawn thinner than footprint x minPixels")
        let msl = ShaderLibrary.sources.joined(separator: "\n")
        check(msl.contains("inline ThinCover thin_coverage(float worldWidth, float footprint, float minPixels)") && msl.contains("inline float pixel_world_size(float3 worldPos, constant FrameUniforms& frame)")
              && msl.contains("c.width = max(worldWidth, footprint * minPixels);") && msl.contains("c.coverage = worldWidth / max(c.width, 1e-6);"),
              "thin: the shader library carries the same rule (Shaders/Common.swift) with the signatures the grass rewrite uses")
    }
}

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

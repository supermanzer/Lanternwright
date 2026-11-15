import Foundation
import Metal
import simd

/// Self-tests: Phase A10: the dormant machines' dull tick (Q103), the orrery collar's louder click on a notch with an arm (Q104), the receiving crystals' near-miss glow (Q102), the prism chamber's ring and floor marks
/// following the ring step (Q105), and the tide gauge's brass glow and pale stone (Q125 found). Run alone with `--selftest a10`.
extension SelfTestRunner {
    func runA10() {
        guard name == "all" || name == "a10" else { return }
        let sr: Float = 44100
        func render(_ seconds: Float, _ events: [ArchiveAudio.Event]) -> [Float] {
            let a = ArchiveAudio(sampleRate: sr); a.wet = 0
            var q = ArchiveAudio.Inputs(); q.active = false; a.setInputs(q)
            for e in events { a.handle(e) }
            var left = [Float](repeating: 0, count: Int(sr * seconds)), right = left
            var i = 0
            while i < left.count { let n = min(512, left.count - i); left.withUnsafeMutableBufferPointer { lp in right.withUnsafeMutableBufferPointer { rp in a.render(frames: n, left: lp.baseAddress! + i, right: rp.baseAddress! + i) } }; i += n }
            return left
        }
        func rms(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }

        // ---- Q103: the dormant tick: quiet, dull, inside 300-1200 Hz, gone fast.
        let d = render(0.5, [.dormant]), none = render(0.3, []), orrery = render(0.5, [.tick(0, gain: 1)])
        let dPeak = d.map { abs($0) }.max() ?? 0, oPeak = orrery.map { abs($0) }.max() ?? 0
        let partials = DormantTone.ratios.map { DormantTone.hz * $0 }
        let power = partials.map { FootstepAnalysis.power(d, $0) }
        let off = [100, 2500, 4000].map { FootstepAnalysis.power(d, Float($0)) }.max() ?? 0
        check(rms(d[0..<Int(sr * 0.06)]) > 0.0008 && rms(d[Int(sr * 0.2)..<d.count]) < 1e-6 && dPeak < 0.5 * oPeak && partials.allSatisfy { $0 >= 300 && $0 <= 1200 } && power[0] > off * 4 && rms(none[0..<none.count]) < 1e-6,
              "a10: the dormant tick sounds in the first 60 ms, is gone by 0.2 s, peaks at \(String(format: "%.3f", dPeak)) (under half the orrery tick's \(String(format: "%.3f", oPeak))), has its partials in 300-1200 Hz (\(partials.map { String(format: "%.0f", $0) })) and is silent with no event (Q103)")

        // ---- Q104: the collar's click is louder on a notch that has an arm (and only on those).
        let armed = (0..<Orrery.collarDetents).filter { CollarTone.armHere(notch: $0) }, plainNotches = (0..<Orrery.collarDetents).filter { !CollarTone.armHere(notch: $0) }
        let loud = render(0.4, [.collar(armHere: true)]), soft = render(0.4, [.collar(armHere: false)])
        let lPeak = loud.map { abs($0) }.max() ?? 0, sPeak = soft.map { abs($0) }.max() ?? 0
        check(armed.count == 3 && plainNotches.count == Orrery.collarDetents - 3 && sPeak > 0.002 && lPeak > 2.5 * sPeak && lPeak < 0.5 && rms(loud[Int(sr * 0.25)..<loud.count]) < 1e-6,
              "a10: the collar clicks \(String(format: "%.1f", lPeak / max(sPeak, 1e-9))) times louder on the \(armed.count) notches that hold an arm (peak \(String(format: "%.3f", lPeak)) against \(String(format: "%.3f", sPeak))), both audible, both gone by 0.25 s (Q104)")

        // ---- Q102: the near channel: between dormant and lit, a different shape from lit (a ring that out-glows its body), steady, and lit/blaze win.
        let col = GlassPuzzleProps.color(0)
        let n0 = ReceiverGlow.nearEmissive(near: 0, color: col), n5 = ReceiverGlow.nearEmissive(near: 0.5, color: col), n1 = ReceiverGlow.nearEmissive(near: 1, color: col)
        let lit = ReceiverGlow.emissive(level: 1, color: col, blaze: false)
        check(abs(n0.body.w - ReceiverGlow.dormantStrength) < 1e-4 && n0.body.w < n5.body.w && n5.body.w < n1.body.w && n1.body.w >= 2 * ReceiverGlow.dormantStrength && n1.body.w <= 0.35 * lit.w && n1.ring.w > n1.body.w && n1.ring.w > lit.w * 0.45,
              "a10: the near glow rises from dormant \(ReceiverGlow.dormantStrength) through \(String(format: "%.2f", n5.body.w)) to \(String(format: "%.2f", n1.body.w)) (lit is \(lit.w)), and its ring (\(String(format: "%.2f", n1.ring.w))) out-glows its body, lit's ring (\(String(format: "%.2f", lit.w * 0.45))) does not (Q102)")
        guard let device = MTLCreateSystemDefaultDevice() else { check(false, "a10: no Metal device"); return }
        let renderer = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"]))
        renderer.fixedTime = 12; renderer.autoExposure = false; renderer.taaEnabled = false
        renderer.world = .glassWood
        let gw = renderer.scene
        func gItem(_ n: String) -> DrawItem? { gw.items.first { $0.name == n } }
        ReceiverGlow.set(gw, 0, level: 0, color: col, near: 1); ReceiverGlow.set(gw, 1, level: 1, color: col, near: 1); ReceiverGlow.set(gw, 2, level: 0, color: col)
        let nearBody = gItem(ReceiverGlow.name(0))!.uniforms.emissive.w, litBody = gItem(ReceiverGlow.name(1))!.uniforms.emissive.w, darkBody = gItem(ReceiverGlow.name(2))!.uniforms.emissive.w
        let nearRing = gItem(ReceiverGlow.ringName(0))!.uniforms.emissive.w, darkRing = gItem(ReceiverGlow.ringName(2))!.uniforms.emissive.w
        ReceiverGlow.set(gw, 0, level: 0, color: col)
        let backToDark = gItem(ReceiverGlow.name(0))!.uniforms.emissive.w
        check(nearBody > darkBody + 0.3 && nearBody < litBody * 0.35 && abs(litBody - ReceiverGlow.litStrength) < 1e-4 && nearRing > darkRing + 0.8 && abs(backToDark - ReceiverGlow.dormantStrength) < 1e-4,
              "a10: set(near:) drives the scene: near body \(String(format: "%.2f", nearBody)) and ring \(String(format: "%.2f", nearRing)), lit stays \(String(format: "%.2f", litBody)) when near is also given, dormant \(String(format: "%.2f", darkBody)), and near 0 darkens it again (Q102)")

        // ---- Q105: the ring's notches and the floor's marks are one per ring step, and every gate's target sits on a notch (so a coarser step moves marks and notches together).
        let step = TideArchivePuzzle.ringStep, onNotch = TideArchivePuzzle.beamTargets.allSatisfy { t in let q = t / step; return abs(q - q.rounded()) < 1e-3 }
        check(ArchiveProps.ringNotches == Int((2 * Float.pi / step).rounded()) && abs(Float(ArchiveProps.ringNotches) * step - 2 * Float.pi) < 1e-3 && onNotch,
              "a10: the prism ring and the chamber floor carry \(ArchiveProps.ringNotches) notches (one per \(String(format: "%.1f", step * 180 / .pi)) degree step) and every gate's target lies on a notch (Q105)")
        let arch = Renderer(device: device, options: LaunchOptions.parse(["lanternwright"])); arch.world = .tideArchive
        let floor = arch.scene.items.first { $0.name == ArchiveProps.floorName }
        var bare = MeshBuilder()
        bare.cylinder(radiusTop: 1, radiusBottom: 1, height: 0.3, segments: 40, smooth: false, surface: ArchiveProps.iron)
        let bareIdx = bare.build(device: device, label: "bare floor").indexCount, marksIdx = (floor?.mesh.indexCount ?? 0) - bareIdx
        check(floor != nil && marksIdx == 36 * (ArchiveProps.ringNotches + 3), "a10: the chamber floor holds its marks: \(marksIdx / 36) boxes over the slab (one tick per notch (\(ArchiveProps.ringNotches)) and a line per gate), expected \(ArchiveProps.ringNotches + 3) (Q105)")

        // ---- Q125 (found): the gauge's stone is pale and its brass glow reads brass (below the bloom's cream).
        let lum = 0.2126 * TideMarks.steleColor.x + 0.7152 * TideMarks.steleColor.y + 0.0722 * TideMarks.steleColor.z
        check(lum >= 0.7 && TideMarks.idleEmissive >= 0.6 && TideMarks.idleEmissive <= 0.9,
              "a10: the tide gauge's stone has luminance \(String(format: "%.2f", lum)) (pale) and its idle brass glow is \(TideMarks.idleEmissive) (Q125)")
    }
}

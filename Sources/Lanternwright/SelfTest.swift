import Foundation
import Metal
import simd

/// `--selftest [name]`: fast, headless checks that tasks extend with their own cases. The checks live in `SelfTests/`, grouped
/// by area (core, world, audio, game); each block keeps its own `name == ...` guard, so `--selftest <name>` still runs just it.
final class SelfTestRunner {
    let name: String
    let device: MTLDevice
    var ok = true
    init(name: String, device: MTLDevice) { self.name = name; self.device = device }
    func check(_ cond: Bool, _ label: String) {
        print("\(cond ? "PASS" : "FAIL")  \(label)")
        ok = ok && cond
    }
}

enum SelfTest {
    static func run(_ name: String, device: MTLDevice) -> Bool {
        let r = SelfTestRunner(name: name, device: device)
        r.runCore(); r.runWorld(); r.runAudio(); r.runGame(); r.runControls(); r.runApproach(); r.runParallax(); r.runTAA(); r.runCollision(); r.runSteps(); r.runAmbience(); r.runSurf(); r.runWind(); r.runPad(); r.runWater(); r.runHollowness(); r.runSplash(); r.runBots(); r.runTrees(); r.runNeedles(); r.runFoley(); r.runGrassCoverage(); r.runGrassCull(); r.runStory(); r.runGate(); r.runReturn(); r.runInterior(); r.runPlates(); r.runPortal(); r.runFork(); r.runRouteWorld(); r.runTideArchive(); r.runTideWire(); r.runArchiveWorld(); r.runArchiveAudio(); r.runContradictions(); r.runGrassWalk(); r.runPages(); r.runShore(); r.runLook(); r.runPace(); r.runNav(); r.runConfine(); r.runFraming(); r.runNavAudit(); r.runGuidance(); r.runPassTimer(); r.runLayers(); r.runBanding(); r.runFrameGraph(); r.runShoreWater(); r.runLight(); r.runMaterialNames(); r.runThinCoverage(); r.runVelocity(); r.runUpscale(); r.runMarginCue(); r.runBeamSignal(); r.runDoorLeaf(); r.runInteriorLight(); r.runInteriorSteps(); r.runDoorway(); r.runWindowShafts(); r.runLanternChain(); r.runAnswerPhrase(); r.runSwashCoherence(); r.runDryInsideWet(); r.runCausewayGrounded(); r.runDoorLevel(); r.runDoorHeavy(); r.runBuoyPlacement(); r.runStepMix(); r.runShellClosed(); r.runPageFold(); r.runPagesSeated(); r.runTide(); r.runTideOnScreen(); r.runArchiveProps()
        return r.ok
    }
}

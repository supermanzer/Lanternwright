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
        r.runCore(); r.runWorld(); r.runAudio(); r.runGame(); r.runBots()
        return r.ok
    }
}

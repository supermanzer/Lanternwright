import Metal
import simd
import Foundation

/// S03.4 (user decision 2, 2026-10-28): a note nailed to the lighthouse door, there for the player who comes back from the Glass Wood. One small sheet with two nail heads and a
/// curled corner, nothing else: no glow, no marker (F03 #43, F04 P1). It is hidden until the altar is solved and the player is on Varrow (`Game` shows it); it is read like a page
/// and is NOT a page (it is logged in the Notebook and does not count for the gate). Its text is `Story.doorNote`.
enum DoorNote {
    static let itemName = "door_note"
    /// Where the sheet's centre is, in the tower's frame (the door faces +Z; the planks' face is at wallR + 0.08 and the iron straps stand proud of it at + 0.095): between the lower
    /// and the middle strap, left of the keyhole, a little off true.
    static let local = SIMD3<Float>(-0.17, Lighthouse.baseY + 1.40, Lighthouse.wallR(2.0) + 0.083)
    /// Width and height of the sheet, metres: smaller than a page.
    static let size = SIMD2<Float>(0.22, 0.30)
    static var worldCenter: SIMD3<Float> { Layout.lighthouse + local }
    /// Debug: `LW_DOOR_NOTE=1` in the environment draws it from the start, so a frame tool can show it without playing (the game itself hides it until it is earned).
    static let shownForTools = ProcessInfo.processInfo.environment["LW_DOOR_NOTE"] == "1"

    static func mesh() -> MeshBuilder {
        let nx = 8, ny = 10
        let w = size.x, h = size.y
        // The bottom-right corner has come away from the wood and curls toward the viewer; the rest lies flat with a slight sag between the nails.
        func lift(_ x: Float, _ y: Float) -> Float {
            let corner = simd_length(SIMD2(x - w / 2, y + h / 2))
            let curl = 0.032 * pow(max(0, 1 - corner / 0.10), 2)
            let sag = 0.004 * sin(Float.pi * (x / w + 0.5)) * max(0, 0.5 - (y / h + 0.5)) * 2
            return 0.002 + curl + sag
        }
        var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = []
        for j in 0...ny {
            for i in 0...nx {
                var x = (Float(i) / Float(nx) - 0.5) * w, y = (Float(j) / Float(ny) - 0.5) * h
                if i == 0 || i == nx || j == 0 || j == ny {                           // a ragged edge: pull the border in by a few millimetres
                    let k = Int32(j * 29 + i)
                    let pull = 0.002 + 0.006 * Island.noise.unit(k, 83)
                    x -= (x < 0 ? -1 : 1) * pull * (i == 0 || i == nx ? 1 : 0.3); y -= (y < 0 ? -1 : 1) * pull * (j == 0 || j == ny ? 1 : 0.3)
                }
                pos.append(SIMD3(x, y, lift(x, y)))
                let e: Float = 0.004
                nrm.append(simd_normalize(SIMD3(-(lift(x + e, y) - lift(x - e, y)) / (2 * e), -(lift(x, y + e) - lift(x, y - e)) / (2 * e), 1)))
            }
        }
        var idx: [UInt32] = []
        for j in 0..<ny { for i in 0..<nx {
            let a = UInt32(j * (nx + 1) + i), b = a + 1, c = a + UInt32(nx + 1), d = c + 1
            idx += [a, b, d, a, d, c]                                                   // counter-clockwise seen from +Z, where the player stands
        } }
        let paper = Surface(color: SIMD3(0.88, 0.84, 0.72), roughness: 0.9, material: .paper)
        let iron = Surface(color: SIMD3(0.05, 0.055, 0.07), roughness: 0.5, material: .iron)
        var m = MeshBuilder()
        // Tilted four degrees, as if nailed in a hurry; the whole sheet in the door's frame, centred on `local`.
        let place = translation(local) * rotationZ(0.07)
        m.addIndexed(positions: pos, indices: idx, smoothNormals: nrm, surface: paper, transform: place)
        for sx: Float in [-1, 1] {                                                       // the two nail heads, near the top edge
            m.sphere(radius: 0.0125, segments: 8, surface: iron, transform: place * translation(SIMD3(sx * w * 0.30, h * 0.40, 0.012)) * scaling(SIMD3(1, 1, 0.5)))
        }
        return m
    }

    static func build(into scene: Scene, device: MTLDevice) {
        scene.add(itemName, mesh: mesh().build(device: device, label: "door note"), uniforms: ObjectUniforms(model: translation(Layout.lighthouse)), hidden: !shownForTools)
    }
}

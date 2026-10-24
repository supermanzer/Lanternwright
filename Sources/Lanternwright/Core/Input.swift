import simd

/// One tick's worth of player intent, independent of AppKit. The game consumes this, so tests can synthesise it.
struct InputState {
    var move = SIMD2<Float>(0, 0)      // x: strafe right (+) / left (-), y: forward (+) / back (-); each -1...1
    var run = false
    var look = SIMD2<Float>(0, 0)      // radians this frame: x = yaw (right +), y = pitch (up +)
    var click = false                  // primary click edge (one frame)
    var journalPressed = false         // J edge
    var escapePressed = false          // Esc edge
    var pageFlip = 0                   // -1 / +1 when left / right arrow was pressed (journal navigation)
}

/// Raw key/mouse accumulator filled by GameView's event handlers and drained once per frame by `sample`.
final class Input {
    enum Key {
        static let a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2, w: UInt16 = 13
        static let e: UInt16 = 14, j: UInt16 = 38, escape: UInt16 = 53, space: UInt16 = 49
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    }

    private var down = Set<UInt16>()
    var shift = false
    private var mouse = SIMD2<Float>(0, 0)
    private var clickEdge = false
    private var journalEdge = false
    private var escapeEdge = false
    private var flipEdge = 0

    /// Radians of turn per mouse count. 0.0022 is a comfortable default for a 6720-px-wide display's pointer speed.
    var sensitivity: Float = 0.0022
    var invertY = false

    func keyDown(_ code: UInt16) {
        down.insert(code)
        if code == Key.j { journalEdge = true }
        if code == Key.escape { escapeEdge = true }
        if code == Key.left { flipEdge -= 1 }
        if code == Key.right { flipEdge += 1 }
    }
    func keyUp(_ code: UInt16) { down.remove(code) }
    func addMouse(dx: Float, dy: Float) { mouse += SIMD2(dx, dy) }
    func click() { clickEdge = true }

    /// Forget everything held (used when focus is lost, so a key released elsewhere doesn't stay "down").
    func releaseAll() {
        down.removeAll(); shift = false; mouse = .zero
    }

    /// Read and clear the per-frame deltas/edges. `captured` is false while the mouse is released (menus, journal).
    func sample(captured: Bool) -> InputState {
        var s = InputState()
        if captured {
            let f: Float = (down.contains(Key.w) || down.contains(Key.up)) ? 1 : 0
            let b: Float = (down.contains(Key.s) || down.contains(Key.down)) ? 1 : 0
            let r: Float = down.contains(Key.d) ? 1 : 0
            let l: Float = down.contains(Key.a) ? 1 : 0
            var m = SIMD2(r - l, f - b)
            if length_squared(m) > 1 { m = normalize(m) }       // diagonal movement must not be faster
            s.move = m
            s.run = shift
            var turn: Float = 0
            if down.contains(Key.left) { turn -= 1 }
            if down.contains(Key.right) { turn += 1 }
            s.look = SIMD2(mouse.x * sensitivity + turn * 0.03, -mouse.y * sensitivity * (invertY ? -1 : 1))
            s.click = clickEdge
        }
        s.journalPressed = journalEdge
        s.escapePressed = escapeEdge
        s.pageFlip = flipEdge
        mouse = .zero; clickEdge = false; journalEdge = false; escapeEdge = false; flipEdge = 0
        return s
    }
}

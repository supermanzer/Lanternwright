import AppKit
import MetalKit

/// The game's MTKView. Translates AppKit events into the plain `Input` object and owns mouse capture.
@MainActor
final class GameView: MTKView {
    /// The user's display is 6720 px wide; rendering at native size would waste most of the GPU.
    static let maxDrawableWidth: CGFloat = 2560

    let input = Input()
    /// Fraction of the capped drawable size actually rendered (Settings.renderScale).
    var renderScale: CGFloat = 1 { didSet { updateDrawableSize() } }
    /// While captured the pointer is hidden and frozen, and mouse movement turns the camera.
    private(set) var isCaptured = false
    /// Called when capture changes (the overlay shows/hides the crosshair).
    var onCaptureChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Mouse capture

    func captureMouse() {
        guard !isCaptured, window?.isKeyWindow == true else { return }
        isCaptured = true
        // Detach the cursor from the pointer position: it stops moving, but NSEvent deltas keep arriving.
        CGAssociateMouseAndMouseCursorPosition(0)
        NSCursor.hide()
        onCaptureChange?(true)
    }

    func releaseMouse() {
        guard isCaptured else { return }
        isCaptured = false
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        input.releaseAll()
        onCaptureChange?(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        guard let w = window else { return }
        w.acceptsMouseMovedEvents = true
        // Losing focus (Cmd-Tab, another window) must give the pointer back.
        for name in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.releaseMouse() }
            })
        }
    }

    // MARK: Events

    override func mouseDown(with event: NSEvent) {
        if isCaptured { input.click() }          // when released, the overlay (menu / title / journal) handles clicks
    }
    override func mouseMoved(with event: NSEvent) { addDelta(event) }
    override func mouseDragged(with event: NSEvent) { addDelta(event) }
    override func rightMouseDragged(with event: NSEvent) { addDelta(event) }
    override func otherMouseDragged(with event: NSEvent) { addDelta(event) }
    private func addDelta(_ e: NSEvent) {
        if isCaptured { input.addMouse(dx: Float(e.deltaX), dy: Float(e.deltaY)) }
    }

    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }
        // The Esc that RELEASES the mouse (opening the pause menu) must not also count as the Esc that closes it.
        if event.keyCode == Input.Key.escape && isCaptured { releaseMouse(); return }
        input.keyDown(event.keyCode)
    }
    override func keyUp(with event: NSEvent) { input.keyUp(event.keyCode) }
    override func flagsChanged(with event: NSEvent) { input.shift = event.modifierFlags.contains(.shift) }

    // MARK: Drawable size

    func updateDrawableSize() {
        let backing = convertToBacking(bounds.size)
        guard backing.width > 0, backing.height > 0 else { return }
        let scale = min(1, GameView.maxDrawableWidth / backing.width) * renderScale
        drawableSize = CGSize(width: (backing.width * scale).rounded(), height: (backing.height * scale).rounded())
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }
}

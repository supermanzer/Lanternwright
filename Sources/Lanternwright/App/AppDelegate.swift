import AppKit
import MetalKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, MTKViewDelegate {
    private let device: MTLDevice
    private let options: LaunchOptions
    private var window: NSWindow!
    private var view: GameView!
    private var renderer: Renderer!
    private var game: Game!
    private var audio: AudioEngine?
    private var overlay: OverlayView!
    private var wasJournalOpen = false
    private var lastFrameTime = CACurrentMediaTime()
    private var fpsFrames = 0
    private var fpsStart = CACurrentMediaTime()

    init(device: MTLDevice, options: LaunchOptions) {
        self.device = device
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        renderer = Renderer(device: device, options: options)
        game = Game(scene: renderer.scene)
        let engine = AudioEngine()
        if engine.start() { audio = engine }
        // --view / --camera also work for the windowed game: they set the starting pose.
        if let cam = options.camera ?? options.viewName.flatMap(Viewpoints.named) {
            game.player.position = cam.position - SIMD3(0, Player.eyeHeight, 0)
            game.player.yaw = cam.yaw
            game.player.pitch = cam.pitch
        }

        let rect = NSRect(x: 0, y: 0, width: 1600, height: 900)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Lanternwright"
        window.center()

        view = GameView(frame: rect, device: device)
        view.colorPixelFormat = Renderer.outputFormat
        view.preferredFramesPerSecond = 120
        view.autoResizeDrawable = false   // GameView caps the drawable size itself
        view.delegate = self
        view.onCaptureChange = { [weak self] _ in self?.updateTitle() }

        overlay = OverlayView(frame: view.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onFlip = { [weak self] d in self?.game.journal.flip(d) }
        overlay.onClose = { [weak self] in self?.game.journal.isOpen = false }
        view.addSubview(overlay)
        window.contentView = view
        view.updateDrawableSize()

        updateTitle()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.mainMenu = AppDelegate.makeMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let cb = renderer.queue.makeCommandBuffer() else { return }
        let now = CACurrentMediaTime()
        defer {
            audio?.update(now: now, game: game)
            for event in game.drainEvents() { audio?.handle(event) }
        }
        if options.showFPS {
            fpsFrames += 1
            if now - fpsStart >= 1 {
                window.title = String(format: "Lanternwright: %.0f fps (%d x %d)", Double(fpsFrames) / (now - fpsStart),
                                      Int(self.view.drawableSize.width), Int(self.view.drawableSize.height))
                fpsFrames = 0; fpsStart = now
            }
        }
        game.advance(now: now, input: self.view.input.sample(captured: self.view.isCaptured))
        syncOverlay(now: now)
        renderer.encode(commandBuffer: cb, target: drawable.texture, camera: game.camera)
        cb.present(drawable)
        cb.commit()
    }

    /// Push game state into the overlay, and hand the mouse back and forth when the journal opens and closes.
    private func syncOverlay(now: Double) {
        let dt = CGFloat(min(now - lastFrameTime, 0.1)); lastFrameTime = now
        let journal = game.journal
        if journal.isOpen && view.isCaptured { view.releaseMouse() }
        if wasJournalOpen && !journal.isOpen && !view.isCaptured { view.captureMouse() }
        wasJournalOpen = journal.isOpen

        var dirty = false
        func set<T: Equatable>(_ current: inout T, _ new: T) { if current != new { current = new; dirty = true } }
        set(&overlay.captured, view.isCaptured)
        set(&overlay.prompt, game.hovered?.prompt)
        set(&overlay.journalOpen, journal.isOpen)
        set(&overlay.pageIndex, journal.current)
        set(&overlay.whiteout, CGFloat(game.whiteout))
        if overlay.pages.map(\.number) != journal.collectedPages.map(\.number) { overlay.pages = journal.collectedPages; dirty = true }
        if overlay.step(dt: dt) { dirty = true }
        if dirty { overlay.needsDisplay = true }
    }

    private func updateTitle() {
        window.title = view.isCaptured ? "Lanternwright" : "Lanternwright: click to look around (Esc releases the mouse)"
    }

    /// Minimal menu so Cmd-Q works (a bare executable gets no menu bar by default).
    private static func makeMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Lanternwright", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        return main
    }
}

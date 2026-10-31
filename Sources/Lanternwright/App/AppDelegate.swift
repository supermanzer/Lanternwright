import AppKit
import MetalKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, MTKViewDelegate {
    private let device: MTLDevice
    private var options: LaunchOptions
    private var window: NSWindow!
    private var view: GameView!
    private var renderer: Renderer!
    private var game: Game!
    private var audio: AudioEngine?
    private var overlay: OverlayView!
    private var wasJournalOpen = false
    private var saveDirty = false
    private var titleActive = true
    private var settings = Settings.load()
    private var titleClock: Float = 0
    private var lastSave = CACurrentMediaTime()
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
        renderer.passTimer = PassTimer(device: device)          // G10.0.1: read back one frame late; its table goes into the F-key context
        renderer.taaEnabled = true                  // F02 R1 (accepted by the user): temporal anti-aliasing in the game; headless tools opt in with --taa
        game = Game(scenes: renderer.scenes)
        let engine = AudioEngine()
        if engine.start() { audio = engine }
        // Resume from the last save (unless --new, --view or --camera ask for something specific).
        let debugLaunch = options.state != nil || options.world != nil
        if !options.newGame, !debugLaunch, options.camera == nil, options.viewName == nil, let save = SaveStore.load() { game.restore(save) }
        // `--state solved` / `--world glass` jump straight to the interesting place for inspection. They never touch the save.
        if options.state == "solved" || options.state == "travelled" { game.puzzle.forceSolved(); if options.state == "travelled" { game.state.set("lensTouched") }; game.settleAtmosphere(); game.simulate(seconds: 0.1); _ = game.drainEvents() }
        if options.state == "mirrors" || options.state == "both" { game.glass?.forceMirrorsSolved() }
        if options.state == "chimes" || options.state == "both" { game.glass?.forceChimesSolved() }
        if options.state == "both" { game.glass?.forceAltar() }
        if ["mirrors", "chimes", "both"].contains(options.state ?? "") { game.simulate(seconds: 0.1); _ = game.drainEvents() }
        if options.world == .glassWood || ["mirrors", "chimes", "both"].contains(options.state ?? "") { game.travel(to: .glassWood); _ = game.drainEvents() }
        game.state.onChange = { [weak self] _, _ in self?.saveDirty = true }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeSave() }
        }
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
        window.contentMinSize = NSSize(width: 1000, height: 720)                    // F05 S2: the Notebook and journal layouts need about 720 pt of height
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()

        view = GameView(frame: rect, device: device)
        view.colorPixelFormat = Renderer.outputFormat
        view.preferredFramesPerSecond = 120
        view.autoResizeDrawable = false   // GameView caps the drawable size itself
        view.delegate = self
        view.onCaptureChange = { [weak self] _ in self?.updateTitle() }
        view.interceptKey = { [weak self] code in self?.overlay.handleKey(code) ?? false }

        overlay = OverlayView(frame: view.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onFlip = { [weak self] d in self?.game.journal.flip(d) }
        overlay.onTab = { [weak self] t in self?.game.journal.select(t) }
        overlay.onClaim = { [weak self] id, page, side in self?.game.setClaim(id, page: page, to: side) }
        overlay.onNotebookTone = { [weak self] i in self?.game.playNotebookTone(i) }
        overlay.onClose = { [weak self] in self?.game.journal.isOpen = false }
        overlay.settings = settings
        overlay.onBegin = { [weak self] in self?.beginPlaying() }
        overlay.onIntroDone = { [weak self] fromTitle in self?.introDone(fromTitle: fromTitle) }
        overlay.onShowControls = { [weak self] in self?.showControls() }
        overlay.onResume = { [weak self] in self?.resumePlaying() }
        overlay.onQuit = { NSApp.terminate(nil) }
        overlay.onNewGame = { [weak self] in self?.newGame() }
        overlay.onSettingsChanged = { [weak self] s in self?.apply(settings: s) }
        apply(settings: settings)
        titleActive = options.viewName == nil && options.camera == nil           // --view/--camera skip the title (screenshots, testing)
        overlay.titleOpen = titleActive
        overlay.titleHasSave = SaveStore.load() != nil && !options.newGame
        overlay.onFeedbackSubmit = { [weak self] text in self?.submitFeedback(text) }
        overlay.onFeedbackCancel = { [weak self] in self?.closeFeedback(saved: nil) }
        view.addSubview(overlay)
        window.contentView = view
        view.updateDrawableSize()

        updateTitle()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.mainMenu = AppDelegate.makeMenu(target: self)
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
            for event in game.drainEvents() {
                audio?.handle(event)
                if event == .feedbackRequested { DispatchQueue.main.async { [weak self] in self?.openFeedback() } }
            }
        }
        if options.showFPS {
            fpsFrames += 1
            if now - fpsStart >= 1 {
                window.title = String(format: "Lanternwright: %.0f fps (%d x %d)", Double(fpsFrames) / (now - fpsStart),
                                      Int(self.view.drawableSize.width), Int(self.view.drawableSize.height))
                fpsFrames = 0; fpsStart = now
            }
        }
        var sampled = self.view.input.sample(captured: self.view.isCaptured)
        if titleActive || overlay.introOpen { sampled = InputState() }    // the world waits behind the title and the controls screen
        // Esc while the pause menu is showing resumes (the Esc that opened the menu never reaches here: see GameView).
        if sampled.escapePressed && overlay.menuOpen { resumePlaying() }
        game.advance(now: now, input: sampled)
        renderer.world = game.world                                        // draw the world the player is in
        renderer.mistScale = game.mistScale; renderer.beamIntensity = game.beamAmount; renderer.marginPressure = game.player.marginPressure; renderer.beamSignal = game.lighthouseSignal; renderer.interiorOpen = game.interiorApplied; renderer.worldTime = Renderer.windClock(game: game)
        syncOverlay(now: now)
        if now - lastSave > 15 { lastSave = now; writeSave() }          // autosave (position changes constantly)
        if saveDirty { writeSave() }                                    // progress events save immediately
        renderer.encode(commandBuffer: cb, target: drawable.texture, camera: titleActive ? titleCamera() : game.camera)
        cb.present(drawable)
        cb.commit()
    }

    // MARK: Title, menu, settings

    private func apply(settings s: Settings) {
        let s = s.clamped()
        settings = s
        s.save()
        view.input.sensitivity = s.effectiveSensitivity
        LookFilter.calm = s.calmCamera
        Player.paceScale = s.pace
        Player.guidance = options.freeRoam ? .free : s.guidance                  // --freeroam wins over the saved setting
        Settings.current = s
        view.input.invertY = s.invertY
        Player.slipEnabled = s.slipOnSteep
        renderer.taaEnabled = s.taa
        // Render resolution below 1: MetalFX upscales a smaller scene to the full drawable when asked for (and supported); otherwise the smaller drawable is stretched as before.
        let upscale = s.metalFX && s.renderScale < 0.999 && Renderer.metalFXSupported
        renderer.renderScale = upscale ? s.renderScale : 1
        view.renderScale = upscale ? 1 : CGFloat(s.renderScale)
        audio?.synth.master = s.volume
    }

    private func beginPlaying() {
        titleActive = false
        overlay.titleOpen = false
        // A new game (no save) shows the controls once before the player can move; resuming a save goes straight in.
        if !settings.introSeen && !overlay.titleHasSave { overlay.showIntro(fromTitle: true) } else { view.captureMouse() }
    }

    /// The controls screen was closed. From the title that starts the game (the click is consumed by the overlay, so it never reaches the world);
    /// from the pause menu we simply return to the menu (it reappears because the mouse is still free).
    private func introDone(fromTitle: Bool) {
        if !settings.introSeen { var s = settings; s.introSeen = true; apply(settings: s) }
        if fromTitle { view.captureMouse() }
    }

    func showControls() {
        guard !titleActive, !overlay.introOpen, !overlay.feedbackOpen else { return }
        if view.isCaptured { view.releaseMouse() }
        overlay.showIntro(fromTitle: false)
    }

    private func resumePlaying() { view.captureMouse() }

    /// Delete the save and relaunch the app (the simplest correct way to rebuild the world from scratch).
    private func newGame() {
        SaveStore.delete()
        saveDirty = false
        var fresh = settings; fresh.introSeen = false; apply(settings: fresh)        // a new game shows the controls again
        options.newGame = true
        let path = Bundle.main.bundlePath
        if path.hasSuffix(".app") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "sleep 0.6; open -n '\(path)' --args --new"]
            try? p.run()
        }
        NSApp.terminate(nil)
    }

    /// Camera for the title screen: a slow circle around the island, rising and falling a little, always looking at the lighthouse hill.
    private func titleCamera() -> Camera {
        let t = titleClock * 0.035
        let glass = game.world == .glassWood
        let radius: Float = glass ? 290 : 330, height: Float = (glass ? 55 : 70) + 25 * sin(t * 1.7)
        let center = glass ? SIMD3<Float>(0, 0, 20) : SIMD3<Float>(-10, 0, -40)
        let pos = center + SIMD3(radius * cos(t + 0.9), height, radius * sin(t + 0.9))
        let look = glass ? SIMD3<Float>(0, 12, -20) : SIMD3<Float>(-20, 38, -45)
        let d = look - pos
        var cam = Camera(position: pos, yaw: atan2(d.x, -d.z), pitch: asin(d.y / length(d)))
        cam.fovY = 52 * .pi / 180
        return cam
    }

    // MARK: Saving

    private func writeSave() {
        guard options.viewName == nil, options.camera == nil, options.state == nil, options.world == nil, game != nil else { return }
        do { try SaveStore.save(game.makeSave()); saveDirty = false } catch { FileHandle.standardError.write(Data("save failed: \(error)\n".utf8)) }
    }

    // MARK: Feedback

    /// F: grab what the player is looking at, then show the panel (mouse released so they can type).
    func openFeedback() {
        guard !overlay.feedbackOpen, !overlay.introOpen, !titleActive else { return }
        game.journal.isOpen = false
        view.releaseMouse()
        let size = view.drawableSize
        let timer = renderer.passTimer; renderer.passTimer = nil          // the snapshot frame must not replace the game's own table
        try? Screenshot.snapshot(renderer: renderer, camera: game.camera, width: Int(size.width), height: Int(size.height), to: FeedbackStore.pendingScreenshotURL)
        renderer.passTimer = timer
        overlay.showFeedback()
    }

    private func submitFeedback(_ text: String) {
        do {
            let entry = try FeedbackStore.save(text: text, context: game.feedbackContext(extra: renderer.passTimer.map { $0.summary }.map { ["pass ms": $0] } ?? [:]))
            closeFeedback(saved: "Thank you. Saved as \(entry.id)")
        } catch {
            closeFeedback(saved: "Could not save feedback: \(error.localizedDescription)")
        }
    }

    private func closeFeedback(saved message: String?) {
        if message == nil { FeedbackStore.discardPending() }
        overlay.hideFeedback()
        window.makeFirstResponder(view)
        view.captureMouse()
        if let message {
            overlay.toast = message
            overlay.needsDisplay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.overlay.toast = nil; self?.overlay.needsDisplay = true }
        }
    }

    /// Push game state into the overlay, and hand the mouse back and forth when the journal opens and closes.
    private func syncOverlay(now: Double) {
        let dt = CGFloat(min(now - lastFrameTime, 0.1)); lastFrameTime = now
        titleClock += Float(dt)
        let journal = game.journal
        if journal.isOpen && view.isCaptured { view.releaseMouse() }
        if wasJournalOpen && !journal.isOpen && !view.isCaptured { view.captureMouse() }
        wasJournalOpen = journal.isOpen

        var dirty = false
        func set<T: Equatable>(_ current: inout T, _ new: T) { if current != new { current = new; dirty = true } }
        set(&overlay.captured, view.isCaptured)
        let wantMenu = !titleActive && !view.isCaptured && !journal.isOpen && !overlay.feedbackOpen && !overlay.introOpen && game.whiteout < 0.5
        if wantMenu && !overlay.menuOpen { overlay.showMenu(); game.putAwayReading() }          // F06 B1: a note card does not wait behind the pause menu
        if !wantMenu && overlay.menuOpen { overlay.hideMenu() }
        set(&overlay.prompt, game.hoverPrompt)
        set(&overlay.promptDone, game.hoveredFinished)
        set(&overlay.journalOpen, journal.isOpen)
        set(&overlay.pageIndex, journal.current)
        set(&overlay.journalTab, journal.tab)
        set(&overlay.tabItems, journal.visibleTabs.map { OverlayView.TabItem(tab: $0, title: journal.title($0), unread: journal.hasUnread($0)) })
        set(&overlay.notebookNotes, game.story.notes.compactMap { Story.noteText($0) })
        set(&overlay.claimCards, game.visibleContradictions.map { c in
            let found = Set(journal.collectedPages.map(\.number))
            let v = game.verdict(c.id)
            return OverlayView.ClaimCard(id: c.id, hers: c.hers, his: c.his,
                rows: game.visibleEvidence(c)          // (the Archive's piece shows once a route has begun)
                    .map { OverlayView.ClaimRow(page: $0.page, excerpt: $0.excerpt(route: journal.route), found: found.contains($0.page), side: game.claim(c.id, page: $0.page)?.title) },
                status: v == .settled ? "Settled." : nil)
        })
        set(&overlay.notebookSeen, StoneID.allCases.map { game.state.has(Notebook.seenFlag($0)) })
        set(&overlay.notebookStruck, StoneID.allCases.map { game.state.has(Notebook.struckFlag($0)) })
        set(&overlay.whiteout, CGFloat(game.whiteout))
        set(&overlay.whiteoutCaption, game.whiteCaption)
        set(&overlay.bannerText, game.banner)
        set(&overlay.readingText, game.reading)
        set(&overlay.readingMap, game.readingMap)
        set(&overlay.pageWaiting, game.pageWaiting)
        set(&overlay.pageSlots, journal.pageSlots)
        if overlay.pages.map(\.number) != journal.tabPages.map(\.number) { overlay.pages = journal.tabPages; dirty = true }
        if overlay.step(dt: dt) { dirty = true }
        if dirty { overlay.needsDisplay = true }
    }

    private func updateTitle() {
        window.title = "Lanternwright"
        window.contentMinSize = NSSize(width: 1000, height: 720)                    // F05 S2: the Notebook and journal layouts need about 720 pt of height
    }

    /// Menu bar: Quit (Cmd-Q), View > Full Screen (Ctrl-Cmd-F), Help > Controls / Send Feedback. The feedback item deliberately has NO key
    /// equivalent: a plain "f" equivalent would fire while typing in the feedback panel; the F key itself is handled by the game (FeedbackShortcut).
    static func makeMenu(target: AnyObject? = nil) -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Lanternwright", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        let fs = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fs)
        viewItem.submenu = viewMenu
        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let helpMenu = NSMenu(title: "Help")
        let controls = NSMenuItem(title: "Controls…", action: #selector(menuShowControls), keyEquivalent: "")
        let feedback = NSMenuItem(title: "Send Feedback…  (\(FeedbackShortcut.label))", action: #selector(menuSendFeedback), keyEquivalent: "")
        controls.target = target; feedback.target = target
        helpMenu.addItem(controls); helpMenu.addItem(feedback)
        helpItem.submenu = helpMenu
        return main
    }

    @objc func menuShowControls() { showControls() }
    @objc func menuSendFeedback() { openFeedback() }
}

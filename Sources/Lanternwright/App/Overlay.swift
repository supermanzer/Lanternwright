import AppKit

/// Everything 2D that sits on top of the Metal view: crosshair, hover prompt, the journal reader, the final fade.
/// Text stays in AppKit (not Metal) so we get proper typography for free. It is drawn in `draw(_:)` rather than with
/// Core Animation layers so it can also be rendered to a PNG without a window (see `snapshot`).
@MainActor
final class OverlayView: NSView {
    // State pushed in by the app each frame.
    var captured = false
    var prompt: String?
    var journalOpen = false
    var pages: [JournalPage] = []
    var pageIndex = 0
    var whiteout: CGFloat = 0
    /// Draws a stand-in scene behind the overlay (only used by the headless snapshot).
    var debugBackdrop: NSColor?

    var onFlip: ((Int) -> Void)?
    var onClose: (() -> Void)?

    private var ring: CGFloat = 0           // 0 = dot, 1 = ring; eased toward the target

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// Pass mouse events through to the game, except while the journal is open.
    override func hitTest(_ point: NSPoint) -> NSView? { journalOpen ? self : nil }

    /// Ease the crosshair toward its target shape; returns true if anything needs redrawing.
    @discardableResult
    func step(dt: CGFloat) -> Bool {
        let target: CGFloat = prompt != nil ? 1 : 0
        let before = ring
        ring += (target - ring) * min(1, dt * 16)
        if abs(ring - target) < 0.01 { ring = target }
        return ring != before
    }

    // MARK: Journal geometry (shared by drawing and clicking)

    private var panel: NSRect {
        let w = min(640, bounds.width * 0.86), h = min(500, bounds.height * 0.78)
        return NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }
    private var leftArrow: NSRect { NSRect(x: panel.minX + 24, y: panel.maxY - 66, width: 56, height: 36) }
    private var rightArrow: NSRect { NSRect(x: panel.maxX - 80, y: panel.maxY - 66, width: 56, height: 36) }

    override func mouseDown(with event: NSEvent) {
        guard journalOpen else { return }
        let p = convert(event.locationInWindow, from: nil)
        if leftArrow.contains(p) { onFlip?(-1) }
        else if rightArrow.contains(p) { onFlip?(1) }
        else if !panel.contains(p) { onClose?() }
    }

    // MARK: Drawing

    private func serif(_ size: CGFloat) -> NSFont { NSFont(name: "Baskerville", size: size) ?? NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size) }

    override func draw(_ dirtyRect: NSRect) {
        if let b = debugBackdrop { b.setFill(); bounds.fill() }

        if captured && !journalOpen && whiteout < 0.5 { drawCrosshair() }
        if journalOpen { drawJournal() }
        if whiteout > 0 { drawWhiteout() }
    }

    private func drawCrosshair() {
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let r = 2 + 6 * ring                                     // dot radius 2 -> ring radius 8
        let rect = NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        // A dark halo keeps it visible over bright sky and dark rock alike.
        let halo = NSBezierPath(ovalIn: rect.insetBy(dx: -1, dy: -1))
        halo.lineWidth = ring > 0.5 ? 3.5 : 1
        NSColor.black.withAlphaComponent(0.45).setStroke(); NSColor.black.withAlphaComponent(0.45).setFill()
        if ring > 0.5 { halo.stroke() } else { halo.fill() }
        let path = NSBezierPath(ovalIn: rect)
        NSColor.white.withAlphaComponent(0.92).setStroke(); NSColor.white.withAlphaComponent(0.92).setFill()
        if ring > 0.5 { path.lineWidth = 1.6; path.stroke() } else { path.fill() }

        if let prompt, ring > 0.3 {
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.8); shadow.shadowBlurRadius = 4; shadow.shadowOffset = NSSize(width: 0, height: 1)
            let attrs: [NSAttributedString.Key: Any] = [.font: serif(16), .foregroundColor: NSColor.white.withAlphaComponent(min(1, ring)), .shadow: shadow]
            let size = (prompt as NSString).size(withAttributes: attrs)
            (prompt as NSString).draw(at: NSPoint(x: c.x - size.width / 2, y: c.y + 20), withAttributes: attrs)
        }
    }

    private func drawJournal() {
        NSColor.black.withAlphaComponent(0.5).setFill(); bounds.fill()
        let p = panel
        // Paper with a soft shadow and a thin inner rule.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.55); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        NSColor(calibratedRed: 0.93, green: 0.89, blue: 0.77, alpha: 1).setFill()
        NSBezierPath(roundedRect: p, xRadius: 14, yRadius: 14).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.25, alpha: 0.55).setStroke()
        let rule = NSBezierPath(roundedRect: p.insetBy(dx: 12, dy: 12), xRadius: 8, yRadius: 8); rule.lineWidth = 1; rule.stroke()

        let ink = NSColor(calibratedRed: 0.17, green: 0.12, blue: 0.08, alpha: 1)
        let faded = NSColor(calibratedRed: 0.17, green: 0.12, blue: 0.08, alpha: 0.55)
        func text(_ s: String, font: NSFont, color: NSColor, in rect: NSRect, align: NSTextAlignment = .left, spacing: CGFloat = 0) {
            let para = NSMutableParagraphStyle(); para.alignment = align; para.lineSpacing = spacing; para.lineBreakMode = .byWordWrapping
            (s as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        }

        if pages.isEmpty {
            text("The journal is empty.", font: serif(26), color: ink, in: NSRect(x: p.minX + 48, y: p.minY + 70, width: p.width - 96, height: 40), align: .center)
            text("Pages you find on the island are kept here, so you can read them again.", font: serif(19), color: faded,
                 in: NSRect(x: p.minX + 60, y: p.minY + 130, width: p.width - 120, height: 120), align: .center, spacing: 6)
        } else {
            let page = pages[min(max(pageIndex, 0), pages.count - 1)]
            text("The Keeper's Journal", font: serif(15), color: faded, in: NSRect(x: p.minX + 48, y: p.minY + 38, width: p.width - 96, height: 22), align: .center)
            text("page \(toRoman(page.number))", font: .systemFont(ofSize: 12, weight: .medium), color: faded, in: NSRect(x: p.minX + 48, y: p.minY + 64, width: p.width - 96, height: 18), align: .center)
            text(page.text, font: serif(24), color: ink, in: NSRect(x: p.minX + 56, y: p.minY + 110, width: p.width - 112, height: p.height - 210), spacing: 9)
            // Page dots + arrows.
            let dotsY = p.maxY - 50
            let totalW = CGFloat(pages.count) * 16
            for i in 0..<pages.count {
                let x = p.midX - totalW / 2 + CGFloat(i) * 16 + 4
                (i == pageIndex ? ink : faded).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: dotsY, width: i == pageIndex ? 8 : 6, height: i == pageIndex ? 8 : 6)).fill()
            }
            text("‹", font: serif(34), color: pageIndex > 0 ? ink : faded.withAlphaComponent(0.2), in: leftArrow, align: .center)
            text("›", font: serif(34), color: pageIndex < pages.count - 1 ? ink : faded.withAlphaComponent(0.2), in: rightArrow, align: .center)
        }
        text("← →  turn pages     Esc or J  close", font: .systemFont(ofSize: 11), color: faded,
             in: NSRect(x: p.minX, y: p.maxY - 26, width: p.width, height: 16), align: .center)
    }

    private func drawWhiteout() {
        NSColor.white.withAlphaComponent(min(1, whiteout)).setFill(); bounds.fill()
        if whiteout > 0.97 {
            let ink = NSColor(calibratedWhite: 0.25, alpha: 1)
            let big: [NSAttributedString.Key: Any] = [.font: serif(46), .foregroundColor: ink]
            let small: [NSAttributedString.Key: Any] = [.font: serif(17), .foregroundColor: ink.withAlphaComponent(0.6)]
            let s1 = "The light folds…" as NSString, s2 = "(end of the vertical slice)" as NSString
            let z1 = s1.size(withAttributes: big), z2 = s2.size(withAttributes: small)
            s1.draw(at: NSPoint(x: bounds.midX - z1.width / 2, y: bounds.midY - 40), withAttributes: big)
            s2.draw(at: NSPoint(x: bounds.midX - z2.width / 2, y: bounds.midY + 28), withAttributes: small)
        }
    }

    private func toRoman(_ n: Int) -> String { ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"][min(max(n, 0), 8)] }

    // MARK: Headless snapshot

    /// Render this view to a PNG (no window needed).
    func snapshot(to path: String) throws {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { throw NSError(domain: "overlay", code: 1) }
        cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "overlay", code: 2) }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent.isEmpty ? "." : (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: path))
    }
}

/// `--dump-overlay base`: writes base-crosshair.png, base-journal.png, base-journal-empty.png and base-end.png.
@MainActor
enum OverlayDump {
    static func write(base: String) throws {
        _ = NSApplication.shared
        let backdrop = NSColor(calibratedRed: 0.22, green: 0.30, blue: 0.40, alpha: 1)
        func make() -> OverlayView {
            let v = OverlayView(frame: NSRect(x: 0, y: 0, width: 1600, height: 900))
            v.debugBackdrop = backdrop
            return v
        }
        var v = make(); v.captured = true; v.prompt = "Touch the stone"; v.step(dt: 1)
        try v.snapshot(to: base + "-crosshair.png")
        v = make(); v.journalOpen = true; v.pages = JournalContent.pages; v.pageIndex = 2
        try v.snapshot(to: base + "-journal.png")
        v = make(); v.journalOpen = true
        try v.snapshot(to: base + "-journal-empty.png")
        v = make(); v.whiteout = 1
        try v.snapshot(to: base + "-end.png")
    }
}

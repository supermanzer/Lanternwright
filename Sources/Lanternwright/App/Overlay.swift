import AppKit

/// Everything 2D that sits on top of the Metal view: crosshair, hover prompt, the journal reader, the final fade.
/// Text stays in AppKit (not Metal) so we get proper typography for free. It is drawn in `draw(_:)` rather than with
/// Core Animation layers so it can also be rendered to a PNG without a window (see `snapshot`).
@MainActor
final class OverlayView: NSView {
    // State pushed in by the app each frame.
    var captured = false
    var prompt: String?
    /// The hovered thing has already done its job: a quieter, smaller ring and a dimmer prompt.
    var promptDone = false
    var journalOpen = false
    var pages: [JournalPage] = []
    var journalTab: JournalTab = .ilse
    /// One tab on the journal's top edge (S03.2): its label and whether it holds something not yet read (a small amber diamond).
    struct TabItem: Equatable { var tab: JournalTab; var title: String; var unread: Bool }
    var tabItems: [TabItem] = [TabItem(tab: .ilse, title: "Pages", unread: false), TabItem(tab: .notebook, title: "Notebook", unread: false)]
    /// Notebook: per stone, whether its glyph has been seen / struck.
    var notebookSeen = [false, false, false]
    var notebookStruck = [false, false, false]
    var pageIndex = 0
    var whiteout: CGFloat = 0
    /// Text shown while the screen is white ("The light folds…").
    var whiteoutCaption: String?
    /// A line of story text near the top of the screen ("Ilse: ..."), set by the game.
    var bannerText: String?
    /// F05 S1: the text of a note being read in the world (the door note): a small sheet of paper over the game, not the journal.
    var readingText: String?
    /// A page has appeared (or was announced) and has not been read yet: a small journal marker sits in the corner until it is collected (F02 P0).
    var pageWaiting = false
    /// Draws a stand-in scene behind the overlay (only used by the headless snapshot).
    var debugBackdrop: NSColor?

    // Feedback panel (F). The text view and buttons are real AppKit controls so editing, selection and paste just work.
    private(set) var feedbackOpen = false
    var onFeedbackSubmit: ((String) -> Void)?
    var onFeedbackCancel: (() -> Void)?
    private var feedbackText: NSTextView?
    private var feedbackViews: [NSView] = []
    // Title screen and pause menu.
    var titleOpen = false
    var titleHasSave = false
    private(set) var menuOpen = false
    var settings = Settings()
    var onBegin: (() -> Void)?
    var onResume: (() -> Void)?
    var onQuit: (() -> Void)?
    var onNewGame: (() -> Void)?
    var onSettingsChanged: ((Settings) -> Void)?
    private var menuViews: [NSView] = []
    private var newGameArmed = false
    private var titleTime: CGFloat = 0

    // Intro / controls screen (see IntroScreen.swift).
    var introOpen = false
    /// Opened from the title (so closing it starts the game) rather than from the pause menu (closing returns to the menu).
    var introFromTitle = false
    var introFade: CGFloat = 0
    var onIntroDone: ((Bool) -> Void)?
    var onShowControls: (() -> Void)?

    /// Brief confirmation shown after sending ("Thank you: saved").
    var toast: String?

    /// Lines logged in the Notebook (the door note, S03.4), drawn under the rubbings.
    var notebookNotes: [String] = []
    var onFlip: ((Int) -> Void)?
    var onClose: (() -> Void)?
    var onTab: ((JournalTab) -> Void)?
    var onNotebookTone: ((Int) -> Void)?
    /// S03.9: the contradiction shown in the Notebook (the first with evidence found): its two claims, the pieces of evidence (found or not, and which claim each is set against), and the quiet line.
    struct ClaimRow: Equatable { var page: Int; var excerpt: String; var found: Bool; var side: String? }
    struct ClaimCard: Equatable { var id: String; var hers: String; var his: String; var rows: [ClaimRow]; var status: String?; var waiting = false }
    var claimCards: [ClaimCard] = []
    var onClaim: ((String, Int, Claim) -> Void)?

    private var ring: CGFloat = 0           // 0 = dot, 1 = ring; eased toward the target

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// Pass mouse events through to the game, except while the journal is open.
    override func hitTest(_ point: NSPoint) -> NSView? { (feedbackOpen || menuOpen) && !introOpen ? super.hitTest(point) : ((journalOpen || titleOpen || introOpen) ? self : nil) }

    /// Ease the crosshair toward its target shape; returns true if anything needs redrawing.
    @discardableResult
    func step(dt: CGFloat) -> Bool {
        if titleOpen { titleTime += dt }
        var fading = false
        if introOpen && introFade < 1 { introFade = min(1, introFade + dt / 0.6); fading = true }
        let target: CGFloat = prompt != nil ? (promptDone ? 0.6 : 1) : 0
        let before = ring
        ring += (target - ring) * min(1, dt * 16)
        if abs(ring - target) < 0.01 { ring = target }
        return ring != before || titleOpen || fading
    }

    // MARK: Journal geometry (shared by drawing and clicking)

    private var panel: NSRect {
        let w = min(640, bounds.width * 0.86), h = min(500, bounds.height * 0.78)
        return NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }
    private var leftArrow: NSRect { NSRect(x: panel.minX + 24, y: panel.maxY - 66, width: 56, height: 36) }
    private var rightArrow: NSRect { NSRect(x: panel.maxX - 80, y: panel.maxY - 66, width: 56, height: 36) }

    /// The i-th tab, left to right from the panel's corner; a tab is as wide as its label needs.
    func tabRect(_ i: Int) -> NSRect {
        func width(_ k: Int) -> CGFloat { max(72, 28 + 9.5 * CGFloat(tabItems[k].title.count)) }
        var x = panel.minX + 24
        for k in 0..<i { x += width(k) + 4 }
        return NSRect(x: x, y: panel.minY + 20, width: width(i), height: 24)
    }
    /// The three notebook cells, side by side.
    func notebookCell(_ i: Int) -> NSRect {
        let w = (panel.width - 96 - 2 * 24) / 3
        return NSRect(x: panel.minX + 48 + CGFloat(i) * (w + 24), y: panel.minY + 102, width: w, height: 150)
    }
    /// The box for `side` on a row: Hers on the left, His on the right, at the row's right end.
    func claimBox(_ i: Int, _ side: Claim) -> NSRect { let r = claimRow(i); return NSRect(x: r.maxX - (side == .hers ? 150 : 74), y: r.minY + 1, width: 68, height: 20) }
    /// A piece of evidence's row in the claims card, under the three cells.
    func claimRow(_ i: Int) -> NSRect { NSRect(x: panel.minX + 48, y: panel.minY + 312 + CGFloat(i) * 22, width: panel.width - 96, height: 22) }

    override func mouseDown(with event: NSEvent) {
        if introOpen { dismissIntro(); return }
        if titleOpen { onBegin?(); return }
        guard journalOpen else { return }
        let p = convert(event.locationInWindow, from: nil)
        for (i, item) in tabItems.enumerated() where tabRect(i).contains(p) { if item.tab != journalTab { onTab?(item.tab) }; return }
        if journalTab == .notebook {
            // A found piece of evidence has two boxes, Hers and His: a click on one sets that side (S03.10b).
            if let card = claimCards.first { for (i, row) in card.rows.enumerated() where row.found { for side in Claim.allCases where claimBox(i, side).contains(p) { onClaim?(card.id, row.page, side); return } } }
            for i in 0..<3 where notebookCell(i).contains(p) { onNotebookTone?(i); return }
            if !panel.contains(p) { onClose?() }
            return
        }
        if leftArrow.contains(p) { onFlip?(-1) }
        else if rightArrow.contains(p) { onFlip?(1) }
        else if !panel.contains(p) { onClose?() }
    }

    // MARK: Drawing

    func serif(_ size: CGFloat) -> NSFont { NSFont(name: "Baskerville", size: size) ?? NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size) }

    override func draw(_ dirtyRect: NSRect) {
        if let b = debugBackdrop { b.setFill(); bounds.fill() }

        if captured && !journalOpen && !feedbackOpen && !menuOpen && !introOpen && whiteout < 0.5 { drawCrosshair() }
        if titleOpen && !introOpen { drawTitle() }
        if menuOpen && !introOpen { drawMenuCard() }
        if introOpen { drawIntro() }
        if journalOpen { drawJournal() }
        if feedbackOpen { drawFeedbackCard() }
        if let toast { drawToast(toast) }
        if let readingText, !journalOpen, !feedbackOpen, !menuOpen, !titleOpen, !introOpen { drawReading(readingText) }
        if let bannerText, !journalOpen, !feedbackOpen, !menuOpen, !titleOpen, !introOpen { drawBanner(bannerText) }
        if pageWaiting, !journalOpen, !feedbackOpen, !menuOpen, !titleOpen, !introOpen, whiteout < 0.5 { drawPageMarker() }
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
        let tone = promptDone ? NSColor(calibratedRed: 0.85, green: 0.95, blue: 0.80, alpha: 0.62) : NSColor.white.withAlphaComponent(0.92)
        tone.setStroke(); tone.setFill()
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

        // Tabs (top-left): the active one is inked, the other faded.
        for (i, item) in tabItems.enumerated() {
            let r = tabRect(i)
            text(item.title, font: serif(16), color: item.tab == journalTab ? ink : faded, in: r, align: .center)
            if item.tab == journalTab { ink.withAlphaComponent(0.6).setFill(); NSRect(x: r.minX + 8, y: r.maxY, width: r.width - 16, height: 1.5).fill() }
            if item.unread {          // an amber diamond at the tab's corner: something here has not been read
                let d = NSBezierPath(), c = NSPoint(x: r.maxX - 6, y: r.minY + 3)
                d.move(to: NSPoint(x: c.x, y: c.y - 4)); d.line(to: NSPoint(x: c.x + 4, y: c.y)); d.line(to: NSPoint(x: c.x, y: c.y + 4)); d.line(to: NSPoint(x: c.x - 4, y: c.y)); d.close()
                NSColor(calibratedRed: 0.86, green: 0.58, blue: 0.16, alpha: 1).setFill(); d.fill()
            }
        }

        if journalTab == .notebook {
            drawNotebook(ink: ink, faded: faded, text: text)
        } else if pages.isEmpty {
            text("The journal is empty.", font: serif(26), color: ink, in: NSRect(x: p.minX + 48, y: p.minY + 70, width: p.width - 96, height: 40), align: .center)
            text("Pages you find on the island are kept here, so you can read them again.", font: serif(19), color: faded,
                 in: NSRect(x: p.minX + 60, y: p.minY + 130, width: p.width - 120, height: 120), align: .center, spacing: 6)
        } else {
            let page = pages[min(max(pageIndex, 0), pages.count - 1)]
            text(journalTab.heading, font: serif(15), color: faded, in: NSRect(x: p.minX + 48, y: p.minY + 46, width: p.width - 96, height: 22), align: .center)
            text("page \(toRoman(page.number))", font: .systemFont(ofSize: 12, weight: .medium), color: faded, in: NSRect(x: p.minX + 48, y: p.minY + 72, width: p.width - 96, height: 18), align: .center)
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
        if journalTab != .notebook {
            text("← →  turn pages     Esc or J  close", font: .systemFont(ofSize: 11), color: faded,
                 in: NSRect(x: p.minX, y: p.maxY - 26, width: p.width, height: 16), align: .center)
        }
    }

    /// The notebook: one rubbing per stone, drawn once its glyph has been seen; struck stones can be tapped to hear them again.
    private func drawNotebook(ink: NSColor, faded: NSColor, text: (String, NSFont, NSColor, NSRect, NSTextAlignment, CGFloat) -> Void) {
        let p = panel
        text("Rubbings of the stones", serif(20), ink, NSRect(x: p.minX + 48, y: p.minY + 70, width: p.width - 96, height: 28), .center, 0)
        let names = ["the first stone", "the second stone", "the third stone"]
        for i in 0..<3 {
            let c = notebookCell(i)
            let seen = notebookSeen[i], struck = notebookStruck[i]
            // The leaf: a slightly darker square of paper with a ragged-looking edge.
            NSColor(calibratedRed: 0.88, green: 0.82, blue: 0.68, alpha: 1).setFill()
            NSBezierPath(roundedRect: c.insetBy(dx: 4, dy: 4), xRadius: 4, yRadius: 4).fill()
            faded.withAlphaComponent(0.35).setStroke()
            let edge = NSBezierPath(roundedRect: c.insetBy(dx: 4, dy: 4), xRadius: 4, yRadius: 4); edge.lineWidth = 1; edge.stroke()
            let mid = NSPoint(x: c.midX, y: c.minY + 52)
            if seen {
                drawRubbing(i, at: mid, color: ink.withAlphaComponent(0.82))
                text(names[i], serif(15), ink, NSRect(x: c.minX, y: c.minY + 100, width: c.width, height: 20), .center, 0)
                text(struck ? "tap to hear" : "not yet struck", .systemFont(ofSize: 11), faded, NSRect(x: c.minX, y: c.minY + 124, width: c.width, height: 16), .center, 0)
                if struck {          // a small sound-wave mark
                    ink.withAlphaComponent(0.5).setStroke()
                    for r in [6.0, 11.0, 16.0] as [CGFloat] {
                        let arc = NSBezierPath(); arc.appendArc(withCenter: NSPoint(x: c.midX - 52 + r * 0.2, y: c.minY + 132), radius: r, startAngle: -50, endAngle: 50)
                        arc.lineWidth = 1.2; arc.stroke()
                    }
                }
            } else {
                text("?", serif(40), faded.withAlphaComponent(0.3), NSRect(x: c.minX, y: c.minY + 36, width: c.width, height: 56), .center, 0)
                text("not yet found", .systemFont(ofSize: 11), faded, NSRect(x: c.minX, y: c.minY + 124, width: c.width, height: 16), .center, 0)
            }
        }
        if let card = claimCards.first {
            text("Two accounts", .systemFont(ofSize: 11), faded, NSRect(x: p.minX + 56, y: p.minY + 256, width: p.width - 112, height: 16), .left, 0)
            text("Hers: \u{201C}\(card.hers)\u{201D}", serif(15), ink, NSRect(x: p.minX + 56, y: p.minY + 271, width: p.width - 112, height: 20), .left, 0)
            text("His: \u{201C}\(card.his)\u{201D}", serif(15), ink, NSRect(x: p.minX + 56, y: p.minY + 290, width: p.width - 112, height: 20), .left, 0)
            for (i, row) in card.rows.enumerated() {
                let r = claimRow(i)
                text(row.found ? row.excerpt : "?", serif(14), row.found ? ink : faded.withAlphaComponent(0.4), NSRect(x: r.minX + 8, y: r.minY + 2, width: r.width - 170, height: 20), .left, 0)
                if row.found {
                    for side in Claim.allCases {
                        let b = claimBox(i, side), chosen = row.side == side.title
                        if chosen { ink.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: b, xRadius: 4, yRadius: 4).fill() }
                        text(side.title, serif(14), card.waiting ? faded.withAlphaComponent(0.5) : (chosen ? ink : faded), NSRect(x: b.minX, y: b.minY + 1, width: b.width, height: 18), .center, 0)
                        (card.waiting ? faded.withAlphaComponent(0.2) : (chosen ? ink.withAlphaComponent(0.7) : faded.withAlphaComponent(0.4))).setStroke()
                        let box = NSBezierPath(roundedRect: b, xRadius: 4, yRadius: 4); box.lineWidth = 1; box.stroke()
                    }
                }
            }
            if let status = card.status { text(status, serif(14), faded, NSRect(x: p.minX + 56, y: p.minY + 402, width: p.width - 112, height: 20), .left, 0) }
        }
        if !notebookNotes.isEmpty {
            text("Notes", .systemFont(ofSize: 11), faded, NSRect(x: p.minX + 56, y: p.minY + 428, width: p.width - 112, height: 14), .left, 0)
            text(notebookNotes.joined(separator: "\n"), serif(15), ink, NSRect(x: p.minX + 56, y: p.minY + 442, width: p.width - 112, height: 30), .left, 2)
        }
        text("Tab  next tab     Esc or J  close", .systemFont(ofSize: 11), faded, NSRect(x: p.minX, y: p.maxY - 26, width: p.width, height: 16), .center, 0)
    }

    /// A graphite-rubbing look of each glyph: the stone's carved shape, drawn with a rough stroke.
    private func drawRubbing(_ i: Int, at c: NSPoint, color: NSColor) {
        color.setFill(); color.setStroke()
        func bar(_ rect: NSRect, angle: CGFloat = 0) {
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            var t = AffineTransform(translationByX: rect.midX, byY: rect.midY); t.rotate(byRadians: angle); t.translate(x: -rect.midX, y: -rect.midY)
            path.transform(using: t); path.fill()
        }
        switch i {
        case 0:      // waves: three offset bars
            let offsets: [CGFloat] = [-8, 8, -8]
            for (k, dx) in offsets.enumerated() { bar(NSRect(x: c.x - 36 + dx, y: c.y - 28 + CGFloat(k) * 28, width: 72, height: 9)) }
        case 1:      // wind: two diagonals
            for dx: CGFloat in [-17, 17] { bar(NSRect(x: c.x + dx - 4.5, y: c.y - 42, width: 9, height: 84), angle: 0.6) }
        default:     // stone: a square
            bar(NSRect(x: c.x - 31, y: c.y - 31, width: 62, height: 62))
        }
    }

    // MARK: Title

    private func drawTitle() {
        // A soft vignette keeps the title legible over any part of the island.
        let grad = NSGradient(colors: [NSColor.black.withAlphaComponent(0.0), NSColor.black.withAlphaComponent(0.45)])
        grad?.draw(in: bounds, relativeCenterPosition: NSPoint(x: 0, y: 0))
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.7); shadow.shadowBlurRadius = 14; shadow.shadowOffset = .zero
        let title: [NSAttributedString.Key: Any] = [.font: serif(78), .foregroundColor: NSColor.white, .kern: 14, .shadow: shadow]
        let sub: [NSAttributedString.Key: Any] = [.font: serif(22), .foregroundColor: NSColor.white.withAlphaComponent(0.85), .kern: 3, .shadow: shadow]
        let pulse = 0.55 + 0.45 * sin(titleTime * 2.2)
        let hint: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(pulse), .kern: 2, .shadow: shadow]
        func centred(_ s: String, _ attrs: [NSAttributedString.Key: Any], y: CGFloat) {
            let z = (s as NSString).size(withAttributes: attrs)
            (s as NSString).draw(at: NSPoint(x: bounds.midX - z.width / 2, y: y), withAttributes: attrs)
        }
        centred("LANTERNWRIGHT", title, y: bounds.midY - 150)
        centred("THE ISLE OF VARROW", sub, y: bounds.midY - 50)
        centred(titleHasSave ? "CLICK TO CONTINUE" : "CLICK TO BEGIN", hint, y: bounds.maxY - 150)
    }

    // MARK: Pause menu

    private var menuCard: NSRect {
        let w = min(520, bounds.width * 0.86), h: CGFloat = 590
        return NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    func showMenu() {
        guard !menuOpen else { return }
        menuOpen = true
        newGameArmed = false
        buildMenuControls()
        needsDisplay = true
    }

    func hideMenu() {
        guard menuOpen else { return }
        menuOpen = false
        menuViews.forEach { $0.removeFromSuperview() }
        menuViews = []
        needsDisplay = true
    }

    private func buildMenuControls() {
        menuViews.forEach { $0.removeFromSuperview() }
        menuViews = []
        let c = menuCard
        func label(_ text: String, y: CGFloat) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.textColor = NSColor.white.withAlphaComponent(0.85); l.font = .systemFont(ofSize: 14)
            l.frame = NSRect(x: c.minX + 36, y: y, width: 170, height: 20)
            return l
        }
        func slider(_ value: Float, min lo: Double, max hi: Double, y: CGFloat, action: Selector) -> NSSlider {
            let s = NSSlider(value: Double(value), minValue: lo, maxValue: hi, target: self, action: action)
            s.frame = NSRect(x: c.minX + 210, y: y, width: c.width - 246, height: 22)
            return s
        }
        let resume = NSButton(title: "Resume", target: self, action: #selector(menuResume))
        resume.frame = NSRect(x: c.minX + 36, y: c.minY + 86, width: c.width - 72, height: 36); resume.bezelStyle = .rounded; resume.keyEquivalent = "\r"
        let sens = slider(settings.lookSpeed, min: 0.5, max: 1.5, y: c.minY + 150, action: #selector(menuLookSpeed))
        let calm = slider(settings.calmCamera, min: 0, max: 1, y: c.minY + 190, action: #selector(menuCalm))
        let pace = slider(settings.pace, min: 0.7, max: 1.3, y: c.minY + 230, action: #selector(menuPace))
        let vol = slider(settings.volume, min: 0, max: 1, y: c.minY + 270, action: #selector(menuVolume))
        let scale = slider(settings.renderScale, min: 0.5, max: 1, y: c.minY + 310, action: #selector(menuScale))
        let guide = NSSegmentedControl(labels: Guidance.allCases.map(\.title), trackingMode: .selectOne, target: self, action: #selector(menuGuidance))
        guide.selectedSegment = Guidance.allCases.firstIndex(of: settings.guidance) ?? 0
        guide.frame = NSRect(x: c.minX + 210, y: c.minY + 349, width: c.width - 246, height: 24)
        let invert = NSButton(checkboxWithTitle: "Invert vertical look", target: self, action: #selector(menuInvert))
        invert.state = settings.invertY ? .on : .off
        invert.frame = NSRect(x: c.minX + 36, y: c.minY + 392, width: 260, height: 22)
        invert.attributedTitle = NSAttributedString(string: "Invert vertical look", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.85), .font: NSFont.systemFont(ofSize: 14)])
        let newGame = NSButton(title: "New game…", target: self, action: #selector(menuNewGame))
        newGame.frame = NSRect(x: c.minX + 36, y: c.maxY - 62, width: 150, height: 32); newGame.bezelStyle = .rounded; newGame.identifier = NSUserInterfaceItemIdentifier("newgame")
        let slip = NSButton(checkboxWithTitle: "Slide on very steep slopes (try it)", target: self, action: #selector(menuSlip))
        slip.state = settings.slipOnSteep ? .on : .off
        slip.frame = NSRect(x: c.minX + 36, y: c.minY + 418, width: 330, height: 22)
        slip.attributedTitle = NSAttributedString(string: "Slide on very steep slopes (try it)", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.85), .font: NSFont.systemFont(ofSize: 14)])
        let taa = NSButton(checkboxWithTitle: "Smooth fine detail (anti-aliasing)", target: self, action: #selector(menuTAA))
        taa.state = settings.taa ? .on : .off
        taa.frame = NSRect(x: c.minX + 36, y: c.minY + 444, width: 330, height: 22)
        taa.attributedTitle = NSAttributedString(string: "Smooth fine detail (anti-aliasing)", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.85), .font: NSFont.systemFont(ofSize: 14)])
        let mfx = NSButton(checkboxWithTitle: "Sharper upscaling (MetalFX), when resolution is below 100 %", target: self, action: #selector(menuMetalFX))
        mfx.state = settings.metalFX ? .on : .off
        mfx.isEnabled = Renderer.metalFXSupported          // greyed out where the device has no temporal scaler
        mfx.frame = NSRect(x: c.minX + 36, y: c.minY + 466, width: c.width - 72, height: 20)
        mfx.attributedTitle = NSAttributedString(string: "Sharper upscaling (MetalFX), when resolution is below 100 %", attributes: [.foregroundColor: NSColor.white.withAlphaComponent(Renderer.metalFXSupported ? 0.85 : 0.35), .font: NSFont.systemFont(ofSize: 14)])
        let controls = NSButton(title: "Controls…", target: self, action: #selector(menuControls))
        controls.frame = NSRect(x: c.minX + 36, y: c.minY + 494, width: c.width - 72, height: 30); controls.bezelStyle = .rounded
        let quit = NSButton(title: "Quit", target: self, action: #selector(menuQuit))
        quit.frame = NSRect(x: c.maxX - 36 - 110, y: c.maxY - 62, width: 110, height: 32); quit.bezelStyle = .rounded
        menuViews = [resume, label("Look speed", y: c.minY + 152), sens, label("Camera calm", y: c.minY + 192), calm,
                     label("Walking pace", y: c.minY + 232), pace, label("Volume", y: c.minY + 272), vol, label("Render resolution", y: c.minY + 312), scale, label("Guidance", y: c.minY + 352), guide, invert, slip, taa, mfx, controls, newGame, quit]
        for v in menuViews { v.appearance = NSAppearance(named: .darkAqua); addSubview(v) }
    }

    @objc private func menuResume() { onResume?() }
    @objc private func menuQuit() { onQuit?() }
    @objc private func menuControls() { onShowControls?() }
    @objc private func menuTAA(_ b: NSButton) { settings.taa = b.state == .on; onSettingsChanged?(settings) }
    @objc private func menuSlip(_ b: NSButton) { settings.slipOnSteep = b.state == .on; onSettingsChanged?(settings) }
    @objc private func menuLookSpeed(_ s: NSSlider) { settings.lookSpeed = Float(s.doubleValue); onSettingsChanged?(settings) }
    @objc private func menuGuidance(_ s: NSSegmentedControl) { settings.guidance = Guidance.allCases[max(0, min(s.selectedSegment, Guidance.allCases.count - 1))]; onSettingsChanged?(settings) }
    @objc private func menuPace(_ s: NSSlider) { settings.pace = Float(s.doubleValue); onSettingsChanged?(settings) }
    @objc private func menuCalm(_ s: NSSlider) { settings.calmCamera = Float(s.doubleValue); onSettingsChanged?(settings) }
    @objc private func menuVolume(_ s: NSSlider) { settings.volume = Float(s.doubleValue); onSettingsChanged?(settings) }
    @objc private func menuMetalFX(_ b: NSButton) { settings.metalFX = b.state == .on; onSettingsChanged?(settings) }
    @objc private func menuScale(_ s: NSSlider) { settings.renderScale = Float(s.doubleValue); onSettingsChanged?(settings) }
    @objc private func menuInvert(_ b: NSButton) { settings.invertY = b.state == .on; onSettingsChanged?(settings) }
    @objc private func menuNewGame(_ b: NSButton) {
        if newGameArmed { onNewGame?() } else { newGameArmed = true; b.title = "Erase save and restart?"; b.frame.size.width = 210 }
    }

    private func drawMenuCard() {
        NSColor.black.withAlphaComponent(0.5).setFill(); bounds.fill()
        let c = menuCard
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.6); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.22, alpha: 1).setFill()
        NSBezierPath(roundedRect: c, xRadius: 14, yRadius: 14).fill()
        NSGraphicsContext.restoreGraphicsState()
        let title: [NSAttributedString.Key: Any] = [.font: serif(30), .foregroundColor: NSColor.white]
        let hint: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white.withAlphaComponent(0.55)]
        ("Paused" as NSString).draw(at: NSPoint(x: c.minX + 36, y: c.minY + 28), withAttributes: title)
        (Controls.pauseHint as NSString).draw(at: NSPoint(x: c.minX + 36, y: c.minY + 62), withAttributes: hint)
    }

    // MARK: Feedback panel

    private var feedbackCard: NSRect {
        let w = min(660, bounds.width * 0.88), h: CGFloat = 330
        return NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    func showFeedback() {
        guard !feedbackOpen else { return }
        feedbackOpen = true
        let c = feedbackCard
        let scroll = NSScrollView(frame: NSRect(x: c.minX + 28, y: c.minY + 92, width: c.width - 56, height: 150))
        scroll.hasVerticalScroller = true; scroll.borderType = .noBorder; scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1)
        scroll.appearance = NSAppearance(named: .aqua)      // light field regardless of the system theme
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: scroll.contentSize.height))
        tv.isRichText = false; tv.font = .systemFont(ofSize: 16); tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isVerticallyResizable = true; tv.autoresizingMask = [.width]
        tv.drawsBackground = true; tv.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1)
        tv.textColor = NSColor(calibratedWhite: 0.1, alpha: 1); tv.insertionPointColor = .black
        tv.appearance = NSAppearance(named: .aqua)
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        feedbackText = tv
        let send = NSButton(title: "Send", target: self, action: #selector(sendFeedback))
        send.frame = NSRect(x: c.maxX - 28 - 90, y: c.minY + 262, width: 90, height: 32)
        send.bezelStyle = .rounded; send.keyEquivalent = "\r"; send.keyEquivalentModifierMask = .command
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelFeedback))
        cancel.frame = NSRect(x: c.maxX - 28 - 90 - 100, y: c.minY + 262, width: 90, height: 32)
        cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        feedbackViews = [scroll, send, cancel]
        feedbackViews.forEach(addSubview)
        window?.makeFirstResponder(tv)
        needsDisplay = true
    }

    func hideFeedback() {
        guard feedbackOpen else { return }
        feedbackOpen = false
        feedbackViews.forEach { $0.removeFromSuperview() }
        feedbackViews = []; feedbackText = nil
        needsDisplay = true
    }

    /// Text typed so far (used by tests and by Send).
    var feedbackString: String { feedbackText?.string ?? "" }
    func setFeedbackString(_ s: String) { feedbackText?.string = s }

    @objc private func sendFeedback() {
        let t = feedbackString.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { onFeedbackCancel?() } else { onFeedbackSubmit?(t) }
    }
    @objc private func cancelFeedback() { onFeedbackCancel?() }

    private func drawFeedbackCard() {
        NSColor.black.withAlphaComponent(0.55).setFill(); bounds.fill()
        let c = feedbackCard
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.6); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.22, alpha: 1).setFill()
        NSBezierPath(roundedRect: c, xRadius: 14, yRadius: 14).fill()
        NSGraphicsContext.restoreGraphicsState()
        let title: [NSAttributedString.Key: Any] = [.font: serif(24), .foregroundColor: NSColor.white]
        let hint: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white.withAlphaComponent(0.65)]
        ("Tell me how it feels" as NSString).draw(at: NSPoint(x: c.minX + 28, y: c.minY + 24), withAttributes: title)
        ("What felt wrong, or right? A screenshot of this moment is saved with it." as NSString).draw(at: NSPoint(x: c.minX + 28, y: c.minY + 58), withAttributes: hint)
        ("⌘↩ send     Esc cancel" as NSString).draw(at: NSPoint(x: c.minX + 28, y: c.maxY - 34), withAttributes: hint)
    }

    /// A small sheet of paper, centred, with the note's words and a quiet line saying how to put it away.
    private func drawReading(_ text: String) {
        let width = min(460, bounds.width * 0.6)
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 6
        let ink = NSColor(calibratedRed: 0.20, green: 0.15, blue: 0.09, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [.font: serif(24), .foregroundColor: ink, .paragraphStyle: para]
        let size = (text as NSString).boundingRect(with: NSSize(width: width - 80, height: 600), options: [.usesLineFragmentOrigin], attributes: attrs).size
        let r = NSRect(x: bounds.midX - width / 2, y: bounds.midY - (size.height + 110) / 2, width: width, height: size.height + 110)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.5); shadow.shadowBlurRadius = 18; shadow.shadowOffset = NSSize(width: 0, height: -4)
        NSGraphicsContext.saveGraphicsState(); shadow.set()
        NSColor(calibratedRed: 0.91, green: 0.86, blue: 0.73, alpha: 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
        NSGraphicsContext.restoreGraphicsState()
        ink.withAlphaComponent(0.25).setStroke()
        let edge = NSBezierPath(roundedRect: r.insetBy(dx: 8, dy: 8), xRadius: 4, yRadius: 4); edge.lineWidth = 1; edge.stroke()
        (text as NSString).draw(in: NSRect(x: r.minX + 40, y: r.minY + 34, width: width - 80, height: size.height + 4), withAttributes: attrs)
        let hint = "click to put it back" as NSString
        hint.draw(in: NSRect(x: r.minX, y: r.maxY - 38, width: width, height: 20), withAttributes: [.font: serif(13), .foregroundColor: ink.withAlphaComponent(0.55), .paragraphStyle: para])
    }

    private func drawBanner(_ text: String) {
        let width = min(860, bounds.width * 0.82)
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 4
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.7); shadow.shadowBlurRadius = 6; shadow.shadowOffset = .zero
        let attrs: [NSAttributedString.Key: Any] = [.font: serif(22), .foregroundColor: NSColor.white, .paragraphStyle: para, .shadow: shadow]
        let size = (text as NSString).boundingRect(with: NSSize(width: width - 48, height: 400), options: [.usesLineFragmentOrigin], attributes: attrs).size
        let r = NSRect(x: bounds.midX - width / 2, y: 54, width: width, height: size.height + 36)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).fill()
        (text as NSString).draw(in: NSRect(x: r.minX + 24, y: r.minY + 18, width: width - 48, height: size.height + 4), withAttributes: attrs)
    }

    /// The journal marker: a small key cap "J", an amber diamond and "a page is waiting", in the bottom-right corner.
    private func drawPageMarker() {
        let label = "a page is waiting"
        let attrs: [NSAttributedString.Key: Any] = [.font: serif(15), .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.6, alpha: 0.95)]
        let size = (label as NSString).size(withAttributes: attrs)
        let w = size.width + 78, h: CGFloat = 34
        let r = NSRect(x: bounds.maxX - w - 22, y: 22, width: w, height: h)
        NSColor.black.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
        let key = NSRect(x: r.minX + 9, y: r.minY + 7, width: 20, height: 20)
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let kp = NSBezierPath(roundedRect: key, xRadius: 4, yRadius: 4); kp.lineWidth = 1.2; kp.stroke()
        ("J" as NSString).draw(at: NSPoint(x: key.minX + 5.5, y: key.minY + 2), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.9)])
        let d = NSBezierPath(); let c = NSPoint(x: r.minX + 46, y: r.midY)
        d.move(to: NSPoint(x: c.x, y: c.y + 6)); d.line(to: NSPoint(x: c.x + 5, y: c.y)); d.line(to: NSPoint(x: c.x, y: c.y - 6)); d.line(to: NSPoint(x: c.x - 5, y: c.y)); d.close()
        NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.35, alpha: 1).setFill(); d.fill()
        (label as NSString).draw(at: NSPoint(x: r.minX + 58, y: r.midY - size.height / 2), withAttributes: attrs)
    }

    private func drawToast(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [.font: serif(17), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let r = NSRect(x: bounds.midX - size.width / 2 - 18, y: bounds.maxY - 90, width: size.width + 36, height: size.height + 18)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
        (text as NSString).draw(at: NSPoint(x: r.minX + 18, y: r.minY + 9), withAttributes: attrs)
    }

    private func drawWhiteout() {
        NSColor.white.withAlphaComponent(min(1, whiteout)).setFill(); bounds.fill()
        if whiteout > 0.9, let caption = whiteoutCaption {
            let ink = NSColor(calibratedWhite: 0.3, alpha: min(1, (whiteout - 0.9) * 10))
            let attrs: [NSAttributedString.Key: Any] = [.font: serif(40), .foregroundColor: ink, .kern: 2]
            let z = (caption as NSString).size(withAttributes: attrs)
            (caption as NSString).draw(at: NSPoint(x: bounds.midX - z.width / 2, y: bounds.midY - z.height / 2), withAttributes: attrs)
        }
    }

    private func toRoman(_ n: Int) -> String { OverlayView.roman(n) }
    /// The page heading's numeral (pages 1 to 9; anything else clamps to the ends).
    nonisolated static func roman(_ n: Int) -> String { ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"][min(max(n, 0), 9)] }

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

/// `--dump-overlay base`: writes base-crosshair.png, -journal.png, -journal-empty.png, -end.png and -feedback.png.
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
        let tabs = { (ilse: Bool, oren: Bool, notebook: Bool) in [OverlayView.TabItem(tab: .ilse, title: "Ilse", unread: ilse), OverlayView.TabItem(tab: .oren, title: "Oren", unread: oren), OverlayView.TabItem(tab: .notebook, title: "Notebook", unread: notebook)] }
        v = make(); v.journalOpen = true; v.pages = JournalContent.pages.filter { $0.number <= 4 }; v.pageIndex = 2; v.tabItems = tabs(false, true, false)       // S03.2: Oren's tab has a page not read yet
        try v.snapshot(to: base + "-journal.png")
        v = make(); v.journalOpen = true; v.journalTab = .oren; v.pages = JournalContent.pages.filter { $0.number >= 5 }; v.pageIndex = 0; v.tabItems = tabs(true, false, true)
        try v.snapshot(to: base + "-journal-oren.png")
        v = make(); v.journalOpen = true
        try v.snapshot(to: base + "-journal-empty.png")
        v = make(); v.journalOpen = true; v.journalTab = .notebook; v.notebookSeen = [true, true, false]; v.notebookStruck = [true, false, false]
        try v.snapshot(to: base + "-notebook.png")
        v = make(); v.journalOpen = true; v.journalTab = .notebook; v.notebookSeen = [true, true, true]; v.notebookStruck = [true, true, true]; v.notebookNotes = [Story.doorNote]
        v.claimCards = Contradictions.all.map { c in OverlayView.ClaimCard(id: c.id, hers: c.hers, his: c.his, rows: c.evidence.enumerated().map { OverlayView.ClaimRow(page: $1.page, excerpt: $1.excerpt, found: true, side: $0 == 0 ? "His" : ($0 == 1 ? "Hers" : "His")) }, status: "These pages disagree. Read them again, and give it a little while.", waiting: true) }
        try v.snapshot(to: base + "-notebook-note.png")
        v = make(); v.whiteout = 1; v.whiteoutCaption = "The light folds…"
        try v.snapshot(to: base + "-end.png")
        v = make(); v.titleOpen = true; v.titleHasSave = true
        try v.snapshot(to: base + "-title.png")
        v = make(); v.showMenu()
        try v.snapshot(to: base + "-menu.png")
        v = make(); v.showIntro(fromTitle: true); v.introFade = 1
        try v.snapshot(to: base + "-intro.png")
        v = make(); v.showIntro(fromTitle: false); v.introFade = 1
        v.frame = NSRect(x: 0, y: 0, width: 800, height: 520)
        try v.snapshot(to: base + "-intro-small.png")
        v = make(); v.readingText = Story.doorNote
        try v.snapshot(to: base + "-reading.png")
        v = make(); v.bannerText = "Oren: \"She would not follow, so I went ahead, and I have waited here since.\""
        try v.snapshot(to: base + "-banner.png")
        v = make(); v.captured = true; v.pageWaiting = true; v.step(dt: 1)
        try v.snapshot(to: base + "-page-marker.png")
        v = make(); v.showFeedback(); v.setFeedbackString("The surf sounds much better, but the dock feels a bit narrow.")
        try v.snapshot(to: base + "-feedback.png")
    }
}

import AppKit

/// The controls screen (R08): shown once on a new game, and from the pause menu / Help menu at any time. Everything it says comes from the
/// `Controls` table. Drawn in the journal's language (parchment panel, Baskerville headings), laid out at a nominal size and scaled to fit
/// the window, so it reads at 1600x900, at small sizes and in full screen.
extension OverlayView {
    func showIntro(fromTitle: Bool) {
        introOpen = true
        introFromTitle = fromTitle
        introFade = 0
        needsDisplay = true
    }

    func dismissIntro() {
        guard introOpen else { return }
        introOpen = false
        needsDisplay = true
        onIntroDone?(introFromTitle)
    }

    /// Enter, keypad Enter, Space and Esc close the screen. Called by the game view before the key reaches the game. Returns true if consumed.
    func handleKey(_ code: UInt16) -> Bool {
        guard introOpen, [36, 76, Input.Key.space, Input.Key.escape].contains(code) else { return false }
        dismissIntro()
        return true
    }

    // MARK: Layout

    private struct Placed { var row: ControlRow; var y: CGFloat; var height: CGFloat }
    private struct Column { var heads: [(ControlGroup, CGFloat)] = []; var rows: [Placed] = []; var height: CGFloat = 0 }

    private static let nominalWidth: CGFloat = 940
    private static let pad: CGFloat = 46
    private static let colGap: CGFloat = 40
    private static let keyWidth: CGFloat = 150
    private static let capH: CGFloat = 26

    private var ink: NSColor { NSColor(calibratedRed: 0.17, green: 0.12, blue: 0.08, alpha: 1) }
    private var faded: NSColor { NSColor(calibratedRed: 0.17, green: 0.12, blue: 0.08, alpha: 0.6) }

    private func introColumns() -> (cols: [Column], colWidth: CGFloat, height: CGFloat) {
        let colW = (OverlayView.nominalWidth - 2 * OverlayView.pad - OverlayView.colGap) / 2
        let textW = colW - OverlayView.keyWidth - 14
        let attrs: [NSAttributedString.Key: Any] = [.font: serif(15)]
        let groups = Controls.groups
        var cols = [Column(), Column()]
        for (i, (g, rows)) in groups.enumerated() {
            let ci = i < 2 ? 0 : 1
            var y = cols[ci].height + (cols[ci].heads.isEmpty ? 0 : 22)
            cols[ci].heads.append((g, y)); y += 30
            for r in rows {
                let h = (r.action as NSString).boundingRect(with: NSSize(width: textW, height: 400), options: [.usesLineFragmentOrigin], attributes: attrs).height
                let rowH = max(OverlayView.capH + 4, ceil(h) + 4)
                cols[ci].rows.append(Placed(row: r, y: y, height: rowH)); y += rowH + 10
            }
            cols[ci].height = y
        }
        let header: CGFloat = 112, footer: CGFloat = 118
        return (cols, colW, header + max(cols[0].height, cols[1].height) + footer)
    }

    // MARK: Drawing

    func drawIntro() {
        let fade = introFade
        NSColor.black.withAlphaComponent(0.55 * fade).setFill(); bounds.fill()
        let (cols, colW, H) = introColumns()
        let W = OverlayView.nominalWidth
        let s = min(1, bounds.width * 0.94 / W, bounds.height * 0.94 / H)
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        ctx.cgContext.setAlpha(fade)
        let xf = NSAffineTransform()
        xf.translateX(by: bounds.midX - W * s / 2, yBy: bounds.midY - H * s / 2)
        xf.scale(by: s)
        xf.concat()
        let panel = NSRect(x: 0, y: 0, width: W, height: H)
        ctx.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.55); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        NSColor(calibratedRed: 0.93, green: 0.89, blue: 0.77, alpha: 1).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 14, yRadius: 14).fill()
        ctx.restoreGraphicsState()
        NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.25, alpha: 0.55).setStroke()
        let rule = NSBezierPath(roundedRect: panel.insetBy(dx: 12, dy: 12), xRadius: 8, yRadius: 8); rule.lineWidth = 1; rule.stroke()

        func text(_ str: String, _ font: NSFont, _ color: NSColor, in rect: NSRect, align: NSTextAlignment = .left, kern: CGFloat = 0) {
            let para = NSMutableParagraphStyle(); para.alignment = align; para.lineBreakMode = .byWordWrapping
            (str as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para, .kern: kern])
        }
        text("Finding your way", serif(36), ink, in: NSRect(x: 0, y: 40, width: W, height: 46), align: .center)
        text(introFromTitle ? "A few things to know before you step onto the island." : "The controls, whenever you want them.", serif(17), faded,
             in: NSRect(x: 0, y: 86, width: W, height: 24), align: .center)

        for (ci, col) in cols.enumerated() {
            let x0 = OverlayView.pad + CGFloat(ci) * (colW + OverlayView.colGap)
            let top: CGFloat = 112
            for (g, y) in col.heads {
                text(g.rawValue.uppercased(), .systemFont(ofSize: 11.5, weight: .semibold), faded, in: NSRect(x: x0, y: top + y, width: colW, height: 16), kern: 1.6)
                faded.withAlphaComponent(0.35).setFill()
                NSRect(x: x0, y: top + y + 19, width: colW, height: 1).fill()
            }
            for p in col.rows {
                let y = top + p.y
                drawKeys(p.row.keys, at: NSPoint(x: x0, y: y))
                text(p.row.action, serif(15), ink, in: NSRect(x: x0 + OverlayView.keyWidth + 14, y: y + 2, width: colW - OverlayView.keyWidth - 14, height: p.height + 6))
            }
        }
        text(Controls.reassurance, NSFont(name: "Baskerville-Italic", size: 17) ?? serif(17), ink, in: NSRect(x: 0, y: H - 100, width: W, height: 24), align: .center)
        text(introFromTitle ? "Click, or press Enter or Space, to begin" : "Click, or press Enter, Space or Esc, to close", .systemFont(ofSize: 13, weight: .medium), faded,
             in: NSRect(x: 0, y: H - 62, width: W, height: 18), align: .center, kern: 1.2)
        ctx.restoreGraphicsState()
    }

    /// A row's key column: keycaps, mouse glyphs and "or".
    private func drawKeys(_ keys: [KeyLabel], at origin: NSPoint) {
        var x = origin.x
        let cy = origin.y + OverlayView.capH / 2
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        for k in keys {
            switch k {
            case .cap(let label):
                let tw = (label as NSString).size(withAttributes: [.font: font]).width
                let w = max(OverlayView.capH, tw + 16)
                let r = NSRect(x: x, y: origin.y, width: w, height: OverlayView.capH)
                ink.withAlphaComponent(0.28).setFill()
                NSBezierPath(roundedRect: r.offsetBy(dx: 0, dy: 2), xRadius: 6, yRadius: 6).fill()          // the key's lower edge
                NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.90, alpha: 1).setFill()
                let cap = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6); cap.fill()
                ink.withAlphaComponent(0.5).setStroke(); cap.lineWidth = 1; cap.stroke()
                (label as NSString).draw(at: NSPoint(x: r.midX - tw / 2, y: r.midY - 8), withAttributes: [.font: font, .foregroundColor: ink])
                x += w + 5
            case .mouseLeft, .mouseRight, .mouseMove:
                let r = NSRect(x: x, y: cy - 13, width: 19, height: 26)
                ink.withAlphaComponent(0.8).setStroke(); ink.withAlphaComponent(0.8).setFill()
                let body = NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9); body.lineWidth = 1.4; body.stroke()
                let split = NSBezierPath(); split.move(to: NSPoint(x: r.midX, y: r.minY + 1)); split.line(to: NSPoint(x: r.midX, y: r.minY + 11)); split.lineWidth = 1.2; split.stroke()
                let bar = NSBezierPath(); bar.move(to: NSPoint(x: r.minX + 1, y: r.minY + 11)); bar.line(to: NSPoint(x: r.maxX - 1, y: r.minY + 11)); bar.lineWidth = 1.2; bar.stroke()
                if k == .mouseLeft || k == .mouseRight {                                   // the pressed button is filled
                    let half = NSRect(x: k == .mouseLeft ? r.minX + 1.5 : r.midX, y: r.minY + 1.5, width: r.width / 2 - 1.5, height: 9.5)
                    NSBezierPath(rect: half).fill()
                }
                let word = k.plain
                (word as NSString).draw(at: NSPoint(x: r.maxX + 6, y: cy - 8), withAttributes: [.font: font, .foregroundColor: ink])
                x += 19 + 6 + (word as NSString).size(withAttributes: [.font: font]).width + 6
            case .or:
                let a: [NSAttributedString.Key: Any] = [.font: serif(14), .foregroundColor: faded]
                ("or" as NSString).draw(at: NSPoint(x: x + 1, y: cy - 8), withAttributes: a)
                x += (("or" as NSString).size(withAttributes: a)).width + 7
            }
        }
    }
}

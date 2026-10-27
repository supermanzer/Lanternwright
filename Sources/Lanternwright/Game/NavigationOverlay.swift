import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Metal
import simd

/// `--nav-overlay <path.png>`: a top-down map of each world's terrain with its navigation network drawn on it, for authoring and review (M10.3). Writes
/// `<path>-varrow.png` and `<path>-glasswood.png`. CPU only (no renderer), north (-Z) at the top, east (+X) to the right.
///
/// Drawn: hillshade and sea depth; the path weight as a warm tint; the corridors filled in yellow with a dark edge; a provisional 4 m margin band in orange (M10.4's
/// slow-down zone); trail centre lines (white), plaza centres, the spawn (green) and arrival points (blue); the places the player must reach (white dots);
/// vantages (purple, with a line toward the target); a 50 m scale bar.
enum NavigationOverlay {
    static let marginBand: Float = 4

    static func write(to path: String, device: MTLDevice) throws {
        let stem = path.hasSuffix(".png") ? String(path.dropLast(4)) : path
        for (kind, suffix) in [(WorldKind.varrow, "varrow"), (.glassWood, "glasswood")] {
            let out = "\(stem)-\(suffix).png"
            try render(kind, device: device, to: out)
            print("wrote \(out)")
        }
    }

    static func render(_ kind: WorldKind, device: MTLDevice, to path: String) throws {
        let scene = Scene.make(kind, device: device)
        let net = Layout.Navigation.network(for: kind)
        let pts = NavCoverage.points(for: kind, scene: scene)

        // Frame: every region, the vantages and the coverage points, plus a margin.
        var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
        func grow(_ p: SIMD2<Float>, _ r: Float) { lo = simd_min(lo, p - r); hi = simd_max(hi, p + r) }
        for t in net.trails { for (p, w) in zip(t.points, t.halfWidths) { grow(p, w + marginBand) } }
        for pl in net.plazas { grow(pl.center, pl.radius + marginBand) }
        for p in pts { grow(SIMD2(p.position.x, p.position.z), 4) }
        lo -= 30; hi += 30
        let extent = hi - lo
        let scale = min(3, 2400 / max(extent.x, extent.y))                   // pixels per metre
        let w = Int((extent.x * scale).rounded(.up)), h = Int((extent.y * scale).rounded(.up))
        func toPixel(_ p: SIMD2<Float>) -> CGPoint { CGPoint(x: CGFloat((p.x - lo.x) * scale), y: CGFloat((p.y - lo.y) * scale)) }   // z grows downward: north (-z) is at the top

        func blend(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

        // Base raster.
        var buf = [UInt8](repeating: 255, count: w * h * 4)
        let light = normalize(SIMD3<Float>(-0.5, 0.75, -0.45))
        let terrain = scene.terrain!
        for j in 0..<h {
            for i in 0..<w {
                let x = lo.x + (Float(i) + 0.5) / scale, z = lo.y + (Float(j) + 0.5) / scale
                let g = scene.groundHeight(x: x, z: z)
                var rgb: SIMD3<Float>
                if g < 0 {
                    rgb = blend(SIMD3(0.36, 0.55, 0.66), SIMD3(0.09, 0.2, 0.34), min(-g / 18, 1))
                } else {
                    let dx = scene.groundHeight(x: x + 1.5, z: z) - scene.groundHeight(x: x - 1.5, z: z)
                    let dz = scene.groundHeight(x: x, z: z + 1.5) - scene.groundHeight(x: x, z: z - 1.5)
                    let n = normalize(SIMD3<Float>(-dx / 3, 1, -dz / 3))
                    let shade = 0.55 + 0.55 * max(dot(n, light), 0)
                    let base = blend(SIMD3<Float>(0.55, 0.64, 0.42), SIMD3(0.82, 0.8, 0.72), min(g / 70, 1))
                    rgb = base * shade
                    let pw = terrain.pathWeight(x: x, z: z)
                    if pw > 0 { rgb = blend(rgb, SIMD3(0.86, 0.76, 0.52), pw * 0.55) }
                    if g < 0.6 { rgb = blend(rgb, SIMD3(0.9, 0.86, 0.7), 0.5) }            // beach
                }
                let sd = net.signedDistance(SIMD2(x, z))
                if sd <= 0 { rgb = blend(rgb, SIMD3(1, 0.88, 0.25), 0.42) }
                else if sd < marginBand { rgb = blend(rgb, SIMD3(1, 0.55, 0.15), 0.30 * (1 - sd / marginBand)) }
                if abs(sd) < 0.5 / scale { rgb = SIMD3(0.25, 0.18, 0.05) }
                else if abs(sd) < 1.0 / scale { rgb = blend(rgb, SIMD3(0.25, 0.18, 0.05), 0.6) }
                let o = (j * w + i) * 4
                buf[o] = UInt8(max(0, min(255, rgb.x * 255))); buf[o + 1] = UInt8(max(0, min(255, rgb.y * 255))); buf[o + 2] = UInt8(max(0, min(255, rgb.z * 255)))
            }
        }

        // The numbers: how much of the island the corridors cover (2 m grid; the island is everything above the waterline).
        var land = 0, inside = 0, withMargin = 0
        for j in stride(from: 0, to: h, by: Int(2 * scale) > 0 ? max(Int(2 * scale), 1) : 1) {
            for i in stride(from: 0, to: w, by: max(Int(2 * scale), 1)) {
                let x = lo.x + (Float(i) + 0.5) / scale, z = lo.y + (Float(j) + 0.5) / scale
                let sd = net.signedDistance(SIMD2(x, z))
                if scene.groundHeight(x: x, z: z) > 0 { land += 1 }
                if sd <= 0 { inside += 1 }
                if sd <= marginBand { withMargin += 1 }
            }
        }
        let cell: Float = pow(Float(max(Int(2 * scale), 1)) / scale, 2)
        print(String(format: "%@: corridors %.0f m2 (%.1f %% of the %.0f m2 of dry land); with the %.0f m margin %.0f m2 (%.1f %%)", kind.rawValue,
                     Float(inside) * cell, 100 * Float(inside) / Float(max(land, 1)), Float(land) * cell, marginBand, Float(withMargin) * cell, 100 * Float(withMargin) / Float(max(land, 1))))

        // The camera that looks straight at each vantage's target from its position (what the framing assist settles on): paste it after --camera to render that view.
        for v in net.vantages {
            let eye = SIMD3(v.position.x, scene.groundHeight(x: v.position.x, z: v.position.y) + Player.eyeHeight, v.position.y)
            let d = v.target - eye
            print(String(format: "  vantage '%@'%@: --camera %.2f,%.2f,%.2f,%.4f,%.4f", v.name, v.provisional ? " (provisional)" : "", eye.x, eye.y, eye.z, atan2(d.x, -d.z), atan2(d.y, length(SIMD2(d.x, d.z)))))
        }

        // Vector layer, drawn in top-down pixel coordinates.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let image: CGImage? = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
            func dot(_ p: SIMD2<Float>, _ radius: CGFloat, fill: CGColor, stroke: CGColor = color(0, 0, 0)) {
                let c = toPixel(p)
                ctx.setFillColor(fill); ctx.setStrokeColor(stroke); ctx.setLineWidth(1.5)
                let r = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
                ctx.fillEllipse(in: r); ctx.strokeEllipse(in: r)
            }
            func text(_ s: String, at p: CGPoint, size: CGFloat = 13, fill: CGColor = color(1, 1, 1)) {
                let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
                // Keep the label inside the image: a label that would run off the right edge goes to the left of its anchor instead.
                let width = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])), nil, nil, nil))
                var p = p
                if p.x + width > CGFloat(w) - 4 { p.x = max(4, p.x - width - 18) }
                for (dx, dy, c) in [(1.0, 1.0, color(0, 0, 0, 0.9)), (-1.0, 1.0, color(0, 0, 0, 0.9)), (1.0, -1.0, color(0, 0, 0, 0.9)), (-1.0, -1.0, color(0, 0, 0, 0.9)), (0, 0, fill)] as [(CGFloat, CGFloat, CGColor)] {
                    let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                                           NSAttributedString.Key(kCTForegroundColorAttributeName as String): c])
                    ctx.textPosition = CGPoint(x: p.x + dx, y: p.y + dy)
                    CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
                }
            }
            // Trail centre lines.
            ctx.setStrokeColor(color(1, 1, 1, 0.9)); ctx.setLineWidth(1.5); ctx.setLineDash(phase: 0, lengths: [6, 4])
            for t in net.trails {
                ctx.beginPath(); ctx.move(to: toPixel(t.points[0]))
                for p in t.points.dropFirst() { ctx.addLine(to: toPixel(p)) }
                ctx.strokePath()
                let mid = t.samples(spacing: t.totalLength / 2)[1]
                text(t.name, at: CGPoint(x: toPixel(mid).x + 6, y: toPixel(mid).y - 6), size: 12, fill: color(1, 1, 0.8))
            }
            ctx.setLineDash(phase: 0, lengths: [])
            for pl in net.plazas {
                dot(pl.center, 4, fill: color(1, 1, 1, 0.9))
                text(pl.name, at: CGPoint(x: toPixel(pl.center).x + 7, y: toPixel(pl.center).y - 8), size: 12, fill: color(1, 0.95, 0.7))
            }
            // The places the player must reach.
            for p in pts where !p.name.hasPrefix("causeway slab") { dot(SIMD2(p.position.x, p.position.z), 3, fill: color(1, 1, 1)) }
            for p in pts where p.name.hasPrefix("causeway slab") { dot(SIMD2(p.position.x, p.position.z), 1.5, fill: color(0.8, 0.9, 1)) }
            // Vantages: a marker and a line toward the target (at most 60 m of it).
            for v in net.vantages {
                let to = SIMD2(v.target.x, v.target.z), d = to - v.position
                let end = v.position + d / max(length(d), 1e-3) * min(length(d), 60)
                ctx.setStrokeColor(color(0.75, 0.45, 1)); ctx.setLineWidth(2.5)
                ctx.beginPath(); ctx.move(to: toPixel(v.position)); ctx.addLine(to: toPixel(end)); ctx.strokePath()
                ctx.setStrokeColor(color(0.75, 0.45, 1, 0.8)); ctx.setLineWidth(1.5)
                let c = toPixel(v.position), r = CGFloat(v.tolerance * scale)
                ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                dot(v.position, 5, fill: color(0.6, 0.3, 0.95))
                text(v.name + (v.provisional ? " (provisional)" : ""), at: CGPoint(x: c.x + 9, y: c.y + 20), size: 12, fill: color(0.9, 0.8, 1))
            }
            dot(net.spawn, 7, fill: color(0.2, 0.9, 0.3))
            text("spawn", at: CGPoint(x: toPixel(net.spawn).x + 10, y: toPixel(net.spawn).y + 4), size: 13, fill: color(0.6, 1, 0.6))
            for a in net.arrivals where a != net.spawn { dot(a, 6, fill: color(0.3, 0.6, 1)); text("arrival", at: CGPoint(x: toPixel(a).x + 9, y: toPixel(a).y + 18), size: 12, fill: color(0.7, 0.85, 1)) }
            // Scale bar, north arrow, key.
            let bar = CGFloat(50 * scale), bx: CGFloat = 20, by = CGFloat(h) - 28
            ctx.setFillColor(color(0, 0, 0, 0.7)); ctx.fill(CGRect(x: bx - 8, y: by - 24, width: bar + 330, height: 46))
            ctx.setFillColor(color(1, 1, 1)); ctx.fill(CGRect(x: bx, y: by, width: bar, height: 5))
            text("50 m", at: CGPoint(x: bx, y: by - 6), size: 12)
            text("N up (-Z), E right (+X).  Yellow = corridor, orange = 4 m margin band, purple = vantage", at: CGPoint(x: bx + bar + 12, y: by + 6), size: 11)
            return ctx.makeImage()
        }
        guard let image else { throw NSError(domain: "NavigationOverlay", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not draw the overlay"]) }
        guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "NavigationOverlay", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write \(path)"])
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) { throw NSError(domain: "NavigationOverlay", code: 3, userInfo: [NSLocalizedDescriptionKey: "PNG write failed for \(path)"]) }
    }
}

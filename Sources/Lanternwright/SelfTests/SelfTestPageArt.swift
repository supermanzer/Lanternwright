import Foundation
import AppKit
import simd

/// P02.2 (Q51, Q78): the island-profile diagram on page 1 (data in `PageArt`, drawn by `OverlayView`) and what it shows. The words of the page are not touched; this checks the art's data against the
/// world, and renders the journal page with and without the stones' rubbings to see that the marks change and nothing else on the page does.
extension SelfTestRunner {
    func runPageArt() {
        guard name == "all" || name == "pageart" else { return }
        // The data is the world's: three marks at the stones' real heights, in the order of the climb, between the dock and the lamp.
        let st = PageArt.stations
        check(st.count == Layout.lanternPath.count && st.first?.along == 0 && abs((st.last?.along ?? 0) - 1) < 1e-5 && zip(st, st.dropFirst()).allSatisfy { $0.along < $1.along }, "pageart: the profile runs from the dock (0) to the lamp (1), station by station along the lantern path (\(st.count) stations)")
        check(StoneID.allCases.allSatisfy { PageArt.mark($0).altitude == $0.position.y }, "pageart: each stone's mark is at that stone's real height (\(StoneID.allCases.map { PageArt.mark($0).altitude }))")
        check(PageArt.stonesByAltitude == [.tide, .wind, .summit] && PageArt.stonesByAltitude.map(\.rawValue) == TonePlatePuzzle.legacyOrder, "pageart: from the lowest mark to the highest the stones are tide, wind, stone: the profile SHOWS the order, nothing in the page text has to")
        check(PageArt.kind(forPage: PageArt.islandProfilePage) == .islandProfile && (1...15).filter { PageArt.kind(forPage: $0) != nil } == [PageArt.islandProfilePage], "pageart: exactly one page carries art (page \(PageArt.islandProfilePage))")
        let gameStates = Game(scenes: [.varrow: Scene.makeWorld(device: device)])
        let page1 = gameStates.interactables.first { $0.id == "page_\(PageArt.islandProfilePage)" }.map { ($0.min + $0.max) / 2 }
        check(page1 != nil && simd_length(SIMD2((page1?.x ?? 0) - Layout.tideStone.x, (page1?.z ?? 0) - Layout.tideStone.z)) > PuzzleRules.clueMinDistance, "pageart: the page that carries it lies more than \(Int(PuzzleRules.clueMinDistance)) m from the nearest stone (G11), found on the dock")
        // The page's words are exactly as they were (no text edit): the art adds no characters to any page.
        check(StoryPages.all.first { $0.id == 1 }?.text == "Day one of the last season. The lamp in the lighthouse has gone quiet again. Oren says I fuss over it like a child. Perhaps. But a lighthouse that does not answer is only a tower.", "pageart: page 1's words are untouched")

        // Render the journal on that page: no rubbings, then one, then all (the overlay is the drawing).
        func render(seen: [Bool], page: Int) -> NSBitmapImageRep? {
            MainActor.assumeIsolated {
                let v = OverlayView(frame: NSRect(x: 0, y: 0, width: 1600, height: 900))
                v.debugBackdrop = NSColor(calibratedRed: 0.22, green: 0.30, blue: 0.40, alpha: 1)
                v.journalOpen = true; v.pages = JournalContent.pages.filter { $0.number == page }; v.pageIndex = 0
                v.tabItems = [OverlayView.TabItem(tab: .ilse, title: "Ilse", unread: false), OverlayView.TabItem(tab: .notebook, title: "Notebook", unread: false)]
                v.notebookSeen = seen
                guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
                v.cacheDisplay(in: v.bounds, to: rep)
                return rep
            }
        }
        func pixels(_ r: NSBitmapImageRep) -> [UInt8] { Array(UnsafeBufferPointer(start: r.bitmapData, count: r.bytesPerRow * r.pixelsHigh)) }
        func diff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> (count: Int, box: (x0: Int, x1: Int, y0: Int, y1: Int)) {
            let pa = pixels(a), pb = pixels(b), bpr = a.bytesPerRow, bpp = a.bitsPerPixel / 8
            var n = 0, box = (x0: Int.max, x1: -1, y0: Int.max, y1: -1)
            for y in 0..<a.pixelsHigh { for x in 0..<a.pixelsWide {
                let i = y * bpr + x * bpp
                if (0..<3).contains(where: { abs(Int(pa[i + $0]) - Int(pb[i + $0])) > 6 }) { n += 1; box = (min(box.x0, x), max(box.x1, x), min(box.y0, y), max(box.y1, y)) }
            } }
            return (n, box)
        }
        func ink(_ r: NSBitmapImageRep, rows: Range<Int>) -> Int {
            let p = pixels(r), bpr = r.bytesPerRow, bpp = r.bitsPerPixel / 8, k = r.pixelsWide / 1600          // the bitmap is 2x on a retina display
            var n = 0
            for y in (rows.lowerBound * k)..<(rows.upperBound * k) { for x in (480 * k)..<(1120 * k) { let i = y * bpr + x * bpp; if Int(p[i]) + Int(p[i + 1]) + Int(p[i + 2]) < 3 * 140 { n += 1 } } }
            return n
        }
        guard let none = render(seen: [false, false, false], page: PageArt.islandProfilePage), let one = render(seen: [true, false, false], page: PageArt.islandProfilePage), let all = render(seen: [true, true, true], page: PageArt.islandProfilePage),
              let plain = render(seen: [false, false, false], page: 9) else { check(false, "pageart: the overlay renders"); return }
        let band = 458..<582                                   // the panel (640 x 500, centred on 1600 x 900) starts at y 200; the art sits 258 to 382 below that, above the page-slot squares
        check(ink(none, rows: band) > 400 && ink(plain, rows: band) < 60, "pageart: page 1 has a drawing under its words and a page with no art has none there (ink \(ink(none, rows: band)) vs \(ink(plain, rows: band)))")
        let d1 = diff(none, one), d3 = diff(none, all)
        check(d1.count > 30 && d3.count > d1.count && d3.count > 150, "pageart: a stone's rubbing changes the drawing (one: \(d1.count) pixels, all three: \(d3.count))")
        let k = none.pixelsWide / 1600
        check(d3.box.y0 >= (band.lowerBound - 6) * k && d3.box.y1 <= (band.upperBound + 6) * k && d3.box.x0 >= 480 * k && d3.box.x1 <= 1120 * k, "pageart: and only inside the art's own band (changed rows \(d3.box.y0)-\(d3.box.y1), columns \(d3.box.x0)-\(d3.box.x1), scale \(k))")
        let third = diff(one, all)
        check(d1.box.x1 < third.box.x0, "pageart: the marks stand apart, the lowest stone's the left-most (its change ends at x \(d1.box.x1), the other two begin at \(third.box.x0))")
    }
}

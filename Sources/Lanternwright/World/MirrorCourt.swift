import simd

/// The geometry and the light-tracing rules of the Glass Wood's mirror puzzle, with no rendering in it, so it can be tested
/// exhaustively. The court is a 5x5 grid of 5 m cells centred on `GlassLayout.mirrorCourt`; column c runs east, row r runs south.
///
/// A moon-prism at `source` always fires a beam east. Along the way: three MIRRORS (4 orientations in 45 degree steps) and three
/// glass PANES (3 colours: 0 tide/cyan, 1 wind/green, 2 stone/amber).
///
/// P02.1 (plan P02 section 3, Q49): there are three RECEIVING CRYSTALS, each tuned to one colour (shown on the crystal and echoed by the mural's three
/// glyphs, left to right). The beam passes THROUGH a crystal (it does not stop there); a crystal LIGHTS the instant the beam reaches it in its own colour,
/// in any order and for as long as it does. The court is solved when all three are lit at once. So the player can reason from partial lights, and the
/// answer is no longer a colour ORDER (the old rule repeated the stones' order: design rules D1 and D4).
enum MirrorCourt {
    static let size = 5
    static let cell: Float = 5

    typealias Cell = (c: Int, r: Int)
    static let source: Cell = (0, 4)
    static let mirrorCells: [Cell] = [(3, 4), (3, 1), (0, 1)]
    static let paneCells: [Cell] = [(1, 4), (3, 3), (2, 1)]
    /// The three receiving crystals and the colour each is tuned to (tide, wind, stone, west to east as the mural reads). `receiver` is the first: the page and the column of light stay by it.
    static let receivers: [Cell] = [(0, 3), (2, 4), (3, 2)]
    static let receiverColors = [0, 1, 2]
    static let receiver: Cell = receivers[0]

    /// The one arrangement that lights all three (found by exhaustive search over the 1728, `mirrors` selftest; it is the same one whatever the order the player lights them in).
    static let solutionMirrors = [3, 1, 3]
    static let solutionPanes = [1, 2, 0]
    /// Where the player finds the court: one receiver already lit, a second touched by the wrong colour, nothing solved, no single click solves it, and a careful player needs six clicks.
    static let initialMirrors = [3, 0, 1]
    static let initialPanes = [2, 1, 0]

    static func world(_ cell: Cell) -> SIMD3<Float> {
        let c = GlassLayout.mirrorCourt
        return SIMD3(c.x + Float(cell.c - size / 2) * Self.cell, c.y, c.z + Float(cell.r - size / 2) * Self.cell)
    }

    /// Direction of the mirror's line for each state, in (column, row) space: along x, diagonal, along z, anti-diagonal.
    /// A mirror along a diagonal turns the beam 90 degrees; one along an axis lets parallel beams through and bounces
    /// perpendicular ones straight back.
    static let mirrorLine: [(Int, Int)] = [(1, 0), (1, 1), (0, 1), (-1, 1)]
    /// Line angle in radians (measured from +x toward +z), for drawing the mirror plate.
    static func mirrorAngle(state: Int) -> Float { Float(state) * .pi / 4 }

    static func reflect(_ d: (Int, Int), state: Int) -> (Int, Int) {
        let u = mirrorLine[state & 3]
        let dot = d.0 * u.0 + d.1 * u.1
        let uu = u.0 * u.0 + u.1 * u.1            // 1 for axis lines, 2 for diagonals
        // d' = 2 (d.u / |u|^2) u - d, which stays in integers for these lines.
        return (2 * dot * u.0 / uu - d.0, 2 * dot * u.1 / uu - d.1)
    }

    struct Trace {
        /// Where the beam changes direction, meets a pane, or ends. Segment i runs from points[i] to points[i + 1].
        var points: [Cell] = []
        /// Colour of the light in each segment: -1 = unfiltered moonlight, else the colour of the last pane it passed.
        var segmentColor: [Int] = []
        /// Pane colours in the order the beam met them.
        var panesMet: [Int] = []
        /// For each receiver, the colours of the light that reached it, in order (empty: dark). A receiver is LIT when one of them is its own colour.
        var arrivals: [[Int]] = Array(repeating: [], count: MirrorCourt.receivers.count)
        func lit(_ k: Int) -> Bool { arrivals[k].contains(MirrorCourt.receiverColors[k]) }
        var litCount: Int { (0..<MirrorCourt.receivers.count).filter(lit).count }
        /// Any receiver reached by any light (lit or showing a wrong colour).
        var reachedReceiver: Bool { arrivals.contains { !$0.isEmpty } }
        /// P02.1: solved when every receiver is lit at once.
        var solved: Bool { litCount == MirrorCourt.receivers.count }
    }

    static func trace(mirrors: [Int], panes: [Int]) -> Trace {
        var t = Trace()
        var pos = source
        var dir = (1, 0)
        var color = -1
        t.points = [pos]
        for _ in 0..<80 {                                  // bounded: back-reflections must not loop forever
            pos = (pos.c + dir.0, pos.r + dir.1)
            let inside = pos.c >= 0 && pos.c < size && pos.r >= 0 && pos.r < size
            if !inside {
                // The beam leaves the court: end it at the last cell inside.
                t.points.append((pos.c - dir.0, pos.r - dir.1)); t.segmentColor.append(color)
                return t
            }
            if pos == source {                             // bounced all the way back into the prism
                t.points.append(pos); t.segmentColor.append(color)
                return t
            }
            if let k = receivers.firstIndex(where: { $0 == pos }) {      // the beam passes through a receiving crystal and goes on
                t.arrivals[k].append(color)
            }
            if let k = mirrorCells.firstIndex(where: { $0 == pos }) {
                let nd = reflect(dir, state: mirrors[k])
                if nd != dir {                              // a mirror edge-on to the beam does nothing
                    t.points.append(pos); t.segmentColor.append(color)
                    dir = nd
                }
            } else if let k = paneCells.firstIndex(where: { $0 == pos }) {
                t.points.append(pos); t.segmentColor.append(color)
                color = panes[k]
                t.panesMet.append(color)
            }
        }
        t.points.append(pos); t.segmentColor.append(color)
        return t
    }
}

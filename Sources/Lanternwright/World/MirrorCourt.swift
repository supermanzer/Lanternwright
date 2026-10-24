import simd

/// The geometry and the light-tracing rules of the Glass Wood's mirror puzzle, with no rendering in it, so it can be tested
/// exhaustively. The court is a 5x5 grid of 5 m cells centred on `GlassLayout.mirrorCourt`; column c runs east, row r runs south.
///
/// A moon-prism at `source` always fires a beam east. Along the way: three MIRRORS (4 orientations in 45 degree steps) and three
/// glass PANES (3 colours: 0 tide/cyan, 1 wind/green, 2 stone/amber). The puzzle is solved when the beam reaches the `receiver`
/// having passed the panes in the order of the mural: tide, wind, stone.
enum MirrorCourt {
    static let size = 5
    static let cell: Float = 5

    typealias Cell = (c: Int, r: Int)
    static let source: Cell = (0, 4)
    static let mirrorCells: [Cell] = [(3, 4), (3, 1), (0, 1)]
    static let paneCells: [Cell] = [(1, 4), (3, 3), (2, 1)]
    static let receiver: Cell = (0, 3)

    static let solutionMirrors = [3, 1, 3]
    static let solutionPanes = [0, 1, 2]
    /// Where the player finds the court: scrambled so that nothing is solved, and no single click solves it.
    static let initialMirrors = [0, 2, 1]
    static let initialPanes = [2, 0, 1]

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
        var reachedReceiver = false
        var solved: Bool { reachedReceiver && panesMet == solutionPanes }
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
            if pos == receiver {
                t.points.append(pos); t.segmentColor.append(color)
                t.reachedReceiver = true
                return t
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

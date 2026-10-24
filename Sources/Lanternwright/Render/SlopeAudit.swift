import Foundation
import simd

/// `--audit-slopes` (F01 W5.1): the grade (rise over run) of the lantern path in 10 m segments, and the steepest 10 m anywhere on it.
enum SlopeAudit {
    struct Segment { var from: Float; var grade: Float; var at: SIMD2<Float> }
    static func segments(terrain: Terrain, path: [SIMD3<Float>] = Layout.route, step: Float = 10) -> [Segment] {
        var out: [Segment] = []
        var travelled: Float = 0
        for k in 0..<(path.count - 1) {
            let a = SIMD2(path[k].x, path[k].z), b = SIMD2(path[k + 1].x, path[k + 1].z)
            let len = simd_length(b - a), dir = (b - a) / len
            var s: Float = 0
            while s + step <= len + 1e-3 {
                let p0 = a + dir * s, p1 = a + dir * (s + step)
                let g = (terrain.sampleHeight(x: p1.x, z: p1.y) - terrain.sampleHeight(x: p0.x, z: p0.y)) / step
                out.append(Segment(from: travelled + s, grade: g, at: p0))
                s += step
            }
            travelled += len
        }
        return out
    }
    static func report(terrain: Terrain) -> String {
        let segs = segments(terrain: terrain)
        var s = "grade of the straight lantern path, per 10 m (rise/run; 0.47 = 25 degrees, 0.84 = 40 degrees):\n"
        for g in segs { s += String(format: "  at %5.0f m (%6.1f, %6.1f): %+5.2f  (%4.1f deg)\n", g.from, g.at.x, g.at.y, g.grade, atan(g.grade) * 180 / .pi) }
        let steepest = segs.map { abs($0.grade) }.max() ?? 0
        s += String(format: "steepest 10 m: %.2f (%.1f degrees); %d of %d segments steeper than 0.47\n", steepest, atan(steepest) * 180 / .pi, segs.filter { abs($0.grade) > 0.47 }.count, segs.count)
        return s
    }
}

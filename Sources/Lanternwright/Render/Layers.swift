import Foundation

/// G10.0.2: the layers of a frame that the shimmer attribution switches off one at a time (`--shimmer-layers`, and `--layers-off a,b` for any view or tool). A debug and measuring
/// aid only: nothing is off unless a tool says so, and the hooks are one `contains` test each.
enum RenderLayer: String, CaseIterable {
    case grass, trees, water, glass, props, sky, shadows
    /// The two mist sheets over the sea (a flat haze at 1.6 m and 6.5 m: also over low beach ground). `water` switches them off too; this switches only them (F04 W1's test needs the surface alone).
    case mist
    nonisolated(unsafe) static var off: Set<RenderLayer> = []
    static func isOff(_ l: RenderLayer) -> Bool { !off.isEmpty && off.contains(l) }

    /// The layer a scene item belongs to; nil for the terrain, which is never switched off (it is what the other layers stand on).
    static func of(name: String, refractive: Bool) -> RenderLayer? {
        if name.hasPrefix("terrain") { return nil }
        if refractive { return .glass }
        if name.hasPrefix("trees_") || name.hasPrefix("needles_") { return .trees }
        return .props
    }
    static func parse(_ list: String) -> Set<RenderLayer>? {
        var out: Set<RenderLayer> = []
        for part in list.split(separator: ",") { guard let l = RenderLayer(rawValue: part.trimmingCharacters(in: .whitespaces)) else { return nil }; out.insert(l) }
        return out
    }
}

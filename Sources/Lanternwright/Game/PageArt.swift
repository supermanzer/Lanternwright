import Foundation
import simd

/// P02.2 (Q78): art on a journal page, drawn by the overlay under the page's own words (the words are the user's and are NOT touched here). The first is the ISLAND PROFILE on page 1: the way
/// the keeper climbed seen from the side, sea level to the lamp, with a mark at each stone's real altitude. A mark shows the stone's rubbing once the Notebook has it (a close look, `Notebook.looksAt`)
/// and a bare circle until then, so the page says nothing a player has not looked at: the altitude order is SEEN on it, the glyph says which stone stands where. Data only; the drawing is `OverlayView`.
enum PageArt {
    enum Kind: Equatable { case islandProfile }
    /// The page the profile hangs on: page 1, found on the dock, a long way from every stone (graph rule G11: a key is learned far from where it is used). Page 3 ("the way I first climbed this island")
    /// would suit the words better but lies at the wind stone itself; moving the art there is this one constant (Q78).
    static let islandProfilePage = 1
    static func kind(forPage n: Int) -> Kind? { n == islandProfilePage ? .islandProfile : nil }

    /// One station on the climb, as a fraction of its horizontal length (0 = the dock's landing, 1 = the lamp) and a height in metres.
    struct Station: Equatable { var along: Float; var altitude: Float }
    /// The profile: the lantern path's points (dock landing, the three stones, the lighthouse), by their real positions in `Layout`.
    static let stations: [Station] = {
        let pts = Layout.lanternPath
        var dist: [Float] = [0]
        for i in 1..<pts.count { dist.append(dist[i - 1] + simd_length(SIMD2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z))) }
        return pts.indices.map { Station(along: dist[$0] / dist.last!, altitude: pts[$0].y) }
    }()
    /// Where each stone's mark stands: the station of its own position (the lantern path passes through all three).
    static func mark(_ id: StoneID) -> Station { stations[1 + id.rawValue] }
    /// The stones from the lowest to the highest: the order the profile shows (and the old plates' order).
    static var stonesByAltitude: [StoneID] { StoneID.allCases.sorted { mark($0).altitude < mark($1).altitude } }
    static var maxAltitude: Float { stations.map(\.altitude).max() ?? 1 }
}

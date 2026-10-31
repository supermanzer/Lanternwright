import Foundation

/// S04 (optional): the Tide Archive's shadow-play tableau (S02 section 3, lever 6): one lantern lit at the right place casts the remembered moment on a wall as flat cut-out silhouettes, and ONE
/// remembered moment is shown from each sibling's side. The route decides which version is met first (the stand on the player's own side is the one within reach from the start); lighting the lantern
/// from the other side, once the first has been seen, shows the other. Flat cut-out meshes and light only: no voice, no animation but a slow shift.
///
/// This file is the STATE and the DATA (builder B). The cut-out meshes, the light and the wall are builder A's: they read `Game.tableauShown` and `ShadowTableaux.archive.figures(version)` and the item names
/// below (posted on the board topic `story`). Nothing here gates anything; both versions seen is recorded (`ti_tableau_ilse`, `ti_tableau_oren`) for the optional third ending (S02 section 8).
enum TableauPosture: String, Equatable, CaseIterable {
    case standing, holdingLamp, reaching, turnedAway, raisingLens, kneeling
}

/// One silhouette: who it is, where along the wall (0 left ... 1 right), how tall against the wall (fraction of the wall's height), its posture, and what it carries.
struct TableauFigure: Equatable {
    let who: PageAuthor
    let x: Float
    let height: Float
    let posture: TableauPosture
    let carries: String?
}

struct Tableau: Equatable {
    let id: String
    /// What the moment is, in one line (for the reviewer and the cut-out artist, never shown to the player).
    let moment: String
    /// The scene items: the wall the silhouettes fall on, and the lantern at each side's stand.
    let wall: String
    let lanternItems: [PageAuthor: String]
    /// The two versions: the same night, the same two figures, in different places and postures.
    let ilseSide: [TableauFigure]
    let orenSide: [TableauFigure]
    func figures(_ version: PageAuthor) -> [TableauFigure] { version == .oren ? orenSide : ilseSide }
}

enum ShadowTableaux {
    /// The Archive's tableau: the evening Oren went through the lens, before the lamp was lit (the night the two accounts disagree about).
    static let archive = Tableau(
        id: "ti_tableau",
        moment: "The evening Oren went through the lens first, before the lamp was lit: Ilse at her lamp, Oren at the lens, a wall of lamplight between them.",
        wall: "ti_tableau_wall",
        lanternItems: [.ilse: "ti_tableau_lantern_ilse", .oren: "ti_tableau_lantern_oren"],
        // From Ilse's side: she stands at her lamp, upright, holding it, looking across; he is far off with his back to her and the lens raised. The gap is wide and she does not cross it.
        ilseSide: [TableauFigure(who: .ilse, x: 0.22, height: 0.62, posture: .holdingLamp, carries: "lamp"),
                   TableauFigure(who: .oren, x: 0.80, height: 0.66, posture: .raisingLens, carries: "lens")],
        // From Oren's side: he is nearer the middle, half turned, one hand reaching back toward her; she is small and still at her lamp, held low. The gap is narrower and he does not close it.
        orenSide: [TableauFigure(who: .oren, x: 0.34, height: 0.66, posture: .reaching, carries: "lens"),
                   TableauFigure(who: .ilse, x: 0.74, height: 0.58, posture: .standing, carries: "lamp")])
    /// The slow shift of the whole picture, -1...1 of a small drift (builder A scales it): a pure function of the game clock, so frames are reproducible.
    static func shift(_ t: Float) -> Float { sin(2 * .pi * t / 40) }
}

extension TideArchivePuzzle {
    static let tableauFlags: [PageAuthor: String] = [.ilse: "ti_tableau_ilse", .oren: "ti_tableau_oren"]
    static func tableauLightName(_ side: PageAuthor) -> String { "ti_tableau_light_\(side == .oren ? "oren" : "ilse")" }
    static let tableauLightNames = [tableauLightName(.ilse), tableauLightName(.oren)]
}

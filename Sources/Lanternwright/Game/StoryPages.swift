import Foundation

/// Who wrote a page. The gate (S03.3) counts pages by author; the journal (S03.2) files them under the author's tab.
enum PageAuthor: String, Codable, CaseIterable { case ilse, oren, neutral }

/// S03.1: a journal page as data. `id` is the page's number everywhere else (the save stores collected pages by it, the world's lecterns and sheets use it). `location` is a stable key
/// for where the sheet lies (`world.place`, for tools and later tasks; where it actually stands is `PuzzleProps` / `GlassPuzzleProps`). `glyphLevel` is the `glyphsKnown` at which the page
/// gains its margin lines (S02 section 3: literacy); no page has margin lines yet, so every level is 0.
struct StoryPage: Equatable {
    let id: Int
    let author: PageAuthor
    let text: String
    let location: String
    let glyphLevel: Int
}

/// The eight pages, text unchanged from before S03.1 (pinned by SelfTestStory: the page text is the user's to change, never an incidental edit; page 3 was restored in F04 T1).
enum StoryPages {
    static let all: [StoryPage] = [
        // Varrow: Ilse's journal.
        StoryPage(id: 1, author: .ilse, text: "Day one of the last season. The lamp has gone quiet again. Oren says I fuss over it like a child. Perhaps. But a lighthouse that does not answer is only a tower.", location: "varrow.dock", glyphLevel: 0),
        StoryPage(id: 2, author: .ilse, text: "The stones remember the sea best. I strike the tide-stone first, always: everything on this island begins at the water.", location: "varrow.tide-stone", glyphLevel: 0),
        StoryPage(id: 3, author: .ilse, text: "I tune the lamp each evening the way I first climbed this island: from the water, through the wind, to the stone. Out of order, they only argue.", location: "varrow.wind-stone", glyphLevel: 0),  // F04 T1 (#56): restored exactly as first written (the 2026-10-23 reword told the order outright; the world already carries it in its rank notches)
        StoryPage(id: 4, author: .ilse, text: "Oren has asked again for the lens. He says light that can fold can also carry. Carry what, brother? He did not answer, and I did not like the silence.", location: "varrow.lighthouse-door", glyphLevel: 0),
        // The Glass Wood: Oren's journal.
        StoryPage(id: 5, author: .oren, text: "I went through the lens first. Ilse will say I stole it, and she will be right about the lens and wrong about the reason. The wood on this side is made of glass, and it hums. I wrote down what the stones taught us: water, wind, stone. They mean something here too.", location: "glasswood.arrival", glyphLevel: 0),
        StoryPage(id: 6, author: .oren, text: "Light is not carried, Ilse. It is turned. Three mirrors, three panes of glass: I set them by the order on the wall, the way the keeper climbs. Water, wind, stone. When the beam arrives in that order, the wood answers.", location: "glasswood.receiver", glyphLevel: 0),
        StoryPage(id: 7, author: .oren, text: "The chimes at the pool are tuned to the same three tones as the stones on the island. I did not need a mural for these. I only had to remember how each stone sounded when we were children, and she let me strike them first.", location: "glasswood.chimes", glyphLevel: 0),
        StoryPage(id: 8, author: .oren, text: "Two accounts will reach you, and they will not agree. Hers says I left her. Mine says she would not follow. Read both, then choose whose light you carry. I will be waiting where the wood ends. — O.", location: "glasswood.altar", glyphLevel: 0),
    ]

    static func page(_ id: Int) -> StoryPage? { all.first { $0.id == id } }
    static func ids(by author: PageAuthor) -> [Int] { all.filter { $0.author == author }.map(\.id) }
}

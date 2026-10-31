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

/// The pages: the original eight, with the approved revisions R1 and R3 (page 5's first sentence, page 4's half-line) and the new page 9 (R2) applied in S03.10; page 3 stays exactly as restored in F04 T1 and page 8 is unchanged. Text unchanged from before S03.1 otherwise (pinned by SelfTestStory: the page text is the user's to change, never an incidental edit; page 3 was restored in F04 T1).
enum StoryPages {
    static let all: [StoryPage] = [
        // Varrow: Ilse's journal.
        StoryPage(id: 1, author: .ilse, text: "Day one of the last season. The lamp in the lighthouse has gone quiet again. Oren says I fuss over it like a child. Perhaps. But a lighthouse that does not answer is only a tower.", location: "varrow.dock", glyphLevel: 0),
        StoryPage(id: 2, author: .ilse, text: "The stones remember the sea best. I strike the tide-stone first, always: everything on this island begins at the water. The lamp in the lighthouse listens for the stones, and for nothing else.", location: "varrow.tide-stone", glyphLevel: 0),
        StoryPage(id: 3, author: .ilse, text: "I tune the lamp each evening the way I first climbed this island: from the water, through the wind, to the stone. Out of order, they only argue.", location: "varrow.wind-stone", glyphLevel: 0),  // F04 T1 (#56): restored exactly as first written (the 2026-10-23 reword told the order outright; the world already carries it in its rank notches)
        StoryPage(id: 4, author: .ilse, text: "Oren has asked again for the lens of the lighthouse lamp. He says light that can fold can also carry. Carry what, brother? He did not answer, and I did not like the silence. I told him the lens room is not a place for the impatient, which is not what he asked.", location: "varrow.lighthouse-door", glyphLevel: 0),
        // The Glass Wood: Oren's journal.
        StoryPage(id: 5, author: .oren, text: "The week before the fog, I went through the lens first. Ilse will say I stole it, and she will be right about the lens and wrong about the reason. The wood on this side is made of glass, and it hums. I wrote down what the stones taught us: water, wind, stone. They mean something here too.", location: "glasswood.arrival", glyphLevel: 0),
        StoryPage(id: 6, author: .oren, text: "Light is not carried, Ilse. It is turned. Three mirrors, three panes of glass: I set them by the order on the wall, the way the keeper climbs. Water, wind, stone. When the beam arrives in that order, the wood answers.", location: "glasswood.receiver", glyphLevel: 0),
        StoryPage(id: 7, author: .oren, text: "The chimes at the pool are tuned to the same three tones as the stones on the island. I did not need a mural for these. I only had to remember how each stone sounded when we were children, and she let me strike them first.", location: "glasswood.chimes", glyphLevel: 0),
        StoryPage(id: 8, author: .oren, text: "Two accounts will reach you, and they will not agree. Hers says I left her. Mine says she would not follow. Read both, then choose whose light you carry. I will be waiting where the wood ends. — O.", location: "glasswood.altar", glyphLevel: 0),
        // S03.10 (user decision 6, 2026-10-28; S02 appendix R2): an Ilse page at the seaward end of the dock, away from page 1.
        StoryPage(id: 9, author: .ilse, text: "Rule the first: keepers do not run on the shingle. Rule the second: keepers run when the lamp in the lighthouse is going out. I have broken the second only twice, and I would break it again.", location: "varrow.dock-end", glyphLevel: 0),
    ]

    static func page(_ id: Int) -> StoryPage? { all.first { $0.id == id } }
    /// The pages that stand on Varrow and in the Glass Wood (by id): page 9 is on Varrow's dock.
    static let varrowIDs = [1, 2, 3, 4, 9]
    static let glassIDs = [5, 6, 7, 8]
    static func ids(by author: PageAuthor) -> [Int] { all.filter { $0.author == author }.map(\.id) }
}

/// S04.7: the Tide Archive's six pages (10 to 15), each in the voice of the sibling whose route the player took (S02 section 3, lever 2); pages 11, 13 and 15 also carry the other sibling's trace, which the
/// narrator quotes and reads. They are NOT in `StoryPages.all` (that is the nine pages the gate counts: the way on from the Archive is the solved puzzle only, never a count of pages). The texts are
/// `docs/plans/S04-page-drafts.md`, applied as data and pinned by SHA-256 in `SelfTestStory`; the user has twice reacted to wording, so an edit is a text change plus a new pin.
struct RoutePage: Equatable {
    let id: Int
    let ilse: String
    let oren: String
    let location: String
    func text(route: PageAuthor) -> String { route == .oren ? oren : ilse }
}

extension StoryPages {
    static let archive: [RoutePage] = [
        RoutePage(id: 10, ilse: "The tide comes into the galleries and goes out again in about the time it takes me to read a shelf. The upper ledgers are dry. Someone built this place to be flooded and to keep its books anyway. I read the spines in the order the water leaves them.",
                  oren: "Water in the galleries, rising while I stand here, and the ledgers on the high shelves not even damp. Whoever built this expected the sea and made room for it. I look for where the lamplight lies on the water and I walk toward it.",
                  location: "tidearchive.arrival"),
        RoutePage(id: 11, ilse: "The first line of the charter, in a hand I know from the stone plates at home: a Lanternwright keeps a light so that what is lost between places can find its way back. Not a title. A duty with a name. On the lintel, in chalk: \"Come on, I. You are too slow.\" Oren, a little ahead, as always. He writes as if I could simply come. I have kept a lamp for nine winters, and I do not know whether that chalk is a hand held out or a door left open behind him.",
                  oren: "The first line of the charter: a Lanternwright keeps a light so that what is lost between places can find its way back. Not a lamp. A light, and for the ones who are lost, wherever that is. On the shelf beneath it, a rule-plate in Ilse's careful hand: \"Hold your tone until the lamp answers.\" She has made a wall out of a sentence that was meant to be a road.",
                  location: "tidearchive.lectern"),
        RoutePage(id: 12, ilse: "The Roll of Keepers: every name, every lantern, every pocket held. Maren's is here in the old keeper's hand, and after it the line that should say when she came home. It says nothing. I put my thumb on the blank and the page is cool, as if the ink had only just been taken away. I write her name again below, in mine. Someone should.",
                  oren: "The Roll of Keepers is a ledger of everything held: names, lanterns, pockets. Maren's entry runs out into a blank. Two lines lower, in another ink: \"Oren. Through the lens first. Lost.\" Lost. I had wondered what the word looked like written down. It is tidier than I expected, and it is not in my hand.",
                  location: "tidearchive.roll"),
        RoutePage(id: 13, ilse: "The sluices answer to a tone and to the water together. Tide first, because everything begins at the water. Then wind. Then stone. But the water has to stand at the height of the tone, or the gate hears nothing and goes on holding. On the prism, a chalk arrow pointing at a gate I would not have tried. He thinks light can go anywhere. I think it has to be asked.",
                  oren: "In the chamber at the top the prism takes my beam and gives it back as three: tide, wind, stone, each colour on its own gate. Turn the beam and the colours move; the water decides which gate is low enough to feel them. In the brass beside the prism, a ring pressed in the metal, the shape of Ilse's tuning fork. She would have held the tone until the gate gave. I turn the light.",
                  location: "tidearchive.prism"),
        RoutePage(id: 14, ilse: "The map is on the rim of the dome, in brass pins on slate. Varrow, then a line, then pins I do not know, then a line, a long chain of them, and the last pin has no name. The lighthouse is the first link. The lamp was never for ships. It is the place the chain is held from, and every keeper since has held it by answering.",
                  oren: "On the rim of the dome, in brass pins on slate: a chain. Varrow is the first link, and the lens at the top of our lighthouse is the hook it hangs from. Pins beyond, further than I can read, and a last pin with no name. So that is what the light was for. Not ships. A road laid out in lamps, with someone at each end of it.",
                  location: "tidearchive.dome"),
        RoutePage(id: 15, ilse: "The gallery drains. The Great Ledger lies open at Maren's last entry and the lower half of the page is gone, worn away to a ragged edge. I can read the date. I can read \"to the\", and nothing after it. Under it, in chalk: \"Come on, I,\" and a ring drawn round the I. I do not rub it out. I do not know yet what it asks.",
                  oren: "The gallery drains and the Great Ledger lies open at Maren's last entry. The lower half is worn away. I can read the date. I can read \"to the\", and nothing after it. At the stand beside it a lamp is burning, left lit for me, a little ahead of where I stand. She does not follow. She goes before me and lights the way I would have gone anyway.",
                  location: "tidearchive.ledger"),
    ]
    static let archiveIDs = archive.map(\.id)
    static func archivePage(_ id: Int) -> RoutePage? { archive.first { $0.id == id } }
    /// The text of a page in the journal of a player on `route` (the nine pages are the same on both routes).
    static func text(_ id: Int, route: PageAuthor) -> String? { page(id)?.text ?? archivePage(id)?.text(route: route) }
    /// Who wrote it: the nine have their own authors; an Archive page is in the voice of the route's sibling.
    static func author(_ id: Int, route: PageAuthor) -> PageAuthor? { page(id)?.author ?? (archivePage(id) != nil ? (route == .oren ? .oren : .ilse) : nil) }
}

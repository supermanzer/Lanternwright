# Open questions log

Standing rule from the user (2026-10-28): **do not block on decisions for the user** unless they are a *hard fork* (a choice after which the work cannot continue or would have to be undone in a large way, e.g. a story ending, a world's identity, an irreversible removal). For everything else: pick the most reasonable default that fits the design pillars and the recorded decisions in `docs/STATUS.md`, make it a single constant or control point so a change is cheap, **log it here**, and keep going. The user reviews this file and answers with F notes or in conversation; the reviewer folds answers into the plans.

Format: `### Q<n> (date, who): the question` then *Default taken*, *Where it lives* (file/constant), *What changes if the answer differs*, *Status* (open / answered YYYY-MM-DD: answer).

## Open

### Q1 (2026-10-28, builder B, S03.2): does the Notebook tab keep the stone rubbings?
*Default taken:* yes. The S03 plan says the Notebook tab is "an empty frame until S03.8", but it already holds the three stone rubbings (F01 W7), which a player uses to hear the stones again. They stay; S03.4's door note and S03.9's contradictions are added as further content in the same tab.
*Where it lives:* `App/Overlay.swift` `drawNotebook` (rubbings); `JournalState.addNotebookEntry()` marks the tab when a line is added.
*What changes if the answer differs:* hiding the rubbings is one `if` in `drawNotebook`; their data (`seen_*` / `struck_*` flags) is untouched.
*Status:* open.

### Q2 (2026-10-28, builder B, S03.2): when does a sibling's tab appear, and what is it called?
*Default taken:* a tab appears with the first collected page of that author (no empty "Oren" tab before the Glass Wood: nothing appears before it is collected); the Ilse tab reads "Pages" while the journal is empty (no name is known yet) and "Ilse" from her first page; a neutral page (none exists) is filed under Ilse's tab.
*Where it lives:* `Game/Journal.swift`: `JournalState.visibleTabs`, `JournalState.title(_:)`, `JournalTab.holding(_:)`.
*What changes if the answer differs:* always showing both sibling tabs is one line in `visibleTabs`; renaming the tabs is `title(_:)`.
*Status:* open.

### Q3 (2026-10-28, builder B, S03.2): what counts as "read" for an unread marker?
*Default taken:* a page is read once it is in front of the player in the open journal (any dwell, checked each frame); pages restored from a save are read. A page picked up opens the journal on itself, so in play it is read at once; the markers matter for anything added while the journal is shut (the door note, contradictions).
*Where it lives:* `JournalState.markShown()` (called every frame by `Game.advance`), `Game.restorePage(_:read:)`.
*What changes if the answer differs:* a dwell time (a page counts only after N seconds) is a counter in `markShown()`.
*Status:* open.

### Q4 (2026-10-28, builder B, S03.3): what does the gate say is missing?
*Default taken:* quiet lines by category, never a marker, none while the altar itself is what is missing: only Oren's pages found: "You have heard only him."; only Ilse's: "You have heard only her."; too little of both: "You have heard too little of either."; the contradiction (once S03.9 exists): "Two accounts, and nothing yet that tells them apart." Shown at the lens room ring (S03.5) and as a notebook line; not before the altar is solved.
*Where it lives:* `Game/Gate.swift`: the four `cue...` constants and `GateState.cue(for:)`; the numbers are `GateState.pagesNeeded` (3) and `GateState.contradictionsNeeded` (1).
*What changes if the answer differs:* editing the strings; or showing a cue earlier (before the altar) is one `guard` in `cue(for:)`.
*Status:* open.

### Q5 (2026-10-28, builder A): how soft may the bark's furrows get with distance?
*Default taken:* the furrow and plate edges widen by one pixel footprint (`EDGE_K = 1.0`): the 0.5 m look is unchanged to the eye, the 5 m trunk is very slightly softer, and the woods' near-trunk surface crawl falls by half (trunk-only; with foliage woods 0.049 -> 0.022, grove 0.037 -> 0.029 energy per pixel-frame at the slow step). *Where it lives:* `constant float EDGE_K` above `mat_bark` in `Render/Shaders/Materials.swift`. *What changes if the answer differs:* 2.0 cuts the woods trunk crawl by 72 % but visibly smooths the plates at 3 to 5 m; 0 restores the old look and crawl. *Status:* open.


### Q6 (2026-10-28, builder B, S03.4): how does the door note look and behave?
*Default taken:* one small cream sheet (22 x 30 cm, smaller than a page) with two iron nail heads and a curled corner, nailed between the lower and middle iron straps of the lighthouse door, a little off true; no glow, no marker, no sound. It appears when the altar is solved AND the player is on Varrow, and goes away in the Glass Wood. Reading it opens the journal on the Notebook tab and logs the text once under "Notes"; it is not a page and does not count for the gate. Page 4 lies on the ground by the door steps, so the two papers are close: the note is vertical and nailed, the page lies flat.
*Where it lives:* `World/DoorNote.swift` (look, size, `local` position), `Story.doorNote` (text), `Game.hasReturned` / `syncDoorNote()` / `readNote(_:)` (behaviour), `Overlay.drawNotebook` (the Notes line).
*What changes if the answer differs:* position and size are two constants in `DoorNote`; the condition is one line (`Game.hasReturned`); showing the line elsewhere than the Notebook is the Overlay's `notebookNotes`.
*Status:* open.

### Q7 (2026-10-28, builder B, S03.4): "The lamp is waiting." journal line, and the arrival chime
*Default taken:* the plan's one journal line "The lamp is waiting." is NOT added: the user's door note ("the lamp is waiting at the top") says it, in the Notebook, and a second line would say it twice. The arrival chime phrase (the answer motif, once on arrival, again within 40 m of the door) is asked of builder A on the board topic `story`; B emits the event once A names it.
*Where it lives:* `Story.doorNote`; no code for the line.
*What changes if the answer differs:* add a `Story.notes` entry and call `story.notes.append` at the return (one line in `Game.travel`).
*Status:* open.

## Answered
- 2026-10-28 S03 Oren's exit location: both exits at the original lighthouse; Oren's is a lens portal in the lens room, the dock arch is not an exit.
- 2026-10-28 Page gate: 3 pages of each sibling.
- 2026-10-28 Sealing: visible dimming only.
- 2026-10-28 Page revisions: apply R1-R3 (page 3 stays as restored, page 8 unchanged).
- 2026-10-28 Third ending: approach approved. Conifers: needle look kept. Corridors: kept.

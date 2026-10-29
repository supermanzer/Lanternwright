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

## Answered
- 2026-10-28 S03 Oren's exit location: both exits at the original lighthouse; Oren's is a lens portal in the lens room, the dock arch is not an exit.
- 2026-10-28 Page gate: 3 pages of each sibling.
- 2026-10-28 Sealing: visible dimming only.
- 2026-10-28 Page revisions: apply R1-R3 (page 3 stays as restored, page 8 unchanged).
- 2026-10-28 Third ending: approach approved. Conifers: needle look kept. Corridors: kept.

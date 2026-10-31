# M10 puzzle notes: what the corridors and stations make possible

Written by builder B at M10.5 (2026-10-27). Source for the facts: M10.3 to M10.5 on branch `builder-b` (`Layout.Navigation`, `--nav-overlay`, the framing assist, the stones pilot). **Nothing here is built beyond the stones pilot**; each item is a proposal with its cost, for the reviewer and for S02.

## What the machinery gives a puzzle designer

- **A known route.** The player stays within 4 m of an authored corridor (trails 9 to 11 m wide, plazas 12 to 36 m radius). Corridors cover about 11 % of each world's dry land (16 % with the margin), so every place the eye can be is known. The overlays (`--nav-overlay`) show it.
- **A composed view.** A `Vantage` (position, target, 4 m tolerance) gives a light framing assist: within the tolerance, and looking within 25 degrees of the target, the camera is drawn toward it at most 6 degrees/s (about 2 degrees/s at full look-closer), eased in and out, and cancelled by any input (off for 0.6 s after it). It never fights the player. `--nav-overlay` prints the exact `--camera` for each station so a frame can be rendered.
- **A terrain ray test per station** (`SelfTestNav`): a station whose target cannot be seen fails the selftest. This is how the pilot found what the terrain hides (below).
- **Cost to keep in mind: time.** With the real controller along the centre lines: dock to lighthouse 143 s walking / 85 s running at 2.6 / 4.4 m/s (about 68 s running since F07 B-pace made it 5.5; 162 / 103 s at the first M10.2 speeds); lighthouse to causeway start 76 s; across the causeway 43 s. Any "go back and look again" beat costs minutes, not seconds.

## The stones pilot (built)

The stones are struck by altitude (tide 3 m, wind 34 m, summit 66 m). **Finding: the Varrow hill is convex, so only the downhill direction is intervisible.** From the bench at the wind stone the tide stone is hidden; from the tide stone the wind stone is hidden. So the "ascending altitude" clue cannot be read looking up. Two stations:

| Station | Where | Target | What the frame shows (shots/) |
|---|---|---|---|
| **The climb** | 14 m before the tide stone on the shore path | the lighthouse lantern room | `m105-station-climb.png`: the tide stone (glyph, crystal) in the foreground, the lantern-lit path rising to the lighthouse in the notch |
| **The descent** | 10 m past the summit stone toward the wind stone | halfway between the wind and tide capstones | `m105-station-descent.png`: the path down to the wind stone and its lectern (readable, about 80 m away), the beach and the sea beyond; the tide stone, about 190 m away, is only a speck on the beach |

Camera lines: `--camera 125.14,4.33,130.04,-0.7168,0.3555` and `--camera 0.25,66.21,-9.49,2.4545,-0.3457`. The stones are small at that range, so the frame reads as a *composition* (the path running down past the wind stone to the shore and the sea), not as an inspection: the tide stone is identifiable only with look-closer (right mouse, 2.9x), and a puzzle that needs all three stones legible in one frame needs a closer station or a larger marker (a renderer change, builder A). What the pilot does show is that the *direction* of the order (down to the water) can be seen from the top and cannot be seen from the bottom. A wrong-order strike resets everything, so the station is where a player works out the order, not where they strike.

## Proposals per existing puzzle (none built)

**Lighthouse stones and the causeway**
- *Gate by corridor opening.* Give `Trail`/`Plaza` an optional `opensWith: flag`. Close the north descent, the causeway and the islet until `solved`, so the walk north is the reward (today a free-roamer can walk to the causeway start any time). Cost: the M10.6 audit must check every gate state (closed, opening, open), and a corridor opening or closing under the player must move them (`nearestReachable` already does, but a closing trail should wait until nobody is in it).
- *Sight-line clue.* Let the three capstones show a faint colour pillar visible from the descent station only (needs the renderer: builder A). The player sees blue, green, amber, bottom to top, and the order is on the screen.
- *Forced revisit.* Move one journal page to the descent station's plaza so the pilot's view is met before the strike.

**The lens and the way back**
- The climb back from the islet is 43 s of causeway plus 76 s to the lighthouse. If S02's fork returns the player to Varrow, a destination near the lens (the islet plaza) costs nothing; one at the dock costs 2.5 minutes.

**Glass Wood mirror court** (5x5 grid of 5 m cells, centred on the court; the plaza is 26 m radius)
- *Sight-line.* A raised station on the court's rim where the whole beam path reads in one frame (the dome is gentle, so a 3 to 4 m platform would do). The authored "the court from its approach" vantage (32 m, from the western path) sees the court's centre; it has not been checked for all 25 cells.
- *Gate.* The rim path joins the court to the chime ring round the pool; closing it until the mirrors are solved would make the junction the only way on.

**Chime ring** (five chimes on a 6.5 m arc, placed so you stand in the opening facing all five)
- *Station.* In the opening, looking at the arc's middle. The code comment already describes this view; it is the natural second Glass Wood station.

**The pool and the altar**
- *Forced revisit / reveal.* The pool is invisible from the altar path (the dome hides it, tested) and visible from the rim (`the pool from its rim`). Something that appears in the water once both puzzles are solved forces a trip to the rim, which is off the main route.
- *Altar.* `the altar from the junction` (37 m) is authored; the approach down the altar path is a straight 47 m, a good place for a slow reveal.

**S02's fork door**
- The vantage and corridor data are where the tableaux and the fork door live (X00). A door is a gate (`opensWith`), a tableau is a station. The fork's return to Varrow is the 2.5 minute question above.

## Risks to carry forward

- **Soft-locks.** Every gate multiplies the states `--nav-audit` (M10.6) must check. Do not add a gate without adding its states to the audit.
- **Feeling policed.** 11 % coverage is thin. Loose (M10.7) widens trails 1.6x and the margin 2x; widen before removing.
- **The assist is not a puzzle element.** It only helps a player who is already looking nearly at the view; a puzzle must still work with it off (Free roam, or a player who keeps moving the mouse).

# F04: fourth playtest (notes #52 to #59)

Source: `Lanternwright --feedback` #52 to #59 (2026-10-28; screenshots `20261028-063300.png` to `20261028-064710.png`). Owner: **builder A** (Render, Audio, World), and it comes **before the remaining G10 stream 2 work** because these are visible bugs. Notes #58 and #59 are story and gameplay and go to `S03-phase1-fork.md` (builder B).

Same rules as before: before/after frames Read, selftests green, per-task review step, commit by path, INSPECT.md, merge/tag/push at the end (tag `f04-done`), bundle in the integration checkout.

| # | Note | Item |
|---|---|---|
| 52 | Water around the island still moves through the land with no resistance | W1 |
| 53, 54, 55 | Duplicate pages on the dock, the hill and the summit that cannot be interacted with; "three pages but still only one I can read" | P1 |
| 56 | The page 3 wording makes less sense than the previous wording; restore the previous phrases | T1 |
| 57 | "Should a beam of light throw a shadow?" (the white light column at the Glass Wood altar casts a hard shadow on the plinth) | L1 |
| 58, 59 | Where to go after both siblings' stories; the lighthouse should be the focal point and the place the path is chosen | S03 (builder B) |

## W1 (#52): the shore water still goes through the land

The screenshot (`20261028-063300.png`, dock looking along the east beach) shows, in the shallows: **flat, dark-brown polygons with hard straight edges lying in the water** (about x=1000 to 1400, y=620 to 700, and x=800 to 960, y=690 to 715 of 2000), a **sand bar whose outline is clipped by the water surface in straight facets**, and ripple rings that cross the shore line as if the water were not blocked by it. F03 G2 added the swash model (shoaling, delay, tongue, lee shadow); the *motion* may be right now but the *rendering of the contact line* is not.

Diagnose first (bisect: water off, terrain only; wireframe of the water disc vs the terrain mesh; `--no-swash`):
1. The brown polygons look like **terrain triangles poking through the water surface** (a shelf of the beach whose height is just below the water plane: with the swash and wave heights added, it is intermittently under and over). Cure: the water's depth is already read from the scene (`sceneCopy`/`distanceTexture`); take the shoreline from the **per-pixel depth difference**, not from geometry heights: fade the water to transparent and the wet-sand colour through the last 10 to 20 cm, and offset the water surface so it never intersects a terrain triangle (clamp wave height by the local water depth: `h = min(h, 0.8 * depth)`).
2. Waves must visibly be **blocked and refracted by the land**: ripple rings and swell crests need to fade and bend to the local depth contour (use the shore-distance or depth field the swash already has to attenuate wave amplitude and turn the wave normal's direction toward the shore normal as depth falls). Water must never show moving ripples on land, nor continue across the sand bar.
3. Foam line along the contact edge, stable (not flickering), thin, and following the swash's front.

Accept: frames of the dock/east beach at three heights (eye 1.7 m; looking down from the dock; from the island's high side) before/after, showing no polygon facets, no ripples on the bar; `--shimmer-layers` water crawl not worse; a selftest that no water pixel renders over terrain that is above the local water height by more than 1 cm (sample the depth buffer along three beach transects). The user has now said this three times (#34, #52 and F01): **do not close the item without frames from the exact view of the screenshot** (use the feedback entry's position and yaw: `position 175.0, 0.8, 205.0`, `yaw -0.03 / pitch -0.05`).

## P1 (#53 to #55): remove the decoy sheets

F03 P1 put "loose sheets" (blank, darker) beside every real page. The user reads them as duplicates and gets frustrated when they cannot be read. **Remove the loose sheets entirely** (`DroppedPages.swift`, `PuzzleProps.swift` around line 239, and the `Game.swift` line that leaves them behind). Each page is one object. If a page needs to look "dropped", the way it lies (angled, caught on something, weighted by a pebble) does that; nothing else near it may look like paper. Keep: the page's rest pose, the gust lift, readability, `--list-pages`, and the selftests that all eight can be collected. Accept: frames of the three locations in the screenshots (dock, hill, summit) show one sheet; a selftest that the scene contains exactly one paper object per page id.

## T1 (#56): restore the previous wording

The note was written next to page 3 (position 43.1, 33.9, 55.6 on the island). `Game/Journal.swift` page 3 was reworded on 2026-10-23 (commit `093d8f4`, "page 3 reword") to tell the player the order of the stones. **Restore exactly the earlier text** (from git: `I tune the lamp each evening the way I first climbed this island: from the water, through the wind, to the stone. Out of order, they only argue.`) and check that the puzzle is still solvable and fair: the world already carries the order (rank notches added in the same commit), so the page need not repeat it. Add a selftest that fixes the page text. If other pages were reworded since the first playtests (compare `git log -p -- Journal.swift`), list them in your report and **do not change them**: the user said "restore the previous phrases" and only page 3 shows a reword in history. Accept: page 3 text equals the old one byte for byte; the stones puzzle bot still solves.

## L1 (#57): light has no shadow

The tall white glow column at the Glass Wood altar (and probably any emissive beam, glow shaft or light thread) is drawn as a solid in the **shadow pass**, so it casts a hard black shadow on the plinth. Light sources do not cast shadows. Cure: mark emissive/glow/beam geometry as non-casting (`castsShadow = false` in the scene item), audit every emissive prop (lanterns' glass, the altar column, the lens ring, beams, motes, rings, the page's former glow if any remains) and fix all. Accept: a selftest that lists the non-casting items and asserts the altar column is among them and that no item with emissive > 0 is in the shadow draw list; frame of the altar from the screenshot's view (position 0.8, 7.0, -95.2, yaw -2.27) showing no shadow from the column; the plinth's and pillars' own shadows remain.

## Performance note from these notes (feeds G10 stream 3)

The `pass ms` field in the feedback context (G10.0.1) shows what the user's machine really does at full resolution: **frame 12.9 to 16.9 ms; opaque + sky 9.4 to 11.8 ms; scene copy for AO 0.4 to 1.15 ms; shadow 4096 0.6 to 1.1 ms; TAA resolve 0.4 to 0.6 ms** (about 60 to 75 fps on a 120 Hz display). The bench at 1600 x 900 had 5 ms: the real drawable is about 2.6 times as many pixels, so **opaque + sky is the cost that matters, and it scales with pixels**. After F04 and the tree bark/LOD work, **builder A takes stream 3 (efficiency) before the remaining de-aliasing tasks**, in this order: G10.3.5 overdraw check on opaque + sky, G10.3.2 (the AO copy), G10.3.1 (shadow cache), then G10.4.1 (MetalFX at a render scale below 1, which attacks the pixel-bound cost directly). Judge each on the real drawable size (add `--size 2560x1440` bench rows).

HOLISTIC REVIEW (from the parallel session, requested by the user). Read it fully, then turn it into tasks.

Please do NOT implement all of this blindly. Do this: (1) read it against the finished M5 work, (2) add the items you agree with to docs/TASKS.md as a new section "M5.5: Refinement" ordered by value, with an Accept line each, noting any you reject and why, (3) add any that need a human judgement to docs/INSPECT.md, (4) work them one at a time, committing at each pausing point as before.

A. PUZZLE DESIGN (highest value; matches pillar 3 "fair mystery" and pillar 2 "observable cause and effect")
1. The lighthouse puzzle is nearly trivially solved. The stones sit in order along the lantern path, and journal page 3 states the answer outright ("water, wind, stone"). With no penalty and 3 stones there are 6 permutations, so brute force beats reading. Walking the path IS the solution. Keep the readable-clue idea but make the player do one act of deduction: soften page 3 into an image (the keeper's climb) and let the world carry the ordering, e.g. altitude markers or a tide-line carved on each stone, rather than stating the sequence.
2. Make wrong answers informative, not just a reset. Today a wrong strike dims all three. Instead: keep the correct prefix lit and dim only the wrong one, or let the three tones form a rising arpeggio only when the order is right, so the player can HEAR that something is off. This turns trial and error into learning.
3. Give the "tide" stone a real tide. The design doc mentions tide gates but the sea is static. A slow tide cycle (visible on the dock piles and the shore) that gates when the Tide stone rings would make "from the water" a physical, observable clue, and a reason to revisit the shoreline.
4. Exploit the fixed golden-hour sun. Shadows are already crisp (cascaded shadow maps). One authored shadow clue (the lighthouse's shadow falling across a glyph or a causeway marker) is cheap, fair, and uses the look the game is built around.
5. The slice is one linear corridor (dock -> path -> summit -> islet). Myst-likes reward a loop: add one optional branch or vantage (a shortcut down, a sea cave, a ridge viewpoint that reveals the causeway site) so exploration is a choice, and so the lighthouse beam (once lit) can sweep the sea at dusk and reveal something that was invisible before.

B. THE GLYPH LANGUAGE AND THE JOURNAL (pillar 5: one internal logic; it is the spine of M5)
6. Make the journal an active notebook, not just a page reader: auto-record each glyph and tone the first time the player looks at or strikes it (a small rubbing plus a tap-to-hear tone). M5 puzzle 2 (resonance chord from the tide/wind/stone tones) otherwise relies on the player remembering three sounds from an earlier world. Memory burden is the classic Myst complaint.
7. Reuse, do not re-explain. Check that M5's mural, mirrors and chord puzzle visibly use the SAME three glyph shapes and the same tones as Varrow, and that the Glass Wood puzzles can be solved from clues inside that world plus the notebook (no knowledge only in docs).

C. WORLD, GUIDANCE AND FEEL
8. Sonic landmarks: make the stones hum faintly with 3D falloff when near, and the lens/lighthouse carry a distant tone once lit. Audio wayfinding costs little, suits the procedural audio, and helps without any UI.
9. A "look closer" affordance: hold right mouse (or a key) to narrow the FOV for inspecting distant detail. Free-roaming 3D loses Myst's framed shots; a zoom lets players spot clues (glyphs, the causeway site) the way a pre-rendered frame did.
10. Interact prompts: confirm a clear hover state for interactables and a distinct one for already-used ones, so players know what is finished. Consider a subtle sound when a hover target comes into reach.
11. Link the two worlds in the world. Before the transition, the Lens should show a hint of the Glass Wood (a scrying glimpse through the ring) and the home island should change after the link (lighthouse beam sweeping the sea, mist thinning), so the player feels the first world is alive and consequential. Keep a reason to come back (return link is T5.6, so use it).
12. Pacing: dock-to-summit is roughly 250 m at 3.2 m/s (about 80 s one way), and the islet is another 330 m. That is fine for a first read but the return trips add up. Check that Shift-run is discoverable (a one-time hint) and consider a gentle auto-run toggle rather than fast travel.

D. ENGINEERING (needed before more worlds are added)
13. Stringly-typed puzzle/scene wiring ("beam_tide", "lit_tide", "causeway_3") will collide across scenes. Namespace ids per scene, or give puzzles a small protocol (id, persistentFlags, forceSolved, visuals) and register them with the Scene so Game does not know LighthousePuzzle by name. Game.persistentFlags is currently a hard-coded array of Varrow flags; make it come from the registered puzzles.
14. Save format: SaveData has a version but only one scene. Plan for per-scene state (a dictionary keyed by scene id) and a migration path before the Glass Wood adds flags. Note: partial stone progress is deliberately not saved (fine), but the INSPECT.md row for T4.5 says "puzzle progress kept"; reword to "solved state, pages and position".
15. SelfTest.swift is a single 660+ line file and Renderer.swift is 650+. Split by area (selftests per module) before M5 doubles them; keep every check passing and add a test for each new puzzle's solve and reset logic, including the new informative-wrong-answer behaviour.
16. Add a deterministic scripted playthrough (bot) as a selftest per world that walks to each stone and solves, so regressions in colliders, terrain pads or interactable reach are caught automatically. The Varrow bot already walks the path; extend it to cover the transition into and out of the Glass Wood.

E. WHAT IS ALREADY WORKING WELL (keep it)
No fail state, hand-authored landmarks, a single source of truth for the sky/fog, procedural audio, fast frame times, headless screenshot verification, and the feedback loop (F key). Protect these while adding the above.

PRIORITY ORDER I suggest: 1+2 (puzzle), 6+7 (notebook and glyph reuse), 13+14 (multi-scene plumbing), 3, 8, 9, 11, 4, 5, then 10, 12, 15, 16.

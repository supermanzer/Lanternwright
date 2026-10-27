# Lanternwright — Design & Development Plan

*An original first-person exploration/puzzle game for macOS, in the tradition of Myst (1993).*
Native Swift + Metal. No engine, no external assets. Everything (terrain, sky, water, sound) is procedural.

---

## 1. What we learned from the genre (research summary)

| Lesson | Source | How Lanternwright applies it |
|---|---|---|
| World first, then story and puzzles in a loop where each feeds the others. Myst began with an island as a natural boundary. | Rand Miller interview [1] | The island's geography is designed first. Every puzzle mechanism is a piece of the island's infrastructure (a lighthouse, tide gates, an observatory). |
| No enemies, timers or death. The player sets the pace. | Myst history [2][3] | No fail state. A wrong answer resets the mechanism with a soft chime. Nothing is ever lost. |
| Puzzles reflect "real life": frustration and reward are part of a believable place. | Miller [1] | No sliding-block filler. Each puzzle answers the question "why would the keeper have built this?" |
| Myst's biggest criticism was obtuse puzzles and no hints. | Myst, Wikipedia [2] | Every solution must be derivable from clues the player can *see*. Keeper's journal pages collect automatically into a readable journal. |
| Pre-rendered frames let designers frame clues exactly. Free 3D loses that control, so guidance has to work at a larger scale. | Blow & Miller [5][6] | We use **landmarks and light**: tall silhouettes (the lighthouse) are visible from everywhere, paths are lined with lanterns, and interactables glow faintly on hover. |
| Teach without words. Distinct regions aid orientation. Make it obvious what is interactive. | The Witness [7][8] | A hover cursor plus a subtle emissive pulse on interactables. Each region has its own palette and material language. |
| Culturally consistent puzzle logic: Riven's numerals are one internal rule that is reused. | Riven analyses [9] | The Lanternwright's glyph system (three tones: tide, wind, stone) recurs in every puzzle, so learning it once pays off throughout. |
| Story comes through exploration, not cutscenes. | Obduction design goals [10] | No cutscenes. Story is told through journal pages, architecture and the state of the world. |

## 2. Design pillars

1. **Beauty is the reward.** The world should make players stop walking just to look. Golden-hour light, deep water, mist.
2. **Observable cause and effect.** Every interaction changes something you can see or hear.
3. **Fair mystery.** Hard is fine. Arbitrary is not. Each clue lives in the world, close to where it is used.
4. **Unhurried.** No death, no timers, no inventory juggling.
5. **One internal logic.** One culture, one glyph language, one set of engineering rules.

## 3. Premise (original)

The player wakes on a stone dock on a small island in a still, mist-hung sea at perpetual dusk. The island belonged to **Ilse Varrow**, the last *Lanternwright*. She was a maker of lenses that could *fold light into other places*. Her lighthouse no longer shines. Scattered pages of her journal describe resonance stones that tune the lighthouse lens, and her growing unease about her brother **Oren**, who wanted to use the lenses for something else.

Each completed lens opens a **Refraction**, a separate world reached through light, much as Myst's linking books lead to Ages. The long-form story ends in a choice between the siblings' accounts, which echoes Myst's ethical choice without copying it.

## 4. Core loop

```
explore → notice (landmark, sound, light) → find clue (journal page, glyph, mechanism)
   → experiment with mechanism → observe world change → new area opens → explore …
```

## 5. World layout (vertical slice: "The Isle of Varrow")

* **The Dock** (spawn, southeast). The first journal page is here.
* **Lantern path.** Stone lanterns lead uphill.
* **Three resonance stones**: *Tide* (by the shore), *Wind* (on the ridge) and *Stone* (at the summit). Each sounds a tone and lights its glyph.
* **The Lighthouse** on the summit is always visible and serves as the orienting landmark.
* **The Islet**, offshore to the north. It is unreachable until the puzzle is solved. Then a stone causeway rises from the sea, and a floating lens waits at its end.

**Slice puzzle, "As the keeper climbed":** a journal page reads *"I tune the lamp each evening the way I first climbed this island: from the water, through the wind, to the stone."* Activating the stones in order of altitude (Tide → Wind → Stone) lights each one and sends a beam toward the lighthouse. The lens then ignites and the causeway rises. A wrong order dims all the stones with a falling chime, and the player can try again.

## 6. Technical architecture

**Constraints found in this environment:** there are only Command Line Tools (no Xcode), so there is no offline `metal` compiler. SceneKit is soft-deprecated, and RealityKit custom shaders need precompiled libraries.
**Decision:** SwiftPM executable plus AppKit plus **a custom Metal renderer**, with MSL source embedded as Swift strings and compiled at launch via `MTLDevice.makeLibrary(source:)`. This gives full control over the image, has no dependencies, and teaches the whole pipeline.

```
main.swift ─ CLI args (window mode | --screenshot headless mode)
App.swift  ─ NSApplication, window, GameView (MTKView subclass: input)
Game.swift ─ fixed update loop: Player, Interaction, PuzzleState, Audio
Renderer   ─ frame graph:
   1. Sky LUT pass      (lat-long 256×128 HDR, single-scattering atmosphere, mipmapped → ambient irradiance)
   2. Shadow pass       (sun ortho, 4096² depth)
   3. Opaque HDR pass   (rgba16F + linear depth; GGX + Lambert, PCF shadows, LUT ambient, aerial perspective)
   4. Sky pass          (full-res sky + sun disk + fBm clouds, behind geometry)
   5. Water pass        (Gerstner verts, Fresnel LUT reflection, refraction of scene copy, depth absorption, foam)
   6. Bloom             (threshold + 5-level down/up chain)
   7. Composite         (ACES filmic tonemap, bloom, vignette, grain → sRGB drawable)
World      ─ procedural heightfield island + primitive-built architecture
Overlay    ─ AppKit NSView: crosshair, journal pages (text stays in AppKit, not Metal)
Audio      ─ AVAudioEngine source nodes: wind, surf, synthesized chimes
```

**Why these techniques (a short tutorial):**
* **HDR plus ACES tonemapping.** Real light spans many orders of magnitude, and the sun is about 10⁵× brighter than shadow. We light in physical-ish linear units in a float buffer, then *tonemap* compresses that range like film does: a soft shoulder for highlights and rich saturation in the mids. Clamping to 0–1 instead produces the flat, plasticky look of early-2000s games.
* **Aerial perspective.** Air scatters light, so distant objects take on the sky's color and lose contrast. Our brains read this as *distance*, and it is the single cheapest way to make a world feel vast. Fog color is sampled from the same sky LUT, so it always matches the sky.
* **Sky LUT.** Ray-marching the atmosphere per pixel for every surface would be expensive. We bake it once per frame into a small texture and reuse it for the background, fog, water reflections and (via mipmaps) diffuse ambient light. One source of truth keeps every surface lit consistently.
* **Fresnel water.** At grazing angles water reflects nearly everything, and looking straight down you see through it. Getting that angle-dependence right (Schlick's approximation) is what makes water read as water.
* **Shadow mapping with PCF.** We render depth from the sun, then each pixel asks "is something closer to the sun than me?" Percentage-closer filtering averages several such tests to soften the edges.

**Pattern notes:** the renderer is a **pipeline of passes** (frame graph). Game state is a **flag store** (a blackboard pattern) that puzzles read and write, which decouples puzzle logic from rendering. Interactables are a **component list** (an id, bounds and an action closure), which keeps the door open to data-driven levels.

**Headless screenshot mode:** `Lanternwright --screenshot out.png --camera x,y,z,yaw,pitch --size WxH` renders through the same pipeline offscreen and writes a PNG. This is used for visual regression and development without a window.

## 7. Milestones

| # | Milestone | Acceptance criteria | Status |
|---|---|---|---|
| M0 | Scaffold | `swift build` succeeds; `scripts/bundle.sh` produces `Lanternwright.app` that launches a window; headless screenshot writes a PNG | **done** |
| M1 | The look | HDR + ACES, atmosphere sky + clouds, terrain island, shadows, water, bloom; screenshot looks like a painting at golden hour | **done** |
| M2 | Embodiment | WASD + mouse-look, terrain grounding, colliders, water boundary, ambience audio | **done** |
| M3 | Vertical slice | Dock/path/lighthouse built; 3 resonance stones; journal overlay; puzzle solvable; causeway rises; islet reachable | **done** |
| M4 | Polish pass | Instanced grass/foliage, cascaded shadows, god rays, SSAO, footsteps per surface, save/load of flags, settings menu | **done** |
| M5 | First Refraction | Linking through the lens to a second world (e.g. a glass forest under twin moons) with 2–3 puzzles reusing the glyph language | **done (the final choice is deliberately not built)** |
| M6+ | Full game | 3–4 Refractions, sibling-choice ending, title screen, notarized build | planned |

## 8. Controls

WASD move · Mouse look · Click interact · J journal · Shift run (brisk, not a sprint) · Esc release mouse / close journal · Cmd-Q quit

**Pace and look (M10.1, M10.2).** Walking is 2.3 m/s and running 3.6 m/s (a stroll: the island is a few hundred metres across, so landmarks are a minute or two apart; dock to lighthouse is about 160 s walking along the trails). The look is smoothed (about 70 ms) with a soft limit on flicks (about 240 degrees/s) and pitch limited to +-65 degrees. The pause menu has *Look speed* (0.5 to 1.5, default 0.7 of the old sensitivity), *Camera calm* (0 = raw mouse to 1) and *Walking pace* (0.7 to 1.3). Every amount is a setting because the F key is how a player corrects it.

**Guided movement (M10.3 to M10.7).** Each world has an authored set of corridors (`Layout.Navigation`: trails 9 to 11 m wide, plazas 20 m round the landmarks). Inside them you move freely; past an edge a 4 m margin slows the way outward, steers you back and ends in a hard limit you slide along; nothing says "invisible wall". The pause menu's *Guidance* is Guided (as authored), Loose (corridors 1.6x wider, margin 8 m) or Free roam (no region: the old unconfined walking); `--freeroam` forces it for tools. At a few composed views (vantage stations) a light framing assist draws the camera toward the view when you have stopped turning, at most 6 degrees/s, and any input cancels it. The corridors cover about 12 % of each world's dry land, which also bounds what the renderer has to draw (`ReachableRegion`). `--nav-overlay` draws the corridors and `--nav-audit` is the soft-lock guard: no interactable may be unreachable.

## Sources

1. [Interview with Rand Miller, co-creator of Myst — WayTooMany.games](https://waytoomany.games/2020/05/21/interview-with-rand-miller-co-creator-of-myst/)
2. [Myst — Wikipedia](https://en.wikipedia.org/wiki/Myst)
3. [Myst, World Video Game Hall of Fame 2024 — The Strong Museum of Play](https://www.museumofplay.org/games/myst/)
4. [Traversing Myst — USC Scalar](https://scalar.usc.edu/works/traversing-myst/versions)
5. [The Witness and Obduction Creators Talk Game Design — PlayStation LifeStyle](https://www.playstationlifestyle.net/2017/08/25/the-witness-obduction-ps4-game-design/)
6. [Dev on Dev: The Witness, Obduction Creators Trade Notes — PlayStation Blog](https://blog.playstation.com/?p=194187)
7. [The Witness: Five features that define the game — Game Informer](https://gameinformer.com/games/the_witness/b/pc/archive/2013/06/14/five-features-that-define-the-game)
8. [The Witness: Designing Video Game Environments — Fletcher Studio](https://www.fletcher.studio/blog/2017/5/26/the-witness-designing-video-game-environments)
9. [Riven (2024) Complete Walkthrough Part 2 — God is a Geek](https://www.godisageek.com/2024/06/riven-2024-complete-walkthrough-part-2) · [D'ni Numerology — LP Archive](https://lparchive.org/Riven/Update%2015)
10. [Obduction Wiki](https://obduction.fandom.com/wiki/Obduction?oldid=8253) · [Embedding a Story within a Place with Obduction — Voices of VR](https://voicesofvr.com/?p=3474)
11. [Rand Miller on his favorite puzzle that everybody hates — AV Club](https://avclub.com/Myst-creator-rand-miller-on-his-favorite-puzzle-that-ev-1798251819)
12. [Inform Designer's Manual §50: The design of puzzles](https://inform-fiction.org/manual/html/s50.html)

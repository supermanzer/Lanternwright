# Review R01, part 2: worlds, sound, graphics, maths

Written by a reviewing Claude session at the user's request. Part 1 (`R01-part1-gameplay.md`) covers puzzle design, the notebook and engineering. This part covers new worlds, sound, the "plastic" look, and the mathematics.

**How to use this.** Triage, don't obey. For every item write one line in TASKS.md (a new "M5.5/M6 Refinement" section) with an Accept line, OR reject it with a reason. Rejections are valuable; the reviewer is deliberately ambitious. Judge each item against the design pillars in DESIGN.md §2 (beauty, observable cause and effect, fair mystery, unhurried, one internal logic) and the hard rules in CLAUDE.md (no external deps, no `.metal`, CLT only). Anything that breaks a pillar or a rule is rejected.

---

## 1. Extending the game to new worlds and puzzles

The premise already contains the engine for a coherent campaign: lenses *fold light*, and each world is a "Refraction". Take that literally.

**1.1 One optical idea per world, and the white beam as the through-line.** Each Refraction teaches one property of light, and completing it returns one colour of the spectrum to the lighthouse lens. At the end the lens holds all colours: white light, and the sibling choice (Ilse's account or Oren's) is what you do with it.
| World | Property | Core puzzle verb |
|---|---|---|
| Varrow (done) | resonance / order | strike in sequence |
| The Glass Wood (M5) | reflection / routing | aim mirrors, tinted glass |
| The Drowned Observatory | refraction / focus | raise or lower water to bend a beam; focus the fixed sun through a lens onto a plate |
| The Umbral Archive (night, only your lantern's light) | shadow | cast a shadow to complete a glyph; light/dark as geometry |
| Oren's world, "The Carrying" | transmission | send a signal (tones/light) between islets, reusing everything above |
Keep each world solvable from clues inside it plus the notebook (Part 1 item 6). Never require outside knowledge.

**1.2 Cross-world information.** Myst's best trick is "observe here, apply there". Build at least one puzzle whose clue is in world A and whose mechanism is in world B, with the notebook as the bridge (e.g. a tone sequence heard in the Glass Wood sets the three stones on Varrow to a second state). This also gives players a reason to return home (T5.6) and makes the hub meaningful.

**1.3 The lens room as a hub.** One chamber at the lighthouse top with a ring of sockets. As worlds are completed the beam changes colour and the home island changes with it (mist colour, a new reflection on the sea at dusk). Allow any order after the second world (a dependency graph, not a line), so the player chooses.

**1.4 Extend the glyph language, don't replace it.** Each world adds exactly one new glyph and one new tone to the three from Varrow. Introduce a numeral system built from the same three shapes (Riven's D'ni idea) that murals use, so reading it once pays off everywhere.

**1.5 Puzzle verbs to vary** (so no two feel alike): sequence, routing, harmonic (chord), state observation (tide), alignment (shadow), cross-world transfer, and one *deduction from absence* puzzle (what is missing from a mural). Avoid: timers, inventory, hint buttons that spell out the answer, sliding-block filler.

**Likely detrimental, reject if tempted:** a procedurally generated endless world list (kills hand-authored landmarks and fair mystery); NPCs or dialogue (breaks "no cutscenes", pillar 4); a quest log that tells the player what to do.

## 2. Gameplay refinements (beyond Part 1)

- **Slope-aware pace.** Scale walking speed by the gradient (Tobler's hiking function: speed falls roughly exponentially with slope). The 250 m climb then feels like a climb, downhill feels quick, and cadence and bob follow. Cheap, and it reinforces "the way I first climbed this island".
- **Real sliding collision.** `Player.step` tries "full move, then X alone, then Z alone". That catches on diagonal walls and corners. Use an iterative slide: on contact, remove the velocity component along the contact normal and re-try, up to 3 iterations. Keep the existing step/slope tests.
- **Water as a surface you touch.** The sea is a soft wall. Add ankle-deep wading at the shore (speed drops, splash sounds, expanding ripple rings), which also teaches players where the edge is without a hard stop.
- **Camera feel.** Widen the FOV a few degrees when running (eased), and a small vertical impulse on stopping. Keep the bob; it is already well chosen.
- **Hover feedback.** Distinguish "untouched", "in use" and "finished" interactables (Part 1 item 10).

## 3. Sound: more nuanced dynamics

The synthesis is good; what's missing is *space*, *response* and *restraint*.

1. **Acoustic space.** There is already a simple two-tap feedback reverb on the chime bus (`AmbienceSynth.swift`). Replace it with a feedback-delay-network reverb (a Freeverb/Schroeder or 8-line FDN is ~60 lines, no dependencies) shared by every source with send level and decay driven by the surroundings: ray-cast 8 directions against terrain and colliders for openness and nearest wall distance. Open headland: long, faint, sparse echo off the cliffs. Lighthouse interior: tight, bright stone. Chimes and footsteps should feed it.
2. **Positional sources, not global levels.** Place sounds in the world: surf as a *line source* (emit from the nearest shoreline point to the player, so it swings around you as you walk the coast), gulls, the dock's creak and lap, each stone's hum, lantern flicker. `AVAudioEnvironmentNode` (HRTF) is available without third-party code.
3. **Occlusion by terrain.** Low-pass and attenuate wind and surf when the hill is between you and the coast (a short heightfield ray-march gives a free sonic shadow). Walking over the ridge and hearing the sea fall away is the cheapest way to make the island feel solid.
4. **Dynamics and restraint (pillar 4).** Duck the ambient bed a few dB under chimes and the ignition (sidechain), and let the ambience *breathe*: slow swells and genuine near-silence. A soft limiter on the master bus and a loudness target keep stacked chimes plus surf from clipping.
5. **The puzzle score is the glyph language.** Build a sparse generative drone from the three stone tones in just-intonation ratios (1 : 9/8 : 3/2). Each lit stone adds a voice; the solved chord blooms with the lens ignition. Pillar 5 (one internal logic) and pillar 2 (observable cause and effect) in one mechanism. Also: the correct order should sound like a rising arpeggio (Part 1 item 2).
6. **Footsteps.** Round-robin plus small pitch and level jitter (already partly there); add wading, a hollow thump on the dock (a short low resonance), and a slope-dependent scuff. Silence between steps matters more than adding layers.
7. **Chimes as modal objects.** Per-mode decay (high modes die first), a short noise strike transient, slight detune pairs that beat (shimmer), strike-strength-dependent brightness. The reverb gives them air.
8. **Sonic landmarks.** A distant bell buoy out to sea (gives direction without UI), crickets or frogs only in vegetation at dusk, a low whistle through the lighthouse gallery (a resonant band-pass excited by wind speed).

**Likely detrimental:** continuous melodic music (would compete with the ambience and break the unhurried feel); voice or narration; UI blips. Keep it generative, quiet and tied to world state.

## 4. Graphics: why it reads as "layers of plastic", and what fixes it

Diagnosis from reading `Lit.swift`, `Water.swift`, `Terrain.swift`. The lighting model is sound (HDR, GGX, IBL, CSM, aerial perspective). The plastic look comes from *missing physical effects* and *too-clean surfaces*, not from the renderer's structure.

**4.1 Light that stays in the scene.**
- **Local lights.** Emissive lanterns, glyphs, the lens and the beams currently light nothing; they are stickers. Pass the nearest N (8 to 16) emitters in a constant buffer and add inverse-square point lights in `lit_fragment` (no shadows needed; a smooth windowed falloff `saturate(1-(d/r)^4)^2`). At dusk this gives warm pools on the path and, on ignition, the lens lighting the whole summit: a dramatic payoff for the puzzle (pillar 2). Highest value item in this section.
- **Ground bounce.** Shaded sides get only cool sky irradiance. Add a warm bounce from the sunlit ground into the lower hemisphere of the irradiance map (sun colour x ground albedo x sun elevation). Shadows stop being uniformly blue.
- **Contact hardening.** PCF uses a fixed 16-tap kernel, so every shadow has the same softness. Use PCSS-style blocker search (a few taps) to widen the penumbra with distance from the occluder. Cheap, and shadows then "plant" objects to the ground. Replace the `fract(sin(dot(...)))` rotation hash with interleaved gradient noise (Jimenez) or a small blue-noise texture; sin-hashes are precision-dependent and show patterns.
- **Real god rays.** The current radial blur only works when the sun is on screen. March 16 to 32 steps through the cascaded shadow map toward the camera (jittered per pixel) for volumetric light that works from any angle, and reuse it for the lens beam later.

**4.2 Surfaces with a history (the main anti-plastic lever).**
- **Height-blended material layers.** Terrain materials are blended with `mix` and smoothsteps, which gives soft airbrushed gradients. Use height-based blending (each layer has a height value; the winner takes the pixel with a narrow transition) so grass pokes through sand and soil crumbles into rock with crisp, natural boundaries.
- **Cavity, edge and weathering.** Darken and desaturate in crevices (use the SSAO/curvature signal), lighten worn edges, put moss on north and wet faces, rain streaks running down stone (a stretched vertical noise driven by world Y), salt crust near the waterline. Real surfaces show where water, light and time have been.
- **Break up roughness and albedo at three scales** (metres, decimetres, centimetres). Roughness is currently near-constant per material, which is the plastic tell: real stone, wood and soil vary in gloss patch by patch. Drive roughness from the same noise as the albedo, plus a wet-darkening term near the water.
- **Bevel everything.** Boxes and cones with razor edges read as CGI because no real edge is sharp. Chamfer the dock planks, lighthouse blocks, stones and lanterns by even 1 to 2 cm so edges catch a highlight. Add per-block displacement, mortar lines and per-block colour offsets to the lighthouse via a procedural coursing pattern in the shader.
- **Noise quality.** `vnoise3` is value noise with axis-aligned artefacts at every scale. Switch to gradient noise (quintic interpolation) and rotate each octave to kill grid alignment; use analytic derivatives for the bump normal instead of finite differences (a quarter of the noise evaluations).
- **Clutter at three scales** (rule of thumb): macro (boulders, fallen logs), meso (half-buried rocks, driftwood, reeds, flowers), micro (pebbles, leaf litter, shells). Currently only grass is scattered; this is the second biggest lever after local lights.
- **Vegetation.** Per-blade colour and height variation, blade-base darkening and blend toward the terrain colour, backlit translucency (grass glows at golden hour), and large-scale travelling gust waves sampled from one shared wind field (see 5.4). Cypress as stacked cones will always read as a toy; add branch-level irregularity or fewer, better hero trees near the path.

**4.3 Water.**
- 4 Gerstner waves repeat visibly. Use 8 to 12 components with directions spread in a band around the wind (random but seeded), and band-limit by distance.
- **Whitecaps from the Jacobian.** Foam where the Gerstner displacement's Jacobian determinant goes negative (crests folding) is the standard cheap trick; foam then trails and decays rather than sitting only on the shore.
- **Subsurface at crests.** Backlit wave crests glow green when the sun is behind them; this is the difference between "blue plastic" and water at golden hour.
- **Reflections of the island.** Reflections sample only the sky LUT, so the lighthouse and hill never mirror in the sea. Add a half-resolution screen-space reflection with fallback to the LUT (the scene copy already exists), or a cheap planar reflection of the lighthouse and hill silhouette.
- **Shore run-up**: tie the foam line, the wet-sand darkening line and the surf audio to the same swell function so they agree.

**4.4 Camera and post.**
- **Auto-exposure (eye adaptation).** Largest single "feels real" step for a first-person game: slowly adapt exposure from a histogram or average of the HDR buffer as you move from shade to open sky or enter the lighthouse. Time constant ~1.5 s up, ~0.5 s down.
- **Tonemapper.** The ACES fit shifts hues (blue toward purple, bright reds toward orange) and clips highlights harshly. Evaluate AgX or Khronos PBR Neutral, or a custom filmic curve, against the existing screenshots before switching. Add a modest colour-grade step (lift/gamma/gain) for the dusk mood.
- **Anti-aliasing.** TAA was skipped to protect the grass; the alternative that fits is MSAA 4x on the opaque pass plus alpha-to-coverage for grass blades, or SMAA. Thin props (lantern frames, railings) and the horizon shimmer without it. Measure first (the frame budget has ~5 ms of headroom).
- **Lens touches, sparingly**: faint chromatic fringe at the edges, bloom already present. No depth of field, no motion blur (they fight the "painting" look).

**Likely detrimental, reject if tempted:** ray tracing or any GPU feature needing newer tools; photoreal scanned assets (no external assets rule); a full volumetric cloud raymarcher or fluid ocean FFT (large cost, little payoff next to local lights, auto-exposure and weathering); film-grain/vignette increases (already present; more would muddy the painting look).

## 5. Underlying mathematics

1. **Ground height and the rendered mesh disagree.** `Terrain.sampleHeight` uses bilinear interpolation of a 2 m grid, but the mesh is made of triangles. Within a cell a bilinear patch and a triangulated surface differ by up to several centimetres on rough ground, so feet can float or sink relative to what you see, and `normal()` takes central differences over a bilinear field, which is C0 and creases at cell borders. Fix: make the sampler use the *same triangle split as the mesh* (barycentric height) and compute the normal from that triangle (or from the cached smooth normals). Add a selftest that compares `sampleHeight` against the mesh triangle height at random points.
2. **Terrain shape: erosion, not just noise.** fBm plus ridged noise gives plausible but "inflated" hills with no drainage. Options in increasing effort: (a) analytic-derivative "erosion-style" fBm (octaves damped by accumulated slope, which carves valleys with no simulation); (b) a seeded particle hydraulic-erosion pass over the 513 x 513 grid at load (about 100k droplets, under a second, deterministic); the result also tells you where streams and sediment fans belong, and where sand should collect. Both keep determinism. Preserve the pad flattening and the path-walkability constraints (re-run the existing selftests).
3. **Mesh resolution.** 2 m spacing gives a coarse silhouette near the player, where the eye notices. Add a near-camera finer ring (clipmap or CDLOD at 0.5 m) or displace detail in the vertex shader from the same noise, with the CPU ground query kept consistent (see item 1).
4. **One wind field.** Define `wind(pos, time) -> (direction, strength, gust)` once (world-space travelling noise) and feed grass, trees, mist, gull flight, cloud drift, water ripple direction and the audio wind level from it. This is the same architecture as the sky LUT being the single source of truth for light, and it makes the world feel causally coherent.
5. **Reverse-Z depth.** Perspective with a 6 km ocean and 0.1 m near plane wastes float-depth precision. Reverse-Z (swap near/far in the projection, clear to 0, compare `greater`) gives near-uniform precision and removes z-fighting at the shoreline and on thin geometry. Touches the projection, depth clears and all compares; do it behind the selftest and screenshot checks.
6. **Fixed-step to render interpolation.** The game updates at fixed 120 Hz; the camera should read an interpolated pose between the last two states (alpha = accumulator / dt) so motion is smooth at any display rate. Mouse look stays per-frame, as now.
7. **Diffuse model.** Lambert is the only diffuse. For rough surfaces (stone, earth, dry grass) use a Burley/Disney or Oren-Nayar term (retro-reflection at grazing angles flattens the lit-to-shade falloff the way real rough surfaces do) and add specular occlusion from the AO term so crevices do not shine. Small shader change, visible on the hill at low sun.
8. **Colour management audit.** Keep everything in linear HDR (it is), but check albedo ranges (nothing above ~0.85, grass ~0.05 to 0.2 as it is) and that bloom threshold and exposure are consistent after auto-exposure lands.
9. **Time-of-day.** The sun is fixed (perpetual dusk). A very slow drift would add life but would break any shadow-based clue (Part 1 item 4). Choose: either fixed sun + shadow puzzle, or slow drift + no shadow clue. Do not do both. My recommendation is the fixed sun (it is the game's visual signature).

## 6. Suggested order for this part

1. Local point lights from emitters (4.1) and the puzzle score (3.5): both strengthen the puzzle's cause and effect.
2. Terrain sampler/mesh agreement + selftest (5.1), then wind field (5.4) and slope-aware pace (2).
3. Material work: height-blended layers, roughness variation, cavity/edge/weathering, bevels, clutter (4.2).
4. Auto-exposure, tonemapper evaluation, AA (4.4).
5. Audio space: reverb, positional surf, terrain occlusion (3.1 to 3.3).
6. Water upgrades (4.3), erosion (5.2), reverse-Z (5.5), the rest.

Run the full selftest and a before/after screenshot of `dock`, `overview`, `summit` for every visual change, and Read the PNGs. A change that does not visibly improve those frames is not worth its complexity; say so in the task's done-note.

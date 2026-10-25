# F02: plan from the user's second playtest (15 notes, #18 to #32, 2026-10-25)

Source: `Lanternwright --feedback` entries #18 to #32 (screenshots in `~/Library/Application Support/Lanternwright/feedback/`, files `20261025-*.png`). The reviewer read all notes and opened the screenshots for #19, #20, #23, #25, #26, #28, #29 and #32. **Triage into TASKS.md (accept with an Accept line, or REJECT with a reason), then work in the order given at the end.** Same rules as before: before/after frames Read and compared, selftests and bots green, commit at each pausing point, `docs/INSPECT.md` updated, `scripts/bundle.sh` at the end, story ending left to the user. Also fill in an "Outcome" section at the top of this file when you finish, in the style of F01's.

Two lessons from this round, applied to everything below:
1. **F01's audio fixes were verified by relative measurements and the user still hears them as wrong** (#18, #27, #30, #22: the same complaints as F01 #6 and #10). So this time set **absolute targets** (dB at stated distances, modulation depth, spectral shape) and assert them in selftests. Where a number cannot capture "sounds like a boiling kettle", say so in INSPECT.md and keep the targets conservative.
2. **Several F01 fixes introduced their own faults** (#19, #20: the tree footings; #25: the broken pillar). Every fix that adds geometry needs a close-up frame at 0.5 m from two sides before it is called done.

## The user's notes, mapped to workstreams

| # | Note (short) | Workstream |
|---|---|---|
| 18 | Ocean still too loud far from the shore (at about 130 m inland, play position 90, 94) | A1 |
| 19 | Noticeable gaps at the bases of trees | G1 |
| 20 | The 3D effect at a tree base looks inverted; no bases around trunks, go straight into the ground | G1 |
| 21 | Steps on rock sound like a xylophone; solid stone does not resonate | A2 |
| 22 | Wind is very loud, nothing visual shows wind; sounds and visuals must align. Add very soft slow melodic droning moving inland | A3, A4 |
| 23 | Shimmer on fine details; may need a different rendering to keep them crisp and static | R1 |
| 24 | Stone (causeway) steps are a high plinking sound; should be a superficial smack with no resonance | A2 |
| 25 | Toppled pillar sits inside its base; make placement respect the base, and the break rough, not laser-cut | G2 |
| 26 | Distant details jump back after several steps toward them; visuals must obey real parallax | R2 |
| 27 | Ocean too constant, like one wave always breaking; needs rhythm and distance falloff | A1 |
| 28 | The camera does not step up when crossing steps; it should follow terrain | M1 |
| 29 | Interacting with water needs water sounds; the "hard block" feels artificial | A5, G3 |
| 30 | Wind sounds like a boiling kettle; too loud, too constant, not tied to the visuals | A3 |
| 31 | Dock steps too hollow, not like solid planks | A2 |
| 32 | The lines on the dock planks are too geometric | G4 |

---

## A. Audio

### A1. Surf: absolute level, rhythm (#18, #27)
**Why it is still wrong (from code, `AudioSpace.surfField`, `AudioEngine`).** F01 made the falloff `1/(1+(d/20)^2)` and then `level = (3 sum/24)^0.7`, and `surfGain = 0.75 * level`. The 0.7 exponent and the sum over 24 rays flatten the curve: the summit measured 11 times quieter than the beach in RMS (about -21 dB), which is far too little. A listener 130 m inland from a quiet sea should hear it only as a faint wash; at 200 m, almost nothing. Second, the surf noise is a continuous envelope with a slow swell, not discrete breaking waves, hence "a wave constantly breaking".

**Plan.**
- Replace the level law with an explicit physical-ish one: amplitude `~ 1/(1 + d/8)` for a line source plus air absorption, giving about -6 dB per doubling beyond 16 m. Targets (relative to the level standing at the waterline = 0 dB): **40 m: -14 dB; 100 m: -26 dB; 200 m: -38 dB or below (inaudible under the ambient bed)**. Assert these in a selftest from the same functions the engine calls (not copies of the constants).
- Give the surf **rhythm**: synthesise waves as discrete events. A wave set every 6 to 11 s (jittered, with every third or fourth larger), each with a rising swash (1 to 2 s), a crest hiss, and a retreating drain with a falling lowpass (2 to 4 s), and a clear quiet gap between. Level modulation depth (max over min of the 1-second envelope across 60 s) must be at least 8 dB at the waterline, and the pattern must not be periodic enough to loop audibly. Far from the shore, the individual waves smear into a slow swell (lowpass, 0.1 to 0.2 Hz modulation), which is the existing "farness" behaviour: keep that, but do it by lowering level and bandwidth, not by raising constant sub-bass.
- Stereo: each wave should travel along the nearest shoreline (a small pan sweep) instead of a fixed pan.
- Selftest additions: at 5 m, 40 m, 100 m, 200 m, 300 m of shore distance, offline render 60 s and report level in dB relative to the waterline and the envelope modulation depth. Table in the done-note.

### A2. Hard surfaces and planks: stone is a smack, wood is a plank (#21, #24, #31)
**Why it is wrong.** `FootstepRecipe` for rock and stone has a modal body that rings (the user hears a xylophone, #21, and a high plinking, #24). Real stone underfoot has almost no resonance: a short broadband impact, mostly 1 to 4 kHz, a tiny bit of low thump from the ground, and gritty grains if there is loose material. The dock is now too hollow (#31): F01 mapped clearance to cavity gain up to full boom.

**Plan.**
- **Stone and rock recipes:** remove or heavily damp every modal partial above 600 Hz; decay of the whole step under 60 ms (measure -30 dB time; target under 80 ms). Impact = filtered noise burst (2 to 5 ms attack, band 800 Hz to 5 kHz) plus a damped low thump (60 to 120 Hz, under 40 ms). Add optional grit grains (a few quiet clicks) for the `rock` surface only, and a very quiet slap tail for wet causeway slabs. Vary per step (pitch of the band centre, level, grain count); no repeated identical step.
- **Selftest (assert):** for stone and rock, the spectral peak-to-mean ratio above 300 Hz is low (no tonal peak: a ratio below a chosen bound against a noise reference), -30 dB decay time under 80 ms, and the strongest 1/3-octave band is not above 4 kHz.
- **Dock:** cap the cavity layer so even the seaward end reads as a solid plank on beams: cavity gain at hollowness 1 is at most 40 % of the current, decay shortened to under 0.35 s, and add a solid "knock" (wood body, 150 to 400 Hz, 40 to 90 ms) to every dock step. Landward planks stay a dull thud. Keep the monotonic selftest but lower the end values; add: -30 dB decay at hollowness 1 under 0.4 s.
- Listen-check list into INSPECT.md: stone causeway, summit rock, lighthouse plinth, shore-end planks, mid-dock, dock end.

### A3. Wind: believable level, no kettle, tied to a wind field (#22, #30)
**Why it is wrong.** F01 replaced the broadband rustle with two resonant band-passes (Q 7 and 8) that follow gusts. A high-Q band-passed noise is exactly the whistling-kettle sound. The level also rises with altitude to `0.18 + 0.55 * y/70`, which makes the summit loud and constant, while the visuals show nothing (#22).

**Plan.**
- **Sound design:** wind is low-frequency, broadband, with large dynamic range: a lowpassed brown-ish noise (corner 200 to 900 Hz following gust strength) with slow gust envelopes (4 to 12 s, deep: gusts reach 4 to 10 times the lull amplitude), occasional short louder flurries, and a second **very gentle** formant only on strong gusts (Q at most 1.5), plus occasional leaf or grass rustle that appears only when grass or trees are near. No narrow resonances above Q 2.
- **Absolute level:** lull at the summit no louder than the surf at the waterline minus 6 dB; gust peaks at most about 8 dB above that. Add a selftest: peak-to-RMS and the 1-second envelope depth (at least 10 dB between lull and gust), and spectral flatness is not tonal (no band more than about 10 dB above the local spectrum).
- **One shared wind field.** Create `World/Wind.swift` (or extend the existing band wind field) with a single `wind(position, time) -> (direction, strength)` used by audio, grass, trees, clouds, water, particles. The audio level for wind must be a function of that same strength at the player's position. If strength is low, the sound is low.
- **Visuals that show wind where it sounds strong (#22):** grass blades lean and ripple in gust waves that travel across the meadow (a visible moving band, speed matched to the gust); conifer crowns sway (a vertex bend in the shader proportional to height squared, using the wind field); cloud and mist drift direction matches the wind direction; a few windblown particles (seed fluff, spray off wave crests at the shore, dust on the summit) when strength is high; the lighthouse flag or any cloth, if there is one. On the summit the wind should be visibly stronger than on the beach, and the user should be able to look at the grass and say "a gust is arriving" about a second before they hear it (visual leads audio by distance/propagation: gust wave moves at about 8 to 14 m/s, so sound level and the visible front arrive together at the listener). Measure: a selftest that the audio gust envelope and the grass-bend amplitude at the player position are correlated (above 0.8) over 60 s.
- Frame cost for the sway and particles +0.3 ms at most.

### A4. The soft drone that grows inland (#22)
The user asked for "slow melodic droning very softly in the background as we leave the shore and progress into the island".
- A very quiet, slow, harmonic pad built from the game's own tone table (`ToneTable`: D, A, and the stone tones, as in the stone drone T55.2): a sustained root and fifth with a slowly drifting third or sixth, chord change every 25 to 50 s, long attack and release, subtle slow detune and chorus. Not a tune: a melody that is felt, one slow phrase of 3 to 5 notes over about two minutes.
- Level: silent on the beach (inside about 25 m of the shore), fades in over the next 60 m as `shoreDistance` grows, then plateaus at about -34 dB below the wind lull (quiet enough that listeners notice it only when it stops). Ducks under chimes and puzzle tones like the other ambience (use the existing ducking). Inside the Glass Wood use the glass tones' own key.
- It must stay consistent with the glyph/tone language (pillar 5): derive notes only from `ToneTable`, never arbitrary pitches. Selftest: all pad partials are within 5 cents of table tones or their octaves and fifths; level at 10 m, 60 m, 120 m shore distance.

### A5. Water sounds when the player interacts with water (#29)
- Wading: ankle-deep splash and slosh already exist as a grain layer. Add **entering** (first contact: a soft splash, scale by speed), **leaving** (drip tail), **knee-deep drag** (a continuous low wash while moving, scaled by depth and speed), and **stillness** (quiet lap against the legs). Different from stepping on wet sand.
- Whatever the "hard block" of #29 is (see G3), any water the player touches or triggers must make water sound: if the thing is a puzzle pool or a basin, give it filling, draining or trickling sounds that match its animation.
- Selftest: first-contact event fires once per entry, level scales with entry speed, wading layer silent when out of the water.

---

## G. Geometry and materials

### G1. Tree bases: straight into the ground, no footing collars (#19, #20)
**Cause.** F01's `Placement.skirt` adds a tapering footing and soil apron around every conifer trunk. In the frames it reads as a dark octagonal collar that is wider than the trunk, ends above the slope on the uphill side, and leaves a visible gap or step below the trunk. The user says the effect looks inverted and wants no bases: **trees go straight into the ground.**
- Remove the skirt and apron from tree trunks entirely. Instead extend the trunk mesh itself straight down (same cylinder, same bark material, same normals) from the highest ground under the trunk to **the lowest ground sample under the trunk's footprint minus 0.3 m**, so no gap can show on any slope. The terrain simply occludes the buried part. A very slight natural root swell is allowed only if it is part of the trunk surface (a gentle radius increase in the lowest 0.4 m with bark texture and no change in colour), never a separate dark slab.
- Same principle for **every upright prop** (lanterns, resonance stones, signposts, rocks that stand, pillars): the embedding is an extension of the prop's own base, same material, no flared plinth and no separate dark apron. **Lantern bases from F01 #8 still must read as embedded in the slope:** extend the lantern's footing straight down in the lantern's own stone, no flare outwards.
- Verify with a close-up from uphill and downhill of the same tree on a 30-degree slope at 0.5 m and 2 m (`tree-base-up`, `tree-base-down` views). Update the contact selftest: lowest sample of the buried part is below terrain at every footprint sample, and no visible mesh part is wider than the trunk by more than 5 %.
- Update PROPS.md and MATERIALS.md notes accordingly.

### G2. The toppled islet pillar (#25)
**Screenshot reading.** The fallen drum overlaps the standing base: the fallen piece's mesh pierces the base's side, the break surfaces on both parts are perfectly planar, and the cut looks "laser-sliced".
- **Placement that respects the base:** compute the fallen section's rest pose from its oriented bounding box: it must not intersect the standing base's OBB (separation distance at least 2 cm), rest on the ground or on the plinth with its lowest point touching (use `Placement.lay` against the plinth top and the terrain), and be rotated away from the stump as if it fell outward, with a plausible small yaw and a slight settle into the ground. Selftest: no vertex of the fallen piece lies inside the base mesh volume (point-in-convex-prism test) and the lowest vertex is within 2 cm of a supporting surface.
- **Rough break:** displace the break faces with fracture noise: a jagged, conchoidal or stepped fracture (domain-warped Worley with 2 to 3 octaves, amplitude 3 to 8 cm, a few shattered chips on the ground), and **match the stump's top profile to the fallen piece's broken end** (same noise, mirrored), so the two fit like a real break. Fresh broken faces are paler and rougher (no weathering on the newest fracture, a little dust), with edges chipped. A few fragments lie around.
- Apply the same rule to any other broken, snapped or missing element (the snapped dock board, any ruins).

### G3. The "hard block" at the water (#29)
**Screenshot reading** (position 4.7, 3.2, -3.4; feedback `20261025-134154`): the player looks down on a ring of cobbled stone with a smooth, saturated blue water surface whose border is a hard curved edge with a thin white line, almost a bowl cut out of the paving. It looks like a flat, hard-edged block of water, not water.
- Find what the object is (position is on the lighthouse-hill pad region; check `Layout`, the pools or basins, and the water material) and tell the user in INSPECT.md.
- Fix: water must meet stone with a soft shoreline: a wet-stone darkening band on the paving, a thin foam or meniscus line with irregular edge, refraction and depth tint that deepens gradually from the edge (not a flat blue), small ripples responding to the player's steps, shallow-water caustic hints. If it is a puzzle pool, give it a rim stone and keep the surface continuous with the world's water shader. See also A5 for sound.

### G4. Dock planks: less geometric (#32)
**Screenshot reading.** The planks have perfectly straight parallel edges, square ends, a regular gap, and concentric circular ring patterns on the face that look like a bullseye ripple instead of wood grain; nail holes are tidy octagons.
- **Edges and ends:** break up the straightness: per-board edge wobble (sawn, slightly wavy, 2 to 6 mm), ends cut at slightly off-square angles with splintered, chipped corners, uneven gaps (some boards touching, some 3 cm), occasional bent or lifted corners.
- **Grain:** replace concentric rings with flat-sawn board grain: long, nearly parallel cathedral (flame) figures that run with the board length, warped by low-frequency noise and interrupted by occasional knots (knots deflect the grain lines around them), plus a fine fibre streak and some raised grain where softer wood has weathered. No circles unless they are knots.
- **Nails:** square-cut or round-headed nails, slightly oblique, rust bleed streaks, some missing, pulled up, or sunk, not a regular octagon.
- Evidence: `dock-close` and a top-down 0.5 m view before/after.

---

## R. Rendering

### R1. Shimmer on fine detail (#23)
**Reading.** The frame is a 0.3 m overhead view of turf with bright patches (the sand showing through) and fine ripple detail. The user sees crawling on small features when moving and asks for "a different rendering to ensure these appear crisp and static".
**Diagnosis.** The renderer has no anti-aliasing for geometry or shader output beyond mip and band-limit logic (MSAA was rejected earlier; the shader band-limiting covers material functions but not threshold edges such as the patchy sand mask, grass blade tips, high-contrast speckle, specular on rippled normals). Sub-pixel features produce temporal aliasing.
**Plan.**
- Implement **temporal anti-aliasing (TAA)**: sub-pixel camera jitter (Halton 2,3, 8 samples), motion vectors (the world is static except wind-driven grass and trees, so camera reprojection from depth plus per-object motion for animated vertices is enough), history in HDR, neighbourhood colour clamping (variance clipping) to reject ghosting, a velocity-weighted blend factor, and a light sharpening pass (CAS) to restore crispness. Disable jitter in `--screenshot` mode unless `--taa` is given, so existing headless baselines stay comparable, and add a mode that renders N frames of a moving camera.
- Where the existing shaders compute per-pixel thresholds of high-contrast masks (sand patches in turf, speckle, scree edges), band-limit them with the `fpix` approach or use smoother transitions so TAA has less to resolve.
- If TAA is judged too costly or too risky for the pipeline, the minimum acceptable alternative is **SMAA 1x plus specular/normal-variance filtering (Toksvig) plus alpha-to-coverage for grass**, but do not skip the measurement below. Say which you chose and why.
- **Measure shimmer:** extend `--approach` or add `--shimmer`: render a 60-frame sequence with a slow camera pan (and a slow walk) over turf, sand, the dock, the cobble path, the masonry, the grass; per pixel temporal luminance variance (after removing the expected motion by comparing against a high-sample supersampled reference of the same frames) must drop by at least 60 % versus now. Report the table and keep the frames in `shots/f02/`.
- Budget: TAA +0.6 ms at 1600x900 (it replaces nothing, so say if it is higher); report the settled bench.
- Also fix the user's ghosting risk: test fast turns and the rotating beam (additive, moving) for ghosting.

### R2. Distant details "jump back" as the player walks (#26)
**Reading.** At position -39, 5, 140 the user looks along the island. The phrase "appear to jump back after so many steps towards them" suggests something at distance changes position discretely (not smoothly), breaking parallax. Candidate causes, check each:
1. **Distant LOD/impostor swaps** that change the silhouette or shift the apparent position (conifer far LODs, merged-per-cell LODs, the dithered cross-fade from R09 where a far level has a different pivot or shape).
2. **Terrain far-mesh or normal/height LOD** shifting a ridge by a few metres (a vertex snapping effect when the mesh grid changes spacing).
3. **A camera-relative or fixed-distance layer** (sky, distant island backdrop, the "horizon" clouds, haze billboard) that moves with the camera in a step, or that is re-centred by a quantised amount (for example snapping to a 10 m grid), so it appears to jump.
4. **Depth precision** at distance (z-fighting between layers) or a far-plane clip that pops.
**Plan.**
- Reproduce: render a sequence from position (-39, 5, 140) walking 0.5 m per frame toward the north for 40 m at 1600x900, crop on distant features (the lighthouse, ridge line, far trees), compute each tracked feature's screen position and size, compare against the pinhole-camera prediction (`x_screen = f * X/Z`), and flag any frame-to-frame deviation above 0.5 px of prediction. That finds the jump, and its cause.
- Fix each cause found (quantised layers must be continuous; LODs keep the same pivot, silhouette and size; terrain geomorphing so vertices slide between LODs instead of snapping).
- Keep the measurement as a permanent selftest (`--parallax`), with the largest deviation per feature in the done-note. This ties to the continuous-detail rule: nothing may change position or form suddenly.

---

## M. Movement

### M1. Camera follows the steps (#28)
**Reading.** Position (-0.5, 6.6, -83.2), looking at a stepped stone stair. The feet height uses the smooth terrain or the collider top, and the camera sits at `feet + 1.7 + bob`. The user feels no step-up: either the stair is not in the collision/height field (visual only) so the player glides through at ground height, or the eye height changes instantly in a way that reads as a teleport rather than a step.
**Plan.**
- Find out which: are the stairs meshes with colliders, are they part of the terrain height (`Terrain.height`), or visual only? Make **the ground the player walks on equal the visible stair surface** (one source of truth, the same rule as the T55.11 sampler-and-mesh fix). If stairs are inside the terrain height function, keep them smooth (small chamfer) so the player rises with each tread.
- Add **eye-height smoothing**: the feet position stays physical, the camera's vertical offset follows with a critically damped spring (about 0.08 to 0.12 s) so a 20 cm riser becomes a quick eased rise with a small bob impulse, and landing from a drop gets a tiny dip. Cap the lag so it never lags more than 15 cm behind the feet. Do not smooth horizontal movement.
- Footsteps: the step sound should trigger as the foot lands on each tread (existing logic) and a stair step should sound the same as a stone step.
- Selftest: walking up a 6-step staircase of 18 cm risers: the camera height is monotonic, no single frame jumps by more than 4 cm, and it settles within 0.3 s after the last riser. Audit all stairs and ledges on the island (list them in the done-note).

---

## Order of work
1. **G1, G2, M1** (visible faults introduced or left by F01, quick to verify).
2. **A2, A1, A3** (the audio the user has now complained about twice), then **A4, A5**.
3. **R2** (measure first, because the cause decides the fix), then **R1** (TAA, the largest item).
4. **G3, G4**.

## Questions that need the user (put in INSPECT.md; do not decide)
1. **Water edge (#29):** the builder identifies the object; does the user want it to stay as a feature once it looks like water?
2. **Drone:** one pad for the whole island, or different keys per area (shore, hill, Glass Wood)?
3. **TAA:** acceptable to add a temporal filter (slight softness on fast turns) in exchange for stable fine detail? The sharpening pass mitigates it.
4. Still open from before: the door interior, slip angle, conifers (stylised or needle-level), the ending.

## Stopping note
These notes are mostly defects and audio calibration, not art direction, so they are within the loop's scope. After F02, the same stopping rule applies: if the next round's suggestions are mostly art direction or would add complexity for invisible gains, hand back to the user.

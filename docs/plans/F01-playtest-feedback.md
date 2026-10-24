# F01: plan from the user's first playtest (17 notes, 2026-10-24)

Source: `Lanternwright --feedback` entries #1 to #17 (screenshots in `~/Library/Application Support/Lanternwright/feedback/`). The reviewer read all 17 notes and opened the screenshots for #1, #3, #5, #8, #12, #14, #16 and #17. The user played a build that had the lighthouse rework (they said "The lighthouse looks much better, thank you", #9). Everything else they found is below. **Read this file in full, triage it into TASKS.md (accept with an Accept line, or REJECT with a reason), then work it in the order given in "Order of work".** Same rules as always: before/after frames Read and compared, selftests and bots green, commit at each pausing point, INSPECT.md updated, `scripts/bundle.sh` at the end of the run, story ending left to the user.

## The user's notes, mapped to workstreams

| # | Note (short) | Workstream |
|---|---|---|
| 1 | Dock is too orderly, like vinyl flooring; should be chaotic, weathered, old | W2 |
| 2 | Dock section lying on stone should not sound hollow | W6 |
| 3 | Grass/sand interface shows clear pixel rendering | W1 |
| 4 | What makes the green surface green? Needs moss and low plants, finer ground detail | W1 |
| 5, 15 | Floating objects around trees ("pine cones", twigs) | W3 |
| 6 | Wave sound does not diminish as the player gets farther from the shore | W6 |
| 7 | A newly read page should open the journal on that page, not on the Notebook tab | W7 |
| 8 | Final approach to the lighthouse is unbelievably steep; lantern bases do not meet the slope | W5, W3 |
| 9 | "The lighthouse looks much better" | (keep it) |
| 10 | Movement around the lighthouse appears stuck; waves now sound like static white noise | W4, W6 |
| 11 | Let the player try the door and find it locked, or enter and find it abandoned | W4 |
| 12 | A beam of light is not visibly connected to anything | W4 |
| 13 | Idea: let the player slip on slopes that are too steep, to guide them | W5 |
| 14 | A rock is clearly a polygon; all surfaces need real-world texture | W3 |
| 16 | The causeway "feels like plastic blocks" | W3 |
| 17 | The islet pillars are plastic rectangles; every material must look natural and weathered, implying age | W0, W3 |

**The core lesson (applies to everything):** the reviewer and the builder have been judging a handful of named views. The user walks everywhere and looks at everything. Several large objects were never upgraded because no named view showed them: the causeway slabs and islet pillars are plain tan boxes; rocks are faceted icospheres with flat colour; the islet ground is a uniform green felt; pebbles are white low-poly gems. W3 starts with a **coverage audit** so this cannot happen again.

---

## W0. Shared toolkit: natural variation and weathering (do first; W1 to W3 depend on it)

**Problem.** The blocky "pixel" patterns in #3 and #5 (and the camouflage-like blocks on the ground in #16) are the lattice artefact of thresholded value noise, which has now been found at least four times (pits, flaking, path, now ground). Fixing it one material at a time is whack-a-mole. And "plastic" comes from surfaces that look *new*: nothing has a history.

**Plan.**
- W0.1 **Noise library audit and replacement.** List every use of `vnoise3` or a value-noise threshold in `Render/Shaders/*.swift` (terrain, sand, grass blend masks, dirt, path edges, wet-sand, pad masks). Provide in `Common.swift`: gradient (Perlin-style) noise with analytic or cheap derivatives; **rotated, offset octaves** (each octave rotated by a fixed matrix so lattice directions never line up); a **domain-warp** helper; **Worley** with F1/F2 and cell id; **ridged** and **billow** variants. Replace value-noise thresholds that feed *visible shapes* with these. Keep band-limiting (`fpix`) and the R09 continuous-detail rule.
- W0.2 **Height-blend and soft masks.** Blend materials by height values plus noise with a narrow transition, then add micro-scale break-up along every boundary (a boundary is never a clean smoothstep of a single noise). This is the grass-sand interface in #3.
- W0.3 **A shared weathering function** applied at the end of every material (per-material parameters): `weather(albedo, roughness, P, N, objectSeed, params)`. It adds, scaled by the material's age/exposure parameters:
  - **crevice grime and AO** where the height or curvature signal is low;
  - **water staining**: vertical streaks running down from ledges, sills, nail heads and horizontal joints;
  - **moss and lichen** biased to north-facing, low, damp and sheltered places, and into cracks;
  - **salt crust and tide-line darkening** near sea level (a band at y between -0.2 and +1.2 m);
  - **sun bleaching** on upward faces; **edge wear** (lighter, rounded) on convex edges; **rust** on iron with drips;
  - **chips, cracks and pits** with irregular, non-axis-aligned shapes.
- W0.4 **Per-object variation.** No two rocks, planks, posts, slabs or lanterns should look identical. Give every object a stable seed (from its instance index or position hash, through `ObjectUniforms` or a vertex colour channel), and let materials use it to offset the noise domain, tint and age parameters.
- W0.5 **Update `Controls`-style documentation**: a short `docs/MATERIALS.md` listing each material, its tiers (macro, meso, micro; see R09), its weathering parameters and which props use it.

**Accept.** A material test sheet (`--view material-sheet`, a flat gallery of every material on a sphere and on a slab under the same light) before and after; zero axis-aligned lattice shapes at 0.3 m, 1 m and 3 m on terrain, sand, dirt and the path (check with a `ground-close` set of views, see W1); frame budget +0.7 ms.

---

## W1. Ground and ground cover (notes #3, #4; helps #5, #15, #16, #17)

**Problem (from the screenshots).** At 0.3 m (#3, #5) the grass-sand and soil surfaces are big soft blocks, like a low-resolution image magnified (and in #5 the slope reads as dark pixel-noise gravel). Away from the path the ground is a smooth green, which the user rightly asks about: if it is green, something should be growing. The islet (#17) is a flat uniform green with no detail at all.

**Plan.**
- W1.1 Remove the lattice from the terrain material (W0.1) and re-grade the grass/sand/soil transition per W0.2. Add views `ground-grass`, `ground-sand`, `ground-edge`, `ground-slope`, each at 0.3 m looking down, and `ground-islet`.
- W1.2 **Make green mean plants.** Underneath the grass the ground albedo should be soil and duff (earthy brown-grey, only slightly green); the green comes from a layered **ground cover**:
  - **moss mats** (velvety, slightly brighter at the tips, a faint soft sheen, strongest in damp low places, on north faces, around rocks and tree bases, and along path edges);
  - **clover and low herbs** (small three-lobed leaf cards 4 to 12 cm, clumped);
  - **lichen patches** on rock and bare soil; **fine grass** (thin, curved blades) in a second species with a different height and hue; seed heads and the occasional tiny flower;
  - **leaf and needle litter** under trees (the conifer duff exists; extend it to a broader soft-edged area).
  Do the large scale in the terrain shader (mask by moisture proxy: low slope, low altitude, near water and path edges, shade) and the small scale as **instanced micro-vegetation within about 10 m**, thinned with dithered fade (R09). Do not create a hard radius.
- W1.3 **Grass blades vs the surface (note #4).** Make blades read as separate plants: darker, more saturated bases where they emerge, slight per-blade hue and height variance, thin tapered tips, some bent, some dead (straw) blades. The terrain beneath should be visibly different from the blade colour.
- W1.4 **The islet and every landmark pad** (the grass-free pad mask made some areas look like felt). Replace "no grass" with *appropriate ground*: a mossy, thin-grassed meadow with exposed stones, or worn flagstones where the design wants it. No landmark ground may be a flat uniform colour.

**Accept.** Before/after at 0.3 m, 1 m and 5 m on grass, sand, the interface, a slope and the islet (Read them): no blocks, visible plant structure, soft but irregular boundaries; the R09 `--approach` filmstrip on the meadow shows a gradual arrival of the plant detail; frame budget +0.5 ms.

---

## W2. The dock: weathered, chaotic wood (note #1; extends to every wooden object)

**Problem.** The dock reads as vinyl flooring: planks identical in width, length, spacing and colour, with perfectly straight edges, a repeated grain streak and symmetric nail holes.

**Plan.** Make it look like it has stood in salt air for decades:
- **Geometry irregularity**: plank widths 0.14 to 0.26 m (per plank), uneven gaps (some 5 mm, some 30 mm), slight rotation and height offsets per plank, **cupping and warping** (the top surface bows across and along the plank), edges rounded and chipped by wear, some ends split or cut at an angle; one or two **missing or broken planks** (a dark gap through which the stringers and water show); a **replaced plank** that is newer and paler; visible **stringers and cross-beams** underneath; sagging between supports.
- **Material**: grain as a *growth-ring model* (distance from a virtual trunk axis, domain-warped, with cathedral figures and **knots** that swirl the grain around them), long cracks (checks) following the grain and opening at the ends, **silvered grey** weathering on the tops, **darker wet and mossy** lower edges and low spots, **salt crust** and bleached patches, **rust streaks** running from nail heads, nail heads of different sizes and some bent or missing, worn **walking line** down the middle, gouges.
- **Posts and piles**: split tops, rope that is frayed and stained, barnacle and weed bands, rust-stained iron cleats, a lean.
- Reuse the same wood material (with per-use parameters) on the lighthouse door, benches, rails, any other timber.

**Accept.** Views `dock-close` (at 1 m, looking down), `dock-side` (low, from the beach) and `dock-under` (from the water below the deck): the planks are individually distinguishable by width, tone, grain, wear and gap; no repeated pattern visible; it reads as old and weathered. Frame budget +0.3 ms. A selftest that planks are deterministic from the seed.

---

## W3. Every object on the island: audit, then upgrade (notes #5, #8, #14, #15, #16, #17)

**W3.1 Coverage audit (first).** Write a tool (`--audit-props`) that lists every scene item and instance group with its material id, vertex count, bounding size and whether it uses the flat `standard` material with a constant colour. Flag any item whose projected size would exceed about 0.5% of a 1600x900 frame at 5 m. Add `--view prop-gallery`: a contact sheet of every distinct prop type at 2 m under the same light. Put the audit output in `docs/PROPS.md`. Treat any flagged flat prop as a defect. **Known flagged items (from the screenshots):** causeway slabs (#16), islet pillars and the lens base (#17), rocks (#14), pebbles and shells and driftwood (#16, #5), the pine cones and twigs (#5, #15), the lantern bases (#8).

**W3.2 Rocks (#14).** The rock is a low-poly icosphere. Rebuild: a subdivided mesh (3 or more levels) displaced by 2 to 3 octaves of ridged/billow noise plus a few planar **fracture cuts** (so it has facets that are *natural*, with chipped edges), rounded by a blend between smooth and flat normals; stone material from W0 with strata, lichen and moss (north and low), a dark wet base, salt bleaching near the sea; **half-buried** with soil and grass tucked at the base (a skirt of ground-cover cards and a darker contact patch); per-rock variation; clusters of a large rock with smaller ones. Pebbles and shells: rounded meshes with material, not faceted gems.

**W3.3 Causeway slabs (#16).** Replace flat boxes with weathered dressed stone: uneven tops (gentle dishing), chipped edges, per-slab tilt and offset, visible gaps with water, **barnacle and weed bands** at the waterline, algae on the wet surface (slick, darker, greener), salt crust above, lichen, cracks, and slight sinking at one end. As they rise from the sea during the puzzle, they should *drip*: wet darkening that fades as they dry (reuse the tide-line logic).

**W3.4 Islet (#17).** The five pillars are plain tan boxes: make them weathered standing stones (taper, lean, chiselled faces with the glyph language, lichen and moss, a fallen or broken one, a worn base with a stone footing), the lens base a real stepped stone or iron-and-glass ring with age and a patina, the ground per W1.4.

**W3.5 Embedding rule (#8 lanterns; also stones, rocks, pillars, plinths, posts).** Add a placement helper `Placement.embed(center, footprintRadius, kind)` that samples the terrain over the footprint, puts the object's pivot at the **highest** ground under it and gives it a **foundation skirt** (a tapering stone/earth/roots footing) extending down to the **lowest** sample plus about 0.15 m, with a soil mound or tuft ring blending it into the slope. Props stay **vertical** (the user's words); their bases extend downhill. Apply to the stone lanterns (bodies and the footing), resonance stones, rocks, pillars, signposts, tree trunks (root flare that wraps the slope) and the lighthouse plinth. Selftest: for every placed prop, the gap between its lowest vertex and the terrain under its footprint is within a small tolerance (embedded 0 to 15 cm, never floating) at every footprint sample.

**W3.6 Floating cones and twigs (#5, #15).** Pine cones and twigs hover: they are placed at the sampled ground height of their centre, with their own pivot at the middle of the mesh, so on a slope the downhill side is airborne and the cones sit *on top* of the ground. Fix with the same embed rule (pivot at the base, rotate to lie flat on the slope, sink 20 to 30%), scale cones to a believable size (about 5 to 9 cm), put twigs *on* the ground at the slope angle, and cluster them under trees. Add the selftest above for **all** clutter (pebbles, shells, driftwood, cones, twigs, flowers, litter). Check at a hillside: no object visibly hovers.

**Accept.** `docs/PROPS.md` shows zero flat large props; the `prop-gallery` sheet Read before/after; hillside, causeway, islet, rock and lantern close-ups Read before/after; the contact selftest passes for every placed object; frame budget +0.6 ms.

---

## W4. The lighthouse: door, beam, collision (notes #10, #11, #12)

**W4.1 Collision (#10, "movement around the lighthouse appears stuck").** The collider was refitted to the wall and the plinth steps made walkable (T58.8); the user now gets stuck. Reproduce with a bot that circles the tower at radii 5.0, 5.5, 6.0, 7.0 in both directions at walk and run speed, and walks into the plinth steps from several angles. Likely causes: step height (`maxStep` 0.5 m) against the plinth riser heights; the push-out and `canMove` slope test fighting each other at the curved wall (the code tries "full move, then axis moves"); the vertical smoothing; the collider being a polygon or a circle not matching the stepped plinth. Fix: make wall collision a proper **iterative slide** (project the velocity onto the contact tangent, up to 3 iterations, with a small skin distance), allow stepping onto each plinth tier (tier height within `maxStep`; add ramps or smaller steps if needed), and add a **stuck detector** in the bots (no progress for more than 1 s while input is held is a failure). Include this in the permanent bot suite for all landmark colliders.

**W4.2 The door (#11).** The user offered two options: the player tries the door and finds it locked, or enters and finds it abandoned. **Recommendation: do both, in two phases** (confirm Phase 2 with the user before building it):
- Phase 1 (do now): the door is an interactable. Clicking it plays a muted latch rattle and a soft low thump of the weight against the bolt, and shows a short banner such as *"Locked. The keeper took the key with her."* (use the existing banner system; keep it one line and in the keeper's voice). Add dust motes in the doorway crack and a faint draught sound. No new puzzle.
- Phase 2 (ask the user first): after the island puzzle is solved (lighthouse lit), the door opens onto a short abandoned interior: a round stone room, a spiral stair rising to a sealed hatch, a keeper's table with the fourth journal page or an object that ties to Oren, dust, cobwebs, old lamp oil stains. It needs an interior lighting solution (sun shafts through the door and windows, a few small local glows). Treat as its own mini-milestone.
- Whatever the choice, the door must not look like a prop: its planks, strap hinges, ring and arch are already good; add a worn threshold and a keyhole.

**W4.3 The beam (#12, "does not appear connected to anything").** In the screenshot (#12) a bright vertical column of light stands over the sea with no visible source; it reads as a floating rectangle. The beams were built for the old lantern room. Find out what this is (the sweeping lighthouse beam, or the sun glint path, or the puzzle beams) and fix the connection: the lighthouse beams must **start at the lens inside the lantern room** (aligned to the *new* lantern room geometry), taper from a bright core, sweep with a visible **lens flare and glow at the source**, and be volumetrically visible along their whole length (haze scattering in the air), not only where they hit the sea; fade with distance; cast a faint light patch where they meet water or land. The sun glint on the water must not be mistaken for a beam (if it is the glint, make it look like a glint: broken, shimmering, wider at the horizon). Add views `beam-source` (from the gallery), `beam-sea`, and a night variant, and check that from the dock the beam can be traced to the lantern room.

**Accept.** The collider bots pass (including a long circling run with no stuck events); the door gives feedback; screenshots show a beam attached to the lantern room from three vantage points; INSPECT.md asks the user which door option they want next.

---

## W5. Slopes and locomotion (notes #8, #13)

**Problem.** The final approach is far too steep (the walkable limit is `maxSlope` 1.19, about 50 degrees, which is a climbing wall). The user also suggests letting the player slip on slopes that are too steep to guide them along paths ("I don't know if this is needed yet").

**Plan.**
- W5.1 **Slope audit**: a tool that walks the lantern path and prints the grade per 10 m segment (and the steepest grade anywhere on the intended route), plus a map image of grades. Report it. Target: the lantern path never steeper than about 25 degrees (grade 0.47) for any 10 m stretch.
- W5.2 **Re-grade the path.** If the straight polyline exceeds the target, route the path with switchbacks (a small A* or a graded descent over the heightfield from waypoint to waypoint, minimising slope), keeping the landmark positions and pads in `Layout.swift` unchanged, and **carve the terrain** along the route (a cut-and-fill bench a few metres wide, blended), so the path is genuinely walkable. Regenerate the lantern positions along the new route. The final approach to the lighthouse door must be gentle.
- W5.3 **Comfortable and difficult slopes.** Lower the hard `maxSlope` to about 0.84 (40 degrees). Taper the walking speed smoothly from about 25 degrees (full) to about 38 degrees (about 40%); keep the existing slope-aware pace as the base. This alone gives the guidance effect the user describes without a gimmick.
- W5.4 **Optional soft slip (user's idea; default OFF).** Beyond about 40 degrees the player slides gently downhill with a soft scrape sound until they reach a gentler grade (never any damage, never a trap, no inertia beyond a metre or two). Implement it behind a setting so the user can try it and say yes or no; ask in INSPECT.md. It must respect pillar 4 (unhurried, no fail state): nothing is ever lost.
- W5.5 Bots: walk the whole route (dock to lighthouse and back to the causeway) and assert no segment forces the speed below the target or triggers a stuck event.

**Accept.** The audit report before and after; a grade map image; the bot route completes; screenshots of the final approach look like a walkable hill, not a wall.

---

## W6. Audio: hollowness, surf, wind (notes #2, #6, #10)

**W6.1 Dock hollowness from what is under the planks (#2).** `Scene.surface` returns `.wood` for any point on the dock strip above the terrain, including the landward planks that rest on the beach. Compute **clearance** = plank top minus the ground below (terrain or water surface). Pass a continuous `hollowness = smoothstep(0.15, 0.8, clearance)` through `StepMix` to the footstep recipes: at about zero clearance the body resonance gain and decay drop to a short dull **thud** (solid wood on stone, a little scuff of sand), growing to the full hollow cavity and slow decay over open water. Keep the per-plank pitch, and make planks over the water the only ones with the cavity boom. Selftest: spectral low-band energy and decay increase monotonically with clearance; the shore-end planks are measurably less hollow than the seaward planks.

**W6.2 Surf must fall with distance (#6).** The code uses `surfGain = 0.7 / (1 + d/25) + ...` with `d = shoreDistance(..., maxRadius: 160)`. Two flaws: the falloff is gentle (still about 0.1 at 160 m) and `d` stops at 160 m, so most of the island sits at the same plateau level. Replace with a physical model: the sea is a **line source**; sum the contribution of the coastline seen from the player (use the existing 24 rays, weight each by an inverse-distance law, steeper than 1/d: about 1/(1+(d/12)^2)), add **air absorption** (low-pass cutoff falls with distance: about 6 kHz on the beach to about 300 Hz at 150 m, so distant surf is a low rumble, never a hiss), a **terrain occlusion** term that already exists (keep it), and extend the search radius to cover the whole island (to 400 m) so the value really goes to near-silent inland and on the summit except for a slow low swell. Pan toward the strongest coast.
**W6.3 "Static white noise" (#10).** At the summit the user hears static, not waves. Likely the swell modulation is being lost (surf contribution at near-zero gain with the muffle filter fully closed, so what remains is the wind noise and the fizz) or the wind at altitude is a flat noise. Measure it: synthesize the ambience at the beach, mid-slope, summit and the plinth and report per position: RMS of surf vs wind, spectral centroid, and **modulation depth** of the swell in the 0.05 to 0.3 Hz range. Requirements: surf at any audible level keeps clear slow swells (depth above a threshold, 7 to 14 s periods; modulation depth *increases* with distance as it becomes a slow rumble); the wind at altitude is band-shaped (a low whistle and gusts with moving formant-like bands and slow level changes), not broadband static. Add these as selftests with fixed seeds. Write the per-position table into the done-note.
**W6.4** Keep everything inside the audio-thread rules (no allocation or locks in the render path).

**Accept.** Tests above pass; the user's two complaints are addressed in INSPECT.md with the exact walking route to hear them (shore to ridge to summit to plinth).

---

## W7. UI: journal opens on the page you just read (note #7)

When the player reads a page (clicking it in the world or finding it), the journal opens **on the Pages tab, on that page**, even if the Notebook tab was last open. Plain `J` can reopen on the last used tab. Where: `Game.swift` (where `journal.isOpen = true` is set when a page is picked up) should set `journal.tab = .pages` and `journal.current = <that page's index>`. Selftest: open the Notebook, then read a new page, assert tab and page. Also check that pressing J afterwards returns to the page just read, and that Esc and J close it as today.

---

## Order of work

1. **Quick correctness fixes (P0)**: W7 (journal tab), W3.6 (floating cones and twigs) with its contact selftest, W3.5 (embed rule for lanterns and other props), W4.1 (stuck around the lighthouse) with the circling bot, W6.2 and W6.3 (surf distance and the static-noise measurement), W6.1 (dock clearance sound).
2. **Foundation**: W0 (noise, height-blend, weathering, per-object seeds).
3. **Visual realism**: W2 (dock), W1 (ground and cover), then W3.1 to W3.4 (audit, rocks, causeway, islet).
4. **Guidance and structure**: W5 (slopes, re-grade, taper), W4.3 (beam), W4.2 phase 1 (locked door).
5. **Needs the user**: W4.2 phase 2 (interior), W5.4 (slip). Put the questions in INSPECT.md.

Fold R09 (continuous detail) and R07 (door seams and similar) into these where they overlap; R09 is the standard every new detail must meet.

## Questions for the user (put them in INSPECT.md, do not decide)

1. Door: is the locked door enough, or build the abandoned interior (Phase 2) after the puzzle is solved?
2. Slip on slopes: try it (setting default off)? What angle feels right?
3. Conifers: stylised or needle-level (still open from before).
4. Ending of the story (still open).

## Process notes for the builder

- Judge by **walking-distance views**, not only the named ones: add the new views listed above and run `--audit-props`.
- The user plays `Lanternwright.app`. Run `scripts/bundle.sh` at the end of the run and report the bundle's time and commit.
- Every change should be checked at 0.3 m, 1 m, 5 m and 30 m, because the user lies close to things.

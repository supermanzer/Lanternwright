# G10: graphics architecture audit

## Outcome (builder A, 2026-10-29; details and numbers in `docs/TASKS.md` under G10 and in `docs/shots/*-final.txt`)

**Status: NOT closed, so no `g10-done` tag.** Three items are open: G10.4.2 (never started, see below) and G10.G.2 / G10.G.3 (builder B's grass stream; G10.G.1 is done and tagged `g10-g1`). Everything else is done, measured with no action, or dropped. Tags on `main`: `g10-s0`, `g10-s1`, `g10-g1`, `g10-s2`, `g10-s3`, `g10-s4`.

**Done.** Stream 0 (G10.0.1 pass timer, 0.2 shimmer attribution, 0.3 banding probe). Stream 1 (1.1 `RenderTargets`, 1.2 passes extracted, 1.3 uniforms are values, 1.4 shader split, 1.5 tools green; 27 frames byte-identical). G10.2.0 bark/trunk band-limit (reviewer order 1). G10.2.2 the shared `thin_coverage` helper (the rest of 2.2 is "measured ceiling", below). G10.2.3 output dither. G10.2.1 camera-motion velocity buffer. G10.3.5 terrain-shader skips (opaque + sky -17 to -31 % at 2560x1440 on island views). G10.3.9 margin cue. G10.4.1 MetalFX temporal upscaling AS AN OPTION (`--render-scale`, pause-menu setting). G10.G.1 grass compute culling (B).

**Measured, no action** (each recorded with its numbers): G10.2.1 animated-vertex velocity (grass tips move <= 1.5 px/frame at 5 m, trees < 0.2 px; MetalFX is not the default), G10.2.2 thin tree geometry (branches change tree edge crawl +-2 %), G10.2.4 water/glass specular AA, G10.2.5 shadow seams, G10.2.6 tree LOD dither (<= 5 % of the edge crawl), G10.3.1 shadow cascade cache (ceiling 0 to 0.4 ms), G10.3.2 the scene copy (no gain, reverted), G10.3.4 CPU encode (0.2 ms), G10.3.6 / 3.7 / 3.8 the region consumers (measured ceilings), G10.4.1's DEFAULT scale (0.75 is not 25 % faster and loses detail: default stays 1.0).

**Dropped.** G10.3.3 as a task of stream 3 (it is stream G's G.1, done). The plan's "grass first" and "30 % better on grass and trees" (grass is about 1 % of the crawl).

**Not done.** G10.4.2 "spend the headroom": there is no headroom to spend while MetalFX is not the default and the pass-ms tables show no stream-3 saving large enough to buy detail; revisit only if the user asks for more distant grass or a larger near cascade. G10.G.2 chunked fade and G10.G.3 corridor-bounded chunks: builder B's.

**Before / after (stream-0 baselines against main at tag `g10-s2`).**
| Pass ms at 2560x1440, TAA, frame / opaque+sky | before | after |
|---|---|---|
| varrow dock | 9.51 / 5.62 | 8.37 / 4.51 |
| varrow overview | 9.44 / 5.56 | 7.54 / 3.76 |
| varrow shore | 9.29 / 5.60 | 9.21 / 4.81 |
| varrow summit | 10.32 / 6.95 | 9.49 / 6.26 |
| glass wood overview | 8.26 / 5.10 | 7.05 / 3.56 |
| glass wood court | 7.25 / 5.02 | 6.59 / 4.11 |

Banding, longest identical run of rows in the worst sky strip (Glass Wood night): 275 -> 41; flat share 67.7 -> 46.2 %. Slow-step shimmer, energy per pixel-frame (surface / edge): woods 0.0486 / 1.705 -> 0.0279 / 1.693 (surface -43 %, the bark band-limit); grove, shore, crystal within +-12 % (the surface rises are the dither's own grain: `LW_DITHER=0` removes them, edge unaffected); dock edge +7 %, traced by bisection to F04 W1 (the per-pixel waterline, commit 3c4623f: dock raw edge 34.1 -> 36.9 on that commit alone; the film's fade width changes it by < 2 %), so it is a deliberate image change at the dock's waterline, not a regression to fix.


Owner: builder A, after F03. User request (2026-10-26): "I still notice shimmering and odd behaviors that I assume are aliasing related. Given how many features we have added piece by piece, perform an architectural review of the entire graphics system. Identify ways to modularize it and make it more efficient. If you can find ways to improve the quality of the fine detail as well, that would be appreciated. Go ahead and make the changes you find."

Rules for this plan: **measure first** (stream 0), every change is judged by numbers from the tools that already exist (`--shimmer`, `--parallax`, `--approach`, `--bench`) plus the new per-pass timer, and by frames Read before and after. A change that cannot show a gain is reverted, not kept "because it is cleaner". A change that alters the look says so in INSPECT.md.

## What the reviewer found (from reading the code; each is a claim to verify, not a fact)

Size: Render/ is about 4.5k lines of Swift plus 2.7k of MSL in strings. 3.4 to 5.3 ms/frame at 2560x1440 is fast, so **the audit is mostly about quality and structure, not about rescuing frame rate.**

**Structure**
- S1. `Renderer` is one class with about 100 stored properties (every pipeline, every texture, TAA state, bloom chain, AO, eye adaptation, wind, clock) and `encode()` is a single ~300-line function that opens and closes about 14 encoders inline (shadow x3, opaque, scene-copy blit, water + glass + mist, AO copy blit + 3 passes, TAA 2 passes, beams, god rays, bloom chain, composite). Adding the last five features each grew it. Nothing states which pass reads or writes which texture, so ordering bugs show up as artifacts: F03 #47 (the mist drawn with a crystal tree's vertices, a ghost in the sky) is exactly that kind of leaked state between passes.
- S2. Per-frame state is a global mutable `frame: FrameUniforms` that passes patch in place (`f.sunViewProj = matrix` inside the shadow loop, `frame.casTexel.w = ...` set in `updateFrame` and read by AO). Any pass can break the next one.
- S3. The shaders are Swift string literals joined into one library; `Lit.swift` is an uber-shader that branches on a material id (`mid == 8` copper roof...) and runs the bump/AO/noise for every material inside one function. Hard to reason about cost and aliasing per material.
- S4. Render targets are created in one function with no lifetimes; the HDR scene is copied twice per frame (`sceneCopy` for water, again for AO) at full resolution.
- S5. Debug and measurement code (Shimmer, Parallax, Approach, Audit, SlopeAudit) lives beside the renderer; good tools, but they reach into renderer internals, which makes refactoring risky. They are the safety net for it: keep them working at every step.

**Aliasing and "odd behaviours" (why it still shimmers)**
- A1. **TAA assumes a static world.** Its motion vector is reconstructed from depth and the camera matrices only. Since F02 A3/T66.6 the grass, conifer crowns, clouds and water move with the wind, and LOD cross-fades are dithered per frame. None of that has a velocity, so on every moving pixel the history is reprojected to the wrong place and then clamped: which is the definition of ghosting plus shimmer. The F02 `--shimmer` metric used a static scene, so it could not see this.
- A2. **Sub-pixel geometry.** Grass blades are 1.6 to 2.4 cm wide. At 1600 px across a ~60 degree view one pixel is about 1.3 mm per metre of distance, so a blade falls under one pixel beyond ~15 m, and is rasterised as a coin-flip of coverage: TAA cannot fix coverage that changes sign frame to frame (variance clipping throws the history away). The same applies to needle cards, ropes, railings, cleats, and the thin crystal edges. The shaders band-limit *textures* by pixel footprint (good, R09) but there is no equivalent for *geometry*.
- A3. **No dither before the 8-bit output.** `Post.swift` has no dither or noise; the output is `bgra8Unorm_srgb`. Smooth dusk gradients (the sky above the horizon, fog, the beam) will band, and banding that shifts under TAA looks like crawling.
- A4. **Shadow cascades are re-rendered with no blend verification**: near (14 m), mid (70 m), far (340 m radius, 4096). Texel snapping is correct (`fitCascade` snaps in light space), but the seams between cascades and the 16-tap PCF kernel at the near/mid boundary have never been measured for flicker while walking. Unknown, so measure.
- A5. **Specular and normal aliasing** is handled by the Toksvig-style roughness bias on props, but the water has its own scheme (footprint fade, Water.swift), the grass uses the ordinary lit path with a per-vertex normal, and the glass uses a fixed roughness (`a2 = 0.0064`): sparkles on glass and water crests under motion are the likeliest remaining specular shimmer.
- A6. **Render scale below 1 is a plain bilinear stretch** by the MTKView (`renderScale` in GameView). It blurs everything, and it happens after the TAA, so the TAA's sharpness is lost. If a user has to lower the scale for speed they get the worst of both.

**Efficiency**
- E1. **Grass: 74,000 instances per frame** (grid 272 x 272, `grassCell` 0.31, radius 42 m), each running about ten noise evaluations in the vertex shader before most of them are rejected. Most of the field is invisible or thinned to nothing (density, keep, distance thinning). A compute pass that tests each *cell chunk* once and emits only the visible blades through an indirect draw would cut the vertex work by an estimated 5 to 10 times and removes the grid-recentring work from the vertex stage. (Estimate: measure with the pass timer before and after.)
- E2. **Shadow caching.** The 340 m far cascade only changes if the sun moves (it does not in play): render it once and keep it. The mid cascade changes only when its snapped centre changes (every 6.8 cm): reuse it between snaps. Only the near cascade needs rendering most frames.
- E3. **Two full-resolution blits** (S4): the scene copy for refraction can be skipped when no refractive object or water is in the frustum (the water covers the sea, which is most views, but not the Glass Wood interior or views inland), and the AO copy can be replaced by sampling the existing copy.
- E4. **Pass timing is unknown.** The bench gives total ms per view. There is no per-pass GPU time, so we cannot say whether AO, TAA, water or shadows dominates. Apple GPUs can timestamp each encoder (`MTLCounterSampleBuffer`, stage-boundary sampling). Do this first.
- E5. **Upscaling.** MetalFX (system framework, no dependency, available in the Command Line Tools SDK) offers a temporal upscaler that takes depth, a motion vector and the jitter, and gives better quality at a render scale of 0.67 to 0.77 than our TAA at 1.0. It needs A1's velocity buffer. This is the "higher fine-detail quality" lever with the best expected return, and it also gives headroom for the cost of E1.
- E6. **CPU side:** the scene is a flat array of items culled every frame (`item.hidden`, `item.refractive`, sun frustum) with one draw per item. Measure CPU encode time per frame (add to the pass timer). If it is above 1 ms, batch static props by material into argument-buffer-indexed draws or an indirect command buffer; if not, leave it alone.

## Streams and tasks (builder A, in this order)

Task ids are G10.<stream>.<n>. Each has an Accept line; "frames" means before/after PNGs Read and compared.

### Stream 0: measure (no behaviour change)
- **G10.0.1 Per-pass GPU timer.** `MTLCounterSampleBuffer` timestamps at the start and end of each encoder, collected a frame late (like the eye-adaptation readback), printed by `--bench` as a table (pass, ms) and optionally in the F-key feedback context (`pass ms: shadow 0.4, opaque 1.9 ...`). Fall back silently where the device does not support stage-boundary sampling. Files: new `Render/PassTimer.swift`, small hooks in `Renderer.encode`. Accept: the table sums to within 10% of the existing per-frame figure on all four bench views.
- **G10.0.2 Shimmer attribution.** Extend `--shimmer` with a *moving* world (wind on, game clock advancing, camera walking) and a per-layer breakdown: render the same walk with one layer disabled at a time (grass, trees, water, glass, props, sky, shadows) and report the flicker score each layer is responsible for, ranked. Metric stays the motion-compensated one from F02. Accept: a ranked table printed for the five standard scenes; commit it as `docs/shots/shimmer-baseline.txt`. **This table decides the order of streams 2 to 4: if it contradicts the order below, re-order and say why in TASKS.md.**
- **G10.0.3 Banding probe.** Render the sky/dusk views, take the final 8-bit image, and report the count of distinct levels along a vertical gradient strip and the max step. Accept: number recorded as the baseline for G10.2.3.

### Stream 1: modularise the frame (behaviour-preserving)
Target shape: `Renderer` keeps device, queue, scenes, options and a list of passes; each pass is a small type with `init(renderer)`, `encode(context)`; a `FrameContext` carries the command buffer, the (immutable per pass) `FrameUniforms` copy, the camera, the targets and the timer. Passes declare what they read and write (documentation plus a debug-build assertion that no pass reads a texture that has not been written this frame).
- **G10.1.1 `RenderTargets`.** Move `ensureTargets` and every texture into a struct with named members and sizes; no behaviour change. Accept: bench within 2%, frames pixel-identical.
- **G10.1.2 Extract the passes** one per commit, in this order: Shadow (cascades as data, which prepares E2), Opaque+Sky, Water+Glass+Mist (this is where #47's leaked vertex binding came from: give each draw its own explicit bindings), AO, TAA, Beams, GodRays+Bloom, Composite. After each: `--selftest` green and frames pixel-identical (compare PNG bytes; they must be equal, not "close"). Accept: `Renderer.encode` is under 60 lines, a list of passes.
- **G10.1.3 Frame uniforms are values.** Replace the in-place patching (`f.sunViewProj = matrix`) with a copy per pass. Accept: no pass mutates `renderer.frame`.
- **G10.1.4 Shader organisation.** Split `Lit.swift` by concern (ground, props, foliage) into separate functions called from a thin dispatcher, keeping one pipeline. No `.metal` files (hard rule). Accept: pixel-identical frames, selftest green, compile time not worse.
- **G10.1.5 Tools stay green.** After the refactor `--shimmer`, `--parallax`, `--approach`, `--audit` and `--slope-audit` run and give the same numbers as before it (record both). Accept: numbers equal within noise.

### Stream 2: de-alias (the user's actual complaint). Order set by G10.0.2
- **G10.2.1 Velocity buffer.** Add an RG16Float velocity attachment to the opaque pass (and glass/water as the TAA already uses their depth). Static geometry writes the camera-only vector; every vertex-animated shader (grass, conifer crowns and needle cards, crystal sway, water, anything driven by the wind clock) recomputes its *previous* position with the previous clock and previous matrices and writes the true vector. TAA uses the buffer instead of depth reprojection. Accept: on a windy walk, `--shimmer` moving-world score improves on the grass and tree layers by at least 30%, and no new ghosting in a pan across the Glass Wood (frames from 3 consecutive steps).
- **G10.2.2 Geometry coverage for thin things.** Grass first (stream G if B has it by then; otherwise a minimal shader change): clamp each blade's rendered width to at least one pixel footprint at its distance and scale its alpha/brightness by the true coverage (width over footprint), so a sub-pixel blade becomes a faint, stable tint instead of a flickering speck. The same rule for needle cards and for ropes/rails (a `minFootprint` in the vertex stage). Accept: the grass layer's flicker score drops by 50% or more; the look at 5 m is unchanged (frames at 1, 5, 15, 40 m).
- **G10.2.3 Output dither.** Add triangular-PDF blue-noise (or interleaved gradient noise) dither of +-1 LSB in the composite just before the 8-bit write, constant in screen space but animated per frame so TAA-style temporal averaging in the eye hides it. Accept: the G10.0.3 probe shows more distinct levels and no visible bands in the dusk frame; no visible grain at 100% zoom.
- **G10.2.4 Specular/geometric AA for glass and water.** Widen the roughness by the normal's screen-space variance (`dfdx/dfdy` of the normal, Kaplanyan/Toksvig-style) in the crystal and water shaders, and clamp the glass roughness floor. Accept: the glass layer's flicker score drops; highlights keep their shape at 3 m.
- **G10.2.5 Shadow seams.** With the attribution table in hand: if the shadow layer scores high, blend the cascades over the last 10% of each radius (a fade, not a switch) and add the receiver-plane depth bias. If it does not, record "measured, no action" with the number.
- **G10.2.6 LOD dither review.** The tree LOD cross-fade uses a per-frame varying dither that the TAA averages. With the velocity buffer in place check that the cross-fade is now stable on a slow approach (`--approach` contact sheets); if not, switch to a fixed-pattern dither with a time-averaged blend.

### Stream 3: efficiency (each with a before/after number from G10.0.1)
- **G10.3.1 Shadow cascade cache.** Far cascade rendered once per sun change; mid cascade only when its snapped centre or the caster set changes; near every frame. Accept: shadow pass time down at least 40% on the bench views, frames pixel-identical.
- **G10.3.2 Skip the scene copy** when the frustum holds no water or refractive item (cull test already available), and drop the second full-res AO copy. Accept: the copy passes vanish from the timer in inland views; pixel-identical.
- **G10.3.3 Grass cull on the GPU** (this is stream G below: do not start it before builder B has handed the grass over).
- **G10.3.4 CPU encode time.** Add it to the timer; act only if above 1 ms (see E6).
- **G10.3.5 Overdraw check.** Draw a debug overdraw view for the opaque pass at four views; large overdraw in props near the lighthouse or in the glass forest gets a front-to-back sort of the opaque items (cheap) or an early-Z prepass for the heaviest materials. Act only on a measured gain.

- **G10.3.6 Pinned LOD from the reachable region** (needs B's M10.6 API, `ReachableRegion.minDistance` per prop). A prop (tree, rock, lantern, pillar) whose nearest possible eye position is farther than its top LOD's distance gets that LOD forever: no per-frame choice, no dither cross-fade, no needle-level instances built for it. Accept: object count in the needle level drops by the measured share; no visible change from any corridor position (contact sheets from three trail points); one fewer dithered pipeline use in the opaque pass.
- **G10.3.7 Shadow bounds from the region.** Bound the far cascade by the region plus the view range instead of the 340 m sphere; this shrinks `shadowRadius` and so sharpens every texel. Accept: far-cascade texel size reported before/after; shadows from the lighthouse and the stones at 100 m are visibly crisper (frames); no light leaks at the edge.
- **G10.3.8 Terrain and grass bounds.** Terrain mesh density reduced where `region.distance(to:)` is large (no one reaches it, only sees it from afar); grass chunks (stream G) outside the region plus view range are skipped. Accept: triangle count and pass times before/after; frames from the edge corridors show no seam.
- **G10.3.9 Margin cue.** Read `Player.marginPressure` (B, M10.4): fog density up by up to 15% and a gentle low-pass on the ambience bed as it rises, smoothed over 1 s. Accept: nothing at pressure 0; frames at pressure 1 look like dusk thickening, not like a wall.

### Stream 4: quality headroom (only after streams 2 and 3 land)
- **G10.4.1 MetalFX temporal upscaling** (`MTLFXTemporalScaler`): needs depth, velocity (G10.2.1), the jitter and exposure. Render at 0.75 of the drawable (a setting; 1.0 = native TAA as now) and upscale to the drawable. Replace the bilinear stretch. Place it where the TAA resolve is now (it replaces TAA when active; the native TAA stays as the fallback). Accept: at 0.75 scale the image is at least as sharp as native-resolution TAA on the contact sheets (measure with the existing `detail` metric from `Shimmer`), frame time at least 25% lower than native, no new artifacts around the beams (beams stay after the resolve, as in F02). If the scaler is unavailable on the device, the setting is greyed out.
- **G10.4.2 Spend the headroom on detail** only where the shimmer table says the fix was costly: e.g. restore grass density at distance, or a larger near cascade. Accept: each spend has a measured cost and a before/after frame.

### Stream G: grass rewrite (hand to builder B after M10.6; see X00)
- **G10.G.1 Compute culling and compaction.** A compute pass runs over *cell chunks* (e.g. 8 x 8 cells): reject a chunk with no density (the density terms are cheap, most chunks fail) and emit the surviving blades into a buffer with an indirect draw argument. The blade parameters (height, width, lean, colour, wind phase) are computed once in the compute pass and stored (16 bytes per blade is enough), so the vertex shader only bends and projects. Accept: bench total improves by at least 0.4 ms on the shore and dock views and grass vertex time drops at least 3x on the pass timer; the field is **visually identical** (same hash, same density) at 1, 5, 15 m (frames), and the F03 R3 blink test still passes.
- **G10.G.2 Chunked fade instead of per-blade thresholds.** Distance thinning by dropping blades one by one is what makes the far field twinkle as the camera moves (each blade crosses its own threshold at its own moment). Replace with a per-chunk lerp of blade height to zero plus the coverage rule from G10.2.2, so the field melts into the ground tint. Accept: the walk-by flicker score for grass drops by at least 50% and no ring is visible at the edge of the field (frame at the edge).
  > G10.G.2 done (builder B, 2026-10-29): `grass_chunk_fade` (Shaders/Grass.swift, shared by the vertex shader and the culling pass): blade height is scaled by one factor per 8 x 8 cell chunk from the distance of the chunk's centre (0.45 to 1.0 of the draw radius), no blade is dropped by distance any more, and blades narrower than a pixel are drawn a pixel wide and dimmed by `thin_coverage`. **Numbers:** far-field pops (a cell kept in one frame and not the next, patch at 0.55 to 0.85 of the radius, 20 degrees either side of the view, 60 steps of 0.028 m): **102 -> 0** (selftest `grass fade`). `--shimmer-layers` crystal (the grass scene) edge crawl 40.39 -> 39.84, the grass share of it 24.0 -> 23.7 (-1.4 %); grove/woods/shore/dock unchanged within noise. **The plan's accept line ("walk-by flicker score for grass drops by at least 50 %") is NOT met by that metric and cannot be by this change:** the heat map (`SHIMMER_HEAT`) shows the grass crawl is the near field (blades within about 10 m, the large tufts, edges against the ground sliding under a walking camera), not the far field the plan assumed; see Q17. Cost-neutral: `--bench` gw-court 3.75 -> 3.56 ms, ground-grass-5m 6.13 -> 6.20 ms. Frames: no ring at the field's edge (shots/g2/old-edge.png vs new-edge.png); 7 frame hashes changed deliberately (tree-at-14, ground-grass-5m, gw-arrival, gw-court, gw-altar, gw-mirrors, gw-court-taa), baseline regenerated. Edge evidence on flat meadow: shots/g2/old-fieldedge.png vs new-fieldedge.png (Glass Wood, `--world glass --camera -14.5,10.8,105.9,1.6,-0.1`): the grass thins smoothly to the horizon, no ring. review: pass, with one unresolved item: the 50 % flicker target cannot be met by a far-field fade (Q17). Tried and dropped: drawing blades at least 2 px wide (-2.5 % more crawl, but two identical moving walks stopped being bit-identical).
- **G10.G.3 Interaction with M10.** Use the corridor data from M10 (see that plan) to bound which chunks can ever be seen: grass behind the corridor's soft walls can be skipped.

## What the reviewer will check at each pausing point
Pixel-identical frames for stream 1 (byte compare), the ranked shimmer table before/after for stream 2, the pass-timer table for stream 3, and a frame review at walking distance in both worlds. Stream 4 is judged by eye on the contact sheets *and* the numbers.

## Risks the builder should weigh (and may raise)
- A velocity buffer adds a render target and bandwidth on a tile-based GPU: keep it RG16F and write it only from the opaque pass; measure the cost (expected 0.1 to 0.3 ms).
- MetalFX temporal needs macOS 13+; this machine runs 27, but check `supportsDevice`.
- The refactor is the riskiest stream for hidden regressions: the byte-identical rule exists for that reason. If frames differ, find out why before going on.

## G10 grass follow-up (tag `g10-g3`; builder B, 2026-10-30): the near-field edge crawl, measured lever by lever

NOT the plan's dropped item "G10.G.3 corridor-bounded chunks"; this is the follow-up to the G10.G.2 shortfall (Q17: the grass edge crawl is near field, within about 10 m, which a far-field fade cannot reach). Tools: `--shimmer-layers --size WxH` with `SHIMMER_SCENES=crystal,grove` and `SHIMMER_HEAT`, the grass share of the edge crawl times the scene's edge crawl as the number ("grass edge" below), TAA on, the same 60-frame walk for every row; frames in `shots/g3/`. Baselines (shipped look): crystal grass edge 6.45 (960x540), 23.70 (1600x900), 56.82 (2560x1440); grove 0.80, 1.31, 1.48.

**Why the near field cannot be anti-aliased away.** At 1 to 3 m one 0.028 m walking step moves a blade edge by many pixels; the edge metric (no depth, best of a 3x3 match against the last frame) counts that real parallax as crawl. What can be changed is how many such edges there are.

**Levers tried (1600x900, crystal / grove, grass-edge change):**
| Lever | Result | Verdict |
|---|---|---|
| Per-row coverage floor: every row at least one pixel wide, dimmed by what it covers (the tip stays a point) | -0.4 % / -0.1 % | no move: reverted |
| Root-width floor of 1.5 px instead of 1.0 (the earlier 2 px also broke bit-identical walks, F06 note in Q17) | -0.9 % / 0.0 % | no move: reverted |
| Grass velocity | not applicable: the velocity buffer exists only for MetalFX (off by default); native TAA reprojects from depth | not tried |
| **Near-field blade-count LOD**, level 1: within 14 m blades thin to 70 % and widen 25 % | -6.9 % / -14.7 % (total edge crawl -3.5 % / +0.8 %) | kept as an option |
| **Level 2**: 50 % and 40 % | -22.9 % / -22.3 % (total -14.2 % / +1.1 %) | kept as an option |

Level 1 and 2 across the sizes (total edge crawl, then the grass part):

| size | scene | level | total edge crawl | grass edge |
|---|---|---|---|---|
| 960x540 | crystal | 1 | 18.52 -> 17.92 (-3.3 %) | 6.45 -> 5.91 (-8.3 %) |
| 960x540 | grove | 1 | 39.77 -> 39.92 (+0.4 %) | 0.80 -> 0.76 (-4.6 %) |
| 960x540 | crystal | 2 | 18.52 -> 17.21 (-7.1 %) | 6.45 -> 5.09 (-21.0 %) |
| 960x540 | grove | 2 | 39.77 -> 40.05 (+0.7 %) | 0.80 -> 0.68 (-14.4 %) |
| 1600x900 | crystal | 1 | 39.84 -> 38.45 (-3.5 %) | 23.70 -> 22.07 (-6.9 %) |
| 1600x900 | grove | 1 | 100.58 -> 101.34 (+0.8 %) | 1.31 -> 1.11 (-14.7 %) |
| 1600x900 | crystal | 2 | 39.84 -> 34.17 (-14.2 %) | 23.70 -> 18.28 (-22.9 %) |
| 1600x900 | grove | 2 | 100.58 -> 101.65 (+1.1 %) | 1.31 -> 1.02 (-22.3 %) |
| 2560x1440 | crystal | 1 | 82.35 -> 78.04 (-5.2 %) | 56.82 -> 52.13 (-8.3 %) |
| 2560x1440 | grove | 1 | 211.18 -> 212.16 (+0.5 %) | 1.48 -> 1.49 (+0.5 %) |
| 2560x1440 | crystal | 2 | 82.35 -> 70.86 (-14.0 %) | 56.82 -> 45.85 (-19.3 %) |
| 2560x1440 | grove | 2 | 211.18 -> 212.65 (+0.7 %) | 1.48 -> 1.28 (-13.7 %) |

Cost: identical (`--bench`, ground-grass-5m 6.3 ms, gw-court 3.6 ms at every level). The selftest checks that the culling pass and the vertex shader agree to the byte at each level and that fewer cells are kept near the eye.

**Decision.** Default stays 0 (the shipped look, every frame hash unchanged). Levels 1 and 2 are `LW_GRASS_LOD=1|2` for tools and an option for the user (Q30): they buy a 7 to 23 % lower grass edge crawl by thinning the near meadow and widening its blades, which is the opposite of the finer grass detail the user has asked for (notes #3 and #4). The plan's "50 %" target is not reachable by any lever in the grass files.

**The grass and sand boundary (user note #3, 2026-10-24, "grass, sand interfaces show clear pixel rendering").** Reproduced at its recorded position (143.4, 3.1, 169.3, yaw -0.65, pitch -1.24; `shots/g3/sand-base-*.png`): the boundary today is a ragged, soft edge made of fine blades over sand, with no visible pixel blocks at 1600x900 or 2560x1440. It is built by the terrain shader's density mask and the blades' colours, not by the grass geometry, so none of the levers touch it and none helps it; no change is proposed.

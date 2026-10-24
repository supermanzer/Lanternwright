# R05: footsteps that change with the surface (user feedback)

**This comes from the user directly.** The user's words: "I appreciate the change in footstep sounds. They feel much more natural. However, I think the sound should change as you move across different surfaces. You start on a wooden dock and that should sound like you are walking on suspended planks with a certain hollowness. Then you reach sand and that should sound like the grains of sand are shifting as you walk. Then you reach packed dirt and stone which should sound more solid but with some crunch to it."

Keep what the user likes: the natural cadence, soft attack, heel-then-toe pair, run gait and per-step variation. Change *what a step is made of*.

Same rules as before: triage into TASKS.md, selftests and bots green, commit at each pausing point, update INSPECT.md (the existing footstep rows should be rewritten to say what to listen for per surface), story ending left to the user. You cannot listen, so the acceptance has to be measured (see "How to verify").

## Why the surfaces sound alike now (from `AmbienceSynth.startStep`)

Every surface is the same two-part voice: a one-pole low-passed white-noise burst with an exponential decay, plus at most one sine ("thump"). The table only changes decay, gain, cutoff and the sine's pitch. Sand (cutoff 850 Hz, decay 0.21) and grass (650 Hz, 0.17) are nearly the same sound; earth, rock and stone differ mostly in brightness. Nothing in the voice can produce what the user described: no *body resonance* (hollow planks), no *granular texture* (shifting sand), no *crunch* (stone chips on packed ground). Brightness alone cannot do it; the structure of the sound has to differ.

## A better step: three layers per surface

Build each footfall from three layers, each with per-surface parameters, then add the existing per-step random variation (pitch, level, brightness) on top:

1. **Impact** (1 to 6 ms of shaped noise, sharp attack): the moment of contact. Its brightness and length say how hard the surface is.
2. **Body** (a small bank of 2 to 4 damped sine modes, frequency and decay per surface, each detuned randomly by about 3 to 6% per step): how the object under your foot rings. This is what makes wood hollow and stone solid.
3. **Texture** (stochastic micro-grain events: each grain is a 3 to 15 ms band-passed noise tick, triggered at random times with a surface-dependent density across the step's duration): what the surface is made of. This is what makes sand shift and gravel crunch.

Heel then toe, as now: the toe hit uses the same recipe at about 40% level, with fewer grains and a brighter body.

## Per-surface recipes

- **Wooden dock (`wood`): suspended planks, hollow.** Body: a low cavity resonance (around 90 to 160 Hz, slow decay 0.25 to 0.40 s) plus a plank-flex mode around 250 to 400 Hz that dies quickly, and a quiet higher knock (700 to 1100 Hz) in the impact. **Per-plank character:** derive a plank index from position along the dock (distance along `dockStrip` / plank width), hash it to a deterministic pitch offset (about ±12%) and a decay offset, so each plank sounds slightly different and the pattern repeats the same way when you walk back. Occasional (about 1 step in 12, probability rising with a slower, heavier gait) soft creak: a short band-passed, pitch-gliding squeak at about 600 to 1400 Hz. Optional and subtle: a faint water lap or slosh under the dock (reuse the existing surf machinery, low level, only while on the dock). No grains.
- **Sand (`sand`): grains shifting.** Impact: very soft (slow attack 8 to 15 ms, low-passed). Body: almost none. Texture: dense grain cloud, about 60 to 120 grains over 150 to 280 ms, each 4 to 10 ms, band-passed around 1.5 to 5 kHz with a gentle downward sweep over the step (the sand settling), grain level rising then falling (a swish shape). Dry sand: brighter and finer. Wet sand near the waterline (the terrain already has a `wet` weight): lower cutoff (800 to 1500 Hz), fewer, softer grains plus a faint squelch (a short low band-pass thump with a slight pitch drop).
- **Packed dirt / the lantern path (`earth`): solid with some crunch.** Body: short, dull thump (70 to 120 Hz, decay about 40 to 70 ms). Impact: medium-firm. Texture: sparse crunch, 6 to 20 grains over 60 to 140 ms, band-passed 2 to 6 kHz, a few louder (small stones giving way). The path also has pebbles (the terrain already has a pebble term); use pebble weight to raise grain density and level.
- **Stone (`stone`, `rock`, the inlaid plates, lighthouse plinth): solid, hard, a little crunch.** Impact: sharp (1 to 2 ms), bright. Body: a short bright ring (stone about 1.2 to 3 kHz, Q high enough to tick, decay 40 to 90 ms) plus a very low dull thump for mass (80 to 140 Hz). Texture: a handful of fine grit grains (4 to 12) where the sole scuffs. Slightly longer, more distinct reverb tail (the new FDN reverb should pick this up through its send; stone surfaces are a reason to send a little more).
- **Grass (`grass`)**: soft swish: a low-passed noise body with a few very quiet high stalk crackles; slower attack; no body ring. Keep it the quietest surface so the others stand out.
- **Glass Wood surfaces** (optional): map each of its ground kinds to the nearest recipe above, and give the crystalline ground a faint, very quiet high glassy overtone (a short inharmonic partial, tied to `ToneTable` so it stays in the same tuning as the chimes). Do not let this stop the main work.

Running keeps its identity (one harder, shorter impact), but scale each recipe: more body and impact, fewer and shorter grains.

## Transitions between surfaces

Do not flip surface abruptly at one footfall. Use **weights** instead of a single `SurfaceKind`: sample the terrain's surface mix at the foot (sand, grass, rock, path/earth, wet) and the dock/collider surface, and blend the *layer levels* of the two or three dominant recipes (for example the sand-to-grass boundary mixes grain density, the beach-end of the dock blends the plank body away over two steps). Keep `Game.currentSurface` working (tests and other code use it); add a weighted version beside it, e.g. `surfaceMix`, and let the synth accept up to three (kind, weight) pairs per step. The dock boundary is the user's own example: stepping off the planks onto sand should change within one or two steps, never mid-grain-cloud.

## Implementation notes

- All of this stays inside the existing audio thread discipline: no allocation, no locks beyond what `AmbienceSynth` already does for steps. Grain scheduling can pre-roll a small array of (time, level, centre frequency) per step at `startStep` time (fixed capacity, for example 128 grains) and render them in the sample loop; keep the cap on simultaneous step voices.
- Use the existing per-step seed for determinism. Offline `AudioDump` must still produce the same file for the same seed.
- The stone drone, hums and ducking are separate; do not touch them. The reverb send for steps: stone a little more than the others, sand and grass almost none.
- Keep CPU low: grains are a few hundred samples each; fine at the current voice cap.

## How to verify (you cannot listen)

Extend `AudioDump` (or add a `--footstep-dump <surface>` mode) to render N steps of each surface to WAV, then in selftests measure, with fixed seeds:
- **wood**: low-band (80 to 400 Hz) energy fraction clearly above every other surface; a decay to -30 dB longer than 0.2 s; two different plank indices give different dominant pitches; the same plank index twice gives the same pitch.
- **sand**: grain count (peak-pick on a band-passed envelope) at least 5x that of stone; no energy peak above the step's first 10 ms (soft attack); wet sand has a lower spectral centroid than dry.
- **earth**: a dominant low thump (70 to 130 Hz) shorter than 80 ms plus a nonzero grain count, fewer grains than sand.
- **stone**: the shortest attack, highest spectral centroid among the three requested surfaces, a ring partial in 1.2 to 3 kHz.
- **blend**: a step at a 50/50 sand-grass weight lies between its two pure steps in grain density and centroid.
- **regression**: cadence, heel-toe spacing, run behaviour and the existing step tests unchanged; no clipping (peak below 0.9) on any surface at run.
Then say plainly in the done-note that a person must listen, and add per-surface INSPECT.md rows with exact places to walk (dock end, beach, wet sand edge, lantern path, lighthouse plinth, the inlaid plate in the Glass Wood) and what each should sound like in the user's own words: "suspended planks with hollowness", "sand grains shifting", "solid with some crunch". The user will judge; if they say a surface is wrong, the per-surface parameter table must be easy to edit (keep all recipe numbers in one `FootstepRecipe` table, not scattered).

## Priority

Put this *before* the remaining R04 frame items: it is a direct user request. Finish the R04 item you are mid-way through, commit, then do this.

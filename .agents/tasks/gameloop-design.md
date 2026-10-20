# Hex Golf Deckbuilder — Core Turn Loop Design (First Playable)

Status: DESIGN (no code in this step). Authored against the real codebase in the
`feature/gameloop-v1` worktree. Technology stack is **Godot 4.7 + GDScript** (locked).
The engine binary used for verification is `/Applications/Godot.app/Contents/MacOS/Godot`.

This document is the implementable specification for a planner and coder. The settled
concept (hex board-game movement + card deckbuilder golf, "play cards then press Shoot,"
golf complexity as a strategic variance layer tamed by cards, Balatro-style weighted-random
landing, hand-per-hole) is the source of truth and takes precedence over any other design
artifact in the repo. This document pins the exact data shapes and surgical integration
seams so no architectural decisions remain for implementation.

---

## 0. Scope Fences (read first)

**In scope — the deliverable:** a FIRST PLAYABLE of the single-hole core turn loop running
from `scenes/GOLF.tscn`. The player deals a hand at the tee, plays a Club card, optionally
plays shot-shape/modifier cards, aims one of 6 hex directions, previews the footprint,
presses **Shoot**, the ball resolves (carry + roll-out + wind + slope) to a landing hex, a
reward-layer score (chips × mult) is computed, and the loop repeats until the ball is holed
out.

**Win/Lose for first playable:** the hole only needs to be **HOLED OUT**. There is **NO fail
state, NO stroke budget, NO score gate**. Scoring (`final_score = chips × mult` per shot) is
still computed but **demoted to a reward/currency layer** — displayed, accumulated, never
gates anything.

**Explicitly OUT of scope this run (do not build):**
- The shop/run/9-hole meta layer. Existing stubs `run_state_manager.gd`, `shop_manager.gd`,
  `currency_manager.gd` are reused in a LATER phase. They may stay wired where already wired,
  but no new dependencies on them.
- The curated hole+hand "skill challenge" MODE. The seed/definition ARCHITECTURE that makes
  it first-class IS in scope (Section 8); the mode/UI is not.
- A full art pass. New UI must be clean/neutral per Section 14; no decorative work.
- Restructuring/splitting the 6924-line `scripts/hex_grid.gd` for cleanliness. Touch it
  **only** where the new loop genuinely requires it, surgically.
- Do NOT touch `models/`, `textures/`, `theme/`, `addons/`, `assets/`, the `.md` docs, or
  `.github/` except where wiring a new UI control genuinely requires an existing asset ref.

**Clean-build invariant:** the project must load and run headless with **0 script errors at
every incremental step**. The retirement plan (Section 10) is ordered so the build never
breaks between steps.

---

## 1. Current-State Facts (verified by reading the code)

These are the load-bearing facts the design builds on. All confirmed by reading the files.

- **Grid / terrain.** `scripts/hex_grid.gd` (root script of `scenes/GOLF.tscn`,
  `uid://i0lqex70w705`) is a `Node3D`. Offset hex grid, `grid_width` default 10,
  `grid_height` default 40, `TILE_SIZE = 1.0`, `YARDS_PER_CELL = 10.0`.
  `enum SurfaceType { TEE=0, FAIRWAY=1, ROUGH=2, DEEP_ROUGH=3, GREEN=4, SAND=5, WATER=6, TREE=7, FLAG=8 }`.
  Public API already present: `get_cell(col,row)->int`, `set_cell`, `get_grid_width/height`,
  `get_elevation(col,row)->float`, `get_adjacent_cells(col,row)`, `get_outer_ring_cells`,
  `get_tile_distance(from,to)->int`, `world_to_grid(Vector3)->Vector2i`,
  `get_tile_surface_position(Vector2i)->Vector3`, `flag_position: Vector2i`,
  `golf_ball: Node3D`. Procedural generation (`generate_hole_with_par`, island/dogleg/s-curve
  generators) must NOT be broken.
- **Hex direction offsets** are parity-dependent and already implemented in
  `scripts/aoe_system.gd::_get_direction_offsets(is_odd)` and
  `_get_neighbor_in_direction(tile, direction, is_odd)` with the index convention
  `0=Up, 1=Up-Right, 2=Down-Right, 3=Down, 4=Down-Left, 5=Up-Left`. These are the canonical
  6 directions the new aiming uses. Reuse them; do not reinvent.
- **Shot lifecycle** lives in `scripts/shot_manager.gd` (`class_name ShotManager`). Phased
  pipeline with signals: `shot_started → player_aiming → aoe_computed → (confirm) →
  modifiers_applied_on_aoe → landing_resolved → ball_path_simulated → scoring_computed →
  modifiers_applied_on_scoring → shot_completed`. Entry points: `start_shot(ball, start_tile)`,
  `set_aim_target(aim_tile)`, `confirm_shot()`. It already does weighted landing selection in
  `_select_landing_tile_from_aoe` / `_weighted_tile_selection` and curve/distance projection
  in `_calculate_curved_target`. This pipeline IS the turn loop backbone and is KEPT.
- **ShotContext** (`scripts/shot_context.gd`, `RefCounted`) carries per-shot state. Existing
  fields the design reuses verbatim: `start_tile`, `aim_tile`, `landing_tile` (Vector2i);
  `distance_mod`, `accuracy_mod`, `roll_mod`, `wind_curve` (int); `aoe_tiles: Array[Vector2i]`,
  `aoe_radius: int`, `aoe_shape: String`, `aoe_weights: Dictionary`; `path_tiles`,
  `curve_strength: float`, `curve_profile: String`, `max_bounces`, `roll_distance`,
  `elevation_influence: float`; `base_chips`, `chips`, `mult`, `final_score`, `shot_index`;
  `metadata: Dictionary`; helpers `reset()`, `add/get/has_metadata`, `calculate_final_score()`,
  `get_shot_distance[_yards]()`, `set/get_start/landing_terrain()`.
- **Modifier dispatch** (`scripts/modifier_manager.gd`) calls modifier objects at phases
  `apply_before_aim / apply_on_aoe / apply_on_landing / apply_on_scoring / apply_after_shot`,
  each receiving the `ShotContext`. Cards reach this via `CardModifier` wrappers.
- **Cards.** `CardData` (Resource) has `card_id`, `card_name`, `description`, `card_type`
  (`enum CardType { SHOT, NEGATIVE, POSITIVE, NEUTRAL, CLUB, SPECIAL }`), `target_club: String`,
  `effects: Array[Resource]` (each a `CardEffect`), plus `shot_shape`/`accuracy_shape` enums.
  `CardInstance` wraps a `CardData` at runtime. `CardEffect` (Resource) is the composable unit
  with `apply_before_aim/on_aoe/on_landing/on_scoring/after_shot(context, upgrade_level)` and a
  `can_trigger(context)` gate. Concrete effects live in `scripts/cards/effects/`
  (`EffectSimpleStat`, `EffectAOEExpand`, `EffectCurveShot`, `EffectRollModifier`,
  `EffectChipsBonus`, `EffectMultBonus`, `EffectTerrainBonus`, `EffectDistanceBonus`,
  `EffectAOELineHorizontal/Vertical`, `EffectAOEPerfect`, `EffectAOERing`, etc.).
  `CardLibrary` (autoload-style singleton via `CardLibrary.instance`) registers all cards; it
  already registers one CLUB card per `ClubType` with `target_club` set. `DeckManager`
  manages `_draw_pile/_active_cards/_discard_pile`, with `get_hand()`, `play_card()`,
  `draw_candidates()`, `clear_active_cards()`, `shuffle_discard_into_deck()`.
  `DeckDefinition` (Resource) is the seedable deck shape (`card_ids`, `card_counts`, direct
  `cards`). `CardSystemManager` bridges decks ↔ modifier manager ↔ shot manager.
- **Club stats** are defined TWICE today: once as `ClubType` + `CLUB_STATS` dict in
  `hex_grid.gd` (`distance/accuracy/roll/loft/arc_height/swing_difficulty/curve`), and once as
  CLUB cards in `CardLibrary`. The design unifies the numbers onto club cards (Section 3) and
  keeps `CLUB_STATS` as the lookup table those cards reference.
- **Retirement targets confirmed present:** `scripts/swing_meter.gd` (`class_name SwingMeter`,
  3-click meter, emits `swing_completed(power,accuracy,curve_mod)`), `scripts/spin_meter.gd`
  (`SpinMeter`, emits `spin_confirmed(spin_value)` — this is what actually confirms a shot
  today), `scripts/putting_system.gd` (`PuttingSystem`, real-time charge-and-aim putt with its
  own ball physics), `scripts/swing_hand_3d.gd` (SubViewport 3D swing-card hand),
  `scripts/wind_system.gd` (`WindSystem`, already board-ish: returns int `calculate_wind_curve`).
  Scenes: `scenes/ui/SwingMeter.tscn`, `scenes/ui/spin_meter.tscn`, instanced in
  `scenes/ui/main_ui.tscn` (nodes `SwingMeter`, `SpinMeterPanel`, `SpinMeter`, `SwingHand`).
- **How a shot is confirmed today:** `SpinMeter.spin_confirmed → ShotUI._on_spin_confirmed →
  ShotUI._on_swing_completed_with_spin → (force_start_shot if needed) → shot_manager.confirm_shot()`.
  `ShotUI.bypass_card_selection = true` already relaxes prerequisites. This is the exact seam
  the Shoot button replaces.
- **Putting entry today:** `hex_grid._start_new_shot()` routes to `putting_system.enter_putting_mode()`
  when the ball surface is `GREEN`. This branch is what we excise (Section 10).

---

## 2. Requirements

### 2.1 Functional Requirements

FR1. On arriving at the tee, deal a **full hand for the hole** from the club deck and the
shot/modifier deck. Cards are played and discarded during the hole; the hand is refilled at the
next tee. For this one-hole playable, "next tee" is the only refill boundary.

FR2. A turn is: read board → play exactly one **Club card** → optionally play one or more
**shot-shape/modifier cards** → aim one of **6 hex directions** → board previews the **footprint**
(candidate landing hexes with weights + most-likely center) → press **Shoot** → ball resolves
to a landing hex → compute reward-layer score → repeat until holed out.

FR3. A Club card defines a **distance band** (min–max hexes) and a **base roll** and **base
spread**. Clubs: Driver, Fairway Wood, Long Iron, Mid Iron, Short Iron, Wedge, Putter
(Putter playable only when the ball is on the Green). Exact numbers in Section 3.

FR4. When the footprint spans more than one hex, the final landing hex is chosen by
**weighted-random** draw over the footprint (Balatro-style). Shot-shape/modifier/advantage
cards and board conditions **narrow or bias** these weights. Exact model in Section 2/4/5.

FR5. **Board modifiers** (not continuous physics) adjust the footprint and landing: wind,
roll-out, elevation/slope, and lie penalties. Exact math in Section 4.

FR6. **Advantage / shot-shape cards** tame variance with the exact effects in Section 5
(Ignore Wind, Roll +2, Soft Landing, Tighten Spread, Punch, Flop, Draw/Fade, Bump-and-run,
Stinger).

FR7. **Terrain outcomes** are golf-reframed per Section 6 (Tee/Fairway/Rough/Deep Rough/
Bunker/Water/Trees/Green/Flag), affecting legality, spread, roll, reposition, and scoring.

FR8. The loop runs from `scenes/GOLF.tscn`. The ball being on the Flag hex triggers
**hole-out**, which ends the loop with a complete-state (confetti/popup already exist).

FR9. Both the **hole layout** and the **dealt hand** are drivable from a **seed** OR an
explicit **definition resource** (Section 8), cheaply, so curated challenges are first-class
later.

### 2.2 Non-Functional Requirements

NFR1. Clean headless build (0 script errors) preserved at every incremental step.

NFR2. No long loading times. Footprint/preview computation is pure integer hex math over a
small tile set; it must run per-aim-change without frame hitches. No per-shot resource loads.

NFR3. Determinism-with-seed: given the same seed and the same card plays and the same aim, the
resolved landing hex must be reproducible (single seeded RNG stream — Section 2.3/8).

NFR4. Legibility: the previewed footprint, its center, and the per-hex odds must be derivable
and displayable; nothing about landing may depend on hidden continuous trajectory state.

### 2.3 Acceptance Criteria (testable, numbered)

AC1. Loading `scenes/GOLF.tscn` headless produces 0 script errors and a generated hole with a
reachable `flag_position`.

AC2. At the tee, a hand is dealt: the club deck yields ≥1 playable Club card and the
shot/modifier deck yields the configured hand size (default 5) of non-club cards.

AC3. Playing a Club card sets `ShotContext` distance-band/roll/spread basis such that
`compute_footprint()` (Section 2.4) returns a non-empty `Array[Vector2i]` of in-bounds hexes
with a populated `aoe_weights` dict summing to a positive total, and a defined
most-likely-center equal to the aim hex projected to the band center.

AC4. Aiming each of the 6 directions produces a footprint whose center lies along that
direction from the ball, at a hex-distance within `[band_min, band_max]` after modifiers,
clamped to grid bounds.

AC5. Playing "Tighten Spread" reduces the footprint hex count (or concentrates weight toward
center) versus the same shot without it; playing "Ignore Wind" makes the resolved center
independent of the current wind vector.

AC6. Pressing Shoot resolves exactly one landing hex drawn from the footprint weights via the
seeded RNG; with a fixed seed + fixed plays + fixed aim, the landing hex is identical across
runs (NFR3).

AC7. The resolved landing moves the ball strictly closer (in `get_tile_distance` to
`flag_position`) than the start, for a legal forward shot on an open hole (sanity, not a hard
guarantee under adverse wind — the harness asserts "ball moved and hole distance did not
increase for a straight tee shot on a clear hole").

AC8. `final_score = round(chips × mult)` is computed and surfaced each shot; it never blocks
progression and no stroke/score gate exists.

AC9. Landing the ball on the Flag hex triggers the existing hole-complete state exactly once
(`_trigger_hole_complete` guarded by `hole_complete_triggered`).

AC10. Putter is rejected/омitted unless the ball surface is Green; a Green ball resolves putts
through the same play-card→Shoot path (no real-time mini-game).

AC11. Water landing applies the reposition + penalty board modifier (Section 6) and the loop
continues (no fail state).

AC12. The headless harness (Section 15) runs the full loop deal→play→aim→shoot→…→hole-out and
exits 0.

### 2.4 Footprint representation (data shape)

The footprint is the gameplay centerpiece (the repurposed AOE system). It is a plain value
object computed each time the plan changes (club played, modifier played, aim changed). It is
stored on the existing `ShotContext` fields plus a small typed helper. No new persistent state.

Representation (all on `ShotContext`, reusing existing fields where they exist):

- `aim_dir: int` (0–5) — NEW field; the chosen hex direction. Add to `ShotContext`.
- `center_tile: Vector2i` — the **most-likely center** = ball projected `band_center` hexes
  along `aim_dir` then adjusted by directional board modifiers (wind/slope/draw-fade), clamped
  to bounds. Stored in existing `aim_tile` (set via `set_aim_target`) so the existing pipeline
  and UI keep working; `center_tile` is an alias name in docs.
- `aoe_tiles: Array[Vector2i]` (existing) — the full set of candidate landing hexes (the
  spread), always includes `center_tile`.
- `aoe_weights: Dictionary` (existing, `Vector2i -> float`) — per-hex weight; the landing draw
  samples this (the pipeline already honors `aoe_weights` in `_weighted_tile_selection`).
- `band_min:int, band_max:int, band_center:int, base_spread:int, base_roll:int` — NEW transient
  fields written when a Club card is played (Section 3). Add to `ShotContext`.

The "footprint" = (`aoe_tiles` set + `center_tile` + `aoe_weights`). "Spread" = the shape/size
of `aoe_tiles` around `center_tile`. This is exactly the triple the concept calls for:
set of landing hexes + most-likely center + spread + weighting.

---

## 2.5 The Footprint Weighting Model (exact)

**Feel goal:** a shot is a cloud of possible landing hexes centered on where you aimed; it is
more likely to land near the center and less likely at the edges; good cards shrink the cloud
or pull its mass toward the center or shift it predictably. This is the Balatro-style
"weighted bag" feel — randomness you can see and stack the odds on.

**Shape of the cloud.** The spread is a hex disk of radius `R = effective_spread` around
`center_tile`, built with the existing `AOESystem.compute_circle_aoe(center, R, hole)` (rings
0..R). `effective_spread = max(0, base_spread + spread_mods)` where `base_spread` comes from the
club (Section 3) and `spread_mods` is the signed sum of card/board spread modifiers (Tighten
Spread −1, Deep Rough +1, etc.). When `R = 0` the footprint is a single hex (deterministic).

**Weight of each hex.** For a candidate hex `t` at hex-distance `d = hex_distance(center, t)`
(0..R), the base weight is a triangular/linear falloff:

```
w(t) = (R + 1 - d) ^ FALLOFF_POW      # FALLOFF_POW is the concentration exponent
```

with `FALLOFF_POW = 1.0` as the tuned default (linear falloff: center hex weight `R+1`, outer
ring weight `1`). This is deliberately simple, legible, and cheap. Rationale for choosing this
over a Gaussian: it has no tail beyond `R` (the footprint is exactly the visible hexes — no
"impossible" far landings), the numbers are small integers players can reason about, and it
reuses the ring structure the AOE system already produces. A Gaussian would add a `sigma` to
communicate and a truncation decision; the linear hex-ring falloff communicates itself (the
preview literally shows brighter = more likely).

**Edge/terrain reweighting (board bias, applied after base weights).** Multiply each hex weight
by a terrain factor so the cloud realistically avoids some surfaces and clusters on good ones.
Reuse and REPLACE the existing `AOESystem.calculate_weights_by_terrain` factors with the tuned
table (these are MULTIPLIERS on `w(t)`):

| Surface | factor | intent |
|---|---|---|
| FAIRWAY / TEE | 1.15 | ball finds the short grass a touch more |
| GREEN | 1.25 | approaches gather |
| ROUGH | 0.90 | |
| DEEP_ROUGH | 0.75 | |
| SAND | 0.60 | |
| TREE | 0.45 | high shots rarely stop in trees |
| WATER | 0.50 | still possible (then penalty) — not zeroed, or players can't be punished |
| FLAG | 1.40 | gentle gravity toward the cup |

Terrain factors are clamped so no single factor can make a reachable hex unreachable
(min factor 0.30) — variance must stay real.

**How cards narrow/bias the odds (summary; exact per-card in Section 5):**
- *Narrow:* reduce `effective_spread` (Tighten Spread −1) or raise `FALLOFF_POW` toward 2.0
  (concentrates weight on the center without shrinking the visible footprint). The two tools
  exist so "tighten" cards can either shrink the cloud or sharpen it.
- *Bias/shift:* move `center_tile` perpendicular to `aim_dir` (Draw/Fade) or along it
  (distance mods), which moves the whole cloud; terrain reweighting then re-biases toward good
  hexes.
- *Kill variance source:* Ignore Wind zeroes the wind shift of `center_tile` for that shot.

**The draw.** `ShotManager._select_landing_tile_from_aoe` already selects via `aoe_weights`
when present. The only change: the footprint builder must POPULATE `aoe_weights` (it currently
falls back to a distance heuristic). The RNG must be the single seeded stream (Section 8), not
bare `randf()` — see Section 10/Integration for the surgical change.

---

## 3. Clubs as Distance Bands (exact numbers)

Scale: **1 hex = 10 yards**. `distance`/`roll`/`spread` are in **hexes**. Bands are inclusive.
`band_center = round((band_min + band_max) / 2)`. These numbers live in the `CLUB_STATS` table
in `hex_grid.gd` (extended with `band_min/band_max/base_spread`); the CLUB cards in
`CardLibrary` reference the club by `target_club` and carry no duplicate numbers.

| Club (card id) | ClubType | band_min | band_max | band_center | base_spread (R) | base_roll | Yardage (approx) | Notes |
|---|---|---|---|---|---|---|---|---|
| Driver (`club_driver`) | DRIVER | 22 | 26 | 24 | 3 | 3 | 220–260 | widest spread, hottest roll |
| Fairway Wood (`club_fwood`) | WOOD_3 | 18 | 20 | 19 | 2 | 3 | 180–200 | |
| Long Iron (`club_long_iron`) | IRON_3 | 15 | 17 | 16 | 1 | 2 | 150–170 | narrow |
| Mid Iron (`club_mid_iron`) | IRON_6 | 12 | 14 | 13 | 1 | 2 | 120–140 | narrow |
| Short Iron (`club_short_iron`) | IRON_8 | 9 | 11 | 10 | 1 | 1 | 90–110 | tight |
| Wedge (`club_wedge`) | PITCHING_WEDGE | 5 | 8 | 6 | 1 | 0 | 50–80 | tight, stops fast |
| Putter (`club_putter`) | PUTTER | 1 | 4 | 2 | 0 | 1 | 10–40 | GREEN only; single-hex spread |

`base_spread` doubles as the realism knob: longer clubs scatter more (`band_max − band_min` is
also wider for the driver, so the *distance* is itself uncertain). When a Club card is played,
the builder also applies **distance variance within the band** by treating the band as a second
weighting axis: candidate centers at hex-distances `band_min..band_max` along `aim_dir` each get
the same linear falloff toward `band_center`, then the perpendicular spread disk is applied at
each. Implementation simplification that keeps it cheap and legible: compute `center_tile` at
`band_center`, build the spread disk of radius `R' = max(base_spread, round((band_max−band_min)/2))`
so the disk naturally covers the band's distance uncertainty; this folds both axes into one hex
disk and one weight pass. (Chosen over a true 2-axis ellipse because the hex disk is what the
AOE system produces and what the preview can render directly.)

**Roll trait per club** = `base_roll` (hexes of forward roll-out after carry, Section 4.2). The
driver's `base_roll=3` plus its spread is why it is powerful but wild; the wedge's `base_roll=0`
is why it stops fast and is the control club.

Club legality by lie reuses `LieSystem.LIE_DATA[...].allowed_clubs` (already defined). Putter is
restricted to GREEN by both the lie table and an explicit guard in the turn controller.

---

## 4. Board Modifiers (exact math)

All modifiers are integer hex adjustments applied to `center_tile` and `effective_spread` and
`base_roll` BEFORE the weighted draw. None are continuous trajectory physics. Order of
application is fixed (Section 9 pipeline). Let `fwd` = unit step along `aim_dir`,
`perp` = the perpendicular hex axis.

### 4.1 Wind (board modifier; reuse `WindSystem`)
`WindSystem.calculate_wind_curve(shot_direction: Vector2)` already returns an **int** lateral
push in `[-strength, +strength]` (strength 0–3). Use it directly:
- `wind_shift = WindSystem.calculate_wind_curve(fwd_as_vector2)` → write to
  `ShotContext.wind_curve`.
- Apply as a perpendicular shift of `center_tile`: `center_tile += perp * wind_shift`.
- Additionally, a head/tail component shortens/lengthens: project the wind vector onto `fwd`;
  `head_tail = round(dot(wind_vec, fwd) * strength * 0.5)` → add to the along-axis distance
  (tailwind extends, headwind shortens), clamped to `±2`.
- "Ignore Wind" card sets `wind_shift = 0` and `head_tail = 0` for that shot.
Wind is generated per hole via `WindSystem.generate_wind(difficulty)` (already exists); for the
seeded/definition hole it is generated from the seeded RNG (Section 8).

### 4.2 Roll-out (board modifier)
After carry to `center_tile`, the ball rolls forward along `fwd` by
`roll = max(0, base_roll + roll_mod + terrain_roll(landing_surface))` hexes, where `roll_mod`
is the signed sum of card roll effects (Roll +2, Soft Landing −99→clamped 0, etc.) and
`terrain_roll` is:

| Landing surface | terrain_roll |
|---|---|
| GREEN | −1 (grabs) |
| FAIRWAY/TEE | 0 |
| ROUGH | −1 |
| DEEP_ROUGH | −2 |
| SAND | −3 (plugs) |
| TREE | −2 |
| WATER | 0 (handled by reposition) |

Roll is applied by walking `fwd` one hex at a time from the drawn landing hex; each step stops
early if it would leave bounds or enter WATER (ball stops at last valid hex before water, which
then is the landing used for scoring). Roll happens to the **drawn** landing hex, not the
center, so variance + roll compose. `ShotContext.roll_distance` records the applied roll.

### 4.3 Elevation / Slope (board modifier)
Use `hex_grid.get_elevation(col,row)`. Two effects, both integer:
- **Carry elevation:** `elev_delta = elevation(center_tile) − elevation(start_tile)`. Uphill
  targets play longer (shorten the along-axis distance), downhill play shorter:
  `dist_adjust = -round(clamp(elev_delta / ELEV_PER_HEX, -2, 2))` with `ELEV_PER_HEX = 0.6`
  (tuned against `ELEVATION_OFFSETS`/`_calculate_elevation` ranges). Applied to the along-axis
  distance of `center_tile`.
- **Landing/green slope:** after roll, if the final hex is GREEN, apply one extra slope step:
  compute downhill neighbor via the existing slope logic pattern (the gradient over the 6 hex
  neighbors), push the ball one hex downhill with probability proportional to slope steepness;
  for the first playable, make it deterministic one-hex downhill nudge when
  `max_neighbor_drop > SLOPE_THRESHOLD (0.25)`. This replaces the retired putting mini-game's
  continuous slope with a single legible board step.

### 4.4 Lie penalties (board modifier; reuse `LieSystem`)
`LieSystem.apply_lie_to_shot(context, lie_info)` already adds `distance_mod` and `roll_mod` and
chips/mult from `LIE_DATA`. Keep it, with these REFRAMED/retuned values so lie affects the
footprint legibly (edit `LIE_DATA` in `lie_system.gd`):
- Lie `distance_mod` (hexes along axis) and `roll_mod` stay as additive ints already consumed.
- Reintroduce lie **spread** effect as `spread_mod` (the current code comments out accuracy→AOE):
  Fairway/Tee 0, Rough +1, Deep Rough +2, Sand +2, Tree +3 (also see Section 6). Add a
  `spread_mod` key to `LIE_DATA` and have the footprint builder read it. This is the surgical
  re-enable of terrain→spread, now feeding the footprint instead of the old AOE path.

---

## 5. Advantage / Shot-Shape Cards (exact mechanical effects)

Each is a `CardData` (`card_type = SHOT`) composed of existing/ää new `CardEffect` resources.
Effects write to `ShotContext` at `apply_before_aim` (stat/shape) or are read by the footprint
builder. Where an existing effect class suffices it is named; where a new one is needed it is
flagged NEW with its target field. All are integer/board effects.

| Card | Effect on footprint/weighting | Implemented via |
|---|---|---|
| **Ignore Wind** | zero wind shift & head/tail for this shot; sets `ctx.metadata["ignore_wind"]=true` which the wind step checks | NEW `EffectIgnoreWind` (writes metadata flag) |
| **Roll +2** | `roll_mod += 2` | existing `EffectSimpleStat(target_stat="roll_mod", value=2)` |
| **Soft Landing** | kills roll: `roll_mod -= 99` then roll clamped ≥0 → effectively 0; also `metadata["soft_landing"]=true` so green terrain_roll not double-applied | `EffectSimpleStat(roll_mod, -99)` |
| **Tighten Spread** | `spread_mod -= 1` (shrinks disk, min 0) AND `falloff_pow += 0.5` (sharpens center) | NEW `EffectTightenSpread` (writes `spread_mod` + `falloff_pow`) |
| **Punch** | under-trees pass (sets `metadata["punch"]=true` so TREE does not block this shot), `+1 roll`, `spread_mod -1`, caps along-axis distance to `band_center` (low flight = no extra carry) | NEW `EffectPunch` |
| **Flop** | short, ~0 roll: along-axis distance set to `band_min`, `roll_mod -= 99` (→0), `spread_mod -1` | NEW `EffectFlop` |
| **Draw** | bend footprint left: `center_tile += perp * -DRAW_BEND`; `DRAW_BEND=2` | existing `EffectCurveShot(curve_direction=Left)` feeding `curve_strength`/`curve_profile="draw"`; builder converts to perp shift |
| **Fade** | bend right: `center_tile += perp * +FADE_BEND`; `FADE_BEND=2` | existing `EffectCurveShot(curve_direction=Right)` |
| **Bump-and-run** | low carry, big roll: along-axis distance = `band_min`, `roll_mod += 3`, `spread_mod -1` | NEW `EffectBumpRun` |
| **Stinger** | low + wind-immune + long roll: `metadata["ignore_wind"]=true`, `roll_mod += 2`, along-axis distance += 1, `spread_mod -1` | NEW `EffectStinger` |

New transient `ShotContext` fields these require: `spread_mod: int`, `falloff_pow: float`
(default 1.0), plus the existing `roll_mod`, `distance_mod`, `curve_strength`, `curve_profile`,
`wind_curve`, `metadata`. Draw/Fade reuse `curve_strength` (the builder reads it as a perp hex
shift = `round(curve_strength)` rather than the old continuous curve projection).

Validation of card effects: all values are authored constants in the effect resources; no
external input. The only runtime input is which cards the player plays and the aim direction
(both constrained — Section 7).

---

## 6. Terrain Outcome Modifiers (exact)

Golf reframing of the hex terrain. Values consolidated so one table drives legality, spread,
roll, reposition, and scoring. Authoritative home: `LieSystem.LIE_DATA` (lie/start effects) +
Section 4.2 `terrain_roll` (landing effects) + the footprint terrain factors (Section 2.5). The
scoring chips/mult below live on `LIE_DATA` (start) and `ScoringManager.BASE_POINTS` (landing).

| Surface | Playable from? | spread_mod (as lie) | terrain_roll (as landing) | footprint factor | Special |
|---|---|---|---|---|---|
| TEE | yes (all clubs) | 0 | 0 | 1.15 | start-of-hole |
| FAIRWAY | yes | 0 | 0 | 1.15 | ideal |
| ROUGH | yes (not Driver) | +1 | −1 | 0.90 | distance_mod −2 (lie) |
| DEEP_ROUGH | yes (short irons+) | +2 | −2 | 0.75 | distance_mod −4 (lie) |
| SAND/Bunker | Wedge/Short Iron | +2 | −3 | 0.60 | distance_mod −6 (lie) |
| WATER | no | — | — | 0.50 | **penalty + reposition** (below) |
| TREE | restricted | +3 | −2 | 0.45 | **blocks high shots**; only Punch/Stinger pass (else landing re-rolled/stopped short, below) |
| GREEN | Putter only | 0 | −1 | 1.25 | slope nudge (4.3); Putter legal here |
| FLAG | — | — | — | 1.40 | **holed**: ball on flag → `_trigger_hole_complete()` |

**Water reposition:** reuse existing `hex_grid._handle_water_hazard()` behavior as the board
modifier — ball returns to `previous_valid_tile` and `run_state.record_stroke(0)` logs the
penalty stroke. No fail state. The landing-resolution step sets `metadata["hit_water"]=true` and
the animation branch already present handles the splash+return.

**Trees block high shots:** during roll/carry resolution, if the drawn landing hex or a carry
hex is TREE and the shot is NOT Punch/Stinger (`metadata["punch"]`/`["stinger"]` absent), the
ball stops at the last non-TREE hex before it (blocked), matching the "only punch/stinger pass"
rule. Punch/Stinger ignore TREE and roll through.

---

## 7. Hand Cadence & Turn Input

**Deal full hand per hole.** At hole start (tee), `CardSystemManager` deals:
- **Club hand:** the full club set from the club `DeckDefinition` (`get_club_deck()` /
  `swing_deck.tres`) — all 7 clubs available as a hand (clubs are reusable within a hole in golf;
  a club card is not consumed, it is selected per shot). For the first playable, clubs are
  always-available picks (a "bag"), not a depleting pile. This matches real golf and keeps the
  one-hole loop playable.
- **Shot/modifier hand:** draw `HAND_SIZE = 5` cards from the shot/modifier `DeckDefinition`
  (`starter_deck.tres`) into the hand. These ARE consumed (played → discard). Refill to full at
  the next tee. For the one-hole playable there is no next tee, so the hand simply depletes as
  played; running out means plain shots (still fully playable).

**Turn input** (lives in a new thin controller, Section 9): select Club card → optionally play
modifier cards → choose `aim_dir ∈ {0..5}` (keyboard/edge-click mapping to the 6 hex directions
via `AOESystem._get_direction_offsets`) → preview updates live → **Shoot** button confirms.
Aim is constrained to the 6 directions (no free tile click required; the existing hover/lock
tile path may remain as a convenience that snaps to the nearest of the 6 directions, but the
canonical input is the 6-direction choice). External inputs validated: `aim_dir` clamped to
0–5; club selection must be a legal club for the current lie (else the Shoot button stays
disabled and a reason is shown); Putter only on Green.

---

## 8. Authored / Seeded Content Architecture (first-class)

Goal: the hole layout AND the dealt hand are both drivable from a **seed** or an explicit
**definition resource**, cheaply, so curated hole+hand challenges are first-class later. Build
the architecture now; do not build the challenge mode.

### 8.1 Single seeded RNG stream — `HoleContext` (NEW, small)
Add a tiny `scripts/hole_context.gd` (`class_name HoleContext`, extends `RefCounted`) created
once per hole and held by `hex_grid`:

```
class_name HoleContext
var seed: int = 0
var rng: RandomNumberGenerator      # seeded once: rng.seed = seed
var definition: HoleDefinition = null   # null => fully procedural from seed
```

All randomness that affects gameplay — procedural generation choices, `WindSystem.generate_wind`,
the footprint landing draw, slope nudges — MUST pull from `HoleContext.rng`, not bare
`randf()/randi()`. This is the surgical change that makes AC6/NFR3 hold. (Scope: only the RNG
calls on the gameplay-resolution path need rerouting; cosmetic/foliage randomness may stay on
the global RNG.)

### 8.2 `HoleDefinition` resource (NEW)
`scripts/hole_definition.gd` (`class_name HoleDefinition`, extends `Resource`):

```
@export var hole_id: String = ""
@export var seed: int = 0                 # 0 => random seed
@export var par: int = 4
@export var use_procedural: bool = true   # true: generate from seed; false: use explicit layout
# Explicit layout (used when use_procedural == false). Sparse override map:
@export var grid_width: int = 10
@export var grid_height: int = 40
@export var tee: Vector2i = Vector2i(-1,-1)
@export var flag: Vector2i = Vector2i(-1,-1)
@export var surface_overrides: Dictionary = {}   # Vector2i -> SurfaceType int
@export var elevation_overrides: Dictionary = {} # Vector2i -> float
# Wind authored or seeded:
@export var wind_fixed: bool = false
@export var wind_direction_index: int = 0  # 0-7 (WindSystem.DIRECTIONS)
@export var wind_strength: int = 0         # 0-3
# Dealt hand authored or seeded:
@export var hand_definition: HandDefinition = null
```

`hex_grid` hole setup reads `HoleDefinition`: if `use_procedural`, call the existing
`generate_hole_with_par(par)` but with the RNG seeded from `seed`; else build the grid from
`grid_width/height` + apply `surface_overrides`/`elevation_overrides`, set `tee`/`flag`. Wind is
either forced from `wind_*` or generated from the seeded RNG. This is additive — procedural path
unchanged when no definition is supplied (default `HoleContext.definition = null`).

### 8.3 `HandDefinition` resource (NEW; reuses `DeckDefinition`)
`scripts/cards/hand_definition.gd` (`class_name HandDefinition`, extends `Resource`):

```
@export var club_deck: DeckDefinition = null     # falls back to swing_deck.tres
@export var modifier_deck: DeckDefinition = null # falls back to starter_deck.tres
@export var fixed_hand: bool = false             # true => deal exactly dealt_card_ids
@export var dealt_card_ids: Array[String] = []   # curated hand (resolved via CardLibrary)
@export var hand_size: int = 5                   # when not fixed, draw N from modifier_deck
@export var seed: int = 0                         # 0 => use HoleContext.rng
```

`CardSystemManager` gains a `deal_hand_for_hole(hand_def: HandDefinition, rng)` that either deals
`dealt_card_ids` verbatim (curated) or draws `hand_size` from the (seeded-shuffled) modifier
deck. `DeckDefinition.get_all_cards()` + `CardLibrary` already resolve ids → `CardData`. This
makes a curated "play THIS hole with THIS hand" trivially expressible later by authoring one
`HoleDefinition` with a `HandDefinition.fixed_hand = true` — no retrofit.

Default behavior (no definition): `use_procedural=true`, random seed, `hand_size=5`,
fallback decks — identical to today's feel but now seed-reproducible.

---

## 9. Turn-Loop Flow & Where Each Step Lives

A new thin controller **`scripts/turn_controller.gd`** (`class_name TurnController`, extends
`Node`, added as a child of `hex_grid` during `_init_card_system` wiring) owns the loop
sequencing and the footprint builder. It keeps `hex_grid` from growing and isolates the new
logic. It holds references to `shot_manager`, `card_system`, `aoe_system`, `wind_system`,
`lie_system`, `hole_context`, and the `hex_grid` as hole controller.

| # | Step | Owner / function |
|---|---|---|
| 1 | Read board (lie, wind, distance to flag) | `TurnController.begin_turn()` → reads `hex_grid.get_cell/elevation`, `LieSystem.calculate_lie`, `WindSystem` |
| 2 | Play one **Club card** | `CardSystemManager` (existing swing-card selection path, repurposed) → sets `ctx.band_*`, `base_spread`, `base_roll` from `CLUB_STATS` |
| 3 | Optionally play shot-shape/modifier cards | `CardSystemManager.activate_card_modifier` → `ModifierManager` applies effects to `ctx` at `apply_before_aim` |
| 4 | Aim one of 6 hex directions | `TurnController.set_aim_dir(dir)` → writes `ctx.aim_dir`, projects `center_tile`, calls `shot_manager.set_aim_target(center_tile)` |
| 5 | Board PREVIEWS the footprint | `TurnController.build_footprint(ctx)` → populates `ctx.aoe_tiles` + `ctx.aoe_weights`; `hex_grid.refresh_aoe_display()` renders it |
| 6 | Press **SHOOT** | NEW `ShootButton` (Section 10/14) → `TurnController.execute_shot()` → `shot_manager.confirm_shot()` |
| 7 | Ball resolves (carry+roll+wind+slope) → landing; scoring (chips×mult) as reward | `ShotManager._resolve_landing_tile` (weighted draw from footprint) + `TurnController.apply_board_resolution` (roll/slope/water/tree) + existing `_compute_scoring`; animation via existing `hex_grid._on_shot_completed` |
| repeat | until holed out | `hex_grid._start_new_shot()` (minus putting branch) → `TurnController.begin_turn()`; Flag hex → `_trigger_hole_complete()` |

The **footprint builder** (`TurnController.build_footprint`) is the heart. Pseudocode:

```
func build_footprint(ctx) -> void:
    var fwd = AOESystem._get_direction_offsets(ball.x % 2 == 1)[ctx.aim_dir]  # step vec
    # along-axis distance = band_center + distance_mod + elevation adj + wind head/tail
    var dist = ctx.band_center + ctx.distance_mod + elev_adjust(ctx) + wind_headtail(ctx)
    dist = clampi(dist, ctx.band_min, ctx.band_max + 2)   # mods can stretch a little
    var center = walk(ball_tile, ctx.aim_dir, dist)       # hex walk honoring parity
    center += perp(fwd) * (wind_shift(ctx) + draw_fade_shift(ctx))
    center = clamp_to_bounds(center)
    ctx.aim_tile = center
    var R = max(0, ctx.base_spread + ctx.spread_mod + lie_spread_mod(ctx))
    ctx.aoe_tiles = aoe_system.compute_circle_aoe(center, R, hex_grid)
    ctx.aoe_weights = {}
    for t in ctx.aoe_tiles:
        var d = hex_distance(center, t)
        var w = pow(R + 1 - d, ctx.falloff_pow) * terrain_factor(get_cell(t))
        ctx.aoe_weights[t] = max(w, MIN_WEIGHT)
```

`ShotManager._resolve_landing_tile` then draws from `ctx.aoe_weights` (it already prefers
`aoe_weights` when non-empty). The post-draw roll/slope/tree/water board resolution is applied in
`TurnController.apply_board_resolution` invoked from the `landing_resolved` signal (so it sits
inside the existing pipeline and the existing animation in `_on_shot_completed` plays the final
`landing_tile`).

Edge cases handled explicitly: aim into a wall (center clamps to bounds, footprint shrinks at
edge — fine); `R=0` (single-hex deterministic footprint); all-water footprint (draw still
returns a hex, water reposition fires); Putter off-green (Shoot disabled); ball already on Flag
(hole-out, no turn).

---

## 10. Retirement Plan (incremental, build-safe, ordered)

Each step compiles cleanly on its own. Replace behavior BEFORE deleting the thing it replaced.

**Step R0 — Add the replacement first (no removals).**
Add `ShootButton` to `scenes/ui/main_ui.tscn` (a clean `Button`, Section 14) and the new
`TurnController`. Wire `ShootButton.pressed → TurnController.execute_shot → shot_manager.confirm_shot()`.
At this point both the SpinMeter path and the Shoot button can confirm a shot. Build stays green.
*Files touched:* `scenes/ui/main_ui.tscn` (add node), `scripts/turn_controller.gd` (new),
`scripts/hex_grid.gd` (instantiate TurnController in `_init_card_system`),
`scripts/ui/main_ui.gd` (expose `shoot_button`).

**Step R1 — Route confirmation through TurnController only.**
Change `ShotUI._on_spin_confirmed` / `_on_swing_completed_with_spin` to no-op (or delegate to
`TurnController.execute_shot`). Disable/hide the SpinMeter and SwingMeter nodes (set
`visible=false`) but leave scripts in tree. Confirm the loop runs end-to-end via Shoot only.
*Signals touched:* `SpinMeter.spin_confirmed`, `SwingMeter.swing_completed` (disconnected from
the confirm path). *Files:* `scripts/shot_ui.gd`, `scenes/ui/main_ui.tscn` (visibility).

**Step R2 — Excise the real-time putting mini-game.**
In `hex_grid._start_new_shot`, remove the `should_putt`/`enter_putting_mode` branch so Green is a
normal lie where only the Putter club card is legal (lie table already restricts to PUTTER). Stop
instantiating `PuttingSystem` in `_init_putting_system`; remove `putting_system` field reads on
the shot path (`_start_new_shot`, the viewer setup). Putts now resolve as short Putter-card
shots through the same Shoot path.
*Files:* `scripts/hex_grid.gd` (remove putting branch + init), `scenes/*` none required.
After this step, `scripts/putting_system.gd` is unreferenced on the gameplay path.

**Step R3 — Convert wind to board modifier only (already mostly true).**
`WindSystem.calculate_wind_curve` is already a board (int) model. Remove any live-trajectory
wind application in the animation code if present (the flight animation uses
`_calculate_curved_target`/`wind_curve` already as a board offset, so verify and keep). No
live-physics wind exists to delete beyond confirming the footprint builder is the sole consumer.
*Files:* `scripts/hex_grid.gd` (verify flight anim reads resolved `landing_tile`, not live wind).

**Step R4 — Delete retired scripts/scenes (last, once unreferenced).**
Remove node instances from `scenes/ui/main_ui.tscn`: `SwingMeter`, `SpinMeterPanel`, `SpinMeter`,
and `SwingHand` (and the `swing_hand_3d` SubViewport wiring in `hex_grid._init_card_system`).
Then delete files: `scripts/swing_meter.gd`(+`.uid`), `scripts/spin_meter.gd`(+`.uid`),
`scripts/putting_system.gd`(+`.uid`), `scripts/swing_hand_3d.gd`(+`.uid`),
`scenes/ui/SwingMeter.tscn`, `scenes/ui/spin_meter.tscn`, and any swing-card-slot drag helpers
only those scenes used (`scripts/cards/swing_hand.gd`, `scripts/cards/swing_card_3d.gd`,
`scripts/cards/swing_slot_drag_strategy.gd`, `scripts/cards/modifier_card_3d.gd` — **verify no
other references first** with a grep; keep any still referenced). Remove now-dead references in
`shot_ui.gd` (`swing_meter`, `spin_meter`, `_setup_swing_meter`, `_setup_spin_meter`,
`_on_swing_completed*`, `_on_spin_confirmed`) and `card_system_manager.gd` (`swing_hand`,
`swing_hand_3d`, `_setup_swing_hand`, `_on_swing_slot_*`).
*Order within R4:* (a) delete scene node instances, (b) delete scene files, (c) delete scripts,
(d) delete dangling code references — recompile after each sub-step.

Removal order rationale: UI confirm replaced (R0–R1) → gameplay branches rerouted (R2–R3) →
only then delete now-orphaned code (R4), so the build is green throughout.

---

## 11. Keep & Repurpose Plan (exact seams)

- **Hex grid + procedural generation** (`scripts/hex_grid.gd`, `scenes/hole-generator.tscn`):
  KEEP. Touch only: add `HoleContext` ownership + seeded RNG reroute (8.1), apply
  `HoleDefinition` overrides (8.2), remove putting branch (R2), instantiate `TurnController`
  (R0). Do NOT split the file. Generation entry `generate_hole_with_par` unchanged except its
  RNG source.
- **Card data/effect/deck architecture** (`scripts/cards/`): KEEP. Repurpose: Club cards carry
  `target_club` and the footprint builder reads `CLUB_STATS[club].band_*`. Add new effect
  resources (Section 5). `CardSystemManager` gains `deal_hand_for_hole` (8.3) and keeps its
  modifier-wiring role; its swing-slot UI code is retired (R4). `DeckDefinition` reused as-is
  for seedable decks.
- **AOE system** (`scripts/aoe_system.gd`): REPURPOSED as the footprint system — now the
  centerpiece. `compute_circle_aoe` builds the spread; `_get_direction_offsets`/
  `_get_neighbor_in_direction` provide the 6-direction hex walk; `calculate_weights_by_terrain`
  retuned to the Section 2.5 factors. New weight-falloff lives in `TurnController.build_footprint`
  (keeps AOESystem a pure geometry helper).
- **Lie/terrain tables** (`scripts/lie_system.gd`): KEEP. Add `spread_mod` key to `LIE_DATA`
  (4.4/6) and re-enable terrain→spread feeding the footprint. `apply_lie_to_shot` still writes
  `distance_mod`/`roll_mod`/chips/mult.
- **Scoring engine** (`scripts/scoring_manager.gd`, `shot_context.gd`, `modifier_manager.gd`,
  `shot_manager.gd`): KEEP as the reward layer. `ShotManager` pipeline is the loop backbone
  (Section 9). `ShotContext` gains the new transient fields (2.4/5). `ScoringManager` computes
  `final_score = chips × mult` per shot via the existing `scoring_computed` phase; it is
  displayed, never gates. Modifier phases unchanged.

---

## 12. Main Scene Decision

Keep `scenes/GOLF.tscn` (`uid://i0lqex70w705`, root `scripts/hex_grid.gd`) as the run/main
scene. No new main scene is cleaner here because all gameplay systems already instantiate under
`hex_grid` and `main_ui` is already its child. `project.godot` `run/main_scene` stays
`uid://i0lqex70w705` — **no change required**. The only scene edits are inside `main_ui.tscn`
(add ShootButton + hand display, retire meter nodes) and adding `TurnController` under
`hex_grid` at runtime (no scene edit needed for that).

---

## 13. Art Direction (context, not this run's deliverable)

"Refined tabletop golf": premium board-game / classy-golf aesthetic — clean flat/soft-cel
low-poly, limited palette (deep greens, sand, cream, one brass/navy accent), beveled hex tiles;
no cute/mobile/toon styling. New UI (Shoot button, hand display, footprint preview) must be
clean and neutral: flat panels, the existing theme font (`theme/custom_font`), navy/cream with a
brass accent for the primary Shoot action. A full art pass is OUT OF SCOPE; use existing theme
and assets, no new art.

---

## 14. New UI (minimal, clean)

- **ShootButton:** a `Button` in `main_ui.tscn`, bottom-center, labeled "Shoot", primary accent
  (brass). Disabled until a legal Club card is played and an aim direction is set (and Putter
  legality holds). `pressed → TurnController.execute_shot`.
- **Hand display:** reuse the existing fanned-hand concept but as a flat 2D card strip (the 3D
  `SwingHand3D` is retired). For the first playable a simple `HBoxContainer` of card buttons
  (club row + modifier row) is sufficient and clean; clicking a card plays it. No decorative
  framing.
- **Footprint preview:** rendered by the existing `hex_grid.refresh_aoe_display()` tile
  highlights, brightness ∝ `aoe_weights` (brighter center = more likely), plus a distinct marker
  on `center_tile`. A small readout of wind (`WindSystem.get_display_text()`) and lie is enough.

These are neutral/functional, consistent with Section 13; no asset additions.

---

## 15. Verification Strategy (for the implementer)

**Clean build gate (every step):**
`/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only` over the project, and a
headless scene load of `scenes/GOLF.tscn` must report 0 script errors.

**Isolated headless harness (NEW, test-only):** add `scripts/tests/test_turn_loop.gd` + a tiny
`scenes/tests/test_turn_loop.tscn` run via
`Godot --headless scenes/tests/test_turn_loop.tscn` (or `--script`). The harness must, without
any real-time UI:
1. Build a hole from a FIXED `HoleDefinition` (small explicit grid: tee, straight fairway,
   green+flag, one bunker, one water, one tree) with a fixed `seed` — so results are
   reproducible (NFR3/AC6).
2. Deal a fixed hand via `HandDefinition.fixed_hand`.
3. Play a Club card → assert `ctx.band_*/base_spread/base_roll` set (AC3).
4. For each of the 6 `aim_dir`, call `build_footprint` → assert non-empty `aoe_tiles`,
   positive total weight, center along the direction within band (AC4).
5. Play "Tighten Spread" and "Ignore Wind" → assert spread shrinks / center wind-independent
   (AC5).
6. `execute_shot` with fixed seed twice → assert identical `landing_tile` (AC6); assert
   `get_tile_distance(landing, flag) <= get_tile_distance(start, flag)` for a straight clear
   tee shot (AC7); assert `final_score == round(chips*mult)` and no gate (AC8).
7. Drive the loop to the flag (script aim toward flag each turn) → assert
   `_trigger_hole_complete` fires exactly once (AC9) and the harness exits 0 (AC12).
8. Assert Putter rejected off-green and resolves on-green (AC10); assert water landing
   repositions + continues (AC11).

**Verifiable only by code reading / manual play (state explicitly in the PR):** the *feel* of
the weighting (is the variance fun), the live preview brightness mapping, camera/animation
polish, and the UI layout aesthetics. The harness proves the mechanics and determinism; it does
not prove feel.

**Cleanup:** the harness scene/script are test-only; keep them under `scripts/tests/` and
`scenes/tests/` and note they are not shipped content. Remove any scratch files created during
verification.

---

## 16. New Files / Edited Files Summary (for the planner)

**New:**
- `scripts/turn_controller.gd` (loop sequencing + footprint builder)
- `scripts/hole_context.gd` (seeded RNG + definition holder)
- `scripts/hole_definition.gd` (seedable/authorable hole resource)
- `scripts/cards/hand_definition.gd` (seedable/authorable hand resource)
- `scripts/cards/effects/effect_ignore_wind.gd`, `effect_tighten_spread.gd`, `effect_punch.gd`,
  `effect_flop.gd`, `effect_bump_run.gd`, `effect_stinger.gd` (new CardEffects)
- `scripts/tests/test_turn_loop.gd`, `scenes/tests/test_turn_loop.tscn` (harness)

**Edited (surgical):**
- `scripts/shot_context.gd` (add `aim_dir:int`, `band_min/max/center:int`, `base_spread:int`,
  `base_roll:int`, `spread_mod:int`, `falloff_pow:float`; extend `reset()`)
- `scripts/hex_grid.gd` (`CLUB_STATS` += `band_min/band_max/base_spread`; own `HoleContext`;
  seed RNG reroute on resolution path; apply `HoleDefinition`; remove putting branch;
  instantiate `TurnController`; add `ShootButton` wiring)
- `scripts/lie_system.gd` (`LIE_DATA` += `spread_mod`; retuned terrain values)
- `scripts/aoe_system.gd` (retune `calculate_weights_by_terrain` factors)
- `scripts/cards/card_library.gd` (consolidate 7 club cards to the Section 3 ids; register new
  effect-based cards)
- `scripts/cards/card_system_manager.gd` (add `deal_hand_for_hole`; retire swing-slot UI)
- `scripts/shot_ui.gd` (retire meters; route confirm to TurnController)
- `scripts/ui/main_ui.gd` + `scenes/ui/main_ui.tscn` (add ShootButton + 2D hand display; remove
  meter/swing-hand nodes)

**Deleted (R4, after unreferenced):** `scripts/swing_meter.gd`, `scripts/spin_meter.gd`,
`scripts/putting_system.gd`, `scripts/swing_hand_3d.gd`, `scenes/ui/SwingMeter.tscn`,
`scenes/ui/spin_meter.tscn`, and the swing-card-slot helpers once confirmed orphaned.

---

## 17. Assumptions

- A1. Clubs are a reusable "bag" within a hole (not a depleting pile) for the first playable;
  only shot/modifier cards deplete. This matches golf and the "full hand per hole" intent; the
  depleting-club variant can come later without schema change.
- A2. The 6 hex directions are the canonical aim input; the existing hover/lock-tile UI may be
  retained as a convenience that snaps to the nearest direction. The harness uses `aim_dir`
  directly.
- A3. Water is not weight-zeroed (factor 0.50) so adverse shots can still reach it and incur the
  reposition penalty — variance must remain real per the settled "not pure-deterministic" goal.
- A4. `ELEV_PER_HEX=0.6`, `SLOPE_THRESHOLD=0.25`, `FALLOFF_POW=1.0`, `HAND_SIZE=5`, bend=2,
  terrain factors — all are tuning constants, centralized (in `TurnController` consts /
  `LIE_DATA`) so they can be retuned without structural change.
- A5. `CLUB_STATS` keyed by `ClubType` remains the single numeric home for clubs; CLUB cards
  reference it by `target_club`, eliminating the current duplication.

If any assumption is wrong, the affected section is the only thing that changes — the
architecture (seeded HoleContext, footprint on ShotContext, pipeline seam) is unaffected.

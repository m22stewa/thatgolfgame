# Hex Golf Deckbuilder — Core Turn Loop Design (First Playable)

Status: DESIGN — REVISION 2 (no code in this step). Authored against the real codebase in
the `feature/gameloop-v1` worktree. Technology stack is **Godot 4.7.2 + GDScript** (locked;
`project.godot` `config/features` is `"4.7"`). The engine binary used for verification is
`/Applications/Godot.app/Contents/MacOS/Godot`.

> **Revision note.** This revision resolves all 13 findings in
> `.agents/tasks/design-review.md` / `design-verdict.json`. The point-by-point responses are in
> Section 18. Material corrections vs. revision 1: the real **12-club** roster is kept intact
> (no invented ids; a 7-id playable "bag" is a subset — Finding 1); reward scoring is attributed
> to `ShotContext.calculate_final_score()` driven by `ShotManager`, not `ScoringManager`
> (Finding 2); the footprint→`_resolve_landing_tile` hand-off, the seeded-RNG injection seams,
> the `apply_before_aim` timing/reset discipline, the `apply_board_resolution` ordering, the
> terrain-factor home, and the wind head/tail math are all pinned to named functions and fields
> (Findings 3–10).

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
state, NO stroke budget, NO score gate**. The reward score is `final_score = round(chips × mult)`
per shot, **computed by `ShotContext.calculate_final_score()`** (which literally does
`final_score = int(round(chips * mult))`), driven by `ShotManager._compute_scoring()` /
`_apply_modifiers_on_scoring()` at the `scoring_computed` / `modifiers_applied_on_scoring`
phases. It is **demoted to a reward/currency layer** — displayed, accumulated, never gates
anything. **`ScoringManager`'s separate `BASE_POINTS`/`consecutive_fairways`-streak model is OUT
of scope for the first playable** — it has no `chips`/`mult`/`final_score` concept and is not on
the resolution path; leave it unwired/ignored (do not try to make it compute the reward score).

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
- **Club roster — 12 clubs, verbatim from code (do NOT invent ids).** `hex_grid.gd` defines
  `enum ClubType { DRIVER, WOOD_3, WOOD_5, IRON_3, IRON_5, IRON_6, IRON_7, IRON_8, IRON_9,
  PITCHING_WEDGE, SAND_WEDGE, PUTTER }` (12 values) and a `CLUB_STATS` dict with **all 12 rows**
  keyed by `ClubType` (fields `name/distance/accuracy/roll/loft/arc_height/swing_difficulty/
  curve`). `CardLibrary._register_club_cards()` registers **12 CLUB cards**, one per type, with
  ids exactly: `club_driver(DRIVER), club_3wood(WOOD_3), club_5wood(WOOD_5), club_3iron(IRON_3),
  club_5iron(IRON_5), club_6iron(IRON_6), club_7iron(IRON_7), club_8iron(IRON_8),
  club_9iron(IRON_9), club_pw(PITCHING_WEDGE), club_sw(SAND_WEDGE), club_putter(PUTTER)`.
  `CLUB_STATS[ClubType.IRON_7]` is used as the fallback in ~10 `CLUB_STATS.get(club, fallback)`
  call sites in `hex_grid.gd`, so **IRON_7 (and every other enum value) must keep its CLUB_STATS
  row** — deleting any value breaks the clean build. The design therefore **keeps all 12
  `ClubType` values, all 12 `CLUB_STATS` rows, and all 12 club-card ids**; it extends every
  `CLUB_STATS` row with `band_min/band_max/base_spread` (Section 3) and defines a 7-id playable
  "bag" (Section 3/7) that is a *subset* mapped to real ids. `CLUB_STATS` stays the single
  numeric home; CLUB cards reference it by `target_club`.
- **Club-deck source.** `CardLibrary.get_club_deck()` (on `CardLibrary`, NOT `CardSystemManager`)
  returns the default club `CardInstance` set. The live club hand is driven by
  `CardSystemManager.club_deck_manager` (a `DeckManager`), initialized from
  `club_deck_definition` (`swing_deck.tres`) and falling back to `CardLibrary.get_club_deck()`.
  The new `deal_hand_for_hole` (Section 8.3) sources clubs from `club_deck_manager` /
  `CardLibrary.get_club_deck()` — there is no `CardSystemManager.get_club_deck()`.
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

AC8. `ShotContext.calculate_final_score()` yields `final_score == int(round(chips * mult))`,
computed by `ShotManager._compute_scoring`/`_apply_modifiers_on_scoring` and surfaced each shot;
it never blocks progression and no stroke/score gate exists. `ScoringManager` is not asserted
against (out of scope).

AC9. Landing the ball on the Flag hex triggers the existing hole-complete state exactly once
(`_trigger_hole_complete` guarded by `hole_complete_triggered`).

AC10. Putter is rejected unless the ball surface is Green; a Green ball resolves putts
through the same play-card then Shoot path (no real-time mini-game).

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
- `spread_mod:int` (default 0), `falloff_pow:float` (default 1.0) — NEW transient fields written
  by lie + shot-shape cards (Sections 4.4/5). Add to `ShotContext`.

The "footprint" = (`aoe_tiles` set + `center_tile` + `aoe_weights`). "Spread" = the shape/size
of `aoe_tiles` around `center_tile`. This is exactly the triple the concept calls for:
set of landing hexes + most-likely center + spread + weighting.

**Rebuild / reset contract (CRITICAL — the footprint is recomputed on every plan change).**
Lie and card effects are **additive** (`distance_mod += …`, `roll_mod += …`, `spread_mod -= 1`,
`falloff_pow += 0.5`, see `effect_simple_stat.gd` and `lie_system.apply_lie_to_shot`). Because
the footprint is rebuilt each time the plan changes (club played/removed, modifier played/removed,
aim changed), the transient mod fields MUST be reset to defaults before re-applying, or lie and
card mods double-count across re-previews. The contract, owned by `TurnController.rebuild()`:

1. `ctx.reset()` (zeroes `distance_mod/accuracy_mod/roll_mod/wind_curve`, clears `aoe_tiles/
   aoe_weights/path_tiles/metadata`, and — per the extended `reset()` in Section 16 — sets
   `spread_mod=0`, `falloff_pow=1.0`, `band_*`=0, `base_spread=0`, `base_roll=0`,
   `curve_strength=0.0`, `curve_profile=""`).
2. Re-apply the current lie via `LieSystem.apply_lie_to_shot(ctx, lie_info)`.
3. Re-write `band_min/band_max/band_center/base_spread/base_roll` from `CLUB_STATS[club]` for the
   currently-played Club card.
4. Re-apply every currently-played shot-shape/modifier card's effect by calling
   `ModifierManager.apply_before_aim(ctx)` (see Finding 6 / Section 9 for why this is re-invoked
   here rather than relying on the single `start_shot` call).
5. Project `center_tile` and call `TurnController.build_footprint(ctx)` (Section 9).

`ShotContext.reset()` therefore gains clearing of the new fields; confirm it sets `spread_mod=0`
and `falloff_pow=1.0` (not merely leaves them). This reset-then-reapply discipline is the single
source of idempotency for re-previews.

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
These factors live in a NEW `TurnController.terrain_factor(surface:int) -> float` method (a small
const table on `TurnController`), called by `build_footprint`. **Do NOT edit
`AOESystem.calculate_weights_by_terrain`** — it returns *absolute* weights (FAIRWAY=2.0,
GREEN=2.5, …), has no TEE/FLAG entries and no clamp, and the footprint builder never calls it; it
is left unused on the footprint path (it may stay for any legacy caller, but is not part of this
loop). The tuned multiplier table (these are MULTIPLIERS on `w(t)`):

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
(`terrain_factor` returns `max(raw, 0.30)`) — variance must stay real. TEE and FLAG entries
(absent from `calculate_weights_by_terrain`) are included here (`TEE=1.15`, `FLAG=1.40`).

**How cards narrow/bias the odds (summary; exact per-card in Section 5):**
- *Narrow:* reduce `effective_spread` (Tighten Spread −1) or raise `FALLOFF_POW` toward 2.0
  (concentrates weight on the center without shrinking the visible footprint). The two tools
  exist so "tighten" cards can either shrink the cloud or sharpen it.
- *Bias/shift:* move `center_tile` perpendicular to `aim_dir` (Draw/Fade) or along it
  (distance mods), which moves the whole cloud; terrain reweighting then re-biases toward good
  hexes.
- *Kill variance source:* Ignore Wind zeroes the wind shift of `center_tile` for that shot.

**The draw (and the surgical `ShotManager` change — Finding 3).** The footprint builder
(`TurnController.build_footprint`) populates `ctx.aoe_tiles` + `ctx.aoe_weights` and sets a flag
`ctx.add_metadata("footprint_built", true)`. But `ShotManager._resolve_landing_tile()` as written
would **overwrite** the builder's work: it calls `_calculate_curved_target()` (which re-applies
`distance_mod`, `curve_strength`, and `wind_curve` as perpendicular/axial offsets) and then
**rebuilds** `aoe_tiles` via `aoe_system.compute_aoe(target, radius, …)`, only afterwards calling
`_select_landing_tile_from_aoe`. That double-applies curve/wind (once in the builder's
`center_tile` shift, once here) and re-keys the tile set so `aoe_weights` keys may no longer
match → the weighting silently degrades to the `.get(tile, 1.0)` fallback.

**The required change:** in `_resolve_landing_tile()`, add an early branch — when
`current_context.get_metadata("footprint_built", false)` is true (equivalently
`current_context.aoe_weights.size() > 0`), **skip** `_calculate_curved_target()` AND the
`aoe_system.compute_aoe` rebuild entirely; set `current_context.landing_tile =
_weighted_tile_selection()` directly over the builder's `aoe_tiles`/`aoe_weights`, then
`landing_resolved.emit(current_context)`. On this path, `distance_mod`/`curve_strength`/
`wind_curve` are consumed **only** by the builder (they shaped `center_tile` and the disk), so
they are not applied again. The legacy path (no footprint flag) is left intact for safety.

The RNG inside `_weighted_tile_selection` / `_select_landing_tile_from_aoe` must be the single
seeded stream (Section 8 / Finding 4), not bare `randf()` — the exact field seam is specified in
Section 8.1 and Section 10 Step R3.

---

## 3. Clubs as Distance Bands (exact numbers)

Scale: **1 hex = 10 yards**. `distance`/`roll`/`spread` are in **hexes**. Bands are inclusive.
`band_center = round((band_min + band_max) / 2)`. These numbers are added as THREE NEW keys
(`band_min`, `band_max`, `base_spread`) to **every one of the 12 existing `CLUB_STATS` rows** in
`hex_grid.gd` (keyed by `ClubType`); `base_roll` reuses the existing `roll` key already in
`CLUB_STATS`. The 12 CLUB cards in `CardLibrary` keep their existing ids and reference the row by
`target_club`; they carry no duplicate numbers. **No club ids are invented and no `ClubType`
value is removed** (IRON_7 and the others remain the `CLUB_STATS.get(...)` fallback — Section 1 /
Finding 1).

**The first-playable "bag" is a 7-id SUBSET of the real 12**, chosen to span the concept's
seven conceptual slots (Driver / Fairway Wood / Long Iron / Mid Iron / Short Iron / Wedge /
Putter) using real ids and real `ClubType`s:

| Concept slot | Card id (REAL) | ClubType | band_min | band_max | band_center | base_spread (R) | base_roll (=`roll`) | Yardage | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Driver | `club_driver` | DRIVER | 22 | 26 | 24 | 3 | 3 | 220–260 | widest spread, hottest roll |
| Fairway Wood | `club_3wood` | WOOD_3 | 18 | 20 | 19 | 2 | 3 | 180–200 | |
| Long Iron | `club_3iron` | IRON_3 | 15 | 17 | 16 | 1 | 2 | 150–170 | narrow |
| Mid Iron | `club_6iron` | IRON_6 | 12 | 14 | 13 | 1 | 2 | 120–140 | narrow |
| Short Iron | `club_8iron` | IRON_8 | 9 | 11 | 10 | 1 | 1 | 90–110 | tight |
| Wedge | `club_pw` | PITCHING_WEDGE | 5 | 8 | 6 | 1 | 0 | 50–80 | tight, stops fast |
| Putter | `club_putter` | PUTTER | 1 | 4 | 2 | 0 | 1 | 10–40 | GREEN only; single-hex spread |

The 7-id bag is expressed as the default club `HandDefinition`/`swing_deck.tres` content
(Section 7/8.3). The other 5 `ClubType`s (`WOOD_5, IRON_5, IRON_7, IRON_9, SAND_WEDGE`) are NOT
in the bag but their `CLUB_STATS` rows **stay** (they are the fallback and are referenced by
legacy code). For completeness and so a curated hand could later deal them, extend their rows
too with sensible bands derived from their existing `distance` (`band_min/band_max/base_spread`):
`WOOD_5` 16–18 / R2; `IRON_5` 14–16 / R1; `IRON_7` 12–14 / R1; `IRON_9` 10–12 / R1;
`SAND_WEDGE` 4–7 / R1 (base_roll from each row's existing `roll`). These five are off-bag for the
first playable; only the 7 above are dealt.

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
Verified `WindSystem` API: `calculate_wind_curve(shot_direction: Vector2) -> int` returns
`clampi(round(wind_vec.cross(shot_vec) * strength), -strength, strength)` where
`wind_vec = DIRECTIONS[direction_index].normalized()` (the `.cross()` sign convention: **positive
= push to the right of the shot**); `get_direction_vector() -> Vector2` returns that same
normalized `wind_vec` (or `Vector2.ZERO` when wind disabled); `strength` is an int 0–3.
`calculate_wind_curve` returns ONLY the crosswind (lateral) component — it does not return a
head/tail term, so the builder computes head/tail itself from `get_direction_vector()` and
`strength`.

**`fwd` as a `Vector2` (the conversion — Finding 10).** The aim step vector from
`AOESystem._get_direction_offsets(ball.x % 2 == 1)[aim_dir]` is a parity-dependent hex offset
`Vector2i`. To feed it to `WindSystem` (whose `DIRECTIONS` live in a 2D screen convention where
the hole runs W→E and Y+ is down), convert via the **world-space** shot direction, which is
parity-independent and already available: compute
`world_delta = hole.get_tile_surface_position(center_tile) - hole.get_tile_surface_position(ball_tile)`
(a `Vector3`), then `shot_vec = Vector2(world_delta.x, world_delta.z).normalized()`. This matches
the convention `calculate_wind_curve` and `get_direction_vector` use (X across, Z/Y along the
hole). Use `shot_vec` for BOTH the cross and the dot below; do not hand-roll a hex→Vector2 map.

- **Crosswind (lateral):** `wind_shift = WindSystem.calculate_wind_curve(shot_vec)` → write to
  `ShotContext.wind_curve`. Apply as a perpendicular shift of `center_tile`:
  `center_tile += perp(fwd) * wind_shift`, where `perp(fwd)` is the hex-grid perpendicular step
  (the aim direction rotated one hex direction; `+wind_shift` = right of the shot, matching the
  `.cross()` sign).
- **Head/tail (axial):** `wind_vec = WindSystem.get_direction_vector()`;
  `head_tail = clampi(round(wind_vec.dot(shot_vec) * WindSystem.strength * 0.5), -2, 2)`. A
  tailwind (`dot > 0`) extends, a headwind shortens; add `head_tail` to the along-axis distance.
- **"Ignore Wind" / Stinger:** if `ctx.get_metadata("ignore_wind", false)`, set `wind_shift = 0`
  and `head_tail = 0` for that shot (checked in the builder before applying either term).

Wind is generated per hole via `WindSystem.generate_wind(difficulty, rng)` — see Finding 4 /
Section 8.1: `generate_wind` currently uses bare `randf()/randi()`; it gains an optional
`rng: RandomNumberGenerator = null` parameter and uses `rng.randf()/rng.randi()` when supplied
(falling back to the globals when null) so seeded/definition holes are reproducible.
`calculate_wind_curve` is already pure/deterministic given wind state and needs no RNG change.

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
chips/mult from `LIE_DATA` (it intentionally no longer feeds `accuracy_mod` into AOE). Keep it,
with these edits to `LIE_DATA` in `lie_system.gd`:
- Lie `distance_mod` (hexes along axis) and `roll_mod` stay as additive ints already consumed.
- **Re-enable terrain→spread as a NEW `spread_mod` key** (the old accuracy→AOE path is commented
  out). Add `spread_mod` to each `LIE_DATA` row and have `apply_lie_to_shot` write
  `context.spread_mod += lie_info.get("spread_mod", 0)`; the footprint builder reads
  `ctx.spread_mod`. Values: `TEE 0, FAIRWAY 0, ROUGH +1, DEEP_ROUGH +2, SAND +2, TREE +3,
  GREEN 0` (WATER/FLAG are not played from).

**`allowed_clubs` — verified real values (Finding 5).** The current `LIE_DATA.allowed_clubs`
sets (verbatim) are:
- `TEE`: `[DRIVER, WOOD_3, WOOD_5, IRON_3, IRON_5, IRON_6, IRON_7, IRON_8, IRON_9,
  PITCHING_WEDGE]` (note: SAND_WEDGE/PUTTER absent).
- `FAIRWAY`: `[WOOD_3, WOOD_5, IRON_3, IRON_5, IRON_6, IRON_7, IRON_8, IRON_9, PITCHING_WEDGE,
  SAND_WEDGE]` — **excludes DRIVER**.
- `ROUGH`: `[IRON_5, IRON_6, IRON_7, IRON_8, IRON_9, PITCHING_WEDGE, SAND_WEDGE]` — excludes
  DRIVER, all woods, and IRON_3.
- `DEEP_ROUGH` and `TREE`: `[IRON_7, IRON_8, IRON_9, PITCHING_WEDGE, SAND_WEDGE]`.
- `SAND`: `[SAND_WEDGE, PITCHING_WEDGE, IRON_9]`.
- `GREEN`: `[PUTTER]`. `WATER`/`FLAG`: `[]`.

**Retune for the 7-club bag (edit `LIE_DATA.allowed_clubs` so the legality gate matches the bag
and Section 6 prose).** Because the bag is `{DRIVER, WOOD_3, IRON_3, IRON_6, IRON_8,
PITCHING_WEDGE, PUTTER}`, rewrite `allowed_clubs` to the intersection-plus-intent below (keeping
the off-bag ids in the lists is harmless since they are never dealt, but these are the
authoritative retuned sets):
- `TEE`: `[DRIVER, WOOD_3, IRON_3, IRON_6, IRON_8, PITCHING_WEDGE]` (all bag clubs except Putter).
- `FAIRWAY`: `[WOOD_3, IRON_3, IRON_6, IRON_8, PITCHING_WEDGE]` (no Driver, no Putter).
- `ROUGH`: `[IRON_3, IRON_6, IRON_8, PITCHING_WEDGE]` (no Driver, no Wood).
- `DEEP_ROUGH` / `TREE`: `[IRON_6, IRON_8, PITCHING_WEDGE]`.
- `SAND`: `[PITCHING_WEDGE, IRON_8]`.
- `GREEN`: `[PUTTER]`. `WATER`/`FLAG`: `[]`.

The Shoot-button legality gate (Section 7) reads `ctx.get_metadata("allowed_clubs")` (set by
`apply_lie_to_shot`) and additionally enforces Putter-only-on-GREEN explicitly.

---

## 5. Advantage / Shot-Shape Cards (exact mechanical effects)

Each is a `CardData` (`card_type = SHOT`) composed of existing or new `CardEffect` resources.
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
| **Draw** | bend footprint left: `center_tile += perp(fwd) * -DRAW_BEND`; `DRAW_BEND=2` | existing `EffectCurveShot(curve_direction=Draw)` → writes `curve_strength` negative + `curve_profile="draw"`; builder reads `round(curve_strength)` as the perp hex shift |
| **Fade** | bend right: `center_tile += perp(fwd) * +FADE_BEND`; `FADE_BEND=2` | existing `EffectCurveShot(curve_direction=Fade)` → writes `curve_strength` positive + `curve_profile="fade"` |
| **Bump-and-run** | low carry, big roll: along-axis distance = `band_min`, `roll_mod += 3`, `spread_mod -1` | NEW `EffectBumpRun` |
| **Stinger** | low + wind-immune + long roll: `metadata["ignore_wind"]=true`, `roll_mod += 2`, along-axis distance += 1, `spread_mod -1` | NEW `EffectStinger` |

New transient `ShotContext` fields these require: `spread_mod: int`, `falloff_pow: float`
(default 1.0), plus the existing `roll_mod`, `distance_mod`, `curve_strength`, `curve_profile`,
`wind_curve`, `metadata`. `EffectCurveShot`'s real enum is `("Draw","Fade","Random","Hook",
"Slice")`; use `Draw`/`Fade` (Draw writes negative `curve_strength`/`profile="draw"`, Fade
positive/`"fade"`). The **builder** reads `round(curve_strength)` as a perpendicular hex shift of
`center_tile` (Draw left, Fade right). Because `_resolve_landing_tile`'s curve path
(`_calculate_curved_target`) is **bypassed** when a footprint is pre-built (Finding 3 / Section
2.5), the Draw/Fade shift is applied exactly once (in the builder), never doubled.

Validation of card effects: all values are authored constants in the effect resources; no
external input. The only runtime input is which cards the player plays and the aim direction
(both constrained — Section 7).

---

## 6. Terrain Outcome Modifiers (exact)

Golf reframing of the hex terrain. Values consolidated so one table drives legality, spread,
roll, reposition, and scoring. Authoritative home: `LieSystem.LIE_DATA` (lie/start effects) +
Section 4.2 `terrain_roll` (landing effects) + the footprint terrain factors (Section 2.5). The
scoring chips/mult below live on `LIE_DATA` (start) and `ScoringManager.BASE_POINTS` (landing).

Legality reflects the **retuned `LIE_DATA.allowed_clubs`** from Section 4.4 against the 7-club
bag (`DRIVER, WOOD_3=3wood, IRON_3=3iron, IRON_6=6iron, IRON_8=8iron, PITCHING_WEDGE=pw, PUTTER`):

| Surface | Playable from (bag clubs) | spread_mod (as lie) | terrain_roll (as landing) | footprint factor | Special |
|---|---|---|---|---|---|
| TEE | Driver, 3W, 3i, 6i, 8i, PW (not Putter) | 0 | 0 | 1.15 | start-of-hole |
| FAIRWAY | 3W, 3i, 6i, 8i, PW (NOT Driver, not Putter) | 0 | 0 | 1.15 | ideal |
| ROUGH | 3i, 6i, 8i, PW (no Driver, no Wood) | +1 | −1 | 0.90 | distance_mod −2 (lie) |
| DEEP_ROUGH | 6i, 8i, PW | +2 | −2 | 0.75 | distance_mod −4 (lie) |
| SAND/Bunker | PW, 8i | +2 | −3 | 0.60 | distance_mod −6 (lie) |
| WATER | none | — | — | 0.50 | **penalty + reposition** (below) |
| TREE | 6i, 8i, PW (restricted) | +3 | −2 | 0.45 | **blocks high shots**; only Punch/Stinger pass (else landing stopped short, below) |
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

**Deal full hand per hole.** At hole start (tee), `CardSystemManager.deal_hand_for_hole` deals:
- **Club hand (the 7-id bag):** sourced from `CardSystemManager.club_deck_manager` (initialized
  from `club_deck_definition = swing_deck.tres`, falling back to `CardLibrary.get_club_deck()` —
  NOT a nonexistent `CardSystemManager.get_club_deck()`; `get_club_deck()` lives on
  `CardLibrary`). The bag is the 7 real ids from Section 3 (`club_driver, club_3wood, club_3iron,
  club_6iron, club_8iron, club_pw, club_putter`). Clubs are **reusable within a hole** (a club
  card is not consumed, it is selected per shot) — a "bag," not a depleting pile. This matches
  real golf and keeps the one-hole loop playable. (The shipped `swing_deck.tres` may still list
  all 12 ids; the first-playable bag is enforced by the default club `HandDefinition` (Section
  8.3) listing the 7, or by filtering at deal time.)
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

**The injection seam (exact — Finding 4).** Neither `ShotManager` nor `WindSystem` has an RNG
field today; they call bare `randf()/randi()`. Add a nullable field to each and set it from
`HoleContext.rng` when the hole is created (in `hex_grid`'s hole setup, right after
`hole_context.rng` is seeded):

- **`ShotManager`:** add `var rng: RandomNumberGenerator = null`. `hex_grid`/`TurnController`
  sets `shot_manager.rng = hole_context.rng`. Replace the bare `randf()` in **both**
  `_weighted_tile_selection()` and `_select_landing_tile_from_aoe()` with
  `(rng.randf() if rng else randf())`. These are the only two RNG calls on the landing-draw path
  (the footprint-built fast path added in Section 2.5 only reaches `_weighted_tile_selection`).
- **`WindSystem`:** change `generate_wind(difficulty: float = 0.5)` to
  `generate_wind(difficulty: float = 0.5, rng: RandomNumberGenerator = null)` and replace its
  three bare calls — `randf()` (the `wind_chance` roll), `randi() % 8` (direction), and
  `randf_range(min,max)` (speed) — with `rng`-driven equivalents when `rng != null`
  (`rng.randf()`, `rng.randi() % 8`, `rng.randf_range(min,max)`); fall back to the globals when
  null. `calculate_wind_curve` is already deterministic given wind state and needs no change.
- **`TurnController` slope nudge** (Section 4.3) is specified deterministic (no RNG) for the
  first playable, so it needs no seam; if it later becomes probabilistic it must use
  `hole_context.rng`.

With these three call sites rerouted, a fixed `seed` + fixed card plays + fixed `aim_dir`
reproduces the exact landing hex (AC6/NFR3).

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
| 2 | Play one **Club card** | `CardSystemManager` club-selection path, repurposed → `TurnController.rebuild()` writes `ctx.band_*`, `base_spread`, `base_roll` from `CLUB_STATS[club]` |
| 3 | Optionally play shot-shape/modifier cards | `CardSystemManager.activate_card_modifier` → `TurnController.rebuild()` re-applies lie + all played effects (via `ModifierManager.apply_before_aim(ctx)`) to a freshly-reset `ctx` |
| 4 | Aim one of 6 hex directions | `TurnController.set_aim_dir(dir)` → writes `ctx.aim_dir`, calls `rebuild()` which projects `center_tile` and `shot_manager.set_aim_target(center_tile)` |
| 5 | Board PREVIEWS the footprint | `TurnController.build_footprint(ctx)` (called at the end of `rebuild()`) → populates `ctx.aoe_tiles` + `ctx.aoe_weights` + `metadata["footprint_built"]=true`; `hex_grid.refresh_aoe_display()` renders it |
| 6 | Press **SHOOT** | NEW `ShootButton` (Section 10/14) → `TurnController.execute_shot()` → `shot_manager.confirm_shot()` |
| 7 | Ball resolves (carry+roll+wind+slope) → landing; scoring (chips×mult) as reward | `ShotManager._resolve_landing_tile` (footprint-built fast path: weighted draw only — Section 2.5/Finding 3) → `landing_resolved` → `TurnController.apply_board_resolution` mutates `ctx.landing_tile` (roll/tree/water/slope) → `_simulate_ball_path` (rebuilds `path_tiles` from final landing) → `_compute_scoring` → `calculate_final_score()`; cosmetic animation via `hex_grid._on_shot_completed` |
| repeat | until holed out | `hex_grid._start_new_shot()` (minus putting branch) → `TurnController.begin_turn()`; Flag hex → `_trigger_hole_complete()` |

**Turn-order vs. `apply_before_aim` timing (Finding 6).** `ShotManager.start_shot()` calls
`_apply_modifiers_before_aim()` exactly once, *before* `shot_started` is emitted — i.e. before
the player has played any card this turn. The design does NOT rely on that single call to carry
card effects. Instead, `TurnController` owns a `rebuild()` method that runs the full
reset-then-reapply contract (Section 2.4) and is **re-invoked on every plan change** (club
played/removed, modifier played/removed, aim changed). `rebuild()` itself calls
`ModifierManager.apply_before_aim(ctx)` after `ctx.reset()` + lie + club, so `ctx` always
reflects the *current* plan before `build_footprint`. `start_shot` may still run at
`begin_turn()` to initialize the context and shot_index; its one-time `apply_before_aim` is
harmless because `rebuild()` resets and re-applies anyway. This removes any dependency on
card-play happening before `start_shot`.

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

On the footprint-built fast path (Section 2.5 / Finding 3), `_resolve_landing_tile` draws the
raw landing hex directly from `ctx.aoe_weights` via `_weighted_tile_selection()` and emits
`landing_resolved` — it does NOT rebuild tiles or re-apply curve/wind.

**Board-resolution ordering (Finding 8 — must mutate `landing_tile` before scoring).**
`ShotManager.confirm_shot()` runs its phases **synchronously** in one call:
`_resolve_landing_tile()` (emits `landing_resolved`) → `_simulate_ball_path()` →
`_compute_scoring()`. Godot signal emission is synchronous, so a handler connected to
`landing_resolved` runs *before* `_simulate_ball_path`/`_compute_scoring`. The design relies on
this: `TurnController.apply_board_resolution(ctx)` is connected to `landing_resolved` and, during
that synchronous callback, **rewrites `ctx.landing_tile` in place** by applying roll-out (4.2),
tree-block (6), green slope nudge (4.3), and water-stop in this fixed order. Because
`_simulate_ball_path()` then rebuilds `ctx.path_tiles` from `start_tile → (final) landing_tile`
and `_compute_scoring()` scores over `path_tiles` + landing terrain, scoring sees the fully
board-resolved landing. **Scoring-relevant landing is fixed synchronously here.** The purely
cosmetic water splash+return animation in `hex_grid._handle_water_hazard()` (which is
`await`-driven) runs **later** in `hex_grid._on_shot_completed`; `apply_board_resolution` only
sets `ctx.landing_tile` to the reposition tile and `metadata["hit_water"]=true` synchronously so
scoring and the next turn's start tile are correct regardless of animation timing.

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
  `_get_neighbor_in_direction` provide the 6-direction hex walk. The weight falloff AND the
  terrain factors both live in `TurnController.build_footprint` / `TurnController.terrain_factor`
  (keeps AOESystem a pure geometry helper). **`calculate_weights_by_terrain` is left unedited and
  unused on the footprint path** (it returns absolute weights with no TEE/FLAG and no clamp —
  Finding 9); do not retune it.
- **Lie/terrain tables** (`scripts/lie_system.gd`): KEEP. Add `spread_mod` key to `LIE_DATA`
  (4.4/6) and re-enable terrain→spread feeding the footprint. `apply_lie_to_shot` still writes
  `distance_mod`/`roll_mod`/chips/mult.
- **Scoring engine** (`shot_context.gd`, `shot_manager.gd`, `modifier_manager.gd`): KEEP as the
  reward layer. `ShotManager` pipeline is the loop backbone (Section 9). `ShotContext` gains the
  new transient fields (2.4/5). **The reward score is `ShotContext.calculate_final_score()`**
  (`final_score = int(round(chips * mult))`), driven by `ShotManager._compute_scoring` at the
  `scoring_computed` phase and `_apply_modifiers_on_scoring` at `modifiers_applied_on_scoring`;
  `chips`/`mult` are seeded by `_compute_scoring` + `_apply_terrain_scoring` + lie + card effects.
  It is displayed, never gates. Modifier phases unchanged.
- **`ScoringManager`** (`scripts/scoring_manager.gd`): **OUT of scope for the first playable.**
  It uses an unrelated `BASE_POINTS` / `consecutive_fairways`-streak model with no
  `chips`/`mult`/`final_score` concept and is not on the resolution path. Leave it unwired/ignored
  (reused later with the run/shop layer). Do NOT route the reward score through it.

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
3. Play a Club card (a real bag id, e.g. `club_driver` → `ClubType.DRIVER`) → assert
   `ctx.band_min/band_max/band_center/base_spread/base_roll` set from `CLUB_STATS[DRIVER]` (AC3).
4. For each of the 6 `aim_dir`, call `build_footprint` → assert non-empty `aoe_tiles`,
   positive total weight, center along the direction within band (AC4).
5. Play "Tighten Spread" and "Ignore Wind" → assert spread shrinks / center wind-independent
   (AC5).
6. Set `shot_manager.rng` and the wind rng from a fixed `HoleContext.rng`, `execute_shot`
   twice → assert identical `landing_tile` (AC6); assert
   `get_tile_distance(landing, flag) <= get_tile_distance(start, flag)` for a straight clear
   tee shot (AC7); assert `ctx.calculate_final_score() == int(round(ctx.chips * ctx.mult))` and
   that nothing gates progression (AC8). Do NOT assert against `ScoringManager`.
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
- `scripts/shot_context.gd` (add `aim_dir:int`, `band_min/band_max/band_center:int`,
  `base_spread:int`, `base_roll:int`, `spread_mod:int`, `falloff_pow:float`; extend `reset()` to
  zero the ints, set `falloff_pow=1.0`, clear `curve_strength/curve_profile`)
- `scripts/hex_grid.gd` (extend **all 12** `CLUB_STATS` rows with `band_min/band_max/base_spread`
  — do NOT remove any `ClubType` value; own `HoleContext`; set `shot_manager.rng` + pass rng to
  `WindSystem.generate_wind`; apply `HoleDefinition`; remove putting branch; instantiate
  `TurnController`; add `ShootButton` wiring)
- `scripts/shot_manager.gd` (add `var rng: RandomNumberGenerator`; use `rng` in
  `_weighted_tile_selection`/`_select_landing_tile_from_aoe`; add the footprint-built fast-path
  branch in `_resolve_landing_tile` that skips `_calculate_curved_target`+`compute_aoe` rebuild —
  Finding 3)
- `scripts/wind_system.gd` (add optional `rng` param to `generate_wind`; route its 3 bare RNG
  calls through it — Finding 4)
- `scripts/lie_system.gd` (`LIE_DATA` += `spread_mod` key written by `apply_lie_to_shot`; retune
  `allowed_clubs` to the bag per Section 4.4; retune terrain values)
- `scripts/aoe_system.gd` (**no change** — `calculate_weights_by_terrain` is left unused on the
  footprint path; the terrain factors live on `TurnController.terrain_factor` — Finding 9)
- `scripts/cards/card_library.gd` (KEEP all 12 club cards; the 7-id bag is a subset configured in
  the default `HandDefinition`/`swing_deck.tres`; register the new effect-based shot-shape cards
  from Section 5)
- `scripts/cards/card_system_manager.gd` (add `deal_hand_for_hole(hand_def, rng)` sourcing clubs
  from `club_deck_manager`/`CardLibrary.get_club_deck()`; retire swing-slot UI)
- `scripts/shot_ui.gd` (retire meters; route confirm to `TurnController`)
- `scripts/ui/main_ui.gd` + `scenes/ui/main_ui.tscn` (add ShootButton + 2D hand display; remove
  `SwingMeter`/`SpinMeterPanel`/`SpinMeter`/`SwingHand` nodes)

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

---

## 18. Responses to Design Review Findings

Verdict addressed: `design-verdict.json` = CHANGES_REQUESTED, 13 findings (4 HIGH, 6 MEDIUM, 3
NIT). Every finding is ADDRESSED (none backlogged or ignored). The reviewer's code reads were
re-verified against the worktree sources before editing.

- **F1 [HIGH] Club roster is 12, not 7 — ADDRESSED.** Took the reviewer's preferred option. All
  12 `ClubType` values and 12 `CLUB_STATS` rows are kept (IRON_7 etc. remain the ~10×
  `CLUB_STATS.get(...)` fallback); all 12 club-card ids are kept. No ids invented. The playable
  bag is a 7-id SUBSET mapped to real ids (`club_driver→DRIVER, club_3wood→WOOD_3,
  club_3iron→IRON_3, club_6iron→IRON_6, club_8iron→IRON_8, club_pw→PITCHING_WEDGE,
  club_putter→PUTTER`). Section 1 + Section 3 rewritten; off-bag rows given bands too. (Sections
  1, 3, 7, 16.)

- **F2 [HIGH] Scoring misattributed — ADDRESSED.** Reward score is now attributed to
  `ShotContext.calculate_final_score()` (`int(round(chips*mult))`) driven by
  `ShotManager._compute_scoring`/`_apply_modifiers_on_scoring`. `ScoringManager`'s
  BASE_POINTS/streak model declared OUT of scope/unwired. (Sections 0, 2.3 AC8, 11, 15.)

- **F3 [HIGH] Footprint overwrite + curve/wind double-apply — ADDRESSED.** Specified the surgical
  `_resolve_landing_tile` fast-path branch guarded on `metadata["footprint_built"]`
  (equivalently `aoe_weights.size() > 0`): skip `_calculate_curved_target` AND the `compute_aoe`
  rebuild, draw directly via `_weighted_tile_selection`. `distance_mod/curve_strength/wind_curve`
  consumed only by the builder on this path. (Sections 2.5, 5, 9, 16.)

- **F4 [HIGH] Seeded-RNG injection seam — ADDRESSED.** Added `var rng: RandomNumberGenerator` to
  `ShotManager` (set from `HoleContext.rng`) replacing the bare `randf()` in
  `_weighted_tile_selection` and `_select_landing_tile_from_aoe`; added optional `rng` param to
  `WindSystem.generate_wind` routing its three bare `randf()/randi()/randf_range` calls. Slope
  nudge is deterministic (no RNG). (Sections 4.1, 8.1, 16.)

- **F5 [MEDIUM] Club legality vs real `allowed_clubs` — ADDRESSED.** Quoted the real
  `LIE_DATA.allowed_clubs` sets verbatim (FAIRWAY excludes DRIVER; ROUGH starts IRON_5;
  DEEP_ROUGH/TREE at IRON_7; SAND = SW/PW/IRON_9) and gave the retuned sets reconciled with the
  7-club bag. Section 6's "Playable from" column rewritten to match. (Sections 4.4, 6.)

- **F6 [MEDIUM] `apply_before_aim` timing — ADDRESSED.** Specified `TurnController.rebuild()`
  re-invokes `ModifierManager.apply_before_aim(ctx)` (after `ctx.reset()` + lie + club) on every
  plan change, so `ctx` reflects the current plan before `build_footprint`; no dependence on the
  single `start_shot` call. (Sections 2.4, 9.)

- **F7 [MEDIUM] Additive-mod accumulation / reset discipline — ADDRESSED.** Defined the explicit
  reset-then-reapply rebuild contract; `ShotContext.reset()` extended to zero `spread_mod` and
  set `falloff_pow=1.0` (plus band fields and curve fields). (Sections 2.4, 16.)

- **F8 [MEDIUM] `apply_board_resolution` ordering before scoring — ADDRESSED.** Stated that
  `apply_board_resolution` runs on the synchronous `landing_resolved` callback and rewrites
  `ctx.landing_tile` in place (roll/tree/water/slope) BEFORE `_simulate_ball_path` rebuilds
  `path_tiles` and `_compute_scoring` runs; cosmetic water animation deferred to
  `_on_shot_completed`. (Section 9.)

- **F9 [MEDIUM] `calculate_weights_by_terrain` contract — ADDRESSED.** Terrain factors moved to
  `TurnController.terrain_factor()` (multiplier table incl. TEE/FLAG + 0.30 clamp); the
  instruction to edit `calculate_weights_by_terrain` is removed and the function marked unused on
  the footprint path. (Sections 2.5, 11, 16.)

- **F10 [MEDIUM] Wind head/tail data + fwd→Vector2 + seeded wind — ADDRESSED.** Head/tail now uses
  `WindSystem.get_direction_vector()` + `WindSystem.strength` for the dot; `shot_vec` is derived
  from the world-space `get_tile_surface_position` delta (parity-independent, matching the
  WindSystem convention), and the `.cross()` sign (positive = right) is stated; seeded wind via
  the `rng` param (ties to F4). (Section 4.1.)

- **F11 [NIT] `EffectCurveShot` enum — ADDRESSED.** Draw/Fade used (real enum
  Draw/Fade/Random/Hook/Slice); writes `curve_strength` (neg=draw/left, pos=fade/right) +
  `curve_profile`; builder reads `round(curve_strength)` once, ShotManager curve path bypassed
  (F3). (Section 5.)

- **F12 [NIT] `get_club_deck()` home — ADDRESSED.** Clarified `get_club_deck()` is on
  `CardLibrary`; `deal_hand_for_hole` sources clubs from `club_deck_manager` /
  `CardLibrary.get_club_deck()`, not a nonexistent `CardSystemManager.get_club_deck()`. (Sections
  1, 7, 8.3, 16.)

- **F13 [NIT] Version string, glyphs, typo — ADDRESSED.** Header now says Godot 4.7.2
  (`config/features` `"4.7"`); AC9/AC10 non-ASCII glyphs removed; Section 5 `/ää` typo removed.

# Implementation Plan — Hex Golf Deckbuilder Core Turn Loop (First Playable)

Source of truth: `.agents/tasks/gameloop-design.md` (DESIGN REVISION 2, APPROVED) and its review
`.agents/tasks/design-review.md`. This plan sequences that design into build-safe, ordered steps.
Work in the worktree `/Users/m22stewa/Documents/Godot/Golf/.worktrees/gameloop` on branch
`feature/gameloop-v1`. Stack: Godot 4.7.2 + GDScript. Engine binary:
`/Applications/Godot.app/Contents/MacOS/Godot`.

## Clean-build invariant (applies to EVERY step)

Every step must leave the project loading headless with 0 NEW script errors. Run after each step:

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/m22stewa/Documents/Godot/Golf/.worktrees/gameloop --quit-after 600 2>&1 | grep -iE "error|not found|null|invalid|nonexistent" | grep -viE "shader|vulkan|rendering device|headless"
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/m22stewa/Documents/Godot/Golf/.worktrees/gameloop --editor --quit 2>&1 | grep -iE "SCRIPT ERROR|parse error"
```

Accepted baseline: the 2 pre-existing font errors on `main` (missing `uid://csixfh5trj68q`) are NOT
script errors — do not chase them, but do not add new errors. Grep checks are not verification; the
two commands above plus the harness (step 15) are the verification of record.

## The FIVE PINNED RESOLUTIONS (mandatory, non-negotiable; these override any looser design prose)

These are baked into the steps below and restated verbatim here so no implementer can miss them:

- **R#1 SCORING BASIS.** Scoring is a demoted, non-gating reward layer. Reward chips derive from the
  AIMED CENTER distance via the existing `ShotContext.get_shot_distance()` (`start_tile`→`aim_tile`)
  — do NOT re-derive chips from `landing_tile`. Landing TERRAIN is scored on the board-resolved
  landing hex (which is rewritten synchronously before `_compute_scoring`, so this works).
  `scripts/shot_manager.gd` `_simulate_ball_path` STAYS a 2-tile stub (`[start_tile, landing_tile]`);
  per-hex carry-path terrain scoring is OUT OF SCOPE. Any design prose implying carry-path terrain
  affects the score is superseded by this.
- **R#2 ROLL/TREE/WATER WALK.** The board-resolution step (`apply_board_resolution` on the
  `landing_resolved` callback) reconstructs the roll line itself because no `ShotContext` field
  carries the intermediate hexes. Reconstruct by stepping
  `AOESystem._get_neighbor_in_direction(tile, ctx.aim_dir, tile.x % 2 == 1)` exactly `roll` times
  starting from the drawn landing hex, RECOMPUTING parity (`is_odd = tile.x % 2 == 1`) at EACH step
  from the current tile, stopping before out-of-bounds, stopping before a WATER hex, and (for
  non-Punch/non-Stinger shots) stopping before a TREE hex. Punch/Stinger pass through TREE. This
  walk mutates `ctx.landing_tile` in place before scoring.
- **R#3 FOOTPRINT FAST-PATH TRIGGER.** In `scripts/shot_manager.gd` `_resolve_landing_tile`, gate the
  surgical fast-path (which SKIPS both `_calculate_curved_target` AND the `compute_aoe(target_tile,…)`
  rebuild, preserving the TurnController-built `aoe_tiles` + `aoe_weights`) on the metadata flag
  `ctx.metadata["footprint_built"]` ALONE. Do NOT use `aoe_weights.size() > 0` as a trigger or alias —
  stale weights can persist across phases and cause false positives. `ShotContext.reset()` clears this
  via `metadata.clear()`, which is the intended reset. Correct causal note: the legacy path breaks
  because `compute_aoe(target_tile,…)` RE-KEYS `aoe_tiles` so the builder's `aoe_weights` keys no
  longer match (collapsing to uniform via the `.get(tile, 1.0)` fallback) — NOT because a weights
  branch is missing (the legacy `_select_landing_tile_from_aoe` already honors weights).
- **R#4 CLUB BAND vs LEGACY distance INVARIANT.** Enforce `band_center == CLUB_STATS[club].distance`
  for every club. Where the band table in the design diverges from the existing `.distance` value,
  UPDATE `.distance` to equal `band_center` as part of the same `CLUB_STATS` row edit (e.g. Driver:
  set `distance` to match `band_center` 24, or adjust `band_center` to 22 — pick so the playable bag
  feels right, but they MUST be equal). This keeps the ~10 legacy call sites that read
  `CLUB_STATS[...].distance` (`get_current_club_distance`, `get_max_reachable_club`, bounce/carry math
  at hex_grid.gd lines ~2784 and ~3589, range preview) consistent with the footprint builder. Do not
  leave Driver (or any club) desynced. Decision for this plan: **set `CLUB_STATS[DRIVER].distance = 24`
  to match `band_center = 24`** (the hotter driver reads well); for all other bag clubs choose
  `band_center = .distance` and set bands around it (see step 2).
- **R#5 WIND SIGN + perp CONVENTION.** Define `perp(fwd)` by hex index: for a shot whose dominant hex
  direction is `d` (0..5 per `AOESystem._get_direction_offsets`, 0=Up..5=Up-Left), `+wind_shift` uses
  hex direction `(d+2)%6` and `-wind_shift` uses `(d+4)%6`. A harness assertion (step 15) must prove a
  known crosswind pushes the footprint center to the expected side for a fixed tee shot, so the sign
  is a tested fact, not an assumption.

**Finding 7 (NIT) cleanliness:** when retiring swing-hand pieces, treat the 2D `SwingHand`
(`scenes/ui/swing_hand.tscn` / `scripts/cards/swing_hand.gd`) and the `SwingHand3D` SubViewport chain
(`scripts/swing_hand_3d.gd`, reached by the absolute node path
`/root/GOLF/Control/MainUI/SwingHand/SubViewportContainer/SubViewport/SwingHand3D` in
`hex_grid._init_card_system`) as TWO SEPARATE retirements, and grep for all references to each before
removing.

## Scope fences (carry into every step)

No fail state; holed-out is the only win. Scoring computed but demoted to a reward layer; do NOT route
it through `ScoringManager` (its `BASE_POINTS`/streak model is out of scope, left unwired). Do NOT
build shop/run/9-hole layer. Do NOT restructure/split the 6924-line `scripts/hex_grid.gd` for
cleanliness — only surgical changes the loop requires. Do NOT touch `models/`, `textures/`, `theme/`,
`addons/`, `assets/`, `.md` docs, or `.github/` except for genuine new-UI asset wiring. New UI is
clean/neutral ("refined tabletop golf"); a full art pass is OUT OF SCOPE. Keep the project's existing
GDScript patterns. Main scene stays `scenes/GOLF.tscn` (`uid://i0lqex70w705`); `project.godot`
`run/main_scene` is unchanged.

---

# Implementation Plan

- [ ] 1. Extend `ShotContext` with the new transient footprint fields and extend `reset()`.
      Add `aim_dir:int=0`, `band_min:int=0`, `band_max:int=0`, `band_center:int=0`, `base_spread:int=0`,
      `base_roll:int=0`, `spread_mod:int=0`, `falloff_pow:float=1.0`. Extend `reset()` to zero all the
      new ints, set `falloff_pow=1.0`, and (already present but confirm) clear `curve_strength=0.0` and
      `curve_profile=""`. Leave `get_shot_distance()` (aim_tile-based — R#1) and
      `calculate_final_score()` (`int(round(chips*mult))`) UNCHANGED.
      Files: `scripts/shot_context.gd`
      Verify: both headless commands above report 0 new script errors; scene loads clean.

- [ ] 2. Extend all 12 `CLUB_STATS` rows in `hex_grid.gd` with `band_min`/`band_max`/`base_spread` and
      enforce the R#4 invariant.
      Add the three keys to every one of the 12 `ClubType` rows (do NOT remove any `ClubType` value —
      IRON_7 etc. remain the `CLUB_STATS.get(club, CLUB_STATS[ClubType.IRON_7])` fallback at ~10 sites).
      Bag-7 bands (from design §3): DRIVER 22–26 center 24 R3; WOOD_3 18–20 center 19 R2; IRON_3 15–17
      center 16 R1; IRON_6 12–14 center 13 R1; IRON_8 9–11 center 10 R1; PITCHING_WEDGE 5–8 center 6 R1;
      PUTTER 1–4 center 2 R0. Off-bag rows get sensible bands too (WOOD_5 16–18 R2; IRON_5 14–16 R1;
      IRON_7 12–14 R1; IRON_9 10–12 R1; SAND_WEDGE 4–7 R1). `base_roll` reuses the existing `roll` key.
      **R#4:** for each row set `distance == band_center`. Specifically set `CLUB_STATS[DRIVER].distance = 24`
      (was 22). For the other bag clubs pick `band_center` to equal the existing `.distance` where the
      design table already matches (WOOD_3 20→band 18–20 center 19: adjust to center 20 OR set distance 19 —
      pick equal; follow the design's listed centers and set `.distance` to that center). Verify after the
      edit that NO club has `distance != band_center`.
      Files: `scripts/hex_grid.gd`
      Verify: both headless commands report 0 new script errors; add a transient debug assert loop (removed
      before commit) OR confirm by reading that every row's `distance == band_center`. The step-15 harness
      asserts `ctx.band_center == CLUB_STATS[DRIVER].distance`.

- [ ] 3. Add the seeded-RNG seam to `ShotManager` and `WindSystem`.
      `ShotManager`: add `var rng: RandomNumberGenerator = null`; replace the bare `randf()` in BOTH
      `_weighted_tile_selection()` and `_select_landing_tile_from_aoe()` with `(rng.randf() if rng else randf())`.
      `WindSystem`: change `generate_wind(difficulty: float = 0.5)` to
      `generate_wind(difficulty: float = 0.5, rng: RandomNumberGenerator = null)` and route its three bare
      calls — `randf()` (wind_chance), `randi() % 8` (direction), `randf_range(min,max)` (speed) — through
      `rng` when non-null, falling back to the globals when null. `calculate_wind_curve` and
      `get_direction_vector` need no RNG change.
      Files: `scripts/shot_manager.gd`, `scripts/wind_system.gd`
      Verify: both headless commands report 0 new script errors. (Determinism proven in step 15.)

- [ ] 4. Add the footprint fast-path branch to `ShotManager._resolve_landing_tile` (R#3).
      Add an EARLY branch: if `current_context.get_metadata("footprint_built", false)` is true, skip
      `_calculate_curved_target()` AND the `aoe_system.compute_aoe(...)` rebuild entirely; set
      `current_context.landing_tile = _weighted_tile_selection()` over the builder's existing
      `aoe_tiles`/`aoe_weights`, then `landing_resolved.emit(current_context)` and return. Gate on the
      `footprint_built` metadata flag ALONE (NOT `aoe_weights.size() > 0`). Leave the legacy path intact
      below for safety. Add a brief comment stating the correct causal note from R#3 (compute_aoe re-keys
      the tile set).
      Files: `scripts/shot_manager.gd`
      Verify: both headless commands report 0 new script errors. (Behavior proven in step 15.)

- [ ] 5. Extend `LieSystem.LIE_DATA` with `spread_mod` and retune `allowed_clubs` for the 7-club bag.
      Add a `spread_mod` key to each `LIE_DATA` row: TEE 0, FAIRWAY 0, ROUGH +1, DEEP_ROUGH +2, SAND +2,
      TREE +3, GREEN 0 (WATER/FLAG unused). Have `apply_lie_to_shot` write
      `context.spread_mod += lie_info.get("spread_mod", 0)` (the old accuracy→AOE path stays commented out).
      Retune `allowed_clubs` to the bag (design §4.4): TEE `[DRIVER,WOOD_3,IRON_3,IRON_6,IRON_8,PITCHING_WEDGE]`;
      FAIRWAY `[WOOD_3,IRON_3,IRON_6,IRON_8,PITCHING_WEDGE]`; ROUGH `[IRON_3,IRON_6,IRON_8,PITCHING_WEDGE]`;
      DEEP_ROUGH/TREE `[IRON_6,IRON_8,PITCHING_WEDGE]`; SAND `[PITCHING_WEDGE,IRON_8]`; GREEN `[PUTTER]`;
      WATER/FLAG `[]`. Keep `apply_lie_to_shot` still writing `distance_mod`/`roll_mod`/chips/mult and
      `allowed_clubs` to metadata.
      Files: `scripts/lie_system.gd`
      Verify: both headless commands report 0 new script errors.

- [ ] 6. Add the new seedable content resources: `HoleContext`, `HoleDefinition`, `HandDefinition`.
      `scripts/hole_context.gd` (`class_name HoleContext extends RefCounted`): `seed:int`,
      `rng:RandomNumberGenerator`, `definition:HoleDefinition=null`. `scripts/hole_definition.gd`
      (`class_name HoleDefinition extends Resource`) with the exported fields in design §8.2
      (`hole_id/seed/par/use_procedural/grid_width/grid_height/tee/flag/surface_overrides/elevation_overrides/
      wind_fixed/wind_direction_index/wind_strength/hand_definition`). `scripts/cards/hand_definition.gd`
      (`class_name HandDefinition extends Resource`) with design §8.3 fields (`club_deck/modifier_deck/
      fixed_hand/dealt_card_ids/hand_size/seed`).
      Files: `scripts/hole_context.gd`, `scripts/hole_definition.gd`, `scripts/cards/hand_definition.gd`
      Verify: both headless commands report 0 new script errors (new `class_name` types parse and register).

- [ ] 7. Add the new shot-shape `CardEffect` resources and register the shot-shape cards in `CardLibrary`.
      New effect scripts under `scripts/cards/effects/`: `effect_ignore_wind.gd` (sets
      `metadata["ignore_wind"]=true`), `effect_tighten_spread.gd` (`spread_mod -= 1`, `falloff_pow += 0.5`),
      `effect_punch.gd` (`metadata["punch"]=true`, `roll_mod += 1`, `spread_mod -= 1`, cap along-axis distance
      to `band_center`), `effect_flop.gd` (along-axis = `band_min`, `roll_mod -= 99`, `spread_mod -= 1`),
      `effect_bump_run.gd` (along-axis = `band_min`, `roll_mod += 3`, `spread_mod -= 1`),
      `effect_stinger.gd` (`metadata["ignore_wind"]=true`, `roll_mod += 2`, along-axis += 1, `spread_mod -= 1`).
      Each extends `CardEffect` and writes at `apply_before_aim`. Reuse existing `EffectSimpleStat` for
      Roll +2 / Soft Landing and existing `EffectCurveShot` (Draw=negative `curve_strength`/`"draw"`,
      Fade=positive/`"fade"`) for Draw/Fade. Register the new SHOT cards in `CardLibrary` (keep all 12 club
      cards untouched). Builder reads `round(curve_strength)` as a perpendicular hex shift (applied once,
      since the ShotManager curve path is bypassed — R#3).
      Files: `scripts/cards/effects/effect_ignore_wind.gd`, `.../effect_tighten_spread.gd`,
      `.../effect_punch.gd`, `.../effect_flop.gd`, `.../effect_bump_run.gd`, `.../effect_stinger.gd`,
      `scripts/cards/card_library.gd`
      Verify: both headless commands report 0 new script errors; the new card ids resolve via `CardLibrary`.

- [ ] 8. Create `TurnController` with the footprint builder, terrain factors, and board-resolution.
      `scripts/turn_controller.gd` (`class_name TurnController extends Node`), added as a child of
      `hex_grid` during `_init_card_system`. Implement: `begin_turn()`, `rebuild()` (the reset→lie→club→
      `ModifierManager.apply_before_aim(ctx)`→project center→`build_footprint` contract from design §2.4/§9),
      `set_aim_dir(dir)`, `build_footprint(ctx)` (design §9 pseudocode: along-axis dist with
      `distance_mod`+elevation+wind head/tail clamped to band, center walk honoring parity via
      `AOESystem._get_neighbor_in_direction`, perp shift for wind+draw/fade using R#5 `perp(fwd)` =
      `(d+2)%6` for +shift / `(d+4)%6` for −shift, `compute_circle_aoe` disk, linear falloff
      `pow(R+1-d, falloff_pow) * terrain_factor(...)`, set `metadata["footprint_built"]=true`),
      `terrain_factor(surface)->float` (const multiplier table incl. TEE=1.15/FLAG=1.40, clamped
      `max(raw,0.30)`; do NOT touch `AOESystem.calculate_weights_by_terrain`), `execute_shot()` →
      `shot_manager.confirm_shot()`, and `apply_board_resolution(ctx)` connected to `landing_resolved`
      implementing the **R#2** roll/tree/water walk (step `_get_neighbor_in_direction` `roll` times from the
      drawn landing hex, recomputing parity each step, stop before OOB/WATER, stop before TREE unless
      Punch/Stinger), plus the deterministic green slope nudge (design §4.3), mutating `ctx.landing_tile`
      in place BEFORE `_simulate_ball_path`/`_compute_scoring`. Wind: `wind_shift` from
      `calculate_wind_curve(shot_vec)` (shot_vec from world-space `get_tile_surface_position` delta),
      head/tail from `get_direction_vector().dot(shot_vec)*strength*0.5` clamped [-2,2]; `ignore_wind`
      metadata zeroes both. Honor R#1: builder/center drive `aim_tile`, so `get_shot_distance()` chips come
      from the aimed center; landing terrain scored on the resolved hex.
      Files: `scripts/turn_controller.gd`
      Verify: both headless commands report 0 new script errors (class parses; not yet wired into the loop).

- [ ] 9. [Retirement R0] Add the ShootButton and wire TurnController into `hex_grid` — ADD BEFORE REMOVE.
      Add a clean `Button` "Shoot" (brass accent, bottom-center) to `scenes/ui/main_ui.tscn`; expose it in
      `scripts/ui/main_ui.gd` as `shoot_button`. In `hex_grid._init_card_system`, instantiate `TurnController`
      as a child and give it refs to `shot_manager`, `card_system`, `aoe_system`, `wind_system`, `lie_system`,
      `hole_context`, and `hex_grid`; connect `shot_manager.landing_resolved → TurnController.apply_board_resolution`.
      Wire `ShootButton.pressed → TurnController.execute_shot → shot_manager.confirm_shot()`. Both the legacy
      SpinMeter path and the Shoot button can confirm at this point — build stays green.
      Files: `scenes/ui/main_ui.tscn`, `scripts/ui/main_ui.gd`, `scripts/hex_grid.gd`
      Verify: both headless commands report 0 new script errors; scene loads with the new button present.

- [ ] 10. Own `HoleContext` in `hex_grid`, seed the RNG, and apply `HoleDefinition`; deal the hand.
      In `hex_grid` hole setup: create a `HoleContext`, seed `rng.seed` from the definition seed (or random),
      set `shot_manager.rng = hole_context.rng`, and pass `hole_context.rng` to `WindSystem.generate_wind`.
      If `definition.use_procedural` is false, build the grid from `grid_width/height` + apply
      `surface_overrides`/`elevation_overrides` + set tee/flag; else run existing `generate_hole_with_par`
      with the seeded RNG (additive; procedural path unchanged when `definition == null`). Add
      `CardSystemManager.deal_hand_for_hole(hand_def, rng)` sourcing clubs from `club_deck_manager` /
      `CardLibrary.get_club_deck()` (NOT a nonexistent `CardSystemManager.get_club_deck()`) and drawing
      `hand_size` modifier cards from `starter_deck.tres` (or dealing `dealt_card_ids` verbatim when
      `fixed_hand`). Clubs are a reusable bag (not consumed); modifier cards deplete.
      Files: `scripts/hex_grid.gd`, `scripts/cards/card_system_manager.gd`
      Verify: both headless commands report 0 new script errors; scene generates a hole with reachable
      `flag_position` and a dealt hand (AC1/AC2).

- [ ] 11. Route the turn loop through `TurnController` (club select → modifiers → aim → preview → Shoot).
      Repurpose the club-selection path and `CardSystemManager.activate_card_modifier` to call
      `TurnController.rebuild()` on every plan change; map the 6-direction aim to `TurnController.set_aim_dir`
      (keyboard/edge-click; the existing hover/lock tile may remain as a snap-to-nearest convenience). After
      `rebuild()`, `hex_grid.refresh_aoe_display()` renders the footprint (brightness ∝ `aoe_weights`, marker
      on center). Enforce Shoot-button legality: disabled until a legal club for the current lie is played and
      an aim is set; Putter only on GREEN (read `ctx.get_metadata("allowed_clubs")` + explicit Putter-on-GREEN
      guard).
      Files: `scripts/turn_controller.gd`, `scripts/hex_grid.gd`, `scripts/cards/card_system_manager.gd`,
      `scripts/ui/main_ui.gd`
      Verify: both headless commands report 0 new script errors; manual/headless: playing a club then pressing
      Shoot resolves a landing and advances the loop.

- [ ] 12. [Retirement R1] Route confirmation through TurnController ONLY; hide the meters.
      Change `ShotUI._on_spin_confirmed` / `_on_swing_completed_with_spin` to no-op or delegate to
      `TurnController.execute_shot`; disconnect `SpinMeter.spin_confirmed` / `SwingMeter.swing_completed` from
      the confirm path. Set `SwingMeter`/`SpinMeter`/`SpinMeterPanel` nodes `visible=false` in
      `main_ui.tscn` (scripts stay in tree for now).
      Files: `scripts/shot_ui.gd`, `scenes/ui/main_ui.tscn`
      Verify: both headless commands report 0 new script errors; the loop runs end-to-end via Shoot only.

- [ ] 13. [Retirement R2] Excise the real-time putting mini-game.
      In `hex_grid._start_new_shot`, remove the `should_putt = ball_surface == GREEN` →
      `putting_system.enter_putting_mode()` branch so GREEN is a normal lie where only the Putter club card
      is legal (lie table already restricts to PUTTER). Stop instantiating `PuttingSystem` in
      `_init_putting_system`; remove `putting_system` field reads on the shot path. Putts now resolve as short
      Putter-card shots through the Shoot path. Keep `_trigger_hole_complete`/`hole_complete_triggered` and
      the ball-on-flag check intact.
      Files: `scripts/hex_grid.gd`
      Verify: both headless commands report 0 new script errors; GREEN ball resolves a putt via Shoot;
      ball-on-flag still triggers hole complete exactly once. (`scripts/putting_system.gd` now unreferenced.)

- [ ] 14. [Retirement R3] Confirm wind is board-modifier-only (no live-trajectory wind).
      Verify the flight animation in `hex_grid` reads the resolved `landing_tile` (board offset), not live
      per-frame wind; the footprint builder is the sole consumer of wind for resolution. Remove any live
      wind application found; otherwise this is a verify-and-document step.
      Files: `scripts/hex_grid.gd` (only if live wind application is found)
      Verify: both headless commands report 0 new script errors; shot animation targets the resolved landing.

- [ ] 15. Add the isolated headless test harness and prove the full loop + R#5 crosswind sign + determinism.
      Create `scripts/tests/test_turn_loop.gd` + `scenes/tests/test_turn_loop.tscn` (test-only; not shipped).
      Build a hole from a FIXED small `HoleDefinition` (tee, straight fairway, green+flag, one bunker, one
      water, one tree) with a fixed `seed`. Deal a fixed hand via `HandDefinition.fixed_hand`. Assert:
      (AC3) playing `club_driver` sets `ctx.band_*`/`base_spread`/`base_roll` from `CLUB_STATS[DRIVER]` and
      `ctx.band_center == CLUB_STATS[DRIVER].distance` (R#4);
      (AC4) each of 6 `aim_dir` yields non-empty `aoe_tiles`, positive total weight, center along the
      direction within band;
      (AC5) Tighten Spread shrinks/concentrates the footprint; Ignore Wind makes the center wind-independent;
      (**R#5**) a fixed crosswind on a fixed tee shot pushes `center_tile` to the EXPECTED side (hex dir
      `(d+2)%6` for +shift) — assert the center moved to that side, not the opposite;
      (AC6) with fixed seed + fixed plays + fixed aim, two `execute_shot` runs produce an IDENTICAL
      `landing_tile`;
      (AC7) `get_tile_distance(landing, flag) <= get_tile_distance(start, flag)` for a straight clear tee shot;
      (AC8) `ctx.calculate_final_score() == int(round(ctx.chips * ctx.mult))` and nothing gates progression
      (do NOT assert against `ScoringManager`);
      (AC9) driving aim toward the flag each turn reaches the flag and `_trigger_hole_complete` fires exactly
      once; harness exits 0 (AC12);
      (AC10) Putter rejected off-GREEN, resolves on-GREEN; (AC11) water landing repositions and the loop
      continues.
      Files: `scripts/tests/test_turn_loop.gd`, `scenes/tests/test_turn_loop.tscn`
      Verify: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/m22stewa/Documents/Godot/Golf/.worktrees/gameloop scenes/tests/test_turn_loop.tscn` runs all assertions and exits 0; both
      clean-build commands report 0 new script errors.

- [ ] 16. [Retirement R4] Delete the retired meter/putting/swing-hand scripts and scenes (last, once orphaned).
      Order within this step, recompiling after each sub-step: (a) grep for all references to each target
      (treat the 2D `SwingHand`=`swing_hand.tscn`/`scripts/cards/swing_hand.gd` and the `SwingHand3D`
      SubViewport chain=`scripts/swing_hand_3d.gd` at the absolute path in `_init_card_system` as TWO SEPARATE
      retirements — Finding 7); (b) remove node instances from `main_ui.tscn` (`SwingMeter`, `SpinMeterPanel`,
      `SpinMeter`, `SwingHand`) and the `SwingHand3D` wiring in `hex_grid._init_card_system`; (c) delete scene
      files `scenes/ui/SwingMeter.tscn`, `scenes/ui/spin_meter.tscn`; (d) delete scripts
      `scripts/swing_meter.gd`(+`.uid`), `scripts/spin_meter.gd`(+`.uid`), `scripts/putting_system.gd`(+`.uid`),
      `scripts/swing_hand_3d.gd`(+`.uid`), and the swing-card-slot helpers (`scripts/cards/swing_hand.gd`,
      `scripts/cards/swing_card_3d.gd`, `scripts/cards/swing_slot_drag_strategy.gd`,
      `scripts/cards/modifier_card_3d.gd`) ONLY if the grep in (a) confirms they are orphaned — keep any still
      referenced; (e) remove dangling references in `shot_ui.gd` (`swing_meter`/`spin_meter`/`_setup_*`/
      `_on_swing_completed*`/`_on_spin_confirmed`) and `card_system_manager.gd` (`swing_hand`/`swing_hand_3d`/
      `_setup_swing_hand`/`_on_swing_slot_*`).
      Files: `scenes/ui/main_ui.tscn`, `scripts/hex_grid.gd`, `scripts/shot_ui.gd`,
      `scripts/cards/card_system_manager.gd`, plus deleted files above
      Verify: both clean-build commands report 0 new script errors after EACH sub-step; the step-15 harness
      still passes end-to-end.

## What can only be verified by reading code / manual play (state in the PR)

The *feel* of the weighted variance (is it fun), the live preview brightness mapping, camera/animation
polish, and UI layout aesthetics. The harness proves mechanics, determinism (AC6/NFR3), and the R#5
crosswind sign; it does not prove feel. WCAG/accessibility of the new UI is not validated here.

## Sequencing rationale (how the five resolutions are ordered)

Schema first (steps 1–2: `ShotContext` fields + `CLUB_STATS` bands with **R#4** enforced), then the
resolution seams in isolation (step 3 seeded RNG, step 4 **R#3** fast-path, step 5 lie spread/legality).
Then the new data types (step 6) and cards (step 7). The builder and board-resolution (step 8) carry
**R#1** (aim-based chips), **R#2** (roll/tree/water walk), and **R#5** (perp/wind sign) in one coherent
unit. Retirement is strictly add-before-remove (step 9 adds Shoot+TurnController; 10–11 wire the loop;
12 routes confirm through TurnController and hides meters; 13 excises putting; 14 confirms board-only
wind) so the headless build never breaks. The harness (step 15) proves the full loop, determinism, and
the **R#5** crosswind sign before the final deletions (step 16), which only remove now-orphaned code with
a grep guard (Finding 7 two-retirement split). Every step leaves the project buildable.

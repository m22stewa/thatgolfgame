# Hex-based deckbuilding golf: core turn loop (feature/gameloop-v1)

Retires the old real-time swing/spin/putting/wind-physics flows and replaces them with a turn-based, card-driven loop: deal a hand per hole, play a club (a distance band) plus shot-shape/modifier cards, aim one of six hex directions, preview a weighted "footprint" landing disk, press Shoot, resolve the ball on the board (carry + roll + wind + slope), score on a demoted reward layer, and hole out. Built across four features (foundation seams → footprint engine + harness → live wiring + grep-guarded retirements → convergence/cleanup) from the approved design, carrying five pinned resolutions and Finding 7 verbatim. All four FEAT files are marked `completed` and record both clean-build commands at 0 new script errors (baseline: the 2 accepted pre-existing font errors for `uid://csixfh5trj68q`) and the headless harness at 40 checks / 0 failures / exit 0.

Watch for: nothing blocking. The live end-to-end loop through `hex_grid.gd` is proven only to the extent that GOLF.tscn loads headless with 0 script errors (AC1) plus the isolated harness over a faithful `StubHole`; the live deal→shoot→hole-out path and the footprint's visual/feel qualities are code-reading/manual-only, as the FEAT-004 note states (possible, by design). The orphaned `shot_panel.gd`/`shot_panel.tscn` pair and a null-but-declared `putting_system` field survive as dead-but-safe code (confirmed, intentional, out of scope).

**Verdict**: APPROVED

## High-level view

The five pinned resolutions are implemented exactly as specified. R#1: `build_footprint` sets `ctx.aim_tile = center` and `ShotContext.get_shot_distance()` still measures start→aim, so reward chips derive from the aimed center while landing terrain is scored on the board-resolved hex; `_simulate_ball_path` remains the 2-tile `[start, landing]` stub. R#2: `apply_board_resolution` reconstructs the roll line by stepping `AOESystem._get_neighbor_in_direction` exactly `roll` times from the drawn landing hex, recomputing parity each step, stopping before OOB/WATER and (for non-Punch/non-Stinger) before TREE, then a deterministic green-slope nudge, mutating `ctx.landing_tile` in place before scoring. R#3: `_resolve_landing_tile`'s fast-path gates on `metadata["footprint_built"]` alone and skips both `_calculate_curved_target` and `compute_aoe`; `ShotContext.reset()` clears the flag via `metadata.clear()`. R#4: every one of the 12 CLUB_STATS rows has `distance == band_center` (Driver 24, etc.); CLUB_STATS carries no `band_center` key, so TurnController reads `distance` as the center — the invariant holds by construction. R#5: `_apply_perp_shift` uses hex dir `(d+2)%6` for `+wind_shift` and `(d+4)%6` for `-wind_shift`, and the harness asserts the crosswind sign on both signs.

Finding 7 is satisfied as two separate, grep-guarded retirements: the 2D SwingHand (`scripts/ui/swing_hand.gd` + `scenes/ui/swing_hand.tscn`) and the SwingHand3D SubViewport chain (`scripts/swing_hand_3d.gd` + its card-slot scenes/strategy) are both deleted in the diff with `.uid` sidecars. A worktree-scoped grep finds no dangling code references to either — only documentation comments remain, plus a null-safe `putting_system` field and the out-of-scope `shot_panel` pair.

The core loop is wired end to end and both the hand and the hole are seed/definition-drivable. `HoleContext`/`HoleDefinition`/`HandDefinition` resources exist; `hex_grid` seeds `hole_context.rng`, feeds it to `shot_manager.rng` and `WindSystem.generate_wind`, and `CardSystemManager.deal_hand_for_hole` can deal fixed or seeded hands. The procedural-generation path is untouched: `_apply_hole_definition_overrides` returns early when `definition == null or use_procedural`.

Scope held. The diff touches no `models/`, `textures/`, `theme/`, `addons/`, `assets/`, or `.github/` paths; the only `.md` changes are the task's own design/plan docs under `.agents/tasks/`. No fail state, stroke budget, or score gate is wired into the new core files, and `ScoringManager` is not routed. Scoring is `int(round(chips * mult))` with nothing gating progression (AC8). `hex_grid.gd` is edited surgically (additive bands, new fields, guarded seams), not restructured.

<details>
<summary>Issues (0)</summary>

No blocking or non-blocking action items. The items in "Watch for" are informational: live end-to-end and feel/visual qualities are manual/code-reading-only by design, and the dead-but-safe `shot_panel`/`putting_system` residue is intentional and out of scope.

</details>

<details>
<summary>Details</summary>

### R#1 scoring basis — aimed center, not landing

`TurnController.build_footprint` sets `ctx.aim_tile = center` (the projected footprint center) before building the disk, and `ShotContext.get_shot_distance()` measures `start_tile → aim_tile`. `_compute_scoring` reads `base_chips = int(distance * 5)` from that aimed distance, so reward chips come from the aimed center as pinned. Landing terrain is scored separately over `path_tiles`, and `path_tiles` is `[start_tile, landing_tile]` — the board-resolved landing hex (mutated in place by `apply_board_resolution`). `_simulate_ball_path` is left as the 2-tile stub with no change (confirmed).

### R#2 roll / tree / water walk

`apply_board_resolution` computes `roll = max(0, base_roll + roll_mod + _terrain_roll(landing_surface))`, then steps `AOESystem._get_neighbor_in_direction(tile, ctx.aim_dir, tile.x % 2 == 1)` up to `roll` times from the drawn landing hex. Parity (`is_odd`) is recomputed inside the loop at each step (confirmed). It breaks before out-of-bounds, before WATER, and before TREE unless `passes_tree` (`metadata["punch"] or metadata["stinger"]`) — matching "Punch/Stinger pass through TREE". A deterministic green-slope nudge (steepest neighbor drop > 0.25, ties broken by direction order) follows, water is tagged with `metadata["hit_water"]`, and `ctx.landing_tile` is mutated in place before `_simulate_ball_path`/`_compute_scoring`. The harness directly exercises the non-punch tree stop, the punch pass-through, and the water stop.

### R#3 footprint fast-path trigger

`_resolve_landing_tile` opens with `if current_context.get_metadata("footprint_built", false):` → select via `_weighted_tile_selection()` over the pre-built `aoe_tiles`/`aoe_weights`, emit `landing_resolved`, return — skipping `_calculate_curved_target` and the `compute_aoe` rebuild. The gate is the flag alone; the comment correctly explains why `aoe_weights.size() > 0` is not the trigger (stale weights persist across phases). The `aoe_weights.size() > 0` check that remains at `_select_landing_tile_from_aoe` is inside the legacy branch, not the fast-path trigger. `ShotContext.reset()` clears the flag via `metadata.clear()`, and `build_footprint` sets it last.

### R#4 club band vs legacy distance invariant

All 12 CLUB_STATS rows satisfy `distance == band_center`: Driver 24 (22–26), 3-Wood 19 (18–20), 5-Wood 17 (16–18), 3-Iron 16 (15–17), 5-Iron 15 (14–16), 6-Iron 13 (12–14), 7-Iron 13 (12–14), 8-Iron 10 (9–11), 9-Iron 11 (10–12), Pitching Wedge 6 (5–8), Sand Wedge 6 (4–7), Putter 2 (1–4). The rows carry no explicit `band_center` key; `_write_band_from_club` reads `band_center` with a `distance` fallback, so the invariant holds by construction for every club including Driver. The ~10 legacy `CLUB_STATS.get(...).distance` sites now read these centers; no `ClubType` value was removed (IRON_7 fallback intact). The harness asserts the invariant for Driver against the real constant map.

### R#5 wind sign + perp convention

`_apply_perp_shift` computes `perp_dir := (d + 2) % 6 if perp_shift > 0 else (d + 4) % 6` for dominant direction `d`, then walks `abs(perp_shift)` steps. `perp_shift = wind_shift + round(curve_strength)`, and `wind_shift` comes from `WindSystem.calculate_wind_curve`. The harness carries the crosswind-sign assertion for both signs: it reconstructs the expected perp walk from the calm center and asserts the windy center landed on the expected side and not the opposite, then mirrors the wind and confirms the sign flips and still lands on the `(d+2)%6` side for the positive shift.

### Finding 7 — two separate swing-hand retirements

The diff deletes, with `.uid` sidecars, the SwingHand3D SubViewport chain (`scripts/swing_hand_3d.gd`, `scenes/swing_hand_3d.tscn`, `scripts/cards/swing_card_3d.gd`, `scenes/cards/swing_card_3d.tscn`, `scripts/cards/swing_slot_drag_strategy.gd`) and the 2D SwingHand (`scripts/ui/swing_hand.gd`, `scenes/ui/swing_hand.tscn`) as two distinct retirements, alongside the meter retirements (`swing_meter.gd`, `spin_meter.gd`, their scenes) and `putting_system.gd`. A worktree-scoped grep for every retired basename finds no live code reference: the only hits are doc-comments in `hex_grid.gd` and `card_system_manager.gd`, the out-of-scope `shot_panel.gd`/`shot_panel.tscn` (self-contained `SpinMeterContainer` nodes and a stale comment, no dependency on deleted files), and a null-safe `putting_system: Node` field whose init is a no-op so every guarded read is inert. No `preload`/`load`/`ext_resource` in the worktree points at a deleted path. (The broad grep's many hits against retired files were all in the main worktree, i.e. the base branch, not this feature branch.)

### End-to-end wiring + seed/definition drivability

`hex_grid` owns `turn_controller`, `hole_context`, `shoot_button`, and `current_aim_dir`; `_init_card_system` instantiates TurnController, wires its collaborator refs, connects `shot_manager.landing_resolved → apply_board_resolution`, and routes ShootButton.pressed → `execute_shot`. `_setup_hole_context` seeds `hole_context.rng` from the definition seed (or `randi()` when none), sets `shot_manager.rng`, and seeds `WindSystem.generate_wind(difficulty, hole_context.rng)`. `CardSystemManager.deal_hand_for_hole(hand_def, rng)` deals clubs as a reusable bag and modifier cards (depleting), fixed or via seeded Fisher-Yates. The fixed-seed determinism is proven by the harness (two seeded `execute_shot` runs land identically, AC6). Procedural generation is unbroken: `_apply_hole_definition_overrides` returns early when `definition == null or use_procedural`.

### Build + scope posture

Recorded evidence (FEAT-001..004 findings): both clean-build commands report 0 new script errors against the accepted baseline of 2 pre-existing font errors (`uid://csixfh5trj68q`), and the harness exits 0 with 40/40 checks. The diff touches no off-limits directory; the only `.md` changes are the task's design/plan docs under `.agents/tasks/`. No fail state, stroke budget, or score gate appears in the new core files, and `ScoringManager` is left unwired — `calculate_final_score()` is `int(round(chips * mult))`. `hex_grid.gd` changes are additive/surgical (band fields on CLUB_STATS, new typed fields, guarded hole-definition/turn-plan seams, no-op putting init), not a restructuring.

</details>

<details>
<summary>File map</summary>

- `scripts/shot_context.gd` — footprint fields (aim_dir, band_*, base_spread/roll, spread_mod, falloff_pow) + reset() extended; get_shot_distance()/final_score unchanged (R#1).
- `scripts/hex_grid.gd` — CLUB_STATS distance bands (R#4), TurnController/HoleContext instantiation + wiring, hole-definition/turn-plan seams, no-op putting init, SwingHand3D wiring removed.
- `scripts/shot_manager.gd` — seeded `rng` seam, R#3 footprint fast-path in `_resolve_landing_tile`.
- `scripts/turn_controller.gd` (new) — footprint builder (R#1/R#5) + board resolution (R#2) + terrain factor table.
- `scripts/cards/effects/effect_*.gd` (6 new) — ignore_wind, tighten_spread, punch, flop, bump_run, stinger.
- `scripts/cards/card_library.gd` — registers the new SHOT cards; 12 club cards untouched.
- `scripts/cards/card_system_manager.gd` — `deal_hand_for_hole`, swing-hand references excised.
- `scripts/lie_system.gd` — spread_mod per LIE row, allowed_clubs retuned to the bag.
- `scripts/wind_system.gd` — `generate_wind(difficulty, rng)` seeded seam.
- `scripts/hole_context.gd` / `scripts/hole_definition.gd` / `scripts/cards/hand_definition.gd` (new) — seedable content resources.
- `scripts/tests/test_turn_loop.gd` + `scenes/tests/test_turn_loop.tscn` (new, test-only) — 40-check headless harness.
- `scenes/ui/main_ui.tscn` / `scripts/ui/main_ui.gd` — ShootButton + 2D hand strip; meter/swing nodes removed.
- Deleted: `swing_meter.gd`, `spin_meter.gd`, `putting_system.gd`, `swing_hand_3d.gd`, `swing_card_3d.gd`, `swing_slot_drag_strategy.gd`, `ui/swing_hand.gd` (+ `.uid`s) and scenes `SwingMeter.tscn`, `spin_meter.tscn`, `swing_hand.tscn`, `swing_hand_3d.tscn`, `cards/swing_card_3d.tscn`.

Full diff: `git -C /Users/m22stewa/Documents/Godot/Golf/.worktrees/gameloop diff main...feature/gameloop-v1`.

</details>

# Design Review — Hex Golf Deckbuilder Core Turn Loop (Revision 2)

Reviewer: design-review subagent (fresh read, no authoring context).
Subject: `.agents/tasks/gameloop-design.md` (REVISION 2).
Method: judged on paper + targeted code spot-checks against the `.worktrees/gameloop` worktree.
Scope of verdict: count of HIGH + MEDIUM findings. >0 ⇒ CHANGES_REQUESTED.

This is revision 2; it claims to resolve 13 prior findings. I re-verified the load-bearing
code claims independently rather than trusting Section 18. The design is unusually well
grounded — the great majority of its integration seams, data shapes, and retirement targets
are REAL and accurately quoted. The remaining findings below are genuine problems that would
bite the coder, plus nits.

---

## Findings

### 1. [MEDIUM] Reward score chips are computed from `aim_tile`, not the board-resolved `landing_tile`

Section 9 ("Board-resolution ordering") asserts that after `apply_board_resolution` rewrites
`ctx.landing_tile` in place, `_simulate_ball_path()` rebuilds `path_tiles` and `_compute_scoring()`
"scores over `path_tiles` + landing terrain, [so] scoring sees the fully board-resolved landing."

Verified against `scripts/shot_manager.gd`:
- `_compute_scoring()` sets `base_chips = int(get_shot_distance() * 5)`, and
  `ShotContext.get_shot_distance()` (verified in `scripts/shot_context.gd`) computes the distance
  between `start_tile` and **`aim_tile`** — NOT `landing_tile`. So the distance-based chips reflect
  the aimed center, not the drawn+rolled landing hex. Variance and roll-out do not move the score.
- `_simulate_ball_path()` appends only `[start_tile, landing_tile]` (a 2-element path, straight
  line, no interpolation). `_compute_scoring()` then iterates `path_tiles` and calls
  `_apply_terrain_scoring(surface)` per tile — so only the start terrain and the final landing
  terrain are scored; intermediate carry/roll tiles are never scored. The claim that scoring
  reflects the path is effectively just "start + landing terrain."

Impact: the "reward score reflects the resolved shot" intent is only half true. Terrain-on-landing
is scored correctly (because `landing_tile` is rewritten synchronously before `_compute_scoring`,
which I confirmed is the real call order), but the chips magnitude is driven by where you aimed,
not where the ball ended up. For a first playable where score never gates anything this is survivable,
but the design explicitly promises the opposite, so a coder will either (a) implement it as written
and silently diverge from the spec, or (b) guess at a fix.

Concrete fix: state the intended basis explicitly. Either
- change `_compute_scoring` to base distance on `landing_tile` (`get_shot_distance` variant that
  uses `landing_tile - start_tile`, or add `get_landing_distance()` to `ShotContext`), and note
  that `aim_tile` is kept equal to `center_tile` only for preview; OR
- keep the current `aim_tile`-based chips and change the Section 9 prose to say "distance chips
  are computed from the aimed center; only landing terrain (not carry path) adjusts the score."

Pick one and pin it so there is no ambiguity for the coder.

### 2. [MEDIUM] Roll-out walk mutates a `landing_tile` that `_simulate_ball_path` then uses, but the terrain-scoring loop only sees start + final landing — the "carry hex" tree-block and water-stop rules have no path to inspect

Section 4.2 and Section 6 specify roll/tree/water resolution that depends on inspecting
intermediate hexes ("if the drawn landing hex OR a carry hex is TREE…", "each step stops early
if it would … enter WATER"). Section 9 places this in `apply_board_resolution` on the
`landing_resolved` callback. That is a sound place to MUTATE `landing_tile`. The gap: the design
never says where the intermediate carry/roll hexes come from. `_simulate_ball_path` (verified)
produces only `[start, landing]`; there is no per-hex carry path in `ShotContext` for
`apply_board_resolution` to walk. The roll walk must therefore reconstruct the hex line itself
(start→center→out) using the AOE direction-walk helpers.

Impact: the coder has to build the carry/roll hex sequence from scratch inside
`apply_board_resolution` (walking `fwd` from `center_tile` and from the drawn landing hex via
`AOESystem._get_neighbor_in_direction`). Feasible, but unspecified — and easy to get wrong at
parity boundaries because each step must recompute `is_odd`.

Concrete fix: specify the walk explicitly, e.g. "`apply_board_resolution` reconstructs the roll
line by stepping `AOESystem._get_neighbor_in_direction(tile, ctx.aim_dir, tile.x % 2 == 1)`
`roll` times from the drawn landing hex, recomputing parity each step, stopping before WATER or
out-of-bounds, and (for non-Punch/Stinger) stopping before TREE." Name the helper and the
per-step parity recompute so there is no ambiguity.

### 3. [MEDIUM] `_select_landing_tile_from_aoe` already honors `aoe_weights` — the Finding-3 fast path is necessary for a different reason than stated, and the stated trigger is incomplete

Section 2.5 / F3 argue the surgical `_resolve_landing_tile` change is needed because the builder's
`aoe_tiles`/`aoe_weights` would be overwritten and curve/wind double-applied. I verified this is
true in the OVERWRITE sense: `_resolve_landing_tile()` calls `_calculate_curved_target()` then
`aoe_system.compute_aoe(target_tile, …)` and assigns the result to `current_context.aoe_tiles`,
discarding the builder's tile set, THEN calls `_select_landing_tile_from_aoe`.

But note two things the design gets slightly wrong, which matter for the implementer:
1. `_select_landing_tile_from_aoe` already contains `if current_context.aoe_weights.size() > 0:
   return _weighted_tile_selection()`. So weights are honored even on the legacy path — the real
   bug is that `aoe_tiles` has just been re-keyed by `compute_aoe(target_tile,…)`, so
   `_weighted_tile_selection` iterates the NEW tiles while `aoe_weights` still holds the builder's
   OLD keys → every lookup hits the `.get(tile, 1.0)` fallback and the weighting collapses to
   uniform. The design's phrase "weighting silently degrades to the `.get(tile, 1.0)` fallback"
   is correct, but the cause is the tile-set re-key, not a missing weights branch. The fix (skip
   `_calculate_curved_target` AND the `compute_aoe` rebuild) is correct regardless.
2. The design proposes gating the fast path on `metadata["footprint_built"]` "equivalently
   `aoe_weights.size() > 0`". These are NOT equivalent in the current code: `confirm_shot()` runs
   `_apply_modifiers_on_aoe()` → possibly `_compute_aoe()` before `_resolve_landing_tile()`, and
   nothing clears a stale `aoe_weights` between shots except `ctx.reset()`. Relying on
   `aoe_weights.size() > 0` risks a false positive if a prior path left weights populated. Use the
   explicit `footprint_built` flag ONLY, and make sure `ctx.reset()` clears it (it clears
   `metadata`, so this holds — but say so).

Concrete fix: in Section 2.5, (a) correct the causal explanation to "the tile set is re-keyed by
`compute_aoe(target_tile,…)` so `aoe_weights` keys no longer match," and (b) make the fast-path
trigger the `footprint_built` metadata flag alone (drop the "equivalently `aoe_weights.size() > 0`"
alias, which is unsafe), noting `reset()` clears it via `metadata.clear()`.

### 4. [MEDIUM] Band semantics vs. existing `CLUB_STATS.distance` is underspecified and internally inconsistent for the Driver

Section 3 adds `band_min/band_max/base_spread` to every `CLUB_STATS` row and gives Driver
`band_min=22, band_max=26, band_center=24`. Verified: the real `CLUB_STATS[DRIVER].distance = 22`.
So the design is treating the existing `distance` (max range, 22) as the band MINIMUM and inventing
a longer `band_max=26` above the club's previously-defined max. For every other bag club the band
also straddles the old `distance` differently (e.g. 3-Wood real `distance=20`, band 18–20 — here
`distance` is the band MAX). There is no stated rule for how `band_min/band_max` relate to the
existing `distance` key, and the relationship is inconsistent across clubs (Driver: distance=min;
3-Wood: distance=max; 6-Iron real distance=15, band 12–14 — distance is ABOVE band_max).

Impact: this matters because ~10 legacy call sites still read `CLUB_STATS[...].distance`
(verified: `get_current_club_distance`, `get_max_reachable_club`, the bounce/carry math at lines
2784 and 3589, etc.). If the band numbers and the legacy `distance` disagree, the legacy
range-preview / reachability UI will show distances that do not match what the footprint builder
actually produces. The design says "do not break procedural generation" but is silent on this
legacy-`distance`-vs-band divergence.

Concrete fix: add one sentence stating the invariant, e.g. "`band_center` SHOULD equal the
existing `distance` for each club so legacy reachability/preview code stays consistent; where the
table above diverges from `distance`, update `distance` to `band_center` as part of the row edit"
— OR explicitly accept the divergence and note which legacy readers become cosmetic-only. As
written, the Driver row (band_center 24 vs distance 22) will desync the range preview.

### 5. [MEDIUM] `_simulate_ball_path`'s straight 2-tile path undercuts the `path_tiles`-based terrain scoring the design relies on

Related to Finding 1 but distinct and independently actionable. Section 11 ("Scoring engine")
and Section 9 both lean on `_compute_scoring` scoring "over `path_tiles`." Verified: `path_tiles`
is literally `[start_tile, landing_tile]` with a `# TODO: Implement proper line-drawing algorithm`
comment in `shot_manager.gd`. So any design statement implying mid-flight terrain (water carried
over, trees passed through) affects the reward score is false with the current implementation.

Impact: the tree-block / water-stop rules in Section 6 are enforced by `apply_board_resolution`
mutating `landing_tile` (fine), but the SCORING of those terrains relies on them appearing in
`path_tiles`, which they won't. Since score is demoted to a non-gating reward layer this is not
fatal, but it is a stated-vs-real mismatch the coder must not be left to discover.

Concrete fix: explicitly scope this. Add to Section 9/11: "For the first playable, scoring
inspects only start terrain and the final (board-resolved) landing terrain; `_simulate_ball_path`
remains a 2-tile stub. Per-hex path scoring is out of scope." That removes the implication that
carry-path terrain is scored.

### 6. [NIT] Wind `.cross()` sign convention ("positive = right of shot") is asserted but not verified against the DIRECTIONS layout

Section 4.1 states `calculate_wind_curve`'s `.cross()` is "positive = push to the right of the
shot," and the builder applies `perp(fwd) * wind_shift` with "+wind_shift = right of the shot."
Verified `calculate_wind_curve` returns `clampi(int(round(wind_vec.cross(shot_vec) * strength)),
-strength, strength)` with `shot_vec` normalized — but the sign ("right vs left") depends on the
`DIRECTIONS` 2D convention (`Y+` is down, hole runs W→E) AND on how `perp(fwd)` is oriented in hex
space. The design never ties these two coordinate systems together concretely enough to be sure
"+" lands on the player's right. The two conventions could silently disagree, mirroring draw/fade
and crosswind.

Concrete fix: specify `perp(fwd)` by index, e.g. "`perp(fwd)` for a shot whose dominant hex
direction is `d` is hex direction `(d+2) % 6` for +shift and `(d+4) % 6` for −shift," and add a
harness assertion that a known crosswind pushes the center to the expected side for a fixed tee
shot. This turns an assumption into a tested fact.

### 7. [NIT] R4 node-path mismatch: `SwingHand` is a 2D `swing_hand.tscn` instance, while `hex_grid` wires a `SwingHand3D` SubViewport by absolute path

Verified: `main_ui.tscn` instances `scenes/ui/swing_hand.tscn` (uid `cswinghand1`) as node
`SwingHand`, and separately `hex_grid._init_card_system` looks up
`/root/GOLF/Control/MainUI/SwingHand/SubViewportContainer/SubViewport/SwingHand3D`. The design's
R4 talks about retiring both "`SwingHand`" and "the `swing_hand_3d` SubViewport wiring" but treats
them as one thing in places. These are two distinct nodes/scripts (`scripts/cards/swing_hand.gd`
vs `scripts/swing_hand_3d.gd`). The design already says "verify no other references first with a
grep," which covers the risk, but the summary tables list them loosely.

Concrete fix: in R4, list the two retirements separately: (a) the 2D `SwingHand`
(`swing_hand.tscn` / `scripts/cards/swing_hand.gd`), and (b) the `SwingHand3D` SubViewport chain
reached by the absolute path in `_init_card_system`. Keep the "grep first" guard.

---

## Verified Assumptions (independently confirmed against the worktree)

- **ClubType = 12 values, IRON_7 is the fallback.** `hex_grid.gd` `enum ClubType {DRIVER, WOOD_3,
  WOOD_5, IRON_3, IRON_5, IRON_6, IRON_7, IRON_8, IRON_9, PITCHING_WEDGE, SAND_WEDGE, PUTTER}`;
  ~10 `CLUB_STATS.get(club, CLUB_STATS[ClubType.IRON_7])` call sites. Removing any value WOULD
  break the build. (F1 claim correct.)
- **`CLUB_STATS` rows** have `name/distance/accuracy/roll/loft/arc_height/swing_difficulty/curve`
  exactly as the design states; `roll` key exists and is reused as `base_roll`.
- **12 club cards registered** in `CardLibrary._register_club_cards()` with ids exactly
  `club_driver, club_3wood, club_5wood, club_3iron, club_5iron, club_6iron, club_7iron, club_8iron,
  club_9iron, club_pw, club_sw, club_putter`. The 7 bag ids all exist.
- **`CardLibrary.get_club_deck()`** exists and returns a `CardInstance` array; `CardSystemManager`
  has `club_deck_definition` + `club_deck_manager: DeckManager`; falls back to
  `card_library.get_club_deck()`. There is NO `CardSystemManager.get_club_deck()`. (F12 correct.)
- **`hex_grid` sets `card_system.club_deck_definition = club_deck`** where `club_deck` preloads
  `swing_deck.tres`. `swing_deck.tres` exists.
- **`DeckManager`** has `get_hand`, `play_card`, `draw_candidates`, `clear_active_cards`,
  `shuffle_discard_into_deck`, `initialize_with_instances`, `draw_specific_card`.
- **`ShotContext`** has every reused field the design names, and `reset()` zeroes the existing
  mod fields; `calculate_final_score()` = `int(round(chips * mult))`. (F2/F7 basis correct;
  `reset()` does NOT yet touch the new fields, as the design acknowledges.)
- **`ShotManager`** pipeline, signals, `start_shot/set_aim_target/confirm_shot`, synchronous phase
  order (`_resolve_landing_tile` → `_simulate_ball_path` → `_compute_scoring`), bare `randf()` in
  BOTH `_weighted_tile_selection` and `_select_landing_tile_from_aoe`, and `_resolve_landing_tile`
  overwriting `aoe_tiles` via `compute_aoe` — all confirmed. (F3/F4/F8 mechanisms real.)
- **`_apply_modifiers_before_aim` runs once inside `start_shot`, before `shot_started`** — exactly
  as F6 describes; the `rebuild()`-re-invokes-`apply_before_aim` plan is sound.
- **`AOESystem`** has `compute_circle_aoe(center, radius, hole_controller)`,
  `_get_direction_offsets(is_odd)` with the stated 0=Up..5=Up-Left convention,
  `_get_neighbor_in_direction`, and `calculate_weights_by_terrain` returning ABSOLUTE weights
  (FAIRWAY=2.0, GREEN=2.5, no TEE/FLAG entries, no clamp). (F9 claim correct.)
- **`LieSystem.LIE_DATA.allowed_clubs`** sets match the design's Finding-5 verbatim quotation
  exactly (FAIRWAY excludes DRIVER; ROUGH starts IRON_5; DEEP_ROUGH/TREE = IRON_7+;
  SAND = SAND_WEDGE/PITCHING_WEDGE/IRON_9; GREEN = PUTTER). `apply_lie_to_shot` adds
  `distance_mod`/`roll_mod`, writes `allowed_clubs` to metadata, applies chips/mult, and the
  accuracy→AOE path is commented out. (F5 correct; the `spread_mod` add is a clean extension.)
- **`WindSystem`**: `generate_wind(difficulty=0.5)` uses bare `randf()/randi()%8/randf_range()`;
  `calculate_wind_curve(Vector2)->int` returns the clamped crosswind only (no head/tail term);
  `get_direction_vector()->Vector2` returns normalized DIRECTIONS or ZERO; `strength` is int 0–3.
  (F4/F10 basis correct.)
- **`ModifierManager`** has `apply_before_aim/apply_on_aoe/apply_on_scoring(context)`.
- **Retirement seams**: `_start_new_shot()` has the `should_putt = ball_surface == GREEN` →
  `putting_system.enter_putting_mode()` branch; `_init_putting_system()` exists;
  `_trigger_hole_complete()` guarded by `hole_complete_triggered`; ball-on-flag triggers it in
  `_start_new_shot`; `_handle_water_hazard()` returns the ball to `previous_valid_tile` and calls
  `run_state.record_stroke(0)`; `previous_valid_tile = context.start_tile`;
  `force_start_shot()` exists; `refresh_aoe_display()` exists. All real.
- **ShotUI confirm path**: `spin_confirmed → _on_spin_confirmed → _on_swing_completed_with_spin →
  force_start_shot → confirm_shot`; `bypass_card_selection = true`. Confirmed.
- **Main scene / project.godot**: `run/main_scene="uid://i0lqex70w705"`; GOLF.tscn root script is
  `res://scripts/hex_grid.gd` with that uid; `config/features=("4.7","Forward Plus")`. "No change
  required" is correct.
- **Retirement targets exist**: `scripts/swing_meter.gd(+.uid)`; `main_ui.tscn` nodes `SwingMeter`,
  `SpinMeterPanel`, `SpinMeter`, `SwingHand`.
- **Scope fences** present and consistent with the brief: holed-out-only win, no fail/stroke gate,
  no shop/9-hole layer, surgical-only `hex_grid.gd`, don't touch `models/textures/theme/addons/
  assets/.md/.github`, seeded content architecture (not the challenge mode) in scope.

## Unverified / Wrong Assumptions

- **WRONG (partial) — F3 causal explanation.** The design says weights degrade to the
  `.get(tile,1.0)` fallback "so `aoe_weights` keys may no longer match." The real mechanism is
  the tile-set RE-KEY by `compute_aoe(target_tile,…)`; `_select_landing_tile_from_aoe` already has
  a `aoe_weights.size()>0 → _weighted_tile_selection()` branch, so weights ARE consulted — they
  just point at stale keys. The proposed fix still works; the rationale is imprecise. (Finding 3.)
- **WRONG — "scoring sees the fully board-resolved landing" (chips).** `base_chips` derives from
  `get_shot_distance()` which uses `aim_tile`, and `path_tiles` is a 2-tile stub. Landing TERRAIN
  is scored on the resolved hex, but chip MAGNITUDE and carry-path terrain are not. (Findings 1, 5.)
- **UNVERIFIED — band-vs-`distance` consistency.** The design does not state how the new
  `band_*` keys relate to the legacy `distance` key that ~10 call sites still read; the table
  values diverge from `distance` inconsistently across clubs. Not confirmable as safe without a
  stated invariant. (Finding 4.)
- **UNVERIFIED — carry/roll hex reconstruction.** No `ShotContext` field carries the intermediate
  carry/roll hexes, so `apply_board_resolution`'s roll/tree/water walk must be reconstructed by
  the coder; the walk is not specified. (Finding 2.)
- **UNVERIFIED — wind sign ("+ = right").** Asserted, not derived from the DIRECTIONS layout +
  hex `perp` orientation; could mirror. (Finding 6.)
- **NOT RE-CHECKED (accepted as plausible, out of spot-check budget):** exact contents of
  `starter_deck.tres`; the concrete `EffectCurveShot` enum ordering (design quotes
  Draw/Fade/Random/Hook/Slice — plausible, matches `curve_profile` strings in `shot_context.gd`);
  `get_elevation` range vs `ELEV_PER_HEX=0.6` tuning; `swing_hand_3d.gd` SubViewport node path at
  runtime. These affect tuning/robustness, not architecture.

---

## Verdict

HIGH findings: 0. MEDIUM findings: 5 (Findings 1–5). NIT findings: 2 (Findings 6–7).

MEDIUM count > 0 ⇒ **CHANGES_REQUESTED**.

The architecture is sound and overwhelmingly grounded in real code — none of the MEDIUMs are
architectural; they are spec precision gaps (scoring basis, roll-path reconstruction, fast-path
trigger, band/`distance` invariant, path-stub scope) that would otherwise be resolved by coder
guesswork. Tightening the five sections above should clear the loop quickly.

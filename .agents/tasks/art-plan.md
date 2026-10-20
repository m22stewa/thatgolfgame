# Implementation Plan — "Refined Tabletop Golf" Art-Direction Pass

Worktree (ABSOLUTE root for ALL paths; relative paths land in the wrong tree):
`/Users/m22stewa/Documents/Godot/Golf/.worktrees/artpass`

Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot` (Godot 4.7.2.stable, Forward+).
Main scene: `/Users/m22stewa/Documents/Godot/Golf/.worktrees/artpass/scenes/GOLF.tscn` (uid://i0lqex70w705), root script `scripts/hex_grid.gd`.
Branch: `feature/art-tabletop`. Commit locally only; never push. Stage only source files you change (never `git add -A` — the worktree carries unrelated `*.import` churn under `assets/` and `models/`).

## Grounding facts discovered in the code (do not re-derive; verified by reading)

1. **Tiles are rendered from the `*-mesh.tres` files, NOT the `unit_hex_*.tscn` scenes.** `scripts/hex_grid.gd` lines 270–279 build `mesh_map` by `preload()`-ing `scenes/tiles/<surface>-mesh.tres`. `_generate_grid()` (line ~6411) creates one `MultiMeshInstance3D` per `SurfaceType` with `mm.mesh = mesh_map[surf_type]`. So **every tile of a surface type shares ONE material — the StandardMaterial3D embedded as the first sub_resource of its `*-mesh.tres`.** The `unit_hex_*.tscn` files are unused by gameplay; do NOT edit them.
2. Surface→mesh reuse: `TREE` uses `fairway-mesh.tres`; `FLAG` uses `green-mesh.tres`; `TEE` uses `teebox-mesh.tres`.
3. Current embedded tile albedos (first sub_resource of each `*-mesh.tres`):
   - fairway `Color(0.0534, 0.4563, ~0, 1)`
   - green `Color(0,1,0,1)` + `emission_enabled=true` + `rim_enabled=true`  ← the "pure green with emission/rim" the brief calls out; it lives HERE, not in GOLF.tscn.
   - rough `Color(0, 0.251, 0, 1)`
   - deeprough `Color(0.0063, 0.1548, ~0, 1)`
   - sand `Color(0.677, 0.673, 0.287, 1)`
   - water `Color(0, 0.290, 1, 1)` + `albedo_texture` (`seamless_cartoon_styled_water...jpg`) + `metallic=0.6 roughness=0.48 uv1_triplanar=true`
   - teebox `Color(0,0,0,1)` (pure black — clearly wrong; TEE surface renders black)
   - ground (hex sides/base) `Color(0.241, 0.189, 0.0317, 1)` (brown dirt; shared base, keep but tune)
4. Tiles are positioned in world space by `hex_grid.gd` (`x = col*1.5`, `z = row*height + (col%2)*height/2`, `height = sqrt(3)`), rotated `Basis(UP, PI/6)`, Y-stretched 2.5×. Mowing stripes must be derived from **world-space XZ in the shader** (not UV, since all instances share one mesh/UV set).
5. Trees are placed in `hex_grid.gd` `_generate_grid()` (loop at line ~6545) — one scene instance per `TREE` cell, chosen from `TREE_SCENES` (`scenes/tiles/trees.tscn`, `trees-2.tscn`, `trees-3.tscn`), each given random scale/rotation, a `StaticBody3D`+`CylinderShape3D` collision, group `trees`, and a call to `_apply_random_tree_colors()` (line ~6800). **Tree PLACEMENT is generation and must not change.**
6. The three tree scenes are **imported low-poly FBX meshes** (`Tree_small_regular`, `Tree_average_lush`, `Tree_Spruce_small_01`), each a `MeshInstance3D` with a `StandardMaterial3D` using `vertex_color_use_as_albedo=true`, a gradient `albedo_texture`, and `emission_enabled=true`. They are NOT CSGSphere3D. Therefore `_apply_random_tree_colors()` (which only touches `CSGSphere3D` children) is a **no-op for the real trees** — foliage recolor must move to the vertex-color material.
7. `scripts/tree_spawner.gd` is attached to an **inert** `tree-spawner` node in GOLF.tscn (`visible=false`, no `tree_scenes`, not driven by generation). It is NOT the active placement path. Retune it only if we route placement through it; otherwise leave it.
8. GOLF.tscn environment: the active `WorldEnvironment` uses `Environment_rvr3e` (GOLF.tscn lines 38–55): `background_mode=2` sky, `tonemap_mode=2`, `sdfgi_use_occlusion=true`, `glow_enabled=true glow_intensity=6.49`, distance `fog_enabled=true` (begin 100 end 180), volumetric fog (`volumetric_fog_density=0.013`). Sky is `ProceduralSkyMaterial_cdobm` (bright blue top). The `DirectionalLight3D` (line 246) is `visible=false light_energy=0.4`. A second `Environment_fkwjp` + `World3D_eulkx` (lines 81–84) feed a SubViewport, not the main view. `textureFloor` (line ~424) is a 400×400 plane with an animated cloud shader as backdrop.
9. Existing reusable shaders in `scripts/`: `outline.gdshader` (actually a sphere-MASK shader — NOT a true outline, do not reuse for tree outlines), `water.gdshader`, `floor.gdshader`, `ice.gdshader`, `flag.gdshader`. Leaf textures exist at `models/leaves/leaves-0[1-6].jpg`.
10. **Capture harness** (BEFORE set already produced): `scenes/tests/capture_course.tscn` → `scripts/tests/capture_course.gd`. It instances the real `GOLF.tscn` unmodified, hides UI, drives its own capture camera at the game's tilted angle, regenerates until a tree-bearing hole appears, and saves `before_board_wide.png`, `before_bunker_water.png`, `before_trees.png` to `res://.agents/tasks/art-shots/`. The three BEFORE PNGs exist at `/Users/m22stewa/Documents/Godot/Golf/.worktrees/artpass/.agents/tasks/art-shots/`.

## Palette (target albedos, confident/limited — brief)

| Surface | Hex | Linear Color() approx (sRGB→use hex in editor; values below are sRGB) |
|---|---|---|
| fairway | #3c7140 | Color(0.235, 0.443, 0.251, 1) |
| green | #579448 | Color(0.341, 0.580, 0.282, 1) |
| sand | #d2bd84 | Color(0.824, 0.741, 0.518, 1) |
| water | #4b7892 (muted slate) | Color(0.294, 0.471, 0.573, 1) |
| tee | #c7b48a (warm tee) | Color(0.780, 0.706, 0.541, 1) |
| rough | deep rough #2f5030 | Color(0.184, 0.314, 0.188, 1) |
| deep rough | darker than rough, same family | ~Color(0.12, 0.22, 0.13, 1) |
| accents | brass #b8923f, navy #243b53 | flag/pin + backdrop only |

No neon, no fully saturated primaries, no emissive turf, no glossy specular.

## Verification commands (used by every stage; discovered + confirmed to pass on current tree now)

- **V1 — headless run, 0 new errors** (baseline currently 0):
  ```
  /Applications/Godot.app/Contents/MacOS/Godot --headless \
    --path /Users/m22stewa/Documents/Godot/Golf/.worktrees/artpass --quit-after 400 2>&1 \
    | grep -iE "error|not found|null|invalid|nonexistent" \
    | grep -viE "shader|vulkan|rendering device|headless"
  ```
  Expected: no output (ignore the 2 accepted baseline font errors for `uid://csixfh5trj68q`; they are NOT script errors and did not surface in this grep on the current tree).
- **V2 — editor import, 0 SCRIPT/parse errors**:
  ```
  /Applications/Godot.app/Contents/MacOS/Godot --headless \
    --path /Users/m22stewa/Documents/Godot/Golf/.worktrees/artpass --editor --quit 2>&1 \
    | grep -iE "SCRIPT ERROR|parse error"
  ```
  Expected: no output.
- **V3 — turn-loop harness, 40/40, exit 0**:
  ```
  /Applications/Godot.app/Contents/MacOS/Godot --headless \
    --path /Users/m22stewa/Documents/Godot/Golf/.worktrees/artpass \
    scenes/tests/test_turn_loop.tscn 2>&1 | tail -3
  ```
  Expected: `=== harness complete: 40 checks, 0 failures ===`, exit 0.
- **V4 — live-hand-wiring harness, 16/16, exit 0**:
  ```
  /Applications/Godot.app/Contents/MacOS/Godot --headless \
    --path /Users/m22stewa/Documents/Godot/Golf/.worktrees/artpass \
    scenes/tests/test_live_hand_wiring.tscn 2>&1 | tail -3
  ```
  Expected: `=== live hand wiring test complete: 16 checks, 0 failures ===`, exit 0.

All four must pass after every stage. Material/scene edits can corrupt a `.tres`/`.tscn` and break the parse, so V1–V4 catch regressions even for art-only changes.

---

# Stages

- [ ] 1. **Environment overhaul in GOLF.tscn (clean neutral-studio look + perf win).**
      Edit `Environment_rvr3e` (`scenes/GOLF.tscn` lines 38–55) in place: remove `glow_intensity=6.49` → set `glow_enabled=false` (or `glow_intensity≈0.15` if any bloom is kept); remove `fog_enabled`/all `fog_*` lines (distance fog OFF); remove all `volumetric_fog_*` lines (OFF); remove `sdfgi_use_occlusion` and ensure SDFGI is OFF (`sdfgi_enabled` absent/false); add soft neutral ambient (`ambient_light_source=3` sky-based or a neutral `ambient_light_color` ~#bfc6cc at `ambient_light_energy≈0.6`) and gentle SSAO (`ssao_enabled=true`, low radius/intensity). Replace the bright-blue `ProceduralSkyMaterial_cdobm` with a soft neutral gradient sky (desaturated pale top ~#aebfc9, warm-neutral horizon) OR keep ProceduralSky with toned-down colors — pick the gradient-sky route for a calmer backdrop. Turn the `DirectionalLight3D` (line 246) ON (`visible=true`), keep it as a soft key (`light_energy≈0.9`, warm-neutral `light_color`, `shadow_enabled=true`, soft shadow). Leave camera transform, tonemap choice, and `textureFloor` geometry untouched (optionally calm the cloud-shader speed/contrast later in trees stage — not here).
      Files: `/Users/m22stewa/Documents/Godot/Golf/.worktrees/artpass/scenes/GOLF.tscn`
      Verify: V1, V2, V3, V4 all pass. (This stage is self-contained and leaves the board buildable and playable.)

- [ ] 2. **Fix the green tile material — drop emissive/rim hack.**
      In `/Users/m22stewa/Documents/Godot/Golf/.worktrees/artpass/scenes/tiles/green-mesh.tres`, edit the first sub_resource (`StandardMaterial3D_td1sn`): set `albedo_color = Color(0.341,0.580,0.282,1)` (#579448), **remove** `emission_enabled = true` and `rim_enabled = true`, set `roughness=1.0`, `metallic=0.0`, `specular=0.1` (matte felt). Do NOT touch the ArrayMesh geometry data in the file. This also fixes FLAG tiles (they reuse green-mesh).
      Files: `scenes/tiles/green-mesh.tres`
      Verify: V1–V4 pass; green no longer glows (confirm visually in AFTER shots, stage 9).

- [ ] 3. **Repalette + matte-ify every other terrain material (flat-color baseline before texture).**
      For each `*-mesh.tres` first sub_resource, set `albedo_color` to the palette value and `roughness=1.0 metallic=0.0 specular≈0.1` (matte): `fairway-mesh.tres` #3c7140; `rough-mesh.tres` #2f5030; `deeprough-mesh.tres` ~#1f3a22 (darker); `sand-mesh.tres` #d2bd84; `teebox-mesh.tres` #c7b48a (fixes the pure-black tee); `water-mesh.tres` base to #4b7892 (keep its triplanar texture but drop `metallic` to ~0.1 and set `roughness≈0.35` for muted slate, no glossy spec). Tune `ground-mesh.tres` (hex base) to a slightly warmer/darker soil that reads under the new ambient (~#4a3a24). Same-pattern edit across files — one stage, files listed.
      Files: `scenes/tiles/fairway-mesh.tres`, `rough-mesh.tres`, `deeprough-mesh.tres`, `sand-mesh.tres`, `teebox-mesh.tres`, `water-mesh.tres`, `ground-mesh.tres`
      Verify: V1–V4 pass.

- [ ] 4. **Turf texture shader (felt weave + mowing stripes) via a ShaderMaterial on fairway & green.**
      Author `scripts/turf.gdshader` (`shader_type spatial;`): soft-cel/flat diffuse; cheap procedural detail = fine value-noise "felt grain" modulating albedo ±3–5% + subtle roughness break-up; **mowing stripes** = `sin(dot(world_xz, stripe_dir) * stripe_freq)` thresholded into soft alternating light/dark bands (±4–6% lightness). Derive world XZ in the vertex/fragment stage from `(MODEL_MATRIX * vec4(VERTEX,1)).xz` so bands are continuous across all MultiMesh instances. Expose uniforms: `base_color`, `stripe_dir` (vec2), `stripe_freq`, `stripe_strength`, `grain_strength`, `roughness`. Assign this ShaderMaterial as the first sub_resource material of `fairway-mesh.tres` and `green-mesh.tres` (green: tighter `stripe_freq`, gentler strength). **Align `stripe_dir` to the hole's play direction**: set it from script — in `hex_grid.gd` after generation, compute play dir = normalize(world(flag_cell) − world(tee_cell)).xz and call `set_shader_parameter("stripe_dir", dir)` on the fairway/green MultiMesh materials (add a small helper `_apply_mowing_direction()` invoked at the end of `_generate_grid()`; access the two MultiMeshInstance3D via the `multimesh_nodes` map — store refs or re-fetch by surface). Keep it cheap (no texture fetch, pure math). No baked texture needed.
      Files: `scripts/turf.gdshader` (new), `scenes/tiles/fairway-mesh.tres`, `scenes/tiles/green-mesh.tres`, `scripts/hex_grid.gd` (add `_apply_mowing_direction()` + call; do NOT change generation/layout/positions).
      Verify: V1–V4 pass (V3/V4 confirm generation + turn loop still work after the hex_grid helper is added).

- [ ] 5. **Sand ripple + rough/deep-rough tuft break-up (reuse the turf shader family).**
      Add ripple + tuft variants (either `#define`/uniform flags in `turf.gdshader` or sibling shaders `scripts/sand.gdshader`, `scripts/rough_turf.gdshader`): sand = fine concentric/linear ripple from world XZ (`sin`-based, low amplitude) modulating albedo + normal-ish roughness; rough/deep-rough = higher-frequency mottled grass-tuft noise (no stripes). Assign to `sand-mesh.tres`, `rough-mesh.tres`, `deeprough-mesh.tres` first-sub_resource materials. Keep all procedural (no new big textures). If a baked tiling texture is genuinely needed for grain, author a small ≤256×256 PNG under `textures/` (e.g. `textures/felt_grain.png`) and import with repeat — only if the pure-procedural grain reads too flat in stage-9 shots.
      Files: `scripts/sand.gdshader` + `scripts/rough_turf.gdshader` (new, or extended `turf.gdshader`), `scenes/tiles/sand-mesh.tres`, `rough-mesh.tres`, `deeprough-mesh.tres`, optional `textures/felt_grain.png`.
      Verify: V1–V4 pass.

- [ ] 6. **Beveled/physical tile read + soft contact shadow + muted water.**
      Tile "catch the key light / physical piece" read: raise the `DirectionalLight3D` key energy/angle (done in stage 1) is the cheap win; additionally enable `ssao` crevice darkening (stage 1) and give the `ground-mesh` sides a slightly darker AO-ish base so bevels read. If tiles need an actual beveled lip, prefer a shader rim-darkening on the turf shader (darken fragments where world-space height derivative is steep) over editing ArrayMesh geometry — do NOT regenerate tile meshes. Water: finalize muted-slate look using existing `scripts/water.gdshader` if it gives a calmer ripple than the current triplanar JPG; otherwise keep the retinted StandardMaterial from stage 3 with low metallic. No glossy specular anywhere.
      Files: `scripts/turf.gdshader` (rim-darken tweak), `scenes/tiles/ground-mesh.tres`, `scenes/tiles/water-mesh.tres` (+ optional swap to `scripts/water.gdshader`).
      Verify: V1–V4 pass.

- [ ] 7. **Crafted "game-piece" tree material: soft-cel fill + dark outline + foliage recolor path.**
      Give the three tree scenes (`scenes/tiles/trees.tscn`, `trees-2.tscn`, `trees-3.tscn`) a soft-cel look: author `scripts/tree_toon.gdshader` (flat 2–3 band cel on a `foliage_colour` uniform, trunk kept brown via vertex color / second material; no emission — remove `emission_enabled` from the embedded StandardMaterials) and a **dark outline** via a new `scripts/tree_outline.gdshader` using the inverted-hull technique (`cull_front;` render back faces expanded along normal by a small `outline_width` in a dark navy/near-black, as a `next_pass` on the foliage material, or a duplicated scaled MeshInstance). Keep silhouettes legible at the board camera angle. Because the real trees use `vertex_color_use_as_albedo`, expose `foliage_colour` as a uniform the recolor path can set. **Rewrite `hex_grid.gd::_apply_random_tree_colors()`** (line ~6800) to walk `MeshInstance3D` children and set the `foliage_colour` shader param (or duplicate+tint the StandardMaterial albedo) instead of looking for `CSGSphere3D` (current no-op). Use the brief's muted-green variation set already present in `tree_spawner.gd::foliage_colors` as the palette. Do NOT change where trees are placed.
      Files: `scripts/tree_toon.gdshader` + `scripts/tree_outline.gdshader` (new), `scenes/tiles/trees.tscn`, `trees-2.tscn`, `trees-3.tscn`, `scripts/hex_grid.gd` (`_apply_random_tree_colors` rewrite only).
      Verify: V1–V4 pass (V3 regenerates tree-bearing holes; confirm no null/parse errors from the recolor rewrite).

- [ ] 8. **Soft contact shadow under each tree + MultiMesh instancing for perf.**
      Contact shadow "placed piece" read: add a small, cheap faux contact shadow — a flattened dark, semi-transparent disc (a `QuadMesh`/`PlaneMesh` with an unshaded radial-gradient alpha material) parented under each tree at its base, OR rely on the real `DirectionalLight3D` shadow now that it's ON (cheaper; prefer real shadow + a faint baked disc only if the real shadow reads too weak at the camera angle). **MultiMesh instancing**: trees currently instance a full scene (with per-tree `StaticBody3D` collision) per TREE cell — convert the *visual* foliage/trunk meshes to `MultiMeshInstance3D` grouped by tree model, keeping per-cell `StaticBody3D` collision as separate lightweight nodes (gameplay reads tree collisions, see `test_turn_loop` "punch passes tree"). Implement in `hex_grid.gd`: collect per-model transforms during the TREE loop, then build one MultiMesh per model after the loop; add collision bodies separately so the `trees` group + collision contract is preserved. If MultiMesh + per-instance `foliage_colour` variation proves too costly to wire safely, fall back to instanced scenes but still remove the per-tree redundant work — document the choice in the FEAT `findings`. Must not alter tree PLACEMENT (count/positions/cells).
      Files: `scripts/hex_grid.gd` (tree loop + new MultiMesh build), optional `scenes/tiles/tree_contact_shadow.tscn` or inline mesh.
      Verify: V1–V4 pass — **V3 is the gate**: `test_turn_loop` asserts "non-punch roll stops before TREE", "punch rolls THROUGH the tree", so tree collisions must still exist after instancing. Confirm 40/40.

- [ ] 9. **Capture AFTER screenshots with the SAME framings as the BEFORE set.**
      Reuse the existing harness unchanged in behavior; add an output-prefix so it writes `after_*.png` without overwriting the baseline. Minimal edit to `scripts/tests/capture_course.gd`: change the three `_render_and_save("before_*.png")` calls to a prefix var (default `"after_"`) OR add an exported/boolean flag; keep the identical camera framing, UI-hiding, and tree-bearing-hole regeneration logic so AFTER matches BEFORE framings. Run windowed (macOS needs real pixels):
      ```
      /Applications/Godot.app/Contents/MacOS/Godot \
        --path /Users/m22stewa/Documents/Godot/Golf/.worktrees/artpass \
        scenes/tests/capture_course.tscn
      ```
      Confirm `after_board_wide.png`, `after_bunker_water.png`, `after_trees.png` appear in `/Users/m22stewa/Documents/Godot/Golf/.worktrees/artpass/.agents/tasks/art-shots/` alongside the `before_*` set for side-by-side review.
      Files: `scripts/tests/capture_course.gd` (prefix only; no framing/generation change).
      Verify: V1–V4 pass; three `after_*.png` files exist and are non-trivial in size (>50 KB each, i.e. not blank/black).

## Notes, gaps, assumptions

- The brief says the green emission/rim is "in GOLF.tscn"; it is actually in `green-mesh.tres`. Stage 2 fixes it there. Assumption recorded.
- Mowing-stripe "play direction" is assumed to be tee→flag; both cells are known to `hex_grid.gd` (`tee_position`, `flag_position`). If a hole has no distinct fairway/green direction, default `stripe_dir` to world +Z.
- sRGB hex values are given; when writing `.tres`, Godot `Color()` literals in resource files are sRGB in the editor's albedo field — use the approx `Color()` values in the table, then eyeball against AFTER shots and iterate (art is subjective per the brief).
- Keep all turf/sand/rough texture procedural; only add a ≤256² PNG under `textures/` if procedural grain reads flat (stage 5 fallback).
- Do NOT touch `scripts/tests/` except the capture-harness prefix (stage 9) and the generation-preserving `hex_grid.gd` helpers; the turn-loop/live-hand harnesses must keep passing untouched.

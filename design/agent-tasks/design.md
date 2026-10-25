# Design — Snap-Style Layout, Prominent Felt, Cross-Platform Hole-View Input

## 0. Pre-flight: revision provenance

The step prompt instructed me to check `/Users/m22stewa/Documents/Godot/Golf/.agents/tasks/design-verdict.json`. It **exists and is a real review of this snaplayout design** (`reviewDoc` → `/Users/m22stewa/Documents/Golf/.agents/tasks/design-review.md`; verdict `CHANGES_REQUESTED`, 6 findings: 1 HIGH, 3 MEDIUM, 2 NIT, all concerning this UI/felt/input design). This is therefore a **revision pass**: every finding was re-verified against the worktree source and resolved below, and §10 records the response to each. (An earlier version of this document mistook an on-disk verdict for a stale `gameloop` artifact; that is corrected — the current verdict and review on disk are about *this* design, and §10 answers exactly those 6 findings.)

## 1. Overview

This is a UI/UX + cross-platform input pass on the Godot 4.7.2 golf deckbuilder, scoped to three goals that do **not** touch gameplay, turn-loop, hole generation, scoring, or the card system beyond re-parenting the existing hand UI:

1. **Snap layout** — the 3D hole fills the top ~75% of the window; cards/modifiers/Shoot live in a dedicated bottom ~25% felt tray.
2. **Prominent felt** — a new procedural woven-felt `ShaderMaterial` on the bottom tray (dark green felt + stitched brass rail), plus pushed-further felt weave/grain on the existing turf and rough shaders.
3. **Cross-platform hole-view input** — rework `hole_viewer.gd` camera controls (zoom / pan / rotate+pitch / aim) to be native on desktop mouse+keyboard, laptop trackpad, and phone touch, with on-screen affordances.

**Technology stack (locked):** Godot 4.7.2, GDScript, Godot `ShaderMaterial` with `.gdshader` source (spatial shaders for turf, a `canvas_item` shader for the felt tray, following the existing `turf.gdshader` / `sand.gdshader` procedural value-noise family — no texture fetch), Godot `Control` anchor/container layout for all UI, and Godot's built-in `InputEvent` subclasses for gestures. No new addons, no new languages, no imported texture atlases. The deleted `scripts/mobile/` experiment is **not** revived; gesture handling is built directly into `hole_viewer.gd`.

The existing architecture that constrains every decision:
- `scenes/GOLF.tscn` → `Control/MainUI` (instance of `scenes/ui/main_ui.tscn`) is the whole 2D UI; the 3D world lives under `HoleGenerator/HexGrid`.
- `HoleViewer` (instance of `scenes/ui/hole_viewer.tscn`, script `scripts/hole_viewer.gd`) builds its own `SubViewportContainer` → `SubViewport` → `Camera3D` at runtime in `_setup_viewport()`, and **shares the main `World3D`** (`_share_world()`), so it renders the same 3D hole. It registers its camera with `hex_grid.set_external_camera(camera, viewport, self)` for picking.
- Picking/aiming flows: `hole_viewer` `_update_hovered_tile()` → `hex_grid.set_hover_cell()`; `_handle_tile_click()` → `hex_grid.set_aim_cell()`. `set_aim_cell` returns `bool` and drives the footprint/trajectory preview.
- `putting_system` is **retired and stays `null`** (`hex_grid._init_putting_system()` is a no-op; GREEN is a normal PUTTER lie). So `hole_viewer`'s `if putting_system:` branches are currently dead but must be **preserved intact** for forward compatibility — we route through them without assuming they fire.
- Hand UI unique names (`%HandStrip`, `%ClubRow`, `%ModifierRow`, `%ShootButton`) are resolved by `main_ui.gd` (`get_node_or_null("%...")`), by `hex_grid.gd` (via `main_ui_ref.shoot_button`, the `club_card_selected`/`modifier_card_selected` signals, `set_hand()`), and asserted by the headless live-hand test `scripts/tests/test_live_hand_wiring.gd` (`main_ui.get_node_or_null("%ClubRow")`, `"%ShootButton")`).

All paths below are absolute under the worktree `/Users/m22stewa/Documents/Godot/Golf/.worktrees/snaplayout`.

---

## 2. Task 1 — Snap layout (75/25 split)

### 2.1 Exact anchor math

Godot `unique_name_in_owner` is preserved by **re-parenting and re-anchoring nodes, never renaming or recreating them**. `unique_name_in_owner` is a property of the node that is independent of tree position, so a node keeps resolving under `%Name` from the scene owner (`MainUI`) regardless of which parent it sits under, as long as it stays within the `MainUI` owned subtree. This is the linchpin that keeps `main_ui.gd`, `hex_grid.gd`, and the live-hand test green (see §5).

**HoleViewer (top ~75%).** In `scenes/ui/main_ui.tscn` the `HoleViewer` instance node gets anchor-rect layout:
```
anchor_left = 0.0
anchor_top = 0.0
anchor_right = 1.0
anchor_bottom = 0.75
offset_left = 0; offset_top = 0; offset_right = 0; offset_bottom = 0
grow_horizontal = 2
grow_vertical = 2
```
**Inheritance caveat (must defeat the base scene).** Verified against source: the `anchors_preset = 9` / `anchor_bottom = 1.0` / `offset_right = 800.0` / `grow_vertical = 2` values live on the **root node of `scenes/ui/hole_viewer.tscn`**, and the `main_ui.tscn` instance line currently overrides only `layout_mode = 1`, `min_zoom = 20.0`, `max_zoom = 100.0`. A scene instance inherits the base root's layout for every property it does not explicitly override. **Therefore the fix is not "set `anchor_bottom = 0.75`" alone** — that would leave the inherited `offset_right = 800.0` and the preset-9 `anchor_right` fighting the intended full-width top band, and the viewport would not span the window width.

Decision (chosen path): **leave `hole_viewer.tscn` untouched and override all eight layout properties explicitly on the `main_ui.tscn` instance line** — `anchor_left = 0.0`, `anchor_top = 0.0`, `anchor_right = 1.0`, `anchor_bottom = 0.75`, `offset_left = 0.0`, `offset_top = 0.0`, `offset_right = 0.0`, `offset_bottom = 0.0`, plus `grow_horizontal = 2`, `grow_vertical = 2`. All four anchors **and** all four offsets must appear on the instance so no inherited value leaks through. (The alternative — changing the `hole_viewer.tscn` root to `PRESET_FULL_RECT` — is rejected because it edits a second scene and could affect any other instance of that scene; overriding on the single instance is the lower-blast-radius choice.) The `min_zoom`/`max_zoom` overrides stay. Because `HoleViewer`'s internal `ViewportContainer` is `PRESET_FULL_RECT` of `HoleViewer` and `stretch = true`, the `SubViewport` resizes to the band automatically — no code change needed for the container.

**Bottom tray (~25%).** A new node `Tray` (type `PanelContainer`, `unique_name_in_owner = true` so scripts/future code can find `%Tray`) is added to `MainUI`:
```
anchor_left = 0.0
anchor_top = 0.75
anchor_right = 1.0
anchor_bottom = 1.0
offset_* = 0
grow_horizontal = 2
grow_vertical = 2
```
This is fully anchor-based: the tray is always the bottom quarter at any window size (1920×1080 default, resized desktop, or portrait-ish mobile), scaling with the window as required. No hardcoded 1920×1080 offsets remain on the tray or HoleViewer.

**Tray interior.** Inside `Tray`:
- A `MarginContainer` (`TrayMargin`, ~16px margins, bottom extra for the brass rail read) →
- An `HBoxContainer` (`TrayContent`, `separation = 24`, `alignment = 1`) with three logical zones laid out left→right:
  - **Left/center (grows):** the existing `%HandStrip` `PanelContainer` re-parented here, `size_flags_horizontal = SIZE_EXPAND_FILL`. `%HandStrip` keeps its `Rows` → `%ClubRow` + `%ModifierRow` children exactly as-is.
  - **Right (fixed):** the existing `%ShootButton` re-parented here as the Snap-style primary action, `size_flags_vertical = SIZE_SHRINK_CENTER`. It ends up against the tray's right margin **not because it is the last HBox child** (an `HBoxContainer` does not pin its last child to the right edge; it simply packs children left-to-right) but because the preceding `%HandStrip` has `size_flags_horizontal = SIZE_EXPAND_FILL` and consumes all the horizontal slack, pushing the shrink-to-content button to the right. Its old bottom-center float anchors are dropped; it now sizes to content inside the HBox.

`%HandStrip` loses its floating bottom-center anchors (`anchors_preset = 7`, the ±420/−210 offsets) and becomes a container child with `SIZE_EXPAND_FILL`; its `StyleBoxFlat_handstrip` can stay or be slimmed since the tray felt now provides the backing (keep it for row contrast — decision: keep the handstrip stylebox but make the tray felt the dominant visual).

The tray's felt material (§3) is a `ShaderMaterial` set on `Tray.material` (a `Control` shader attaches via the node's `material` property, not via a `theme_override_styles/panel` stylebox). Decision: give `Tray` a `ShaderMaterial` (felt) on its `material` property, and a thin `StyleBoxFlat` panel (dark, near-opaque) as a fallback/base so the tray still reads dark even before/if the shader fails to load.

### 2.2 Camera framing adaptation (shorter viewport)

The viewport is now ~75% tall and full width, i.e. a **wider** aspect than the old near-square/left-panel shape. `_center_on_hole()` currently sets `target_zoom = clamp(max(hole_bounds.size.x * 2, hole_bounds.size.y * 0.5), min_zoom, max_zoom)` (verified against source). A hole is long in Z (grid_height ~40) and narrow in X (grid_width ~10); the wider-but-shorter viewport means the limiting dimension for fitting the hole lengthwise is now **vertical screen extent**, so without a change the hole can crop top/bottom.

Decision: make framing aspect-aware instead of hardcoded multipliers.
- In `_center_on_hole()`, compute the viewport aspect `aspect = float(viewport.size.x) / float(viewport.size.y)` (guard divide-by-zero; fall back to 16/9).
- Fit zoom so the hole's Z extent fits the vertical field and its X extent fits the horizontal field, taking the larger required zoom: `needed_for_z = hole_bounds.size.y * Z_FIT_FACTOR`, `needed_for_x = (hole_bounds.size.x * X_FIT_FACTOR) / aspect`, `target_zoom = clamp(max(needed_for_z, needed_for_x), min_zoom, max_zoom)`. `Z_FIT_FACTOR`/`X_FIT_FACTOR` are new tuning consts (start `Z_FIT_FACTOR = 0.55`, `X_FIT_FACTOR = 2.0`, matching today's effective behavior) so the change is a refinement, not a rewrite.
- Keep the existing `forward_shift` logic in `_update_camera_transform()` (tee at bottom of view) unchanged.
- Re-run framing on resize: in `HoleViewer._ready()` after `_setup_viewport()`, connect `viewport_container.resized` (the container, a `Control`, emits `resized`) to a handler `_on_viewport_resized()` that calls `_center_on_hole()` **only when not tracking the ball and not mid-interaction** (so a resize re-frames the hole but doesn't yank the camera off the ball during play). This keeps framing correct across window/orientation changes without fighting ball tracking.

Edge case: during the first frames `viewport.size` may be `(0,0)` before layout settles. `_find_references()` already runs `call_deferred`; additionally guard `_center_on_hole()` to skip (and retry next resize) if `viewport.size.y <= 1`.

### 2.3 HUD readouts → corners over the hole

Move the HUD out of mid-screen into compact corners **of the HoleViewer band** (so they overlay the hole, not the tray). These become children of `HoleViewer` (via a dedicated `HoleHUD` `Control` child of `HoleViewer`, `MOUSE_FILTER_IGNORE` so it never steals aim input) anchored to corners:
- `WindWidget` → top-left corner (keeps its existing script wiring; `hole_viewer.gd._setup_wind_display()` finds it via scene-wide `find_child("WindWidget", true, false)`, so re-parenting under HoleViewer does **not** break that lookup).
- `LieView` + `LieInfoPanel` (lie info) → left edge, below Wind.
- `HoleInfoLabel` (Par / hole) and shot-count from `ShotUI`'s readout → top-right corner, tucked beside the Generate buttons.
- `GenerateButton` + `GenerateUniqueButton` → **kept** (user decision), tucked into the top-right corner of the hole region, anchored to the top-right with a small inset. Their `pressed` signals are wired in `hex_grid._find_and_setup_ui()` (defined ~line 2572 of `scripts/hex_grid.gd`, called from `_ready`/`_setup_systems`) via `main_ui.generate_button` / `main_ui.generate_unique_button` (`@onready var generate_button := $GenerateButton`). Re-parenting them changes their node path, so `main_ui.gd`'s `$GenerateButton` / `$GenerateUniqueButton` `@onready` paths **must be updated** (see §5 — decision: switch to `%` unique-name lookups).

### 2.4 Retire decorative clutter

Set `visible = false` / remove from the active layout (do not delete scripts they may reference): `Panel` (Kenney border), `tiltshift` (already hidden), `icons` (hint sprites — the on-screen control affordances in §4.4 replace them), the three hidden tutorial `Label`/`Label2`/`Label3` at `MainUI` level. `DeckWidget` and `ModifierDeckUI` stay `visible = false` as today. Decision: keep the nodes present but hidden rather than deleting, to avoid disturbing any `@onready`/`find_child` lookups (`main_ui.gd` has `@onready var combined_deck_widget: DeckWidget = $DeckWidget`, a *typed* `@onready`, so deleting `DeckWidget` would null it and risk a load error — keeping it hidden is the safe, reversible choice).

### 2.5 ShotUI

`ShotUI` drives swing/shot flow and is wired in `hex_grid._find_and_setup_ui()` (`shot_ui = main_ui.shot_ui`, plus `update_target_info`, `club_name`, `club_range` label references used by `set_aim_cell`). Decision: keep `ShotUI` in the tree and functional; reposition/condense its **visible** readout parts into the hole-region HUD corner (§2.3), but do not rename it, change its node path relative to `main_ui.gd`'s `$ShotUI`, or touch its signal wiring. If `ShotUI`'s visible panel must move, move it by re-anchoring the child panel inside `ShotUI`, leaving the `ShotUI` root node as `$ShotUI`.

---

## 3. Task 2 — Prominent felt

### 3.1 Felt tray shader (new)

New file: `/Users/m22stewa/Documents/Godot/Golf/.worktrees/snaplayout/scripts/ui/felt_tray.gdshader`, `shader_type canvas_item;` (a 2D Control shader, since the tray is a `Control`). It renders a visibly woven dark-green felt with a stitched brass inner rail, cheap and procedural (no imported texture), consistent with the existing `turf.gdshader` value-noise family.

Uniforms and defaults:
```
uniform vec4 felt_dark  : source_color = vec4(0.133, 0.227, 0.149, 1.0); // ~#223a26
uniform vec4 felt_light : source_color = vec4(0.176, 0.290, 0.188, 1.0); // ~#2d4a30
uniform vec4 brass       : source_color = vec4(0.722, 0.573, 0.247, 1.0); // ~#b8923f
uniform float weave_scale   : hint_range(20.0, 400.0) = 160.0; // weave cells across the tray
uniform float weave_contrast: hint_range(0.0, 1.0)   = 0.35;   // err MORE prominent
uniform float fuzz_strength : hint_range(0.0, 0.3)   = 0.08;   // fine felt fuzz speckle
uniform float rail_thickness: hint_range(0.0, 0.1)   = 0.018;  // brass rail as fraction of min(uv)
uniform float rail_inset    : hint_range(0.0, 0.1)   = 0.010;
uniform float stitch_freq   : hint_range(0.0, 400.0) = 120.0;  // dashed stitch along the rail
uniform float tray_aspect   : hint_range(0.1, 10.0) = 7.0;     // tray_width/tray_height, set from script so stitch pitch is uniform in screen space
```
Weave model (woven over/under): use `UV * weave_scale` and build an over/under lattice from two orthogonal sine ridges whose phase alternates per cell — e.g. `warp = sin(uv.x*TAU*weave_scale)`, `weft = sin(uv.y*TAU*weave_scale)`, and select which thread is "on top" per cell with `step`/`mod` of the cell index so adjacent cells alternate (classic basket weave). Modulate albedo between `felt_dark` and `felt_light` by the weave mask scaled by `weave_contrast`. Add `fuzz = (value_noise(uv*weave_scale*6.0)-0.5)*2.0*fuzz_strength` for the fuzz. Reuse the same `hash2`/`value_noise` helpers as `turf.gdshader` so it reads as the same material family. Because the tray is physically small on screen, `weave_scale` is tuned high enough that the weave is clearly visible at a glance (this is the showcase surface — bias toward MORE prominent per the brief).

Brass rail: compute the border distance per axis, `edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y))`; the rail is the band `rail_inset <= edge <= rail_inset + rail_thickness`, drawn in `brass`. Within that band, multiply brightness by a dashed mask `step(0.5, fract(perimeter_coord * stitch_freq))` to read as stitching.

**`perimeter_coord` is defined explicitly:** the tray is a wide rectangle, so a single linear coordinate would give uneven stitch pitch between the long and short sides. Decision — make stitch pitch uniform in *screen space* by scaling the horizontal bands by `tray_aspect`:
- On the **top/bottom** bands (where `min(UV.y, 1.0-UV.y) < min(UV.x, 1.0-UV.x)`): `perimeter_coord = UV.x * tray_aspect`.
- On the **left/right** bands (otherwise): `perimeter_coord = UV.y`.
where `tray_aspect = tray_width / tray_height` is passed in as the `tray_aspect` uniform and refreshed from GDScript on `Tray.resized`. **Corner handling:** at the four corners the two bands meet and the dash phase is discontinuous; accept a small corner overlap (the brass simply fills the corner square) rather than attempting arc-length continuity — on a felt table edge a solid brass corner reads correctly and avoids corner artifacts. Visual-only, manual-verified per §8.

The shader is assigned as a `ShaderMaterial(shader = felt_tray.gdshader)` on the `Tray` node's `material` in `main_ui.tscn`. Default param values above are baked into the `ShaderMaterial` sub-resource in the scene so it reads correctly without script.

Fallback decision: procedural-first (matches the art pass which found procedural grain sufficient and added no baked PNG). If, in a verification screenshot, the weave reads flat, the fallback is a single small ≤256×256 tiling PNG under `/Users/m22stewa/Documents/Godot/Golf/.worktrees/snaplayout/textures/felt_weave.png` sampled with `REPEAT` — authored only if needed, kept as the sole baked texture.

### 3.2 Turf / rough felt — push further

**Primary (mandatory) edit — the mesh `.tres` overrides.** Verified against source: all four tile mesh materials pin the relevant shader parameters as `shader_parameter/...` overrides. Because a `ShaderMaterial` override wins over the shader's `uniform ... = default`, **raising the shader-file defaults alone renders no visible change on these tiles** — the `.tres` values are what actually render. The `.tres` edits are therefore the primary, non-conditional action, each with an explicit target value (only the listed `shader_parameter/...` lines change; ArrayMesh geometry and `base_color` are untouched):

| File | Param | Current (verified) | New |
|---|---|---|---|
| `scenes/tiles/fairway-mesh.tres` | `grain_strength` | 0.04 | **0.07** |
| `scenes/tiles/fairway-mesh.tres` | `stripe_strength` | 0.05 | 0.06 (optional nudge) |
| `scenes/tiles/green-mesh.tres` | `grain_strength` | 0.035 | **0.06** |
| `scenes/tiles/rough-mesh.tres` | `tuft_strength` | 0.08 | **0.11** |
| `scenes/tiles/rough-mesh.tres` | `tuft_scale` | 16.0 | **20.0** |
| `scenes/tiles/deeprough-mesh.tres` | `tuft_strength` | 0.09 | **0.13** |
| `scenes/tiles/deeprough-mesh.tres` | `tuft_scale` | 20.0 | leave 20.0 |

Note: `deeprough-mesh.tres` already sits at `tuft_strength 0.09` / `tuft_scale 20.0`, so its deltas differ from the others — bump `tuft_strength` to 0.13 for a feltier deep-rough and leave `tuft_scale` at 20.0 (already dense enough). Green uses a distinct explicit grain value (0.06) rather than reusing fairway's, so putting-surface grain stays slightly finer than fairway.

**Secondary (shader-source) edit — the new finer weave octave.** This is a genuine shader-code change with no `.tres` override to defeat it:
- `/Users/m22stewa/Documents/Godot/Golf/.worktrees/snaplayout/scripts/turf.gdshader` — in the `grain` expression, add a second, finer weave-like octave (reuse `value_noise` at `wxz*8.0` plus `wxz*18.0`, mixed) so the grain reads as a woven micro-texture rather than loose speckle. This changes *how* `grain_strength` is applied for every instance, including the fairway/green tiles, and does take effect regardless of the `.tres` override. Keep the `ROUGHNESS`/`METALLIC`/`SPECULAR` matte block unchanged.
- For consistency only, also raise the shader-file `grain_strength`/`stripe_strength` defaults in `turf.gdshader` and `tuft_strength`/`tuft_scale` defaults in `rough_turf.gdshader` to roughly match the new `.tres` values — but understand this default bump renders nothing on the four pinned tiles; it only affects any future material that does *not* pin the override. The `.tres` edits above are what change the look today.

Palette nudge (optional, "if easy" per brief): the `base_color` defaults live in the mesh `.tres` materials. Decision: leave the authored palette from the art pass as-is (already the muted sage/olive family per `FEAT-002`); do not repalette in this pass to avoid scope creep. Felt *weave strength* is the priority. Any desaturation toward sage/olive is deferred to a follow-up if the user wants it after seeing the stronger weave.

---

## 4. Task 3 — Cross-platform hole-view input (highest risk)

### 4.1 Input model and gating

`hole_viewer.gd` currently handles only `InputEventMouseButton` / `InputEventMouseMotion` in `_input()`, gated by `_is_mouse_inside()` and `_is_mouse_over_ui_control()`. The overhaul adds touch and gesture events and a tap-vs-drag discriminator, while keeping the existing mouse behavior and the aim-not-stolen-by-pan guarantee.

The band is now the top 75%; all "inside bounds" checks already use `get_global_rect().has_point(...)`, which stays correct because the rect follows the new anchors. The tray sits below HoleViewer, so touches/clicks in the tray fall outside HoleViewer's rect and are left for the tray UI (buttons) — no extra masking needed.

**emulate_mouse_from_touch:** with native touch handling added, leaving Godot's default mouse-from-touch emulation on would double-fire (a touch would produce both `InputEventScreenTouch` and a synthetic `InputEventMouseButton`). Decision: set `input_devices/pointing/emulate_mouse_from_touch = false` in `project.godot` and handle touch natively. We keep `emulate_touch_from_mouse` at its default (false) so desktop mouse stays real mouse events. Documented `project.godot` change (§4.6). (On desktop/trackpad there is no touch, so disabling touch→mouse emulation has no desktop effect; it only prevents double events on phones.)

### 4.2 Tap-vs-drag discriminator (shared by touch and mouse)

A tap (→ aim/select) must be distinguished from a drag (→ pan/rotate). A single helper state applies to both left-mouse and single-finger touch:
- On press/touch-down: record `press_pos`, `press_time = Time.get_ticks_msec()`, set `pending_tap = true`, do **not** aim yet.
- On move: if cumulative movement exceeds `TAP_MOVE_THRESHOLD` px, clear `pending_tap` and begin the drag gesture (pan for single pointer).
- On release/touch-up: if `pending_tap` is still true **and** `Time.get_ticks_msec() - press_time <= TAP_TIME_THRESHOLD`, treat as a tap → aim/select the tile under the release point; otherwise it was a drag, do nothing on release.

Constants: `TAP_MOVE_THRESHOLD = 10.0` (px; screen px is fine for all three modalities), `TAP_TIME_THRESHOLD = 350` (ms). This fixes the current desktop behavior too, where left-drag now pans but a left-click still reliably aims (left-click press no longer aims immediately; aim happens on release only if it was a tap), guaranteeing aim is never stolen by pan.

### 4.3 Per-modality gesture map (complete)

| Action | Desktop (mouse + keyboard) | Laptop trackpad | Phone touch |
|---|---|---|---|
| **Zoom** | Scroll wheel (`WHEEL_UP`/`WHEEL_DOWN` → `target_zoom ∓ zoom_speed`) | Pinch (`InputEventMagnifyGesture.factor`) **only**; plus on-screen +/− buttons | Two-finger pinch (`InputEventMagnifyGesture` where emitted; fallback: two-finger inter-finger distance change from two `InputEventScreenDrag`); plus on-screen +/− buttons |
| **Pan** | Left-drag (past tap threshold) OR hold `Space`+drag OR right-drag; arrow keys / WASD nudge | Two-finger scroll (`InputEventPanGesture.delta` → world pan) | One-finger drag (past tap threshold) |
| **Rotate (yaw)** | Middle-drag (horizontal) OR `Q`/`E` keys | On-screen Rotate button (guaranteed) OR two-finger twist (see §4.7) | On-screen Rotate button (guaranteed) OR two-finger twist (see §4.7) |
| **Pitch** | Middle-drag (vertical) | **Not adjustable** — camera stays at default pitch 55°; `Reset` re-asserts it (see note) | **Not adjustable** — camera stays at default pitch 55°; `Reset` re-asserts it (see note) |
| **Aim / select tile** | Left-click = tap (no drag, under time threshold) → `set_aim_cell` | Left-click / tap on trackpad = tap → `set_aim_cell` | Single-finger tap (no drag, under threshold) → `set_aim_cell` |
| **Hover preview** | Mouse motion → `set_hover_cell` | Mouse motion → `set_hover_cell` | *No hover on touch;* tap shows footprint preview for the tapped tile (see §4.5) |

Notes on the harder cases:
- **Pitch is desktop-only (decision).** Only desktop middle-drag (vertical component) adjusts `camera_angle` (pitch), clamped to the existing `MIN_PITCH = 25.0` .. `MAX_PITCH = 65.0` constants (verified present in `hole_viewer.gd`). On trackpad and touch nothing ever mutates `camera_angle`/`target_pitch`, so pitch simply never leaves its initial default of **55.0** (the current `camera_angle`/`target_pitch` initializers). Rationale: pitch is a minor comfort axis, not required to aim or read the hole; yaw (rotate), zoom, and pan are the controls that must be reachable everywhere, and they are. Flagged consequence: trackpad/touch users cannot tilt the camera; if playtesting shows they want it, the follow-up (explicitly out of scope) is a dedicated pitch affordance (a vertical drag handle in `HoleControls`) plus an axis-lock rule.
- **Reset-and-pitch contract (corrected against source).** The existing `reset_view()` (verified at `hole_viewer.gd` line 693) does **only** `target_yaw = 0.0`, `is_tracking_ball = true`, and re-centers; it **never touches** `camera_angle`/`target_pitch` and there is **no `DEFAULT_PITCH` constant** today. To make Reset a true "restore the view" control (and give desktop users a way to undo a middle-drag pitch change), `reset_view()` **must be modified** to also reset pitch, and a new constant added:
  ```gdscript
  const DEFAULT_PITCH: float = 55.0  # matches the initial camera_angle / target_pitch

  func reset_view() -> void:
      target_yaw = 0.0
      camera_angle = DEFAULT_PITCH
      target_pitch = DEFAULT_PITCH
      is_tracking_ball = true
      if ball_node and is_instance_valid(ball_node):
          center_on_ball(true)
      else:
          _center_on_hole()
  ```
  On trackpad/touch pitch never changed, so resetting it is a harmless no-op there (it stays 55.0); on desktop it restores pitch after a middle-drag tilt. This makes §4.3 (Pitch), §4.4 (Reset), and §10 self-consistent: Reset *does* restore default pitch because we add that line, not because the current method already did.
- **Trackpad / touch rotate** has no middle button and no modifier channel. The **guaranteed** rotate path on both is the on-screen Rotate affordance button (§4.4), which steps yaw by a fixed increment. Two-finger twist is shipped as a **best-effort** enhancement (§4.7 specifies the exact math); it is never the sole path, so rotate is always reachable even if twist detection is flaky on a device. No `Shift`+two-finger-drag rotate channel is used (removed to eliminate the yaw/pitch decomposition ambiguity).
- **Trackpad two-finger scroll** arrives as `InputEventPanGesture` (macOS) — mapped to **pan** (native scroll convention), not zoom. Trackpad zoom is **pinch only** (`InputEventMagnifyGesture`). The earlier "Ctrl/Cmd + two-finger scroll → zoom" path is **dropped**: `InputEventPanGesture` carries no key-modifier state, so that mapping was not implementable without sampling `Input.is_key_pressed(...)` in the handler, and it overlapped the unmodified pan mapping. Pinch already covers trackpad zoom natively. Matches macOS conventions (pinch = zoom, two-finger scroll = pan).
- Keyboard `Q`/`E` (rotate) and arrows/WASD (pan nudge) are handled only while the hole band has focus or the pointer is over it, and only when not typing elsewhere. WASD/arrows already exist as `left`/`right`/`up`/`down` input actions in `project.godot` (bound to A/D/W; `down` is empty today) — we reuse those for pan nudge and add explicit new actions for the rest (§4.6).

### 4.4 On-screen control affordances

A small `Control` cluster (`HoleControls`, child of `HoleViewer`'s HUD layer, `MOUSE_FILTER_STOP` on the buttons only so they consume their own clicks) pinned to a hole-region corner (decision: bottom-right of the hole band, above the tray, so it doesn't collide with the top-corner HUD/Generate buttons). Subtle, corner, consistent with the clean look. Buttons:
- **Zoom In (+)** → `set_zoom(target_zoom - zoom_speed)` (closer).
- **Zoom Out (−)** → `set_zoom(target_zoom + zoom_speed)` (farther).
- **Rotate** → rotate yaw by a fixed step (`target_yaw += deg_to_rad(45)`); repeated presses cycle around. This is the **guaranteed** trackpad/touch rotate path (two-finger twist is only a best-effort supplement).
- **Reset view** → `reset_view()` — now modified (§4.3) to reset yaw **and** pitch to `DEFAULT_PITCH = 55.0`, re-center on ball/hole, and re-enable tracking. On trackpad/touch, pitch never moved so this is effectively a yaw/center reset; on desktop it also undoes a middle-drag tilt.

There is intentionally **no pitch affordance** here: pitch is desktop-only (§4.3), so adding a pitch control would imply a capability trackpad/touch do not have. Keeping the cluster to zoom/rotate/reset also keeps it subtle per the clean-look brief.

These buttons are `BaseButton`s, so the existing `_is_mouse_over_ui_control()` already returns true for them and the camera won't treat a button press as a pan/aim — no special-casing needed beyond adding them as controls.

### 4.5 Aiming & putting continuity

Aiming must keep working under the new model:
- **Hover** (`set_hover_cell`): unchanged for mouse/trackpad via `_update_hovered_tile()` in `_process`. On touch there is no hover; `_update_hovered_tile()` reads `get_local_mouse_position()` which is meaningless under touch, so it is guarded to **skip hover updates when the last input was touch** (track `last_input_was_touch: bool`, set true on any `InputEventScreenTouch`/`ScreenDrag`, false on real mouse motion).
- **Tap-to-aim on touch (documented behavior):** because there is no hover on touch, a single-finger **tap** calls the same `_handle_tile_click(tap_pos)` → `hex_grid.set_aim_cell(tile)` path that a desktop left-click uses. Verified against `scripts/hex_grid.gd` line 2021: `set_aim_cell` returns `false` as its first line when `not is_valid_target(cell)`; on a valid tile it sets `locked_cell`/`target_locked` and calls `_update_aoe_for_cell(locked_cell)` + `_update_trajectory(...)` **before** the `if shot_ui and golf_ball:` guard. So on touch, **the footprint/AOE/trajectory preview appears for the tapped tile** even when `ShotUI` is absent, and tapping another tile re-aims. This is the explicit touch aiming contract: tap = both "hover" and "select" collapsed into one gesture. Mirror this in a code comment in `_handle_tile_click`. A tap on an invalid tile returns `false`, locks nothing, surfaces no error, and leaves the preview on the last valid aim.
- **Putting (touch path, fully specified).** `_handle_putting_mouse_button` (line 489) routes a real `InputEventMouseButton` with `button_index == MOUSE_BUTTON_LEFT` to `putting_system.handle_input(event)` (line 504) and right-click to pan. Since `putting_system` is `null` today (retired), these branches are inert but **preserved unchanged**. For touch, the flow is:
  1. The **tap/drag discriminator (§4.2) runs first**, even in putting mode — a single-finger drag pans (pan stays available in putting mode), and only a classified **tap** (not a drag) is a candidate for putting input.
  2. On a classified tap while `is_putting_mode`, we **synthesize an `InputEventMouseButton`** (not forward the `InputEventScreenTouch`, whose API is `index`/no `button_index` and would not match `handle_input`'s contract): set `button_index = MOUSE_BUTTON_LEFT`, emit it `pressed = true` then `pressed = false`, with `position = tap_pos`, and forward each to `putting_system.handle_input(...)` **guarded on `putting_system != null`**.
  3. Because `putting_system` is null today, this guard means the forward is a safe no-op now; if putting is ever un-retired, the synthesized mouse event preserves the exact mouse-based contract `handle_input` expects. This keeps putting input working under the new model without resurrecting the retired system.

### 4.6 project.godot changes (enumerated)

Only input settings are edited in `/Users/m22stewa/Documents/Godot/Golf/.worktrees/snaplayout/project.godot` (no gameplay settings):
1. Add under `[input_devices]` (new section): `pointing/emulate_mouse_from_touch=false` (prevents double-firing with native touch handling). (`emulate_touch_from_mouse` left default/false.)
2. Add new input actions under `[input]` for discoverable, remappable camera control (keyboard + semantic names used by the gesture handler):
   - `cam_pan` (bound to `Space` as the modifier-drag enabler),
   - `cam_rotate_left` (`Q`), `cam_rotate_right` (`E`),
   - `cam_zoom_in` (`=`/`+`), `cam_zoom_out` (`-`),
   - reuse existing `left`/`right`/`up`/`down` (A/D/W already bound) for pan nudge; bind the currently-empty `down` action to `S`.
   Each as the standard `[input]` action dict (deadzone + `events` array of `InputEventKey`), matching the existing `left`/`right`/`up` format already in the file.

The two pre-existing font errors (`uid://csixfh5trj68q`) are the accepted baseline and are **not** touched.

### 4.7 Which InputEvent types are handled

In `hole_viewer.gd._input(event)` (and `_unhandled_input` for keyboard where appropriate):
- `InputEventMouseButton` — existing: wheel zoom, middle pitch/rotate, right pan, left tap-aim (now via tap discriminator).
- `InputEventMouseMotion` — existing: hover + active-drag pan/rotate.
- `InputEventScreenTouch` — new: finger down/up, drives tap discriminator and multi-touch tracking (`index`, `pressed`, `position`). Maintain a `touches: Dictionary[index→position]`.
- `InputEventScreenDrag` — new: finger move; one finger → pan; two fingers → pinch (zoom) + twist (rotate), per the concrete rule below.
- `InputEventMagnifyGesture` — new: trackpad pinch and touch pinch (where emitted) → zoom via `factor`.
- `InputEventPanGesture` — new: trackpad two-finger scroll → **pan** (`delta`) only. No modifier branch (the event carries no key-modifier state, and pinch handles trackpad zoom).
- Keyboard via input actions (`Input.is_action_pressed`/`_just_pressed`) in `_process`/`_unhandled_input`: `cam_rotate_left/right`, pan nudge (`left/right/up/down`), `cam_zoom_in/out`.

**Two-finger pinch + twist (concrete rule, chosen over "best-effort" hand-waving).** The review required either scoping twist out or specifying it. Decision: **specify it** as two independent axes derived every two-finger frame — they do not need pinch-vs-twist disambiguation because they are orthogonal measures of the same pair of positions:
- Maintain the two current touch positions `p0`, `p1` (from the `touches` dictionary, updated by each `InputEventScreenDrag`).
- **Pinch (zoom):** `dist = p0.distance_to(p1)`. Each two-finger frame compute `factor = dist / prev_dist` (guard `prev_dist > 0`); apply `target_zoom = clamp(target_zoom / factor, min_zoom, max_zoom)` (fingers apart → `factor > 1` → zoom in), then store `prev_dist = dist`.
- **Twist (rotate):** `ang = atan2(p1.y - p0.y, p1.x - p0.x)`. Each two-finger frame compute `d_ang = wrapf(ang - prev_ang, -PI, PI)` (wrap handling), apply `target_yaw += d_ang`, then store `prev_ang = ang`.
- Seed `prev_dist`/`prev_ang` on the frame the second finger lands; no cross dead-zone — small simultaneous distance and angle changes both apply, which feels natural. The on-screen Rotate button remains the guaranteed rotate path; this twist is the native-gesture enhancement, now fully specified so the implementer isn't inventing it. If `InputEventMagnifyGesture` is also delivered on a device, pinch is taken from `factor` and the `ScreenDrag` distance path is the fallback only (don't double-apply: prefer `MagnifyGesture` when present in the same frame).

Multi-touch bookkeeping: track active touches in a dictionary keyed by `index`; 1 active → single-pointer gestures; 2 active → pinch/twist; on the frame a second finger lands, cancel any pending single-finger pan/tap so a two-finger gesture doesn't leave a stale pan, and seed `prev_dist`/`prev_ang`. On any `InputEventScreenTouch` with `pressed == false`, erase that index; if `touches` empties, clear `is_panning`/`is_rotating`/`pending_tap`.

---

## 5. Preserving unique names through re-parenting (the critical invariant)

Enforcement owner: the **scene file** (`main_ui.tscn`) owns the `unique_name_in_owner` flags; `main_ui.gd` owns the `@onready` path lookups. Both must stay consistent. Rules applied:

- **Unique-named nodes** `%HandStrip`, `%ClubRow`, `%ModifierRow`, `%ShootButton`: re-parented into `Tray` but keep `unique_name_in_owner = true` and keep their node `name`. `main_ui.gd` resolves them with `get_node_or_null("%ShootButton")` etc. (not fixed paths), so re-parenting is transparent. `hex_grid.gd` reaches `%ShootButton` via `main_ui_ref.shoot_button` (itself a `%`-lookup) and the `club_card_selected`/`modifier_card_selected` signals on `main_ui` — all path-independent. The live-hand test uses `main_ui.get_node_or_null("%ClubRow")` / `"%ShootButton")` — path-independent. **Verdict: re-parenting these four is safe with zero script edits**, provided `unique_name_in_owner` stays set (verify in the edited `.tscn`).
- **Path-based `@onready` nodes in `main_ui.gd`** use `$Name` (fixed child paths): `$ShotUI`, `$DeckWidget`, `$WindWidget`, `$LieView`, `$HoleInfoLabel`, `$HoleViewer`, `$GenerateButton`, `$GenerateUniqueButton`. Any node we re-parent that is referenced by `$` **must have its `@onready` path updated** in `main_ui.gd`. Decision to minimize edits:
  - `$HoleViewer` — we re-anchor but do **not** re-parent (stays a direct child of `MainUI`); path unchanged.
  - `$ShotUI`, `$DeckWidget` — stay direct children of `MainUI` (only visibility/inner panel moves); paths unchanged.
  - `$WindWidget`, `$LieView`, `$HoleInfoLabel` — re-parented under a `HoleHUD`/`HoleViewer` child for corner placement. **Decision: set `unique_name_in_owner = true` on these three in the `.tscn` and switch their `main_ui.gd` `@onready` lookups to `%`-form** so future re-parenting never breaks them again. `hole_viewer.gd` finds `WindWidget` via scene-wide `find_child`, which is unaffected.
  - `$GenerateButton`, `$GenerateUniqueButton` — re-parented to the top-right hole corner; **decision: add `unique_name_in_owner = true` and switch to `%GenerateButton`/`%GenerateUniqueButton`**. `hex_grid._find_and_setup_ui()` reads them as `main_ui.generate_button` (the `@onready` var), so fixing the var's lookup fixes hex_grid too.

Net: the four hand-UI unique names need **no script change** (only `.tscn` re-parent). The five `$`-path HUD/dev nodes that physically move need their `main_ui.gd` `@onready` lookups switched to `%` unique-name form (and `unique_name_in_owner = true` set in the `.tscn`). This is the complete, enumerated set of code touches required by re-parenting.

---

## 6. Files to touch (absolute worktree paths)

Under `/Users/m22stewa/Documents/Godot/Golf/.worktrees/snaplayout`:

Edited:
- `scenes/ui/main_ui.tscn` — re-anchor `HoleViewer` to top 0..0.75; add `Tray` `PanelContainer` (0.75..1.0) with felt `ShaderMaterial`; re-parent `%HandStrip`/`%ShootButton` into the tray; re-parent/re-corner `WindWidget`, `LieView`, `LieInfoPanel`, `HoleInfoLabel`, `GenerateButton`, `GenerateUniqueButton`; set `unique_name_in_owner = true` on the moved HUD/dev nodes; add `HoleControls` affordance cluster + `HoleHUD` container (children of `HoleViewer`); hide `Panel`/`tiltshift`/`icons`/hidden `Label`s; embed the felt `ShaderMaterial` sub-resource.
- `scripts/ui/main_ui.gd` — switch moved nodes' `@onready` lookups from `$Name` to `%Name`; no change to the four hand-UI `%` lookups or the card-population logic.
- `scripts/hole_viewer.gd` — aspect-aware `_center_on_hole()` + resize handler; add `InputEventScreenTouch/ScreenDrag/MagnifyGesture/PanGesture` handling; tap-vs-drag discriminator; two-finger pinch+twist math (§4.7); keyboard action handling; touch-aware hover guard; on-screen affordance button hookups; **modify `reset_view()` to reset pitch and add `const DEFAULT_PITCH = 55.0`** (§4.3); preserve putting branches (guarded) and add the synthesized-mouse touch-putting forward (§4.5). Add tuning consts (`TAP_MOVE_THRESHOLD`, `TAP_TIME_THRESHOLD`, `Z_FIT_FACTOR`, `X_FIT_FACTOR`, `DEFAULT_PITCH`).
- `scenes/tiles/fairway-mesh.tres`, `green-mesh.tres`, `rough-mesh.tres`, `deeprough-mesh.tres` — **primary felt edit**: set the explicit `shader_parameter/...` override values in the §3.2 table; ArrayMesh geometry and `base_color` untouched. (Not conditional — verified all four pin the params.)
- `scripts/turf.gdshader` — add the finer weave octave in the `grain` expression (real shader-source change); bump `grain_strength`/`stripe_strength` defaults for consistency (renders nothing on pinned tiles, see §3.2).
- `scripts/rough_turf.gdshader` — bump `tuft_strength`/`tuft_scale` defaults for consistency (same caveat).
- `project.godot` — `[input_devices] pointing/emulate_mouse_from_touch=false`; new `[input]` actions (`cam_pan`, `cam_rotate_left/right`, `cam_zoom_in/out`, bind `down`→S).

New:
- `scripts/ui/felt_tray.gdshader` — procedural woven-felt + brass rail `canvas_item` shader.
- (Conditional) `textures/felt_weave.png` — only if procedural weave reads flat in verification shots.

Not touched: `models/`, `.md` docs, `.github/`, gameplay/turn-loop/scoring/card-system logic, `hex_grid.gd` structure (we only *call* its existing `set_aim_cell`/`set_hover_cell`/`set_external_camera`/`reset_view`), the retired `putting_system`, the two baseline font errors.

---

## 7. Error handling & validation (per fallible operation)

- **Viewport not yet sized** (`_center_on_hole` early): if `viewport == null` or `viewport.size.y <= 1`, skip framing and retry on next `resized` signal. Recoverable, not fatal, not logged (expected during layout settle).
- **hex_grid not found** (`_find_references`): existing fallbacks (`get_node_or_null` chain + recursive search) retained; if still null, camera still renders (world shared), aiming no-ops until re-acquired via the existing `_update_wind_display` re-acquire path. Recoverable; no new logging.
- **`set_aim_cell` returns false** (invalid tile tapped/clicked): no lock, preview unchanged, no error surfaced. Expected, not logged.
- **Gesture with stale touch index** (finger-up missed): on any `InputEventScreenTouch` with `pressed == false`, erase that index from `touches`; if `touches` empties mid-gesture, clear `is_panning`/`is_rotating`/`pending_tap`/`prev_dist`/`prev_ang`. Prevents a stuck pan/zoom. Recoverable, not logged.
- **Pinch with `prev_dist == 0`** (first two-finger frame or coincident fingers): guard `prev_dist > 0.001` before dividing; skip that frame's zoom. Recoverable, not logged.
- **Magnify/Pan gesture on a platform that doesn't emit them** (plain desktop mouse): those branches simply never fire; wheel-zoom and drag-pan cover desktop. No validation needed — absence is the normal case.
- **Shader compile failure** (felt_tray): Godot logs a shader error and the Control falls back to its base `StyleBoxFlat` (dark panel). Caught at author time by the headless import check (§8). Fatal to the felt look but not to playability — the tray still functions as a container.
- **Re-parent breaks a `%`/`$` lookup**: caught by the live-hand test (unique names) and by a headless scene-load (typed `@onready` vars like `$DeckWidget: DeckWidget` would push a null/type error on load). Both are run in §8.

### External-input validation rules
- **Tap vs drag:** movement input, px; required; threshold `TAP_MOVE_THRESHOLD = 10.0`; on exceed → drag, else on release within `TAP_TIME_THRESHOLD = 350 ms` → tap. Failure mode (neither): no-op.
- **Zoom:** `target_zoom` always `clamp(_, min_zoom, max_zoom)` (existing exports, overridden to 20/100 in `main_ui.tscn`). Out-of-range inputs clamp, never error.
- **Yaw:** unbounded (wraps via `lerp_angle`/`wrapf`); pitch `clamp(_, MIN_PITCH 25°, MAX_PITCH 65°)` (existing; only touched by desktop middle-drag and `reset_view`).
- **Pinch factor** (`InputEventMagnifyGesture.factor` or computed ratio): multiply/divide `target_zoom`, then clamp.
- **Touch index:** integer from the OS; used only as a dictionary key; no range assumption.

### Invariant ownership
- *"Aim is never stolen by pan"* — owned by the tap-vs-drag discriminator in `hole_viewer.gd`: aim fires only on a release classified as a tap. Chosen there because it's the single place both mouse and touch pointers converge.
- *"HoleViewer renders the shared world"* — owned by `_share_world()` (unchanged); re-anchoring doesn't affect world sharing.
- *"Unique names resolve"* — owned by `main_ui.tscn` flags + `main_ui.gd` lookups (§5).
- *"Reset restores the default view"* — owned by `reset_view()` *after* the §4.3 modification that adds the pitch reset; before the modification the method does not restore pitch (verified), so the implementer must apply that change.

---

## 8. Testability & verification

Unit-testable in isolation: the tap-vs-drag classifier (pure function of positions + timestamps — extractable/callable headless), the aspect→zoom math in `_center_on_hole`, the twist/pinch delta math (pure functions of two positions). Decision: keep them as small, directly-callable methods so they *can* be unit-tested.

Integration (headless, the gates that must stay green):

**Step 0 — prime the import cache and capture the real baseline (required first).** This worktree has **no `.godot/` import directory** (verified). A first headless run against an un-imported project performs a (re)import pass, and several resources here are referenced only by `uid://` (e.g. `project.godot run/main_scene = "uid://i0lqex70w705"`, the font uids), so the gates below can spuriously fail or report a different error set on a cold first invocation. Therefore, before any change:
   1. Prime the cache: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/m22stewa/Documents/Godot/Golf/.worktrees/snaplayout --import` (or `--editor --quit` if `--import` is unavailable in this build), and confirm it completes and `.godot/` now exists.
   2. **Capture the actual in-worktree baseline error set** from a clean run of each gate below *before* touching anything, and save it. The "2 accepted font-uid errors (`uid://csixfh5trj68q`)" are **not assumed** identical here — the real baseline is whatever this primed worktree emits. All "no new errors" judgments are measured against *this captured baseline*.

1. **Live-hand wiring** (the named must-pass test):
   `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/m22stewa/Documents/Godot/Golf/.worktrees/snaplayout scenes/tests/test_live_hand_wiring.tscn` → exit 0. Proves `%ClubRow`/`%ShootButton` survive the re-parent and the whole deal→select→Shoot loop works.
2. **Turn loop:** `… scenes/tests/test_turn_loop.tscn` → exit 0 (unchanged gameplay).
3. **Scene import / compile:** `/Applications/Godot.app/Contents/MacOS/Godot --headless --path … --editor --quit` (or a one-frame headless load of `GOLF.tscn`) → **no new errors beyond the Step 0 captured baseline**; confirms `main_ui.tscn` re-parent, `felt_tray.gdshader` compile, `turf`/`rough_turf` shader compile, the `.tres` param edits load, and the `project.godot` input edits parse.
4. **Playability smoke:** headless load of `scenes/GOLF.tscn` for N frames asserting no script errors (the touch/gesture handlers must not throw on a desktop-only headless run — gesture branches simply don't fire; `reset_view()` with the new pitch lines must not error).

Hard-to-test and handled by manual/visual check (documented as such): actual felt weave prominence (tray + fairway/green/rough `.tres` strengths), trackpad two-finger/pinch feel, and on-device touch gestures (one-finger pan, two-finger pinch+twist, tap-to-aim) — verified via screenshots (reuse `scenes/tests/capture_course.tscn`) and a note that trackpad/touch feel needs a human on real hardware. Keeping `set_aim_cell`/`_handle_tile_click` as the single aim sink keeps the loop headless-testable regardless of input modality.

Cleanup: any scratch capture scene/screenshot created for verification is removed after.

---

## 9. Flagged assumptions (unverified)

- **A2:** `HoleViewer`'s internal `ViewportContainer` is `PRESET_FULL_RECT` + `stretch`, so the `SubViewport` follows the re-anchored band with no code change. Verified by reading `_setup_viewport()`.
- **A3:** `putting_system` is `null` in the current build (verified: `_init_putting_system()` is a no-op). The putting input branches are preserved but inert; the touch forwarding is guarded on non-null. If putting is later un-retired, the guarded synthesized-mouse path (§4.5) activates with the mouse contract preserved.
- **A4:** `InputEventMagnifyGesture`/`InputEventPanGesture` are delivered for macOS trackpads in Godot 4.7 (standard behavior); their emission on specific phones is device-dependent, so touch pinch also has the two-`ScreenDrag` distance fallback (§4.7). Not verified on hardware — flagged for on-device testing.
- **A5:** All four mesh `.tres` files pin `grain_strength`/`stripe_strength`/`tuft_strength`/`tuft_scale` overrides (verified by grep). The `.tres` edits are the rendering change; the shader-default bumps render nothing on these tiles and exist only for consistency/future materials. The new grain octave in `turf.gdshader` is a shader-source change that *does* take effect on the pinned tiles.
- **A6:** `emulate_mouse_from_touch` default is on in Godot; disabling it is required to avoid double input. Standard behavior, not empirically confirmed in this build — low risk. No legacy touch UI depends on mouse-emulation today (the only touch surface is the hole band, handled natively).
- **A7:** Switching the moved HUD/dev nodes to `unique_name_in_owner` + `%` lookups is a behavior-preserving refactor of `main_ui.gd`'s `@onready` lines; verified safe because `hex_grid` reads them through those same `@onready` vars, not fixed paths.
- **A8:** `DEFAULT_PITCH = 55.0` is a **new** constant (verified: it does not exist today; the default pitch is the `camera_angle`/`target_pitch` initializer `55.0`). It must be added alongside the `reset_view()` modification.

---

## 10. Responses to design review findings

This revision addresses **every** finding in the on-disk `design-review.md` / `design-verdict.json` (verdict `CHANGES_REQUESTED`: 1 HIGH, 3 MEDIUM, 2 NIT). These are a real review of *this* snaplayout design — §0 is corrected to reflect that (an earlier draft wrongly dismissed the verdict as a stale gameloop artifact; the findings, locations, and reviewDoc all concern this document, so they are treated as a genuine revision pass). Each source claim the review made was re-verified against the worktree before applying the fix.

- **Finding 1 [HIGH] — `reset_view()` does not restore pitch; the pitch-fallback contract was false. ADDRESSED (option a).** Verified: `reset_view()` (line 693) sets only `target_yaw`/`is_tracking_ball` and re-centers; it never touches `camera_angle`/`target_pitch`, and no `DEFAULT_PITCH` existed. Fix: §4.3 now specifies modifying `reset_view()` to set `camera_angle = DEFAULT_PITCH` and `target_pitch = DEFAULT_PITCH`, and adds `const DEFAULT_PITCH = 55.0` (matching the current initializer), with the full snippet. §4.3 (Pitch row/note), §4.4 (Reset), §6 (files), §7 (invariant), and §8 (gate 4) are all made consistent: Reset restores pitch *because we add that line*, not because the current method did. On trackpad/touch pitch never changes, so the reset is a harmless no-op there.

- **Finding 2 [MEDIUM] — turf/rough `.tres` edits were framed as conditional, but all four `.tres` pin the params. ADDRESSED.** Verified via grep: `fairway grain 0.04/stripe 0.05`, `green grain 0.035`, `rough tuft 0.08/scale 16.0`, `deeprough tuft 0.09/scale 20.0` — all pinned, so shader-default bumps alone render nothing. §3.2 is rewritten: the `.tres` override edits are now the **primary, non-conditional** action with an explicit per-file target table (fairway grain 0.04→0.07; green grain 0.035→0.06; rough tuft 0.08→0.11, scale 16→20; deeprough tuft 0.09→0.13, scale left at 20.0 since it already matches). Shader-source edits are kept only for the genuinely-effective new finer weave octave in `turf.gdshader`'s `grain` expression, plus default-consistency bumps that are explicitly noted to render nothing on the pinned tiles. §6 and A5 updated to list the `.tres` edits as mandatory.

- **Finding 3 [MEDIUM] — touch putting forward left the synthesized event type and tap/drag gating unspecified. ADDRESSED.** Verified: `_handle_putting_mouse_button` forwards a real `InputEventMouseButton` (`button_index == MOUSE_BUTTON_LEFT`) to `putting_system.handle_input`. §4.5 now specifies: the tap/drag discriminator runs first (a drag pans; only a classified tap is a putting candidate), and a tap **synthesizes an `InputEventMouseButton`** (button_index=LEFT, pressed true then false, position=tap_pos) forwarded to `putting_system.handle_input` guarded on non-null — not a raw `InputEventScreenTouch`, whose API wouldn't match. Inert today (system null), correct if un-retired.

- **Finding 4 [MEDIUM] — two-finger twist/pinch math and disambiguation unspecified. ADDRESSED (specified, not scoped out).** §4.7 now gives the concrete rule: pinch factor = `current / previous inter-finger distance` applied to `target_zoom` (clamped, guarded on `prev_dist > 0.001`); twist = per-frame `wrapf` delta of `atan2(p1.y-p0.y, p1.x-p0.x)` applied to `target_yaw`; both applied every two-finger frame as independent orthogonal axes with no cross dead-zone; `prev_dist`/`prev_ang` seeded when the second finger lands and cleared when touches empty; prefer `MagnifyGesture.factor` over the ScreenDrag distance when both arrive in a frame (no double-apply). The on-screen Rotate button remains the guaranteed path; twist is the now-fully-specified enhancement.

- **Finding 5 [NIT] — `DEFAULT_PITCH` referenced as if it exists. ADDRESSED.** §4.3 and new assumption A8 state explicitly that `DEFAULT_PITCH = 55.0` is a **new** constant to add (tied to Finding 1), matching the current `camera_angle`/`target_pitch` initializer; `MIN_PITCH`/`MAX_PITCH` are the existing constants referenced for the clamp.

- **Finding 6 [NIT] — muddled provenance (§0 disowned the verdict while §10 answered it). ADDRESSED.** §0 is rewritten to treat the on-disk verdict/review as a genuine review of this design and this pass as a revision; §10's opening sentence now names the same artifacts. The internal contradiction is removed.

No finding was backlogged or ignored. None of the fixes alter the original requirements — they tighten precision and correct two claims that were wrong against source (Findings 1 and 2), staying inside the "no gameplay/turn-loop/scoring/card-system changes" constraint.


# Copilot Instructions for the Godot Golf Project

## Project Overview
- Godot 4.x project for procedural golf course prototyping and 3D scene navigation.
- Custom scripts and scenes are present in `scripts/` and `scenes/`.
- Includes a third-party Fly Camera addon for free 3D navigation during prototyping.

## Key Files & Structure
- `project.godot`: Main Godot project config (edit via Godot Editor only).
- `scenes/main.tscn`: Main scene, wires up UI, camera, and course generator.
- `scripts/CourseGenerator.gd`: Procedural golf course generator, grid-based, visualizes 3D meshes and labels.
- `assets/fly_camera_addon-*/addons/sk_fly_camera/`: Fly Camera addon (see `src/fly_camera.gd` for controls/settings).
- `scenes/camera_3d_2.gd`: Example custom camera script (not always used).

## Addon Usage: Fly Camera
- To enable free 3D navigation, add a `FlyCamera` node (from the addon) to your scene.
- Default controls: WASD to move, Shift/Ctrl to change speed, RMB to toggle mouse look.
- Controls and settings are customizable via inspector or script.
- Addon is self-contained; no project settings changes required unless customizing input actions.

## Procedural Course Generation
- `CourseGenerator.gd` generates a grid-based golf course with random hazards, fairways, and greens.
- UI button in `main.tscn` triggers regeneration (`_on_button_pressed`).
- Visualization uses `MeshInstance3D` and `Label3D` for each cell; colors and codes are mapped per surface type.
- All logic for grid, hazards, and visualization is in `CourseGenerator.gd`.

## Developer Workflow
- **Editing:** Use Godot Editor for scenes, scripts, and assets. Avoid manual edits to `.import`/`.godot` files.
- **Run/Test:** Press F5 or the play button in Godot Editor to run the main scene.
- **Version Control:** Only commit source assets/scripts. Ignore `.godot/` and platform-specific build folders.
- **Adding Scripts:** Place new `.gd` files in `scripts/` or `scenes/` as appropriate.
- **Addon Registration:** Addons are under `assets/`; register via Godot Editor if not already enabled.

## Scene-Driven Editing Preference
- Prefer scene-driven setup for visuals and content whenever feasible (textures, materials, meshes, node layout, label placement, visibility defaults).
- Avoid applying/overriding presentation details in code unless it is truly dynamic (e.g., runtime animations, procedural generation, data-driven text updates).
- When code needs to support visuals, treat it as a fallback: only set textures/materials if the scene did not already define them.
- Goal: maximize the ability to open a `.tscn` and visually verify the result without running gameplay logic.

## Project Conventions & Patterns
- Scripts use `.gd` extension and are attached to nodes/scenes.
- Scene structure: `main.tscn` is the entry point; UI and logic are connected via signals.
- Procedural logic is centralized in `CourseGenerator.gd`.
- Addons are kept in `assets/` and not mixed with main project scripts.

## Integration Points
- No external dependencies beyond the Fly Camera addon.
- Addon is isolated; no cross-component communication required.
- All procedural generation and visualization is handled in `CourseGenerator.gd`.

---
_Update this file as the project evolves, especially when adding new workflows, scripts, or dependencies._

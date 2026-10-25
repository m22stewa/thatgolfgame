**AI DESIGN: Hex Golf Roguelike Architecture**

This project is a **Balatro‑style arcade golf roguelike** implemented in **Godot 4.5** using **GDScript** and a **scene + script** architecture.​  
The core idea: a hex‑based golf course, where each shot is modified by cards and passives that change the AOE, physics, scoring, and tile state.

The hole generation (grid of hex tiles, ball, UI, etc.) is **already implemented**.  
There is currently a **single main script** that controls AOE and returns a list of neighbor IDs/coordinates like "tile_2_9" or entries in an array.

Copilot should help **refactor** and **extend** the project into small, single‑purpose scripts, without rewriting the existing generator.

---

## IMPLEMENTATION STATUS

*Last Updated: December 2024*

### ✅ Completed Systems

**Core Shot System** (in `scripts/`)
- `shot_context.gd` - Data object for shot state (chips, mult, AOE, physics, curve, bounce tracking)
- `shot_manager.gd` - Shot lifecycle phases with signals (10 phases from start to cleanup)
- `modifier_manager.gd` - Holds modifiers, calls lifecycle methods at each phase
- `aoe_system.gd` - Computes AOE tiles from center
- `shot_ui.gd` - Complete shot UI display with swing meter integration
- `hex_tile.gd` - Tile data with terrain, elevation, tags
- `lie_system.gd` - Terrain-based shot modifiers (power, accuracy, spin, roll)
- `putting_system.gd` - Separate putting flow with aim circle and power bar
- `wind_system.gd` - Wind generation and effect calculation (not yet fully integrated with shots)

**Cards & Deck System** (in `scripts/cards/`)
- `card_data.gd` - Resource class for card blueprints (id, name, rarity, type, effects)
- `card_effect.gd` - Base class for modular card effects with trigger conditions
- `card_instance.gd` - Runtime card wrapper (upgrade level, uses, temp modifiers)
- `deck_manager.gd` - Draw/hand/discard pile management with shot lifecycle hooks
- `card_modifier.gd` - Bridge class connecting CardInstance to ModifierManager
- `card_library.gd` - Static library of all cards with factory methods
- `card_system_manager.gd` - Central controller integrating cards with shot system
- `deck_definition.gd` - Resource for defining deck contents (starter deck, club deck)
- `deck_view_3d.gd` - 3D deck visualization with draw animations
- `card_3d.gd` - 3D card representation for deck view

**Card Effects** (in `scripts/cards/effects/`)
- `effect_chips_bonus.gd` - Flat chip bonus
- `effect_mult_bonus.gd` - Flat mult bonus
- `effect_aoe_expand.gd` - Expands landing zone radius
- `effect_terrain_bonus.gd` - Conditional bonuses based on landing terrain
- `effect_distance_bonus.gd` - Bonuses based on shot distance (per-cell, long, short)
- `effect_bounce_bonus.gd` - Bonuses for bounce/trick shots
- `effect_roll_modifier.gd` - Modifies roll distance and friction
- `effect_curve_shot.gd` - Adds curve/spin to trajectory

**Card Types Defined:**
- **Club** - Determines which club is used for the shot
- **Shot** - Played to modify current shot
- **Passive** - Always provides effect while in hand
- **Consumable** - Single-use powerful effects
- **Joker** - Always active, persist between shots

**Rarities:** Common (60%), Uncommon (25%), Rare (12%), Legendary (3%)

**Starter Deck Cards:**
- Power Drive (Common Shot) - +10 chips
- Steady Putter (Common Shot) - Bonus for short shots
- Fairway Finder (Common Passive) - Bonus on fairway landing

**Club Deck** - Full set of golf clubs as selectable cards:
- Driver, 3 Wood, 5 Wood
- 3 Iron through 9 Iron
- Pitching Wedge, Sand Wedge
- Putter

**UI Components** (in `scenes/ui/`)
- `card_ui.tscn` / `card_ui.gd` - Individual card visual with hover/select states
- `hand_ui.tscn` / `hand_ui.gd` - Hand display with fan layout
- `card_selection_ui.tscn` - Grid-based card selection overlay
- `deck_widget.tscn` - 3D deck container for HUD (standalone SubViewportContainer)
- `deck_view_3d.tscn` - Interactive 3D deck with draw animation
- `combined_deck_view.tscn` - Parent Node3D managing both SwingDeck and ModifierDeck
- `SwingMeter.tscn` - 3-click timing mechanic for power/accuracy/curve
- `shot_ui.tscn` - Main shot interface (hole info, club info, terrain, shot counter)
- `target_marker.tscn` - Visual indicator for aim target
- `hole_viewer.tscn` - Camera controller for viewing the hole
- `WindWidget.tscn` - Wind direction/speed display with title and dynamic text
- `LieView.tscn` - Current lie terrain display with title and dynamic text

**Gameplay Loop (Current State):**
1. ✅ Ball placed on tee at hole start
2. ✅ Player clicks Club Deck to select club
3. ✅ Player clicks Modifier Deck to draw modifier cards (3 choices)
4. ✅ Player hovers/clicks to aim at target tile
5. ✅ Visual trajectory and AOE landing zone shown
6. ✅ Player clicks to lock target, SwingMeter appears
7. ✅ 3-click timing: Power → Accuracy → Curve
8. ✅ Ball animates along curved flight path
9. ✅ Ball rolls based on spin, terrain, elevation
10. ✅ Scoring calculated (chips × mult)
11. ✅ If on green, putting mode activates
12. ✅ Hole complete when ball reaches flag

### 🔄 Partially Implemented

1. **Wind System** - WindSystem exists and generates wind per hole:
   - `effect_wind.gd` WindModifier created but not auto-added to ModifierManager
   - Wind effects on trajectory not fully applied during shot execution
   - ✅ UI widget displays dynamically with format "W 26km/h" (direction + speed)
   - ✅ Widget has title label at top, dynamic text at bottom

2. **Scoring Display** - Chips/mult calculated but:
   - No running total display
   - No end-of-hole score popup
   - No cumulative run score

3. **Card Hand System** - HandUI exists but:
   - Not connected to active gameplay
   - No "play from hand" mechanic implemented

### 📋 Next Priority: Roguelike Run Structure

Per the design doc, the next major systems to implement:

**Run State Manager** - Tracks:
- Current hole number (1-18 or endless)
- Total strokes taken
- Score/money accumulated
- Deck composition between holes
- Unlocked cards/upgrades

**Shop System** - Between holes:
- Purchase new cards to add to deck
- Upgrade existing cards
- Remove negative/weak cards
- Spend accumulated chips/score

**Progression System:**
- Par bonuses for under-par finishes
- Streak bonuses for consecutive good shots
- Risk/reward card trades (Gloomhaven style)

---

**Core concepts and responsibilities**

**Hole and tiles**

- Each hole is a scene with:
  - A Hole root node.
  - A collection of hex tile nodes (e.g. HexTile) arranged in a grid.
  - A Ball node.
  - UI nodes for hand, passives, and scoring.
- Tiles can be referenced:
  - By node name (e.g. "tile_2_9").
  - By indices in an array or map.
- Each HexTile should expose:
  - Read/write properties for:
    - terrain_type (e.g. fairway, rough, sand, water, green, hazard).
    - elevation.
    - tags (array or set of strings for special effects: "gold", "warp", "springboard", "cursed", etc.).
  - Helper methods:
    - add_tag(tag: String).
    - remove_tag(tag: String).
    - has_tag(tag: String) -> bool.

**Shot lifecycle and AOE**

Introduce a **Shot Lifecycle** that other systems can hook into:

Phases for a single shot:

- prepare_shot
  - Create a ShotContext data object with base stats from ball / hole state.
- apply_modifiers_before_aim
  - Passive/global modifiers can change the context here.
- player_aims
  - Player clicks a tile to define a center for AOE.
- compute_aoe
  - AOE system computes list of tile IDs/coords in range.
- apply_modifiers_on_aoe
  - Modifiers adjust AOE shape, radius, and tile weights.
- resolve_landing_tile
  - Choose landing tile from AOE (uniform or weighted).
- simulate_ball_path
  - Move ball; compute tile path, bounces, etc.
- compute_scoring
  - Compute Chips, Mult, final score for shot.
- apply_modifiers_on_scoring
  - Scoring modifiers tweak Chips/Mult based on context.
- cleanup_shot

- Update run state, deck, UI, etc.

Copilot should:

- Extract the existing "everything in one script" logic into:
  - ShotManager (or similar) that owns this lifecycle.
  - AOESystem helper to compute AOE tiles from a center tile.
- Use Godot **signals** where appropriate (e.g. shot_started, shot_resolved) to keep systems decoupled.​​

**Data objects**

**ShotContext**

Create a **ShotContext** GDScript class (could be a Resource or simple script):

- Purpose: carry all the state a shot needs so modifiers can read/write it.
- Fields (loose typing is fine):
  - hole: reference to current hole or hole controller.
  - ball: reference to ball node.
  - start_tile_id: ID/coords of the tile where the shot starts.
  - aim_tile_id: ID/coords chosen by the player.
  - aoe_tiles: array of tile IDs/coords.
  - aoe_radius: number (base AOE radius).
  - aoe_shape: enum/string ("circle", "cone", "strip", etc.).
  - aoe_weights: optional dictionary mapping tile IDs to weight values.
  - path_tiles: array of tile IDs/coords the ball actually travels through.
  - base_chips: number (from distance, elevation, path length, etc.).
  - chips: number (start from base_chips, modified by systems).
  - mult: number (starting multiplier, modified by systems).
  - final_score: number (chips × mult).
  - shot_index_in_hole: integer.
  - metadata: dictionary for misc tags (e.g. "hit_hazard": true).

Copilot should generate helper methods for ShotContext as needed, but **keep it simple and data‑oriented**.

**Modifier system: what can be modified**

Modifiers will operate on four main "channels":

- **AOEShape**
  - Can change:
    - aoe_radius.
    - aoe_shape.
    - aoe_tiles (add/remove tiles).
    - aoe_weights (bias landing distribution toward tiles with certain tags/terrain).
- **ShotPhysics**
  - Affect:
    - Number of allowed bounces.
    - Roll distance/friction behavior.
    - Elevation influence.
  - Concrete effect:
    - Change how ShotManager computes path_tiles from landing_tile.
- **Scoring**
  - Modify:
    - base_chips.
    - chips.
    - mult.
    - final_score.
  - Often conditional on:
    - Terrain types in path_tiles.
    - Number of bounces.
    - Presence of certain tags (e.g. "gold", "hazard_adjacent").
    - Distance to cup.
- **TileState**
  - Modify tiles directly:
    - Add/remove tags.
    - Change terrain_type or elevation.
  - Can be:
    - One‑shot (card modifies a tile immediately).
    - Per‑shot triggers (e.g. a passive that adds a tag after landing).

Modifiers do **not** need to know about UI or card definitions.  
Cards and passives will be higher‑level concepts that _use_ modifiers.

**Modifier interfaces**

Introduce a minimal **Modifier** interface as a GDScript pattern (not strict interface):

Each modifier script should have one or more of these methods; Copilot can stub and call them from the manager:

- func apply_before_aim(context: ShotContext) -> void:
- func apply_on_aoe(context: ShotContext) -> void:
- func apply_on_landing(context: ShotContext) -> void:
- func apply_on_scoring(context: ShotContext) -> void:
- func apply_after_shot(context: ShotContext) -> void:

Not every modifier must implement all methods.  
Modifiers can be:

- Nodes in the scene tree (e.g. children of RunState or ShotManager).
- Or data objects attached to a deck/hand system (later).

Copilot should:

- Create a ModifierManager or ModifierHandler node that:
  - Keeps a list/array of active modifier instances.
  - Calls the relevant methods at each shot phase.
- Make it easy to add/remove modifiers at runtime.

**Event model and signals**

Introduce a small event model using **signals**.  
Signals can be defined on ShotManager or an autoload EventBus:

Suggested signals:

- signal shot_started(context)
- signal aoe_computed(context)
- signal shot_landed(context)
- signal shot_scored(context)
- signal hole_completed(hole_result)
- signal tile_state_changed(tile_id, tile_ref)

Copilot should use signals to connect future systems (UI, VFX, SFX, deck UI) without hard‑coding dependencies.​

**Integration with existing hole generator**

Constraints for Copilot:

- The existing **hole generation** script stays as‑is in terms of core functionality:
  - It should remain responsible for:
    - Instantiating tiles.
    - Naming or indexing them (e.g. "tile_2_9").
    - Providing a way to look up tiles by ID/coords.
- New systems should:
  - **Read** tile data from the existing generator.
  - **Write** tile state by using new helper methods on HexTile (add/remove tags, etc.).
  - Use the existing AOE neighbor calculation as a starting point, but move that logic into an AOESystem or similar helper script.

Copilot should **not** break current hole generation, only refactor and add new classes around it.

**Coding style guidelines for Copilot**

- Use **GDScript** for all new scripts.
- Loose typing is fine; do not enforce strict types unless helpful.
- Prefer **small, single‑purpose scripts**:
  - shot_manager.gd
  - shot_context.gd
  - modifier_manager.gd
  - hex_tile.gd (if not already separated)
  - aoe_system.gd
- Use Godot 4.5 signal syntax and best practices.​
- Whenever adding new code, prefer:
  - Clear, descriptive names over clever ones.
  - Comments that explain which phase of the shot lifecycle the code is for.

**What to ask Copilot to do next**

Given this design, Copilot should be asked to:

- **Create ShotContext**
  - A simple GDScript class or script file with the fields described above.
- **Create ShotManager**
  - Own the shot lifecycle phases.
  - Use existing AOE logic (moved into a helper) to fill aoe_tiles and aoe_radius.
  - Emit the suggested signals at each phase.
- **Create ModifierManager**
  - Hold an array of modifier instances.
  - Provide methods like apply_before_aim(context) that loop through modifiers and call methods when they exist.
- **Refactor AOE logic**
  - Move the "AOE from tile ID/coords" calculation into aoe_system.gd.
  - Expose a function like:
    - func compute_aoe(center_id, radius, hole_ref) -> Array:.
- **Add basic HexTile helpers**
  - Ensure HexTile has terrain_type, elevation, tags, and helper methods for tag management.
# Card System Documentation

## Overview
The Card System in "That Golf Game" is a modular system designed to handle deck management, card effects, and UI interactions. It is split into three main deck types:
1.  **Swing Deck**: Contains shot modifiers (e.g., "Power Drive", "Precision Swing"). Drawn once per shot to affect the shot.
2.  **Modifier Deck**: Contains passive modifiers and bonuses. Drawn after selecting swing card + tile.
3.  **Club Deck**: Contains the player's clubs. Used to select the active club.

## Game Flow

The shot workflow follows a board-game style approach for precise planning:

1. **Select Target Tile** - Player chooses where they want to aim
2. **Select Swing Card** - Player plays a swing card (determines shot modifiers + AOE pattern)
3. **Draw Modifier Card** - Player must draw a modifier card (adds bonuses/penalties)
4. **Execute Shot** - Ball flies along the preview arc, landing within the AOE pattern

### AOE (Landing Zone) Patterns

AOE is now **card-driven only** - no automatic AOE based on club accuracy. Default is a single tile (perfect accuracy).

Cards can provide these AOE patterns:
- **Ring (+N)**: Filled circle of N rings around target (traditional accuracy spread)
- **Line Vertical (+N)**: N tiles short + center + N tiles long (distance variance)
- **Line Horizontal (+N)**: N tiles left + center + N tiles right (draw/fade variance)
- **Single**: Just the target tile (perfect accuracy, default)

AOE patterns from multiple cards can stack/combine.

## Core Architecture

### 1. Data Structures
*   **`CardData`** (`scripts/cards/card_data.gd`): The "blueprint" resource for a card. Defines stats, name, description, and effects.
*   **`CardInstance`** (`scripts/cards/card_instance.gd`): A runtime instance of a card. Tracks state like `upgrade_level`, `uses_remaining`, and `is_exhausted`.
*   **`DeckDefinition`** (`scripts/cards/deck_definition.gd`): A resource for defining deck contents.
*   **`CardLibrary`** (`scripts/cards/card_library.gd`): A static registry of all available cards in the game.

### 2. Managers
*   **`CardSystemManager`** (`scripts/cards/card_system_manager.gd`): The central hub. Connects the card system to the `ShotManager`, `ModifierManager`, and UI.
*   **`DeckManager`** (`scripts/cards/deck_manager.gd`): Manages the logic of a single deck (draw pile, discard pile, hand).

### 3. UI Components
*   **`CardUI`** (`scripts/cards/card_ui.gd`): The 2D visual representation of a card. Handles mouse interaction (hover, click).
*   **`CardSelectionUI`** (`scripts/ui/card_selection_ui.gd`): The grid-based menu for selecting a club.
*   **`DeckView3D`** (`scripts/cards/deck_view_3d.gd`): Handles the 3D visualization of a single deck (drawing animations, card inspection).
*   **`CombinedDeckView`** (`scripts/cards/combined_deck_view.gd`): Combines two DeckView3D instances (swing + modifier) in a single viewport.
*   **`DeckWidget`** (`scenes/ui/deck_widget.tscn`): The container for the 3D deck views, placed in the HUD.

### 4. Cursor System
*   **`CursorManager`** (`scripts/ui/cursor_manager.gd`): Autoload singleton managing custom cursors.
    - **DEFAULT**: Standard pointer cursor
    - **HAND_OPEN**: Hovering over deck (ready to draw)
    - **HAND_POINT**: Hovering over card in UI overlay
    - **ZOOM**: Hovering over drawn card (click to inspect)

## Card Effects

### AOE Effects (Card-Driven Landing Zones)
- `EffectAOERing`: Ring pattern (+N rings of possible landing)
- `EffectAOELineVertical`: Line along shot direction (short/long variance)
- `EffectAOELineHorizontal`: Line perpendicular to shot (draw/fade variance)
- `EffectAOEExpand`: Modify accuracy (adds/removes AOE rings)
- `EffectAOEPerfect`: Perfect accuracy (single tile landing)

### Shot Modifier Effects
- `EffectSimpleStat`: Modify distance_mod, accuracy_mod, roll_mod, curve_strength
- `EffectCurveShot`: Add curve to shot (draw/fade)
- `EffectDistanceBonus`: Bonus chips based on shot distance
- `EffectRollModifier`: Modify roll distance after landing
- `EffectBounceBonus`: Add extra bounces

### Scoring Effects
- `EffectChipsBonus`: Add flat chips
- `EffectMultBonus`: Multiply score
- `EffectTerrainBonus`: Bonus when landing on specific terrain

## How To...

### Add a New Card
1. Create a new `.tres` file in the appropriate folder:
   - `resources/cards/swing/` for swing cards
   - `resources/cards/modifiers/` for modifier cards
2. Set the resource type to `CardData`
3. Fill in card properties (id, name, description, rarity, etc.)
4. Add effect resources to the `effects` array

### Add AOE to a Swing Card
1. Open the card's `.tres` file
2. Add a new effect to the `effects` array
3. Choose the appropriate AOE effect type:
   - `EffectAOERing` for circle spread
   - `EffectAOELineVertical` for short/long variance
   - `EffectAOELineHorizontal` for draw/fade variance
4. Set the distance parameter (e.g., `ring_distance = 2` for +2 rings)

### Create a New Deck
1.  In the FileSystem, right-click and select **Create New -> Resource...**
2.  Search for **DeckDefinition**.
3.  Save the file (e.g., `res://resources/decks/my_new_deck.tres`).
4.  In the Inspector, add card IDs to the `Card Ids` array.
5.  Assign the deck to the appropriate property in `HexGrid`.

### Change Card Art
1.  Select the **DeckWidget** or **CombinedDeckView** in your scene.
2.  In the Inspector, assign textures to **Card Front Texture** and **Card Back Texture**.
3.  Textures are located in `textures/cards/`.

## File Structure
```
scripts/cards/           # Core logic and data classes
  card_data.gd           # Card blueprint resource
  card_instance.gd       # Runtime card state
  deck_manager.gd        # Deck logic
  deck_view_3d.gd        # 3D deck visualization
  combined_deck_view.gd  # Two-deck combined view
  effects/               # Card effect scripts
    effect_aoe_ring.gd
    effect_aoe_line_vertical.gd
    effect_aoe_line_horizontal.gd
    effect_simple_stat.gd
    effect_curve_shot.gd
    ...

scenes/ui/               # UI scenes
  deck_widget.tscn
  combined_deck_view.tscn
  card_selection_ui.tscn

resources/
  cards/
    swing/               # Swing card .tres files
    modifiers/           # Modifier card .tres files
    clubs/               # Club card .tres files
  decks/                 # Deck definition files

textures/cards/          # Card textures
  card-front.png
  card-back.png
  card-back-blue.png
  card-back-green.png
```

# Card System Documentation

## Overview
The Card System in "That Golf Game" is a modular system designed to handle deck management, card effects, and UI interactions. It is split into two main deck types:
1.  **Swing Deck**: Contains shot modifiers (e.g., "Power Drive", "Precision Swing"). Drawn during gameplay to affect the next shot.
2.  **Modifier Deck**: Contains passive modifiers and bonuses.
3.  **Club Deck**: Contains the player's clubs. Used to select the active club.

## Core Architecture

### 1. Data Structures
*   **`CardData`** (`scripts/cards/card_data.gd`): The "blueprint" resource for a card. Defines stats, name, description, and effects.
*   **`CardInstance`** (`scripts/cards/card_instance.gd`): A runtime instance of a card. Tracks state like `upgrade_level`, `uses_remaining`, and `is_exhausted`.
*   **`DeckDefinition`** (`scripts/cards/deck_definition.gd`): A resource for defining deck contents.
*   **`CardDatabase`** (`scripts/cards/card_database.gd`): JSON-based card loader. Reads from `resources/cards/cards.json`.

### 2. Managers
*   **`CardSystemManager`** (`scripts/cards/card_system_manager.gd`): The central hub. Connects the card system to the `ShotManager`, `ModifierManager`, and UI.
*   **`DeckManager`** (`scripts/cards/deck_manager.gd`): Manages the logic of a single deck (draw pile, discard pile, hand).
*   **`CardLibrary`** (`scripts/cards/card_library.gd`): A static registry of all available cards in the game.

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

## JSON Card Database

Cards can be defined in `resources/cards/cards.json` for easy editing:

```json
{
    "swing_cards": [
        {
            "card_id": "power_drive",
            "card_name": "Power Drive",
            "description": "+20 distance.",
            "rarity": "UNCOMMON",
            "card_type": "SHOT",
            "tags": ["power", "distance"],
            "effects": [
                {"type": "distance_mod", "value": 20}
            ]
        }
    ],
    "modifier_cards": [...],
    "club_cards": [...]
}
```

### Supported Effect Types
- `distance_mod`, `accuracy_mod`, `roll_mod`, `aoe_radius`, `curve_strength` → EffectSimpleStat
- `curve` / `curve_shot` → EffectCurveShot
- `distance_bonus` → EffectDistanceBonus
- `chips_bonus` → EffectChipsBonus
- `mult_bonus` → EffectMultBonus
- `roll_modifier` → EffectRollModifier
- `bounce_bonus` → EffectBounceBonus
- `terrain_bonus` → EffectTerrainBonus

## How To...

### Add a New Card (JSON Method)
1. Open `resources/cards/cards.json`
2. Add a new entry to the appropriate array (`swing_cards`, `modifier_cards`, or `club_cards`)
3. Call `CardDatabase.reload()` to hot-reload during development

### Add a New Card (Programmatic Method)
Add a new entry in `CardLibrary._register_golf_cards()`:
```gdscript
var new_card = CardData.create("my_card_id", "My Card Name", CardData.Rarity.COMMON)
new_card.description = "Does something cool."
_register(new_card)
```

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

### Adjust Animation Speed
*   **Draw Animation**: Controlled in `scripts/cards/deck_view_3d.gd`. Look for `animate_move_to`.
*   **Selection Animation**: Controlled in `scripts/ui/card_selection_ui.gd`. Adjust `animation_duration`.

## File Structure
```
scripts/cards/           # Core logic and data classes
  card_data.gd
  card_instance.gd
  card_database.gd       # JSON loader
  deck_manager.gd
  deck_view_3d.gd
  combined_deck_view.gd  # Two-deck combined view
  effects/               # Card effect scripts

scenes/ui/               # UI scenes
  deck_widget.tscn
  combined_deck_view.tscn
  card_selection_ui.tscn

resources/
  cards/
    cards.json           # Master card definitions
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

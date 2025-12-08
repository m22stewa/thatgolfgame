# Card System Documentation

## Overview
The Card System in "That Golf Game" is a modular system designed to handle deck management, card effects, and UI interactions. It is split into two main deck types:
1.  **Modifier Deck**: Contains shot modifiers (e.g., "Power Drive", "Wind Reader"). Drawn during gameplay to affect the next shot.
2.  **Club Deck**: Contains the player's clubs. Used to select the active club.

## Core Architecture

### 1. Data Structures
*   **`CardData`** (`scripts/cards/card_data.gd`): The "blueprint" resource for a card. Defines stats, name, description, and effects.
*   **`CardInstance`** (`scripts/cards/card_instance.gd`): A runtime instance of a card. Tracks state like `upgrade_level`, `uses_remaining`, and `is_exhausted`.
*   **`DeckDefinition`** (`scripts/cards/deck_definition.gd`): A resource used to define the contents of a deck (list of card IDs or resources).

### 2. Managers
*   **`CardSystemManager`** (`scripts/cards/card_system_manager.gd`): The central hub. Connects the card system to the `ShotManager`, `ModifierManager`, and UI.
*   **`DeckManager`** (`scripts/cards/deck_manager.gd`): Manages the logic of a single deck (draw pile, discard pile, hand).
*   **`CardLibrary`** (`scripts/cards/card_library.gd`): A static registry of all available cards in the game.

### 3. UI Components
*   **`CardUI`** (`scripts/cards/card_ui.gd`): The 2D visual representation of a card. Handles mouse interaction (hover, click).
*   **`CardSelectionUI`** (`scripts/ui/card_selection_ui.gd`): The grid-based menu for selecting a club.
*   **`DeckView3D`** (`scripts/cards/deck_view_3d.gd`): Handles the 3D visualization of the deck on the table (drawing animations).
*   **`DeckWidget`** (`scenes/ui/deck_widget.tscn`): The container for the 3D deck view, placed in the HUD.

## How To...

### Add a New Card
1.  **Programmatically**: Add a new entry in `CardLibrary._register_golf_cards()`.
    ```gdscript
    var new_card = CardData.create("my_card_id", "My Card Name", CardData.Rarity.COMMON)
    new_card.description = "Does something cool."
    _register(new_card)
    ```
2.  **Resource-based**: Create a new `CardData` resource in the editor and save it.

### Create a New Deck
1.  In the FileSystem, right-click and select **Create New -> Resource...**
2.  Search for **DeckDefinition**.
3.  Save the file (e.g., `res://resources/decks/my_new_deck.tres`).
4.  In the Inspector, add card IDs to the `Card Ids` array (e.g., "power_drive", "clean_strike").
5.  To use this deck, assign it to the `Starter Deck` or `Club Deck` property of the `HexGrid` node in `GOLF.tscn`.

### Change Card Art
1.  Select the **DeckWidget** in your scene (e.g., `DeckOverlay` or `ClubDeckOverlay`).
2.  In the Inspector, look for the **Deck Configuration** group.
3.  Assign a texture to **Card Front Texture**.
4.  This will apply to all cards in that deck (both 3D and 2D selection).

### Adjust Animation Speed
*   **Draw Animation**: Controlled in `scripts/cards/deck_view_3d.gd`. Look for `animate_move_to`.
*   **Selection Animation**: Controlled in `scripts/ui/card_selection_ui.gd`. Adjust `animation_duration`.

## File Structure
*   `scripts/cards/`: Core logic and data classes.
*   `scenes/ui/`: UI scenes (`CardUI`, `CardSelectionUI`).
*   `resources/decks/`: Deck definition files.

# Card3D Addon - Implementation Guide

## Overview
The Card3D addon provides a 3D card system for Godot 4.x with drag-and-drop functionality, multiple layout strategies, and collection management.

## Key Components

### 1. Card3D (Base Card Node)
- **Location**: `addons/card_3d/scenes/card_3d.tscn`
- **Script**: `addons/card_3d/scripts/card_3d.gd`
- **Features**:
  - Hover animations (scale and position changes)
  - Face up/down state
  - Collision detection via StaticBody3D
  - Signals: `card_3d_mouse_down`, `card_3d_mouse_up`, `card_3d_mouse_over`, `card_3d_mouse_exit`
  - Tween-based animations for smooth movement and rotation

### 2. CardCollection3D (Container for Cards)
- **Location**: `addons/card_3d/scenes/card_collection_3d.tscn`
- **Script**: `addons/card_3d/scripts/card_collection/card_collection_3d.gd`
- **Features**:
  - Manages multiple Card3D nodes
  - Automatic layout application
  - Drop zone collision shape
  - Signals: `card_selected`, `card_deselected`, `card_clicked`, `card_added`, `card_moved`
  - Methods: `append_card()`, `insert_card()`, `remove_card()`, `move_card()`

### 3. CardLayout Strategies
Base class: `CardLayout` (`addons/card_3d/scripts/card_layouts/card_layout.gd`)

#### Available Layouts:
- **FanCardLayout**: Arranges cards in an arc/fan pattern
  - Properties: `arc_angle_deg`, `arc_radius`, `direction` (NORMAL/REVERSE)
  
- **LineCardLayout**: Arranges cards in a horizontal line
  - Properties: `max_width`, `card_width`, `padding`
  
- **PileCardLayout**: Stacks cards on top of each other

### 4. DragController
- **Script**: `addons/card_3d/scripts/drag_controller.gd`
- **Features**:
  - Manages drag-and-drop between CardCollection3D instances
  - Handles rotation during drag based on mouse movement
  - Configurable drag thresholds and rotation limits
  - Signals: `drag_started`, `drag_stopped`, `card_moved`
  - Must be parent of CardCollection3D nodes

## Basic Implementation

### Scene Setup
```
Card3DDemo (Node3D)
├── Camera3D
├── DirectionalLight3D
└── DragController (Node3D)
    ├── PlayerHand (CardCollection3D)
    └── PlayArea (CardCollection3D)
```

### Script Example
See `scripts/card_3d_demo.gd` for a working example that demonstrates:
- Setting up card collections with different layouts
- Creating and adding cards
- Handling drag-and-drop events
- Responding to card interactions

## Usage Pattern

1. **Create a DragController** node in your scene
2. **Add CardCollection3D** nodes as children of the DragController
3. **Set layout strategies** on each collection:
   ```gdscript
   var fan_layout = FanCardLayout.new()
   fan_layout.arc_angle_deg = 60.0
   player_hand.card_layout_strategy = fan_layout
   ```
4. **Instantiate Card3D** nodes and add them:
   ```gdscript
   var card = Card3DScene.instantiate()
   player_hand.append_card(card)
   ```
5. **Connect signals** to handle game logic:
   ```gdscript
   drag_controller.card_moved.connect(_on_card_moved)
   ```

## Demo Scene
- **File**: `scenes/card_3d_demo.tscn`
- **Description**: Basic demonstration with a fan-layout hand and line-layout play area
- **Features**: 5 test cards that can be dragged between collections

## Next Steps for Integration
1. Extend Card3D to create custom card types with your game's card data
2. Override drag behavior methods in CardCollection3D for game-specific rules
3. Add card visuals (textures, materials) to CardFrontMesh and CardBackMesh
4. Integrate with your existing card data system (CardInstance, DeckManager)

## Old UI System (Removed)
The following files were part of the previous 2D UI system and have been deleted:
- ~~`scenes/ui/swing_card_slot.tscn`~~ - DELETED
- ~~`scenes/ui/swing_card_ui.tscn`~~ - DELETED
- ~~`scripts/ui/swing_card_slot.gd`~~ - DELETED
- ~~`scripts/ui/swing_card_ui.gd`~~ - DELETED

**Kept and Updated:**
- `scenes/ui/swing_hand.tscn` - Now wraps the 3D hand in a SubViewport
- `scripts/ui/swing_hand.gd` - Simplified to be a wrapper for SwingHand3D

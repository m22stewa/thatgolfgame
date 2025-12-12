# That Golf Game

A **Balatro-style roguelike golf game** built with Godot 4, featuring procedural hex-based courses, deck-building mechanics, and arcade-style scoring.

## Overview

This project combines procedurally generated 3D golf holes with card-based modifiers inspired by Gloomhaven and Balatro. Each shot can be enhanced by cards that modify distance, accuracy, scoring multipliers, and more. The goal is to complete holes while building up chips and multipliers for high scores.

## Features

### Course Generation
- **Procedural Hole Generation**: Randomly generates complete golf holes with tee boxes, fairways, greens, and hazards
- **Hex Grid System**: Course layout built on a hexagonal tile grid for natural terrain flow
- **Multiple Surface Types**: Fairway, rough, deep rough, sand bunkers, water hazards, and greens
- **Organic Edge Trimming**: Noise-based boundary variation creates natural-looking hole shapes
- **Elevation System**: Dynamic terrain with hills, valleys, and slopes affecting gameplay
- **Foliage System**: Automatically places grass patches, bushes, rocks, and flowers based on terrain type
- **Tree Placement**: Random tree spawning with multiple tree models and color variations
- **Par System**: Holes generated as Par 3, 4, or 5 with appropriate yardage

### Card System (Roguelike Core)
- **Two-Deck System**:
  - **Club Deck**: Select your club for each shot (Driver through Putter)
  - **Modifier Deck**: Draw cards that add bonuses to your shot
- **Combined Deck View**: Both decks managed in a single 3D SubViewport
- **JSON Card Database**: Master card list in `resources/cards/cards.json` with automatic effect parsing
- **Card Types**: Shot modifiers, Passives, Consumables, and Jokers
- **Rarities**: Common (60%), Uncommon (25%), Rare (12%), Legendary (3%)
- **Card Effects**: Chip bonuses, multiplier bonuses, AOE expansion, terrain bonuses, curve shots, roll modifiers
- **3D Deck Visualization**: Interactive deck with draw animations and card zoom inspection

### Shot System
- **Full Club Selection**: Driver through Sand Wedge with realistic distances (90-220 yards)
- **Swing Meter**: Traditional 3-click golf game mechanic (Power → Accuracy → Curve)
- **Lie System**: Terrain affects shot stats (rough reduces distance, sand loses accuracy, etc.)
- **Club Stats**: Distance, accuracy, roll, loft, and arc height per club

### Shot Shapes
- **Hook/Draw**: Curves left for right-handed golfers
- **Fade/Slice**: Curves right for right-handed golfers
- **Visual Trajectory**: White arc shows aim, cyan arc shows curved flight path
- **Swing Meter Curve**: Third click timing determines shot curve

### Ball Physics
- **Natural Rollout**: Ball rolls after landing based on club type
- **Elevation Effects**: Downhill adds roll, uphill reduces roll
- **Spin Effects**: Topspin adds forward roll, backspin pulls ball back
- **Hazard Stops**: Ball stops at water, sand, or trees
- **Curved Flight**: Ball follows realistic curved trajectory when hook/slice applied

### Putting System
- **Dedicated Putting Mode**: Activates when ball lands on green
- **Aim Circle**: Visual indicator around ball showing direction
- **Power Charging**: Click and hold to charge putt power
- **Slope Physics**: Green contours affect putt direction and speed

### Scoring System (Balatro-Style)
- **Chips**: Base points earned from shot distance and terrain
- **Multiplier**: Bonus multiplier from cards and achievements
- **Final Score**: Chips × Mult for each shot
- **Terrain Bonuses**: Fairway landing, green landing, hole-in-one multipliers

### UI/UX Features
- **Custom Cursors**: Context-sensitive cursor changes (pointer, hand open, hand point, zoom)
- **Wind Widget**: Shows wind direction and speed ("W 26km/h" format) with title label
- **Lie Widget**: Shows current terrain type with title and dynamic text
- **Card Zoom**: Click cards to enlarge and center for inspection

## Project Structure

```
├── scenes/           # Godot scenes (.tscn files)
│   ├── GOLF.tscn             # Main game scene
│   ├── golf_ball.tscn        # Golf ball with shader support
│   ├── tiles/                # Tile models (teebox, etc.)
│   └── ui/                   # UI scenes
│       ├── SwingMeter.tscn       # Power/accuracy/curve timing
│       ├── deck_widget.tscn      # 3D deck SubViewportContainer
│       ├── combined_deck_view.tscn  # Parent for both decks
│       ├── WindWidget.tscn       # Wind display
│       └── LieView.tscn          # Terrain lie display
├── scripts/          # GDScript files
│   ├── hex_grid.gd           # Main game logic and course generation
│   ├── shot_manager.gd       # Shot lifecycle management
│   ├── modifier_manager.gd   # Shot modifier system
│   ├── lie_system.gd         # Terrain-based modifiers
│   ├── putting_system.gd     # Putting mechanics
│   ├── wind_system.gd        # Wind generation and effects
│   ├── ui/
│   │   └── cursor_manager.gd     # Custom cursor system (autoload)
│   └── cards/                # Card system scripts
│       ├── card_system_manager.gd  # Central card controller
│       ├── deck_manager.gd         # Deck pile management
│       ├── card_library.gd         # All card definitions
│       ├── card_database.gd        # JSON card loader (autoload)
│       ├── combined_deck_view.gd   # Dual-deck management
│       └── effects/                # Individual card effect scripts
├── models/           # 3D models
│   ├── features/     # Foliage models (bushes, grass, rocks, flowers)
│   └── ...           # Trees, golf ball, terrain meshes
├── resources/        # Resource files
│   ├── decks/        # Deck definitions (starter_deck.tres, club_deck.tres)
│   └── cards/
│       ├── cards.json        # Master card definitions
│       └── *.tres            # Card resources
├── assets/           # Third-party assets and addons
│   ├── fly_camera_addon/     # Free 3D camera navigation
│   └── kenney-platforms/     # Platform assets
└── textures/         # Texture files
    ├── cards/        # Card face textures
    ├── cursors/      # Custom cursor images
    └── icons/        # UI icons
```

## Controls

### Camera
- **WASD**: Move camera
- **Shift/Ctrl**: Change speed
- **Right Mouse Button**: Toggle mouse look

### Gameplay
1. **Click Club Deck**: Select club for this shot
2. **Click Modifier Deck**: Draw and select modifier cards
3. **Hover/Click Tile**: Aim at target tile
4. **Left Click (on valid tile)**: Lock target, start swing meter
5. **Swing Meter** (3 clicks):
   - First click: Set power (0-100%)
   - Second click: Set accuracy (center = perfect)
   - Third click: Set curve (left/right = hook/slice)
6. **Ball Flies**: Watch the shot play out
7. **Repeat**: Until ball is in the hole

### Other Controls
- **Regenerate Button**: Generate a new random hole
- **Space** (during animation): Fast-forward ball flight

## Requirements

- Godot 4.x

## Getting Started

1. Open the project in Godot 4
2. Run the main scene (`scenes/GOLF.tscn`)
3. Click the Club Deck to select a club
4. Click the Modifier Deck to draw cards
5. Click a tile to aim and take your shot
6. Complete the hole, then regenerate for a new one

## Documentation

- `design.md` - Architecture and implementation status
- `GAME_SYSTEMS.md` - Detailed reference for all game systems
- `CARD_SYSTEM.md` - Card system documentation
- `WIND_SYSTEM.md` - Wind system design document

## License

This project is for personal/educational use.

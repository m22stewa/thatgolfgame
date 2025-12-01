# That Golf Game

A procedural golf game built with Godot 4 featuring realistic shot mechanics and hex-based course generation.

## Overview

This project is a golf game prototype with procedurally generated 3D golf holes, realistic terrain, hazards, and a full shot system with club selection, shot shapes, spin effects, and ball physics.

## Features

### Course Generation
- **Procedural Hole Generation**: Randomly generates complete golf holes with tee boxes, fairways, greens, and hazards
- **Hex Grid System**: Course layout built on a hexagonal tile grid for natural terrain flow
- **Multiple Surface Types**: Fairway, rough, deep rough, sand bunkers, water hazards, and greens
- **Organic Edge Trimming**: Noise-based boundary variation creates natural-looking hole shapes
- **Elevation System**: Dynamic terrain with hills, valleys, and slopes affecting gameplay
- **Foliage System**: Automatically places grass patches, bushes, rocks, and flowers based on terrain type
- **Tree Placement**: Random tree spawning with multiple tree models and color variations

### Shot System
- **Full Club Selection**: Driver through Sand Wedge with realistic distances (90-220 yards)
- **Club Arc Heights**: Each club has appropriate trajectory height
- **Distance Validation**: Tiles outside club range are dimmed and unavailable

### Shot Shapes
- **Hook/Draw**: Curves left for right-handed golfers (loses 1-2 tiles distance)
- **Fade/Slice**: Curves right for right-handed golfers (loses 1-2 tiles distance)
- **Handedness Toggle**: Switch between right-handed and left-handed (reverses curve directions)
- **Visual Trajectory**: White arc shows aim direction, cyan arc shows actual curved path

### Ball Physics
- **Natural Rollout**: Ball rolls after landing based on club type (Driver rolls 3 tiles, wedges land soft)
- **Elevation Effects**: Downhill adds roll (+1 tile), uphill reduces roll (-1 tile)
- **Spin Effects**: Topspin adds forward roll, backspin pulls ball back (applied after natural roll)
- **Hazard Stops**: Ball stops at water, sand, or trees
- **Hole Detection**: Ball reaching the flag during flight, roll, or spin completes the hole

### AOE Landing Zone
- **Shape-Adjusted AOE**: Landing zone shifts based on shot shape selection
- **Visual Feedback**: Shows potential landing tiles with probability rings

## Project Structure

```
├── scenes/           # Godot scenes (.tscn files)
│   ├── hole-generator.tscn   # Main scene for hole generation
│   ├── golf_ball.tscn        # Golf ball with shader support
│   └── tiles/                # Tile models (teebox, etc.)
├── scripts/          # GDScript files
│   ├── hex_grid.gd           # Main game logic and shot system
│   ├── golf_ball.gd          # Ball visuals and effects
│   ├── shot_manager.gd       # Shot state management
│   ├── modifier_manager.gd   # Shot modifiers
│   └── *.gdshader            # Custom shaders (grass, water, sky, etc.)
├── models/           # 3D models
│   ├── features/     # Foliage models (bushes, grass, rocks, flowers)
│   └── ...           # Trees, golf ball, terrain meshes
├── assets/           # Third-party assets and addons
│   ├── fly_camera_addon/     # Free 3D camera navigation
│   └── kenney-platforms/     # Platform assets
└── textures/         # Texture files
```

## Controls

### Camera
- **WASD**: Move camera
- **Shift/Ctrl**: Change speed
- **Right Mouse Button**: Toggle mouse look

### Gameplay
- **Club Buttons**: Select club (Driver, 3W, 5W, 3i-9i, PW, SW)
- **Shape Buttons**: Toggle Hook, Draw, Fade, or Slice
- **Spin Buttons**: Toggle Topspin or Backspin
- **Handedness Buttons**: Switch between Right-handed and Left-handed
- **Left Click**: Lock target tile
- **Regenerate Button**: Generate a new random hole

## Requirements

- Godot 4.x

## Getting Started

1. Open the project in Godot 4
2. Run the main scene (`scenes/hole-generator.tscn`)
3. Select a club and click on a tile to aim
4. Use shape/spin modifiers for advanced shots
5. Click the regenerate button to create new random holes

## License

This project is for personal/educational use.

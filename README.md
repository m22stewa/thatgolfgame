# That Golf Game

A procedural golf course generator built with Godot 4.

## Overview

This project is a prototype for procedurally generating 3D golf holes with realistic terrain, hazards, and landscaping. Each hole is generated on a hex-based grid system with natural-looking organic edges.

## Features

- **Procedural Hole Generation**: Randomly generates complete golf holes with tee boxes, fairways, greens, and hazards
- **Hex Grid System**: Course layout built on a hexagonal tile grid for natural terrain flow
- **Multiple Surface Types**: Fairway, rough, deep rough, sand bunkers, water hazards, and greens
- **Organic Edge Trimming**: Noise-based boundary variation creates natural-looking hole shapes
- **Foliage System**: Automatically places grass patches, bushes, rocks, and flowers based on terrain type
- **Tree Placement**: Random tree spawning with multiple tree models and color variations
- **Water Cleanup**: Smart system removes floating/disconnected water features
- **Course Features**: Includes flag placement on greens and tee box models

## Project Structure

```
├── scenes/           # Godot scenes (.tscn files)
│   ├── hole-generator.tscn   # Main scene for hole generation
│   └── tiles/        # Tile models (teebox, etc.)
├── scripts/          # GDScript files
│   ├── hex_grid.gd   # Main procedural generation logic
│   └── *.gdshader    # Custom shaders (grass, water, sky, etc.)
├── models/           # 3D models
│   ├── features/     # Foliage models (bushes, grass, rocks, flowers)
│   └── ...           # Trees, golf ball, terrain meshes
├── assets/           # Third-party assets and addons
│   ├── fly_camera_addon/     # Free 3D camera navigation
│   └── kenney-platforms/     # Platform assets
└── textures/         # Texture files
```

## Controls

- **WASD**: Move camera
- **Shift/Ctrl**: Change speed
- **Right Mouse Button**: Toggle mouse look
- **Regenerate Button**: Generate a new random hole

## Requirements

- Godot 4.x

## Getting Started

1. Open the project in Godot 4
2. Run the main scene (`scenes/hole-generator.tscn`)
3. Click the regenerate button to create new random holes

## License

This project is for personal/educational use.

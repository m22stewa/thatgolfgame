# Design files

Everything about the game's design that isn't code. The `.gdignore` here keeps Godot from importing any of it.

## docs/

Hand-written design docs that used to sit in the project root.

- `design.md` - Architecture and implementation status
- `GAME_SYSTEMS.md` - Detailed reference for all game systems
- `CARD_SYSTEM.md` - Card system documentation
- `CARD3D_IMPLEMENTATION.md` - 3D card implementation notes
- `WIND_SYSTEM.md` - Wind system design document
- `AI DESIGN.docx`, `prompt for scoring and cards.docx` - Early design prompts

## claude/

Snapshots of design work made with Claude on claude.ai, taken Oct 25, 2026. The live versions may have moved on since.

- `hex-golf-roguelike-design.html` - Hex golf roguelike design page. Open it in a browser. Live: https://claude.ai/artifact/S2sEqvLvaRcCZDPT35KNbj
- `hex-movement-systems-research.md` - "Hex Movement Systems: Research for a Card-Built Golf Shot", Oct 21. Live: https://claude.ai/artifact/LXmm9bCtJfTh4tLabpDRV5
- `putting-puzzles.md` - "Putting puzzles", the second tab of the same doc, Oct 23

- `design_handoff_putting/` - Final putting design handoff: rules spec (`README.md`) and a playable prototype (`Putting - Final Design.dc.html`, needs `support.js` beside it). Unzipped from `Hex golf roguelike design.zip`.

The two Markdown exports drop the embedded diagrams (marked `[embedded content: ...]`); see the live doc for those.

## figma/

- `golfgame.fig` - Figma file, copied from Downloads. Open it with Figma (File > Import).

## agent-tasks/

A copy of `.agents/tasks/`: plans, design reviews and verdicts from agent runs. The originals stay in `.agents/tasks/` because the agent tooling reads and writes there.

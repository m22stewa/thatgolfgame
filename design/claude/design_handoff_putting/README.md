# Handoff: Putting phase (Godot)

## Overview
Replaces the current putt resolution in `scripts/green_board.gd` (pick a target hex, then an auto-resolving chain of up to 60 arrow pushes) with a planned putting puzzle:
- **Line** is chosen by reading the slopes (P3 "Break").
- **Pace** comes from a Gloomhaven-style putting deck: each putt rolls `2 + flipped modifier`.
- The ball must reach the hole in **4 putts or fewer**. One-putts and two-putts are possible but need planning.

## About the design files
`Putting - Final Design.dc.html` is an **HTML design reference/prototype**, not code to port line by line. Recreate the rules and UI in the existing Godot project (GDScript, `GreenBoard`, the card resources and the run state). The prototype's JS `sim()` is the reference implementation of the rules below. Open the file in a browser to play it.

## Fidelity
- **Rules**: final, ready to implement as specified.
- **UI**: mid-fidelity. Use the in-game scorecard style (paper `#f6f1e3`, ink `#1f3a2c`, pencil `#4a4a48`, red `#b8432f`, Barlow Condensed + a pencil hand font).

## Turn structure
1. **Read**: the player picks 1 of 6 hex directions from the ball. The preview runs `simulate_putt` for totals 0–6 and labels where each total stops, so the read is never hidden.
2. **Prepare (optional)**: *Caddie Peek* costs 1 chip and reveals the top card of the putting deck.
3. **Strike**: *Flip & Putt* rolls 2 + the flipped card. Rolling cards flip again, and their values sum. Alternatively, *Lag Putt* costs 1 chip and rolls exactly 2 with no flip.
4. **Roll**: the ball moves hex by hex, and each hex it enters applies its rules (below).
5. **Resolve**: the ball drops or stops. Flipped cards go to the discard pile. ✕ or ★ shuffles the discard back into the draw pile after the putt.
6. **Limit**: after 4 putts with no drop, the player picks up and scores 5.

## Movement rules (`simulate_putt(start, dir, total, special) -> {path, holed, reason}`)
- `pace = total`. If `total <= 0`, the ball doesn't move.
- Loop while `pace > 0`:
  - Step to the neighbour in the current heading.
  - If the next hex is off the green, stop at the last green hex (fringe).
  - Otherwise move the ball and subtract 1 pace.
  - **Cup hex**:
    - With special ✕ (lip out), the ball stops on the previous hex and doesn't drop.
    - With special ★, or if 0 or 1 pace remains, the ball drops.
    - Otherwise it's too firm: it lips out and keeps rolling on its heading.
  - **Spike marks**: the ball stops dead.
  - **Slope arrow** `(arrow_dir, strength 1–3)`, compared with the current heading:
    - **Same direction (downhill)**: `pace += strength - 1`.
    - **Opposite direction (uphill)**: `pace -= strength - 1`.
    - **Side (60° or 120° off the line)**: turn the heading 60° toward the arrow. A strength-1 slope only bends the ball if `pace <= 2` (the "slow-ball break" toggle). At most one bend per hex.
  - **Slick**: `pace += 1`, which stacks with downhill.
- ★ also drops the ball if it finishes next to the cup.
- The cup hex never has a slope.

## Green authoring (important change)
- **Keep arrows sparse**: 4–10 per green, as hand-placed slope zones. Do not put an arrow on every hex.
- **No full-length lips or ledges.** A tier is a band of uphill arrows, with a gentler ramp (strength 1) somewhere so there's a planned route.
- Green radius is 4 (61 hexes), drawn at half the scale of fairway hexes.
- **Par**: 2 when the hex distance from ball to cup is 4 or less, otherwise 3.
- **Generator check**: from the starting ball position, run every direction against the starter deck and reseed if the best one-putt chance is under 15% or over 70%.

The three reference greens in the prototype (`DEFS`) are authored data you can copy:
- **Double break**: 7 slopes.
- **Crowned**: a ring of 6 slopes around a slick centre.
- **Two-tier**: a ramp band plus a funnel slope.

## Putting deck (persists across the run)
Starter deck of 20 cards:

| Card | Count |
|---|---|
| +0 | 6 |
| +1 | 4 |
| −1 | 4 |
| +2 | 1 |
| −2 | 1 |
| Rolling +1 (flip again) | 2 |
| ✕ Lip out (reshuffle) | 1 |
| ★ Sweet spot (reshuffle) | 1 |

- **Draw / discard**: when the draw pile runs out, shuffle the discard pile to refill it.
- **Earned during the run (spec only)**: +3, break cards ↻/↺ (bend 60° then flip again), Steady (ignore slope, flip again), and perks that remove −1s.
- **Curse**: a 3-putt adds a −3 "Yips" card.
- **Bless**: a one-use ★.
- Both curse and bless cards leave the deck once drawn.
- **Advantage / disadvantage (spec only)**: advantage flips two chains and the player picks one. Disadvantage (fringe or spike lie) flips two and applies the one that finishes further from the cup.

## Chips
- Lag Putt and Caddie Peek each cost 1 chip.
- Finishing a green gives +1 chip, plus 1 chip per stroke under par.
- Still open: are these the same chips as the swing chips, or a separate putting pool?

## UI (reference layout)
- **Left**: the green.
  - Shading: flat hexes are uniform, slope hexes slightly darker, slick hexes pale blue.
  - Arrows use chevrons for strength (›, ››, ›››) and spike marks are dots.
  - Cup and flag in red.
  - Six direction buttons ring the ball.
  - Preview: dashed pencil line for total 2, fainter line for total 6, and numbered labels at each stopping hex (labelled in red if that total drops).
- **Right**: a scorecard panel.
  - Green name and par; Putt x/4, chips, and draw/discard counts.
  - FLIP & PUTT as the primary red button; LAG PUTT and CADDIE PEEK as secondary buttons.
  - The cards flipped on the last putt, with the sum pencilled in (e.g. "2 + 1 = 3").
  - A result stamp (Birdie / Par / Bogey…) with "Next green".
- **Ball animation**: one hex per 170 ms along the path.

## State
```
green, ball_hex, heading (or null), strokes, picked_up, holed,
putt_deck.draw[], putt_deck.discard[], chips, peek_active, last_flips[]
```

## Mapping to existing code
- `scripts/green_board.gd`: keep tile generation, slick and spikes. Make arrows sparse and remove full-length lips. Replace `roll()` (the push chain) with `simulate_putt()`, and use the same function for the preview.
- New `PuttDeck` resource (`draw_chain()`, reshuffle flag), stored in the run state next to the swing deck.
- `scripts/cards/effects/effect_putt_card.gd`: rework the putt cards as putting-deck modifiers.

## Open decisions
1. **Preview depth**: numbered endpoints (current default), full drop-odds heatmap, or no preview?
2. **Slow-ball break**: keep it?
3. **Lag putt**: fixed at 2, or let the player choose 1–3?
4. **Chip pool**: shared with swing chips or separate?

## Files
- `Putting - Final Design.dc.html`: playable prototype and rules reference. Tweaks: preview mode, slowBreak, startChips. The rules engine is in the logic class (`sim`, `drawChain`, `DEFS`).
- `support.js`: needed to open the HTML locally.

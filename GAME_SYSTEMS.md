# Golf Game Systems Reference

## Table of Contents
1. [Club Base Stats](#1-club-base-stats)
2. [Lie Modifiers (Terrain Effects)](#2-lie-modifiers-terrain-effects)
3. [Scoring System](#3-scoring-system)
4. [Card System Modifiers](#4-card-system-modifiers)
5. [System Interactions](#5-system-interactions)
6. [Key Data Structures](#6-key-data-structures)
7. [Notes & TODO](#7-notes--todo)

---

## 1. Club Base Stats

### Club Statistics Table

| Club | Distance (tiles) | Distance (yards) | Accuracy (AOE rings) | Roll (tiles) | Loft (1-5) | Arc Height | Swing Difficulty |
|------|------------------|------------------|---------------------|--------------|------------|------------|------------------|
| **Driver** | 22 | 220 | 1 (hardest) | 3 | 1 (low) | 12.0 | 1.0 |
| **3 Wood** | 20 | 200 | 1 | 3 | 1 | 11.0 | 0.9 |
| **5 Wood** | 18 | 180 | 1 | 2 | 2 | 10.0 | 0.8 |
| **3 Iron** | 17 | 170 | 1 | 2 | 2 | 9.0 | 0.7 |
| **5 Iron** | 16 | 160 | 0 | 2 | 2 | 8.5 | 0.5 |
| **6 Iron** | 15 | 150 | 0 | 1 | 3 | 8.0 | 0.4 |
| **7 Iron** | 14 | 140 | 0 | 1 | 3 | 7.5 | 0.4 |
| **8 Iron** | 13 | 130 | 0 | 1 | 3 | 7.0 | 0.3 |
| **9 Iron** | 12 | 120 | 0 | 1 | 4 | 6.5 | 0.3 |
| **Pitching Wedge** | 11 | 110 | 0 | 0 | 4 | 6.0 | 0.2 |
| **Sand Wedge** | 9 | 90 | 0 | 0 | 5 (highest) | 5.0 | 0.15 |
| **Putter** | - | - | - | - | - | - | 0.0 (easiest) |

### Stat Definitions
- **Distance**: Maximum range the club can hit (1 tile = 10 yards via `YARDS_PER_CELL`)
- **Accuracy**: AOE ring penalty (higher = larger landing zone = less precise)
- **Roll**: How many tiles the ball rolls after landing
- **Loft**: Ball trajectory height (1=low/piercing, 5=high/soft landing). Intended to affect wind sensitivity.
- **Arc Height**: Visual height of ball flight arc
- **Swing Difficulty**: Affects swing meter timing difficulty (0.0=easy, 1.0=hard)

---

## 2. Lie Modifiers (Terrain Effects)

### Terrain Modifier Table

| Lie | Display Name | Power Mod | Accuracy Mod | Spin Mod | Curve Mod | Roll Mod | Chip Bonus | Mult Bonus | Allowed Clubs |
|-----|--------------|-----------|--------------|----------|-----------|----------|------------|------------|---------------|
| **TEE** | Tee Box | 0 | 0 | 0.0 | 0.0 | 0 | +5 | 0.0 | All except SW |
| **FAIRWAY** | Fairway | -1 | 0 | 0.0 | 0.0 | 0 | 0 | +0.1 | Woods, Irons, Wedges |
| **ROUGH** | Rough | -4 | +1 | -0.5 | -0.3 | -1 | -5 | 0.0 | 5I-9I, PW, SW |
| **DEEP_ROUGH** | Deep Rough | -8 | +2 | -0.8 | -0.7 | -2 | -15 | -0.2 | 7I-9I, PW, SW |
| **SAND** | Bunker | -6 | +1 | +0.5 | -0.6 | -2 | -20 | 0.0 | SW (preferred), PW, 9I |
| **GREEN** | Green | -15 | -1 | 0.0 | 0.0 | +2 | 0 | 0.0 | PUTTER only |
| **WATER** | Water | -100 | 0 | 0.0 | 0.0 | 0 | -50 | -0.5 | None (penalty) |
| **TREE** | Trees | -10 | +2 | -0.7 | -0.8 | -1 | -25 | -0.3 | 7I-9I, PW, SW |
| **FLAG** | Hole | 0 | 0 | 0.0 | 0.0 | 0 | +100 | +1.0 | None (holed!) |

### Modifier Definitions
- **Power Mod**: Tiles added/subtracted from club's max distance
- **Accuracy Mod**: AOE rings added (positive = less accurate, larger landing zone)
- **Spin Mod**: Affects ball spin behavior
- **Curve Mod**: Affects shot curve/hook/slice tendency
- **Roll Mod**: Tiles added/subtracted from roll distance
- **Chip Bonus**: Flat chips added to scoring
- **Mult Bonus**: Multiplier added to scoring

### Slope Modifiers
| Slope Type | Effect |
|------------|--------|
| **Uphill** | `power_mod -= slope_strength * 2` (lose distance) |
| **Downhill** | `power_mod += slope_strength` (gain distance) |
| **Sidehill (left/right)** | `accuracy_mod += 1` (lose accuracy) |

---

## 3. Scoring System

### Core Formula
```
final_score = chips × mult
```

### Base Chips Calculation
- **Distance-based**: `base_chips = shot_distance * 5` (5 chips per cell traveled)
- **Default base**: 10 chips

### Terrain Scoring Effects

| Terrain | Chips Effect | Mult Effect | Metadata Flag |
|---------|--------------|-------------|---------------|
| FAIRWAY | - | +0.1 | - |
| ROUGH | -2 | - | - |
| DEEP_ROUGH | -5 | - | - |
| GREEN | - | +0.5 | - |
| SAND | -10 | - | `hit_sand: true` |
| WATER | ×0.5 (halved) | - | `hit_water: true` |
| TREE | -8 | - | `hit_tree: true` |
| FLAG | - | ×2.0 | `reached_flag: true` |

### Par System Configuration

| Par | Min Yards | Max Yards | Min Width | Max Width |
|-----|-----------|-----------|-----------|-----------|
| 3 | 150 | 300 | 10 | 18 |
| 4 | 320 | 480 | 14 | 28 |
| 5 | 500 | 650 | 20 | 35 |

### Scoring Terminology

| Score vs Par | Name |
|--------------|------|
| -3 or better | Albatross (or "Incredible!") |
| -2 | Eagle |
| -1 | Birdie |
| E (even) | Par |
| +1 | Bogey |
| +2 | Double Bogey |
| +N | +N (generic) |

---

## 4. Card System Modifiers

### Card Effect Types

| Effect Class | Phase | Key Properties |
|--------------|-------|----------------|
| **EffectChipsBonus** | OnScoring | `bonus_chips: int` |
| **EffectMultBonus** | OnScoring | `bonus_mult: float` |
| **EffectDistanceBonus** | OnScoring | `distance_mode` (PerCell/LongShot/ShortShot), `threshold_distance`, `chips_per_unit`, `flat_bonus_chips`, `flat_bonus_mult` |
| **EffectTerrainBonus** | OnScoring | `target_terrain`, `terrain_is_start`, `bonus_chips`, `bonus_mult` |
| **EffectBounceBonus** | OnScoring | `chips_per_bounce`, `mult_per_bounce`, `max_bonus_bounces` |
| **EffectAOEExpand** | OnAOE | `radius_bonus` |
| **EffectCurveShot** | BeforeAim | `curve_direction` (Left/Right/Random), `curve_strength`, `curve_delay_cells`, `bonus_on_curve_land` |
| **EffectRollModifier** | OnLanding | `roll_distance_modifier`, `friction_modifier`, `bonus_chips_on_roll_stop` |

### Card Examples by Rarity

#### Starter Cards
| Card | Effect |
|------|--------|
| Power Drive | +10 chips |
| Steady Putter | +15 chips, +0.5 mult on short shots (≤3 cells) |
| Fairway Finder | +8 chips, +0.3 mult on fairway |

#### Common Cards (60% drop rate)
| Card | Effect |
|------|--------|
| Long Driver | +20 chips, +0.5 mult on shots ≥8 cells |
| Distance Tracker | +2 chips per cell traveled |
| Sand Wedge | +25 chips, +1.0 mult from bunker |
| Wide Angle | +1 AOE radius |

#### Uncommon Cards (25% drop rate)
| Card | Effect |
|------|--------|
| Trick Shot | +10 chips, +0.3 mult per bounce (max 5) |
| Hook/Slice Shot | 0.4 curve strength, +15 chips on curve land |
| Roll Master | 1.75× roll distance, 0.7× friction, +5 chips |
| Green Reader | +20 chips, +1.5 mult on green |
| Combo Builder | +5 chips, +0.2 mult |

#### Rare Cards (12% drop rate)
| Card | Effect |
|------|--------|
| Eagle Eye | +50 chips, +2.0 mult on shots ≤2 cells |
| Bank Shot Pro | +20 chips, +0.5 mult per bounce (max 8) |
| Pressure Player (Joker) | +3.0 mult always |
| Wide Berth | +2 AOE radius |

#### Legendary Cards (3% drop rate)
| Card | Effect |
|------|--------|
| Ace in the Hole | +100 chips, +5.0 mult on ≤1.5 cells, +50 chips/+2.0 mult on green |
| Chaos Driver | Random curve 0.6, +3 AOE radius, +30 chips |
| The Mulligan (Joker) | +50 chips, +2.0 mult always |

#### Consumables (One-time use)
| Card | Effect |
|------|--------|
| Lucky Ball | +3.0 mult |
| Chip Shot | +40 chips |

### Card Rarity Drop Rates
| Rarity | Drop Rate |
|--------|-----------|
| Common | 60% |
| Uncommon | 25% |
| Rare | 12% |
| Legendary | 3% |

---

## 5. System Interactions

### Shot Lifecycle Flow

```
┌────────────────────────────────────────────────────────────────────────┐
│                         SHOT LIFECYCLE                                  │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  1. SHOT START                                                         │
│     HexGrid ──start_shot()──► ShotManager ──► LieSystem                │
│                                    │              │                    │
│                                    ▼              ▼                    │
│                              ShotContext ◄─ apply_lie_to_shot()        │
│                                                                        │
│  2. BEFORE AIM                                                         │
│     ModifierManager ──apply_before_aim()──► CardModifier               │
│                                                  │                     │
│                                                  ▼                     │
│                          ShotContext.curve_strength, etc.              │
│                                                                        │
│  3-4. AIMING & AOE                                                     │
│     ShotUI ──set_aim_target()──► ShotManager                           │
│                                      │                                 │
│                                      ▼                                 │
│                                  AOESystem.compute_*_aoe()             │
│                                      │                                 │
│     ModifierManager ─apply_on_aoe()─►│ (EffectAOEExpand)               │
│                                                                        │
│  5. SWING METER (3-click system)                                       │
│     SwingMeter ──swing_completed(power, accuracy, curve)──► ShotContext│
│                                                                        │
│  6. LANDING RESOLUTION                                                 │
│     ShotManager._calculate_power_adjusted_target()                     │
│     ShotManager._calculate_accuracy_landing()                          │
│     ModifierManager ─apply_on_landing()─► EffectRollModifier           │
│                                                                        │
│  7-8. SCORING                                                          │
│     ShotManager._compute_scoring()                                     │
│       └─► base_chips = distance × 5 + terrain effects                  │
│                                                                        │
│     ModifierManager ─apply_on_scoring()─► All Card Effects             │
│       └─► ChipsBonus, MultBonus, TerrainBonus, DistanceBonus, etc.     │
│                                                                        │
│     final_score = chips × mult                                         │
│                                                                        │
│  9-10. COMPLETION                                                      │
│     ShotManager ──shot_completed.emit()──► ShotUI                      │
│     ModifierManager ─apply_after_shot()─► Card cleanup                 │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Putting System (Separate Flow)

```
┌────────────────────────────────────────────────────────────────────────┐
│                    PUTTING SYSTEM (Separate Flow)                       │
├────────────────────────────────────────────────────────────────────────┤
│  HexGrid (ball on green) ──enter_putting_mode()──► PuttingSystem       │
│                                                                        │
│  Click 1: Set aim_tile                                                 │
│  Click 2: Start charge                                                 │
│  Release: Execute putt with physics (slope + friction)                 │
│                                                                        │
│  Constants:                                                            │
│    - PUTT_SPEED: 4.0 (base speed multiplier)                           │
│    - FRICTION: 2.5                                                     │
│    - SLOPE_FORCE: 2.0                                                  │
│    - MIN_VELOCITY: 0.05 (stop threshold)                               │
└────────────────────────────────────────────────────────────────────────┘
```

### Signal Reference

#### ShotManager Signals
```gdscript
signal shot_started(context: ShotContext)
signal modifiers_applied_before_aim(context: ShotContext)
signal player_aiming(context: ShotContext)
signal aoe_computed(context: ShotContext)
signal modifiers_applied_on_aoe(context: ShotContext)
signal landing_resolved(context: ShotContext)
signal ball_path_simulated(context: ShotContext)
signal scoring_computed(context: ShotContext)
signal modifiers_applied_on_scoring(context: ShotContext)
signal shot_completed(context: ShotContext)
```

#### LieSystem Signals
```gdscript
signal lie_calculated(lie_info: Dictionary)
signal lie_modifiers_applied(context: ShotContext, lie_info: Dictionary)
```

#### PuttingSystem Signals
```gdscript
signal putting_mode_entered()
signal putting_mode_exited()
signal putt_started(target_tile: Vector2i, power: float)
signal putt_completed(final_tile: Vector2i)
```

#### SwingMeter Signals
```gdscript
signal swing_completed(power: float, accuracy: float, curve_mod: float)
signal swing_cancelled()
```

---

## 6. Key Data Structures

### ShotContext
The central data object that flows through all shot systems.

```gdscript
# Tile coordinates
var start_tile: Vector2i       # Where the shot started
var aim_tile: Vector2i         # Where player is aiming
var landing_tile: Vector2i     # Where ball actually lands

# Lie modifiers (additive)
var power_mod: float = 0.0     # Tiles added/subtracted from max distance
var accuracy_mod: float = 0.0  # AOE rings added (positive = less accurate)
var spin_mod: float = 0.0      # Spin modifier
var curve_mod: float = 0.0     # Curve/hook/slice modifier
var roll_mod: float = 0.0      # Roll distance modifier

# AOE data
var aoe_tiles: Array[Vector2i] # All tiles in landing zone
var aoe_radius: int = 1        # Current AOE radius
var aoe_shape: String = "circle"  # "circle", "cone", "strip", "ring"

# Swing meter results
var swing_power: float = 1.0   # 0.0-1.0 (from swing meter)
var swing_accuracy: float = 1.0 # 0.0-1.0 (1.0 = perfect)
var swing_curve: float = 0.0   # -1 to +1 (hook/slice)

# Scoring
var base_chips: int = 0        # Before modifiers
var chips: int = 0             # After modifiers
var mult: float = 1.0          # Multiplier
var final_score: int = 0       # chips × mult
```

### HexTile
Individual hex cell on the course.

```gdscript
@export var terrain_type: int = 1  # SurfaceType enum
@export var elevation: float = 0.0 # Height for slopes
@export var col: int = 0           # Grid column
@export var row: int = 0           # Grid row
var tags: Dictionary = {}          # Special effects ("gold", "warp", etc.)
```

---

## 7. Notes & TODO

### Ball Flight Curve System
The ball now flies in a natural curved path when hook/slice/draw/fade is applied:

**Curve Sources:**
- `swing_curve`: From swing meter (-1 to +1, set by timing)
- `curve_strength`: From card effects
- `curve_mod`: From lie/terrain effects

**Curve Calculation:**
- Curve is scaled by shot distance: `scaled_curve = curve_amount * distance * 0.15`
- Uses realistic golf physics: curve accelerates in second half of flight
- Formula: `curve_factor = pow(t, 1.3) * sin(t * PI * 0.9)` - slow start, rapid curve late
- Ball spin axis tilts based on curve for visual sidespin effect

**Curve Types:**
| Value | Shot Shape | Description |
|-------|------------|-------------|
| Negative | Draw/Hook | Ball curves left (for right-hander) |
| Positive | Fade/Slice | Ball curves right (for right-hander) |

### Wind System Status
The wind system infrastructure is implemented but not fully integrated:

**Implemented:**
- `wind_system.gd` - Wind generation with direction, speed, gustiness
- `effect_wind.gd` - WindModifier class with proper modifier interface
- Wind generated per hole based on difficulty
- 8 cardinal/ordinal directions (N, NE, E, SE, S, SW, W, NW)
- Speed categories: Calm (<5), Light (5-13), Moderate (13-26), Strong (26-41), Very Strong (41+) km/h
- Loft-based sensitivity (higher loft = more wind effect)

**Not Yet Connected:**
- WindModifier not auto-added to ModifierManager at shot start
- Wind effects calculated but not applied to ball trajectory
- Wind UI widget exists but not dynamically updating

**To Complete Wind Integration:**
1. Add WindModifier to ModifierManager when shot starts
2. Call `apply_on_shot()` during shot execution phase
3. Update wind widget on hole generation

### Current Development Focus

**Immediate Next Steps:**
1. **Run State Manager** - Track hole number, strokes, cumulative score
2. **End-of-Hole Flow** - Score display, continue to next hole
3. **Shop System** - Card purchasing between holes
4. **Hand of Cards** - Playable items/actions during shots

**Gameplay Loop Gaps:**
- No between-hole transition flow
- No score accumulation across holes
- No card shop/upgrade system
- No win/lose conditions
- No difficulty progression

### Potential Improvements
- [ ] Complete wind system integration
- [ ] Add elevation-based distance calculations beyond slope
- [ ] Consider club wear/fatigue system
- [ ] Add weather effects (rain = more roll reduction, etc.)
- [ ] Implement card upgrade system
- [ ] Add special tile effects (gold tiles, warp tiles, etc.)
- [ ] Multiplayer support (turn-based or real-time)

---

*Last updated: December 2024*
*Source files: `shot_manager.gd`, `lie_system.gd`, `modifier_manager.gd`, `aoe_system.gd`, `putting_system.gd`, `wind_system.gd`, `cards/`*

# Hex Movement Systems: Research for a Card-Built Golf Shot

Oct 21, 2026 · @Mark Stewart

Build each shot from a club budget plus at most three cards, price **shape** in power rather than distance, and let chance act only on the landing hex. That is the pattern shared by the hex and grid movement systems that work best, from Heat and BattleTech to Golf Peaks and Into the Breach.

- **Keep:** the prototype's power budget, Fwd/Bend cards, Loft and Stop, and wind on the final hex.
- **Change:** tapping a target gives a free default path; cards reshape it. Gentle curves are a 1-power Drift (sidestep); a 60° Bend costs 2 and reads as a dogleg.
- **Add:** overspend past the club's budget is allowed but adds a Strain card to your deck; any card can be played as Fwd ×1 so a hand is never dead.
- **Watch:** paths must render as ball flight, not a zig-zag walk, and hex distances need retuning (a 9-power Driver is about 90 yards at today's 10 yards per hex).

## The design target

The prototype turns a golf shot into a short path you build from cards, hex by hex, under a power budget set by the club. In the mock-up a stroke spends 7 of 9 power on Fwd ×3, Bend R, Fwd ×2 and Bend R, then wind pushes the final hex one step NE.

What the prototype is reaching for:

- **Planning over dexterity.** The shot is assembled before it is hit, like a board-game turn, not timed like a swing meter.
- **Club as budget.** The club sets how much movement you can buy; cards spend it.
- **Cards as verbs.** Move cards (Fwd, Bend) draw the path; Mod cards (Loft: skip a hazard, Stop: no roll) change how the path interacts with the board.
- **One honest variance step.** Wind acts on the final hex, so you can see it coming and plan against it.
- **Golf feel.** The path should still read as a drive, a draw, a layup or a chip, not a game piece walking around.

The research below asks one question of every system surveyed: what makes plotted movement on a grid feel like a decision, and what makes it feel like bookkeeping?

## Survey: six families of grid movement

Almost every grid movement system is one of six families, and the prototype already mixes two of them: programmed sequences (Fwd, Bend) and a movement-point budget (Power 7/9). Rules marked \* are from general knowledge of the game, not a page opened for this report.

| Game | Family | How movement works | What limits it | Lesson for the shot |
| --- | --- | --- | --- | --- |
| Robo Rally\* | Programmed sequence | Lock five cards (Move 1/2/3, Turn L/R, U-Turn, Back Up) into registers, then they resolve in order while conveyors and pushers act on you. | Hand size; damage locks registers; board elements you didn't plan for. | The joy and the pain of a pre-committed path. Board elements that move you are the drama. |
| [Golf Peaks](https://gamingtrend.com/reviews/a-puzzle-thats-par-for-the-course-golf-peaks-review/) | Programmed sequence | Each card is a fixed distance, ground or jump; you choose direction only. | Cards are single-use per hole. | Distance on the card, direction from the player keeps cards simple. |
| [Mage Knight](https://ultraboardgames.com/mage-knight/movement.php) | Movement points | Cards give Move points; you pay the cost of each hex you **enter** (e.g. forest 3). Any card [played sideways](https://rulespal.com/mage-knight/rulebook) is Move 1. | Terrain cost per hex; hand of cards. | Sideways play means no dead cards. Terrain priced per hex entered. |
| BattleTech\* | Movement points | Walk, run or jump modes; turning costs 1 MP per hexside; rough and woods cost extra. | MP per mode; running and jumping hurt accuracy. | Turning as a cost is exactly what Bend should be. Mode choice trades reach for precision. |
| Gloomhaven\* | Movement points | Move X per card; Jump ignores obstacles and hazards en route; difficult terrain costs 2. | Card economy; hazards hurt when entered. | Jump vs ground is a clean, readable verb pair. |
| X-Wing\* | Templates / dials | Pick a manoeuvre on a dial (straight, bank, turn, K-turn at a speed); red manoeuvres give stress, which blocks more red until cleared. | Ship's dial; stress. | Hard moves cost a lingering penalty rather than a bigger number. |
| [Sails of Glory](https://geekdad.com/2013/04/sails-of-glory/) | Templates / dials | Manoeuvre cards placed in front of the ship; which options you get depends on the wind angle to your heading. | Wind relative to heading. | Wind that changes which moves are available, not just where you end up. |
| [Heat: Pedal to the Metal](https://officialgamerules.org/game-rules/heat-pedal-to-the-metal-rules/) | Momentum / racing | Sum played speed cards to move; corners have speed limits; overspeed costs Heat equal to the difference; can't pay and you spin out. Boost: pay 1 Heat to flip a speed card. | Heat cards clog your hand; corners. | Overspending has a priced, visible cost instead of a hard cap. |
| [Rallyman GT](https://zatu.com/blogs/how-to-play/how-to-play-rallyman-gt) | Momentum / racing | Plan the racing line first, then roll gear dice one by one (safe) or all at once (flat-out, earns focus tokens). Too many hazard symbols and you spin out. | Gear can only shift one step; hazard symbols on dice. | Plan the line, then choose how much risk to take resolving it. |
| Flamme Rouge\* | Momentum / racing | Draw energy cards, play one per turn; finishing in front means drafting an exhaustion card into your deck. | Deck depletes; exhaustion clogs it. | Effort now pollutes your future hand, a natural deckbuilding cost. |
| [Hey, That's My Fish!](https://en.doc.boardgamearena.com/Gamehelpheythatsmyfish) | Line / slide | A penguin moves in a straight line over contiguous ice in any direction, never through other penguins. | Blockers and missing hexes. | Any-distance straight moves are fast and readable; blockers create the decisions. |
| [Hive](https://en.doc.boardgamearena.com/Gamehelphive) | Jump / hop | Grasshopper jumps a line of pieces to the first empty hex; Spider slides exactly 3 around the hive. | Each piece has one fixed pattern. | Jump-over-a-line is a perfect Loft verb. Exact-distance moves are puzzly. |
| [Hoplite](https://www.giantbomb.com/hoplite/3030-45184/) | Tactics on hex | Move one hex per turn, or spend energy on Leap (2 hexes) or Bash. | Energy pool. | A tiny verb set on hexes is enough for depth. |
| [Into the Breach](https://gamedeveloper.com/game-platforms/road-to-the-igf-subset-games-i-into-the-breach-i-) | Tactics with telegraphs | Enemy attacks are shown before you act; pushes redirect them. | Perfect information, no hit chance. | Designers chose telegraphs so “every death felt like your own fault.” Show the wind before the hit. |

## Golf games that already use grids, cards or dice

No golf game found does exactly what the prototype does: build a multi-step flight path from cards under a budget. The closest neighbours each solve one piece of it.

| Game | How a shot works | What to take | What to avoid |
| --- | --- | --- | --- |
| [Golf Peaks](https://gamingtrend.com/reviews/a-puzzle-thats-par-for-the-course-golf-peaks-review/) (video, 2018) | Each card is a fixed distance; you only pick the direction. Cards are ground rolls, jumps, or jump-then-roll. Each card is used once per hole. | Jump vs roll as the core card split. The order you spend cards is the puzzle. | Exact-landing rule: rolling past the cup by one tile feels like bookkeeping, not golf. |
| [18 Holes](https://www.meeplemountain.com/reviews/18-holes/) (board game) | Course built from hex tiles. Clubs are drafted; each club draws from one or two of five shot decks numbered 1 to 5. A shot card is a path shape: nearly every card in the 4 deck travels three hexes straight, then usually turns one hex. | Shot cards as drawn path shapes, gated by club. The closest precedent to the prototype. | Reviewer found setup (laying tiles) took about as long as playing. |
| [Golfie](https://fingerguns.net/reviews/2023/02/10/golfie-review-pc-spilling-the-tee/) (roguelike deckbuilder) | Physics minigolf; cards add power, lob (over obstacles) or curve before the putt. Every card adds heat; if the reactor maxes out it explodes and you lose 2 energy. | Heat as a cost on stacking cards, so combos have a ceiling. | Reviewer complaint: you can't remove cards from your deck, so builds can't be shaped. |
| [Cursed to Golf](https://en.wikipedia.org/wiki/Cursed_to_Golf) (roguelike) | Real-time 2D golf with 30+ Ace Cards: Mulligan, U-Turn (re-aim mid-air), Rocketball, Scattershot. Extra shots convert to shop cash. | One-shot rule-breaking cards and a Mulligan as items, not as the core verb. | Ace Cards sit on top of a dexterity swing; the cards are spice, not the plan. |

The gap the prototype fills: Golf Peaks proves card-ordered movement on a grid is fun, but its cards are rigid; Golfie proves stacking shot cards needs a cost ceiling. Neither lets you **draw the shape** of a shot.

## What is common

Every system pairs a **small set of movement verbs** with **one scarce budget** and **one source of board pressure**. The specifics vary; that skeleton does not.

- **Few verbs.** Step, turn, jump, slide. Robo Rally has about seven card types; Hoplite has move, leap and bash. Depth comes from order and context, not from verb count.
- **One budget per turn.** Move points (Mage Knight, BattleTech), a summed speed (Heat), energy (Hoplite), or simply cards in hand (Golf Peaks, Robo Rally).
- **Turning is priced.** BattleTech charges per hexside; X-Wing makes hard turns red; Heat prices corners by speed. Going straight is cheap everywhere.
- **Terrain prices entry, not exit.** Mage Knight charges the hex you enter; Gloomhaven makes Jump the way around hazards.
- **A risk dial on resolution.** Rallyman's safe vs flat-out, Heat's boost, X-Wing's red moves: you choose how much uncertainty to buy.
- **Lingering cost for greed.** Heat cards, stress, exhaustion cards: overreaching hurts later turns, not just this one.
- **Information before commitment.** Wind direction in Sails of Glory, telegraphs in Into the Breach, the racing line in Rallyman: the board's pressure is visible when you plan.

## What works

The systems people praise share one trait: the plan is cheap to read and expensive to perfect.

1. **Price the curve, not the distance.** Straight power is plentiful; shape costs extra. BattleTech's per-hexside turn cost and Heat's corner limits make the interesting move the expensive one. For golf: Fwd is cheap, Bend costs power, and a hard bend costs more.
2. **Overspend allowed, at a visible price.** Heat lets you exceed a corner's limit by paying Heat equal to the difference; only failing to pay spins you out. A hard cap (“Power 9, no more”) is less interesting than “go to 11 and draw a Shank card.”
3. **Make dead cards impossible.** Mage Knight's sideways rule turns any card into Move 1. A hand that can't make a legal shot is the most frustrating state a card game has.
4. **Two clean verb families.** Ground vs jump (Golf Peaks, Gloomhaven), step vs slide (Fish, Hive). Players learn them in one shot and keep finding new combinations.
5. **Plan then resolve, with one honest twist.** Rallyman plans the line, then rolls. Into the Breach shows the threat, then lets you act. The prototype's “wind pushes the final hex +1 NE” is this exactly: one visible step of board pressure after the plan.
6. **Board elements that move you.** Robo Rally's conveyors, Heat's slipstream, Hive's line-jumps. Slopes, cart paths and wind gusts are golf's natural version and turn the board into a puzzle piece rather than scenery.
7. **Greed leaves a mark.** Exhaustion cards (Flamme Rouge) and stress (X-Wing) mean the big shot now makes the next shot harder. In a deckbuilder this is free: add a card to the deck.

## Pain points and how games handle them

The biggest risk for a plotted shot is that it stops feeling like golf and starts feeling like walking a game piece around.

| Pain point | Where it shows up | How games mitigate it | For this game |
| --- | --- | --- | --- |
| Path reads as a zig-zag walk, not a ball flight | Robo Rally-style step lists | Templates (X-Wing) draw one smooth arc per choice | Bends should render as a curved flight, and a shot should be 2–4 cards, not 7 steps |
| A hex grid has only 6 straight headings, 60° apart, so a one-step turn is a dogleg | Any hex grid; your hole runs diagonally | Line/slide moves allow any of 6 axes only | Shape with Drift (one sidestep, heading unchanged) for gentle curves; keep a full 60° Bend as the expensive dogleg card |
| Exact landing feels fiddly | Golf Peaks rolls past the cup | Distance tolerance; holes that capture | Ball drops if it passes over the cup at roll speed 1–2 |
| Analysis paralysis from too many orderings | Robo Rally, programmed games | Fewer cards per plan; timers in some | Cap the shot at 3 cards plus the club; preview updates live |
| Dead hand: no legal plan | Any hand-based movement | Sideways play (Mage Knight) | Any card can be played as Fwd ×1 |
| One bad step wrecks the whole plan | Robo Rally pushes, Rallyman spins | Spin-outs cost position, not the game | Variance hits the final hex only (wind, roll), never mid-path |
| Preview lies | Physics card golf | Perfect-information previews (Into the Breach) | Show the exact path; show variance as a ring around the final hex with odds |
| Setup and bookkeeping drag | 18 Holes tile laying | Digital handles it | Keep all costs computed and shown on the card and the budget bar |

## Proposed model: Club, Line, Shape, Land

Keep the prototype's core (build the flight from cards under a club's power budget) and add four rules from the survey: price shape over distance, split air from ground, allow overspend at a cost, and apply variance only at the end.

&#91;embedded content: shot anatomy · 4 stages, 1 penalty branch\]

The player decides everything in Club, Line and Shape with full information; only the Land stage adds chance, and it is previewed with odds before the hit.

**1. Club sets the budget and the split.** Each club card gives **Power** (hexes of travel to spend) and a **Carry/Roll split**: the first hexes are in the air, the rest on the ground. Example starting values:

| Club | Power | Air hexes | Roll hexes | Notes |
| --- | --- | --- | --- | --- |
| Driver | 9 | 7 | 2 | Tee and fairway only |
| 5 Iron | 7 | 6 | 1 |  |
| 8 Iron | 5 | 5 | 0 |  |
| Wedge | 3 | 3 | 0 | Out of sand and rough without penalty |
| Putter | 3 | 0 | 3 | Green only; all ground |

**2. Line: the default flight is free.** Tapping a target (today's aiming) plots a straight path along the true line and fills it with plain Fwd steps. A player who plays no cards still hits a sensible shot. This keeps the fast, Snap-like pace.

**3. Shape: cards replace part of the plain path.** A shot takes at most 3 shape cards. Cards are priced so **shape costs power and distance is cheap**:

- Drift (one sidestep, heading unchanged) costs 1. This is the gentle draw or fade.
- Bend (turn 60°) costs 2. This is the dogleg cut.
- Loft and Low change whether hexes are air or ground. Air hexes ignore what they pass over; ground hexes pay terrain.

**4. Overspend is allowed.** Going past the club's power is legal. Each extra point adds a **Strain** card (a mishit) to your deck, as Heat and Flamme Rouge do. The over-swing is a real option with a visible, lasting price.

**5. Land: one honest variance step.** After the path, three things happen in order, and all of them show in the preview before you hit:

1. Wind pushes the landing hex, as in the prototype.
2. The landing ring: a shot at 70% of power or less lands exactly; at full power it can land on any of the 6 neighbouring hexes; overspent shots widen to a ring of 2. Odds are shown on each hex.
3. Roll walks the ground hexes; sand stops the ball, water drops it, slopes push it.

This maps onto what the game already has: the club bag, the weighted landing ring with its odds, wind, roll-out, and the trick-shot points. The new pieces are the path builder and pricing cards in power.

## Card ideas

Twenty-four starting cards, grouped by what they do to the path. Costs are in power; a cost of 0 means the card changes the rules instead of spending distance. Any card can also be played face-down as Fwd ×1.

| Group | Card | Cost | Effect on the path | Golf read | Inspired by |
| --- | --- | --- | --- | --- | --- |
| Move | Fwd ×2 / ×3 | 2 / 3 | Advance along the current heading | Stock distance | Robo Rally, Golf Peaks |
| Move | Lay Up | 0 | End the flight now; refund unspent power as +1 accuracy (smaller ring) | Club down, control up | X-Wing green moves |
| Move | Drive It | 0 | Next Fwd card counts double; landing ring +1 | Swing out of your shoes | Heat boost |
| Shape | Drift L / Drift R | 1 | One sidestep; heading unchanged | Gentle draw or fade | X-Wing bank |
| Shape | Bend L / Bend R | 2 | Turn heading 60° | Dogleg cut, hook or slice | BattleTech facing cost |
| Shape | S-Curve | 3 | Drift one way, then the other | Shaping around trees | X-Wing banks |
| Shape | Late Break | 1 | Apply your next shape card to the last 2 hexes only | Ball that turns at the end | Templates |
| Flight | Loft | 1 | Next 3 hexes are air; ignore hazards and trees beneath | Flop or high iron | Hive grasshopper, Gloomhaven Jump |
| Flight | Punch | 0 | All hexes ground-level; pass under trees; +1 roll; wind halved | Low punch out | Prototype “Punch” |
| Flight | Stinger | 1 | Ignore wind; the final 2 hexes become roll | Low, boring, running | Current Stinger card |
| Flight | Carry the Trouble | 2 | Air hexes may cross water or sand of any length this shot | Forced carry | Gloomhaven Flying |
| Landing | Stop | 0 | No roll after landing | Spin it back | Prototype “Stop” |
| Landing | Release | 0 | +2 roll; roll ignores rough cost | Let it run | Heat slipstream |
| Landing | Dart | 1 | Landing ring tightens by 1 | Dialled-in yardage | Current Tighten Spread card |
| Landing | Bounce | 1 | On landing in rough, hop one more hex forward | Lucky kick | Robo Rally pushers |
| Board | Read the Slope | 0 | Choose the direction a slope pushes you on this shot | Reading the green | Robo Rally conveyors |
| Board | Ride the Wind | 0 | Wind push applies twice, but you choose to take it or not after seeing the shape | Using the breeze | Sails of Glory |
| Board | Bank Shot | 1 | Bounce off a tree or wall hex instead of stopping | Off the cart path | Hey That's My Fish blockers |
| Board | Cart Path | 0 | Roll along a straight run of path hexes for free | Classic lucky roll | Heat slipstream |
| Strain (curse) | Shank | — | Unplayable in your hand; discards on draw at hole end | Mishit hangover | Flamme Rouge exhaustion |
| Strain (curse) | Yips | — | While in hand, putts cost +1 | Nerves on the green | X-Wing stress |
| Caddie (passive) | Course Knowledge | — | First Drift each shot is free | Experienced caddie | Balatro jokers |
| Caddie (passive) | Wind Reader | — | See next shot's wind before you choose a club | Reading flags | Into the Breach telegraphs |
| Caddie (passive) | Power Fade | — | Every Drift R also adds +1 roll | Signature shot | Build-defining joker |

Three design rules keep this list healthy as it grows:

- A card names one verb. Combos come from order, not from long rules text.
- Shape always costs more than distance at the same tier.
- Curse cards come from greed (overspend, hazards), never at random.

## Open questions and a prototype plan

The fastest way to learn whether this works is a playable greybox of one hole with eight cards, before any art or content.

Open questions:

- **Tap-to-aim or pure plotting?** The proposal keeps tap-to-aim as the free default path. The prototype screenshot plots every step from cards. Tap-first is faster; plot-first is more board-game.
  - Lets keep it as tap first for now
- **What does a 60° Bend look like in flight?** It needs to render as a curve, not a corner, or the shot reads as a game piece walking.
  - I like the shot shape line we already have. Maybe build upon that?
- **Hand per hole or per shot?** Per hole (today) makes cards scarce across 4 shots; per shot gives more combos but fewer hard choices.
  - Lets try per shot
- **Does the putter use the same system?** All-ground paths with slopes may make putting the best puzzle in the game, or the most tedious.
  - I think putting should be its own separate thing, once you are on teh green. We can keep it simple for now, but in the future, it might be a full on different style mini game (or games?)
- **Power numbers.** The club table above is a starting guess; distance per hex is 10 yards today, so a 9-power Driver is about 90 yards of path plus overspend, far shorter than the current 220–260 yard bands. Either hexes get longer or holes get shorter.
  - I think we can refine the hex size/hole size/club distance to whatever makes sense for the gameplay loop.

Prototype plan:

1. Build the path builder on the current board: the club sets the budget, the tapped target makes a default path, and Fwd, Drift, Bend, Loft and Stop modify it, with a live preview.
   1. Yes, that sounds good. Hide any elements that aren't paramount to the prototype. Things like the scoreboard, debug info, etc. Don't delete them, just hide them for the prototype.&#32;
2. Price cards in power and add the Strain card for overspend.
3. Move wind and the landing ring to the final hex only; keep roll-out and trick-shot points as they are.
   1. Wind can/should affect the shot shape in the air (unless cards/items nullify or add to it)
4. Play 10 holes and count, per shot, how many cards were played and how often the default path was hit unchanged. If most shots are unchanged, shape is too expensive; if every shot uses 3 cards, it is too cheap.

## Sources

Pages opened and checked for this report:

- [Heat: Pedal to the Metal rules](https://officialgamerules.org/game-rules/heat-pedal-to-the-metal-rules/)
- [Mage Knight movement](https://ultraboardgames.com/mage-knight/movement.php) and [Mage Knight rulebook summary](https://rulespal.com/mage-knight/rulebook)
- [Hey, That's My Fish! game help (Board Game Arena)](https://en.doc.boardgamearena.com/Gamehelpheythatsmyfish)
- [Hive game help (Board Game Arena)](https://en.doc.boardgamearena.com/Gamehelphive)
- [How to play Rallyman GT (Zatu)](https://zatu.com/blogs/how-to-play/how-to-play-rallyman-gt)
- [Road to the IGF: Into the Breach (Game Developer)](https://gamedeveloper.com/game-platforms/road-to-the-igf-subset-games-i-into-the-breach-i-)
- [Golf Peaks review (GamingTrend)](https://gamingtrend.com/reviews/a-puzzle-thats-par-for-the-course-golf-peaks-review/)
- [18 Holes review (Meeple Mountain)](https://www.meeplemountain.com/reviews/18-holes/)
- [Golfie review (FingerGuns)](https://fingerguns.net/reviews/2023/02/10/golfie-review-pc-spilling-the-tee/)

From search summaries only, not opened: [Cursed to Golf (Wikipedia)](https://en.wikipedia.org/wiki/Cursed_to_Golf), [Sails of Glory (GeekDad)](https://geekdad.com/2013/04/sails-of-glory/), [Hoplite (Giant Bomb)](https://www.giantbomb.com/hoplite/3030-45184/). Robo Rally, BattleTech, Gloomhaven, X-Wing and Flamme Rouge rules are from general knowledge and marked \* in the survey.

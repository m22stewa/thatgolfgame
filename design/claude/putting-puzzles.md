# Putting puzzles

Oct 23, 2026 · @Mark Stewart

Putting works as a hex maze you read before you strike. The slope arrows already act like Pokémon spin tiles and Chip's Challenge force floors. This build adds two pieces from sliding puzzles: **lips**, walls the ball stops against as in Ricochet Robots, and **slick patches**, ice the ball slides across. The cup still takes only a ball the green delivers, so a bad leave can cost two or three putts, and a planned route can hole a long putt that touches many hexes.

## Survey: movement puzzles on grids

The puzzles that fit putting share one rule: the player chooses where a move starts and which way it goes, and the board decides where it ends.

| Game | What moves | The rule that makes it a puzzle |
| --- | --- | --- |
| [Ricochet Robots](https://en.wikipedia.org/wiki/Ricochet_Robots) | Robots, in straight lines | A robot doesn't stop until it hits a wall or another robot. The fewest moves to the target wins. |
| [Golf Peaks](https://en.wikipedia.org/wiki/Golf_Peaks) | A golf ball, by cards | Each card sets how many tiles the ball moves, and you choose the direction. Slopes carry the ball on, sand and water stop it, portals move it elsewhere, and a chip card jumps obstacles ([review](https://www.useapotion.com/2019/03/golf-peaks-review/), [store page](https://store.steampowered.com/app/923260/Golf_Peaks/)). Its hazards are logic, not physics. |
| [TERASLIDE](https://www.nintendo.com/games/detail/teraslide-switch) | A fox on a hex grid | Every move slides in a straight line to an obstacle or the edge. 100 levels add 10 mechanics, with undo. |
| [Hoplite](<https://en.wikipedia.org/wiki/Hoplite_(video_game)>) | A hero on a hex arena | Lava is instantly fatal. A leap spends a limited stamina pool, so long moves have a cost. |
| Pokémon ice and spin tiles (from memory, approximate) | The player | Ice slides you until something stops you. Spin tiles push you the way their arrow points until a wall, another spin tile or a stop tile. |
| Chip's Challenge (from memory, approximate) | Chip and blocks | Force floors push in a fixed direction. Ice slides straight, and ice corners turn the slide. |

The Pokémon and Chip's Challenge wikis blocked automated reading, so those two rows are from memory.

## Tiles to borrow

Each puzzle rule becomes one kind of green hex, and each one asks the player a different question.

| Puzzle rule | On the green | What it asks of the player | Status |
| --- | --- | --- | --- |
| Spin tile, force floor | Slope arrow: pushes the ball 1 to 3 hexes, again on each hex it lands on | Read the chain from where the struck roll ends | In the game |
| Stop tile, sand | Spike marks stop the ball dead; a flat hex ends the chain | Use them to park a long putt | In the game |
| Ricochet bounce | The forgotten putter: the ball bounces back along its line | Bank shots | In the game |
| Ricochet walls | Lip along a ridge, with a gate in the middle: the ball stops against it | Go round or through the gate, or use the lip as a backstop | Added Oct 23 |
| Ice, TERASLIDE slides | Slick patch: the ball keeps sliding the way it was going until grippy green, a lip or the cup | Strike onto the patch's edge in the direction you want to slide | Added Oct 23 |
| Ice corners, Ricochet's diagonal walls | Sprinkler head: turns the ball 60 degrees | Two-cushion routes | Proposed |
| Golf Peaks uphill roll-back | Tier step: a push that can't climb the step rolls back down | Pace across a two-tier green | Proposed |
| Chip's Challenge one-way floors | One-way gate in a lip | Approach from the right side | Proposed |
| Golf Peaks portals | Paired drains: in one, out the other | Long putts across the whole green | Proposed |
| Golf Peaks' limited cards | A shown putt count for the ball's spot, worked out by a solver | Know a two-putt from a three-putt before you strike | Proposed |

## A sample green

&#91;embedded content: sample green · a planned route and a straight one\]

Striking straight at the cup leaves the ball against the lip, with the next putt routed round it. Striking two hexes onto the slick patch slides the ball through the gap below the lip and onto a slope that pushes it into the cup.

## Proposed rules

Lips and slick patches are in the green generator now. The other pieces are next, in this order: each adds one new question to a green.

In the game as of Oct 23:

- **Lips** run along each ridge spine, on every hex edge the spine crosses. A gate is left open around the spine's middle, and no lip touches the cup. A struck ball or an arrow push stops on the near side of a lip.
- **Slick patches**: 1 or 2 per green, 3 to 7 hexes each, at least 2 hexes from the cup. They have no arrow. A ball that runs onto one keeps going in its last direction until grippy green, where that hex's arrow takes over. A lip or the putter stops it on the ice, and the cup takes it.
- **Fewer free feeders**: 1 or 2 valleys into the cup instead of 2 or 3, and shallower. Over 30 test greens, about 31 of roughly 148 hexes now run into the cup, down from 37, and the longest holed chain averages 9 hexes.

Next to build:

1. **Putt count for the green.** A breadth-first search over every reachable strike gives the fewest putts from any hex. Show it on the gauge (`2 putts from here`), and score a holed putt against it.
2. **Sprinkler heads** turn the ball 60 degrees; one or two per green, never beside the cup.
3. **Tier steps**: on two-tier greens, a push that ends partway up the step rolls back down it.
4. **One-way gates** in some lips.
5. **Paired drains** for long greens only, once the solver can check they don't break a green.

Open question: does Read the Green (it shows the whole route) become too strong once greens are mazes? It might show only the first stop instead.

## Sources

Pages opened on Oct 23, 2026:

- [Ricochet Robots, Wikipedia](https://en.wikipedia.org/wiki/Ricochet_Robots)
- [Golf Peaks, Wikipedia](https://en.wikipedia.org/wiki/Golf_Peaks)
- [Golf Peaks review, Use a Potion](https://www.useapotion.com/2019/03/golf-peaks-review/)
- [Golf Peaks, Steam store page](https://store.steampowered.com/app/923260/Golf_Peaks/)
- [TERASLIDE, Nintendo store page](https://www.nintendo.com/games/detail/teraslide-switch)
- [Hoplite, Wikipedia](<https://en.wikipedia.org/wiki/Hoplite_(video_game)>)

Bulbapedia, the Pokémon Fandom wiki, StrategyWiki and the Chip's Challenge wikis refused automated reading.

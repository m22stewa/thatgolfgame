extends RefCounted
class_name HoleContext

## HoleContext - Per-hole runtime state, including the seeded RNG used to
## make shot resolution and wind generation deterministic for a given seed.

var seed: int = 0
var rng: RandomNumberGenerator = null
var definition: HoleDefinition = null

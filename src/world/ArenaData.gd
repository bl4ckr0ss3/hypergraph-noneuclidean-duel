class_name ArenaData
extends RefCounted
## Immutable description of a generated arena (produced by ArenaGenerator from a
## seed). Runtime/mutable state (current owners, colours, gate open flags,
## collected fragments) is copied into the World node so the same ArenaData can
## be regenerated identically on both peers from the shared seed.

var world_seed: int = 0
var graph: Graph = null
var node_role: PackedInt32Array = PackedInt32Array()   # 0 normal, 1 sat-switch, 2 modular-dial
var k_colors: int = 4
var init_owner: PackedInt32Array = PackedInt32Array()  # -1 neutral
var init_color: PackedInt32Array = PackedInt32Array()  # -1 uncoloured
var gates: Array[Gate] = []
var fragments: Array[ProofFragment] = []
var spawn_points: PackedVector2Array = PackedVector2Array()
var stats: Dictionary = {}

## How many colour states a node of the given role cycles through.
## SAT switches are boolean (2); everything else uses the full palette.
static func colors_for_role(role: int, k: int) -> int:
	return 2 if role == 1 else k

class_name Gate
extends RefCounted
## A puzzle-locked gate guarding one or more proof fragments. Three flavours,
## each a real constraint verified algorithmically every server tick:
##   COLORING - the induced subgraph over `nodes` must be a proper colouring.
##   SAT      - the CNF `clauses` must be satisfied by the switch-node values.
##   MODULAR  - sum of node colour-indices must be congruent to `target` mod m.
## A node is "set" once it has been captured/coloured (node_color >= 0).

enum Type { COLORING, SAT, MODULAR }

var id: int = 0
var type: int = Type.COLORING
var nodes: PackedInt32Array = PackedInt32Array()
var anchor: Vector2 = Vector2.ZERO
var is_open: bool = false
var fragment_ids: Array[int] = []

# COLORING
var coloring_edges: Array = []   # Array[Vector2i] of global node-index pairs
# SAT
var clauses: Array = []          # Array[Array[Vector2i]], local var indices
# MODULAR
var modulus: int = 4
var target: int = 0

func all_set(node_color: PackedInt32Array) -> bool:
	for n in nodes:
		if node_color[n] < 0:
			return false
	return true

func _assignment(node_color: PackedInt32Array) -> PackedByteArray:
	var asg := PackedByteArray()
	asg.resize(nodes.size())
	for i in range(nodes.size()):
		asg[i] = 1 if node_color[nodes[i]] == 1 else 0
	return asg

## The single source of truth for "is this gate satisfied?".
func verify(node_color: PackedInt32Array) -> bool:
	if not all_set(node_color):
		return false
	match type:
		Type.COLORING:
			return GraphColoring.is_proper(node_color, coloring_edges)
		Type.SAT:
			return SatPuzzle.eval(clauses, _assignment(node_color))
		Type.MODULAR:
			var s := 0
			for n in nodes:
				s += node_color[n]
			return FiniteField.mod(s, modulus) == target
	return false

func type_label() -> String:
	match type:
		Type.COLORING: return "COLORING"
		Type.SAT: return "SAT"
		Type.MODULAR: return "MOD-%d" % modulus
	return "?"

## Short status line for the HUD when a player is near this gate.
func progress(node_color: PackedInt32Array) -> String:
	match type:
		Type.SAT:
			var sat := SatPuzzle.satisfied_count(clauses, _assignment(node_color))
			return "SAT %d/%d clauses true" % [sat, clauses.size()]
		Type.MODULAR:
			var s := 0
			var complete := true
			for n in nodes:
				if node_color[n] < 0:
					complete = false
				else:
					s += node_color[n]
			var cur := str(FiniteField.mod(s, modulus)) if complete else "?"
			return "sum mod %d = %s  (need %d)" % [modulus, cur, target]
		Type.COLORING:
			var bad := 0
			for e in coloring_edges:
				if node_color[e.x] >= 0 and node_color[e.y] >= 0 and node_color[e.x] == node_color[e.y]:
					bad += 1
			return "COLORING: %d conflict(s)" % bad
	return ""

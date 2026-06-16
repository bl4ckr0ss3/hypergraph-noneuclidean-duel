class_name GraphColoring
extends RefCounted
## Graph k-colouring constraint used by COLORING gates: a gate opens when every
## node in its set carries a colour and no edge inside the set is monochromatic.
## Verifier + greedy hint + chromatic estimate. Validated in verify.py.
##
## Colours are integers >= 0 (palette index); -1 means "uncoloured".

## True iff every endpoint of every edge is coloured and adjacent colours differ.
static func is_proper(colors: PackedInt32Array, edge_pairs: Array) -> bool:
	for e in edge_pairs:
		var i: int = e.x
		var j: int = e.y
		if colors[i] < 0 or colors[j] < 0:
			return false
		if colors[i] == colors[j]:
			return false
	return true

## Greedy largest-degree-first colouring with k colours. Returns the colouring,
## or an empty array if it could not stay within k colours (a hint, not a proof).
static func greedy(graph: Graph, k: int) -> PackedInt32Array:
	var n := graph.node_count()
	var order := range(n)
	order.sort_custom(func(a, b): return graph.degree(a) > graph.degree(b))
	var color := PackedInt32Array()
	color.resize(n)
	for i in range(n):
		color[i] = -1
	for v in order:
		var used := {}
		for u in graph.neighbors(v):
			if color[u] >= 0:
				used[color[u]] = true
		var picked := -1
		for c in range(k):
			if not used.has(c):
				picked = c
				break
		if picked == -1:
			return PackedInt32Array()
		color[v] = picked
	return color

## Number of colours greedy actually uses on the whole graph (upper-bound style
## estimate of the chromatic number; cheap and deterministic). >= 1.
static func chromatic_estimate(graph: Graph) -> int:
	var n := graph.node_count()
	if n == 0:
		return 0
	var color := greedy(graph, n)  # n colours always succeeds
	var used := {}
	for c in color:
		used[c] = true
	return maxi(1, used.size())

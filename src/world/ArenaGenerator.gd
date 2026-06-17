class_name ArenaGenerator
extends RefCounted
## Deterministic arena generation from a seed. Both peers call generate() with
## the same seed (shared by the host) and produce byte-identical arenas, because
## every random draw comes from a single seeded RandomNumberGenerator consumed
## in a fixed order and no unordered container affects the sequence.
##
## Layout: a hyperbolic "tree-with-rings". Nodes are placed on concentric
## hyperbolic circles (radius = layer * RING_STEP) via the exponential map from
## the origin (Euclidean radius = tanh(rh/2)). Each node links to the angularly
## nearest node one ring in, and neighbours on the same ring link with some
## probability. Because hyperbolic circumference grows exponentially, outer rings
## hold many more nodes than inner ones -- the arena genuinely fills the disk the
## way a {p,q} tiling would, while staying a clean graph to color/route over.

const LAYERS := 3
const RING_STEP := 1.15
const LAYER_COUNTS := [1, 6, 10, 14]
const RING_PROB := 0.75
const K_COLORS := 4

static func generate(world_seed: int) -> ArenaData:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	var data := ArenaData.new()
	data.world_seed = world_seed
	data.k_colors = K_COLORS

	var g := Graph.new()
	var roles_arr: Array[int] = []
	g.add_node(Vector2.ZERO)
	roles_arr.append(0)
	var layers: Array = [[0]]

	for l in range(1, LAYERS + 1):
		var count: int = LAYER_COUNTS[l] if l < LAYER_COUNTS.size() else 12
		var rh: float = float(l) * RING_STEP
		var radius: float = tanh(rh * 0.5)
		var prev: Array = layers[l - 1]
		var this_layer: Array = []
		var off: float = rng.randf() * TAU
		for j in range(count):
			var ang: float = off + TAU * (float(j) + rng.randf_range(-0.15, 0.15)) / float(count)
			var pos := Vector2(cos(ang), sin(ang)) * radius
			var idx := g.add_node(pos)
			roles_arr.append(0)
			this_layer.append(idx)
			var parent := _nearest_by_angle(g, prev, ang)
			if parent >= 0:
				g.add_edge(idx, parent)
		for j in range(count):
			if rng.randf() < RING_PROB:
				g.add_edge(this_layer[j], this_layer[(j + 1) % count])
		layers.append(this_layer)

	data.graph = g

	# --- gates -------------------------------------------------------------
	var gates: Array[Gate] = []
	var used_nodes := {}

	# (1) COLORING gate over the inner ring (layer 1): proper-colour the cycle.
	var color_nodes: Array = layers[1]
	var cgate := Gate.new()
	cgate.id = 0
	cgate.type = Gate.Type.COLORING
	cgate.nodes = PackedInt32Array(color_nodes)
	cgate.coloring_edges = _induced_edges(g, color_nodes)
	cgate.anchor = _centroid(g, color_nodes)
	for n in color_nodes:
		used_nodes[n] = true
	gates.append(cgate)

	# (2) SAT gate over 4 switch-nodes from layer 2.
	var sat_nodes: Array = []
	for t in range(4):
		sat_nodes.append(layers[2][t])
	var sat_gen := SatPuzzle.generate(rng, sat_nodes.size(), 5, 3)
	var sgate := Gate.new()
	sgate.id = 1
	sgate.type = Gate.Type.SAT
	sgate.nodes = PackedInt32Array(sat_nodes)
	sgate.clauses = sat_gen["clauses"]
	sgate.anchor = _centroid(g, sat_nodes)
	for n in sat_nodes:
		used_nodes[n] = true
		roles_arr[n] = 1
	gates.append(sgate)

	# (3) MODULAR gate over 3 dial-nodes from layer 2.
	var mod_nodes: Array = []
	for t in range(4, 7):
		mod_nodes.append(layers[2][t])
	var mgate := Gate.new()
	mgate.id = 2
	mgate.type = Gate.Type.MODULAR
	mgate.nodes = PackedInt32Array(mod_nodes)
	mgate.modulus = K_COLORS
	mgate.target = rng.randi_range(0, K_COLORS - 1)
	mgate.anchor = _centroid(g, mod_nodes)
	for n in mod_nodes:
		used_nodes[n] = true
		roles_arr[n] = 2
	gates.append(mgate)

	data.gates = gates

	# --- proof fragments (FRAGMENT_TARGET total: one per gate + free ones) --
	var fragments: Array[ProofFragment] = []
	var reward_pool: Array = []
	for n in layers[LAYERS]:
		if not used_nodes.has(n):
			reward_pool.append(n)
	if reward_pool.is_empty():
		reward_pool.append(g.node_count() - 1)
	_shuffle(rng, reward_pool)

	var fid := 0
	for gi in range(gates.size()):
		var rn: int = reward_pool[fid % reward_pool.size()]
		var frag := ProofFragment.new()
		frag.id = fid
		frag.pos = g.positions[rn]
		frag.gate_id = gi
		gates[gi].fragment_ids.append(fid)
		fragments.append(frag)
		fid += 1
	while fragments.size() < GameConfig.FRAGMENT_TARGET:
		var rn2: int = reward_pool[fid % reward_pool.size()]
		var frag2 := ProofFragment.new()
		frag2.id = fid
		frag2.pos = g.positions[rn2]
		frag2.gate_id = -1
		fragments.append(frag2)
		fid += 1
	data.fragments = fragments

	# --- runtime node-state init arrays ------------------------------------
	var n_total := g.node_count()
	data.node_role = PackedInt32Array(roles_arr)
	var owner := PackedInt32Array()
	var color := PackedInt32Array()
	owner.resize(n_total)
	color.resize(n_total)
	for i in range(n_total):
		owner[i] = -1
		color[i] = -1
	data.init_owner = owner
	data.init_color = color

	# --- spawn points: opposite nodes on the INNER ring --------------------
	# Spawning on the inner ring (not the rim) gives each player a rich, readable
	# neighbourhood under the recentre camera; a rim spawn pushes the whole arena
	# to one side of the disk.
	var inner: Array = layers[1]
	var s0 := _nearest_by_angle(g, inner, 0.0)
	var s1 := _nearest_by_angle(g, inner, PI)
	var sp := PackedVector2Array()
	sp.append(g.positions[s0] if s0 >= 0 else Vector2(0.3, 0.0))
	sp.append(g.positions[s1] if s1 >= 0 else Vector2(-0.3, 0.0))
	data.spawn_points = sp

	data.stats = _build_stats(data)
	return data

# --- helpers ---------------------------------------------------------------
static func _nearest_by_angle(g: Graph, candidates: Array, ang: float) -> int:
	var best := -1
	var best_d := INF
	for c in candidates:
		var p: Vector2 = g.positions[c]
		var a := atan2(p.y, p.x)
		var diff: float = absf(_ang_diff(a, ang))
		if diff < best_d:
			best_d = diff
			best = c
	return best

static func _ang_diff(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI

static func _induced_edges(g: Graph, nodeset: Array) -> Array:
	var s := {}
	for n in nodeset:
		s[n] = true
	var out: Array = []
	for e in g.edges:
		if s.has(e.x) and s.has(e.y):
			out.append(e)
	return out

static func _centroid(g: Graph, nodeset: Array) -> Vector2:
	var c := Vector2.ZERO
	for n in nodeset:
		c += g.positions[n]
	if nodeset.size() > 0:
		c /= float(nodeset.size())
	return HyperMath.clamp_disk(c)

static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t

static func _build_stats(data: ArenaData) -> Dictionary:
	var g := data.graph
	var sat_clauses := 0
	var sat_vars := 0
	for gate in data.gates:
		if gate.type == Gate.Type.SAT:
			sat_clauses += gate.clauses.size()
			sat_vars += gate.nodes.size()
	var chrom := GraphColoring.chromatic_estimate(g)
	var diff_score := float(g.edges.size()) * 0.12 + float(sat_clauses) * 0.6 \
		+ float(data.gates.size()) * 1.0 + float(chrom) * 0.5
	var diff_label := "EASY"
	if diff_score > 9.0:
		diff_label = "HARD"
	elif diff_score > 6.0:
		diff_label = "MEDIUM"
	return {
		"seed": data.world_seed,
		"nodes": g.node_count(),
		"edges": g.edges.size(),
		"gates": data.gates.size(),
		"fragments": data.fragments.size(),
		"chromatic_estimate": chrom,
		"sat_vars": sat_vars,
		"sat_clauses": sat_clauses,
		"connected": g.is_fully_connected(),
		"difficulty": diff_label,
		"difficulty_score": snappedf(diff_score, 0.1),
	}

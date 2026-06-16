extends Node
## Headless GDScript test of the in-engine logic (mirrors tools/reference/verify.py
## but exercises the real GDScript ports). Run with autoloads present via:
##
##     godot --headless --path . tests/TestRunner.tscn
##
## Exits 0 if every check passes, 1 otherwise.

var _checks := 0
var _fails := 0

func _ready() -> void:
	print("=== HYPERGRAPH GDScript logic tests ===")
	_test_hyper()
	_test_graph()
	_test_coloring()
	_test_sat()
	_test_field()
	_test_arena()
	print("---------------------------------------")
	if _fails == 0:
		print("RESULT: ALL %d CHECKS PASSED" % _checks)
	else:
		print("RESULT: %d / %d CHECKS FAILED" % [_fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func chk(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("  FAIL: %s" % msg)

func _approx(a: float, b: float, t: float = 1e-4) -> bool:
	return absf(a - b) <= t

func _rdisk(rng: RandomNumberGenerator, maxr: float = 0.85) -> Vector2:
	var r := maxr * sqrt(rng.randf())
	var th := rng.randf() * TAU
	return Vector2(cos(th), sin(th)) * r

# --- tests -----------------------------------------------------------------
func _test_hyper() -> void:
	print("[1] HyperMath")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for _i in range(400):
		var a := _rdisk(rng)
		var x := _rdisk(rng)
		var y := _rdisk(rng)
		chk(HyperMath.recenter(a, a).length() < 1e-5, "recenter(a,a) != 0")
		chk((HyperMath.recenter_inv(a, HyperMath.recenter(a, x)) - x).length() < 1e-4, "recenter inverse")
		chk(HyperMath.recenter(a, x).length() < 1.0, "recenter left disk")
		chk(_approx(HyperMath.hdist(HyperMath.recenter(a, x), HyperMath.recenter(a, y)), HyperMath.hdist(x, y), 1e-3), "isometry")
		chk(_approx(HyperMath.hdist(x, y), HyperMath.hdist(y, x)), "symmetry")
	for _i in range(400):
		var p := _rdisk(rng, 0.9)
		var ang := rng.randf() * TAU
		var step := rng.randf_range(0.05, 1.4)
		var q := HyperMath.move(p, Vector2(cos(ang), sin(ang)), step)
		chk(q.length() < 1.0, "move left disk")
		chk(_approx(HyperMath.hdist(p, q), step, 1e-3), "move step length")
	for _i in range(200):
		var u := _rdisk(rng)
		var v := _rdisk(rng)
		chk((HyperMath.geodesic_point(u, v, 0.0) - u).length() < 1e-5, "geodesic t=0")
		chk((HyperMath.geodesic_point(u, v, 1.0) - v).length() < 1e-3, "geodesic t=1")

func _test_graph() -> void:
	print("[2] Graph / Dijkstra")
	var g := Graph.new()
	for i in range(4):
		g.add_node(Vector2(cos(0.0), sin(0.0)) * tanh(float(i) * 0.5))
	g.add_edge(0, 1)
	g.add_edge(1, 2)
	g.add_edge(2, 3)
	var path := g.shortest_path(0, 3)
	chk(path.size() == 4, "path graph length")
	chk(path[0] == 0 and path[3] == 3, "path endpoints")
	chk(g.is_fully_connected(), "connected")
	g.add_node(Vector2(0.9, 0.0))  # isolated
	chk(not g.is_fully_connected(), "disconnected detected")

func _test_coloring() -> void:
	print("[3] GraphColoring")
	var colors := PackedInt32Array([0, 1, 0, 1])
	var good := [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3)]
	chk(GraphColoring.is_proper(colors, good), "proper accepted")
	var bad := [Vector2i(0, 2)]  # both colour 0
	chk(not GraphColoring.is_proper(colors, bad), "monochromatic rejected")
	var partial := PackedInt32Array([0, -1])
	chk(not GraphColoring.is_proper(partial, [Vector2i(0, 1)]), "uncoloured rejected")

func _test_sat() -> void:
	print("[4] SatPuzzle")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i in range(300):
		var n := rng.randi_range(3, 7)
		var m := rng.randi_range(2, 8)
		var inst := SatPuzzle.generate(rng, n, m, 3)
		chk(SatPuzzle.eval(inst["clauses"], inst["planted"]), "planted satisfies CNF")

func _test_field() -> void:
	print("[5] FiniteField")
	for p in [5, 7, 11, 13]:
		for a in range(1, p):
			chk(FiniteField.mul(a, FiniteField.inv(a, p), p) == 1, "GF(%d) inverse" % p)
	chk(FiniteField.mod(-3, 7) == 4, "mod negative")

func _test_arena() -> void:
	print("[6] ArenaGenerator determinism")
	var a := ArenaGenerator.generate(12345)
	var b := ArenaGenerator.generate(12345)
	var c := ArenaGenerator.generate(99999)
	chk(a.graph.node_count() == b.graph.node_count(), "det node count")
	chk(a.graph.edges.size() == b.graph.edges.size(), "det edge count")
	var same := a.graph.positions.size() == b.graph.positions.size()
	if same:
		for i in range(a.graph.positions.size()):
			if a.graph.positions[i] != b.graph.positions[i]:
				same = false
				break
	chk(same, "deterministic positions for same seed")
	chk(a.graph.is_fully_connected(), "arena connected")
	chk(a.fragments.size() >= 5, "fragments >= target")
	chk(a.gates.size() == 3, "three gates generated")
	var differs := a.graph.edges.size() != c.graph.edges.size()
	if not differs and a.graph.positions.size() == c.graph.positions.size():
		for i in range(a.graph.positions.size()):
			if a.graph.positions[i] != c.graph.positions[i]:
				differs = true
				break
	chk(differs, "different seed produces different arena")

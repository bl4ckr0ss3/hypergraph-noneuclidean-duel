extends Node
## Smoke test: drives PoincareView.build() exactly like a real match start, to
## surface any runtime error in arena generation / tiling / entity setup that the
## pure-logic tests don't cover. Run:
##   godot --headless --path . tests/SmokeBuild.tscn

func _ready() -> void:
	print(">> smoke: start")
	var w = preload("res://src/render/PoincareView.gd").new()
	w.name = "World"
	add_child(w)
	print(">> smoke: world node ready, calling build()")
	var roster := { 1: {"slot": 0, "name": "P1"}, 2: {"slot": 1, "name": "P2"} }
	w.build(1234567, roster, 0)
	print(">> smoke: build() returned")
	print(">> arena null? ", w.arena == null)
	if w.arena:
		print(">> nodes=", w.arena.graph.node_count(), " edges=", w.arena.graph.edges.size())
		print(">> gates=", w.arena.gates.size(), " fragments=", w.arena.fragments.size())
		print(">> tiling tiles=", w.tiling.size())
		print(">> players=", w.players.size(), " enemies=", w.enemies.size())
		print(">> spawn_points=", w.arena.spawn_points.size())
	print(">> GameState.seconds_left=", GameState.seconds_left, " state=", GameState.state)
	print(">> smoke: DONE OK")
	get_tree().quit(0)

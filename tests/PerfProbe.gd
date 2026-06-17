extends Node2D
## Measures real average FPS of the full render path (vsync off) for a few
## seconds, then prints and quits. Confirms the geodesic-arc optimisation.

var _t := 0.0
var _frames := 0
var _w

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_w = preload("res://src/render/PoincareView.gd").new()
	_w.name = "World"
	add_child(_w)
	var roster := { 1: {"slot": 0, "name": "Alice"}, 2: {"slot": 1, "name": "Bob"} }
	_w.build(20260617, roster, 0)
	_w.local_id = 1
	for i in range(mini(12, _w.arena.graph.node_count())):
		_w.node_color[i] = i % _w.arena.k_colors
		_w.node_owner[i] = i % 2

func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _t >= 3.0:
		print(">> avg_fps=%.1f frames=%d engine_fps=%d" % [float(_frames) / _t, _frames, Engine.get_frames_per_second()])
		get_tree().quit(0)

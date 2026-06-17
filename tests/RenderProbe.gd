extends Node2D
## Offscreen-ish render probe: builds a real arena, draws one frame in a window,
## captures it to res://_probe.png, and quits. Lets us SEE what the game renders
## without a human. Run windowed (NOT headless):
##   godot --path . tests/RenderProbe.tscn

func _ready() -> void:
	var w = preload("res://src/render/PoincareView.gd").new()
	w.name = "World"
	add_child(w)
	var roster := { 1: {"slot": 0, "name": "Alice"}, 2: {"slot": 1, "name": "Bob"} }
	w.build(20260617, roster, 0)
	w.local_id = 1  # centre camera on player 1

	# simulate some captured / coloured nodes for a representative shot
	for i in range(mini(12, w.arena.graph.node_count())):
		w.node_color[i] = i % w.arena.k_colors
		w.node_owner[i] = i % 2
	# put player 2 somewhere visible near the centre
	if w.players.has(2):
		w.players[2].hpos = Vector2(0.35, 0.2)
	# a geodesic projectile mid-flight
	var p = preload("res://src/gameplay/Projectile.gd").new()
	p.origin = w.players[1].hpos
	p.dir = Vector2(1.0, 0.25).normalized()
	p.s = 0.8
	p.owner_slot = 0
	w.projectiles.append(p)

	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_probe.png")
	print(">> probe saved res://_probe.png size=", img.get_size())
	get_tree().quit(0)

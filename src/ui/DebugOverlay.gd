class_name DebugOverlay
extends Control
## Toggleable (F3) developer overlay: seed, graph/puzzle stats from the generator,
## live gate/fragment state, networking info, FPS, and the tail of the log buffer.

var world: PoincareView = null
var _text: Label
var _acc := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var panel := PanelContainer.new()
	panel.modulate = Color(1, 1, 1, 0.92)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 12)
	_text.add_theme_color_override("font_color", Color("9fe8d0"))
	margin.add_child(_text)

func toggle() -> void:
	visible = not visible

func _process(delta: float) -> void:
	if not visible:
		return
	_acc += delta
	if _acc < 0.15:  # throttle: rebuilding the stats string every frame is costly
		return
	_acc = 0.0
	_text.text = _build_text()

func _build_text() -> String:
	var lines: Array[String] = []
	lines.append("HYPERGRAPH DEBUG  (F3 to hide)")
	lines.append("fps: %d" % Engine.get_frames_per_second())
	lines.append("--- net ---")
	lines.append("id: %d   host: %s   peers: %d" % [Net.get_local_id(), str(Net.is_host), Net.roster.size()])

	if world == null or world.arena == null:
		lines.append("(no arena - in menu)")
		return "\n".join(lines)

	var st: Dictionary = world.arena.stats
	lines.append("--- generation (seed %d) ---" % int(st.get("seed", 0)))
	lines.append("nodes: %d   edges: %d" % [int(st.get("nodes", 0)), int(st.get("edges", 0))])
	lines.append("gates: %d   fragments: %d" % [int(st.get("gates", 0)), int(st.get("fragments", 0))])
	lines.append("chromatic est: %d   k-colours: %d" % [int(st.get("chromatic_estimate", 0)), world.arena.k_colors])
	lines.append("SAT vars/clauses: %d / %d" % [int(st.get("sat_vars", 0)), int(st.get("sat_clauses", 0))])
	lines.append("connected: %s" % str(st.get("connected", true)))
	lines.append("difficulty: %s (%.1f)" % [str(st.get("difficulty", "?")), float(st.get("difficulty_score", 0.0))])

	lines.append("--- live ---")
	var open_gates := 0
	for g in world.arena.gates:
		if g.is_open:
			open_gates += 1
	lines.append("gates open: %d / %d" % [open_gates, world.arena.gates.size()])
	var collected := int(GameState.scores.get(0, 0)) + int(GameState.scores.get(1, 0))
	lines.append("fragments taken: %d / %d" % [collected, world.arena.fragments.size()])
	var enemies_alive := 0
	for e in world.enemies:
		if e.alive:
			enemies_alive += 1
	lines.append("enemies alive: %d / %d" % [enemies_alive, world.enemies.size()])
	for g in world.arena.gates:
		lines.append("  gate %d [%s]: %s" % [g.id, g.type_label(), "OPEN" if g.is_open else g.progress(world.node_color)])

	lines.append("--- log ---")
	for line in Log.recent(6):
		lines.append(line)

	return "\n".join(lines)

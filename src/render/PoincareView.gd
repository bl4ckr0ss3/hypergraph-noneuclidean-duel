class_name PoincareView
extends Node2D
## The World node: both the hyperbolic renderer AND the in-match state container
## + networking surface. Lives at the fixed path /root/Main/World on both peers
## so its RPCs resolve.
##
## RENDERING. Everything is drawn in the Poincare-disk projection. The camera is
## a Mobius "recenter" that maps the LOCAL player to the disk centre, so each peer
## sees itself centred while the shared world state renders correctly-differently
## for each. Because Mobius maps send geodesics to geodesics, straight hyperbolic
## paths (edges, projectiles) draw as circular arcs, and objects shrink toward the
## boundary (the conformal (1-|w|^2) factor) -- the signature non-Euclidean look.
##
## AUTHORITY. The host (peer 1) simulates enemies, resolves all combat, owns node/
## gate/fragment/round state and broadcasts it. Clients send their own player
## state and request captures/collects; the host validates and echoes results.

const STATE_SEND_HZ := GameConfig.STATE_SEND_HZ
const SIM_HZ := GameConfig.SIM_HZ
const ENEMY_COUNT := 2

var arena: ArenaData = null
var node_owner: PackedInt32Array = PackedInt32Array()
var node_color: PackedInt32Array = PackedInt32Array()
var players: Dictionary = {}            # peer_id -> HPlayer
var enemies: Array[GraphHunter] = []
var projectiles: Array[Projectile] = []
var tiling: Array = []                  # background {p,q} tiles (Array[PackedVector2Array])

var local_id: int = 1
var is_host: bool = false

var _send_accum := 0.0
var _sim_accum := 0.0
var _host_rng := RandomNumberGenerator.new()

signal arena_built(stats: Dictionary)

func _ready() -> void:
	_host_rng.randomize()
	set_process(true)

# ---------------------------------------------------------------------------
# Build / teardown
# ---------------------------------------------------------------------------
func build(world_seed: int, roster: Dictionary, mode: int) -> void:
	arena = ArenaGenerator.generate(world_seed)
	node_owner = arena.init_owner.duplicate()
	node_color = arena.init_color.duplicate()
	tiling = HyperTiling.regular_tiling(7, 3, 2, 48)

	players.clear()
	for pid in roster:
		var slot := int(roster[pid]["slot"])
		var pl := HPlayer.new()
		pl.peer_id = int(pid)
		pl.slot = slot
		pl.pname = str(roster[pid].get("name", "P%d" % (slot + 1)))
		pl.color = GameConfig.slot_color(slot)
		pl.spawn(_spawn_for(slot))
		players[int(pid)] = pl

	local_id = Net.get_local_id()
	is_host = Net.is_host

	enemies.clear()
	for i in range(ENEMY_COUNT):
		var e := GraphHunter.new()
		var sn: int = clampi(arena.graph.node_count() - 1 - i * 4, 0, arena.graph.node_count() - 1)
		e.hpos = arena.graph.positions[sn]
		e.current_node = sn
		enemies.append(e)

	projectiles.clear()
	GameState.reset_match(mode)
	GameState.set_state(GameState.S.PLAYING)
	arena_built.emit(arena.stats)
	Log.info("Arena built seed=%d %s" % [world_seed, str(arena.stats)])

func teardown() -> void:
	arena = null
	players.clear()
	enemies.clear()
	projectiles.clear()
	tiling.clear()
	queue_redraw()

func _spawn_for(slot: int) -> Vector2:
	if arena and slot < arena.spawn_points.size():
		return arena.spawn_points[slot]
	return Vector2.ZERO

func local_player() -> HPlayer:
	if players.has(local_id):
		return players[local_id]
	return null

# ---------------------------------------------------------------------------
# Frame loop
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if arena == null:
		return
	if GameState.state == GameState.S.PLAYING:
		_handle_local_input(delta)
		_advance_projectiles(delta)
		_update_local_respawn(delta)
		if is_host:
			_host_simulate(delta)
		_send_accum += delta
		if _send_accum >= 1.0 / STATE_SEND_HZ:
			_send_accum = 0.0
			_broadcast_local_state()
	queue_redraw()

func _view() -> Dictionary:
	var size := get_viewport_rect().size
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.46
	return { "center": center, "radius": radius }

func _camera_center() -> Vector2:
	var pl := local_player()
	return pl.hpos if pl else Vector2.ZERO

# ---------------------------------------------------------------------------
# Local input
# ---------------------------------------------------------------------------
func _handle_local_input(delta: float) -> void:
	var pl := local_player()
	if pl == null:
		return
	var v := _view()
	var center: Vector2 = v["center"]
	var mouse := get_global_mouse_position()
	pl.facing = (mouse - center).angle()
	pl.fire_cd = maxf(0.0, pl.fire_cd - delta)
	if not pl.alive:
		return

	# Screen-space WASD -> p-frame direction (camera flips y when projecting).
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if iv.length() > 0.05:
		var dir := Vector2(iv.x, -iv.y)
		pl.hpos = HyperMath.move(pl.hpos, dir.normalized(), GameConfig.PLAYER_SPEED * delta)

	if Input.is_action_pressed("fire") and pl.fire_cd <= 0.0:
		pl.fire_cd = GameConfig.FIRE_COOLDOWN
		var aim := HyperMath.aim_dir(center, mouse)
		spawn_projectile.rpc(pl.hpos, aim, pl.slot)

	if Input.is_action_just_pressed("cycle_color"):
		pl.selected_color = (pl.selected_color + 1) % arena.k_colors

	if Input.is_action_just_pressed("interact"):
		_try_interact(pl)

func _try_interact(pl: HPlayer) -> void:
	# Prefer collecting an available fragment over capturing a node.
	var best_f := -1
	var best_fd := INF
	for f in arena.fragments:
		if f.is_available(arena.gates):
			var d := HyperMath.hdist(pl.hpos, f.pos)
			if d < best_fd:
				best_fd = d
				best_f = f.id
	if best_f != -1 and best_fd <= GameConfig.INTERACT_RANGE_H:
		if is_host:
			_handle_collect_request(local_id, best_f)
		else:
			request_collect.rpc_id(1, best_f)
		return

	var bn := arena.graph.nearest_node(pl.hpos)
	if bn >= 0 and HyperMath.hdist(pl.hpos, arena.graph.positions[bn]) <= GameConfig.CAPTURE_RANGE_H:
		if is_host:
			_handle_capture_request(local_id, bn)
		else:
			request_capture.rpc_id(1, bn)

func _advance_projectiles(delta: float) -> void:
	var still_alive: Array[Projectile] = []
	for p in projectiles:
		p.advance(delta)
		if p.alive:
			still_alive.append(p)
	projectiles = still_alive

func _update_local_respawn(delta: float) -> void:
	var pl := local_player()
	if pl and not pl.alive:
		pl.respawn_timer -= delta
		if pl.respawn_timer <= 0.0:
			pl.spawn(_spawn_for(pl.slot))

# ---------------------------------------------------------------------------
# Host simulation (authoritative)
# ---------------------------------------------------------------------------
func _alive_player_positions() -> Array:
	var out: Array = []
	for pid in players:
		var pl: HPlayer = players[pid]
		if pl.alive:
			out.append(pl.hpos)
	return out

func _host_simulate(delta: float) -> void:
	for e in enemies:
		if not e.alive:
			e.think_cd -= delta
			if e.think_cd <= 0.0:
				_respawn_enemy(e)
			continue
		e.think_cd -= delta
		if e.think_cd <= 0.0:
			e.think_cd = GameConfig.ENEMY_THINK_INTERVAL
			var targets := _alive_player_positions()
			if not targets.is_empty():
				e.think(arena.graph, targets)
		e.step(arena.graph, delta)

	# enemy -> player contact
	for e in enemies:
		if not e.alive:
			continue
		for pid in players:
			var pl: HPlayer = players[pid]
			if pl.alive and HyperMath.hdist(e.hpos, pl.hpos) < GameConfig.ENEMY_HIT_RANGE_H:
				_apply_hit(pid)

	# projectile collisions
	for p in projectiles:
		if not p.alive:
			continue
		var ppos := p.pos()
		for e in enemies:
			if e.alive and HyperMath.hdist(ppos, e.hpos) < GameConfig.ENEMY_HIT_RANGE_H:
				e.alive = false
				e.think_cd = GameConfig.RESPAWN_SECONDS
				p.alive = false
				break
		if p.alive and GameState.mode == GameState.Mode.DUEL:
			for pid in players:
				var pl: HPlayer = players[pid]
				if pl.alive and pl.slot != p.owner_slot and HyperMath.hdist(ppos, pl.hpos) < GameConfig.PLAYER_RADIUS_H * 1.5:
					_apply_hit(pid)
					p.alive = false
					break

	GameState.tick_timer(delta)
	var result := GameState.check_win()
	if result != "":
		_end_round(result)
		return

	_sim_accum += delta
	if _sim_accum >= 1.0 / SIM_HZ:
		_sim_accum = 0.0
		_broadcast_enemy_state()
		push_round_snapshot.rpc(GameState.make_snapshot())

func _apply_hit(pid: int) -> void:
	var pl: HPlayer = players[pid]
	pl.alive = false
	pl.respawn_timer = GameConfig.RESPAWN_SECONDS
	if pid != local_id:
		notify_hit.rpc_id(pid)

func _respawn_enemy(e: GraphHunter) -> void:
	# Re-enter at whichever outer node is farthest from all players.
	var n := arena.graph.node_count()
	var start: int = maxi(0, n - 14)
	var best: int = n - 1
	var best_d := -1.0
	for i in range(start, n):
		var mind := INF
		for pid in players:
			mind = minf(mind, HyperMath.hdist(arena.graph.positions[i], players[pid].hpos))
		if mind > best_d:
			best_d = mind
			best = i
	e.hpos = arena.graph.positions[best]
	e.current_node = best
	e.path = PackedInt32Array()
	e.think_cd = 0.0
	e.alive = true

func _handle_capture_request(sender_id: int, node: int) -> void:
	if not is_host or arena == null:
		return
	if not players.has(sender_id):
		return
	var pl: HPlayer = players[sender_id]
	if not pl.alive:
		return
	if node < 0 or node >= arena.graph.node_count():
		return
	if HyperMath.hdist(pl.hpos, arena.graph.positions[node]) > GameConfig.CAPTURE_RANGE_H:
		return
	var role := arena.node_role[node]
	var cur := node_color[node]
	var newc := pl.selected_color
	match role:
		1:  # SAT switch: boolean toggle
			newc = 0 if cur != 0 else 1
		2:  # modular dial: cycle 0..k-1
			newc = (cur + 1) % arena.k_colors if cur >= 0 else 0
		_:  # normal node: paint with carried colour
			newc = pl.selected_color
	node_owner[node] = pl.slot
	node_color[node] = newc
	apply_node_state.rpc(node, pl.slot, newc)
	_recheck_gates()

func _handle_collect_request(sender_id: int, frag_id: int) -> void:
	if not is_host or arena == null:
		return
	if frag_id < 0 or frag_id >= arena.fragments.size():
		return
	var f: ProofFragment = arena.fragments[frag_id]
	if not f.is_available(arena.gates):
		return
	if not players.has(sender_id):
		return
	var pl: HPlayer = players[sender_id]
	if not pl.alive or HyperMath.hdist(pl.hpos, f.pos) > GameConfig.INTERACT_RANGE_H:
		return
	f.collected = true
	f.collected_by = pl.slot
	GameState.add_score(pl.slot, 1)
	apply_fragment_collected.rpc(frag_id, pl.slot)
	var result := GameState.check_win()
	if result != "":
		_end_round(result)

func _recheck_gates() -> void:
	for gate in arena.gates:
		var open := gate.verify(node_color)
		if open != gate.is_open:
			gate.is_open = open
			apply_gate_state.rpc(gate.id, open)
			Log.info("Gate %d (%s) -> %s" % [gate.id, gate.type_label(), "OPEN" if open else "LOCKED"])

func _end_round(result: String) -> void:
	if GameState.state == GameState.S.ROUND_OVER:
		return
	GameState.declare_over(result)
	declare_round_over.rpc(result)

func _broadcast_local_state() -> void:
	var pl := local_player()
	if pl == null:
		return
	push_player_state.rpc(pl.hpos, pl.facing, pl.selected_color, pl.alive)

func _broadcast_enemy_state() -> void:
	var ps := PackedVector2Array()
	var al := PackedByteArray()
	for e in enemies:
		ps.append(e.hpos)
		al.append(1 if e.alive else 0)
	push_enemy_state.rpc(ps, al)

# ---------------------------------------------------------------------------
# RPCs
# ---------------------------------------------------------------------------
@rpc("any_peer", "unreliable_ordered", "call_remote")
func push_player_state(hpos: Vector2, facing: float, sel: int, alive: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		var pl: HPlayer = players[sender]
		pl.hpos = hpos
		pl.facing = facing
		pl.selected_color = sel
		pl.alive = alive

@rpc("any_peer", "reliable", "call_local")
func spawn_projectile(origin: Vector2, dir: Vector2, owner_slot: int) -> void:
	var p := Projectile.new()
	p.origin = origin
	p.dir = dir
	p.owner_slot = owner_slot
	projectiles.append(p)

@rpc("any_peer", "reliable", "call_remote")
func request_capture(node: int) -> void:
	_handle_capture_request(multiplayer.get_remote_sender_id(), node)

@rpc("any_peer", "reliable", "call_remote")
func request_collect(frag_id: int) -> void:
	_handle_collect_request(multiplayer.get_remote_sender_id(), frag_id)

@rpc("authority", "reliable", "call_remote")
func apply_node_state(node: int, owner_slot: int, color: int) -> void:
	if node >= 0 and node < node_color.size():
		node_owner[node] = owner_slot
		node_color[node] = color

@rpc("authority", "reliable", "call_remote")
func apply_gate_state(gate_id: int, open: bool) -> void:
	if arena and gate_id >= 0 and gate_id < arena.gates.size():
		arena.gates[gate_id].is_open = open

@rpc("authority", "reliable", "call_remote")
func apply_fragment_collected(frag_id: int, slot: int) -> void:
	if arena and frag_id >= 0 and frag_id < arena.fragments.size():
		arena.fragments[frag_id].collected = true
		arena.fragments[frag_id].collected_by = slot
		GameState.add_score(slot, 1)

@rpc("authority", "unreliable_ordered", "call_remote")
func push_enemy_state(ps: PackedVector2Array, al: PackedByteArray) -> void:
	for i in range(mini(ps.size(), enemies.size())):
		enemies[i].hpos = ps[i]
		enemies[i].alive = al[i] != 0

@rpc("authority", "unreliable_ordered", "call_remote")
func push_round_snapshot(snap: Dictionary) -> void:
	GameState.apply_snapshot(snap)

@rpc("authority", "reliable", "call_remote")
func notify_hit() -> void:
	var pl := local_player()
	if pl:
		pl.alive = false
		pl.respawn_timer = GameConfig.RESPAWN_SECONDS

@rpc("authority", "reliable", "call_remote")
func declare_round_over(result: String) -> void:
	GameState.declare_over(result)

# ---------------------------------------------------------------------------
# HUD / debug helpers
# ---------------------------------------------------------------------------
func hud_hint() -> String:
	var pl := local_player()
	if pl == null:
		return ""
	if not pl.alive:
		return "DOWN - respawning in %.1fs" % maxf(0.0, pl.respawn_timer)
	# nearest gate by anchor
	var near := ""
	var best_d := INF
	for gate in arena.gates:
		var d := HyperMath.hdist(pl.hpos, gate.anchor)
		if d < best_d and d < 2.2:
			best_d = d
			near = "[%s] %s" % [gate.type_label(), ("OPEN" if gate.is_open else gate.progress(node_color))]
	return near

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
func _draw() -> void:
	if arena == null:
		return
	var v := _view()
	var center: Vector2 = v["center"]
	var radius: float = v["radius"]
	var cam := _camera_center()

	draw_circle(center, radius, Color(0.03, 0.05, 0.08, 1.0))
	_draw_tiling(cam, center, radius)
	draw_arc(center, radius, 0.0, TAU, 96, GameConfig.DISK_EDGE_COLOR, 2.0, true)
	_draw_edges(cam, center, radius)
	_draw_gates(cam, center, radius)
	_draw_nodes(cam, center, radius)
	_draw_fragments(cam, center, radius)
	_draw_enemies(cam, center, radius)
	_draw_projectiles(cam, center, radius)
	_draw_players(cam, center, radius)

func _to_screen(cam: Vector2, world: Vector2, center: Vector2, radius: float) -> Vector2:
	var w := HyperMath.recenter(cam, world)
	return center + Vector2(w.x, -w.y) * radius

## Conformal shrink factor toward the boundary (the "everything gets small far
## away" hyperbolic look). Returns ~1 at the centre, small near the edge.
func _shrink(cam: Vector2, world: Vector2) -> float:
	var w := HyperMath.recenter(cam, world)
	return clampf(1.0 - w.length_squared(), 0.12, 1.0)

func _geo_screen(cam: Vector2, a: Vector2, b: Vector2, center: Vector2, radius: float, n: int = 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var samples := HyperMath.geodesic_samples(a, b, n)
	for s in samples:
		pts.append(_to_screen(cam, s, center, radius))
	return pts

func _draw_tiling(cam: Vector2, center: Vector2, radius: float) -> void:
	for poly in tiling:
		var m: int = poly.size()
		for i in range(m):
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % m]
			var line := _geo_screen(cam, a, b, center, radius, 6)
			draw_polyline(line, GameConfig.BG_TILING_COLOR, 1.0, true)

func _draw_edges(cam: Vector2, center: Vector2, radius: float) -> void:
	for e in arena.graph.edges:
		var a: Vector2 = arena.graph.positions[e.x]
		var b: Vector2 = arena.graph.positions[e.y]
		var line := _geo_screen(cam, a, b, center, radius, 12)
		draw_polyline(line, GameConfig.GEODESIC_COLOR, 1.5, true)

func _draw_gates(cam: Vector2, center: Vector2, radius: float) -> void:
	var font := ThemeDB.fallback_font
	for gate in arena.gates:
		var col := Color("9d7bff") if gate.type == Gate.Type.SAT else (Color("ffb454") if gate.type == Gate.Type.MODULAR else Color("66d9a6"))
		# ring around each gate node
		for n in gate.nodes:
			var sp := _to_screen(cam, arena.graph.positions[n], center, radius)
			var sc := _shrink(cam, arena.graph.positions[n])
			draw_arc(sp, 14.0 * sc, 0.0, TAU, 20, col, 2.0, true)
		# anchor marker
		var ap := _to_screen(cam, gate.anchor, center, radius)
		var asc := _shrink(cam, gate.anchor)
		var label := gate.type_label().substr(0, 1)
		if gate.is_open:
			draw_arc(ap, 18.0 * asc, 0.0, TAU, 24, Color(col, 0.5), 2.0, true)
		else:
			draw_circle(ap, 16.0 * asc, Color(col, 0.22))
			draw_arc(ap, 16.0 * asc, 0.0, TAU, 24, col, 2.0, true)
		draw_string(font, ap + Vector2(-5, 5) * asc, label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * asc), Color.WHITE)

func _draw_nodes(cam: Vector2, center: Vector2, radius: float) -> void:
	for i in range(arena.graph.node_count()):
		var pos: Vector2 = arena.graph.positions[i]
		var sp := _to_screen(cam, pos, center, radius)
		var sc := _shrink(cam, pos)
		var r := 9.0 * sc
		var col := GameConfig.NEUTRAL_COLOR
		if node_color[i] >= 0:
			col = GameConfig.node_color(node_color[i])
		draw_circle(sp, r, col)
		# owner outline
		var own_slot := node_owner[i]
		var oc := GameConfig.slot_color(own_slot) if own_slot >= 0 else Color(1, 1, 1, 0.25)
		draw_arc(sp, r + 2.0, 0.0, TAU, 18, oc, 2.0, true)
		# role glyph
		var role := arena.node_role[i]
		if role == 1:
			draw_rect(Rect2(sp - Vector2(r, r) * 0.5, Vector2(r, r)), Color(0, 0, 0, 0.55), false, 1.5)
		elif role == 2:
			draw_arc(sp, r * 0.45, 0.0, TAU, 12, Color(0, 0, 0, 0.55), 1.5, true)

func _draw_fragments(cam: Vector2, center: Vector2, radius: float) -> void:
	var t := float(Time.get_ticks_msec()) / 1000.0
	for f in arena.fragments:
		if f.collected:
			continue
		var sp := _to_screen(cam, f.pos, center, radius)
		var sc := _shrink(cam, f.pos)
		var avail := f.is_available(arena.gates)
		var pulse := 1.0 + 0.18 * sin(t * 4.0)
		var r := 8.0 * sc * (pulse if avail else 1.0)
		var col := Color("ffe066") if avail else Color(0.5, 0.5, 0.55, 0.5)
		var pts := PackedVector2Array([
			sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)
		])
		draw_colored_polygon(pts, col)
		if not avail:
			draw_arc(sp, r + 3.0, 0.0, TAU, 16, Color(0.8, 0.3, 0.3, 0.6), 1.5, true)

func _draw_enemies(cam: Vector2, center: Vector2, radius: float) -> void:
	for e in enemies:
		if not e.alive:
			continue
		var sp := _to_screen(cam, e.hpos, center, radius)
		var sc := _shrink(cam, e.hpos)
		var r := 12.0 * sc
		var col := Color("ff3b3b")
		var pts := PackedVector2Array([
			sp + Vector2(0, -r), sp + Vector2(r * 0.9, r * 0.8), sp + Vector2(-r * 0.9, r * 0.8)
		])
		draw_colored_polygon(pts, col)
		draw_arc(sp, r + 3.0, 0.0, TAU, 18, Color(1, 0.4, 0.4, 0.5), 1.5, true)

func _draw_projectiles(cam: Vector2, center: Vector2, radius: float) -> void:
	for p in projectiles:
		var trail := p.trail(6, 0.7)
		var screen := PackedVector2Array()
		for w in trail:
			screen.append(_to_screen(cam, w, center, radius))
		var col := GameConfig.slot_color(p.owner_slot)
		draw_polyline(screen, Color(col, 0.8), 2.5, true)
		if screen.size() > 0:
			draw_circle(screen[0], 4.0 * _shrink(cam, p.pos()), Color.WHITE)

func _draw_players(cam: Vector2, center: Vector2, radius: float) -> void:
	var font := ThemeDB.fallback_font
	for pid in players:
		var pl: HPlayer = players[pid]
		var sp := _to_screen(cam, pl.hpos, center, radius)
		var sc := _shrink(cam, pl.hpos)
		var r := 13.0 * sc
		var body := pl.color if pl.alive else Color(pl.color, 0.35)
		draw_circle(sp, r, body)
		draw_arc(sp, r + 2.0, 0.0, TAU, 22, Color.WHITE, 2.0, true)
		# carried colour swatch
		draw_circle(sp, r * 0.45, GameConfig.node_color(pl.selected_color))
		# turret (only meaningful for the local, centred player)
		if pid == local_id and pl.alive:
			var tip := sp + Vector2(cos(pl.facing), sin(pl.facing)) * (r + 10.0)
			draw_line(sp, tip, Color.WHITE, 2.5, true)
		# name
		draw_string(font, sp + Vector2(-18, -r - 6), pl.pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))

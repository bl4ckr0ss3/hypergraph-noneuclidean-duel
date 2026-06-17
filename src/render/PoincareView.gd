class_name PoincareView
extends Node2D
## The World node: hyperbolic renderer + in-match state container + networking
## surface. Lives at /root/Main/World on both peers so its RPCs resolve.
##
## RENDERING (cute, soft, MapleStory-flavoured): everything is drawn in the
## Poincare-disk projection, camera = a Mobius recentre on the LOCAL player.
## Geodesics are drawn as EXACT circular arcs orthogonal to the unit circle
## (one draw_arc per edge) instead of sampled polylines -- this is both
## mathematically exact and ~10x cheaper, which is what keeps the framerate up.
##
## AUTHORITY: the host (peer 1) simulates enemies, resolves combat, owns node/
## gate/fragment/round state and broadcasts it. Clients send their own player
## state and request captures/collects; the host validates and echoes results.
## Remote players & enemies are position-interpolated (vpos) for smoothness.

const STATE_SEND_HZ := GameConfig.STATE_SEND_HZ
const SIM_HZ := GameConfig.SIM_HZ
const ENEMY_COUNT := 2
const INTERP_RATE := 14.0

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
var _anim := 0.0
var _fx: Array = []                     # transient effects: {pos,t,ttl,kind,color}
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
	tiling = HyperTiling.regular_tiling(7, 3, 2, 12)  # decorative; kept small for perf

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
		e.vpos = e.hpos
		e.current_node = sn
		enemies.append(e)

	projectiles.clear()
	_fx.clear()
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
	_fx.clear()
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
	_anim += delta
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
	_interpolate(delta)
	_age_fx(delta)
	queue_redraw()

func _interpolate(delta: float) -> void:
	var t := clampf(delta * INTERP_RATE, 0.0, 1.0)
	for pid in players:
		var pl: HPlayer = players[pid]
		if pid == local_id:
			pl.vpos = pl.hpos
		else:
			pl.vpos = pl.vpos.lerp(pl.hpos, t)
	for e in enemies:
		if is_host:
			e.vpos = e.hpos
		else:
			e.vpos = e.vpos.lerp(e.hpos, t)

func _view() -> Dictionary:
	var size := get_viewport_rect().size
	return { "center": size * 0.5, "radius": minf(size.x, size.y) * 0.46, "size": size }

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
	var alive_list: Array[Projectile] = []
	for p in projectiles:
		p.advance(delta)
		if p.alive:
			alive_list.append(p)
	projectiles = alive_list

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

	for e in enemies:
		if not e.alive:
			continue
		for pid in players:
			var pl: HPlayer = players[pid]
			if pl.alive and HyperMath.hdist(e.hpos, pl.hpos) < GameConfig.ENEMY_HIT_RANGE_H:
				_apply_hit(pid)

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
	_spawn_fx(pl.hpos, 2, pl.color)
	if pid != local_id:
		notify_hit.rpc_id(pid)

func _respawn_enemy(e: GraphHunter) -> void:
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
		1:
			newc = 0 if cur != 0 else 1
		2:
			newc = (cur + 1) % arena.k_colors if cur >= 0 else 0
		_:
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
		_spawn_fx(arena.graph.positions[node], 0, GameConfig.slot_color(owner_slot))

@rpc("authority", "reliable", "call_remote")
func apply_gate_state(gate_id: int, open: bool) -> void:
	if arena and gate_id >= 0 and gate_id < arena.gates.size():
		arena.gates[gate_id].is_open = open
		if open:
			_spawn_fx(arena.gates[gate_id].anchor, 1, Color("ffe9a8"))

@rpc("authority", "reliable", "call_remote")
func apply_fragment_collected(frag_id: int, slot: int) -> void:
	if arena and frag_id >= 0 and frag_id < arena.fragments.size():
		arena.fragments[frag_id].collected = true
		arena.fragments[frag_id].collected_by = slot
		_spawn_fx(arena.fragments[frag_id].pos, 1, GameConfig.FRAGMENT_COLOR)
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
		_spawn_fx(pl.hpos, 2, pl.color)

@rpc("authority", "reliable", "call_remote")
func declare_round_over(result: String) -> void:
	GameState.declare_over(result)

# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------
func _spawn_fx(world_pos: Vector2, kind: int, color: Color) -> void:
	_fx.append({ "pos": world_pos, "t": 0.0, "ttl": 0.7, "kind": kind, "color": color })

func _age_fx(delta: float) -> void:
	for f in _fx:
		f.t += delta
	_fx = _fx.filter(func(f): return f.t < f.ttl)

# ---------------------------------------------------------------------------
# HUD helper
# ---------------------------------------------------------------------------
func hud_hint() -> String:
	var pl := local_player()
	if pl == null:
		return ""
	if not pl.alive:
		return "oops! popping back in %.1fs" % maxf(0.0, pl.respawn_timer)
	var near := ""
	var best_d := INF
	for gate in arena.gates:
		var d := HyperMath.hdist(pl.hpos, gate.anchor)
		if d < best_d and d < 2.2:
			best_d = d
			near = "[%s] %s" % [gate.type_label(), ("OPEN!" if gate.is_open else gate.progress(node_color))]
	return near

# ===========================================================================
# Rendering
# ===========================================================================
func _draw() -> void:
	if arena == null:
		return
	var v := _view()
	var center: Vector2 = v["center"]
	var radius: float = v["radius"]
	var size: Vector2 = v["size"]
	var cam := _camera_center()

	_draw_sky(size)
	# soft disk "bubble world" with a gentle outer glow
	draw_circle(center, radius + 8.0, Color(GameConfig.DISK_EDGE_COLOR, 0.18))
	draw_circle(center, radius, GameConfig.DISK_FILL)
	_draw_tiling(cam, center, radius)
	draw_arc(center, radius, 0.0, TAU, 128, GameConfig.DISK_EDGE_COLOR, 5.0, true)
	_draw_edges(cam, center, radius)
	_draw_gates(cam, center, radius)
	_draw_nodes(cam, center, radius)
	_draw_fragments(cam, center, radius)
	_draw_fx(cam, center, radius, false)
	_draw_enemies(cam, center, radius)
	_draw_projectiles(cam, center, radius)
	_draw_players(cam, center, radius)
	_draw_fx(cam, center, radius, true)

# --- helpers ---------------------------------------------------------------
func _scr(cam: Vector2, world: Vector2, center: Vector2, radius: float) -> Vector2:
	var w := HyperMath.recenter(cam, world)
	return center + Vector2(w.x, -w.y) * radius

func _shrink(cam: Vector2, world: Vector2) -> float:
	var w := HyperMath.recenter(cam, world)
	return clampf(1.0 - w.length_squared(), 0.12, 1.0)

func _ellipse(c: Vector2, rx: float, ry: float, n: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

## Draw the exact geodesic between world points a,b as a circular arc orthogonal
## to the unit circle (or a straight chord through the centre). One draw_arc.
func _geo(cam: Vector2, a: Vector2, b: Vector2, center: Vector2, radius: float, color: Color, width: float, aa: bool) -> void:
	# recenter(cam, a) and recenter(cam, b) inlined to avoid per-call overhead
	# (this is the hottest path; ~150+ edges/frame). w = (z-cam)/(1 - conj(cam)*z).
	var er := 1.0 - (cam.x * a.x + cam.y * a.y)
	var ei := -(cam.x * a.y - cam.y * a.x)
	var den := er * er + ei * ei
	var ax := ((a.x - cam.x) * er + (a.y - cam.y) * ei) / den
	var ay := ((a.y - cam.y) * er - (a.x - cam.x) * ei) / den
	er = 1.0 - (cam.x * b.x + cam.y * b.y)
	ei = -(cam.x * b.y - cam.y * b.x)
	den = er * er + ei * ei
	var bx := ((b.x - cam.x) * er + (b.y - cam.y) * ei) / den
	var by := ((b.y - cam.y) * er - (b.x - cam.x) * ei) / den
	var sa := Vector2(center.x + ax * radius, center.y - ay * radius)
	var sb := Vector2(center.x + bx * radius, center.y - by * radius)
	var det := ax * by - ay * bx
	if absf(det) < 1e-4:
		draw_line(sa, sb, color, width, aa)
		return
	var ca := (1.0 + ax * ax + ay * ay) * 0.5
	var cb := (1.0 + bx * bx + by * by) * 0.5
	var ccx := (ca * by - cb * ay) / det
	var ccy := (ax * cb - bx * ca) / det
	var rs := sqrt((ax - ccx) * (ax - ccx) + (ay - ccy) * (ay - ccy)) * radius
	var cs := Vector2(center.x + ccx * radius, center.y - ccy * radius)
	var anga := atan2(-(ay - ccy), ax - ccx)
	var d := wrapf(atan2(-(by - ccy), bx - ccx) - anga, -PI, PI)
	var npts: int = clampi(int(absf(d) / 0.30) + 2, 2, 12)
	draw_arc(cs, rs, anga, anga + d, npts, color, width, aa)

func _draw_sky(size: Vector2) -> void:
	var quad := PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)])
	var cols := PackedColorArray([GameConfig.SKY_TOP, GameConfig.SKY_TOP, GameConfig.SKY_BOTTOM, GameConfig.SKY_BOTTOM])
	draw_polygon(quad, cols)
	# a few soft drifting clouds
	for i in range(3):
		var cx := fposmod(size.x * (0.2 + 0.3 * i) + _anim * (6.0 + i * 3.0), size.x + 160.0) - 80.0
		var cy := size.y * (0.12 + 0.1 * i)
		var cc := Color(1, 1, 1, 0.35)
		draw_circle(Vector2(cx, cy), 26, cc)
		draw_circle(Vector2(cx + 26, cy + 6), 20, cc)
		draw_circle(Vector2(cx - 24, cy + 6), 18, cc)

func _draw_tiling(cam: Vector2, center: Vector2, radius: float) -> void:
	for poly in tiling:
		var m: int = poly.size()
		for i in range(m):
			_geo(cam, poly[i], poly[(i + 1) % m], center, radius, GameConfig.BG_TILING_COLOR, 1.5, false)

func _draw_edges(cam: Vector2, center: Vector2, radius: float) -> void:
	for e in arena.graph.edges:
		_geo(cam, arena.graph.positions[e.x], arena.graph.positions[e.y], center, radius, GameConfig.GEODESIC_COLOR, 2.5, false)

func _draw_gates(cam: Vector2, center: Vector2, radius: float) -> void:
	var font := ThemeDB.fallback_font
	for gate in arena.gates:
		var col := Color("c3a6ff") if gate.type == Gate.Type.SAT else (Color("ffc785") if gate.type == Gate.Type.MODULAR else Color("9fe3c0"))
		for n in gate.nodes:
			var sp := _scr(cam, arena.graph.positions[n], center, radius)
			var sc := _shrink(cam, arena.graph.positions[n])
			draw_arc(sp, 15.0 * sc, 0.0, TAU, 22, Color(col, 0.9), 2.5, true)
		var ap := _scr(cam, gate.anchor, center, radius)
		var asc := _shrink(cam, gate.anchor)
		if gate.is_open:
			# sparkle ring
			draw_arc(ap, 20.0 * asc, 0.0, TAU, 24, Color(col, 0.4), 2.0, true)
			for k in range(5):
				var a := _anim * 2.0 + TAU * k / 5.0
				draw_circle(ap + Vector2(cos(a), sin(a)) * 18.0 * asc, 2.0 * asc, Color("fff3b0"))
		else:
			draw_circle(ap, 17.0 * asc, Color(col, 0.85))
			draw_circle(ap, 17.0 * asc * 0.6, Color(1, 1, 1, 0.35))
			# tiny padlock
			draw_arc(ap + Vector2(0, -3 * asc), 5.0 * asc, PI, TAU, 8, GameConfig.INK, 2.0, true)
			draw_rect(Rect2(ap + Vector2(-5, -1) * asc, Vector2(10, 9) * asc), GameConfig.INK, true)
			draw_string(font, ap + Vector2(-4, 6) * asc, gate.type_label().substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * asc), Color.WHITE)

func _draw_nodes(cam: Vector2, center: Vector2, radius: float) -> void:
	for i in range(arena.graph.node_count()):
		var pos: Vector2 = arena.graph.positions[i]
		var sp := _scr(cam, pos, center, radius)
		var sc := _shrink(cam, pos)
		var r := 10.0 * sc
		var col := GameConfig.NEUTRAL_COLOR
		if node_color[i] >= 0:
			col = GameConfig.node_color(node_color[i])
		# soft shadow + glossy bubble
		draw_circle(sp + Vector2(0, 1.5 * sc), r, Color(GameConfig.INK, 0.12))
		draw_circle(sp, r, col)
		var own_slot := node_owner[i]
		if own_slot >= 0:
			draw_arc(sp, r + 2.0, 0.0, TAU, 16, GameConfig.slot_color(own_slot), 2.5, false)
		draw_circle(sp + Vector2(-r * 0.35, -r * 0.35), r * 0.28, Color(1, 1, 1, 0.6))  # gloss
		var role := arena.node_role[i]
		if role == 1:
			draw_rect(Rect2(sp - Vector2(r, r) * 0.4, Vector2(r, r) * 0.8), Color(GameConfig.INK, 0.5), false, 1.5)
		elif role == 2:
			draw_arc(sp, r * 0.45, 0.0, TAU, 12, Color(GameConfig.INK, 0.5), 1.5, true)

func _draw_fragments(cam: Vector2, center: Vector2, radius: float) -> void:
	for f in arena.fragments:
		if f.collected:
			continue
		var avail := f.is_available(arena.gates)
		var bob := sin(_anim * 3.0 + f.id) * 3.0
		var sp := _scr(cam, f.pos, center, radius) + Vector2(0, bob)
		var sc := _shrink(cam, f.pos)
		if avail:
			# soft glow + bouncy heart
			draw_circle(sp, 14.0 * sc, Color(GameConfig.FRAGMENT_COLOR, 0.2))
			_draw_heart(sp, sc * (1.0 + 0.08 * sin(_anim * 5.0)), GameConfig.FRAGMENT_COLOR, 1.0)
		else:
			# caged: dim heart inside a soft bubble
			_draw_heart(sp, sc * 0.85, Color(0.7, 0.65, 0.72), 0.7)
			draw_arc(sp, 13.0 * sc, 0.0, TAU, 18, Color(0.55, 0.5, 0.6, 0.7), 1.5, true)

func _draw_heart(sp: Vector2, sc: float, col: Color, alpha: float) -> void:
	var s := 9.0 * sc
	var c := Color(col, alpha)
	draw_circle(sp + Vector2(-s * 0.45, -s * 0.25), s * 0.5, c)
	draw_circle(sp + Vector2(s * 0.45, -s * 0.25), s * 0.5, c)
	draw_colored_polygon(PackedVector2Array([sp + Vector2(-s * 0.9, 0), sp + Vector2(s * 0.9, 0), sp + Vector2(0, s)]), c)
	draw_circle(sp + Vector2(-s * 0.22, -s * 0.4), s * 0.13, Color(1, 1, 1, 0.7 * alpha))

func _draw_enemies(cam: Vector2, center: Vector2, radius: float) -> void:
	for e in enemies:
		if not e.alive:
			continue
		var sp := _scr(cam, e.vpos, center, radius)
		var sc := _shrink(cam, e.vpos)
		var s := 15.0 * sc
		var sq := 1.0 + 0.14 * sin(_anim * 6.0 + e.vpos.x * 0.1)
		var w := s / sq
		var h := s * sq
		draw_colored_polygon(_ellipse(sp + Vector2(0, s * 0.8), s * 0.7, s * 0.2, 12), Color(GameConfig.INK, 0.12))
		draw_colored_polygon(_ellipse(sp, w, h, 18), Color(GameConfig.ENEMY_COLOR, 0.92))
		# eyes
		draw_circle(sp + Vector2(-w * 0.3, -h * 0.12), s * 0.15, Color.WHITE)
		draw_circle(sp + Vector2(w * 0.3, -h * 0.12), s * 0.15, Color.WHITE)
		draw_circle(sp + Vector2(-w * 0.3, -h * 0.1), s * 0.07, GameConfig.INK)
		draw_circle(sp + Vector2(w * 0.3, -h * 0.1), s * 0.07, GameConfig.INK)
		draw_arc(sp + Vector2(0, h * 0.18), s * 0.13, PI * 0.15, PI * 0.85, 8, GameConfig.INK, 1.5, true)
		draw_circle(sp + Vector2(-w * 0.35, -h * 0.42), s * 0.1, Color(1, 1, 1, 0.5))  # shine

func _draw_projectiles(cam: Vector2, center: Vector2, radius: float) -> void:
	for p in projectiles:
		var col := GameConfig.slot_color(p.owner_slot)
		var head := _scr(cam, p.pos(), center, radius)
		var tail := _scr(cam, HyperMath.from_polar(p.origin, p.dir, maxf(0.0, p.s - 0.5)), center, radius)
		draw_line(tail, head, Color(col, 0.55), 3.0, true)
		var sc := _shrink(cam, p.pos())
		draw_circle(head, 5.0 * sc, Color.WHITE)
		draw_circle(head, 3.0 * sc, col)

func _draw_players(cam: Vector2, center: Vector2, radius: float) -> void:
	for pid in players:
		var pl: HPlayer = players[pid]
		var sp := _scr(cam, pl.vpos, center, radius)
		var sc := _shrink(cam, pl.vpos)
		_draw_character(sp, sc, pl.color, pl.facing, pid == local_id, pl.selected_color, pl.pname, pl.alive)

func _draw_character(sp: Vector2, sc: float, col: Color, facing: float, is_local: bool, sel: int, pname: String, alive: bool) -> void:
	var s := 16.0 * sc
	var a := 1.0 if alive else 0.4
	var bob := sin(_anim * 3.0 + sp.x * 0.05) * 1.5 * sc
	var o := sp + Vector2(0, bob)
	# shadow
	draw_colored_polygon(_ellipse(sp + Vector2(0, s * 0.95), s * 0.7, s * 0.22, 12), Color(GameConfig.INK, 0.12 * a))
	# soft halo
	draw_circle(o, s * 1.05, Color(col, 0.16 * a))
	# body
	draw_circle(o + Vector2(0, s * 0.55), s * 0.5, Color(col, a))
	# head
	var head := o + Vector2(0, -s * 0.15)
	draw_circle(head, s * 0.62, Color(GameConfig.SKIN, a))
	# hair band in slot colour
	draw_arc(head, s * 0.6, PI * 0.04, PI * 0.96, 16, Color(col, a), s * 0.3, true)
	# eyes (pupils follow aim)
	var look := Vector2(cos(facing), sin(facing)) * s * 0.1
	var eye_l := head + Vector2(-s * 0.24, s * 0.0)
	var eye_r := head + Vector2(s * 0.24, s * 0.0)
	draw_circle(eye_l, s * 0.17, Color(1, 1, 1, a))
	draw_circle(eye_r, s * 0.17, Color(1, 1, 1, a))
	draw_circle(eye_l + look, s * 0.09, Color(GameConfig.INK, a))
	draw_circle(eye_r + look, s * 0.09, Color(GameConfig.INK, a))
	draw_circle(eye_l + look + Vector2(-s * 0.03, -s * 0.03), s * 0.035, Color(1, 1, 1, a))
	draw_circle(eye_r + look + Vector2(-s * 0.03, -s * 0.03), s * 0.035, Color(1, 1, 1, a))
	# blush
	draw_circle(head + Vector2(-s * 0.36, s * 0.2), s * 0.1, Color(1, 0.55, 0.65, 0.5 * a))
	draw_circle(head + Vector2(s * 0.36, s * 0.2), s * 0.1, Color(1, 0.55, 0.65, 0.5 * a))
	# smile
	draw_arc(head + Vector2(0, s * 0.22), s * 0.14, PI * 0.15, PI * 0.85, 8, Color(GameConfig.INK, a), 2.0, true)
	# carried-colour balloon
	var gem := head + Vector2(s * 0.55, -s * 0.65)
	draw_line(head + Vector2(s * 0.25, -s * 0.45), gem, Color(GameConfig.INK, 0.45 * a), 1.5, true)
	draw_circle(gem, s * 0.2, Color(GameConfig.node_color(sel), a))
	draw_circle(gem + Vector2(-s * 0.06, -s * 0.06), s * 0.06, Color(1, 1, 1, 0.6 * a))
	# name
	if pname != "":
		var font := ThemeDB.fallback_font
		draw_string(font, sp + Vector2(-22, -s * 1.85), pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(GameConfig.INK, 0.9 * a))
	# local aim dot
	if is_local and alive:
		var aim := sp + Vector2(cos(facing), sin(facing)) * s * 1.6
		draw_circle(aim, 3.5 * sc, Color(col, 0.7))

func _draw_fx(cam: Vector2, center: Vector2, radius: float, over: bool) -> void:
	for f in _fx:
		var kind: int = f.kind
		# kinds 0 (capture, under) drawn in the under pass; 1,2 over
		if over == (kind == 0):
			continue
		var p: float = float(f.t) / float(f.ttl)
		var fpos: Vector2 = f.pos
		var sp := _scr(cam, fpos, center, radius)
		var sc := _shrink(cam, fpos)
		var col: Color = f.color
		match kind:
			0:  # capture ripple
				draw_arc(sp, (6.0 + 22.0 * p) * sc, 0.0, TAU, 20, Color(col, (1.0 - p) * 0.8), 3.0, true)
			1:  # collect / open burst — little rising hearts/sparkles
				for k in range(6):
					var ang := TAU * float(k) / 6.0
					var rr: float = (4.0 + 26.0 * p) * sc
					var pp: Vector2 = sp + Vector2(cos(ang), sin(ang)) * rr - Vector2(0.0, 10.0 * p * sc)
					draw_circle(pp, 3.0 * sc * (1.0 - p), Color(col, 1.0 - p))
			2:  # hit — pop stars
				for k in range(5):
					var ang2 := TAU * float(k) / 5.0 + _anim
					var rr2: float = (5.0 + 20.0 * p) * sc
					draw_circle(sp + Vector2(cos(ang2), sin(ang2)) * rr2, 2.5 * sc * (1.0 - p), Color(col, 1.0 - p))

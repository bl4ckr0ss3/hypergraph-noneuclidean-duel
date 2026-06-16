class_name GraphHunter
extends RefCounted
## Enemy that hunts along the arena graph. Each think-tick it picks the nearest
## player by hyperbolic distance, runs Dijkstra from its current node to the
## player's nearest node over hyperbolic edge weights, and then walks the path
## one edge at a time along geodesics. Because hyperbolic shortest paths tend to
## cut through the dense centre of the disk, the hunter takes routes that look
## like non-Euclidean shortcuts rather than straight Euclidean lines.
##
## Server-authoritative: only the host simulates; positions are broadcast.

var hpos: Vector2 = Vector2.ZERO
var current_node: int = 0
var target_node: int = -1
var chase_pos: Vector2 = Vector2.ZERO
var path: PackedInt32Array = PackedInt32Array()
var think_cd: float = 0.0
var alive: bool = true

## Re-plan toward the nearest player. `player_positions` is Array[Vector2].
func think(graph: Graph, player_positions: Array) -> void:
	var best := -1
	var best_d := INF
	for i in range(player_positions.size()):
		var d := HyperMath.hdist(hpos, player_positions[i])
		if d < best_d:
			best_d = d
			best = i
	if best == -1:
		return
	chase_pos = player_positions[best]
	current_node = graph.nearest_node(hpos)
	target_node = graph.nearest_node(chase_pos)
	path = graph.shortest_path(current_node, target_node)

func step(graph: Graph, dt: float) -> void:
	var dest: Vector2
	if path.size() >= 2:
		dest = graph.positions[path[1]]
	elif path.size() == 1 and HyperMath.hdist(hpos, graph.positions[path[0]]) > 0.1:
		dest = graph.positions[path[0]]
	else:
		dest = chase_pos  # fallback: bee-line along the geodesic toward the player

	var d := HyperMath.hdist(hpos, dest)
	if d < 0.09:
		hpos = dest
		if path.size() >= 2:
			current_node = path[1]
			path = path.slice(1)
		return
	# direction toward dest expressed in hpos's recentred frame
	var dir := HyperMath.recenter(hpos, dest)
	if dir.length_squared() < 1e-10:
		return
	hpos = HyperMath.move(hpos, dir.normalized(), GameConfig.ENEMY_SPEED * dt)

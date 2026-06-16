class_name Graph
extends RefCounted
## Undirected graph whose nodes live in the Poincare disk. Edge weights are the
## true hyperbolic distances between endpoints, so shortest paths follow the
## geometry (often "through the middle", which is the counter-intuitive feature
## the enemy AI exploits). Pathfinding is Dijkstra (V is small, so O(V^2) is fine
## and keeps the result deterministic across peers).

var positions: PackedVector2Array = PackedVector2Array()
var adj: Array = []            # adj[i] : Array[int]  neighbours of node i
var edges: Array[Vector2i] = []  # canonical (i<j) pairs, for rendering

func node_count() -> int:
	return positions.size()

func add_node(pos: Vector2) -> int:
	positions.append(pos)
	adj.append([])
	return positions.size() - 1

func has_edge(i: int, j: int) -> bool:
	return adj[i].has(j)

func add_edge(i: int, j: int) -> void:
	if i == j or has_edge(i, j):
		return
	adj[i].append(j)
	adj[j].append(i)
	edges.append(Vector2i(mini(i, j), maxi(i, j)))

func neighbors(i: int) -> Array:
	return adj[i]

func degree(i: int) -> int:
	return adj[i].size()

func edge_weight(i: int, j: int) -> float:
	return HyperMath.hdist(positions[i], positions[j])

func nearest_node(pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in range(positions.size()):
		var d := HyperMath.hdist(pos, positions[i])
		if d < best_d:
			best_d = d
			best = i
	return best

## Dijkstra from `src`. Returns { "dist": PackedFloat32Array, "prev": PackedInt32Array }.
func dijkstra(src: int) -> Dictionary:
	var n := node_count()
	var dist := PackedFloat32Array()
	var prev := PackedInt32Array()
	var visited := PackedByteArray()
	dist.resize(n)
	prev.resize(n)
	visited.resize(n)
	for i in range(n):
		dist[i] = INF
		prev[i] = -1
		visited[i] = 0
	dist[src] = 0.0
	for _step in range(n):
		# pick the unvisited node with the smallest tentative distance
		var u := -1
		var best := INF
		for i in range(n):
			if visited[i] == 0 and dist[i] < best:
				best = dist[i]
				u = i
		if u == -1:
			break
		visited[u] = 1
		for v in adj[u]:
			var nd: float = dist[u] + edge_weight(u, v)
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
	return { "dist": dist, "prev": prev }

## Shortest path (inclusive) from src to dst as a list of node indices, or empty.
func shortest_path(src: int, dst: int) -> PackedInt32Array:
	var r := dijkstra(src)
	var prev: PackedInt32Array = r["prev"]
	var path := PackedInt32Array()
	if src != dst and prev[dst] == -1:
		return path  # unreachable
	var cur := dst
	while cur != -1:
		path.append(cur)
		if cur == src:
			break
		cur = prev[cur]
	path.reverse()
	return path

## Quick connectivity check from node 0 (BFS).
## NOTE: not named is_connected() — that collides with Object.is_connected(signal, callable).
func is_fully_connected() -> bool:
	var n := node_count()
	if n == 0:
		return true
	var seen := PackedByteArray()
	seen.resize(n)
	var queue := [0]
	seen[0] = 1
	var count := 1
	while not queue.is_empty():
		var u: int = queue.pop_back()
		for v in adj[u]:
			if seen[v] == 0:
				seen[v] = 1
				count += 1
				queue.append(v)
	return count == n

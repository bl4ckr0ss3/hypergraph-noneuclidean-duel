class_name HyperTiling
extends RefCounted
## Generates a regular {p,q} tessellation of the Poincare disk for the arena
## *background grid* (purely visual; gameplay graph structure is separate).
##
## Method: build the central regular p-gon, then flood-fill outward by reflecting
## whole tiles across their edges. Reflection across a geodesic = inversion in the
## circle orthogonal to the unit circle through the edge's endpoints (or a line
## reflection when that geodesic is a diameter). Tiles are de-duplicated by a
## rounded centroid key. This is an APPROXIMATION: numerical drift accumulates a
## few layers out, but since it only draws the backdrop, small errors are cosmetic.
##
## Hyperbolic regularity requires 1/p + 1/q < 1/2.

## Returns Array[PackedVector2Array] — each entry is one tile's disk-space vertices.
static func regular_tiling(p: int, q: int, layers: int, max_tiles: int = 110) -> Array:
	var a := PI / float(p)
	var b := PI / float(q)
	if 1.0 / float(p) + 1.0 / float(q) >= 0.5:
		return []  # not a hyperbolic tiling
	var ratio := cos(a + b) / cos(a - b)
	if ratio <= 0.0:
		return []
	var r0 := sqrt(ratio)  # Euclidean circumradius of the central tile

	var center_poly := PackedVector2Array()
	for k in range(p):
		var ang := TAU * float(k) / float(p)
		center_poly.append(Vector2(cos(ang), sin(ang)) * r0)

	var result: Array = [center_poly]
	var seen := {}
	seen[_poly_key(center_poly)] = true
	var frontier: Array = [center_poly]

	for _layer in range(layers):
		var next_frontier: Array = []
		for poly in frontier:
			var n: int = poly.size()
			for i in range(n):
				var pa: Vector2 = poly[i]
				var pb: Vector2 = poly[(i + 1) % n]
				var refl := _reflect_polygon(poly, pa, pb)
				if refl.is_empty():
					continue
				var key := _poly_key(refl)
				if seen.has(key):
					continue
				seen[key] = true
				result.append(refl)
				next_frontier.append(refl)
				if result.size() >= max_tiles:
					return result
		frontier = next_frontier
	return result

# --- internals -------------------------------------------------------------
static func _reflect_polygon(poly: PackedVector2Array, pa: Vector2, pb: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		var r := _reflect_point(pa, pb, v)
		if is_nan(r.x) or is_nan(r.y) or r.length() >= 0.9995:
			return PackedVector2Array()  # drifted out of the disk; drop tile
		out.append(r)
	return out

## Reflect point P across the geodesic through disk points A and B.
static func _reflect_point(pa: Vector2, pb: Vector2, p: Vector2) -> Vector2:
	# Orthogonal-circle centre C solves  C.A = (1+|A|^2)/2 ,  C.B = (1+|B|^2)/2.
	var ca := (1.0 + pa.length_squared()) * 0.5
	var cb := (1.0 + pb.length_squared()) * 0.5
	var det := pa.x * pb.y - pa.y * pb.x
	if abs(det) < 1e-9:
		# A, B, origin collinear -> geodesic is a diameter; reflect across the line.
		var d := (pb - pa).normalized()
		var proj := d * p.dot(d)
		return 2.0 * proj - p
	var c := Vector2((ca * pb.y - cb * pa.y) / det, (pa.x * cb - pb.x * ca) / det)
	var r2 := c.distance_squared_to(pa)
	var diff := p - c
	var dl2 := diff.length_squared()
	if dl2 < 1e-12:
		return p
	return c + diff * (r2 / dl2)

static func _poly_key(poly: PackedVector2Array) -> String:
	var cx := 0.0
	var cy := 0.0
	for v in poly:
		cx += v.x
		cy += v.y
	var n := float(poly.size())
	return "%d,%d" % [roundi(cx / n * 600.0), roundi(cy / n * 600.0)]

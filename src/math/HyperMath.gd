class_name HyperMath
extends RefCounted
## Poincare-disk hyperbolic geometry. Points are Vector2 read as complex numbers
## z = x + i*y with |z| < 1. All identities here are validated numerically by
## tools/reference/verify.py (Mobius isometry, distance, geodesic sampling,
## in-disk movement) and ported 1:1 from that reference.
##
## Key maps (a, z, w are disk points; conj is complex conjugate):
##   recenter(a, z)     = (z - a) / (1 - conj(a)*z)        sends a -> 0  (isometry)
##   recenter_inv(a, w) = (w + a) / (1 + conj(a)*w)        inverse of the above
##   hdist(u, v)        = 2 * atanh(|recenter(u, v)|)       hyperbolic distance

const MAX_R := 0.99999  # keep strictly inside the open disk

# --- Complex helpers (Vector2 as complex) ---------------------------------
static func cmul(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)

static func cdiv(a: Vector2, b: Vector2) -> Vector2:
	var d := b.x * b.x + b.y * b.y
	if d < 1e-18:
		return Vector2.ZERO
	return Vector2((a.x * b.x + a.y * b.y) / d, (a.y * b.x - a.x * b.y) / d)

static func conj(a: Vector2) -> Vector2:
	return Vector2(a.x, -a.y)

static func atanh_safe(x: float) -> float:
	var c := clampf(x, -MAX_R, MAX_R)
	return 0.5 * log((1.0 + c) / (1.0 - c))

# --- Core hyperbolic maps --------------------------------------------------
## Mobius isometry sending `a` to the origin.
static func recenter(a: Vector2, z: Vector2) -> Vector2:
	var num := z - a
	var den := Vector2(1.0, 0.0) - cmul(conj(a), z)
	return cdiv(num, den)

## Inverse: sends the origin back to `a`.
static func recenter_inv(a: Vector2, w: Vector2) -> Vector2:
	var num := w + a
	var den := Vector2(1.0, 0.0) + cmul(conj(a), w)
	return cdiv(num, den)

## Hyperbolic distance between two disk points.
static func hdist(u: Vector2, v: Vector2) -> float:
	return 2.0 * atanh_safe(recenter(u, v).length())

## Keep a point strictly inside the open unit disk.
static func clamp_disk(z: Vector2, max_r: float = MAX_R) -> Vector2:
	var r := z.length()
	if r > max_r:
		return z * (max_r / r)
	return z

## Exponential map from `origin`: the point at hyperbolic arc length `s` along
## the geodesic leaving `origin` in (origin-frame) unit direction `dir`.
static func from_polar(origin: Vector2, dir: Vector2, s: float) -> Vector2:
	var d := dir.normalized()
	var w := d * tanh(s * 0.5)
	return clamp_disk(recenter_inv(origin, w))

## Move from `p` along the geodesic in (p-frame) screen direction `dir` by
## hyperbolic length `step`. Used for player/enemy locomotion.
static func move(p: Vector2, dir: Vector2, step: float) -> Vector2:
	if dir.length_squared() < 1e-12:
		return p
	return from_polar(p, dir, step)

## Point at arc-length fraction t in [0,1] along the geodesic u -> v.
static func geodesic_point(u: Vector2, v: Vector2, t: float) -> Vector2:
	var w := recenter(u, v)
	var r := w.length()
	if r < 1e-9:
		return u
	var rt := tanh(t * atanh_safe(r))
	return recenter_inv(u, (w / r) * rt)

## World-space polyline approximating the geodesic u -> v (n segments).
static func geodesic_samples(u: Vector2, v: Vector2, n: int = 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		pts.append(geodesic_point(u, v, float(i) / float(n)))
	return pts

# --- Camera mapping (disk world <-> screen pixels) -------------------------
## Project a world point to screen pixels, with the camera centred on `cam`.
## The camera is itself a Mobius recenter, so geodesics map to geodesics.
static func to_screen(cam: Vector2, world: Vector2, screen_center: Vector2, radius: float) -> Vector2:
	var w := recenter(cam, world)
	return screen_center + Vector2(w.x, -w.y) * radius

## Inverse of to_screen: screen pixels back to a world disk point.
static func from_screen(cam: Vector2, screen: Vector2, screen_center: Vector2, radius: float) -> Vector2:
	var w := (screen - screen_center) / radius
	w.y = -w.y
	return clamp_disk(recenter_inv(cam, clamp_disk(w)))

## Unit direction (in cam-frame) from the centred player toward a screen point.
## Equivalent to the direction you would travel/fire to reach that pixel.
static func aim_dir(screen_center: Vector2, screen_point: Vector2) -> Vector2:
	var d := screen_point - screen_center
	d.y = -d.y
	if d.length_squared() < 1e-9:
		return Vector2.RIGHT
	return d.normalized()

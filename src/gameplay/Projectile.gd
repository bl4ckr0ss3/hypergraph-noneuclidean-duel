class_name Projectile
extends RefCounted
## A "geodesic bolt". It travels along the hyperbolic geodesic leaving its origin
## in a fixed origin-frame direction; the world position at arc length s is the
## exponential map from_polar(origin, dir, s). No parallel transport needed, and
## the path renders as a curved arc in the disk projection.

var origin: Vector2 = Vector2.ZERO
var dir: Vector2 = Vector2.RIGHT   # unit, in origin frame
var s: float = 0.0                 # hyperbolic arc length travelled
var owner_slot: int = 0
var alive: bool = true

func pos() -> Vector2:
	return HyperMath.from_polar(origin, dir, s)

func advance(dt: float) -> void:
	s += GameConfig.PROJECTILE_SPEED * dt
	if s > GameConfig.PROJECTILE_RANGE:
		alive = false

## A few trailing world points behind the head, for drawing the curved tracer.
func trail(samples: int = 6, length: float = 0.7) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(samples + 1):
		var ss: float = maxf(0.0, s - length * float(i) / float(samples))
		pts.append(HyperMath.from_polar(origin, dir, ss))
	return pts

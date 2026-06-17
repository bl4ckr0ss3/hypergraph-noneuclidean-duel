class_name HPlayer
extends RefCounted
## Networked player state (data only; input/integration live in PoincareView).
## Position is a Poincare-disk point; each client renders with its OWN player at
## the disk centre, so this same world state looks correctly different to each.

var peer_id: int = 0
var slot: int = 0
var pname: String = "Player"
var color: Color = Color.WHITE
var hpos: Vector2 = Vector2.ZERO   # disk position (world frame, authoritative)
var vpos: Vector2 = Vector2.ZERO   # visual position (interpolated for remote players)
var facing: float = 0.0            # turret angle (screen radians) for drawing
var selected_color: int = 0        # paint-colour index the player currently holds
var alive: bool = true
var respawn_timer: float = 0.0
var fire_cd: float = 0.0

func spawn(pos: Vector2) -> void:
	hpos = pos
	vpos = pos
	alive = true
	respawn_timer = 0.0
	fire_cd = 0.0

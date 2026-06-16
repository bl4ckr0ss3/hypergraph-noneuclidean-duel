extends Node
## Global constants + runtime InputMap registration.
## Autoload singleton: `GameConfig`.
##
## Input actions are registered here (instead of in project.godot) so the repo
## stays free of hand-authored InputEvent sub-resources, which are verbose and
## error-prone to maintain by hand.

# --- Networking ------------------------------------------------------------
const DEFAULT_PORT := 24565
const MAX_PLAYERS := 2
const STATE_SEND_HZ := 30.0   # how often a client broadcasts its player state
const SIM_HZ := 30.0          # server simulation tick (enemies, gate checks)

# --- Hyperbolic gameplay tuning (all distances in hyperbolic length) -------
const PLAYER_SPEED := 1.6
const PLAYER_RADIUS_H := 0.14
const FIRE_COOLDOWN := 0.28
const PROJECTILE_SPEED := 3.2
const PROJECTILE_RANGE := 4.5
const CAPTURE_RANGE_H := 0.60
const INTERACT_RANGE_H := 0.60
const ENEMY_SPEED := 1.05
const ENEMY_THINK_INTERVAL := 0.5
const ENEMY_HIT_RANGE_H := 0.22
const RESPAWN_SECONDS := 2.5

# --- Match defaults --------------------------------------------------------
const ROUND_SECONDS := 240.0
const FRAGMENT_TARGET := 5

# --- Palette ---------------------------------------------------------------
const SLOT_COLORS := [Color("39d0d8"), Color("ff5c8a")]            # P1 teal, P2 pink
const NODE_PALETTE := [Color("e84545"), Color("f9c74f"), Color("43aa8b"), Color("577590")]
const NEUTRAL_COLOR := Color("2c3242")
const DISK_EDGE_COLOR := Color("39d0d8")
const BG_TILING_COLOR := Color(0.49, 0.40, 1.0, 0.16)
const GEODESIC_COLOR := Color(0.55, 0.62, 0.78, 0.55)

func _ready() -> void:
	_register_actions()

func slot_color(slot: int) -> Color:
	if slot >= 0 and slot < SLOT_COLORS.size():
		return SLOT_COLORS[slot]
	return Color.WHITE

func node_color(idx: int) -> Color:
	if idx >= 0 and idx < NODE_PALETTE.size():
		return NODE_PALETTE[idx]
	return NEUTRAL_COLOR

# --- Input registration ----------------------------------------------------
func _key(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	return e

func _mb(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e

func _bind(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in events:
		InputMap.action_add_event(action, ev)

func _register_actions() -> void:
	_bind("move_up",     [_key(KEY_W), _key(KEY_UP)])
	_bind("move_down",   [_key(KEY_S), _key(KEY_DOWN)])
	_bind("move_left",   [_key(KEY_A), _key(KEY_LEFT)])
	_bind("move_right",  [_key(KEY_D), _key(KEY_RIGHT)])
	_bind("fire",        [_mb(MOUSE_BUTTON_LEFT)])
	_bind("interact",    [_key(KEY_E), _key(KEY_SPACE)])
	_bind("cycle_color", [_key(KEY_Q)])
	_bind("toggle_debug",[_key(KEY_F3)])
	_bind("cancel",      [_key(KEY_ESCAPE)])
	Log.info("Input actions registered")

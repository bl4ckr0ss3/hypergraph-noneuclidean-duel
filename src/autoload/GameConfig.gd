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

# --- Palette (soft, cute MapleStory-style pastel) --------------------------
const SLOT_COLORS := [Color("4fc8c0"), Color("ff9ec7")]           # P1 mint, P2 pink
const NODE_PALETTE := [Color("ff9aa2"), Color("ffd59e"), Color("a8e6cf"), Color("a0c4ff")]  # coral, peach, mint, sky
const NEUTRAL_COLOR := Color("efe9f7")        # soft lavender-white bubble
const DISK_EDGE_COLOR := Color("c9b6ff")      # soft purple ring
const BG_TILING_COLOR := Color(0.64, 0.56, 0.86, 0.22)
const GEODESIC_COLOR := Color(0.74, 0.68, 0.86, 0.55)
# cute-theme additions
const SKY_TOP := Color("c3e8ff")              # background gradient (top)
const SKY_BOTTOM := Color("ffdcec")           # background gradient (bottom)
const DISK_FILL := Color("fff7fb")            # cream disk interior
const INK := Color("7a6e8c")                  # soft outline (never pure black)
const SKIN := Color("ffe2c6")                 # character face
const FRAGMENT_COLOR := Color("ff8fab")       # cute heart (pink)
const ENEMY_COLOR := Color("9be59b")          # cute slime (green)

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

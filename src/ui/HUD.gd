class_name HUD
extends Control
## In-match heads-up display: scores, round timer, objective, contextual gate
## hint, controls, transient flash messages, and the round-over panel. Reads
## GameState + the World node; built in code.

var world: PoincareView = null

var score1: Label
var score2: Label
var timer_label: Label
var objective_label: Label
var hint_label: Label
var flash_label: Label
var result_panel: CenterContainer
var result_title: Label

var _flash_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# top bar
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	score1 = _mk_label(26, GameConfig.slot_color(0))
	score1.text = "P1  0"
	top.add_child(score1)

	top.add_child(_expand())

	var cv := VBoxContainer.new()
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(cv)
	timer_label = _mk_label(28, Color.WHITE)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.text = "04:00"
	cv.add_child(timer_label)
	objective_label = _mk_label(14, Color(0.75, 0.8, 0.9))
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(objective_label)

	top.add_child(_expand())

	score2 = _mk_label(26, GameConfig.slot_color(1))
	score2.text = "0  P2"
	top.add_child(score2)

	# bottom bar
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_bottom = -10
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var controls := _mk_label(12, Color(0.6, 0.65, 0.75))
	controls.text = "WASD move   |   Mouse aim + LMB fire   |   Q cycle colour   |   E capture/collect   |   F3 debug   |   Esc leave"
	bottom.add_child(controls)
	bottom.add_child(_expand())
	hint_label = _mk_label(14, GameConfig.DISK_EDGE_COLOR)
	bottom.add_child(hint_label)

	# flash message
	flash_label = _mk_label(20, Color("ffd166"))
	flash_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	flash_label.offset_top = 64
	flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_label)

	# round-over panel
	result_panel = CenterContainer.new()
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.visible = false
	add_child(result_panel)
	var rp := PanelContainer.new()
	result_panel.add_child(rp)
	var rm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		rm.add_theme_constant_override("margin_" + side, 28)
	rp.add_child(rm)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 14)
	rm.add_child(rv)
	result_title = _mk_label(30, GameConfig.DISK_EDGE_COLOR)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(result_title)
	var btn := Button.new()
	btn.text = "Return to menu"
	btn.pressed.connect(func(): Net.leave())
	rv.add_child(btn)

	visible = false

func _mk_label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _expand() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func on_match_started() -> void:
	result_panel.visible = false
	flash_label.text = ""
	_flash_t = 0.0

func flash(msg: String) -> void:
	flash_label.text = msg
	_flash_t = 3.0

func show_result(result: String) -> void:
	result_title.text = result
	result_panel.visible = true

func _process(delta: float) -> void:
	if not visible:
		return
	var s := int(GameState.seconds_left)
	timer_label.text = "%02d:%02d" % [s / 60, s % 60]
	score1.text = "P1  %d" % int(GameState.scores.get(0, 0))
	score2.text = "%d  P2" % int(GameState.scores.get(1, 0))
	if GameState.mode == GameState.Mode.CO_OP:
		objective_label.text = "CO-OP   %d / %d proof fragments" % [GameState.team_total, GameState.fragment_target]
	else:
		objective_label.text = "DUEL   first to %d fragments" % GameState.fragment_target

	if world and world.arena and GameState.state == GameState.S.PLAYING:
		hint_label.text = world.hud_hint()
	else:
		hint_label.text = ""

	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			flash_label.text = ""

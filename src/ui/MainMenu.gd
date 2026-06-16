class_name MainMenu
extends Control
## Host/Join entry screen + pre-match lobby. Talks to the Net singleton only;
## Main reacts to Net.start_match to leave the menu. Built entirely in code.

const ACCENT := Color("39d0d8")

var entry_panel: VBoxContainer
var lobby_panel: VBoxContainer
var name_edit: LineEdit
var ip_edit: LineEdit
var status_label: Label
var roster_label: Label
var mode_option: OptionButton
var start_button: Button
var lobby_info: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("0a0e14")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 0)
	center.add_child(card)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	card.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "HYPERGRAPH"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Non-Euclidean Duel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	root.add_child(subtitle)

	root.add_child(HSeparator.new())

	# --- entry panel -------------------------------------------------------
	entry_panel = VBoxContainer.new()
	entry_panel.add_theme_constant_override("separation", 8)
	root.add_child(entry_panel)

	entry_panel.add_child(_label("Callsign"))
	name_edit = LineEdit.new()
	name_edit.text = "Player"
	entry_panel.add_child(name_edit)

	var host_btn := Button.new()
	host_btn.text = "HOST LAN GAME"
	host_btn.pressed.connect(_on_host_pressed)
	entry_panel.add_child(host_btn)

	entry_panel.add_child(_label("Host IP address"))
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	entry_panel.add_child(ip_edit)

	var join_btn := Button.new()
	join_btn.text = "JOIN BY IP"
	join_btn.pressed.connect(_on_join_pressed)
	entry_panel.add_child(join_btn)

	var port_hint := _label("Port %d  -  share your LAN IPv4 with your friend" % GameConfig.DEFAULT_PORT)
	port_hint.add_theme_font_size_override("font_size", 11)
	entry_panel.add_child(port_hint)

	# --- lobby panel -------------------------------------------------------
	lobby_panel = VBoxContainer.new()
	lobby_panel.add_theme_constant_override("separation", 8)
	root.add_child(lobby_panel)

	lobby_info = _label("LOBBY")
	lobby_info.add_theme_font_size_override("font_size", 18)
	lobby_panel.add_child(lobby_info)

	roster_label = Label.new()
	roster_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	lobby_panel.add_child(roster_label)

	lobby_panel.add_child(_label("Mode (host decides)"))
	mode_option = OptionButton.new()
	mode_option.add_item("Co-op  -  shared fragment target", GameState.Mode.CO_OP)
	mode_option.add_item("Duel  -  race to the target", GameState.Mode.DUEL)
	mode_option.selected = 0
	lobby_panel.add_child(mode_option)

	start_button = Button.new()
	start_button.text = "START MATCH"
	start_button.pressed.connect(_on_start_pressed)
	lobby_panel.add_child(start_button)

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.pressed.connect(_on_leave_pressed)
	lobby_panel.add_child(leave_btn)

	root.add_child(HSeparator.new())
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color("ff8a5c"))
	root.add_child(status_label)

	Net.lobby_changed.connect(_refresh_lobby)
	show_entry()

func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	return l

func show_entry() -> void:
	visible = true
	entry_panel.visible = true
	lobby_panel.visible = false

func show_lobby() -> void:
	entry_panel.visible = false
	lobby_panel.visible = true
	_refresh_lobby()

func set_status(t: String) -> void:
	if status_label:
		status_label.text = t

func _refresh_lobby() -> void:
	if not lobby_panel.visible:
		return
	var lines: Array[String] = []
	var slots := {}
	for pid in Net.roster:
		slots[int(Net.roster[pid]["slot"])] = str(Net.roster[pid]["name"])
	for s in [0, 1]:
		var who: String = slots.get(s, "(waiting...)")
		lines.append("P%d:  %s" % [s + 1, who])
	roster_label.text = "\n".join(lines)

	var ready := Net.roster.size() >= 2
	if Net.is_host:
		lobby_info.text = "LOBBY  -  you are HOST"
		mode_option.disabled = false
		start_button.visible = true
		start_button.disabled = not ready
		set_status("" if ready else "Waiting for a second player to join...")
	else:
		lobby_info.text = "LOBBY  -  connected"
		mode_option.disabled = true
		start_button.visible = false
		set_status("Waiting for host to start the match...")

func _on_host_pressed() -> void:
	if Net.host_game(GameConfig.DEFAULT_PORT, name_edit.text.strip_edges()):
		show_lobby()
	else:
		set_status("Could not host (port %d busy?)" % GameConfig.DEFAULT_PORT)

func _on_join_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		set_status("Enter the host's IP first")
		return
	if Net.join_game(ip, GameConfig.DEFAULT_PORT, name_edit.text.strip_edges()):
		show_lobby()
		set_status("Connecting to %s ..." % ip)
	else:
		set_status("Invalid address")

func _on_start_pressed() -> void:
	Net.host_start_match(mode_option.get_selected_id())

func _on_leave_pressed() -> void:
	Net.leave()
	show_entry()
	set_status("")

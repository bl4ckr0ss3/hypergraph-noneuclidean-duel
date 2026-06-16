extends Node2D
## Top-level orchestrator (the main scene at /root/Main). Builds the node tree in
## code so the repo carries only one tiny .tscn, wires Net + GameState signals to
## the UI and World, and routes between MENU / LOBBY / PLAYING / ROUND_OVER.

var world: PoincareView     # at /root/Main/World
var ui_layer: CanvasLayer
var menu: MainMenu
var hud: HUD
var debug: DebugOverlay

func _ready() -> void:
	world = PoincareView.new()
	world.name = "World"
	add_child(world)

	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	menu = MainMenu.new()
	menu.name = "MainMenu"
	ui_layer.add_child(menu)

	hud = HUD.new()
	hud.name = "HUD"
	ui_layer.add_child(hud)

	debug = DebugOverlay.new()
	debug.name = "Debug"
	ui_layer.add_child(debug)

	hud.world = world
	debug.world = world

	Net.start_match.connect(_on_start_match)
	Net.returned_to_menu.connect(_on_return_menu)
	Net.connection_failed_signal.connect(_on_conn_failed)
	Net.server_disconnected_signal.connect(_on_server_left)
	Net.peer_left.connect(_on_peer_left)
	GameState.round_over.connect(_on_round_over)

	_show_menu()

func _show_menu() -> void:
	GameState.set_state(GameState.S.MENU)
	hud.visible = false
	menu.visible = true
	menu.show_entry()

func _on_start_match(world_seed: int, roster: Dictionary, mode: int) -> void:
	menu.visible = false
	hud.visible = true
	world.build(world_seed, roster, mode)
	hud.on_match_started()

func _on_return_menu() -> void:
	world.teardown()
	_show_menu()

func _on_conn_failed() -> void:
	hud.visible = false
	menu.visible = true
	menu.show_entry()
	menu.set_status("Connection failed - is the host up?")

func _on_server_left() -> void:
	world.teardown()
	GameState.set_state(GameState.S.MENU)
	hud.visible = false
	menu.visible = true
	menu.show_entry()
	menu.set_status("Server disconnected")

func _on_peer_left(_id: int) -> void:
	if GameState.state == GameState.S.PLAYING:
		hud.flash("Opponent disconnected")
		if Net.is_host:
			world._end_round("OPPONENT LEFT")

func _on_round_over(result: String) -> void:
	hud.show_result(result)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		debug.toggle()
	elif event.is_action_pressed("cancel"):
		if GameState.state != GameState.S.MENU:
			Net.leave()

extends Node
## LAN networking: host/join, seed + roster handshake, disconnect handling.
## Autoload singleton: `Net`.
##
## This singleton owns only the *connection lifecycle* and the pre-match
## handshake. In-match state (player positions, captures, gates, enemies,
## round snapshot) is synchronised by the World node (PoincareView), whose
## node path `/root/Main/World` is identical on both peers so RPCs resolve.
##
## Topology: Godot's ENet is client/server. The host is peer id 1 and is also
## a player. With MAX_PLAYERS == 2 the single client is connected directly to
## the host, so a broadcast rpc() from either side reaches the other with no
## relay. 3+ players would require the server to relay, which is out of scope.

signal lobby_changed
signal peer_left(id: int)
signal connection_failed_signal
signal server_disconnected_signal
signal start_match(world_seed: int, roster: Dictionary, mode: int)
signal returned_to_menu

var is_host := false
var match_seed := 0
var local_name := "Player"
# roster: { peer_id:int -> { "slot":int, "name":String } }
var roster: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func get_local_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()

func get_slot(peer_id: int) -> int:
	if roster.has(peer_id):
		return int(roster[peer_id]["slot"])
	return -1

func local_slot() -> int:
	return get_slot(get_local_id())

# --- Lifecycle -------------------------------------------------------------
func host_game(port: int = GameConfig.DEFAULT_PORT, player_name := "Host") -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, GameConfig.MAX_PLAYERS)
	if err != OK:
		Log.error("Host failed on port %d (err %d)" % [port, err])
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	local_name = player_name
	match_seed = int(randi())  # host picks the shared world seed once
	roster = { 1: { "slot": 0, "name": player_name } }
	Log.net("Hosting on port %d, seed=%d" % [port, match_seed])
	lobby_changed.emit()
	return true

func join_game(ip: String, port: int = GameConfig.DEFAULT_PORT, player_name := "Guest") -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		Log.error("Join failed to %s:%d (err %d)" % [ip, port, err])
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	local_name = player_name
	Log.net("Connecting to %s:%d ..." % [ip, port])
	return true

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_host = false
	roster.clear()
	returned_to_menu.emit()
	Log.net("Disconnected / returned to menu")

## Host-only: begin the match for everyone. Called from the lobby UI.
func host_start_match(mode: int) -> void:
	if not is_host:
		return
	start_match.emit(match_seed, roster, mode)
	_client_start_match.rpc(match_seed, roster, mode)

# --- Host-side signal handlers --------------------------------------------
func _on_peer_connected(id: int) -> void:
	if not is_host:
		return
	var used := {}
	for pid in roster:
		used[int(roster[pid]["slot"])] = true
	var slot := 0
	while used.has(slot):
		slot += 1
	roster[id] = { "slot": slot, "name": "Guest" }
	Log.net("Peer %d connected -> slot %d" % [id, slot])
	_client_receive_setup.rpc_id(id, match_seed, roster)
	lobby_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	Log.net("Peer %d disconnected" % id)
	roster.erase(id)
	if is_host:
		_client_update_roster.rpc(roster)
	lobby_changed.emit()
	peer_left.emit(id)

# --- Client-side signal handlers ------------------------------------------
func _on_connected_to_server() -> void:
	Log.net("Connected as id %d" % multiplayer.get_unique_id())
	_host_register_name.rpc_id(1, local_name)

func _on_connection_failed() -> void:
	Log.error("Connection failed")
	multiplayer.multiplayer_peer = null
	connection_failed_signal.emit()

func _on_server_disconnected() -> void:
	Log.warn("Server disconnected")
	multiplayer.multiplayer_peer = null
	roster.clear()
	server_disconnected_signal.emit()

# --- RPCs ------------------------------------------------------------------
@rpc("any_peer", "reliable")
func _host_register_name(pname: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id):
		roster[id]["name"] = pname
		lobby_changed.emit()
		_client_update_roster.rpc(roster)

@rpc("authority", "reliable")
func _client_receive_setup(world_seed: int, r: Dictionary) -> void:
	match_seed = world_seed
	roster = r
	lobby_changed.emit()

@rpc("authority", "reliable")
func _client_update_roster(r: Dictionary) -> void:
	roster = r
	lobby_changed.emit()

@rpc("authority", "reliable")
func _client_start_match(world_seed: int, r: Dictionary, mode: int) -> void:
	match_seed = world_seed
	roster = r
	start_match.emit(world_seed, r, mode)

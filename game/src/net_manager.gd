extends Node

const PLAYER_SCENE: PackedScene = preload("res://player.tscn")
const PLAYER_SCRIPT := preload("res://src/char_controller.gd")
const DEFAULT_IP := "127.0.0.1"
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 6

var _peer: ENetMultiplayerPeer = null
var _dump := false
var _dump_t := 0.0

var _ip_edit: LineEdit
var _port_edit: LineEdit
var _status: Label
var _roster: Label

@onready var _players: Node3D = get_parent().get_node("Players")
@onready var _spawns: Node3D = get_parent().get_node("SpawnPoints")


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_build_ui()
	_set_status("Single-player preview. Host to play, Join to connect.")
	_dump = "--dump" in OS.get_cmdline_user_args()
	_handle_cmdline_args()


func _process(delta: float) -> void:
	if not _dump:
		return
	_dump_t += delta
	if _dump_t >= 5.0:
		_dump_t = 0.0
		var parts: Array[String] = []
		for c in _players.get_children():
			var b := c as Node3D
			var sync := c.get_node_or_null("MultiplayerSynchronizer")
			parts.append("%s@%s auth=%d sync_auth=%d carried=%s" % [c.name, str(b.position) if b != null else "?", c.get_multiplayer_authority(), sync.get_multiplayer_authority() if sync != null else -1, _carried_name(int(c.name))])
		print("[Net] tree: ", (", ".join(PackedStringArray(parts)) if not parts.is_empty() else "(empty)"))


func _handle_cmdline_args() -> void:
	var args := OS.get_cmdline_user_args()
	if "--host" in args:
		var i := args.find("--host")
		if i + 1 < args.size() and args[i + 1].is_valid_int():
			_port_edit.text = args[i + 1]
		_on_host_pressed.call_deferred()
	elif "--join" in args:
		var j := args.find("--join")
		if j + 1 < args.size():
			_ip_edit.text = args[j + 1]
		if j + 2 < args.size() and args[j + 2].is_valid_int():
			_port_edit.text = args[j + 2]
		_on_join_pressed.call_deferred()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NetUI"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	panel.modulate = Color(1, 1, 1, 0.92)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.text = DEFAULT_IP
	_ip_edit.custom_minimum_size = Vector2(140, 0)
	_ip_edit.tooltip_text = "Host IP"
	row.add_child(_ip_edit)
	_port_edit = LineEdit.new()
	_port_edit.text = str(DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(70, 0)
	_port_edit.tooltip_text = "Port"
	row.add_child(_port_edit)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	box.add_child(btns)
	var host_btn := Button.new()
	host_btn.text = "Host"
	host_btn.pressed.connect(_on_host_pressed)
	btns.add_child(host_btn)
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(_on_join_pressed)
	btns.add_child(join_btn)
	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.pressed.connect(_on_leave_pressed)
	btns.add_child(leave_btn)

	_status = Label.new()
	_status.text = "..."
	box.add_child(_status)
	_roster = Label.new()
	_roster.text = ""
	box.add_child(_roster)


func _port() -> int:
	var p := int(_port_edit.text) if _port_edit.text.is_valid_int() else DEFAULT_PORT
	return clampi(p, 1024, 65535)


func _on_host_pressed() -> void:
	if _peer != null:
		_set_status("Already in a session. Leave first.")
		return
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(_port(), MAX_PLAYERS)
	if err != OK:
		_set_status("Host failed: %s" % err)
		_peer = null
		return
	multiplayer.multiplayer_peer = _peer
	_spawn_player(multiplayer.get_unique_id())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_status("Hosting on port %d. (LAN IP in terminal: ip addr)" % _port())
	_refresh_roster()


func _on_join_pressed() -> void:
	if _peer != null:
		_set_status("Already in a session. Leave first.")
		return
	var ip := _ip_edit.text.strip_edges()
	if ip.is_empty():
		_set_status("Enter a host IP first.")
		return
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, _port())
	if err != OK:
		_set_status("Join failed: %s" % err)
		_peer = null
		return
	multiplayer.multiplayer_peer = _peer
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_status("Connecting to %s:%d ..." % [ip, _port()])


func _on_leave_pressed() -> void:
	_clear_session()
	_set_status("Left session.")


func _clear_session() -> void:
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	for c in _players.get_children():
		_players.remove_child(c)
		c.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_roster()


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(peer_id)
		_refresh_roster()


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		_reclaim_carried(peer_id)
		_despawn_player(peer_id)
		_refresh_roster()


func _reclaim_carried(peer_id: int) -> void:
	for n in get_tree().get_nodes_in_group("grabbables"):
		var g := n as Grabbable
		if g != null and g.carrier_id == peer_id:
			print("[Net] reclaiming ", g.name, " from departed peer ", peer_id)
			g.reset_to_origin()


func _on_connected_to_server() -> void:
	_set_status("Connected! Spawning you ...")
	_refresh_roster()


func _on_connection_failed() -> void:
	_set_status("Connection failed. Check IP/port.")
	_clear_session()


func _on_server_disconnected() -> void:
	# Host left -> session over
	_set_status("Host left. Session ended.")
	_clear_session()


func _spawn_player(peer_id: int) -> void:
	if _players.has_node(str(peer_id)):
		return
	var p := PLAYER_SCENE.instantiate() as CharacterBody3D
	p.name = str(peer_id)
	p.set_multiplayer_authority(peer_id)
	p.position = PLAYER_SCRIPT.spawn_position_for(peer_id, _spawns.get_children())
	_players.add_child(p, true)
	print("[Net] spawned player ", peer_id, " at ", p.position)
	_refresh_roster()


func _despawn_player(peer_id: int) -> void:
	var n := _players.get_node_or_null(str(peer_id))
	if n != null:
		_players.remove_child(n)
		n.queue_free()


func _carried_name(peer_id: int) -> String:
	for n in get_tree().get_nodes_in_group("grabbables"):
		var g := n as Grabbable
		if g != null and g.carrier_id == peer_id:
			return g.name
	return "-"


func _set_status(s: String) -> void:
	print("[Net] ", s)
	if _status != null:
		_status.text = s


func _refresh_roster() -> void:
	if _roster == null:
		return
	var names: Array[String] = []
	for c in _players.get_children():
		names.append(c.name)
	_roster.text = "Players: " + (", ".join(PackedStringArray(names)) if not names.is_empty() else "-")

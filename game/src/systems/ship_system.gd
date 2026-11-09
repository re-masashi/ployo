class_name ShipSystem
extends StaticBody3D

signal failed(system: ShipSystem)
signal repaired(system: ShipSystem)

enum SState { OK, FAILED }

@export var system_id := "engine"
@export var display_name := "ENGINE"
@export var fail_after := 120.0
@export var repair_time := 3.0
@export var critical := true
@export var size := Vector3(1.3, 1.5, 0.9)
@export var accent := Color(0.9, 0.5, 0.15)
@export var start_failed := false

var state: SState = SState.OK
var _fail_t := 0.0
var _progress := 0.0
var _repairer: Node3D = null
var _mesh: MeshInstance3D
var _label: Label3D
var _light: OmniLight3D
var _mat: StandardMaterial3D
var _last_sync := 0.0
var _state_sync_t := 0.0
var _fail_flash_t := 0.0
var _synced_label := ""


func _ready() -> void:
	add_to_group("ship_systems")
	_build_visuals()
	_fail_t = fail_after * randf_range(0.65, 1.35)
	if start_failed:
		state = SState.FAILED
	_refresh_local()


func _server() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _build_visuals() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	var bm := BoxMesh.new()
	bm.size = size
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = accent
	_mat.roughness = 0.7
	bm.material = _mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = bm
	add_child(_mesh)

	var pipe := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = size.y * 0.9
	pipe.mesh = cm
	pipe.position = Vector3(size.x * 0.42, 0.0, 0.0)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.5, 0.52, 0.55)
	metal.metallic = 0.8
	metal.roughness = 0.3
	pipe.material_override = metal
	add_child(pipe)

	_label = ProximityLabel.new()
	_label.position = Vector3(0.0, size.y * 0.5 + 0.55, 0.0)
	_label.pixel_size = 0.01
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	add_child(_label)

	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, size.y * 0.5 + 0.2, 0.0)
	_light.light_color = Color(1.0, 0.16, 0.1)
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	add_child(_light)


func _physics_process(delta: float) -> void:
	if _fail_flash_t > 0.0:
		_fail_flash_t = maxf(0.0, _fail_flash_t - delta)
		_refresh_local()
	if not _server():
		return
	_state_sync_t += delta
	if _state_sync_t >= 1.0:
		_state_sync_t = 0.0
		_broadcast()
	if state == SState.OK:
		_fail_t -= delta
		if _fail_t <= 0.0:
			_fail()
		return
	if _repairer == null:
		return
	if not _repairer_valid():
		_cancel_repair()
		return
	_progress += delta
	_sync_progress()
	if _progress >= repair_time:
		_repair()


func _repairer_valid() -> bool:
	if not is_instance_valid(_repairer):
		return false
	if _repairer.has_method("is_down") and _repairer.is_down():
		return false
	if _repairer.has_method("is_carrying") and _repairer.is_carrying():
		return false
	return global_position.distance_to(_repairer.global_position) < 3.2


func _fail() -> void:
	state = SState.FAILED
	_progress = 0.0
	_repairer = null
	NoiseBus.emit_noise(global_position, 1.6, self)
	print("[Ship] %s failed" % display_name)
	_broadcast()
	failed.emit(self)


func _repair() -> void:
	state = SState.OK
	_progress = 0.0
	_repairer = null
	_fail_t = fail_after * randf_range(0.7, 1.4)
	NoiseBus.emit_noise(global_position, 0.5, self)
	print("[Ship] %s repaired" % display_name)
	_broadcast()
	repaired.emit(self)


func _cancel_repair() -> void:
	if _repairer != null:
		_stop_repair(_repairer, true)
	else:
		_progress = 0.0
		_broadcast()


func interact(player: Node3D) -> void:
	interact_begin(player)


func interact_begin(player: Node3D) -> void:
	if state == SState.OK:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_repair.rpc_id(1, player.get_path())
		return
	_start_repair(player)


func interact_hold(_player: Node3D, _delta: float) -> void:
	pass


func wants_hold() -> bool:
	return state == SState.FAILED


func hold_progress() -> float:
	return clampf(_progress / maxf(repair_time, 0.01), 0.0, 1.0)


func hold_text() -> String:
	return "%s - HOLD E" % display_name


func interact_end(player: Node3D, failed: bool = true) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_stop_repair.rpc_id(1, player.get_path(), failed)
		return
	_stop_repair(player, failed)


@rpc("any_peer")
func _request_stop_repair(player_path: String, failed: bool) -> void:
	if not multiplayer.is_server():
		return
	var p := get_node_or_null(player_path) as Node3D
	if p == null:
		return
	_stop_repair(p, failed)


func _stop_repair(player: Node3D, failed: bool) -> void:
	if _repairer != player:
		return
	var had_progress := _progress > 0.01
	_repairer = null
	_progress = 0.0
	if failed and had_progress:
		_fail_flash_t = 1.4
		NoiseBus.emit_noise(global_position, 0.7, self)
		print("[Ship] %s repair failed" % display_name)
	_broadcast()


@rpc("any_peer")
func _request_repair(player_path: String) -> void:
	if not multiplayer.is_server():
		return
	var p := get_node_or_null(player_path) as Node3D
	if p == null:
		return
	_start_repair(p)


func _start_repair(player: Node3D) -> void:
	if state != SState.FAILED:
		return
	if _repairer != null and _repairer != player:
		return
	_repairer = player
	_progress = 0.0
	_fail_flash_t = 0.0
	_broadcast()


func is_failed() -> bool:
	return state == SState.FAILED


func danger_weight() -> float:
	return 1.0 if critical else 0.5


func _sync_progress() -> void:
	_last_sync += get_physics_process_delta_time()
	if _last_sync >= 0.2:
		_last_sync = 0.0
		_broadcast()


func _broadcast() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_visuals.rpc(state == SState.FAILED, _progress, _label_text())
	else:
		_refresh_local()


@rpc("any_peer", "call_local", "reliable")
func _sync_visuals(is_failed_now: bool, progress: float, text: String) -> void:
	state = SState.FAILED if is_failed_now else SState.OK
	_progress = progress
	_synced_label = text
	_refresh_local()


func _label_text() -> String:
	if not _server() and not _synced_label.is_empty():
		return _synced_label
	if state == SState.OK:
		return "%s\nONLINE" % display_name
	if _fail_flash_t > 0.0:
		return "%s\nREPAIR FAILED" % display_name
	if _repairer != null:
		return "%s\nHOLD E  %d%%" % [display_name, int(100.0 * _progress / maxf(repair_time, 0.01))]
	return "%s\nFAILED - HOLD E" % display_name


func _refresh_local() -> void:
	if _label != null:
		_label.text = _label_text()
		if _fail_flash_t > 0.0:
			_label.modulate = Color(1.0, 0.85, 0.25)
		else:
			_label.modulate = Color(1.0, 0.3, 0.22) if state == SState.FAILED else Color(0.6, 1.0, 0.65)
	if _light != null:
		_light.light_energy = 1.6 if state == SState.FAILED else 0.0
	if _mat != null:
		_mat.emission_enabled = state == SState.FAILED
		_mat.emission = Color(0.8, 0.06, 0.03)
		_mat.emission_energy_multiplier = 0.6

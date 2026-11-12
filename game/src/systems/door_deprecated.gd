class_name DoorDeprecated
extends AnimatableBody3D

@export var size := Vector3(1.5, 2.2, 0.12)
@export var accent := Color(0.45, 0.5, 0.58)
@export var open_angle := -1.45
@export var lockable := false

var _open := false
var _locked := false
var _tween: Tween
var _bar_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("doors")
	sync_to_physics = true
	_build()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(size.x * 0.5, size.y * 0.5, 0.0)
	add_child(shape)

	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = accent
	mat.roughness = 0.6
	mat.metallic = 0.25
	bm.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = bm
	mesh.position = shape.position
	add_child(mesh)

	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(size.x * 0.7, 0.08, 0.05)
	bar.mesh = bar_mesh
	bar.position = shape.position + Vector3(0.0, 0.0, size.z * 0.5 + 0.03)
	_bar_mat = StandardMaterial3D.new()
	_bar_mat.albedo_color = Color(0.85, 0.75, 0.35)
	_bar_mat.metallic = 0.6
	bar.material_override = _bar_mat
	add_child(bar)


func is_open() -> bool:
	return _open


func is_locked() -> bool:
	return _locked


func lock(value: bool) -> void:
	if _locked == value:
		return
	_locked = value
	if _locked:
		_set_open(false)
	_refresh_lock_visual()
	if multiplayer.has_multiplayer_peer():
		_sync_lock.rpc(value)


func toggle_lock() -> void:
	if not lockable:
		return
	lock(not _locked)
	NoiseBus.emit_noise(global_position, 0.35, self)


func open() -> void:
	if _locked:
		return
	_set_open(true)
	if multiplayer.has_multiplayer_peer():
		_sync.rpc(true)


func interact(_player: Node3D) -> void:
	if _locked:
		return
	var target := not _open
	_set_open(target)
	if multiplayer.has_multiplayer_peer():
		_sync.rpc(target)
	NoiseBus.emit_noise(global_position, 0.55, self)


@rpc("any_peer", "call_local", "reliable")
func _sync(open: bool) -> void:
	_set_open(open)


@rpc("any_peer", "call_local", "reliable")
func _sync_lock(value: bool) -> void:
	if _locked == value:
		return
	_locked = value
	if _locked:
		_set_open(false)
	_refresh_lock_visual()


func _set_open(open: bool) -> void:
	if _open == open:
		return
	if open and _locked:
		return
	_open = open
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation:y", open_angle if open else 0.0, 0.28)



func _refresh_lock_visual() -> void:
	if _bar_mat == null or not lockable:
		return
	_bar_mat.albedo_color = Color(0.9, 0.18, 0.14) if _locked else Color(0.85, 0.75, 0.35)
	_bar_mat.emission_enabled = _locked
	_bar_mat.emission = Color(0.9, 0.12, 0.08)
	_bar_mat.emission_energy_multiplier = 1.2 if _locked else 0.0

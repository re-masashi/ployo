class_name Door
extends AnimatableBody3D

@export var open_angle := -1.45
@export var lockable := false
@export var locked_material: StandardMaterial3D

@onready var _bar: MeshInstance3D = %bar

var _open := false
var _locked := false
var _tween: Tween

var _open_angle: float
var _close_angle: float

func _ready() -> void:
	translate(Vector3(-.75, 0, 0))
	add_to_group("doors")
	sync_to_physics = true
	_open_angle = rotation.y + open_angle
	_close_angle = rotation.y

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
	_tween.tween_property(self, "rotation:y", _open_angle if open else _close_angle, 0.28)



func _refresh_lock_visual() -> void:
	if not lockable: return
	_bar.material_override = locked_material if _locked else null

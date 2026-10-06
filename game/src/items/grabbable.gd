class_name Grabbable
extends RigidBody3D

signal broken

@export var weight_kg := 5.0
@export var value := 100
@export var max_hp := 30.0
@export var break_impact_speed := 4.0
@export var fragility := 10.0
@export var carry_speed_factor := 0.9
@export var carry_distance_min := 1.2
@export var carry_distance_max := 2.2

const REGREB_COOLDOWN := 0.4
const PLACE_GRACE := 0.6

var hp: float
var is_carried := false
var is_secured := false
var is_broken := false
var carrier_id := -1
var origin_transform: Transform3D
var _original_value := 0
var _cooldown := 0.0
var _damage_grace := 0.0
var _prev_speed := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	hp = max_hp
	_original_value = value
	origin_transform = global_transform
	add_to_group("grabbables")
	_mesh = get_node_or_null("Mesh") as MeshInstance3D
	contact_monitor = true
	max_contacts_reported = 4
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if _damage_grace > 0.0:
		_damage_grace = maxf(0.0, _damage_grace - delta)
	if is_broken and _mesh != null and _mesh.visible:
		_mesh.visible = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_prev_speed = state.linear_velocity.length()


func _on_body_entered(_body: Node) -> void:
	apply_impact(_prev_speed)


func can_grab() -> bool:
	return not is_carried and not is_secured and not is_broken and _cooldown <= 0.0


func grab_by(peer_id: int) -> void:
	if not can_grab():
		return
	is_carried = true
	carrier_id = peer_id
	_cooldown = 0.0
	_damage_grace = 0.0
	freeze = true
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func release(thrown: bool, impulse: Vector3) -> void:
	is_carried = false
	carrier_id = -1
	freeze = false
	sleeping = false
	if thrown:
		_cooldown = REGREB_COOLDOWN
		apply_central_impulse(impulse)
		angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
	else:
		_damage_grace = PLACE_GRACE


func apply_impact(impact_speed: float) -> void:
	if is_carried or is_secured or is_broken:
		return
	if _damage_grace > 0.0:
		return
	if impact_speed <= break_impact_speed:
		return
	hp -= (impact_speed - break_impact_speed) * fragility
	if hp <= 0.0:
		_break()


func _break() -> void:
	is_broken = true
	hp = 0.0
	value = 0
	if _mesh != null:
		_mesh.visible = false
	broken.emit()
	_remote_break.rpc()


@rpc("any_peer", "call_local")
func _remote_break() -> void:
	if is_broken:
		return
	is_broken = true
	hp = 0.0
	value = 0
	if _mesh != null:
		_mesh.visible = false


func reset_to_origin() -> void:
	is_carried = false
	is_secured = false
	is_broken = false
	carrier_id = -1
	_cooldown = 0.0
	_damage_grace = 0.0
	hp = max_hp
	value = _original_value
	freeze = false
	sleeping = false
	set_multiplayer_authority(1)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = origin_transform
	if _mesh != null:
		_mesh.visible = true

extends Node3D

const SWING_TIME := 0.45
const WALK_RATE := 9.0

var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _base_arm_l := 0.0
var _base_arm_r := 0.0
var _base_leg_l := 0.0
var _base_leg_r := 0.0
var _base_pos := Vector3.ZERO
var _swing_t := 0.0
var _bob_t := 0.0


func _ready() -> void:
	_base_pos = position
	_arm_l = find_child("ArmL", true, false) as Node3D
	_arm_r = find_child("ArmR", true, false) as Node3D
	_leg_l = find_child("LegL", true, false) as Node3D
	_leg_r = find_child("LegR", true, false) as Node3D
	if _arm_l != null:
		_base_arm_l = _arm_l.rotation.x
	if _arm_r != null:
		_base_arm_r = _arm_r.rotation.x
	if _leg_l != null:
		_base_leg_l = _leg_l.rotation.x
	if _leg_r != null:
		_base_leg_r = _leg_r.rotation.x


func play_swing() -> void:
	_swing_t = SWING_TIME


func _process(delta: float) -> void:
	_bob_t += delta
	var body := get_parent() as CharacterBody3D
	if body == null and get_parent() != null:
		body = get_parent().get_parent() as CharacterBody3D
	var moving := body != null and Vector2(body.velocity.x, body.velocity.z).length() > 0.5
	var phase := _bob_t * WALK_RATE
	var step := sin(phase)
	var blend := clampf(delta * 10.0, 0.0, 1.0)

	if moving:
		if _leg_l != null:
			_leg_l.rotation.x = _base_leg_l + step * 0.5
		if _leg_r != null:
			_leg_r.rotation.x = _base_leg_r - step * 0.5
		if _arm_l != null:
			_arm_l.rotation.x = _base_arm_l - step * 0.35
		if _arm_r != null and _swing_t <= 0.0:
			_arm_r.rotation.x = _base_arm_r + step * 0.25
	else:
		if _leg_l != null:
			_leg_l.rotation.x = lerp_angle(_leg_l.rotation.x, _base_leg_l, blend)
		if _leg_r != null:
			_leg_r.rotation.x = lerp_angle(_leg_r.rotation.x, _base_leg_r, blend)
		if _arm_l != null:
			_arm_l.rotation.x = lerp_angle(_arm_l.rotation.x, _base_arm_l, blend)

	if _arm_r != null:
		if _swing_t > 0.0:
			_swing_t = maxf(0.0, _swing_t - delta)
			var t := 1.0 - _swing_t / SWING_TIME
			_arm_r.rotation.x = _base_arm_r + sin(t * PI) * 1.45
		elif not moving:
			_arm_r.rotation.x = lerp_angle(_arm_r.rotation.x, _base_arm_r, blend)

	var bob := absf(sin(phase)) * 0.045 if moving else 0.0
	position = _base_pos + Vector3(0.0, bob, 0.0)

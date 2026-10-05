class_name TestPlayer
extends CharacterBody3D

@export_group("Movement")
@export var walk_speed := 6.2
@export var ground_acceleration := 95.0
@export var ground_deceleration := 110.0
@export var air_acceleration := 70.0
@export var air_deceleration := 28.0
@export var jump_velocity := 6.8
@export var gravity := 13.5
@export var fall_gravity_multiplier := 1.15
@export var max_fall_speed := 40.0
@export var jump_cut_multiplier := 0.55
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12

@export_group("Camera")
@export var mouse_sensitivity := 0.0028
@export var base_fov := 60.0
@export var fov_kick := 4.0
@export var fov_smoothing := 10.0
@export var eye_height := 1.62
@export var bob_frequency := 11.0
@export var bob_amplitude := 0.012
@export var land_dip_amount := 0.025
@export var land_dip_recovery := 14.0
@export var look_pitch_limit := PI / 2.0 - 0.04

var _yaw := 0.0
var _pitch := 0.0
var _cam: Camera3D
var _cam_base_y := 0.0

var _coyote := 0.0
var _jump_buffer := 0.0
var _jump_held := false
var _jump_cut_armed := false
var _was_on_floor := true

var _bob_phase := 0.0
var _bob_offset := 0.0
var _land_dip := 0.0
var _target_fov := 78.0

func _ready() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	col.shape = capsule
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	_cam = Camera3D.new()
	_cam.fov = base_fov
	_cam.near = 0.05
	_cam.far = 120.0
	_cam.current = true
	add_child(_cam)
	_cam_base_y = eye_height
	_cam.position = Vector3(0, _cam_base_y, 0)
	_target_fov = base_fov

	floor_snap_length = 0.75
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = false
	safe_margin = 0.02

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func set_camera_current(active: bool) -> void:
	set_process(active)
	set_physics_process(active)
	set_process_unhandled_input(active)
	if _cam != null:
		_cam.current = active
	if active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, -look_pitch_limit, look_pitch_limit)
		rotation.y = _yaw
		_cam.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event.is_action_pressed("jump"):
		_jump_buffer = jump_buffer_time
	if event.is_action_released("jump"):
		if _jump_cut_armed and velocity.y > 0.0:
			velocity.y *= jump_cut_multiplier
			_jump_cut_armed = false

func _physics_process(delta: float) -> void:
	_jump_held = Input.is_action_pressed("jump")
	_update_coyote_and_jump_buffer(delta)
	_update_horizontal(delta)
	_update_vertical(delta)
	var pre_velocity := velocity
	move_and_slide()
	_update_landing(pre_velocity)
	_update_camera_feel(delta)

func _update_coyote_and_jump_buffer(delta: float) -> void:
	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)

func _update_horizontal(delta: float) -> void:
	var wish := _wish_direction()
	var on_floor := is_on_floor()
	var accel := ground_acceleration if on_floor else air_acceleration
	var decel := ground_deceleration if on_floor else air_deceleration
	var target := wish * walk_speed

	if wish.length_squared() > 0.0:
		velocity.x = _exp_approach(velocity.x, target.x, accel, delta)
		velocity.z = _exp_approach(velocity.z, target.z, accel, delta)
	else:
		velocity.x = _exp_approach(velocity.x, 0.0, decel, delta)
		velocity.z = _exp_approach(velocity.z, 0.0, decel, delta)

func _update_vertical(delta: float) -> void:
	if is_on_floor():
		if _jump_buffer > 0.0:
			velocity.y = jump_velocity
			_jump_buffer = 0.0
			_coyote = 0.0
			_jump_cut_armed = true
			_was_on_floor = false
			return
	else:
		if _jump_buffer > 0.0 and _coyote > 0.0:
			velocity.y = jump_velocity
			_jump_buffer = 0.0
			_coyote = 0.0
			_jump_cut_armed = true
			_was_on_floor = false
			return

		var g := gravity
		if velocity.y < 0.0:
			g *= fall_gravity_multiplier
		velocity.y -= g * delta
		velocity.y = maxf(velocity.y, -max_fall_speed)

		if _jump_cut_armed and not _jump_held and velocity.y > 0.0:
			velocity.y *= jump_cut_multiplier
			_jump_cut_armed = false

func _update_landing(pre_velocity: Vector3) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		var fall_proxy := maxf(-pre_velocity.y, 0.0)
		var strength := clampf(fall_proxy / 18.0, 0.0, 1.0)
		_land_dip = maxf(_land_dip, land_dip_amount * strength)
		_jump_cut_armed = false
	_was_on_floor = on_floor

func _update_camera_feel(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var speed_ratio := clampf(hspeed / maxf(walk_speed, 0.001), 0.0, 1.0)

	_target_fov = base_fov + fov_kick * speed_ratio
	_cam.fov = lerpf(_cam.fov, _target_fov, 1.0 - exp(-fov_smoothing * delta))

	var moving := is_on_floor() and hspeed > 0.5
	if moving:
		_bob_phase += delta * bob_frequency * clampf(hspeed / maxf(walk_speed, 0.001), 0.4, 1.2)
		var amp := bob_amplitude * clampf(hspeed / maxf(walk_speed, 0.001), 0.0, 1.0)
		_bob_offset = lerpf(_bob_offset, sin(_bob_phase * 2.0) * amp, 1.0 - exp(-16.0 * delta))
	else:
		_bob_offset = lerpf(_bob_offset, 0.0, 1.0 - exp(-14.0 * delta))

	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-land_dip_recovery * delta))
	_cam.position.y = _cam_base_y + _bob_offset - _land_dip

func _wish_direction() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v.length_squared() == 0.0:
		return Vector3.ZERO
	var wish := transform.basis * Vector3(v.x, 0.0, v.y)
	wish.y = 0.0
	if wish.length_squared() > 0.0:
		wish = wish.normalized()
	return wish

func _exp_approach(current: float, target: float, rate: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * delta))

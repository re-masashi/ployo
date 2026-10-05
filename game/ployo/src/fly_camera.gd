extends Camera3D

@export var move_speed: float = 12.0
@export var fast_speed: float = 48.0
@export var mouse_sensitivity: float = 0.0025
@export var acceleration: float = 12.0
@export var base_fov: float = 78.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _velocity := Vector3.ZERO
var _was_current := false

func _ready() -> void:
	fov = base_fov
	near = 0.05
	far = 400.0
	_yaw = rotation.y
	_pitch = rotation.x
	set_process(false)

func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, -PI / 2.0 + 0.05, PI / 2.0 - 0.05)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if not current:
		_was_current = false
		_velocity = Vector3.ZERO
		return
	if not _was_current:
		_yaw = rotation.y
		_pitch = rotation.x
		_was_current = true

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_velocity = _velocity.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
		position += _velocity * delta
		return

	var speed := fast_speed if Input.is_key_pressed(KEY_SHIFT) else move_speed
	var direction := Vector3.ZERO

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction -= transform.basis.z
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction += transform.basis.z
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction -= transform.basis.x
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction += transform.basis.x
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		direction += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		direction -= Vector3.UP

	if direction != Vector3.ZERO:
		direction = direction.normalized()

	var target := direction * speed
	_velocity = _velocity.lerp(target, 1.0 - exp(-acceleration * delta))
	position += _velocity * delta

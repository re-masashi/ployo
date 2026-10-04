class_name TestPlayer
extends CharacterBody3D

@export var walk_speed := 4.5
@export var jump_velocity := 5.0
@export var gravity := 9.8
@export var mouse_sensitivity := 0.003
@export var debug_settle_print := true
@export var debug_fps := true

var _fps_time := 0.0

var _yaw := 0.0
var _pitch := 0.0
var _frames := 0
var _cam: Camera3D

func _ready() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	col.shape = capsule
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	_cam = Camera3D.new()
	_cam.position = Vector3(0, 1.6, 0)
	_cam.far = 400.0
	_cam.current = true
	add_child(_cam)

	floor_snap_length = 0.3
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, -PI / 2.0 + 0.05, PI / 2.0 - 0.05)
		rotation.y = _yaw
		_cam.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if event.keycode == KEY_SPACE and is_on_floor():
			velocity.y = jump_velocity

func _physics_process(delta: float) -> void:
	_frames += 1
	if not is_on_floor():
		velocity.y -= gravity * delta

	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var wish := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		wish += fwd
	if Input.is_key_pressed(KEY_S):
		wish -= fwd
	if Input.is_key_pressed(KEY_D):
		wish += right
	if Input.is_key_pressed(KEY_A):
		wish -= right
	if wish.length_squared() > 0.0:
		wish = wish.normalized()
	velocity.x = wish.x * walk_speed
	velocity.z = wish.z * walk_speed

	move_and_slide()

	if debug_settle_print and _frames == 60:
		debug_settle_print = false
		print("PLAYER settle pos=(%.2f,%.2f,%.2f) on_floor=%s" % [position.x, position.y, position.z, str(is_on_floor())])

func _process(delta: float) -> void:
	if not debug_fps:
		return
	_fps_time += delta
	if _fps_time >= 5.0:
		_fps_time = 0.0
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
		var buf := Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)
		var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
		var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		print("PERF fps=%.0f draws=%.0f prims=%.0f tex=%.1fMB buf=%.1fMB vram=%.1fMB phys=%.3fms gpu=%s" % [
			Engine.get_frames_per_second(), draws, prims,
			tex / 1048576.0, buf / 1048576.0, vram / 1048576.0,
			phys * 1000.0, RenderingServer.get_video_adapter_name()])

extends CharacterBody3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

@onready var _cam: Camera3D = %Camera3D

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	
	var dir := Input.get_vector("left", "right", "fwd", "bck")
	var vel := (_cam.global_basis * Vector3(dir.x, 0, dir.y)).normalized() * 4
	velocity.x = vel.x
	velocity.z = vel.z
	pass

var _max_up_angle_view_rad := deg_to_rad(-90.0)
var _max_down_angle_view_rad := deg_to_rad(90.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam.rotation.y += -event.relative.x * .005
		_cam.rotation.x += -event.relative.y * .005
		#use of deg_to_rad, because we change the x axis rotation with rotation,x, which use radians instead of degrees
		_cam.rotation.x = clamp(_cam.rotation.x, _max_up_angle_view_rad, _max_down_angle_view_rad)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("escape_game"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action("jump") and is_on_floor():
		velocity.y = 0.1

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= delta * 0.5
		var travel := move_and_collide(Vector3(0, velocity.y, 0))
		if travel != null: velocity.y = 0

	move_and_slide()
	pass

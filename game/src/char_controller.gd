extends CharacterBody3D

## each peer owns its own body (client-owned),
## host only manages spawning. identity (name + color) is derived
## deterministically from the multiplayer authority id. every peer
## computes the same visuals without extra RPCs.

const PALETTE: Array[Color] = [
	Color(0.95, 0.35, 0.25),
	Color(0.25, 0.55, 0.95),
	Color(0.35, 0.80, 0.35),
	Color(0.95, 0.80, 0.25),
	Color(0.70, 0.40, 0.90),
	Color(0.95, 0.55, 0.20),
]

var player_name := "Player"
var player_color := Color(0.25, 0.55, 0.95)

static func spawn_position_for(peer_id: int, marks: Array) -> Vector3:
	if marks.is_empty():
		var a := TAU * float(absi(peer_id) % 6) / 6.0
		return Vector3(cos(a) * 4.0, 1.0, sin(a) * 4.0)
	var m := marks[absi(peer_id) % marks.size()] as Node3D
	var rng := RandomNumberGenerator.new()
	rng.seed = peer_id
	var jitter := Vector3(rng.randf_range(-0.8, 0.8), 0.5, rng.randf_range(-0.8, 0.8))
	return m.global_position + jitter

@onready var _cam: Camera3D = %Camera3D
@onready var _body: MeshInstance3D = $Body
@onready var _tag: Label3D = $NameTag
@onready var _sync: MultiplayerSynchronizer = $MultiplayerSynchronizer


func _enter_tree() -> void:
	var id := str(name).to_int()
	if id != 0:
		set_multiplayer_authority(id)
		$MultiplayerSynchronizer.set_multiplayer_authority(id)


func _ready() -> void:
	var oid := get_multiplayer_authority()
	player_name = "Player%d" % oid
	player_color = PALETTE[absi(oid) % PALETTE.size()]
	_apply_identity()
	if is_multiplayer_authority():
		# owner places itself deterministically; everyone else syncs
		var marks := get_tree().get_nodes_in_group("spawn_points")
		position = spawn_position_for(oid, marks)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_cam.current = true
		_body.visible = false
		_tag.visible = false
	else:
		_cam.current = false


func setup(p_name: String, p_color: Color) -> void:
	player_name = p_name
	player_color = p_color
	_apply_identity()

func _apply_identity() -> void:
	if not is_node_ready():
		return
	_tag.text = player_name
	var mat := StandardMaterial3D.new()
	mat.albedo_color = player_color
	mat.roughness = 0.6
	_body.set_surface_override_material(0, mat)


func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
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
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam.rotation.y += -event.relative.x * .005
		_cam.rotation.x += -event.relative.y * .005
		#use of deg_to_rad, because we change the x axis rotation with rotation,x, which use radians instead of degrees
		_cam.rotation.x = clamp(_cam.rotation.x, _max_up_angle_view_rad, _max_down_angle_view_rad)

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("escape_game"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action("jump") and is_on_floor():
		velocity.y = 0.1

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if not is_on_floor():
		velocity.y -= delta * 0.5
		var travel := move_and_collide(Vector3(0, velocity.y, 0))
		if travel != null: velocity.y = 0

	move_and_slide()
	pass

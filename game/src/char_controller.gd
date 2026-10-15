extends CharacterBody3D

enum StatusState { NORMAL, STUNNED }
enum LocoState { GROUNDED, AIRBORNE }
enum StanceState { STAND, SPRINT, CROUCH }
enum HandsState { EMPTY, GRABBING, CARRYING, THROWING }

const PALETTE: Array[Color] = [
	Color(0.95, 0.35, 0.25),
	Color(0.25, 0.55, 0.95),
	Color(0.35, 0.80, 0.35),
	Color(0.95, 0.80, 0.25),
	Color(0.70, 0.40, 0.90),
	Color(0.95, 0.55, 0.20),
]

const BASE_SPEED := 4.0
const SPRINT_MULT := 1.6
const CROUCH_MULT := 0.5
const ACCEL_GROUND := 40.0
const ACCEL_AIR := 12.0
const STOP_FRICTION := 32.0
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.12
const JUMP_CUT := 0.5
const LAND_DIP_GAIN := 0.012
const LAND_DIP_MAX := 0.14
const SPRINT_FOV_BONUS := 4.0
const CROUCH_HEIGHT_FACTOR := 0.6
const STAND_CAPSULE_HEIGHT := 2.0
const GRAVITY := 18.0
const JUMP_EMPTY := 4.5
const JUMP_LIGHT := 3.5
const JUMP_MED := 2.5
const GRAB_LIFT_TIME := 0.12
const THROW_BASE := 9.0
const THROW_MIN := 4.0
const THROW_MAX := 12.0
const THROW_CD := 0.4
const THROW_STATE_TIME := 0.1
const STUN_TIME := 2.0
const CARRY_DEFAULT_DIST := 1.4

const WALK_ANIMS := ["walk", "walk_001"]
const WALK_PLAYBACK_SPEED := 3.0
const MODEL_BASE_SCALE := 0.6
const MODEL_YAW_OFFSET := 0.0
const WALK_MOVE_THRESHOLD := 0.5
const MODEL_TURN_SPEED := 12.0

var player_name := "Player"
var player_color := Color(0.25, 0.55, 0.95)

var status: StatusState = StatusState.NORMAL
var loco: LocoState = LocoState.GROUNDED
var stance: StanceState = StanceState.STAND
var hands: HandsState = HandsState.EMPTY
var carried_item: Grabbable = null
var carry_distance := CARRY_DEFAULT_DIST
var carry_yaw := 0.0
var carry_pitch := 0.0

var _stun_t := 0.0
var _grab_t := 0.0
var _throw_t := 0.0
var _throw_cd := 0.0
var _grab_pending := false
var _pending_t := 0.0
var _coyote := 0.0
var _jump_buf := 0.0
var _land_dip := 0.0
var _base_fov := 75.0

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
@onready var _anchor: Marker3D = %CarryAnchor
@onready var _ray: RayCast3D = %GrabRay
@onready var _model: Node3D = $Model
@onready var _tag: Label3D = $NameTag
@onready var _col: CollisionShape3D = $CollisionShape3D

var _anim: AnimationPlayer = null
var _walk_anim := ""
var _prev_pos := Vector3.ZERO
var _walk_keepalive := 0.0
var _anim_diag_done := false


func _enter_tree() -> void:
	var id := str(name).to_int()
	if id != 0:
		set_multiplayer_authority(id)
		$MultiplayerSynchronizer.set_multiplayer_authority(id)


func _ready() -> void:
	var oid := get_multiplayer_authority()
	player_name = "Player%d" % oid
	player_color = PALETTE[absi(oid) % PALETTE.size()]
	_anim = $Model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_resolve_walk_anim()
	_base_fov = _cam.fov
	_prev_pos = global_position
	_apply_identity()
	_ray.add_exception(self)
	_col.shape = _col.shape.duplicate()
	if is_multiplayer_authority():
		var marks := get_tree().get_nodes_in_group("spawn_points")
		position = spawn_position_for(oid, marks)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_cam.current = true
		_model.visible = false
		_tag.visible = false
	else:
		_cam.current = false


func _resolve_walk_anim() -> void:
	if _anim == null:
		push_warning("[Walk] no AnimationPlayer under $Model; walk disabled")
		return
	for n in WALK_ANIMS:
		if _anim.has_animation(n):
			_walk_anim = n
			break
	if _walk_anim.is_empty() and _anim.get_animation_list().size() > 0:
		_walk_anim = _anim.get_animation_list()[0]
	if _walk_anim.is_empty():
		push_warning("[Walk] AnimationPlayer has no animations")
		return
	var clip: Animation = _anim.get_animation(_walk_anim)
	if clip != null:
		clip.loop_mode = Animation.LOOP_LINEAR
	print("[Walk] using anim '", _walk_anim, "' from ", _anim.get_animation_list())


func setup(p_name: String, p_color: Color) -> void:
	player_name = p_name
	player_color = p_color
	_apply_identity()

func _apply_identity() -> void:
	if not is_node_ready():
		return
	_tag.text = player_name

func can_sprint() -> bool:
	return status == StatusState.NORMAL and stance != StanceState.CROUCH and hands == HandsState.EMPTY

func hands_empty() -> bool:
	return hands == HandsState.EMPTY

func speed_factor() -> float:
	if carried_item != null:
		return carried_item.carry_speed_factor
	return 1.0

func _jump_velocity() -> float:
	if carried_item == null:
		return JUMP_EMPTY
	if carried_item.weight_kg <= 8.0:
		return JUMP_LIGHT
	if carried_item.weight_kg <= 20.0:
		return JUMP_MED
	return 0.0


func try_grab_target(item: Grabbable) -> bool:
	if hands != HandsState.EMPTY:
		return false
	if status != StatusState.NORMAL:
		return false
	if _throw_cd > 0.0:
		return false
	if _grab_pending:
		return false
	if item == null or not item.can_grab():
		return false
	_server_or_direct_grab(item)
	return true


func place_carried() -> void:
	if hands != HandsState.CARRYING and hands != HandsState.GRABBING:
		return
	if carried_item == null:
		return
	var item := carried_item
	var spot := _find_place_position(item)
	if not spot[1]:
		print("[Hands] no room to place ", item.name)
		return
	var yaw := _cam.global_rotation.y + carry_yaw
	item.global_transform = Transform3D(Basis(Vector3.UP, yaw), spot[0])
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	_server_or_direct_release(item, false, Vector3.ZERO)


func throw_carried() -> void:
	if hands != HandsState.CARRYING and hands != HandsState.GRABBING:
		return
	if carried_item == null:
		return
	var item := carried_item
	var dir := -_cam.global_transform.basis.z
	var power := clampf(THROW_BASE * 5.0 / maxf(item.weight_kg, 1.0), THROW_MIN, THROW_MAX)
	var impulse := (dir * 0.85 + Vector3.UP * 0.5).normalized() * power * item.mass
	_server_or_direct_release(item, true, impulse)
	hands = HandsState.THROWING
	_throw_t = THROW_STATE_TIME
	_throw_cd = THROW_CD


func apply_stun(duration: float = STUN_TIME) -> void:
	status = StatusState.STUNNED
	_stun_t = maxf(_stun_t, duration)
	velocity.x = 0.0
	velocity.z = 0.0
	if hands == HandsState.CARRYING or hands == HandsState.GRABBING:
		var item := carried_item
		if item != null:
			var fling := Vector3(randf_range(-1.0, 1.0), 1.5, randf_range(-1.0, 1.0))
			_server_or_direct_release(item, true, fling)
			hands = HandsState.EMPTY
			print("[Hands] stunned, dropped ", item.name)


func _my_id() -> int:
	return get_multiplayer_authority()

func _server_or_direct_grab(item: Grabbable) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		item.set_net_authority(_my_id())
		_attach(item)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_remote_grab.rpc(item.get_path(), _my_id())
	else:
		_grab_pending = true
		_pending_t = 2.0
		server_request_grab.rpc_id(1, item.get_path())


@rpc("any_peer")
func server_request_grab(item_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var item := get_node_or_null(item_path) as Grabbable
	if item == null or not item.can_grab():
		_grab_denied.rpc_id(sender)
		return
	item.grab_by(sender)
	item.set_net_authority(sender)
	_client_grab_granted.rpc_id(sender, item_path)
	_remote_grab.rpc(item_path, sender)


## State broadcast so every peer's copy converges (spectators included).
@rpc("any_peer", "call_local")
func _remote_grab(item_path: String, sender: int) -> void:
	var item := get_node_or_null(item_path) as Grabbable
	if item == null or not item.can_grab():
		return
	if sender == _my_id():
		return
	item.set_net_authority(sender)
	item.grab_by(sender)


@rpc("any_peer")
func _client_grab_granted(item_path: String) -> void:
	_grab_pending = false
	_pending_t = 0.0
	var item := get_node_or_null(item_path) as Grabbable
	if item == null or not item.can_grab():
		return
	_attach(item)


@rpc("any_peer")
func _grab_denied() -> void:
	_grab_pending = false
	_pending_t = 0.0


func _server_or_direct_release(item: Grabbable, thrown: bool, impulse: Vector3) -> void:
	var pos := item.global_position
	var rot := item.global_rotation
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		item.set_net_authority(1)
		_release_local(item, thrown, impulse)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_remote_release.rpc(item.get_path(), thrown, impulse, pos, rot)
	else:
		_release_local(item, thrown, impulse)
		server_release.rpc_id(1, item.get_path(), thrown, impulse, pos, rot)


@rpc("any_peer")
func server_release(item_path: String, thrown: bool, impulse: Vector3, pos: Vector3, rot: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var item := get_node_or_null(item_path) as Grabbable
	if item == null:
		return
	item.global_transform = Transform3D(Basis.from_euler(rot), pos)
	item.set_net_authority(1)
	if item.is_carried:
		item.release(thrown, impulse)
	_remote_release.rpc(item_path, thrown, impulse, pos, rot)


@rpc("any_peer", "call_local")
func _remote_release(item_path: String, thrown: bool, impulse: Vector3, pos: Vector3, rot: Vector3) -> void:
	var item := get_node_or_null(item_path) as Grabbable
	if item == null or not item.is_carried:
		return
	if item.carrier_id == _my_id():
		return
	item.global_transform = Transform3D(Basis.from_euler(rot), pos)
	item.set_net_authority(1)
	item.release(thrown, impulse)


func _attach(item: Grabbable) -> void:
	carried_item = item
	item.set_net_authority(_my_id())
	item.grab_by(_my_id())
	if not item.broken.is_connected(_on_carried_broken):
		item.broken.connect(_on_carried_broken.bind(item))
	hands = HandsState.GRABBING
	_grab_t = GRAB_LIFT_TIME
	carry_distance = clampf(CARRY_DEFAULT_DIST, item.carry_distance_min, item.carry_distance_max)
	carry_yaw = 0.0
	carry_pitch = 0.0
	print("[Hands] grabbed ", item.name)


func _release_local(item: Grabbable, thrown: bool, impulse: Vector3) -> void:
	if item.broken.is_connected(_on_carried_broken):
		item.broken.disconnect(_on_carried_broken)
	item.set_net_authority(1)
	item.release(thrown, impulse)
	if carried_item == item:
		carried_item = null
	hands = HandsState.EMPTY


func _on_carried_broken(item: Grabbable) -> void:
	print("[Hands] ", item.name, " broke! value lost.")

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_status_step(delta)
	_locomotion_step(delta)
	_hands_step(delta)
	var was_floor := is_on_floor()
	var pre_y := velocity.y
	move_and_slide()
	_camera_feel_step(delta, was_floor, pre_y)
	_authority_anim_update(delta)


func _process(delta: float) -> void:
	# Remote copies never run _physics_process, so drive their walk
	# visuals from replicated position deltas instead.
	if is_multiplayer_authority():
		return
	if _anim == null or _walk_anim.is_empty():
		_prev_pos = global_position
		return
	var dt := maxf(delta, 0.0001)
	var moved: Vector3 = (global_position - _prev_pos) / dt
	_prev_pos = global_position
	var flat := Vector3(moved.x, 0.0, moved.z)
	_update_walk_visual(flat.length() > WALK_MOVE_THRESHOLD, flat, delta)


func _authority_anim_update(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	_prev_pos = global_position
	_update_walk_visual(flat.length() > WALK_MOVE_THRESHOLD, flat, delta)


func _update_walk_visual(moving: bool, flat_dir: Vector3, delta: float) -> void:
	if flat_dir.length_squared() > 0.01:
		var target_yaw := atan2(-flat_dir.x, -flat_dir.z) + MODEL_YAW_OFFSET
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, clampf(MODEL_TURN_SPEED * delta, 0.0, 1.0))
	if _anim == null or _walk_anim.is_empty():
		return
	# Keepalive: replicated positions arrive in discrete net ticks, so a
	# per-frame delta flickers. Hold playback briefly through gaps.
	if moving:
		_walk_keepalive = 0.35
	else:
		_walk_keepalive = maxf(0.0, _walk_keepalive - delta)
	if _walk_keepalive > 0.0:
		if not _anim.is_playing() or _anim.current_animation != _walk_anim:
			_anim.play(_walk_anim, 0.15)
			if not _anim_diag_done:
				_anim_diag_done = true
				print("[Walk] playing '", _walk_anim, "'")
		# 24fps source x3 = 72fps effective playback.
		_anim.speed_scale = WALK_PLAYBACK_SPEED
	else:
		if _anim.is_playing() and _anim.current_animation == _walk_anim:
			_anim.stop()

func _status_step(delta: float) -> void:
	if _throw_cd > 0.0:
		_throw_cd = maxf(0.0, _throw_cd - delta)
	if _grab_pending:
		_pending_t -= delta
		if _pending_t <= 0.0:
			_grab_pending = false
			_pending_t = 0.0
	if status != StatusState.STUNNED:
		return
	_stun_t -= delta
	if _stun_t <= 0.0:
		status = StatusState.NORMAL
		_stun_t = 0.0

func _locomotion_step(delta: float) -> void:
	loco = LocoState.GROUNDED if is_on_floor() else LocoState.AIRBORNE
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var stunned := status == StatusState.STUNNED
	var dir := Vector2.ZERO
	if not stunned:
		dir = Input.get_vector("left", "right", "fwd", "bck")

	if Input.is_action_pressed("crouch") and not stunned:
		stance = StanceState.CROUCH
	elif Input.is_action_pressed("sprint") and can_sprint() and dir.y < -0.1:
		stance = StanceState.SPRINT
	else:
		stance = StanceState.STAND
	_apply_stance_visual()

	var mult := 1.0
	if stance == StanceState.SPRINT:
		mult = SPRINT_MULT
	elif stance == StanceState.CROUCH:
		mult = CROUCH_MULT
	var speed := BASE_SPEED * speed_factor() * mult

	var accel := ACCEL_GROUND if is_on_floor() else ACCEL_AIR
	accel *= _accel_factor()
	if dir != Vector2.ZERO and not stunned:
		var yaw := _cam.global_rotation.y
		var wish := Vector3(dir.x, 0.0, dir.y).rotated(Vector3.UP, yaw)
		velocity.x = move_toward(velocity.x, wish.x * speed, accel * delta)
		velocity.z = move_toward(velocity.z, wish.z * speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, STOP_FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, STOP_FRICTION * delta)

	if is_on_floor():
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(0.0, _coyote - delta)
	if not stunned and Input.is_action_just_pressed("jump"):
		_jump_buf = JUMP_BUFFER
	else:
		_jump_buf = maxf(0.0, _jump_buf - delta)
	if not stunned and _jump_buf > 0.0 and (is_on_floor() or _coyote > 0.0):
		var jv := _jump_velocity()
		if jv > 0.0:
			velocity.y = jv
			_jump_buf = 0.0
			_coyote = 0.0
	if not stunned and Input.is_action_just_released("jump") and velocity.y > 0.5:
		velocity.y *= JUMP_CUT


func _accel_factor() -> float:
	if carried_item == null:
		return 1.0
	return lerpf(1.0, 0.55, clampf((carried_item.weight_kg - 5.0) / 30.0, 0.0, 1.0))


func _camera_feel_step(delta: float, was_floor: bool, pre_y: float) -> void:
	if not was_floor and is_on_floor() and pre_y < -1.0:
		_land_dip = minf(_land_dip + clampf(-pre_y * LAND_DIP_GAIN, 0.0, LAND_DIP_MAX), 0.16)
	_land_dip = lerpf(_land_dip, 0.0, clampf(delta * 10.0, 0.0, 1.0))
	_cam.position.y += _land_dip
	var want_fov := _base_fov
	if stance == StanceState.SPRINT and Vector2(velocity.x, velocity.z).length() > 1.0:
		want_fov += SPRINT_FOV_BONUS
	_cam.fov = lerpf(_cam.fov, want_fov, clampf(delta * 5.0, 0.0, 1.0))


func _apply_stance_visual() -> void:
	var cap := _col.shape as CapsuleShape3D
	if stance == StanceState.CROUCH and cap != null:
		cap.height = STAND_CAPSULE_HEIGHT * CROUCH_HEIGHT_FACTOR
		_col.position.y = -STAND_CAPSULE_HEIGHT * (1.0 - CROUCH_HEIGHT_FACTOR) * 0.5
		_cam.position.y = -0.5
		_model.scale = Vector3(MODEL_BASE_SCALE, MODEL_BASE_SCALE * CROUCH_HEIGHT_FACTOR, MODEL_BASE_SCALE)
	else:
		if cap != null:
			cap.height = STAND_CAPSULE_HEIGHT
		_col.position.y = 0.0
		_cam.position.y = 0.0
		if is_node_ready() and _model != null:
			_model.scale = Vector3.ONE * MODEL_BASE_SCALE


func _hands_step(delta: float) -> void:
	if _throw_t > 0.0:
		_throw_t -= delta
		if _throw_t <= 0.0 and hands == HandsState.THROWING:
			hands = HandsState.EMPTY
	if status == StatusState.STUNNED:
		return

	if hands == HandsState.EMPTY and Input.is_action_just_pressed("grab"):
		_ray.force_raycast_update()
		var hit := _ray.get_collider() as Grabbable
		if hit != null:
			if not try_grab_target(hit):
				print("[Hands] grab denied: ", hit.name)
	elif (hands == HandsState.CARRYING or hands == HandsState.GRABBING) and Input.is_action_just_pressed("grab"):
		place_carried()
	elif (hands == HandsState.CARRYING or hands == HandsState.GRABBING) and Input.is_action_just_pressed("throw_item"):
		throw_carried()

	if _grab_t > 0.0:
		_grab_t -= delta
		if _grab_t <= 0.0 and hands == HandsState.GRABBING:
			hands = HandsState.CARRYING

	if (hands == HandsState.CARRYING or hands == HandsState.GRABBING) and carried_item != null:
		_follow_carried(delta)


func _follow_carried(delta: float) -> void:
	var item := carried_item
	if multiplayer.has_multiplayer_peer() and not item.is_multiplayer_authority():
		return
	var rate := lerpf(18.0, 7.0, clampf((item.weight_kg - 5.0) / 30.0, 0.0, 1.0))
	if hands == HandsState.GRABBING:
		rate = 25.0
	_anchor.position = Vector3(0.0, -0.15, -carry_distance)
	var target := _anchor.global_position
	item.global_position = item.global_position.lerp(target, clampf(rate * delta, 0.0, 1.0))
	var lv: Vector3 = _cam.global_transform.basis.inverse() * velocity
	var sway := Basis.from_euler(Vector3(carry_pitch + lv.z * 0.01, carry_yaw, -lv.x * 0.015))
	var want := _cam.global_transform.basis * sway
	item.global_transform.basis = item.global_transform.basis.slerp(want, clampf(rate * delta, 0.0, 1.0)).orthonormalized()


func _find_place_position(item: Grabbable) -> Array:
	_anchor.position = Vector3(0.0, -0.15, -carry_distance)
	var want: Vector3 = _anchor.global_position
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return [want, true]
	var space := world.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(_cam.global_position, want)
	q.exclude = [self, item]
	if space.intersect_ray(q).is_empty():
		var down := PhysicsRayQueryParameters3D.create(want + Vector3.UP * 0.5, want + Vector3.DOWN * 2.5)
		down.exclude = [self, item]
		var floor_hit := space.intersect_ray(down)
		if not floor_hit.is_empty():
			want.y = (floor_hit["position"] as Vector3).y + 0.45
		return [want, true]
	var yaw := _cam.global_rotation.y
	var feet := global_position + Vector3(sin(yaw), 0.0, cos(yaw)) * -0.8
	feet.y = global_position.y - 0.6
	var q2 := PhysicsRayQueryParameters3D.create(global_position, feet)
	q2.exclude = [self, item]
	if space.intersect_ray(q2).is_empty():
		return [feet, true]
	return [feet, false]


var _max_up_angle_view_rad := deg_to_rad(-90.0)
var _max_down_angle_view_rad := deg_to_rad(90.0)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if hands == HandsState.CARRYING and Input.is_action_pressed("adjust_modifier"):
			carry_yaw -= event.relative.x * 0.01
			carry_pitch = clampf(carry_pitch - event.relative.y * 0.01, -1.2, 1.2)
		else:
			_cam.rotation.y += -event.relative.x * .005
			_cam.rotation.x += -event.relative.y * .005
			_cam.rotation.x = clamp(_cam.rotation.x, _max_up_angle_view_rad, _max_down_angle_view_rad)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and hands == HandsState.CARRYING:
			_adjust_carry_distance(0.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and hands == HandsState.CARRYING:
			_adjust_carry_distance(-0.15)

func _adjust_carry_distance(amount: float) -> void:
	if carried_item == null:
		return
	carry_distance = clampf(carry_distance + amount, carried_item.carry_distance_min, carried_item.carry_distance_max)

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("escape_game"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("stun_debug"):
		apply_stun()
		get_viewport().set_input_as_handled()

class_name PlayerController
extends CharacterBody3D

signal health_changed(hp: float)
signal downed_changed(is_down: bool)

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

const MAX_HEALTH := 100.0
const REVIVE_HEALTH := 50.0
const PUNCH_CD := 0.55
const PUNCH_IMPACT := 4.2
const CARRY_CREW_SPEED := 0.55
const CARRY_CREW_DIST := 1.2
const CARRY_PLAYER_SPEED := 0.6
const CREW_SHOULDER_OFFSET := Vector3(0.42, 1.32, 0.06)
const CREW_SHOULDER_PIVOT := Vector3(0.0, 0.95, 0.0)
const PLAYER_CARRY_OFFSET := Vector3(0.42, 1.32, 0.06)
const PLAYER_CARRY_PIVOT := Vector3(0.0, 0.0, 0.9)
const PLAYER_DROP_OFFSET := Vector3(0.7, 0.0, 0.2)
const DOWNED_STUN := 999.0

const WALK_ANIMS := ["walk", "walk_001"]
const WALK_PLAYBACK_SPEED := 3.0
const MODEL_BASE_SCALE := 0.6
const MODEL_YAW_OFFSET := 0.0
const WALK_MOVE_THRESHOLD := 0.5
const MODEL_TURN_SPEED := 12.0

static var _carry_claims: Dictionary = {}

static func claim_carry(target_path: String, carrier_id: int) -> bool:
	if _carry_claims.has(target_path):
		return false
	_carry_claims[target_path] = carrier_id
	return true

static func release_carry(target_path: String, carrier_id: int) -> bool:
	if int(_carry_claims.get(target_path, 0)) != carrier_id:
		return false
	_carry_claims.erase(target_path)
	return true

static func drop_carry_claim(target_path: String) -> void:
	_carry_claims.erase(target_path)

static func carrier_has_claim(carrier_id: int) -> bool:
	for path in _carry_claims.keys():
		if int(_carry_claims[path]) == carrier_id:
			return true
	return false


static func release_carry_claims_for(carrier_id: int) -> Array[String]:
	var paths: Array[String] = []
	for path in _carry_claims.keys():
		if int(_carry_claims[path]) == carrier_id:
			paths.append(str(path))
			_carry_claims.erase(path)
	return paths

static func prune_carry_claims(root: Node) -> void:
	for path in _carry_claims.keys():
		if root.get_node_or_null(NodePath(str(path))) == null:
			_carry_claims.erase(path)

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

var health := MAX_HEALTH
var downed := false
var carrying_loot := false
var carrying_player := false
var captured_by: Node3D = null
var carried_crew: CrewAgent = null
var carried_player: PlayerController = null
var carried_by_player_id: int = 0:
	set(value):
		carried_by_player_id = value
		if is_node_ready():
			_set_carried_pose(value != 0)
var _punch_cd := 0.0
var _step_t := 0.0
var _buffs: Dictionary = {}
var _hold_target: Node = null

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
@onready var _throw_preview: Node3D = get_node_or_null("ThrowPreview")

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
	_set_carried_pose(carried_by_player_id != 0)
	add_to_group("players")
	_ray.collision_mask = 3
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

func is_carrying() -> bool:
	return carrying_loot or carrying_player or carried_item != null or carried_crew != null or carried_player != null

func is_being_carried() -> bool:
	return carried_by_player_id != 0

func get_carried_player() -> PlayerController:
	return carried_player

func is_crouching() -> bool:
	return stance == StanceState.CROUCH

func is_stunned() -> bool:
	return status == StatusState.STUNNED

func is_down() -> bool:
	return downed

func is_captured() -> bool:
	return captured_by != null

func get_health() -> float:
	return health


func get_hold_progress() -> float:
	if _hold_target == null or not is_instance_valid(_hold_target):
		return -1.0
	if _hold_target.has_method("hold_progress"):
		return _hold_target.hold_progress()
	return 0.0


func get_hold_text() -> String:
	if _hold_target != null and is_instance_valid(_hold_target) and _hold_target.has_method("hold_text"):
		return _hold_target.hold_text()
	return "HOLD E"

func speed_factor() -> float:
	var f := 1.0
	if carried_player != null:
		f = CARRY_PLAYER_SPEED
	elif carried_crew != null:
		f = CARRY_CREW_SPEED
	elif carried_item != null:
		f = carried_item.carry_speed_factor
	if _buffs.has("speed"):
		f *= _buffs["speed"]["power"]
	return f

func _jump_velocity() -> float:
	var jv := 0.0
	if carried_crew != null or carried_player != null:
		jv = JUMP_MED
	elif carried_item == null:
		jv = JUMP_EMPTY
	elif carried_item.weight_kg <= 8.0:
		jv = JUMP_LIGHT
	elif carried_item.weight_kg <= 20.0:
		jv = JUMP_MED
	if jv > 0.0 and _buffs.has("jump"):
		jv *= _buffs["jump"]["power"]
	return jv


func add_buff(kind: String, duration: float, power: float = 1.4) -> void:
	_buffs[kind] = {"t": duration, "power": power}
	print("[Buff] ", kind, " for ", duration, "s")


func _tick_buffs(delta: float) -> void:
	var expired: Array[String] = []
	for k in _buffs.keys():
		_buffs[k]["t"] -= delta
		if _buffs[k]["t"] <= 0.0:
			expired.append(k)
	for k in expired:
		_buffs.erase(k)


func emit_noise(loudness: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_server_noise.rpc_id(1, global_position, loudness)
	else:
		NoiseBus.emit_noise(global_position, loudness, self)


@rpc("any_peer")
func _server_noise(pos: Vector3, loudness: float) -> void:
	if multiplayer.is_server():
		NoiseBus.emit_noise(pos, loudness, null)


func take_hit(amount: float, _source: Node = null) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		_rpc_take_hit.rpc_id(get_multiplayer_authority(), amount)
		return
	_apply_damage(amount)


@rpc("any_peer")
func _rpc_take_hit(amount: float) -> void:
	if is_multiplayer_authority():
		_apply_damage(amount)


func _apply_damage(amount: float) -> void:
	if downed:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health)
	apply_stun(STUN_TIME)
	emit_noise(1.0)
	print("[Health] ", int(health), " (-", int(amount), ")")
	if health <= 0.0:
		_go_down()


func _go_down() -> void:
	if downed:
		return
	downed = true
	status = StatusState.STUNNED
	_stun_t = DOWNED_STUN
	stance = StanceState.STAND
	_apply_stance_visual()
	_drop_everything()
	downed_changed.emit(true)
	print("[Health] downed")


func heal(amount: float) -> void:
	health = clampf(health + amount, 0.0, MAX_HEALTH)
	health_changed.emit(health)


func revive(full_heal: bool = false) -> void:
	if not downed:
		return
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		_rpc_revive.rpc_id(get_multiplayer_authority(), full_heal)
		return
	_apply_revive(full_heal)


@rpc("any_peer")
func _rpc_revive(full_heal: bool = false) -> void:
	if not is_multiplayer_authority():
		return
	_apply_revive(full_heal)


func _apply_revive(full_heal: bool = false) -> void:
	if carried_by_player_id != 0:
		_apply_carried(0)
	downed = false
	health = MAX_HEALTH if full_heal else maxf(health, REVIVE_HEALTH)
	status = StatusState.NORMAL
	_stun_t = 0.0
	downed_changed.emit(false)
	health_changed.emit(health)
	print("[Health] revived")


func enter_captured(crew: Node3D) -> void:
	captured_by = crew
	_drop_everything()
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		_rpc_capture.rpc_id(get_multiplayer_authority(), crew.get_path())


@rpc("any_peer")
func _rpc_capture(crew_path: String) -> void:
	if not is_multiplayer_authority():
		return
	captured_by = get_node_or_null(crew_path) as Node3D
	_drop_everything()


func exit_captured() -> void:
	if captured_by == null:
		return
	captured_by = null
	apply_stun(0.8)
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		_rpc_uncapture.rpc_id(get_multiplayer_authority())


@rpc("any_peer")
func _rpc_uncapture() -> void:
	if is_multiplayer_authority():
		captured_by = null


func _drop_everything() -> void:
	if carried_item != null:
		var item := carried_item
		_server_or_direct_release(item, true, Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)))
		carried_item = null
	if carried_crew != null and is_instance_valid(carried_crew):
		var crew := carried_crew
		_server_or_direct_crew_release(crew, false, Vector3.ZERO)
		carried_crew = null
	if carried_player != null:
		_drop_player()
	hands = HandsState.EMPTY
	carrying_loot = false
	carrying_player = false


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
	var impulse := _item_throw_velocity(item) * item.mass
	_server_or_direct_release(item, true, impulse)
	hands = HandsState.THROWING
	_throw_t = THROW_STATE_TIME
	_throw_cd = THROW_CD


func _item_throw_velocity(item: Grabbable) -> Vector3:
	var dir := -_cam.global_transform.basis.z
	var power := clampf(THROW_BASE * 5.0 / maxf(item.weight_kg, 1.0), THROW_MIN, THROW_MAX)
	return (dir * 0.85 + Vector3.UP * 0.5).normalized() * power


func _crew_throw_velocity() -> Vector3:
	var dir := -_cam.global_transform.basis.z
	return (dir * 0.82 + Vector3.UP * 0.58).normalized() * 9.5


func _throw_gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _update_throw_preview() -> void:
	if _throw_preview == null:
		return
	if downed or status == StatusState.STUNNED or captured_by != null or not Input.is_action_pressed("aim_throw"):
		_throw_preview.hide_arc()
		return
	if carried_player != null:
		_throw_preview.hide_arc()
		return
	if carried_crew != null and is_instance_valid(carried_crew):
		_throw_preview.show_arc(carried_crew.global_position, _crew_throw_velocity(), _throw_gravity(), [self, carried_crew])
	elif carried_item != null and is_instance_valid(carried_item):
		_throw_preview.show_arc(carried_item.global_position, _item_throw_velocity(carried_item), _throw_gravity(), [self, carried_item])
	else:
		_throw_preview.hide_arc()


func apply_stun(duration: float = STUN_TIME) -> void:
	status = StatusState.STUNNED
	_stun_t = maxf(_stun_t, duration)
	velocity.x = 0.0
	velocity.z = 0.0
	if carried_player != null:
		var body := carried_player
		_drop_player()
		print("[Hands] stunned, dropped ", body.name)
		return
	if carried_crew != null and is_instance_valid(carried_crew):
		var crew := carried_crew
		carried_crew = null
		_server_or_direct_crew_release(crew, true, Vector3(randf_range(-1.0, 1.0), 2.0, randf_range(-1.0, 1.0)))
		hands = HandsState.EMPTY
		carrying_loot = false
		print("[Hands] stunned, dropped ", crew.name)
	elif hands == HandsState.CARRYING or hands == HandsState.GRABBING:
		var item := carried_item
		if item != null:
			var fling := Vector3(randf_range(-1.0, 1.0), 1.5, randf_range(-1.0, 1.0))
			_server_or_direct_release(item, true, fling)
			hands = HandsState.EMPTY
			carrying_loot = false
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
	if multiplayer.get_remote_sender_id() != 1:
		return
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
	carrying_loot = true
	print("[Hands] grabbed ", item.name)


func _release_local(item: Grabbable, thrown: bool, impulse: Vector3) -> void:
	if item.broken.is_connected(_on_carried_broken):
		item.broken.disconnect(_on_carried_broken)
	item.set_net_authority(1)
	item.release(thrown, impulse)
	if carried_item == item:
		carried_item = null
	hands = HandsState.EMPTY
	carrying_loot = false


func _on_carried_broken(item: Grabbable) -> void:
	print("[Hands] ", item.name, " broke! value lost.")
	if carried_item == item:
		carried_item = null
		hands = HandsState.EMPTY
		carrying_loot = false

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_tick_buffs(delta)

	if captured_by != null:
		if is_instance_valid(captured_by) and captured_by.has_method("get_capture_position"):
			global_position = captured_by.get_capture_position()
		else:
			captured_by = null
		velocity = Vector3.ZERO
		_authority_anim_update(delta)
		return

	if carried_by_player_id != 0:
		_follow_carrier(delta)
		_authority_anim_update(delta)
		return

	if downed:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		_authority_anim_update(delta)
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
		_update_throw_preview()
		return
	if carried_by_player_id != 0 or downed:
		_prev_pos = global_position
		_update_walk_visual(false, Vector3.ZERO, delta)
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
	if carried_by_player_id != 0 or downed:
		_prev_pos = global_position
		_update_walk_visual(false, Vector3.ZERO, delta)
		return
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

	_emit_footsteps(delta)


func _emit_footsteps(delta: float) -> void:
	if not is_on_floor() or Vector2(velocity.x, velocity.z).length() < 0.6:
		_step_t = 0.0
		return
	_step_t -= delta
	if _step_t > 0.0:
		return
	_step_t = 0.34 if stance == StanceState.SPRINT else 0.5
	if stance == StanceState.CROUCH:
		emit_noise(0.22)
	elif stance == StanceState.SPRINT:
		emit_noise(1.35)
	else:
		emit_noise(0.65)


func _accel_factor() -> float:
	if carried_crew != null:
		return 0.65
	if carried_item == null:
		return 1.0
	return lerpf(1.0, 0.55, clampf((carried_item.weight_kg - 5.0) / 30.0, 0.0, 1.0))


func _camera_feel_step(delta: float, was_floor: bool, pre_y: float) -> void:
	if not was_floor and is_on_floor() and pre_y < -1.0:
		_land_dip = minf(_land_dip + clampf(-pre_y * LAND_DIP_GAIN, 0.0, LAND_DIP_MAX), 0.16)
		emit_noise(clampf(-pre_y * 0.16, 0.4, 1.3))
	_land_dip = lerpf(_land_dip, 0.0, clampf(delta * 10.0, 0.0, 1.0))
	_cam.position.y += _land_dip
	var want_fov := _base_fov
	if stance == StanceState.SPRINT and Vector2(velocity.x, velocity.z).length() > 1.0:
		want_fov += SPRINT_FOV_BONUS
	_cam.fov = lerpf(_cam.fov, want_fov, clampf(delta * 5.0, 0.0, 1.0))
	if _buffs.has("drunk"):
		var t := Time.get_ticks_msec() * 0.001
		_cam.rotation.z = sin(t * 2.1) * 0.06 + sin(t * 0.7) * 0.03
	else:
		_cam.rotation.z = lerp_angle(_cam.rotation.z, 0.0, clampf(delta * 6.0, 0.0, 1.0))


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


func _update_hold(delta: float) -> void:
	if _hold_target == null or not is_instance_valid(_hold_target):
		_hold_target = null
		return
	if not Input.is_action_pressed("grab"):
		_end_hold()
		return
	_ray.force_raycast_update()
	if _ray.get_collider() != _hold_target:
		_end_hold()
		return
	if _hold_target.has_method("interact_hold"):
		_hold_target.interact_hold(self, delta)
	if _hold_target != null and _hold_target.has_method("wants_hold") and not _hold_target.wants_hold():
		_hold_target = null


func _end_hold() -> void:
	var target := _hold_target
	_hold_target = null
	if target != null and is_instance_valid(target) and target.has_method("interact_end"):
		target.interact_end(self, true)


func _hands_step(delta: float) -> void:
	_punch_cd = maxf(0.0, _punch_cd - delta)
	if _throw_t > 0.0:
		_throw_t -= delta
		if _throw_t <= 0.0 and hands == HandsState.THROWING:
			hands = HandsState.EMPTY
	if status == StatusState.STUNNED:
		_end_hold()
		return

	if Input.is_action_just_pressed("lock_door"):
		_ray.force_raycast_update()
		var lock_col := _ray.get_collider()
		if lock_col is Door and (lock_col as Door).lockable:
			(lock_col as Door).toggle_lock()

	if _hold_target != null:
		_update_hold(delta)
		return

	if carried_crew != null and not is_instance_valid(carried_crew):
		carried_crew = null
		hands = HandsState.EMPTY
		carrying_loot = false

	if carried_player != null and not is_instance_valid(carried_player):
		carried_player = null
		carrying_player = false
		hands = HandsState.EMPTY
		carrying_loot = false
	if carried_player != null and not carried_player.is_down():
		_drop_player()

	if carried_player != null:
		if Input.is_action_just_pressed("grab"):
			_ray.force_raycast_update()
			var col := _ray.get_collider()
			if col is MedStation:
				(col as MedStation).interact(self)
				if carried_player != null and carried_player.is_down():
					return
			if carried_player != null:
				_drop_player()
		return

	if carried_crew != null:
		if Input.is_action_just_pressed("grab"):
			_drop_crew()
		elif Input.is_action_just_pressed("throw_item"):
			_throw_crew()
		else:
			_follow_carried_crew(delta)
		return

	if hands == HandsState.EMPTY and Input.is_action_just_pressed("grab"):
		_ray.force_raycast_update()
		var col := _ray.get_collider()
		var hit := col as Grabbable
		if hit != null:
			if not try_grab_target(hit):
				print("[Hands] grab denied: ", hit.name)
		elif col is CrewAgent:
			var crew := col as CrewAgent
			if crew.can_be_lifted():
				_server_or_direct_crew_grab(crew)
			else:
				print("[Hands] crew not liftable (", crew.state_name(), ")")
		elif col != null and col.has_method("interact_begin"):
			col.interact_begin(self)
			_hold_target = col
		elif col != null and col.has_method("interact"):
			col.interact(self)
		elif col is PlayerController:
			var other := col as PlayerController
			if other != self and other.is_down() and not other.is_being_carried():
				_server_or_direct_player_grab(other)
	elif hands == HandsState.EMPTY and Input.is_action_just_pressed("aim_throw"):
		_punch()
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


func _punch() -> void:
	if _punch_cd > 0.0:
		return
	_punch_cd = PUNCH_CD
	_land_dip = minf(_land_dip + 0.035, 0.16)
	_ray.force_raycast_update()
	var col := _ray.get_collider()
	emit_noise(1.25)
	if col is CrewAgent:
		_hit_crew(col as CrewAgent, PUNCH_IMPACT)
	elif col != null and col.has_method("interact"):
		col.interact(self)
	elif col is Grabbable:
		pass


func _hit_crew(crew: CrewAgent, impact: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		crew.request_impact.rpc_id(1, impact)
	else:
		crew.receive_impact(impact, self)


func _server_or_direct_crew_grab(crew: CrewAgent) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		crew.set_net_authority(_my_id())
		_attach_crew(crew)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_remote_crew_grab.rpc(crew.get_path(), _my_id())
	else:
		_grab_pending = true
		_pending_t = 2.0
		server_request_crew_grab.rpc_id(1, crew.get_path())


@rpc("any_peer")
func server_request_crew_grab(crew_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var crew := get_node_or_null(crew_path) as CrewAgent
	if crew == null or not crew.can_be_lifted():
		_grab_denied.rpc_id(sender)
		return
	crew.grab_by(sender)
	crew.set_net_authority(sender)
	_client_crew_granted.rpc_id(sender, crew_path)
	_remote_crew_grab.rpc(crew_path, sender)


@rpc("any_peer")
func _remote_crew_grab(crew_path: String, sender: int) -> void:
	if sender == _my_id():
		return
	var crew := get_node_or_null(crew_path) as CrewAgent
	if crew == null:
		return
	crew.grab_by(sender)
	crew.set_net_authority(sender)


@rpc("any_peer")
func _client_crew_granted(crew_path: String) -> void:
	_grab_pending = false
	_pending_t = 0.0
	var crew := get_node_or_null(crew_path) as CrewAgent
	if crew == null:
		return
	_attach_crew(crew)


func _attach_crew(crew: CrewAgent) -> void:
	if carried_item != null:
		place_carried()
	carried_crew = crew
	hands = HandsState.CARRYING
	_grab_t = 0.0
	carry_distance = CARRY_CREW_DIST
	carrying_loot = true
	crew.grab_by(_my_id())
	print("[Hands] hoisted ", crew.name)


func _drop_crew() -> void:
	if carried_crew == null:
		return
	var crew := carried_crew
	carried_crew = null
	hands = HandsState.EMPTY
	carrying_loot = false
	_anchor.position = Vector3(0.0, -0.15, -CARRY_CREW_DIST)
	crew.global_position = _anchor.global_position
	crew.rotation.x = 0.0
	crew.rotation.z = 0.0
	_server_or_direct_crew_release(crew, false, Vector3.ZERO)


func _throw_crew() -> void:
	if carried_crew == null:
		return
	var crew := carried_crew
	carried_crew = null
	hands = HandsState.THROWING
	_throw_t = THROW_STATE_TIME
	carrying_loot = false
	crew.global_transform = _crew_shoulder_transform()
	_server_or_direct_crew_release(crew, true, _crew_throw_velocity())


func _server_or_direct_crew_release(crew: CrewAgent, thrown: bool, impulse: Vector3) -> void:
	var pos := crew.global_position
	var rot := Vector3(0.0, crew.global_rotation.y, 0.0)
	var releaser := _my_id()
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		crew.global_transform = Transform3D(Basis.from_euler(rot), pos)
		crew.release_from_carry(thrown, impulse)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_remote_crew_release.rpc(crew.get_path(), thrown, impulse, pos, rot, releaser)
	else:
		crew.global_transform = Transform3D(Basis.from_euler(rot), pos)
		crew.release_from_carry(thrown, impulse)
		server_crew_release.rpc_id(1, crew.get_path(), thrown, impulse, pos, rot)


@rpc("any_peer")
func server_crew_release(crew_path: String, thrown: bool, impulse: Vector3, pos: Vector3, rot: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var crew := get_node_or_null(crew_path) as CrewAgent
	if crew == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	rot.x = 0.0
	rot.z = 0.0
	crew.global_transform = Transform3D(Basis.from_euler(rot), pos)
	crew.release_from_carry(thrown, impulse)
	_remote_crew_release.rpc(crew_path, thrown, impulse, pos, rot, sender)


@rpc("any_peer")
func _remote_crew_release(crew_path: String, thrown: bool, impulse: Vector3, pos: Vector3, rot: Vector3, releaser: int) -> void:
	if releaser == _my_id():
		return
	var crew := get_node_or_null(crew_path) as CrewAgent
	if crew == null:
		return
	rot.x = 0.0
	rot.z = 0.0
	crew.global_transform = Transform3D(Basis.from_euler(rot), pos)
	crew.release_from_carry(thrown, impulse)


func _crew_shoulder_transform() -> Transform3D:
	var basis := global_transform.basis * Basis(Vector3.RIGHT, PI * 0.5)
	var shoulder := global_position + global_transform.basis * CREW_SHOULDER_OFFSET
	return Transform3D(basis, shoulder - basis * CREW_SHOULDER_PIVOT)


func _follow_carried_crew(delta: float) -> void:
	var crew := carried_crew
	if crew == null or not is_instance_valid(crew):
		return
	if multiplayer.has_multiplayer_peer() and not crew.is_multiplayer_authority():
		return
	var target := _crew_shoulder_transform()
	var t := clampf(20.0 * delta, 0.0, 1.0)
	crew.global_position = crew.global_position.lerp(target.origin, t)
	crew.global_transform.basis = crew.global_transform.basis.slerp(target.basis, t).orthonormalized()


func _server_or_direct_player_grab(target: PlayerController) -> void:
	if _grab_pending:
		return
	if target == null or target == self or not target.is_down() or target.is_captured() or target.is_being_carried():
		return
	if downed or captured_by != null or is_carrying():
		return
	if global_position.distance_to(target.global_position) > 3.0:
		return
	if not multiplayer.has_multiplayer_peer():
		_attach_player(target)
		target.set_carried_by_player(_my_id())
	elif multiplayer.is_server():
		if not claim_carry(str(target.get_path()), _my_id()):
			return
		_attach_player(target)
		target.set_carried_by_player(_my_id())
	else:
		_grab_pending = true
		_pending_t = 2.0
		server_request_player_grab.rpc_id(1, target.get_path())


@rpc("any_peer")
func server_request_player_grab(target_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	var target := get_node_or_null(target_path) as PlayerController
	if target == null or not target.is_down() or target.is_captured() or target.is_being_carried():
		_grab_denied.rpc_id(sender)
		return
	if downed or captured_by != null or is_carrying():
		_grab_denied.rpc_id(sender)
		return
	if global_position.distance_to(target.global_position) > 3.0:
		_grab_denied.rpc_id(sender)
		return
	if carrier_has_claim(sender):
		_grab_denied.rpc_id(sender)
		return
	for n in get_tree().get_nodes_in_group("players"):
		var other := n as PlayerController
		if other != null and other != self and other.carried_by_player_id == sender:
			_grab_denied.rpc_id(sender)
			return
	if not claim_carry(str(target.get_path()), sender):
		_grab_denied.rpc_id(sender)
		return
	target.set_carried_by_player(sender)
	_client_player_granted.rpc_id(sender, target_path)


@rpc("any_peer")
func _client_player_granted(target_path: String) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_grab_pending = false
	_pending_t = 0.0
	var target := get_node_or_null(target_path) as PlayerController
	if target != null:
		_attach_player(target)


func _attach_player(target: PlayerController) -> void:
	if target == null or target == self or not target.is_down() or target.is_captured():
		return
	if target.is_being_carried() and target.carried_by_player_id != _my_id():
		return
	if carried_item != null:
		place_carried()
	if carried_crew != null:
		_drop_crew()
	carried_player = target
	carrying_player = true
	hands = HandsState.CARRYING
	carrying_loot = false
	_grab_pending = false
	_pending_t = 0.0
	print("[Hands] hoisted player ", target.name)


@rpc("any_peer")
func server_release_player(target_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var target := get_node_or_null(target_path) as PlayerController
	if target == null:
		drop_carry_claim(target_path)
		return
	if int(_carry_claims.get(target_path, 0)) != sender and target.carried_by_player_id != sender:
		return
	release_carry(target_path, sender)
	target.set_carried_by_player(0)


func _drop_player() -> void:
	if carried_player == null:
		return
	if not is_instance_valid(carried_player):
		carried_player = null
		carrying_player = false
		hands = HandsState.EMPTY
		carrying_loot = false
		return
	var target := carried_player
	carried_player = null
	carrying_player = false
	hands = HandsState.EMPTY
	carrying_loot = false
	if not multiplayer.has_multiplayer_peer():
		target.set_carried_by_player(0)
	elif multiplayer.is_server():
		release_carry(str(target.get_path()), _my_id())
		target.set_carried_by_player(0)
	else:
		server_release_player.rpc_id(1, target.get_path())
	print("[Hands] put down player ", target.name)


func drop_carried_player() -> void:
	_drop_player()


func _follow_carrier(delta: float) -> void:
	var carrier := _find_player_by_id(carried_by_player_id)
	if carrier == null:
		_apply_carried(0)
		return
	var shoulder := carrier.global_position + carrier.global_transform.basis * PLAYER_CARRY_OFFSET
	var target := shoulder - carrier.global_transform.basis * PLAYER_CARRY_PIVOT
	global_position = global_position.lerp(target, clampf(18.0 * delta, 0.0, 1.0))
	global_rotation.y = carrier.global_rotation.y


func _find_player_by_id(id: int) -> PlayerController:
	if id == 0:
		return null
	for n in get_tree().get_nodes_in_group("players"):
		if n.name == str(id):
			return n as PlayerController
	return null


func set_carried_by_player(carrier_id: int) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		_rpc_set_carried.rpc_id(get_multiplayer_authority(), carrier_id)
		return
	_apply_carried(carrier_id)


@rpc("any_peer")
func _rpc_set_carried(carrier_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if carrier_id != 0:
		if sender != 1:
			return
	elif sender != 0 and sender != 1 and sender != carried_by_player_id:
		return
	_apply_carried(carrier_id)


func _apply_carried(carrier_id: int) -> void:
	if carrier_id == carried_by_player_id:
		return
	if carrier_id != 0:
		if not downed or captured_by != null or carried_by_player_id != 0:
			return
	var old_carrier: PlayerController = null
	if carried_by_player_id != 0:
		old_carrier = _find_player_by_id(carried_by_player_id)
	carried_by_player_id = carrier_id
	if carrier_id == 0 and old_carrier != null:
		global_position = old_carrier.global_position + old_carrier.global_transform.basis * PLAYER_DROP_OFFSET


func _set_carried_pose(carried: bool) -> void:
	if _col != null:
		_col.disabled = carried
	if _model != null:
		_model.rotation.x = PI * 0.5 if carried else 0.0
		_model.rotation.z = 0.0


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
		if hands == HandsState.CARRYING and Input.is_action_pressed("rotate_item"):
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

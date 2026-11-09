class_name CrewAgent
extends CharacterBody3D

signal gone
signal state_changed(new_state: int)

enum State { IDLE, PATROL, SUSPICIOUS, HOSTILE, STUNNED, CARRIED, AIRBORNE, GONE }

const GRAVITY := 18.0
const ACCEL := 22.0
const STOP_FRICTION := 26.0
const OFFBOARD_Y := -3.0
const ATTACK_WINDUP := 0.35
const ATTACK_RECOVER := 0.9

@export var crew_name := "Crew"
@export var move_speed := 2.9
@export var chase_speed := 4.4
@export var patrol_radius := 11.0
@export var separation_radius := 2.8
@export var separation_weight := 1.6
@export var arena_extent := 19.0
@export var vision_range := 15.0
@export var vision_angle_deg := 105.0
@export var hearing_range := 13.0
@export var attack_range := 1.9
@export var attack_damage := 30.0
@export var stun_time := 5.0
@export var capture_guard_time := Vector2(10.0, 20.0)

const PERCEIVE_INTERVAL := 0.12
const AVOID_INTERVAL := 0.05
const SEPARATION_INTERVAL := 0.1

var state: State = State.IDLE
var net_state: int = State.IDLE
var _home := Vector3.ZERO
var _patrol_target := Vector3.ZERO
var _investigate_pos := Vector3.ZERO
var _target: Node3D = null
var _seen: Node3D = null
var _captive: Node3D = null
var _guard_point := Vector3.ZERO
var _guard_brig: Node = null
var _capture_stage := 0

var _idle_t := 0.0
var _stun_t := 0.0
var _attack_cd := 0.0
var _think_t := 0.0
var _air_t := 0.0
var _guard_t := 0.0
var _capture_cd := 0.0
var _suspicion_t := 0.0
var _capturing := false
var _guarding := false
var _carried := false
var _carrier_id := -1
var _haul_item: Grabbable = null
var _hauling := false
var _scan_t := 0.0
var _resting := false
var _prev_layer := 1
var _prev_mask := 1
var _walk_t := 0.0
var _visual_pos := Vector3.ZERO
var _visual_basis := Basis.IDENTITY

var _perceive_t := 0.0
var _avoid_t := 0.0
var _cached_avoid_dir := Vector3.ZERO
var _sep_t := 0.0
var _cached_separation := Vector3.ZERO
var _los_query: PhysicsRayQueryParameters3D
var _avoid_query: PhysicsRayQueryParameters3D
var _floor_query: PhysicsRayQueryParameters3D
var _cached_restricted: Array[Node] = []

@onready var _model: Node3D = $Visual/Model
@onready var _visual: Node3D = $Visual
@onready var _label: Label3D = $StateLabel
@onready var _col: CollisionShape3D = $CollisionShape3D

func _enter_tree() -> void:
	if str(name).begins_with("Crew"):
		var id := str(name).trim_prefix("Crew")
		if id.is_valid_int():
			crew_name = "Crew %s" % id

func _ready() -> void:
	_home = global_position
	_visual_pos = global_position
	_visual_basis = global_transform.basis
	_prev_layer = collision_layer
	_prev_mask = collision_mask
	add_to_group("crew")
	if NoiseBus.noise_emitted.is_connected(_on_noise) == false:
		NoiseBus.noise_emitted.connect(_on_noise)
	_los_query = PhysicsRayQueryParameters3D.new()
	_los_query.collision_mask = 1
	_los_query.exclude = [self]
	_avoid_query = PhysicsRayQueryParameters3D.new()
	_avoid_query.collision_mask = 1
	_avoid_query.exclude = [self]
	_floor_query = PhysicsRayQueryParameters3D.new()
	_floor_query.collision_mask = 1
	_floor_query.exclude = [self]
	_perceive_t = randf_range(0.0, PERCEIVE_INTERVAL)
	_sep_t = randf_range(0.0, SEPARATION_INTERVAL)
	_update_label()
	_idle_t = randf_range(0.3, 2.0)


func _ai_active() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _physics_process(delta: float) -> void:
	if state == State.GONE:
		return
	if _carried:
		_tick_visuals(delta)
		if not _ai_active():
			_update_remote_visual(delta)
		return
	if not _ai_active():
		if net_state != state:
			state = net_state as State
			_update_label()
		_tick_visuals(delta)
		_update_remote_visual(delta)
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_capture_cd = maxf(0.0, _capture_cd - delta)
	_think_t = maxf(0.0, _think_t - delta)
	_air_t = maxf(0.0, _air_t - delta)
	_scan_t = maxf(0.0, _scan_t - delta)
	_avoid_t = maxf(0.0, _avoid_t - delta)
	_sep_t = maxf(0.0, _sep_t - delta)
	_perceive_t = maxf(0.0, _perceive_t - delta)

	if not _carried and state != State.AIRBORNE:
		if absf(rotation.x) > 0.001 or absf(rotation.z) > 0.001:
			snap_upright()

	if state == State.AIRBORNE:
		_airborne_step(delta)
		return

	if state == State.STUNNED:
		_stun_t -= delta
		velocity.x = move_toward(velocity.x, 0.0, STOP_FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, STOP_FRICTION * delta)
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		if _stun_t <= 0.0:
			snap_upright()
			_set_state(State.PATROL)
			_pick_patrol_point()
		return

	if _perceive_t <= 0.0:
		_perceive_t = PERCEIVE_INTERVAL
		_perceive(delta)

	_think(delta)
	_tick_visuals(delta)
	_check_offboard()


func _airborne_step(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	move_and_slide()
	_tick_visuals(delta)
	if global_position.y < OFFBOARD_Y:
		_go_gone()
		return
	if is_on_floor() and _air_t <= 0.0:
		velocity = Vector3.ZERO
		snap_upright()
		_set_state(State.STUNNED)
		_stun_t = 3.0
		NoiseBus.emit_noise(global_position, 1.1, self)


func _perceive(_delta: float) -> void:
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p == null or not is_instance_valid(p):
			continue
		if p.has_method("is_down") and p.is_down():
			continue
		var to := p.global_position - global_position
		to.y = 0.0
		var d := to.length()
		var rng := vision_range
		if p.has_method("is_crouching") and p.is_crouching():
			rng *= 0.55
		if d > rng or d < 0.01:
			continue
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.01:
			fwd = Vector3.FORWARD
		if rad_to_deg(fwd.normalized().angle_to(to.normalized())) > vision_angle_deg * 0.5:
			continue
		if not _has_los(p):
			continue
		if d < best_d:
			best = p
			best_d = d

	_seen = best
	if best != null:
		var carrying: bool = best.has_method("is_carrying") and bool(best.is_carrying())
		var captured: bool = best.has_method("is_captured") and bool(best.is_captured())
		var restricted := false
		if _cached_restricted.is_empty():
			_cached_restricted = get_tree().get_nodes_in_group("restricted_areas")
		for a in _cached_restricted:
			var area := a as RestrictedArea
			if area != null and area.contains(best):
				restricted = true
				break
		if carrying or captured or restricted:
			_become_hostile(best)
		elif state == State.HOSTILE:
			_target = best
		elif state == State.SUSPICIOUS and _haul_item == null:
			if global_position.distance_to(best.global_position) < 7.0 and _has_los(best):
				_face_toward(best.global_position, 0.5)
				_idle_t = randf_range(1.5, 3.0)
				_set_state(State.IDLE)

	if (state == State.IDLE or state == State.PATROL) and _haul_item == null:
		_scan_for_missing_loot()


func _scan_for_missing_loot() -> void:
	if _scan_t > 0.0:
		return
	_scan_t = 0.6
	for n in get_tree().get_nodes_in_group("grabbables"):
		var g := n as Grabbable
		if g == null or g.is_carried or g.is_secured or g.is_broken:
			continue
		if g.carrier_id != -1:
			continue
		if g.global_position.distance_to(g.origin_transform.origin) < 2.0:
			continue
		if global_position.distance_to(g.global_position) > vision_range:
			continue
		if not _has_los(g):
			continue
		_haul_item = g
		_become_suspicious(g.global_position)
		return


func _become_suspicious(pos: Vector3) -> void:
	if state == State.HOSTILE or state == State.STUNNED or state == State.CARRIED:
		return
	_investigate_pos = pos
	_suspicion_t = 6.0
	_set_state(State.SUSPICIOUS)


func _become_hostile(target: Node3D) -> void:
	if state == State.GONE or state == State.STUNNED or state == State.CARRIED:
		return
	var was_hostile := state == State.HOSTILE
	_target = target
	_guarding = false
	_clear_haul()
	_set_state(State.HOSTILE)
	if not was_hostile:
		NoiseBus.emit_noise(global_position, 2.0, self)

func _has_los(target: Node3D) -> bool:
	var world := get_world_3d()
	if world == null or target == null:
		return true
	_los_query.from = global_position + Vector3.UP * 1.5
	_los_query.to = target.global_position + Vector3.UP * 1.2
	_los_query.exclude = [self]
	return world.direct_space_state.intersect_ray(_los_query).is_empty()

func _on_noise(pos: Vector3, loudness: float, source: Node) -> void:
	if state == State.GONE or state == State.CARRIED or state == State.STUNNED:
		return
	if source == self:
		return
	if source is CrewAgent:
		return
	if loudness < 0.75:
		return
	if global_position.distance_to(pos) > hearing_range * loudness:
		return
	if state == State.HOSTILE:
		return
	if state == State.SUSPICIOUS and loudness < 1.2:
		return
	_become_suspicious(pos)


func _think(delta: float) -> void:
	match state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, STOP_FRICTION * delta)
			velocity.z = move_toward(velocity.z, 0.0, STOP_FRICTION * delta)
			var separation := _separation()
			if separation.length_squared() > 0.01:
				_patrol_target = _clamp_arena(global_position + separation.normalized() * 3.0)
				_set_state(State.PATROL)
				return
			_idle_t -= delta
			if _idle_t <= 0.0:
				_pick_patrol_point()
				_set_state(State.PATROL)
		State.PATROL:
			if _move_to(_patrol_target, move_speed, delta):
				_set_state(State.IDLE)
				_idle_t = randf_range(1.0, 4.0)
		State.SUSPICIOUS:
			if _haul_item != null:
				_haul_step(delta)
				return
			_suspicion_t -= delta
			var to_investigate := _investigate_pos - global_position
			to_investigate.y = 0.0
			var arrived := to_investigate.length() < 2.0
			if arrived or _move_to(_investigate_pos, move_speed * 1.15, delta) or _suspicion_t <= 0.0:
				velocity.x = move_toward(velocity.x, 0.0, STOP_FRICTION * delta)
				velocity.z = move_toward(velocity.z, 0.0, STOP_FRICTION * delta)
				_idle_t = randf_range(1.5, 3.0)
				_set_state(State.IDLE)
		State.HOSTILE:
			_hostile_step(delta)


func _hostile_step(delta: float) -> void:
	if _guarding:
		_guard_t -= delta
		velocity.x = move_toward(velocity.x, 0.0, STOP_FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, STOP_FRICTION * delta)
		if _guard_t <= 0.0:
			_guarding = false
			_unlock_brig()
			_set_state(State.PATROL)
			_pick_patrol_point()
		return

	if _capturing:
		_capture_step(delta)
		return

	if _target == null or not is_instance_valid(_target):
		_target = _seen
	if _target == null or not is_instance_valid(_target):
		_set_state(State.PATROL)
		_pick_patrol_point()
		return

	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()

	if dist < attack_range + 1.2 and _target.has_method("is_stunned") and _target.is_stunned() \
			and not _target.is_carrying() and not _target.is_captured() \
			and _capture_cd <= 0.0 and not _target.is_down():
		_begin_capture(_target)
		return

	if dist <= attack_range and _has_los(_target):
		velocity.x = move_toward(velocity.x, 0.0, STOP_FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, STOP_FRICTION * delta)
		_face_toward(_target.global_position, delta)
		if _attack_cd <= 0.0:
			_swing_wrench(_target)
		return

	if dist > 30.0:
		_target = null
		_set_state(State.PATROL)
		_pick_patrol_point()
		return

	_move_to(_target.global_position, chase_speed, delta)


func _swing_wrench(target: Node3D) -> void:
	_attack_cd = ATTACK_WINDUP + ATTACK_RECOVER
	NoiseBus.emit_noise(global_position, 1.3, self)
	if target.has_method("take_hit"):
		target.take_hit(attack_damage, self)
	if _model.has_method("play_swing"):
		_model.play_swing()


func _begin_capture(target: Node3D) -> void:
	if not target.has_method("enter_captured"):
		return
	_captive = target
	_capturing = true
	_capture_stage = 1
	_guard_brig = get_tree().get_first_node_in_group("brigs")
	if _guard_brig != null and _guard_brig.has_method("get_capture_point"):
		_capture_stage = 0
		_guard_point = _guard_brig.get_guard_point() if _guard_brig.has_method("get_guard_point") else _guard_brig.get_capture_point()
		if _guard_brig.has_method("open_door"):
			_guard_brig.open_door()
	else:
		_guard_brig = null
		_guard_point = _pick_point_near(global_position, 7.0, 13.0)
	target.enter_captured(self)
	_set_state(State.HOSTILE)
	NoiseBus.emit_noise(global_position, 1.2, self)


func _capture_step(delta: float) -> void:
	if _captive == null or not is_instance_valid(_captive):
		_cancel_capture()
		return
	if _captive.has_method("is_captured") and not _captive.is_captured():
		_cancel_capture()
		return
	if _capture_stage == 0:
		if _move_to(_guard_point, chase_speed * 0.9, delta):
			_capture_stage = 1
			if _guard_brig != null and is_instance_valid(_guard_brig) and _guard_brig.has_method("get_capture_point"):
				_guard_point = _guard_brig.get_capture_point()
		return
	if _move_to(_guard_point, chase_speed * 0.9, delta):
		_release_captive()
		if _guard_brig != null and is_instance_valid(_guard_brig):
			if _guard_brig.has_method("lock"):
				_guard_brig.lock(true)
			if _guard_brig.has_method("get_guard_point"):
				global_position = _guard_brig.get_guard_point()
		_guarding = true
		_guard_t = randf_range(capture_guard_time.x, capture_guard_time.y)
		_capture_cd = _guard_t + 4.0


func _release_captive() -> void:
	if _captive != null and is_instance_valid(_captive) and _captive.has_method("exit_captured"):
		_captive.exit_captured()
	_captive = null
	_capturing = false
	_capture_stage = 0


func _cancel_capture() -> void:
	_captive = null
	_capturing = false
	_capture_stage = 0
	_capture_cd = 4.0
	_unlock_brig()
	_set_state(State.PATROL)
	_pick_patrol_point()


func _unlock_brig() -> void:
	if _guard_brig != null and is_instance_valid(_guard_brig) and _guard_brig.has_method("lock"):
		_guard_brig.lock(false)
	_guard_brig = null


func get_capture_position() -> Vector3:
	var back := global_transform.basis.z
	back.y = 0.0
	if back.length() < 0.01:
		back = Vector3.BACK
	return global_position + back.normalized() * 0.95 + Vector3.UP * 0.05


func _haul_step(delta: float) -> void:
	if _haul_item == null or not is_instance_valid(_haul_item):
		_clear_haul()
		_set_state(State.IDLE)
		return
	var item := _haul_item
	if item.is_secured or item.is_broken:
		_clear_haul()
		_set_state(State.IDLE)
		return
	if item.carrier_id != -1 and not _hauling:
		_clear_haul()
		_set_state(State.IDLE)
		return

	if not _hauling:
		var flat := item.global_position - global_position
		flat.y = 0.0
		if flat.length() < 1.25:
			_hauling = true
			item.set_net_authority(1)
			item.grab_by(1)
			_carry_haul_item()
			NoiseBus.emit_noise(global_position, 0.5, self)
			return
		_move_to(item.global_position, move_speed * 1.25, delta)
		return

	_carry_haul_item()
	var origin := item.origin_transform.origin
	if _move_to(origin, move_speed * 0.8, delta):
		_finish_haul()


func _carry_haul_item() -> void:
	if _haul_item == null or not is_instance_valid(_haul_item):
		return
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	_haul_item.global_position = global_position + fwd.normalized() * 0.8 + Vector3.UP * 1.05
	_haul_item.global_rotation = Vector3(0.0, rotation.y, 0.0)


func _finish_haul() -> void:
	var item := _haul_item
	_haul_item = null
	_hauling = false
	if item != null and is_instance_valid(item):
		var origin := item.origin_transform.origin
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.01:
			fwd = Vector3.FORWARD
		global_position = origin - fwd.normalized() * 1.4
		item.global_transform = item.origin_transform
		item.release(false, Vector3.ZERO)
		print("[Crew] returned ", item.name, " to its spot")
	_set_state(State.PATROL)
	_pick_patrol_point()


func _clear_haul() -> void:
	if _haul_item != null and is_instance_valid(_haul_item) and _hauling:
		_haul_item.release(false, Vector3.ZERO)
	_haul_item = null
	_hauling = false


func _move_to(target: Vector3, speed: float, delta: float) -> bool:
	if state == State.PATROL:
		target = _clamp_arena(target)
	var to := target - global_position
	to.y = 0.0
	if to.length() < 0.35:
		velocity.x = move_toward(velocity.x, 0.0, STOP_FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, STOP_FRICTION * delta)
		_apply_gravity(delta)
		move_and_slide()
		return true

	var dir := (to.normalized() + _separation() * separation_weight).normalized()
	dir = _avoid(dir)
	var wish := dir * speed
	velocity.x = move_toward(velocity.x, wish.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, wish.z, ACCEL * delta)
	_apply_gravity(delta)
	move_and_slide()
	_face_toward(global_position + dir, delta)
	_emit_footsteps(delta, speed)
	return false


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta


func _clamp_arena(p: Vector3) -> Vector3:
	p.x = clampf(p.x, -arena_extent, arena_extent)
	p.z = clampf(p.z, -arena_extent, arena_extent)
	return p


func _separation() -> Vector3:
	if _sep_t > 0.0:
		return _cached_separation
	_sep_t = SEPARATION_INTERVAL
	var push := Vector3.ZERO
	for n in get_tree().get_nodes_in_group("crew"):
		var other := n as CrewAgent
		if other == null or other == self or other.is_gone() or other.is_carried():
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var d := away.length()
		if d < 0.01 or d >= separation_radius:
			continue
		push += away / d * (1.0 - d / separation_radius)

	if state != State.HOSTILE:
		for p_node in get_tree().get_nodes_in_group("players"):
			var player := p_node as Node3D
			if player == null or not is_instance_valid(player):
				continue
			var away_player := global_position - player.global_position
			away_player.y = 0.0
			var pd := away_player.length()
			if pd < 0.01 or pd >= 2.2:
				continue
			push += (away_player / pd) * (1.0 - pd / 2.2) * 2.5

	_cached_separation = push
	return push


func _avoid(dir: Vector3) -> Vector3:
	if _avoid_t > 0.0:
		return _cached_avoid_dir
	_avoid_t = AVOID_INTERVAL
	var world := get_world_3d()
	if world == null:
		_cached_avoid_dir = dir
		return dir
	var origin := global_position + Vector3.UP * 0.9
	var space := world.direct_space_state

	_avoid_query.from = origin
	_avoid_query.to = origin + dir * 1.1
	_avoid_query.exclude = [self]
	if space.intersect_ray(_avoid_query).is_empty():
		_cached_avoid_dir = dir
		return dir

	for angle in [deg_to_rad(32.0), deg_to_rad(-32.0)]:
		var probe := dir.rotated(Vector3.UP, angle)
		_avoid_query.to = origin + probe * 1.35
		if space.intersect_ray(_avoid_query).is_empty():
			_cached_avoid_dir = probe
			return probe

	_cached_avoid_dir = dir.rotated(Vector3.UP, deg_to_rad(70.0))
	return _cached_avoid_dir


func _face_toward(pos: Vector3, delta: float) -> void:
	var flat := pos - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.01:
		return
	var want := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(10.0 * delta, 0.0, 1.0))


func _emit_footsteps(delta: float, speed: float) -> void:
	if not is_on_floor():
		return
	_walk_t -= delta
	if _walk_t > 0.0:
		return
	_walk_t = 0.34 if speed >= chase_speed else 0.5
	var loud := 0.9 if speed >= chase_speed else 0.45
	NoiseBus.emit_noise(global_position, loud, self)


func _pick_patrol_point() -> void:
	var best := _pick_point_near(_home, 3.0, patrol_radius)
	var best_score := -INF
	for _i in range(5):
		var candidate := _pick_point_near(_home, 3.0, patrol_radius)
		var score := INF
		for n in get_tree().get_nodes_in_group("crew"):
			var other := n as CrewAgent
			if other == null or other == self or other.is_gone():
				continue
			score = minf(score, candidate.distance_to(other.global_position))
		if score > best_score:
			best_score = score
			best = candidate
	_patrol_target = best


func _pick_point_near(origin: Vector3, rmin: float, rmax: float) -> Vector3:
	var a := randf() * TAU
	var r := randf_range(rmin, rmax)
	var p := _clamp_arena(origin + Vector3(cos(a) * r, 0.0, sin(a) * r))
	var world := get_world_3d()
	if world != null:
		_floor_query.from = p + Vector3.UP * 5.0
		_floor_query.to = p + Vector3.DOWN * 8.0
		_floor_query.exclude = [self]
		var hit := world.direct_space_state.intersect_ray(_floor_query)
		if not hit.is_empty():
			p.y = (hit["position"] as Vector3).y + 0.1
			return p
	return Vector3(p.x, origin.y, p.z)


func can_be_lifted() -> bool:
	if _carried or _capturing:
		return false
	if state == State.STUNNED:
		return true
	return state == State.IDLE and _resting


func is_carried() -> bool:
	return _carried


func is_gone() -> bool:
	return state == State.GONE


func state_name() -> String:
	match state:
		State.IDLE: return "idle"
		State.PATROL: return "patrol"
		State.SUSPICIOUS: return "suspicious"
		State.HOSTILE: return "hostile"
		State.STUNNED: return "stunned"
		State.CARRIED: return "carried"
		State.AIRBORNE: return "airborne"
		State.GONE: return "gone"
	return "?"


func receive_hit(damage: float, _source: Node = null) -> void:
	if state == State.GONE or _carried:
		return
	receive_impact(6.0 + damage * 0.1, null)


func receive_impact(speed: float, _item: Node = null) -> void:
	if state == State.GONE or _carried:
		return
	if speed < 3.0:
		return
	_stun(clampf(speed * 0.9, 2.0, 7.0))


@rpc("any_peer")
func request_impact(speed: float) -> void:
	if not multiplayer.is_server():
		return
	receive_impact(speed, null)


func _stun(duration: float) -> void:
	if _captive != null:
		_release_captive()
	_unlock_brig()
	_clear_haul()
	_guarding = false
	_capturing = false
	_set_state(State.STUNNED)
	_stun_t = maxf(_stun_t, duration)
	velocity = Vector3.ZERO
	NoiseBus.emit_noise(global_position, 1.0, self)


func set_net_authority(peer_id: int) -> void:
	set_multiplayer_authority(peer_id)
	var sync := get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync != null:
		sync.set_multiplayer_authority(peer_id)


func grab_by(peer_id: int) -> void:
	if _carried:
		return
	if _captive != null:
		_release_captive()
	_clear_haul()
	_carried = true
	_carrier_id = peer_id
	_prev_layer = collision_layer
	_prev_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_set_state(State.CARRIED)
	if _label != null:
		_label.visible = false
	_col.set_deferred("disabled", true)
	set_net_authority(peer_id)


func snap_upright() -> void:
	rotation.x = 0.0
	rotation.z = 0.0


func release_from_carry(thrown: bool, impulse: Vector3) -> void:
	_carried = false
	_carrier_id = -1
	collision_layer = _prev_layer
	collision_mask = _prev_mask
	_col.set_deferred("disabled", false)
	if _label != null:
		_label.visible = true
	set_net_authority(1)
	snap_upright()
	if thrown:
		_set_state(State.AIRBORNE)
		_air_t = 0.2
		velocity = impulse
		NoiseBus.emit_noise(global_position, 1.2, self)
	else:
		_set_state(State.STUNNED)
		_stun_t = 2.0
		velocity = Vector3.ZERO


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	net_state = s
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_state.rpc(s)
	_resting = s == State.IDLE and randf() < 0.35
	if _resting:
		_idle_t = maxf(_idle_t, randf_range(3.5, 7.0))
	_update_label()
	state_changed.emit(s)


@rpc("any_peer", "call_local", "reliable")
func _sync_state(s: int) -> void:
	if multiplayer.is_server():
		return
	net_state = s
	if state != s:
		state = s as State
		_update_label()


func _update_label() -> void:
	if _label == null:
		return
	var suffix := " (resting)" if _resting else ""
	_label.text = "%s\n[%s]%s" % [crew_name, state_name(), suffix]
	if state == State.STUNNED:
		_label.modulate = Color(1.0, 0.9, 0.3)
	elif state == State.HOSTILE:
		_label.modulate = Color(1.0, 0.25, 0.2)
	elif state == State.SUSPICIOUS:
		_label.modulate = Color(1.0, 0.65, 0.2)
	else:
		_label.modulate = Color(0.85, 0.9, 1.0)

func _update_remote_visual(delta: float) -> void:
	if _visual == null:
		return
	var target_pos := global_position
	var target_basis := global_transform.basis
	if _carried or state == State.AIRBORNE:
		_visual_pos = target_pos
		_visual_basis = target_basis
	else:
		target_basis = Basis(Vector3.UP, rotation.y)
		var t := 1.0 - exp(-18.0 * delta)
		_visual_pos = _visual_pos.lerp(target_pos, t)
		_visual_basis = _visual_basis.slerp(target_basis, t).orthonormalized()
	_visual.global_transform = Transform3D(_visual_basis, _visual_pos)


func _tick_visuals(delta: float) -> void:
	if _label != null and _model != null:
		_label.visible = state != State.CARRIED
	if state == State.HOSTILE and _model != null:
		_model.rotation.z = sin(Time.get_ticks_msec() * 0.012) * 0.04
	elif _model != null and state != State.STUNNED:
		_model.rotation.z = lerp_angle(_model.rotation.z, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	if state == State.STUNNED and _model != null:
		_model.rotation.x = lerp_angle(_model.rotation.x, deg_to_rad(75.0), clampf(delta * 6.0, 0.0, 1.0))
	elif _model != null:
		_model.rotation.x = lerp_angle(_model.rotation.x, 0.0, clampf(delta * 6.0, 0.0, 1.0))

func abandon_ship() -> void:
	if state == State.GONE or _carried or _capturing:
		return
	_go_gone()


func _check_offboard() -> void:
	if global_position.y < OFFBOARD_Y:
		_go_gone()

func _go_gone() -> void:
	if state == State.GONE:
		return
	if _captive != null:
		_release_captive()
	_clear_haul()
	_set_state(State.GONE)
	collision_layer = 0
	collision_mask = 0
	_col.set_deferred("disabled", true)
	if _model != null:
		_model.visible = false
	if _label != null:
		_label.visible = false
	gone.emit()
	queue_free()

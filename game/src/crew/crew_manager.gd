extends Node3D

@export var crew_count := 3
@export var first_abandon_after := 150.0
@export var abandon_interval := Vector2(55.0, 95.0)
@export var spawn_min_radius := 5.0
@export var spawn_max_radius := 12.0
@export var spawn_center := Vector3.ZERO

const CREW_SCENE: PackedScene = preload("res://crew.tscn")

var _crew_root: Node3D
var _spawner: MultiplayerSpawner
var _abandon_t := 0.0
var _spawn_points: Array[Vector3] = []


func _ready() -> void:
	_crew_root = get_parent().get_node_or_null("Crew") as Node3D
	_spawner = get_parent().get_node_or_null("CrewSpawner") as MultiplayerSpawner
	_abandon_t = first_abandon_after
	var spawn_root := get_parent().get_node_or_null("CrewSpawnPoints")
	if spawn_root != null:
		for marker in spawn_root.get_children():
			var m := marker as Node3D
			if m != null:
				_spawn_points.append(m.global_position)
	if not _ai_active():
		return
	call_deferred("_spawn_initial")


func _ai_active() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _process(delta: float) -> void:
	if not _ai_active() or _crew_root == null:
		return
	_abandon_t -= delta
	if _abandon_t > 0.0:
		return
	_abandon_t = randf_range(abandon_interval.x, abandon_interval.y)
	_abandon_one()


func _spawn_initial() -> void:
	if _crew_root == null:
		push_warning("[Crew] no Crew node under arena; crew disabled")
		return
	for i in crew_count:
		var c := CREW_SCENE.instantiate() as CrewAgent
		c.name = "Crew%d" % (i + 1)
		c.position = _spawn_pos(i)
		_crew_root.add_child(c, true)
		c.gone.connect(_on_crew_gone.bind(c))
	print("[Crew] spawned %d crew" % crew_count)


func _spawn_pos(i: int) -> Vector3:
	var p := Vector3.ZERO
	if not _spawn_points.is_empty():
		p = _spawn_points[i % _spawn_points.size()]
		p.x += randf_range(-0.45, 0.45)
		p.z += randf_range(-0.45, 0.45)
	else:
		var a := TAU * float(i) / maxf(float(crew_count), 1.0) + randf_range(-0.25, 0.25)
		var r := randf_range(spawn_min_radius, spawn_max_radius)
		p = spawn_center + Vector3(cos(a) * r, 0.0, sin(a) * r)
	var world := get_world_3d()
	if world != null:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 6.0, p + Vector3.DOWN * 10.0)
		q.collision_mask = 1
		var hit := world.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			p.y = (hit["position"] as Vector3).y + 1.1
			return p
	return Vector3(p.x, 1.1, p.z)


func _abandon_one() -> void:
	var alive: Array[CrewAgent] = []
	for n in _crew_root.get_children():
		var c := n as CrewAgent
		if c != null and not c.is_gone() and not c.is_carried():
			alive.append(c)
	if alive.size() <= 1:
		return
	var pick := alive[randi() % alive.size()]
	print("[Crew] %s abandons ship" % pick.name)
	pick.abandon_ship()


func _on_crew_gone(crew: CrewAgent) -> void:
	print("[Crew] %s is gone" % crew.name)


func alive_count() -> int:
	if _crew_root == null:
		return 0
	var n := 0
	for c in _crew_root.get_children():
		if c is CrewAgent and not c.is_gone():
			n += 1
	return n

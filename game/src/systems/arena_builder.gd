class_name ArenaBuilder
extends Node3D

const VASE_SCENE: PackedScene = preload("res://items/vase_light.tscn")
const CRATE_SCENE: PackedScene = preload("res://items/crate_medium.tscn")
const SAFE_SCENE: PackedScene = preload("res://items/safe_heavy.tscn")

const WALL_COLOR := Color(0.24, 0.27, 0.33)
const WALL_TRIM := Color(0.34, 0.38, 0.45)
const FLOOR_COLOR := Color(0.16, 0.18, 0.22)
const CORRIDOR_COLOR := Color(0.2, 0.22, 0.26)
const RAIL_COLOR := Color(0.4, 0.44, 0.5)

const ROOM_ENGINE := Color(0.34, 0.2, 0.16)
const ROOM_POWER := Color(0.3, 0.27, 0.14)
const ROOM_FUEL := Color(0.2, 0.26, 0.28)
const ROOM_STORAGE := Color(0.2, 0.28, 0.2)
const ROOM_GALLEY := Color(0.3, 0.23, 0.16)
const ROOM_MED := Color(0.18, 0.28, 0.26)
const ROOM_BRIG := Color(0.24, 0.22, 0.26)
const ROOM_CREW := Color(0.22, 0.24, 0.3)
const ROOM_LOUNGE := Color(0.24, 0.26, 0.2)

var _systems: Node3D
var _stations: Node3D
var _tasks: Node3D
var _restricted: Node3D
var _loot: Node3D


func _ready() -> void:
	add_to_group("arena_builder")
	_build_shell()
	_build_internal_walls()
	_build_doors()
	_build_labels()
	_build_lights()
	_build_systems()
	_build_stations()
	_build_tasks()
	_build_restricted()
	_build_brig()
	_build_loot()
	_build_pad()


func _build_shell() -> void:
	_add_floor(Vector3(0.0, 0.0, -4.0), Vector2(32.0, 48.0), FLOOR_COLOR)
	_add_floor(Vector3(0.0, 0.0, 25.0), Vector2(16.0, 10.0), FLOOR_COLOR)
	_add_floor_patch(Vector3(0.0, 0.0, -4.0), Vector2(4.0, 48.0), CORRIDOR_COLOR)
	_add_floor_patch(Vector3(-9.0, 0.0, -23.0), Vector2(14.0, 10.0), ROOM_ENGINE)
	_add_floor_patch(Vector3(-9.0, 0.0, -13.0), Vector2(14.0, 10.0), ROOM_GALLEY)
	_add_floor_patch(Vector3(-9.0, 0.0, -2.0), Vector2(14.0, 12.0), ROOM_FUEL)
	_add_floor_patch(Vector3(-9.0, 0.0, 8.0), Vector2(14.0, 8.0), ROOM_BRIG)
	_add_floor_patch(Vector3(-9.0, 0.0, 16.0), Vector2(14.0, 8.0), ROOM_CREW)
	_add_floor_patch(Vector3(9.0, 0.0, -23.0), Vector2(14.0, 10.0), ROOM_POWER)
	_add_floor_patch(Vector3(9.0, 0.0, -13.0), Vector2(14.0, 10.0), ROOM_MED)
	_add_floor_patch(Vector3(9.0, 0.0, -2.0), Vector2(14.0, 12.0), ROOM_STORAGE)
	_add_floor_patch(Vector3(9.0, 0.0, 12.0), Vector2(14.0, 16.0), ROOM_LOUNGE)
	_add_floor_patch(Vector3(0.0, 0.0, 25.0), Vector2(16.0, 10.0), Color(0.24, 0.2, 0.16))

	_add_wall_z(-16.0, -28.0, 20.0, WALL_COLOR)
	_add_wall_z(16.0, -28.0, 20.0, WALL_COLOR)
	_add_wall_x(-28.0, -16.0, 16.0, WALL_COLOR)
	_add_wall_x(20.0, -16.0, -2.0, WALL_COLOR)
	_add_wall_x(20.0, 2.0, 16.0, WALL_COLOR)

	_add_wall_z(-8.0, 20.0, 30.0, RAIL_COLOR, 1.2)
	_add_wall_z(8.0, 20.0, 30.0, RAIL_COLOR, 1.2)
	_add_wall_x(30.0, -8.0, 8.0, RAIL_COLOR, 1.2)


func _build_internal_walls() -> void:
	_add_wall_x(-18.0, -16.0, -2.0, WALL_TRIM)
	_add_wall_x(-8.0, -16.0, -2.0, WALL_TRIM)
	_add_wall_x(4.0, -16.0, -2.0, WALL_TRIM)
	_add_wall_x(12.0, -16.0, -2.0, WALL_TRIM)

	_add_wall_x(-18.0, 2.0, 16.0, WALL_TRIM)
	_add_wall_x(-8.0, 2.0, 16.0, WALL_TRIM)
	_add_wall_x(4.0, 2.0, 16.0, WALL_TRIM)

	for segment in [[-28.0, -24.0], [-22.0, -14.0], [-12.0, -3.0], [-1.0, 7.0], [9.0, 15.0], [17.0, 20.0]]:
		_add_wall_z(-2.0, segment[0], segment[1], WALL_TRIM)
	for segment in [[-28.0, -24.0], [-22.0, -14.0], [-12.0, -3.0], [-1.0, 11.0], [13.0, 20.0]]:
		_add_wall_z(2.0, segment[0], segment[1], WALL_TRIM)


func _build_doors() -> void:
	_add_door_at(-2.0, -23.0)
	_add_door_at(-2.0, -13.0)
	_add_door_at(-2.0, -2.0)
	_add_door_at(-2.0, 16.0)
	_add_door_at(2.0, -23.0)
	_add_door_at(2.0, -13.0)
	_add_door_at(2.0, -2.0)
	_add_door_at(2.0, 12.0)


func _build_labels() -> void:
	var west := [
		[-23.0, "ENGINE", Color(1.0, 0.55, 0.35)],
		[-13.0, "GALLEY", Color(1.0, 0.82, 0.5)],
		[-2.0, "FUEL / BILGE", Color(0.45, 0.75, 1.0)],
		[8.0, "BRIG", Color(1.0, 0.9, 0.55)],
		[16.0, "CREW QUARTERS", Color(0.7, 0.8, 1.0)],
	]
	for entry in west:
		_add_wall_sign(Vector3(-1.78, 2.55, entry[0]), entry[1], entry[2], PI * 0.5)
	var east := [
		[-23.0, "POWER", Color(1.0, 0.85, 0.25)],
		[-13.0, "MED BAY", Color(0.55, 1.0, 0.75)],
		[-2.0, "STORAGE", Color(0.65, 1.0, 0.6)],
		[12.0, "LOUNGE", Color(0.85, 0.9, 0.6)],
	]
	for entry in east:
		_add_wall_sign(Vector3(1.78, 2.55, entry[0]), entry[1], entry[2], -PI * 0.5)
	_add_wall_sign(Vector3(0.0, 2.55, 19.78), "EXTRACTION DECK", Color(1.0, 0.7, 0.3), PI)


func _build_lights() -> void:
	_add_light(Vector3(-9.0, 2.8, -23.0), Color(1.0, 0.45, 0.25))
	_add_light(Vector3(-9.0, 2.8, -13.0), Color(1.0, 0.75, 0.45))
	_add_light(Vector3(-9.0, 2.8, -2.0), Color(0.35, 0.6, 0.9))
	_add_light(Vector3(-9.0, 2.8, 8.0), Color(0.8, 0.8, 1.0))
	_add_light(Vector3(-9.0, 2.8, 16.0), Color(0.55, 0.7, 1.0))
	_add_light(Vector3(9.0, 2.8, -23.0), Color(1.0, 0.85, 0.35))
	_add_light(Vector3(9.0, 2.8, -13.0), Color(0.45, 1.0, 0.7))
	_add_light(Vector3(9.0, 2.8, -2.0), Color(0.6, 1.0, 0.5))
	_add_light(Vector3(9.0, 2.8, 12.0), Color(0.8, 0.9, 0.55))
	_add_light(Vector3(0.0, 3.0, 0.0), Color(0.75, 0.8, 1.0))
	_add_light(Vector3(0.0, 3.0, 25.0), Color(1.0, 0.7, 0.35))


func _build_systems() -> void:
	_systems = Node3D.new()
	_systems.name = "Systems"
	add_child(_systems)
	_add_system("engine", "ENGINE", Vector3(-9.0, 0.8, -23.0), Color(0.85, 0.35, 0.2), 300.0, true, _engine_procedure())
	_add_system("power", "POWER", Vector3(9.0, 0.8, -23.0), Color(0.95, 0.8, 0.2), 320.0, true)
	_add_system("fuel", "FUEL", Vector3(-9.0, 0.8, -2.0), Color(0.8, 0.3, 0.55), 340.0, true)
	_add_system("pump", "BILGE PUMP", Vector3(-13.0, 0.8, 1.0), Color(0.25, 0.55, 0.8), 280.0, false)


func _build_stations() -> void:
	_stations = Node3D.new()
	_stations.name = "Stations"
	add_child(_stations)

	var med := MedStation.new()
	med.name = "MedStation"
	med.position = Vector3(9.0, 0.5, -13.0)
	_stations.add_child(med)

	var vend := VendingMachine.new()
	vend.name = "VendingMachine"
	vend.position = Vector3(9.0, 1.0, 16.0)
	_stations.add_child(vend)

	var galley := Galley.new()
	galley.name = "Galley"
	galley.position = Vector3(-12.0, 0.5, -10.0)
	_stations.add_child(galley)


func _build_tasks() -> void:
	_tasks = Node3D.new()
	_tasks.name = "Tasks"
	add_child(_tasks)
	_add_task("fire", "FIRE", Vector3(-12.0, 0.55, -15.0), Color(1.0, 0.35, 0.08), 4.0)
	_add_task("leak", "HULL LEAK", Vector3(-6.0, 0.4, 1.0), Color(0.2, 0.6, 1.0), 5.0)
	_add_task("breaker", "BREAKER", Vector3(12.0, 0.85, -26.0), Color(1.0, 0.85, 0.2), 3.5)
	_add_task("fuel", "FUEL SPILL", Vector3(-13.0, 0.4, -5.0), Color(0.85, 0.6, 0.15), 5.5)
	_add_task("debris", "DEBRIS", Vector3(9.0, 0.55, 2.0), Color(0.6, 0.6, 0.65), 4.5)


func _build_restricted() -> void:
	_restricted = Node3D.new()
	_restricted.name = "Restricted"
	add_child(_restricted)
	_add_restricted(Vector3(-9.0, 1.5, -23.0), Vector3(13.0, 3.0, 9.5))
	_add_restricted(Vector3(9.0, 1.5, -23.0), Vector3(13.0, 3.0, 9.5))
	_add_restricted(Vector3(-9.0, 1.5, -2.0), Vector3(13.0, 3.0, 11.5))
	_add_restricted(Vector3(9.0, 1.5, -2.0), Vector3(13.0, 3.0, 11.5))


func _build_brig() -> void:
	var brig := Brig.new()
	brig.name = "Brig"
	brig.position = Vector3(-9.0, 0.0, 8.0)

	var door := Door.new()
	door.name = "Door"
	door.position = Vector3(7.0, 0.0, -0.75)
	door.rotation.y = -PI * 0.5
	door.lockable = true
	brig.add_child(door)

	add_child(brig)


func _build_loot() -> void:
	_loot = Node3D.new()
	_loot.name = "Loot"
	add_child(_loot)
	_add_loot(VASE_SCENE, Vector3(12.0, 1.8, 0.0))
	_add_loot(CRATE_SCENE, Vector3(7.0, 1.5, 2.0))
	_add_loot(SAFE_SCENE, Vector3(12.0, 0.9, -5.0))
	_add_loot(VASE_SCENE, Vector3(-9.0, 1.8, 16.0))
	_add_loot(CRATE_SCENE, Vector3(-12.0, 1.5, -15.0))
	_add_loot(SAFE_SCENE, Vector3(12.0, 0.9, 16.0))


func _build_pad() -> void:
	var pad := ExtractionPad.new()
	pad.name = "ExtractionPad"
	pad.position = Vector3(0.0, 0.6, 25.0)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 1.2, 4.0)
	shape.shape = box
	pad.add_child(shape)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.0, 0.08, 4.0)
	mesh.mesh = bm
	mesh.position = Vector3(0.0, -0.50, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.55, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.35, 0.05)
	mat.emission_energy_multiplier = 0.5
	bm.material = mat
	pad.add_child(mesh)

	var label := ProximityLabel.new()
	label.name = "Label3D"
	label.position = Vector3(0.0, 1.0, 0.0)
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.max_distance = 14.0
	label.text = "EXTRACTION"
	pad.add_child(label)
	add_child(pad)


func _add_floor(center: Vector3, size: Vector2, color: Color) -> void:
	_add_box("Floor", Vector3(center.x, -0.1, center.z), Vector3(size.x, 0.2, size.y), color)


func _add_floor_patch(center: Vector3, size: Vector2, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.02, size.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	bm.material = mat
	mesh.mesh = bm
	mesh.position = Vector3(center.x, 0.01, center.z)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _add_wall_z(x: float, z0: float, z1: float, color: Color, height := 3.0) -> void:
	var length := absf(z1 - z0)
	if length < 0.05:
		return
	_add_box("Wall", Vector3(x, height * 0.5, (z0 + z1) * 0.5), Vector3(0.4, height, length), color)


func _add_wall_x(z: float, x0: float, x1: float, color: Color, height := 3.0) -> void:
	var length := absf(x1 - x0)
	if length < 0.05:
		return
	_add_box("Wall", Vector3((x0 + x1) * 0.5, height * 0.5, z), Vector3(length, height, 0.4), color)


func _add_box(node_name: String, center: Vector3, size: Vector3, color: Color, metallic := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = center

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.78
	mat.metallic = metallic
	bm.material = mat
	mesh.mesh = bm
	body.add_child(mesh)

	add_child(body)
	return body


func _add_door_at(x: float, z: float) -> void:
	var door := Door.new()
	door.position = Vector3(x, 0.0, z - 0.75)
	door.rotation.y = -PI * 0.5
	door.open_angle = 1.45 if x > 0.0 else -1.45
	add_child(door)


func _add_wall_sign(pos: Vector3, text: String, color: Color, rot_y: float) -> void:
	var label := Label3D.new()
	label.position = pos
	label.rotation.y = rot_y
	label.text = text
	label.pixel_size = 0.007
	label.font_size = 28
	label.modulate = color
	label.outline_size = 6
	label.outline_modulate = Color(0.02, 0.02, 0.03, 0.9)
	add_child(label)


func _add_light(pos: Vector3, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.omni_range = 13.0
	light.light_energy = 1.1
	light.shadow_enabled = false
	add_child(light)


func _add_system(id: String, title: String, pos: Vector3, color: Color, fail_after: float, critical: bool, procedure: Array = []) -> void:
	var system := ShipSystem.new()
	system.system_id = id
	system.display_name = title
	system.position = pos
	system.accent = color
	system.fail_after = fail_after
	system.critical = critical
	_systems.add_child(system)
	if not procedure.is_empty():
		_attach_procedure(system, procedure)


func _add_task(kind: String, title: String, pos: Vector3, color: Color, hold: float) -> void:
	var task := TaskStation.new()
	task.task_kind = kind
	task.system_id = "task_" + kind
	task.display_name = title
	task.position = pos
	task.accent = color
	task.fx_color = color
	task.repair_time = hold
	task.fail_after = 200.0
	task.start_failed = kind == "debris"
	task.critical = true
	task.size = Vector3(1.0, 1.0, 1.0)
	_tasks.add_child(task)


func _add_restricted(pos: Vector3, size: Vector3) -> void:
	var area := RestrictedArea.new()
	area.name = "Restricted"
	area.position = pos

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.15, 0.1, 0.14)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.material = mat
	mesh.mesh = bm
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(mesh)

	_restricted.add_child(area)


func _add_loot(scene: PackedScene, pos: Vector3) -> void:
	var item := scene.instantiate() as Node3D
	item.position = pos
	_loot.add_child(item)


func _engine_procedure() -> Array:
	# stage is like {"kind":"seq"|"set","actions":[...]}.
	# seq = actions must be done in fixed order.
	# set = actions can be done in any order.
	var stages := []
	stages.append(_stage("seq", [
		_make_action("close_coolant", "Close Coolant Valve", 2.0, "Turn the coolant valve clockwise"),
		_make_action("close_fuel", "Close Fuel Valve", 2.0, "Shut the fuel valve"),
		_make_action("trip_breaker", "Trip Breaker", 2.0, "Flip the breaker to OFF"),
	]))
	stages.append(_stage("seq", [
		_make_action("open_engine", "Open Engine", 3.0, "Crack the engine housing",
			["close_coolant", "close_fuel", "trip_breaker"], true,
			"You opened a pressurized engine - scalding steam!", true),
	]))
	stages.append(_stage("set", [
		_make_action("clean", "Clean Internals", 2.5, "Wipe out grime", ["open_engine"]),
		_make_action("add_oil", "Add Oil", 2.0, "Pour oil into the crankcase", ["open_engine"]),
		_make_action("add_fuel", "Add Fuel", 2.0, "Refill the fuel line", ["open_engine"]),
	]))
	stages.append(_stage("seq", [
		_make_action("close_engine", "Close Engine", 2.0, "Seal the housing",
			["clean", "add_oil", "add_fuel"]),
	]))
	stages.append(_stage("set", [
		_make_action("open_coolant", "Open Coolant Valve", 1.5, "Reopen coolant flow",
			["close_engine"], true, "You opened coolant with the engine still open - flooding!", true),
		_make_action("open_breaker", "Reset Breaker", 1.5, "Flip the breaker back ON", ["close_engine"]),
	]))
	stages.append(_stage("seq", [
		_make_action("start_engine", "Start Engine", 3.0, "Turn the ignition",
			["open_coolant", "open_breaker"], true,
			"You started the engine without coolant - it seized!", true),
	]))
	return stages


func _stage(kind: String, actions: Array) -> Dictionary:
	return {"kind": kind, "actions": actions}


func _make_action(id: String, display: String, hold: float, hint: String,
                  requires: Array[String] = [],
                  accident_on_unguarded_begin: bool = false,
                  accident_reason: String = "Mistake made.",
                  accident_on_fail: bool = false) -> Dictionary:
	return {
		"id": id,
		"display_name": display,
		"hold_time": hold,
		"hint": hint,
		"requires": requires,
		"accident_on_unguarded_begin": accident_on_unguarded_begin,
		"accident_reason": accident_reason,
		"accident_on_fail": accident_on_fail,
	}


func _attach_procedure(system: ShipSystem, stages: Array) -> void:
	var proc := Procedure.new()
	proc.name = "RepairProcedure"
	for s in stages:
		var kind := s["kind"] as String
		var stage
		if kind == "set":
			stage = ActionSet.new()
			stage.name = "StageSet"
		else:
			stage = Sequence.new()
			stage.name = "StageSeq"
		var action_nodes: Array = []
		for a in s["actions"] as Array:
			var action := Action.new()
			action.id = a["id"] as String
			action.display_name = a["display_name"] as String
			action.hold_time = a["hold_time"] as float
			action.hint = a["hint"] as String
			action.requires = a["requires"] as Array[String]
			action.accident_on_unguarded_begin = a["accident_on_unguarded_begin"] as bool
			action.accident_reason = a["accident_reason"] as String
			action.accident_on_fail = a["accident_on_fail"] as bool
			action.name = a["id"] as String
			stage.add_child(action)
			action_nodes.append(action)
		stage.actions = action_nodes
		proc.add_child(stage)
		proc.stages.append(stage)
	system.add_child(proc)
	proc._reindex()
	system.procedure_node = proc.get_path()
	system._bind_procedure()

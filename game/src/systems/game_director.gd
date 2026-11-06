extends Node

const MED_STATION := preload("res://src/systems/med_station.gd")
const VENDING := preload("res://src/systems/vending_machine.gd")
const GALLEY := preload("res://src/systems/galley.gd")
const CREW_MANAGER := preload("res://src/crew/crew_manager.gd")
const RUN_MANAGER := preload("res://src/systems/run_manager.gd")
const DOOR := preload("res://src/systems/door.gd")
const BRIG := preload("res://src/systems/brig.gd")

var _systems: Dictionary = {}
var _water: MeshInstance3D
var _sun: DirectionalLight3D
var _flicker_t := 0.0


func _ready() -> void:
	_bind_systems()
	_build_stations()
	_build_brig()
	_build_ocean()
	_build_bilge_water()
	call_deferred("_build_crew")
	call_deferred("_build_run")


func _process(delta: float) -> void:
	_update_power(delta)
	_update_bilge(delta)


func _update_power(delta: float) -> void:
	if _sun == null:
		_sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if _sun == null:
		return
	var power := _systems.get("power") as ShipSystem
	if power != null and power.is_failed():
		_flicker_t += delta
		_sun.light_energy = 0.25 + absf(sin(_flicker_t * 9.0)) * 0.35
	else:
		_sun.light_energy = lerpf(_sun.light_energy, 1.0, clampf(delta * 2.5, 0.0, 1.0))


func _update_bilge(delta: float) -> void:
	if _water == null:
		return
	var pump := _systems.get("pump") as ShipSystem
	var target := 0.95 if (pump != null and pump.is_failed()) else 0.08
	_water.position.y = move_toward(_water.position.y, target, delta * 0.22)


func _bind_systems() -> void:
	_systems.clear()
	for n in get_tree().get_nodes_in_group("ship_systems"):
		var s := n as ShipSystem
		if s != null:
			_systems[s.system_id] = s


func _build_stations() -> void:
	var med := MED_STATION.new() as MedStation
	med.name = "MedStation"
	med.position = Vector3(-15.5, 0.5, 0.0)
	add_child(med)

	var vend := VENDING.new() as VendingMachine
	vend.name = "VendingMachine"
	vend.position = Vector3(15.5, 1.0, 0.0)
	add_child(vend)

	var galley := GALLEY.new() as Galley
	galley.name = "Galley"
	galley.position = Vector3(-15.5, 0.5, -8.0)
	add_child(galley)


func _build_brig() -> void:
	var brig := BRIG.new() as Brig
	brig.name = "Brig"
	brig.position = Vector3(0.0, 0.0, -18.2)
	var wall_color := Color(0.32, 0.36, 0.42)
	_add_wall(brig, Vector3(4.0, 2.5, 0.2), Vector3(0.0, 1.25, -1.5), wall_color)
	_add_wall(brig, Vector3(0.2, 2.5, 3.0), Vector3(-2.0, 1.25, 0.0), wall_color)
	_add_wall(brig, Vector3(0.2, 2.5, 3.0), Vector3(2.0, 1.25, 0.0), wall_color)
	_add_wall(brig, Vector3(1.25, 2.5, 0.2), Vector3(-1.375, 1.25, 1.5), wall_color)
	_add_wall(brig, Vector3(1.25, 2.5, 0.2), Vector3(1.375, 1.25, 1.5), wall_color)

	var door := DOOR.new() as Door
	door.name = "Door"
	door.position = Vector3(-0.75, 0.0, 1.5)
	brig.add_child(door)

	var sign := Label3D.new()
	sign.name = "BrigSign"
	sign.position = Vector3(0.0, 3.0, 0.0)
	sign.pixel_size = 0.01
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.no_depth_test = true
	sign.font_size = 44
	sign.text = "BRIG\nlock crew inside"
	sign.modulate = Color(1.0, 0.9, 0.55)
	brig.add_child(sign)
	add_child(brig)


func _add_wall(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var wall := StaticBody3D.new()
	wall.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mat.metallic = 0.15
	bm.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = bm
	wall.add_child(mesh)
	parent.add_child(wall)


func _build_ocean() -> void:
	var sea := MeshInstance3D.new()
	sea.name = "Ocean"
	var pm := PlaneMesh.new()
	pm.size = Vector2(320.0, 320.0)
	sea.mesh = pm
	sea.position = Vector3(0.0, -3.6, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.13, 0.2)
	mat.roughness = 0.18
	mat.metallic = 0.35
	sea.material_override = mat
	add_child(sea)


func _build_bilge_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "BilgeWater"
	var pm := PlaneMesh.new()
	pm.size = Vector2(14.0, 14.0)
	water.mesh = pm
	var pump := _systems.get("pump") as ShipSystem
	var water_pos := pump.global_position if pump != null else Vector3(15.5, 0.0, 15.5)
	water.position = Vector3(water_pos.x, 0.08, water_pos.z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.2, 0.22, 0.72)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.12
	mat.metallic = 0.2
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	_water = water


func _build_crew() -> void:
	var root := get_parent()
	if root == null:
		return
	if root.has_node("CrewManager"):
		return
	var cm := CREW_MANAGER.new()
	cm.name = "CrewManager"
	root.add_child(cm)


func _build_run() -> void:
	var root := get_parent()
	if root == null:
		return
	if root.has_node("RunManager"):
		return
	var rm := RUN_MANAGER.new()
	rm.name = "RunManager"
	root.add_child(rm)

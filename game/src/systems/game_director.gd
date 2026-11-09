extends Node

const CREW_MANAGER := preload("res://src/crew/crew_manager.gd")
const RUN_MANAGER := preload("res://src/systems/run_manager.gd")

var _systems: Dictionary = {}
var _water: MeshInstance3D
var _sun: DirectionalLight3D
var _flicker_t := 0.0


func _ready() -> void:
	_bind_systems()
	_build_ocean()
	call_deferred("_bind_systems")
	call_deferred("_build_bilge_water")
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
	var power_out := power != null and power.is_failed()
	if not power_out:
		power_out = _task_failed("breaker")
	if power_out:
		_flicker_t += delta
		_sun.light_energy = 0.25 + absf(sin(_flicker_t * 9.0)) * 0.35
	else:
		_sun.light_energy = lerpf(_sun.light_energy, 1.0, clampf(delta * 2.5, 0.0, 1.0))


func _update_bilge(delta: float) -> void:
	if _water == null:
		return
	var pump := _systems.get("pump") as ShipSystem
	var flooding := pump != null and pump.is_failed()
	if not flooding:
		flooding = _task_failed("leak")
	var target := 0.95 if flooding else 0.08
	_water.position.y = move_toward(_water.position.y, target, delta * 0.22)


func _task_failed(kind: String) -> bool:
	for n in get_tree().get_nodes_in_group("task_stations"):
		var t := n as TaskStation
		if t != null and t.task_kind == kind and t.is_failed():
			return true
	return false


func _bind_systems() -> void:
	_systems.clear()
	for n in get_tree().get_nodes_in_group("ship_systems"):
		var s := n as ShipSystem
		if s != null:
			_systems[s.system_id] = s


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
	_bind_systems()
	var water := MeshInstance3D.new()
	water.name = "BilgeWater"
	var pm := PlaneMesh.new()
	pm.size = Vector2(13.0, 11.0)
	water.mesh = pm
	water.position = Vector3(-9.0, 0.08, -2.0)
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

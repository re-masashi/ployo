class_name TaskStation
extends ShipSystem

@export var task_kind := "fire"
@export var fx_color := Color(1.0, 0.45, 0.1)

var _fx_light: OmniLight3D
var _fx_mesh: MeshInstance3D
var _fx_mat: StandardMaterial3D
var _pulse := 0.0


func _ready() -> void:
	add_to_group("task_stations")
	super._ready()
	_build_task_visuals()


func _process(delta: float) -> void:
	_pulse += delta
	if _fx_light != null:
		_fx_light.light_energy = (0.55 + absf(sin(_pulse * 7.0)) * 0.45) if is_failed() else 0.0
	if _fx_mesh != null:
		_fx_mesh.visible = is_failed()
	if _fx_mat != null and task_kind == "fire" and is_failed():
		_fx_mat.emission_energy_multiplier = 1.2 + absf(sin(_pulse * 9.0)) * 1.6


func _build_task_visuals() -> void:
	_fx_light = OmniLight3D.new()
	_fx_light.position = Vector3(0.0, size.y * 0.5 + 0.5, 0.0)
	_fx_light.light_color = fx_color
	_fx_light.omni_range = 6.0
	_fx_light.light_energy = 0.0
	add_child(_fx_light)

	var mesh := MeshInstance3D.new()
	_fx_mat = StandardMaterial3D.new()
	_fx_mat.albedo_color = fx_color
	_fx_mat.emission_enabled = true
	_fx_mat.emission = fx_color
	_fx_mat.emission_energy_multiplier = 1.4
	_fx_mat.roughness = 0.5

	match task_kind:
		"leak", "fuel":
			var pm := PlaneMesh.new()
			pm.size = Vector2(2.6, 2.6)
			mesh.mesh = pm
			mesh.position = Vector3(0.0, -size.y * 0.5 + 0.03, 0.0)
			_fx_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_fx_mat.albedo_color = Color(fx_color.r, fx_color.g, fx_color.b, 0.62)
		"debris":
			var bm := BoxMesh.new()
			bm.size = Vector3(1.3, 0.55, 0.9)
			mesh.mesh = bm
			mesh.position = Vector3(0.0, -size.y * 0.5 + 0.28, 0.7)
			_fx_mat.emission_energy_multiplier = 0.0
		"breaker":
			var sb := BoxMesh.new()
			sb.size = Vector3(0.28, 0.4, 0.16)
			mesh.mesh = sb
			mesh.position = Vector3(0.0, size.y * 0.5 + 0.25, 0.0)
		_:
			var sm := SphereMesh.new()
			sm.radius = 0.38
			sm.height = 0.76
			mesh.mesh = sm
			mesh.position = Vector3(0.0, size.y * 0.5 + 0.35, 0.0)

	mesh.material_override = _fx_mat
	mesh.visible = is_failed()
	add_child(mesh)
	_fx_mesh = mesh

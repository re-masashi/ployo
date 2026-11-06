class_name Galley
extends StaticBody3D

@export var size := Vector3(1.7, 1.0, 1.0)
@export var accent := Color(0.72, 0.42, 0.22)
@export var cooldown := 7.0

var _label: Label3D
var _cooldown := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("galleys")
	_build()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = accent
	mat.roughness = 0.65
	bm.material = mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = bm
	add_child(_mesh)

	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(size.x * 0.55, 0.08, size.z * 0.55)
	plate.mesh = pm
	plate.position = Vector3(0.0, size.y * 0.5 + 0.05, 0.0)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.25, 0.26, 0.28)
	metal.metallic = 0.7
	plate.material_override = metal
	add_child(plate)

	_label = Label3D.new()
	_label.position = Vector3(0.0, size.y * 0.5 + 0.7, 0.0)
	_label.pixel_size = 0.01
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 44
	_label.text = "GALLEY\nE to eat"
	_label.modulate = Color(1.0, 0.82, 0.5)
	add_child(_label)


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func interact(player: Node3D) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = cooldown
	if player.has_method("heal"):
		player.heal(25.0)
	if player.has_method("add_buff"):
		player.add_buff("speed", 25.0, 1.12)
	if player.has_method("emit_noise"):
		player.emit_noise(0.8)
	NoiseBus.emit_noise(global_position, 0.8, self)
	if _mesh != null:
		var tween := create_tween()
		tween.tween_property(_mesh, "scale:y", 0.94, 0.06)
		tween.tween_property(_mesh, "scale:y", 1.0, 0.1)
	if _label != null:
		_label.text = "GALLEY\nfed"

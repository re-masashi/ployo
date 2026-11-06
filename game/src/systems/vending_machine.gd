class_name VendingMachine
extends StaticBody3D

@export var size := Vector3(0.9, 1.9, 0.65)
@export var cooldown := 8.0

const BUFFS := ["speed", "jump", "drunk", "health", "lucky"]

var _label: Label3D
var _cooldown := 0.0
var _mesh: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("vending_machines")
	_rng.randomize()
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
	mat.albedo_color = Color(0.78, 0.16, 0.2)
	mat.roughness = 0.5
	mat.metallic = 0.2
	bm.material = mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = bm
	add_child(_mesh)

	var glass := MeshInstance3D.new()
	var gbm := BoxMesh.new()
	gbm.size = Vector3(size.x * 0.6, size.y * 0.45, 0.04)
	glass.mesh = gbm
	glass.position = Vector3(0.0, 0.2, size.z * 0.5 + 0.02)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.45, 0.7, 0.85)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.material_override = gm
	add_child(glass)

	_label = Label3D.new()
	_label.position = Vector3(0.0, size.y * 0.5 + 0.5, 0.0)
	_label.pixel_size = 0.01
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 44
	_label.text = "DRINKS\nkick it"
	_label.modulate = Color(1.0, 0.85, 0.55)
	add_child(_label)


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func interact(player: Node3D) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = cooldown
	var kind: String = BUFFS[_rng.randi() % BUFFS.size()]
	if kind == "health":
		if player.has_method("heal"):
			player.heal(35.0)
	else:
		if player.has_method("add_buff"):
			player.add_buff(kind, 18.0, 1.4)
	if player.has_method("emit_noise"):
		player.emit_noise(1.35)
	NoiseBus.emit_noise(global_position, 1.35, self)
	if _mesh != null:
		var tween := create_tween()
		tween.tween_property(_mesh, "rotation:z", 0.12, 0.06)
		tween.tween_property(_mesh, "rotation:z", -0.12, 0.08)
		tween.tween_property(_mesh, "rotation:z", 0.0, 0.08)
	if _label != null:
		_label.text = "DRINKS\n%s!" % kind.to_upper()

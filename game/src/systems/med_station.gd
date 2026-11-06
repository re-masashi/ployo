class_name MedStation
extends StaticBody3D

@export var size := Vector3(1.8, 0.9, 0.9)
@export var accent := Color(0.25, 0.75, 0.55)

var _label: Label3D
var _cooldown := 0.0
var _label_t := 0.0


func _ready() -> void:
	add_to_group("med_stations")
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
	mat.roughness = 0.55
	bm.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = bm
	add_child(mesh)

	var cross := MeshInstance3D.new()
	var cbm := BoxMesh.new()
	cbm.size = Vector3(0.55, 0.12, 0.55)
	cross.mesh = cbm
	cross.position = Vector3(0.0, size.y * 0.5 + 0.07, 0.0)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.95)
	cross.material_override = white
	add_child(cross)

	_label = Label3D.new()
	_label.position = Vector3(0.0, size.y * 0.5 + 0.75, 0.0)
	_label.pixel_size = 0.01
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 48
	_label.text = "MED BAY\nE: heal / revive"
	_label.modulate = Color(0.6, 1.0, 0.8)
	add_child(_label)


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _label_t > 0.0:
		_label_t -= delta
		if _label_t <= 0.0 and _label != null:
			_label.text = "MED BAY\nE: heal / revive"


func interact(player: Node3D) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = 1.0
	_label_t = 1.5
	var carried: PlayerController = null
	if player.has_method("get_carried_player"):
		carried = player.get_carried_player()
	if carried != null and carried.is_down():
		carried.revive(true)
		if player.has_method("drop_carried_player"):
			player.drop_carried_player()
		NoiseBus.emit_noise(global_position, 0.4, self)
		if _label != null:
			_label.text = "MED BAY\nrevived"
		return
	if player.has_method("heal"):
		player.heal(999.0)
	if player.has_method("revive"):
		player.revive()
	NoiseBus.emit_noise(global_position, 0.4, self)
	if _label != null:
		_label.text = "MED BAY\nhealed"

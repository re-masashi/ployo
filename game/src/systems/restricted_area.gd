class_name RestrictedArea
extends Area3D

var _overlapping: Dictionary = {}


func _ready() -> void:
	add_to_group("restricted_areas")
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body != null:
		_overlapping[body] = true


func _on_body_exited(body: Node3D) -> void:
	_overlapping.erase(body)


func contains(body: Node3D) -> bool:
	return body != null and _overlapping.has(body)

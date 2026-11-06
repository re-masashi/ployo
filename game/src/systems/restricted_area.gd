class_name RestrictedArea
extends Area3D

func _ready() -> void:
	add_to_group("restricted_areas")
	collision_layer = 0
	collision_mask = 2
	monitoring = true


func contains(body: Node3D) -> bool:
	return body != null and overlaps_body(body)

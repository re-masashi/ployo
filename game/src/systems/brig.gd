class_name Brig
extends Node3D

@onready var door: Door = get_node_or_null("Door") as Door

func _ready() -> void:
	add_to_group("brigs")


func get_capture_point() -> Vector3:
	return global_position + Vector3(0.0, 0.05, 0.0)


func get_guard_point() -> Vector3:
	return global_position + Vector3(0.0, 0.05, 2.6)


func open_door() -> void:
	if door != null:
		door.open()


func lock(value: bool) -> void:
	if door != null:
		door.lock(value)

func is_locked() -> bool:
	return door != null and door.is_locked()

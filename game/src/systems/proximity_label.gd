class_name ProximityLabel
extends Label3D

@export var max_distance := 9.0
@export var min_distance := 0.0
@export var check_interval := 0.2

var _check_t := 0.0


func _ready() -> void:
	no_depth_test = false
	_update_visibility()


func _process(delta: float) -> void:
	_check_t += delta
	if _check_t < check_interval:
		return
	_check_t = 0.0
	_update_visibility()


func _update_visibility() -> void:
	var p := _local_player()
	if p == null:
		visible = true
		return
	var d := global_position.distance_to(p.global_position)
	visible = d <= max_distance and d >= min_distance


func _local_player() -> Node3D:
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p != null and p.has_method("is_multiplayer_authority") and p.is_multiplayer_authority():
			return p
	return get_tree().get_first_node_in_group("players") as Node3D

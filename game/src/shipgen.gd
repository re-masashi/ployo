@tool
extends Node

@export var back_inc: Array[Vertabrae]
@export var back_dec: Array[Vertabrae]
@export var vertabrae: Array[Vertabrae]
@export var front_inc: Array[Vertabrae]
@export var front_dec: Array[Vertabrae]

class Spine:
	var spine: Array[Array]
	var x_sizes: Array[float]
	var y_sizes: Array[float]
	

func generate_ship_spine() -> Spine:
	var floor_spine_size := randi_range(5, 6)
	#var start := 0
	var spine: Spine = Spine.new()
	var increase := randi_range(1, 5)
	var decrease := increase + randi_range(0, 4)
	var top := decrease + randi_range(1, 3)
	for i in top + 1:
		spine.spine.append([])
	var i := 0
	for floor_spine: Array[Vertabrae] in spine.spine:
		if i == 0:
			var back: Vertabrae = back_inc.pick_random()
			spine.y_sizes.append(back.size.y)
			floor_spine.append(back)
			for j in floor_spine_size:
				var vert: Vertabrae = vertabrae.pick_random()
				floor_spine.append(vert)
				spine.x_sizes.append(vert.size.x)
			var cap: Vertabrae = front_inc.pick_random()
			floor_spine.append(cap)
			spine.x_sizes.append(cap.size.x)
		elif i <= increase:
			var back: Vertabrae = vertabrae.pick_random()
			spine.y_sizes.append(back.size.y)
			floor_spine.append(back)
			for j in floor_spine_size:
				floor_spine.append(vertabrae.pick_random())
			floor_spine.append(front_inc.pick_random())
		elif i <= decrease:
			var back: Vertabrae = vertabrae.pick_random()
			spine.y_sizes.append(back.size.y)
			floor_spine.append(back)
			for j in floor_spine_size:
				floor_spine.append(vertabrae.pick_random())
			floor_spine.append(front_dec.pick_random())
		elif i < top:
			var back: Vertabrae = vertabrae.pick_random()
			spine.y_sizes.append(back.size.y)
			floor_spine.append(back)
			for j in floor_spine_size:
				floor_spine.append(vertabrae.pick_random())
		else:
			#floor_spine.append(" ")
			for j in floor_spine_size:
				if randf() < 0.2:
					floor_spine.append(vertabrae.pick_random())
				else:
					pass
					floor_spine.append(null)
		if i < increase:
			floor_spine_size += 1
		elif i < decrease:
			floor_spine_size -= 1
		i += 1
	return spine

func place_vertabrae(spine: Spine) -> void:
	var i := 0
	var y := 0.0
	for floor_spine: Array[Vertabrae] in spine.spine:
		var j := 0
		var x := 0.0
		for vres in floor_spine:
			if vres != null:
				var v := vres.scene.instantiate()
				if v is VertabraeNode:
					v.position.x = x
					v.position.y = y
					add_child(v)
			x += spine.x_sizes[j]
		y += spine.y_sizes[i]

func _ready() -> void:
	var spine = generate_ship_spine()
	place_vertabrae(spine)

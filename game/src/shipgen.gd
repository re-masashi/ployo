@tool
extends Node

@export var back_inc: Array[Segment]
@export var back_dec: Array[Segment]
@export var vertabrae: Array[Segment]
@export var front_inc: Array[Segment]
@export var front_dec: Array[Segment]

class Spine:
	var spine: Array[Array]
	var x_sizes: Array[float]
	var y_sizes: Array[float]

func pick_matching_htag(tag: String, of: Array[Segment]) -> Segment:
	return of.filter(func(vert: Segment): return vert.back_tag == tag)\
		.pick_random()

func pick_matching_vtag(tag: String, of: Array[Segment]) -> Segment:
	return of.filter(func(vert: Segment): return vert.bottom_tag == tag)\
		.pick_random()

func pick_matching(vtag: String, htag: String, of: Array[Segment]) -> Segment:
	return pick_matching_htag(
		htag,
		of.filter(func(vert: Segment): return vert.bottom_tag == vtag),
	)

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
	for floor_spine: Array[Segment] in spine.spine:
		if i == 0:
			var back: Segment = back_inc.pick_random()
			spine.y_sizes.append(back.size.y)
			floor_spine.append(back)
			var tag := back.front_tag
			for j in floor_spine_size:
				var vert: Segment = pick_matching_htag(tag, vertabrae)
				floor_spine.append(vert)
				spine.x_sizes.append(vert.size.x)
				tag = vert.front_tag
			var cap: Segment = pick_matching_htag(tag, front_inc)
			floor_spine.append(cap)
			spine.x_sizes.append(cap.size.x)
		elif i <= increase:
			var back: Segment = pick_matching_vtag(
				spine.spine[i - 1][0].top_tag,
				vertabrae,
			)
			var tag := back.front_tag
			spine.y_sizes.append(back.size.y)
			floor_spine.append(back)
			for j in floor_spine_size:
				floor_spine.append(pick_matching(
					spine.spine[i - 1][0].top_tag,
					tag,
					vertabrae,
				))
			floor_spine.append(pick_matching_htag(tag, front_inc))
		elif i <= decrease:
			var back: Segment = vertabrae.pick_random()
			spine.y_sizes.append(back.size.y)
			floor_spine.append(back)
			for j in floor_spine_size:
				floor_spine.append(vertabrae.pick_random())
			floor_spine.append(front_dec.pick_random())
		elif i < top:
			var back: Segment = vertabrae.pick_random()
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
	for floor_spine: Array[Segment] in spine.spine:
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

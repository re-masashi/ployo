extends Node3D

@export var width := 7
@export var height := 7
@export var level_count := 5
@export var num_rooms := 10
@export var num_dead_ends := 3
@export var num_extra_stairs := 1
@export var seed := 38754289753

@export var end_material: Material
@export var stair_material: Material
@export var stairend_material: Material

@onready var mesh = BoxMesh.new()

const dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
var levels = make_levels()

func _ready() -> void:
	mesh.size = Vector3(.9, .9, .9)
	
	while !gen_all_levels(seed):
		push_warning("failed to generate a level")
	for n in level_count:
		var lvl = levels[n]
		print("Level ", n, ":")
		for y in height:
			var s = ""
			for x in width:
				if lvl[y * width + x] != null:
					var mesh_inst := MeshInstance3D.new()
					mesh_inst.mesh = mesh
					mesh_inst.position = Vector3(x, -n, y)
					match lvl[y * width + x]:
						&"end": mesh_inst.material_override = end_material
						&"stair": mesh_inst.material_override = stair_material
						&"stairend": mesh_inst.material_override = stairend_material
					add_child(mesh_inst)
				match lvl[y * width + x]:
					&"end": s += "e"
					&"stair": s += "s"
					&"stairend": s += "S"
					&"normal": s += "x"
					_: s += " "
			print(s)
		print("")

func make_levels():
	var lvls = []
	for i in level_count:
		lvls.insert(i, [])
		lvls[i].resize(width * height)
	return lvls

func gen_all_levels(rng_seed: int) -> bool:
	var rng = RandomNumberGenerator.new()
	rng.seed = rng_seed
	levels = make_levels()
	@warning_ignore("integer_division")
	var start_pos = Vector2i((width - 1) / 2, height - 1)
	var start_dir = Vector2i.UP
	var stair_rooms = []
	var last_stair = Vector2i(-1, -1)
	for n in level_count:
		gen_level(n, rng, start_pos, start_dir)
		var dead_ends = mark_dead_ends(n, num_dead_ends, rng)
		if n == level_count - 1: break
		var lvl = levels[n]
		var first_stair_room_i = rng.randi_range(0, num_rooms + dead_ends - 2)
		var first_stair_room = Vector2i(-1, -1)
		for x in width:
			for y in height:
				if lvl[x + y * width] != null && (last_stair.x != x || last_stair.y != y):
					if first_stair_room_i == 0:
						@warning_ignore("integer_division")
						first_stair_room = Vector2i(x, y)
						break
					else: first_stair_room_i -= 1
		if first_stair_room.x < 0 && first_stair_room.y < 0:
			push_error("error: failed to locate the first stair room")
			return false
		last_stair = first_stair_room
		stair_rooms.insert(n, first_stair_room)
		start_pos = first_stair_room
		start_dir = determine_next_dir(first_stair_room, Vector2i(-10, -10), rng)
	for i in stair_rooms.size():
		place_stairs(i, stair_rooms[i], num_extra_stairs)
	return true

func place_stairs(upper: int, last: Vector2i, extra_stairs: int):
	var lvlup = levels[upper]
	var lvldown = levels[upper + 1]
	lvlup[last.x + last.y * width] = &"stair"
	lvldown[last.x + last.y * width] = &"stairend"
	var stairs: Array[Vector2i] = []
	for x in width:
		for y in height:
			if x != last.x && y != last.y:
				var i = x + y * width
				if may_be_stair(lvlup[i]) && may_be_stair(lvldown[i]):
					stairs.push_back(Vector2i(x, y))
	if stairs.is_empty():
		push_warning("no available stair locations")
	extra_stairs = min(extra_stairs, stairs.size())
	for _i in extra_stairs:
		var last_i = 0
		var last_dist = stairs[0].distance_squared_to(last)
		for i in range(1, stairs.size()):
			var dist = stairs[i].distance_squared_to(last)
			if dist > last_dist:
				last_i = i
		last = stairs[last_i]
		stairs.remove_at(last_i)
		lvlup[last.x + last.y * width] = &"stair"
		lvldown[last.x + last.y * width] = &"stairend"

func may_be_stair(v):
	match v:
		&"stair", &"stairend", null: return false
		&"normal", &"end": return true
		_:
			push_error("invalid tile: ", v)
			return false

func mark_dead_ends(n: int, amount: int, rng: RandomNumberGenerator) -> int:
	if amount == 0: return 0
	var lvl: Array = levels[n]
	var ends: Array[Vector2i] = []
	for x in width:
		for y in height:
			var i = x + y * width
			if lvl[i] == &"normal": continue
			var has_connection = false
			for dir in dirs:
				var new_pos = Vector2i(x + dir.x, y + dir.y)
				if new_pos.x >= 0 && new_pos.y >= 0 && new_pos.x < width && new_pos.y < height:
					var v = lvl[new_pos.x + new_pos.y * width]
					match v:
						&"end":
							has_connection = false
							break
						&"normal":
							# dead ends connecting to 2+ rooms would make this not a dead end, so skip
							if has_connection:
								has_connection = false
								break
							else: has_connection = true
			if has_connection:
				lvl[i] = &"end"
				ends.push_back(Vector2i(x, y))
	if ends.is_empty(): return 0
	var amount_to_generate = min(amount, ends.size())
	var first_dead_end = rng.randi_range(0, ends.size() - 1)
	var last = ends[first_dead_end]
	ends.remove_at(first_dead_end)
	for _i in amount_to_generate - 1:
		var last_i := 0
		var last_len_sqr := ends[0].distance_squared_to(last)
		for i in range(1, ends.size()):
			var length = ends[i].distance_squared_to(last)
			if length > last_len_sqr:
				last_i = i
				last_len_sqr = length
		last = ends[last_i]
		ends.remove_at(last_i)
	for end in ends:
		lvl[end.x + end.y * width] = null
	return amount_to_generate

func gen_level(n: int, rng: RandomNumberGenerator, pos: Vector2i, dir: Vector2i):
	var rooms_left = num_rooms - 1
	var lvl = levels[n]
	lvl[pos.x + pos.y * width] = &"normal"
	while rooms_left > 0:
		dir = determine_next_dir(pos, dir, rng)
		pos += dir
		var i := pos.x + pos.y * width
		if lvl[i] == null:
			lvl[i] = &"normal"
			rooms_left -= 1

func determine_next_dir(pos: Vector2i, cur_dir: Vector2i, rng: RandomNumberGenerator):
	var v = pos + cur_dir
	if rng.randf() <= 0.1 && v.x >= 0 && v.y >= 0 && v.x < width && v.y < width:
		return cur_dir
	var dir = dirs[rng.randi_range(0, 3)]
	v = pos + dir
	if v.x < 0 || v.y < 0 || v.x >= width || v.y >= width:
		return Vector2i(-dir.x, -dir.y)
	return dir

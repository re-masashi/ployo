extends Node
class_name RoomGenerator

@export var width := 7
@export var height := 7
@export var level_count := 5
@export var num_rooms := 10
@export var num_dead_ends := 3
@export var num_extra_stairs := 1
@export var door_scene: PackedScene
@export var all_rooms: Array[RoomData]

@export var bilge: RoomData
@export var brig: RoomData
@export var electrical: RoomData
@export var engine: RoomData
@export var fuel: RoomData
@export var galley: RoomData
@export var medbay: RoomData
@export var storage: RoomData

const dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const door_wall_names := ["DoorWallUp", "DoorWallDown", "DoorWallLeft", "DoorWallRight"]
const door_wall_names_btm := ["DoorWallUpBottom", "DoorWallDownBottom", "DoorWallLeftBottom", "DoorWallRightBottom"]
const place_door_dirs = [Vector2i.RIGHT, Vector2i.DOWN]
# number of space between floors. Rooms are actually 14x14 and 3 tall, but there's 1 unit of space inbetween every floor, so 4.
const room_height := 4
const room_size := 14
const half_room_size := float(room_size) / 2

var levels = make_levels()
var num_rooms_by_type: Dictionary[RoomData, int] = {}

func gen_levels(max_attempts: int, node: Node3D, initial_seed: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = initial_seed
	while max_attempts > 0 and !gen_all_levels(rng):
		initial_seed += 50
		push_warning("failed to generate a level for seed ", initial_seed)
		max_attempts -= 1
		rng.seed = initial_seed
	if max_attempts == 0:
		num_rooms_by_type.clear()
		levels.clear()
		return -1
	instantiate_rooms(node)
	num_rooms_by_type.clear()
	levels.clear()
	return initial_seed

func instantiate_rooms(parent: Node3D):
	for n in level_count:
		var y_3d = -n * room_height
		var lvl = levels[n]
		for x in width:
			for y in height:
				var v = lvl[x + y * width]
				if v == null: continue
				for dir in place_door_dirs:
					var new_pos = Vector2i(x + dir.x, y + dir.y)
					if new_pos.x >= width or new_pos.y >= height: continue
					if lvl[new_pos.x + new_pos.y * width] == null: continue
					var door: Door = door_scene.instantiate()
					door.position.x = room_size * new_pos.x - half_room_size * dir.x
					door.position.y = y_3d
					door.position.z = room_size * new_pos.y - half_room_size * dir.y
					if dir.x > 0: door.rotation.y = deg_to_rad(90)
					parent.add_child(door)
				if !is_instance_of(v, RoomPlacement): continue
				var placement: RoomPlacement = v
				if placement.data.scene == null: continue
				var scene: Node3D = placement.data.scene.instantiate()
				placement.scene = scene
				scene.position = Vector3(x * room_size, y_3d, y * room_size)
				scene.rotation.y = deg_to_rad(placement.rotation)
				parent.add_child(scene)
				var children = scene.get_children()
				for i in 4:
					var node_id = children.find_custom(func(nod) -> bool: return nod.name == door_wall_names[i])
					var node = null if node_id == -1 else children[node_id]
					if placement.closed_sides[i]:
						if node != null and is_instance_of(node, Node3D): node.visible = true
						else: push_warning("couldn't close ", door_wall_names[i], " for room at x", y, ", y", y, " l", n, " node=", node)
					elif node != null:
						scene.remove_child(node)
						node.queue_free()
					if placement.data.type == RoomData.RoomType.Stairs:
						var btm_node_id = children.find_custom(func(nod) -> bool: return nod.name == door_wall_names_btm[i])
						var btm_node = null if btm_node_id == -1 else children[btm_node_id]
						if placement.closed_sides_bottom[i]:
							if btm_node != null and is_instance_of(btm_node, Node3D): btm_node.visible = true
							else: push_warning("couldn't close ", door_wall_names_btm[i], " for room at x", y, ", y", y, " l", n)
						elif btm_node != null:
							scene.remove_child(btm_node)
							btm_node.queue_free()

func make_levels():
	var lvls = []
	for i in level_count:
		lvls.insert(i, [])
		lvls[i].resize(width * height)
	return lvls

func gen_all_levels(rng: RandomNumberGenerator) -> bool:
	levels = make_levels()
	num_rooms_by_type = {}
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
	if !place_needed_rooms(rng): return false
	for i in level_count: select_rooms(i, rng)
	for i in level_count: place_rooms(i, rng)
	return true

func room_types(tys: Array):
	for n in level_count:
		var lvl = []
		tys.push_back(lvl)
		var real_lvl = levels[n]
		for x in width:
			for y in height:
				if real_lvl[x + y * width] == null: lvl.push_back(null)
				else:  lvl.push_back(room_type_at(real_lvl, x, y))

func compatible_room_types(tys: Array, lvl: Array, data: RoomData) -> int:
	var i = 0
	for idx in tys.size():
		if tys[idx] == null: continue
		@warning_ignore("integer_division")
		if compatible(tys[idx], data.type) and not has_forbidden_neighbors(lvl, idx % width, idx / width, data):
			i += 1
	return i

func place_room_pos(lvl: Array, room: RoomData, rng: RandomNumberGenerator) -> bool:
	var spots: Array[int] = []
	for x in width:
		for y in height:
			var i = x + y * width
			if lvl[i] == null || is_instance_of(lvl[i], RoomData): continue
			var rty = room_type_at(lvl, x, y)
			if rty == RoomData.RoomType.Stairs: continue
			if !compatible(rty, room.type): continue
			if has_forbidden_neighbors(lvl, x, y, room): continue
			spots.push_back(i)
	if spots.is_empty(): return false
	lvl[spots[rng.randi_range(0, spots.size() - 1)]] = room
	return true

func place_needed_rooms(rng: RandomNumberGenerator) -> bool:
	# bilge
	if bilge != null:
		if !place_room_pos(levels.back(), bilge, rng): return false
	# galley
	if galley != null:
		var n = rng.rand_weighted(PackedFloat32Array([1, 0.71, 0.42, 0.14, 0.02]))
		if !place_room_pos(levels[n], galley, rng): return false
	# medbay
	if medbay != null:
		var n = rng.rand_weighted(PackedFloat32Array([1, 0.76, 0.61, 0.3, 0.15]))
		if !place_room_pos(levels[n], medbay, rng): return false
	# engine
	if engine != null:
		var n = rng.rand_weighted(PackedFloat32Array([0.5, 0.8, 1.0, 0.3, 0.1]))
		if !place_room_pos(levels[n], engine, rng): return false
	# electrical
	if electrical != null:
		var n = rng.rand_weighted(PackedFloat32Array([0.8, 1.0, 0.5]))
		if !place_room_pos(levels[n], electrical, rng): return false
	# fuel
	if fuel != null:
		var n = rng.rand_weighted(PackedFloat32Array([0.3, 0.5, 0.7, 1.0, 0.9]))
		if !place_room_pos(levels[n], fuel, rng): return false
	# storage
	if storage != null:
		var n = rng.rand_weighted(PackedFloat32Array([1, 0.9, 0.7, 0.4, 0.1]))
		if !place_room_pos(levels[n], storage, rng): return false
	# brig
	if brig != null:
		var n = rng.randi_range(0, 4)
		if !place_room_pos(levels[n], brig, rng): return false
	
	return true

func select_rooms(n: int, rng: RandomNumberGenerator):
	var lvl = levels[n]
	for x in width:
		for y in height:
			var v = lvl[x + y * width]
			if v == null || is_instance_of(v, RoomData): continue
			var rooms: Array[RoomData] = []
			var preferred_room_type = rooms_for_pos(n, x, y, rooms)
			if rooms.is_empty(): continue
			var max_prob = 0.0
			for room in rooms:
				var mul = 1.0 if room.type == preferred_room_type else 0.8
				match room.probabilities.size():
					0: max_prob += mul
					1: max_prob += mul * room.probabilities[0]
					_: max_prob += mul * room.probabilities[n]
			var prob = rng.randf_range(0.0, max_prob - 0.1)
			var selected_room = null
			for room in rooms:
				var my_prob = 1.0 if room.type == preferred_room_type else 0.8
				match room.probabilities.size():
					0: pass
					1: prob *= room.probabilities[0]
					_: prob *= room.probabilities[n]
				if prob - my_prob <= 0.0:
					selected_room = room
					break
				else: prob -= my_prob
			if selected_room == null: selected_room = rooms.back()
			lvl[x + y * width] = selected_room

# TODO: separate placement and selection out so that selection happens randomly after the places for
# pre-determined required special rooms have been selected, so that the rest of placement doesn't have to be duplicated.
func place_rooms(n: int, rng: RandomNumberGenerator):
	var lvl = levels[n]
	for x in width:
		for y in height:
			var v = lvl[x + y * width]
			if v == null || !is_instance_of(v, RoomData): continue
			var selected_room: RoomData = v
			var placement = RoomPlacement.new()
			if num_rooms_by_type.has(selected_room): num_rooms_by_type[selected_room] += 1
			else: num_rooms_by_type[selected_room] = 1
			placement.data = selected_room
			placement.rotation = rotate_room(lvl, x, y, selected_room, rng)
			var sides_with_doors: int = RoomData.ty_to_doors(selected_room.type) >> (placement.rotation / 90)
			var doors = (sides_with_doors & 0xf) & (doorways_at(lvl, x, y) ^ 0xf)
			var sides_with_closed_doors: int = (doors | (doors << 4)) >> (4 - (placement.rotation / 90))
			placement.closed_sides.push_back(bool(sides_with_closed_doors & 0b1000))
			placement.closed_sides.push_back(bool(sides_with_closed_doors & 0b0010))
			placement.closed_sides.push_back(bool(sides_with_closed_doors & 0b0100))
			placement.closed_sides.push_back(bool(sides_with_closed_doors & 0b0001))
			if selected_room.type == RoomData.RoomType.Stairs:
				var btm_sides_with_doors: int = RoomData.ty_to_doors(selected_room.type) >> (placement.rotation / 90)
				doors = (btm_sides_with_doors & 0xf) & (doorways_at(levels[n + 1], x, y) ^ 0xf)
				var btm_sides_with_closed_doors: int = (doors | (doors << 4)) >> (4 - (placement.rotation / 90))
				placement.closed_sides_bottom.push_back(bool(btm_sides_with_closed_doors & 0b1000))
				placement.closed_sides_bottom.push_back(bool(btm_sides_with_closed_doors & 0b0010))
				placement.closed_sides_bottom.push_back(bool(btm_sides_with_closed_doors & 0b0100))
				placement.closed_sides_bottom.push_back(bool(btm_sides_with_closed_doors & 0b0001))
			lvl[x + y * width] = placement

func doorways_at(lvl: Array, x: int, y: int) -> int:
	var i = 0
	if y > 0 && lvl[x + (y - 1) * width] != null: i |= 0b1000
	if y + 1 < height && lvl[x + (y + 1) * width] != null: i |= 0b0010
	if x > 0 && lvl[x - 1 + y * width] != null: i |= 0b0100
	if x + 1 < width && lvl[x + 1 + y * width] != null: i |= 0b0001
	return i

func rotate_room(lvl: Array, x: int, y: int, room: RoomData, rng: RandomNumberGenerator) -> int:
	var i = doorways_at(lvl, x, y)
	var valid_rots: Array[int] = []
	var i_room = RoomData.ty_to_doors(room.type)
	for j in 4:
		if i | i_room == i_room: valid_rots.push_back(j * 90)
		i_room >>= 1
	if valid_rots.is_empty():
		push_error("no valid rotations ", i, " ", i_room, " for room ", room)
		return 0
	var v = valid_rots[rng.randi_range(0, valid_rots.size() - 1)]
	if v < 0: return 360 - v
	return v

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
		push_warning("no available stair locations for level ", upper, " to ", upper + 1)
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

func room_type_at(lvl: Array, x: int, y: int) -> RoomData.RoomType:
	if lvl[x + y * width] == &"stair" or lvl[x + y * width] == &"stairend": return RoomData.RoomType.Stairs
	else:
		var doors: Array[Vector2i] = []
		for dir in dirs:
			var pos = Vector2i(x + dir.x, y + dir.y)
			if pos.x < 0 || pos.y < 0 || pos.x >= width || pos.y >= width: continue
			if lvl[pos.x + pos.y * width] == null: continue
			doors.push_back(dir)
		return preferred_type(doors)

func has_forbidden_neighbors(lvl: Array, x: int, y: int, room: RoomData) -> bool:
	if room.cannot_border_tag.is_empty(): return false
	for dir in dirs:
			var pos = Vector2i(x + dir.x, y + dir.y)
			if pos.x < 0 || pos.y < 0 || pos.x >= width || pos.y >= width: continue
			var v = lvl[pos.x + pos.y * width]
			if v == null || !is_instance_of(v, RoomData) || (v as RoomData).tag.is_empty(): continue
			if room.cannot_border_tag.has((v as RoomData).tag):
				return true
	return false

### Returns the preferred room type
func rooms_for_pos(n: int, x: int, y: int, rooms: Array[RoomData]) -> RoomData.RoomType:
	var lvl = levels[n]
	if lvl[x + y * width] == &"stairend": return RoomData.RoomType.Stairs
	var preferred_room_type := room_type_at(lvl, x, y)
	for room in all_rooms:
		if !compatible(preferred_room_type, room.type): continue
		if room.maximum_count > 0 && num_rooms_by_type.has(room) && num_rooms_by_type[room] >= room.maximum_count: continue
		if room.probabilities.size() > 1 and room.probabilities[n] <= 0: continue
		if has_forbidden_neighbors(lvl, x, y, room): continue
		rooms.push_back(room)
	
	return preferred_room_type

### if room of type b can be placed in a cell of type a
func compatible(a: RoomData.RoomType, b: RoomData.RoomType) -> bool:
	if b == RoomData.RoomType.Stairs: return a == b
	match a:
		RoomData.RoomType.DeadEnd: return b != RoomData.RoomType.Hallway and b != RoomData.RoomType.Corner
		RoomData.RoomType.Hallway: return b != RoomData.RoomType.DeadEnd and b != RoomData.RoomType.Corner
		RoomData.RoomType.Corner: return b != RoomData.RoomType.Hallway and b != RoomData.RoomType.DeadEnd
		RoomData.RoomType.Threeway: return b == RoomData.RoomType.Threeway or b == RoomData.RoomType.Fourway
		RoomData.RoomType.Fourway: return b == RoomData.RoomType.Fourway
		RoomData.RoomType.Stairs: return b == RoomData.RoomType.Stairs
		_:
			push_error("unknown roomtype ", b)
			return false

func preferred_type(doors: Array[Vector2i]) -> RoomData.RoomType:
	match doors.size():
		1: return RoomData.RoomType.DeadEnd
		2:
			if doors[0].x == -doors[1].x and doors[0].y == -doors[1].y: return RoomData.RoomType.Hallway
			else: return RoomData.RoomType.Corner
		3: return RoomData.RoomType.Threeway
		4: return RoomData.RoomType.Fourway
		_: 
			push_error("room with ", doors.size(), " doors")
			return RoomData.RoomType.Fourway

extends Node3D

@export var seed_value: int = 1
@export var support_room_count: int = 8
@export var spawn_test_player := true
@export var spawn_layer := 4
@export var world_scale := 1.0 / 3.0

func _ready() -> void:
	var ship := ShipOutline.new()
	var gen := RoomGenerator.new(ship, seed_value, support_room_count)
	gen.generate()

	var builder := ShipBuilder.new(ship, gen)
	var built := builder.build()
	built.scale = Vector3.ONE * world_scale
	add_child(built)

	if spawn_test_player:
		var fly_cam := get_node_or_null("Camera3D")
		if fly_cam != null:
			fly_cam.current = false
		var layer := clampi(spawn_layer, 1, 4)
		var cz := 60.0
		for c in gen.corridors:
			if c["layer"] == layer:
				cz = (float(c["z_min"]) + float(c["z_max"])) * 0.5
		var player := TestPlayer.new()
		player.position = Vector3(0, (ShipBuilder.LAYER_Y[layer - 1] + 1.0) * world_scale, cz * world_scale)
		add_child(player)

	_print_layout(gen)
	_check_hull_fit(ship, gen)

func _check_hull_fit(ship: ShipOutline, gen: RoomGenerator) -> void:
	var full_outline := ship.get_outline()
	var violations := 0

	var mesh_halfwidths := _sample_ship_glb()
	print("hull fit check")
	print("full outline points: %d" % full_outline.size())
	if mesh_halfwidths.is_empty():
		print("WARNING: could not sample ship.glb mesh")
	for room in gen.rooms:
		var rc: Vector2 = room["center"]
		var room_rect := Rect2(
			(rc.x - room["half_w"]) * world_scale,
			(rc.y - room["half_d"]) * world_scale,
			room["half_w"] * 2 * world_scale,
			room["half_d"] * 2 * world_scale)
		var ok_outline := ShipOutline.contains_rect(full_outline, room["center"], room["half_w"], room["half_d"])
		var ok_mesh := true
		if not mesh_halfwidths.is_empty():
			ok_mesh = _rect_inside_mesh(room_rect, mesh_halfwidths)
		var name_str: String = RoomData.get_def(room["type"])["name"]
		var status := "OK" if (ok_outline and ok_mesh) else "VIOLATION"
		if not (ok_outline and ok_mesh):
			violations += 1
		print("  %-22s l%d  outline=%s  mesh=%s  %s" % [
			name_str, room["layer"],
			"ok" if ok_outline else "OUT",
			"ok" if ok_mesh else "OUT",
			status])
	var overlap_pairs := 0
	for i in gen.rooms.size():
		for j in range(i + 1, gen.rooms.size()):
			var a: Dictionary = gen.rooms[i]
			var b: Dictionary = gen.rooms[j]
			if a["layer"] != b["layer"]:
				continue
			if _rects_overlap(
				a["center"].x - a["half_w"], a["center"].y - a["half_d"],
				a["center"].x + a["half_w"], a["center"].y + a["half_d"],
				b["center"].x - b["half_w"], b["center"].y - b["half_d"],
				b["center"].x + b["half_w"], b["center"].y + b["half_d"]):
				overlap_pairs += 1
				violations += 1
				print("  OVERLAP l%d: %s vs %s" % [
					a["layer"],
					RoomData.get_def(a["type"])["name"],
					RoomData.get_def(b["type"])["name"]])
	print("room overlaps: %d" % overlap_pairs)
	for stair in gen.stairs:
		var ok := ShipOutline.contains_rect(full_outline, stair["center"], stair["half_w"], stair["half_d"])
		if not ok:
			violations += 1
		print("  stair l%d->l%d  %s" % [stair["from_layer"], stair["from_layer"] + 1,
			"ok" if ok else "VIOLATION"])
	print("violations: %d" % violations)

func _rects_overlap(ax0: float, az0: float, ax1: float, az1: float, bx0: float, bz0: float, bx1: float, bz1: float) -> bool:
	return ax0 < bx1 and ax1 > bx0 and az0 < bz1 and az1 > bz0

func _sample_ship_glb() -> Dictionary:
	var packed: PackedScene = load("res://assets/ship.glb")
	if packed == null:
		return {}
	var inst := packed.instantiate()
	var result := {}
	var stack: Array[Dictionary] = [{"node": inst, "xf": Transform3D.IDENTITY}]
	while not stack.is_empty():
		var entry: Dictionary = stack.pop_back()
		var n: Node = entry["node"]
		var xf: Transform3D = entry["xf"] * n.transform
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in verts:
					var world_v := xf * v
					var z_key := roundf(world_v.z)
					var abs_x := absf(world_v.x)
					if not result.has(z_key) or abs_x > result[z_key]:
						result[z_key] = abs_x
		for c in n.get_children():
			stack.append({"node": c, "xf": xf})
	inst.queue_free()
	return result

func _rect_inside_mesh(rect: Rect2, mesh_halfwidths: Dictionary) -> bool:
	if mesh_halfwidths.is_empty():
		return true
	var zs := mesh_halfwidths.keys()
	zs.sort()
	var samples: Array[Vector2] = []
	samples.append(rect.position)
	samples.append(Vector2(rect.end.x, rect.position.y))
	samples.append(rect.end)
	samples.append(Vector2(rect.position.x, rect.end.y))
	samples.append(rect.get_center())
	for s in samples:
		var hw_at_z := _interp_halfwidth(zs, mesh_halfwidths, s.y)
		if absf(s.x) > hw_at_z:
			return false
	return true

func _interp_halfwidth(zs: Array, mesh_halfwidths: Dictionary, z: float) -> float:
	if zs.is_empty():
		return INF
	if z <= zs[0]:
		return mesh_halfwidths[zs[0]]
	if z >= zs.back():
		return mesh_halfwidths[zs.back()]
	for i in range(zs.size() - 1):
		var z0: float = zs[i]
		var z1: float = zs[i + 1]
		if z >= z0 and z <= z1:
			var hw0: float = mesh_halfwidths[z0]
			var hw1: float = mesh_halfwidths[z1]
			if hw0 < 1.0 and hw1 < 1.0:
				return maxf(hw0, hw1)
			if hw0 < 1.0:
				return hw1
			if hw1 < 1.0:
				return hw0
			var t := 0.0 if z1 == z0 else (z - z0) / (z1 - z0)
			return lerpf(hw0, hw1, t)
	return INF

func _print_layout(gen: RoomGenerator) -> void:
	print("rooms: %d" % gen.rooms.size())
	for layer in range(1, 5):
		var count := 0
		for r in gen.rooms:
			if r["layer"] == layer:
				count += 1
		print("l%d: %d rooms" % [layer, count])
		for r in gen.rooms:
			if r["layer"] == layer:
				print("   %-22s c=(%6.1f,%6.1f) size=%.1fx%.1f" % [
					RoomData.get_def(r["type"])["name"],
					r["center"].x, r["center"].y,
					r["half_w"] * 2, r["half_d"] * 2])
	print("stairs: %d" % gen.stairs.size())
	for s in gen.stairs:
		print("   l%d->l%d at (%.1f,%.1f)" % [s["from_layer"], s["from_layer"] + 1, s["center"].x, s["center"].y])
	print("ladders: %d" % gen.ladders.size())
	for l in gen.ladders:
		var room: Dictionary = gen.rooms[l["room_index"]]
		var side_names := ["+x", "-x", "+z", "-z"]
		print("   l%d->l%d on %s wall %s" % [l["from_layer"], l["from_layer"] + 1, RoomData.get_def(room["type"])["name"], side_names[l["side"]]])

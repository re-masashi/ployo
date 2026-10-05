class_name ShipBuilder
extends RefCounted

const LAYER_Y: Array[float] = [0.0, 12.0, 24.0, 42.0, 60.0]
const WALL_THICKNESS := 0.4
const LADDER_HOLE_HALF := 1.0
const DOOR_WIDTH := 4.0
const DOOR_MARGIN := 1.0
const WALL_SINK := 0.1
const WALL_TOP_GAP := 0.05
const STEP_EPS := 0.05
const DECK_THICKNESS := 0.5

static func ladder_top_xz(ladder: Dictionary, room: Dictionary) -> Vector2:
	match int(ladder["side"]):
		0:
			return Vector2(room["center"].x + room["half_w"] - 0.5, room["center"].y)
		1:
			return Vector2(room["center"].x - room["half_w"] + 0.5, room["center"].y)
		2:
			return Vector2(room["center"].x, room["center"].y + room["half_d"] - 0.5)
		3:
			return Vector2(room["center"].x, room["center"].y - room["half_d"] + 0.5)
	return Vector2(room["center"])

static func deck_holes_for_layer(layer: int, stairs: Array, ladders: Array, rooms: Array) -> Array[Rect2]:
	var holes: Array[Rect2] = []
	var from_layer := layer - 1
	for stair in stairs:
		if int(stair["from_layer"]) != from_layer:
			continue
		var c: Vector2 = stair["center"]
		var hw: float = stair["half_w"]
		var hd: float = stair["half_d"]
		holes.append(Rect2(c.x - hw, c.y - hd, hw * 2.0, hd * 2.0))
	for ladder in ladders:
		if int(ladder["from_layer"]) != from_layer:
			continue
		var room: Dictionary = rooms[int(ladder["room_index"])]
		var top := ladder_top_xz(ladder, room)
		holes.append(Rect2(
			top.x - LADDER_HOLE_HALF,
			top.y - LADDER_HOLE_HALF,
			LADDER_HOLE_HALF * 2.0,
			LADDER_HOLE_HALF * 2.0))
	return holes

static func deck_triangulation(outline, holes: Array[Rect2]) -> Dictionary:
	var outline_pts := PackedVector2Array()
	if outline is PackedVector2Array:
		outline_pts = outline.duplicate()
	else:
		for p in outline:
			outline_pts.append(p)

	var base_indices := Geometry2D.triangulate_polygon(outline_pts)
	if base_indices.is_empty():
		return {"points": outline_pts, "indices": PackedInt32Array()}

	if holes.is_empty():
		return {"points": outline_pts, "indices": base_indices}

	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(0, base_indices.size(), 3):
		var tri := PackedVector2Array([
			outline_pts[base_indices[i]],
			outline_pts[base_indices[i + 1]],
			outline_pts[base_indices[i + 2]],
		])
		var pieces: Array = [tri]
		for hole in holes:
			var next_pieces: Array = []
			for piece in pieces:
				next_pieces.append_array(_poly_minus_rect(piece, hole))
			pieces = next_pieces
		for piece in pieces:
			piece = _dedupe_poly(piece)
			if piece.size() < 3:
				continue
			if absf(_signed_area(piece)) < 1e-8:
				continue
			var base := points.size()
			for p in piece:
				points.append(p)
			for fan in range(1, piece.size() - 1):
				var fan_area := absf(_signed_area(PackedVector2Array([
					piece[0], piece[fan], piece[fan + 1],
				])))
				if fan_area < 1e-8:
					continue
				indices.append(base)
				indices.append(base + fan)
				indices.append(base + fan + 1)
	var welded := PackedVector2Array()
	var welded_indices := PackedInt32Array()
	var seen := {}
	for t in indices:
		var p: Vector2 = points[t]
		var key := Vector2(snappedf(p.x, 0.001), snappedf(p.y, 0.001))
		if seen.has(key):
			welded_indices.append(seen[key])
		else:
			var ni := welded.size()
			seen[key] = ni
			welded.append(p)
			welded_indices.append(ni)
	return {"points": welded, "indices": welded_indices}

static func _dedupe_poly(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 1e-12:
			out.append(p)
	if out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) <= 1e-12:
		out.remove_at(out.size() - 1)
	return out

static func _poly_minus_rect(poly: PackedVector2Array, rect: Rect2) -> Array:
	var cells: Array = [
		[-INF, -INF, rect.position.x, rect.position.y],
		[rect.position.x, -INF, rect.end.x, rect.position.y],
		[rect.end.x, -INF, INF, rect.position.y],
		[-INF, rect.position.y, rect.position.x, rect.end.y],
		[rect.end.x, rect.position.y, INF, rect.end.y],
		[-INF, rect.end.y, rect.position.x, INF],
		[rect.position.x, rect.end.y, rect.end.x, INF],
		[rect.end.x, rect.end.y, INF, INF],
	]
	var result: Array = []
	for cell in cells:
		var clipped := _clip_poly_aabb(poly, cell[0], cell[1], cell[2], cell[3])
		if clipped.size() < 3:
			continue
		if absf(_signed_area(clipped)) < 1e-8:
			continue
		result.append(clipped)
	return result

static func _clip_poly_aabb(poly: PackedVector2Array, min_x: float, min_y: float, max_x: float, max_y: float) -> PackedVector2Array:
	var current := poly
	var planes := [
		[Vector2.RIGHT, -min_x],
		[Vector2.LEFT, max_x],
		[Vector2.DOWN, -min_y],
		[Vector2.UP, max_y],
	]
	for plane in planes:
		var normal: Vector2 = plane[0]
		var offset: float = plane[1]
		current = _clip_poly_halfplane(current, normal, offset)
		if current.size() < 3:
			return PackedVector2Array()
	return current

static func _clip_poly_halfplane(poly: PackedVector2Array, normal: Vector2, offset: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if poly.is_empty():
		return out
	var prev := poly[poly.size() - 1]
	var prev_d := normal.dot(prev) + offset
	var prev_in := prev_d >= 0.0
	for p in poly:
		var d := normal.dot(p) + offset
		var p_in := d >= 0.0
		if p_in != prev_in:
			var denom := prev_d - d
			if absf(denom) > 1e-12:
				var t := prev_d / denom
				out.append(prev.lerp(p, t))
		if p_in:
			out.append(p)
		prev = p
		prev_d = d
		prev_in = p_in
	return out

static func _signed_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var j := (i + 1) % p.size()
		a += p[i].x * p[j].y - p[j].x * p[i].y
	return a * 0.5

var _ship: ShipOutline
var _gen: RoomGenerator

func _init(ship: ShipOutline, gen: RoomGenerator) -> void:
	_ship = ship
	_gen = gen

func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Ship"

	for layer in range(1, 5):
		_build_deck(root, layer)
		_build_walls(root, layer)
		_build_stairs(root, layer)
		_build_ladders(root, layer)

	_build_lights(root)
	_build_hull(root)
	return root

func _build_deck(root: Node3D, layer: int) -> void:
	var poly := _ship.get_layer_polygon(layer)
	var y: float = LAYER_Y[layer - 1]

	var holes := deck_holes_for_layer(layer, _gen.stairs, _gen.ladders, _gen.rooms)
	var tri := deck_triangulation(poly, holes)
	var pts2: PackedVector2Array = tri["points"]
	var indices: PackedInt32Array = tri["indices"]
	if indices.is_empty():
		return

	var tris: Array[PackedInt32Array] = []
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		if a == b or b == c or a == c:
			continue
		var t := PackedInt32Array([a, b, c])
		if _tri_signed_area(pts2[a], pts2[b], pts2[c]) > 0.0:
			t = PackedInt32Array([a, c, b])
		if absf(_tri_signed_area(pts2[t[0]], pts2[t[1]], pts2[t[2]])) < 1e-10:
			continue
		tris.append(t)

	if tris.is_empty():
		return

	var y_bot: float = y - DECK_THICKNESS
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var top_base := 0
	for p in pts2:
		verts.append(Vector3(p.x, y, p.y))
		normals.append(Vector3.UP)

	var bottom_base := verts.size()
	for p in pts2:
		verts.append(Vector3(p.x, y_bot, p.y))
		normals.append(Vector3.DOWN)

	var top_indices := PackedInt32Array()
	var bottom_indices := PackedInt32Array()
	for t in tris:
		top_indices.append(top_base + t[0])
		top_indices.append(top_base + t[1])
		top_indices.append(top_base + t[2])
		bottom_indices.append(bottom_base + t[0])
		bottom_indices.append(bottom_base + t[2])
		bottom_indices.append(bottom_base + t[1])

	var render_indices := PackedInt32Array()
	render_indices.append_array(top_indices)
	render_indices.append_array(bottom_indices)

	for i in poly.size():
		var a2: Vector2 = poly[i]
		var b2: Vector2 = poly[(i + 1) % poly.size()]
		var ta := Vector3(a2.x, y, a2.y)
		var tb := Vector3(b2.x, y, b2.y)
		var ba := Vector3(a2.x, y_bot, a2.y)
		var bb := Vector3(b2.x, y_bot, b2.y)
		var edge := (tb - ta).normalized() if tb.distance_squared_to(ta) > 1e-12 else Vector3.RIGHT
		var n := Vector3(edge.z, 0.0, -edge.x)
		var base := verts.size()
		verts.append_array([ta, tb, bb, ba])
		for _k in 4:
			normals.append(n)
		render_indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	for hole in holes:
		var corners := [
			Vector3(hole.position.x, y, hole.position.y),
			Vector3(hole.end.x, y, hole.position.y),
			Vector3(hole.end.x, y, hole.end.y),
			Vector3(hole.position.x, y, hole.end.y),
		]
		var corners_bot := [
			Vector3(hole.position.x, y_bot, hole.position.y),
			Vector3(hole.end.x, y_bot, hole.position.y),
			Vector3(hole.end.x, y_bot, hole.end.y),
			Vector3(hole.position.x, y_bot, hole.end.y),
		]
		for e in 4:
			var t0: Vector3 = corners[e]
			var t1: Vector3 = corners[(e + 1) % 4]
			var b0: Vector3 = corners_bot[e]
			var b1: Vector3 = corners_bot[(e + 1) % 4]
			var e2 := (t1 - t0).normalized() if t1.distance_squared_to(t0) > 1e-12 else Vector3.RIGHT
			var n2 := Vector3(-e2.z, 0.0, e2.x)
			var base2 := verts.size()
			verts.append_array([t0, t1, b1, b0])
			for _k in 4:
				normals.append(n2)
			render_indices.append_array([base2, base2 + 2, base2 + 1, base2, base2 + 3, base2 + 2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = render_indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Deck%d" % layer
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.22, 0.25)
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	root.add_child(mi)

	var body := StaticBody3D.new()
	body.name = "Deck%d_body" % layer
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	var faces := PackedVector3Array()
	for i in range(0, indices.size(), 3):
		var a := verts[top_base + indices[i]]
		var b := verts[top_base + indices[i + 1]]
		var c := verts[top_base + indices[i + 2]]
		faces.append(a)
		faces.append(b)
		faces.append(c)
		faces.append(a)
		faces.append(c)
		faces.append(b)
	shape.set_faces(faces)
	col.shape = shape
	body.add_child(col)
	root.add_child(body)

static func _tri_signed_area(a: Vector2, b: Vector2, c: Vector2) -> float:
	return 0.5 * ((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))

func _build_walls(root: Node3D, layer: int) -> void:
	var walls_node := Node3D.new()
	walls_node.name = "Walls%d" % layer
	root.add_child(walls_node)

	var y: float = LAYER_Y[layer - 1]
	var wall_h: float = LAYER_Y[layer] - LAYER_Y[layer - 1]
	var batches := {}

	var planes := {}
	for ri in _gen.rooms.size():
		var room: Dictionary = _gen.rooms[ri]
		if room["layer"] != layer:
			continue
		var def: Dictionary = RoomData.get_def(room["type"])
		var color: Color = def["color"]
		var batch_suffix := "_r%d" % ri
		var w: float = room["half_w"] * 2
		var d: float = room["half_d"] * 2
		var cx: float = room["center"].x
		var cz: float = room["center"].y
		var x0 := cx - w / 2.0
		var x1 := cx + w / 2.0
		var side_key := "pos" if cx > 0.0 else "neg"

		for face in [-1.0, 1.0]:
			var z := snappedf(cz + face * d / 2.0, 0.01)
			if not planes.has(z):
				planes[z] = {"pos": [], "neg": [], "color": color}
			planes[z][side_key].append([x0, x1])

		var inner_x := x0 if cx > 0.0 else x1
		var outer_x := x1 if cx > 0.0 else x0
		_emit_wall(walls_node, batches,
			Vector3(WALL_THICKNESS, wall_h, d),
			Vector3(outer_x, y + wall_h / 2.0, cz), color, batch_suffix)
		var z0 := cz - d / 2.0
		var z1 := cz + d / 2.0
		if d >= DOOR_WIDTH + 2.0 * DOOR_MARGIN:
			var seg_len := (d - DOOR_WIDTH) * 0.5
			for seg in [[z0, z0 + seg_len], [z1 - seg_len, z1]]:
				var seg_cz: float = (seg[0] + seg[1]) * 0.5
				_emit_wall(walls_node, batches,
					Vector3(WALL_THICKNESS, wall_h, seg_len),
					Vector3(inner_x, y + wall_h / 2.0, seg_cz), color, batch_suffix)
		else:
			_emit_wall(walls_node, batches,
				Vector3(WALL_THICKNESS, wall_h, d),
				Vector3(inner_x, y + wall_h / 2.0, cz), color, batch_suffix)

	for z in planes:
		var entry: Dictionary = planes[z]
		for side_key in ["pos", "neg"]:
			var spans: Array = entry[side_key]
			if spans.is_empty():
				continue
			var min_x := INF
			var max_x := -INF
			for s in spans:
				min_x = minf(min_x, s[0])
				max_x = maxf(max_x, s[1])
			var width := (max_x - min_x) + WALL_THICKNESS
			var cx := (min_x + max_x) * 0.5
			var size := Vector3(width, wall_h, WALL_THICKNESS)
			var pos := Vector3(cx, y + wall_h / 2.0, z)
			_emit_wall(walls_node, batches, size, pos, entry["color"])

	_flush_batches(walls_node, batches)

func _emit_wall(walls_node: Node3D, batches: Dictionary, size: Vector3, pos: Vector3, color: Color, key_suffix := "") -> void:
	var key := color.to_html() + key_suffix
	var mat: Material = null
	if batches.has(key):
		mat = batches[key]["mat"]
	else:
		var wall_mat := StandardMaterial3D.new()
		wall_mat.albedo_color = color.darkened(0.3)
		wall_mat.roughness = 0.85
		mat = wall_mat
	size.y += WALL_SINK - WALL_TOP_GAP
	pos.y -= (WALL_SINK + WALL_TOP_GAP) * 0.5
	_emit_box(walls_node, batches, key, mat, size, pos)

func _emit_box(parent: Node3D, batches: Dictionary, key: String, mat: Material, size: Vector3, pos: Vector3, with_body := true) -> void:
	if not batches.has(key):
		batches[key] = {"mat": mat, "boxes": []}
	(batches[key]["boxes"] as Array).append({"size": size, "pos": pos})

	if not with_body:
		return
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.position = pos
	body.add_child(col)
	parent.add_child(body)

func _flush_batches(parent: Node3D, batches: Dictionary, cast_shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON) -> void:
	for key in batches:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		for b in (batches[key]["boxes"] as Array):
			var box := BoxMesh.new()
			box.size = b["size"]
			var arr := box.get_mesh_arrays()
			var bv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var bi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var base := verts.size()
			var xf := Transform3D(Basis(), b["pos"])
			for v in bv:
				verts.append(xf * v)
			for n in bn:
				normals.append(n)
			for t in bi:
				indices.append(base + t)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = batches[key]["mat"]
		mi.cast_shadow = cast_shadow
		parent.add_child(mi)

func _build_stairs(root: Node3D, layer: int) -> void:
	var stairs_node := Node3D.new()
	stairs_node.name = "Stairs%d" % layer
	root.add_child(stairs_node)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.58)
	mat.roughness = 0.8
	var batches := {}

	for stair in _gen.stairs:
		if stair["from_layer"] != layer:
			continue
		var y0: float = LAYER_Y[stair["from_layer"] - 1]
		var y1: float = LAYER_Y[stair["from_layer"]]
		var steps := 10
		var rise: float = (y1 - y0) / steps
		var run: float = (stair["half_d"] * 2) / steps

		for i in steps:
			var size := Vector3(stair["half_w"] * 2, rise, run)
			var step_pos := Vector3(
				stair["center"].x,
				y0 + rise * (i + 0.5) - STEP_EPS,
				stair["center"].y - stair["half_d"] + run * (i + 0.5))
			_emit_box(stairs_node, batches, "stair", mat, size, step_pos)

	_flush_batches(stairs_node, batches)

func _build_ladders(root: Node3D, layer: int) -> void:
	var ladders_node := Node3D.new()
	ladders_node.name = "Ladders%d" % layer
	root.add_child(ladders_node)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.65, 0.4)
	mat.roughness = 0.7
	var batches := {}

	for ladder in _gen.ladders:
		if ladder["from_layer"] != layer:
			continue
		var room: Dictionary = _gen.rooms[ladder["room_index"]]
		var y0: float = LAYER_Y[ladder["from_layer"] - 1]
		var y1: float = LAYER_Y[ladder["from_layer"]]
		var height: float = y1 - y0
		var side: int = ladder["side"]
		var top := ladder_top_xz(ladder, room)
		var pos := Vector3(top.x, 0, top.y)

		var rail_offset := 0.3
		for rail_side in [-1, 1]:
			var rail_size := Vector3(0.1, height, 0.1)
			var rail_pos := Vector3.ZERO
			if side < 2:
				rail_pos = pos + Vector3(0, y0 + height / 2.0 - STEP_EPS, rail_side * rail_offset)
			else:
				rail_pos = pos + Vector3(rail_side * rail_offset, y0 + height / 2.0 - STEP_EPS, 0)
			_emit_box(ladders_node, batches, "ladder", mat, rail_size, rail_pos, false)

		var rung_count := int(height / 0.5)
		for i in rung_count:
			var rung_size := Vector3.ZERO
			if side < 2:
				rung_size = Vector3(0.08, 0.08, rail_offset * 2)
			else:
				rung_size = Vector3(rail_offset * 2, 0.08, 0.08)
			_emit_box(ladders_node, batches, "ladder", mat,
				rung_size, pos + Vector3(0, y0 + 0.4 + i * 0.5, 0), false)

	_flush_batches(ladders_node, batches)

func _build_hull(root: Node3D) -> void:
	var packed: PackedScene = load("res://assets/ship.glb")
	if packed == null:
		return
	var ship := packed.instantiate()
	ship.name = "Hull"
	root.add_child(ship)

func _build_lights(root: Node3D) -> void:
	var lights_node := Node3D.new()
	lights_node.name = "Lights"
	root.add_child(lights_node)

	var fixture_mat := StandardMaterial3D.new()
	fixture_mat.albedo_color = Color(0.12, 0.12, 0.13)
	fixture_mat.roughness = 0.55
	fixture_mat.metallic = 0.65

	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(0.08, 0.08, 0.09)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.88, 0.68)
	bulb_mat.emission_energy_multiplier = 2.8
	bulb_mat.roughness = 0.4
	bulb_mat.metallic = 0.2

	var fixture_batches := {
		"fixture": {"mat": fixture_mat, "boxes": []},
		"bulb": {"mat": bulb_mat, "boxes": []},
	}

	for layer in range(1, 5):
		var lamp_y: float = LAYER_Y[layer] - 2.5
		var floor_h: float = LAYER_Y[layer] - LAYER_Y[layer - 1]
		var max_range: float = floor_h * 1.6
		var fixture_y: float = LAYER_Y[layer] - DECK_THICKNESS - 0.25
		var bulb_y: float = LAYER_Y[layer] - DECK_THICKNESS - 0.45
		for corr in _gen.corridors:
			if corr["layer"] != layer:
				continue
			var length: float = float(corr["z_max"]) - float(corr["z_min"])
			var count := clampi(ceili(length / 40.0), 2, 5)
			var spacing := length / float(count)
			for k in count:
				_add_lamp(lights_node, fixture_batches, layer, k,
					Vector3(0, lamp_y, float(corr["z_min"]) + spacing * (float(k) + 0.5)),
					spacing, max_range, fixture_y, bulb_y)
		for room in _gen.rooms:
			if int(room["layer"]) != layer:
				continue
			var room_d: float = float(room["half_d"]) * 2.0
			var rcount := clampi(ceili(room_d / 40.0), 1, 3)
			var rspacing := room_d / float(rcount)
			var cx: float = (room["center"] as Vector2).x
			var cz0: float = (room["center"] as Vector2).y - float(room["half_d"])
			for k in rcount:
				_add_lamp(lights_node, fixture_batches, layer, k,
					Vector3(cx, lamp_y, cz0 + rspacing * (float(k) + 0.5)),
					rspacing, max_range, fixture_y, bulb_y)

	_flush_batches(lights_node, fixture_batches, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

func _add_lamp(lights_node: Node3D, fixture_batches: Dictionary, layer: int, k: int,
		pos: Vector3, spacing: float, max_range: float, fixture_y: float, bulb_y: float) -> void:
	var lamp := SpotLight3D.new()
	lamp.position = pos
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	var warmth := 0.04 * sin(float(k) * 1.7 + float(layer))
	lamp.light_color = Color(1.0, 0.88 + warmth * 0.3, 0.72 + warmth)
	lamp.light_energy = 3.0
	lamp.spot_range = minf(spacing * 0.55 + 8.0, max_range)
	lamp.spot_angle = 60.0
	lamp.spot_attenuation = 1.1
	lamp.shadow_enabled = true
	lights_node.add_child(lamp)

	(fixture_batches["fixture"]["boxes"] as Array).append({
		"size": Vector3(1.4, 0.18, 2.2),
		"pos": Vector3(pos.x, fixture_y, pos.z),
	})
	(fixture_batches["bulb"]["boxes"] as Array).append({
		"size": Vector3(1.0, 0.08, 1.8),
		"pos": Vector3(pos.x, bulb_y, pos.z),
	})

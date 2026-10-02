class_name ShipBuilder
extends RefCounted

const LAYER_Y: Array[float] = [0.0, 12.0, 24.0, 42.0, 60.0]
const WALL_HEIGHT := 10.0
const WALL_THICKNESS := 0.4

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

	_build_hull(root)
	return root

func _build_deck(root: Node3D, layer: int) -> void:
	var poly := _ship.get_layer_polygon(layer)
	var y: float = LAYER_Y[layer - 1]

	var pts2 := PackedVector2Array()
	for p in poly:
		pts2.append(p)

	var indices := Geometry2D.triangulate_polygon(pts2)
	if indices.is_empty():
		return

	var verts := PackedVector3Array()
	for p in poly:
		verts.append(Vector3(p.x, y, p.y))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Deck%d" % layer
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.22, 0.25)
	mat.roughness = 0.85
	mi.material_override = mat
	root.add_child(mi)

	var body := StaticBody3D.new()
	body.name = "Deck%d_body" % layer
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	var faces := PackedVector3Array()
	for i in range(0, indices.size(), 3):
		faces.append(verts[indices[i]])
		faces.append(verts[indices[i + 1]])
		faces.append(verts[indices[i + 2]])
	shape.set_faces(faces)
	col.shape = shape
	body.add_child(col)
	root.add_child(body)

func _build_walls(root: Node3D, layer: int) -> void:
	var walls_node := Node3D.new()
	walls_node.name = "Walls%d" % layer
	root.add_child(walls_node)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.42, 0.38)
	mat.roughness = 0.9

	var y: float = LAYER_Y[layer - 1]

	var planes := {}
	for room in _gen.rooms:
		if room["layer"] != layer:
			continue
		var def: Dictionary = RoomData.get_def(room["type"])
		var color: Color = def["color"]
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

		var side_walls := [
			{"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, d), "pos": Vector3(x0, y + WALL_HEIGHT / 2.0, cz)},
			{"size": Vector3(WALL_THICKNESS, WALL_HEIGHT, d), "pos": Vector3(x1, y + WALL_HEIGHT / 2.0, cz)},
		]
		for wall in side_walls:
			_emit_wall(walls_node, mat, wall["size"], wall["pos"], color)

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
			var size := Vector3(width, WALL_HEIGHT, WALL_THICKNESS)
			var pos := Vector3(cx, y + WALL_HEIGHT / 2.0, z)
			_emit_wall(walls_node, mat, size, pos, entry["color"])

func _emit_wall(walls_node: Node3D, mat: Material, size: Vector3, pos: Vector3, color: Color) -> void:
	var room_mat := StandardMaterial3D.new()
	room_mat.albedo_color = color.darkened(0.3)
	room_mat.roughness = 0.85

	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = room_mat
	walls_node.add_child(mi)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.position = pos
	body.add_child(col)
	walls_node.add_child(body)

func _build_stairs(root: Node3D, layer: int) -> void:
	var stairs_node := Node3D.new()
	stairs_node.name = "Stairs%d" % layer
	root.add_child(stairs_node)

	for stair in _gen.stairs:
		if stair["from_layer"] != layer:
			continue
		var y0: float = LAYER_Y[stair["from_layer"] - 1]
		var y1: float = LAYER_Y[stair["from_layer"]]
		var steps := 10
		var rise: float = (y1 - y0) / steps
		var run: float = (stair["half_d"] * 2) / steps

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.55, 0.58)
		mat.roughness = 0.8

		for i in steps:
			var step := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(stair["half_w"] * 2, rise, run)
			step.mesh = box
			step.position = Vector3(
				stair["center"].x,
				y0 + rise * (i + 0.5),
				stair["center"].y - stair["half_d"] + run * (i + 0.5))
			step.material_override = mat
			stairs_node.add_child(step)

			var body := StaticBody3D.new()
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = box.size
			col.shape = shape
			body.position = step.position
			body.add_child(col)
			stairs_node.add_child(body)

func _build_ladders(root: Node3D, layer: int) -> void:
	var ladders_node := Node3D.new()
	ladders_node.name = "Ladders%d" % layer
	root.add_child(ladders_node)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.65, 0.4)
	mat.roughness = 0.7

	for ladder in _gen.ladders:
		if ladder["from_layer"] != layer:
			continue
		var room: Dictionary = _gen.rooms[ladder["room_index"]]
		var y0: float = LAYER_Y[ladder["from_layer"] - 1]
		var y1: float = LAYER_Y[ladder["from_layer"]]
		var height: float = y1 - y0
		var side: int = ladder["side"]

		var pos := Vector3.ZERO
		match side:
			0: pos = Vector3(room["center"].x + room["half_w"] + WALL_THICKNESS, 0, room["center"].y)
			1: pos = Vector3(room["center"].x - room["half_w"] - WALL_THICKNESS, 0, room["center"].y)
			2: pos = Vector3(room["center"].x, 0, room["center"].y + room["half_d"] + WALL_THICKNESS)
			3: pos = Vector3(room["center"].x, 0, room["center"].y - room["half_d"] - WALL_THICKNESS)

		var rail_offset := 0.3
		for rail_side in [-1, 1]:
			var rail := MeshInstance3D.new()
			var rail_box := BoxMesh.new()
			rail_box.size = Vector3(0.1, height, 0.1)
			if side < 2:
				rail.position = pos + Vector3(0, y0 + height / 2.0, rail_side * rail_offset)
			else:
				rail.position = pos + Vector3(rail_side * rail_offset, y0 + height / 2.0, 0)
			rail.mesh = rail_box
			rail.material_override = mat
			ladders_node.add_child(rail)

		var rung_count := int(height / 0.5)
		for i in rung_count:
			var rung := MeshInstance3D.new()
			var rung_box := BoxMesh.new()
			if side < 2:
				rung_box.size = Vector3(0.08, 0.08, rail_offset * 2)
				rung.position = pos + Vector3(0, y0 + 0.4 + i * 0.5, 0)
			else:
				rung_box.size = Vector3(rail_offset * 2, 0.08, 0.08)
				rung.position = pos + Vector3(0, y0 + 0.4 + i * 0.5, 0)
			rung.mesh = rung_box
			rung.material_override = mat
			ladders_node.add_child(rung)

func _build_hull(root: Node3D) -> void:
	var packed: PackedScene = load("res://assets/ship.glb")
	if packed == null:
		return
	var ship := packed.instantiate()
	ship.name = "Hull"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.78, 0.82, 0.15)
	mat.roughness = 0.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for child in ship.get_children():
		if child is MeshInstance3D:
			child.material_override = mat
	root.add_child(ship)

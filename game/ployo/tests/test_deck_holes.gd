extends SceneTree

const ShipBuilder := preload("res://src/ship_builder.gd")

var _failed := 0
var _passed := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("PASS  ", msg)
	else:
		_failed += 1
		print("FAIL  ", msg)

func _tri_centroids_in_holes(indices: PackedInt32Array, pts: PackedVector2Array, holes: Array[Rect2]) -> int:
	var bad := 0
	for i in range(0, indices.size(), 3):
		var a: Vector2 = pts[indices[i]]
		var b: Vector2 = pts[indices[i + 1]]
		var c: Vector2 = pts[indices[i + 2]]
		var area := absf((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))
		if area < 1e-8:
			continue
		var cen := (a + b + c) / 3.0
		for h in holes:
			var inner := Rect2(h.position + Vector2(0.01, 0.01), h.size - Vector2(0.02, 0.02))
			if inner.has_point(cen):
				bad += 1
				break
	return bad

func test_ladder_top_xz_sides() -> void:
	var room := {"center": Vector2(10, 40), "half_w": 6.0, "half_d": 8.0}
	var inset := 0.5
	var l0 := {"side": 0}
	var l1 := {"side": 1}
	var l2 := {"side": 2}
	var l3 := {"side": 3}
	_ok(ShipBuilder.ladder_top_xz(l0, room).is_equal_approx(Vector2(10 + 6 - inset, 40)), "ladder side0 top xz")
	_ok(ShipBuilder.ladder_top_xz(l1, room).is_equal_approx(Vector2(10 - 6 + inset, 40)), "ladder side1 top xz")
	_ok(ShipBuilder.ladder_top_xz(l2, room).is_equal_approx(Vector2(10, 40 + 8 - inset)), "ladder side2 top xz")
	_ok(ShipBuilder.ladder_top_xz(l3, room).is_equal_approx(Vector2(10, 40 - 8 + inset)), "ladder side3 top xz")

func test_deck_holes_from_stairs() -> void:
	var stairs := [
		{"from_layer": 1, "center": Vector2(0, 30), "half_w": 2.5, "half_d": 2.5},
		{"from_layer": 2, "center": Vector2(0, 50), "half_w": 2.5, "half_d": 2.5},
	]
	var holes := ShipBuilder.deck_holes_for_layer(2, stairs, [], [])
	_ok(holes.size() == 1, "deck2 gets only layer1 stairs (%d)" % holes.size())
	if holes.size() == 1:
		var h: Rect2 = holes[0]
		_ok(h.position.is_equal_approx(Vector2(-2.5, 27.5)), "stair hole position")
		_ok(h.size.is_equal_approx(Vector2(5, 5)), "stair hole size")

func test_deck_holes_from_ladders() -> void:
	var rooms := [
		{"center": Vector2(10, 40), "half_w": 6.0, "half_d": 8.0},
	]
	var ladders := [
		{"from_layer": 2, "room_index": 0, "side": 0},
		{"from_layer": 1, "room_index": 0, "side": 2},
	]
	var holes := ShipBuilder.deck_holes_for_layer(3, [], ladders, rooms)
	_ok(holes.size() == 1, "deck3 gets only layer2 ladders (%d)" % holes.size())
	if holes.size() == 1:
		var top := ShipBuilder.ladder_top_xz(ladders[0], rooms[0])
		var h: Rect2 = holes[0]
		_ok(h.get_center().is_equal_approx(top), "ladder hole centered on top")
		_ok(h.size.x >= 1.0 and h.size.y >= 1.0, "ladder hole large enough to climb")

func test_deck_holes_layer1_empty() -> void:
	var stairs := [{"from_layer": 1, "center": Vector2(0, 30), "half_w": 2.5, "half_d": 2.5}]
	var holes := ShipBuilder.deck_holes_for_layer(1, stairs, [], [])
	_ok(holes.is_empty(), "deck1 has no holes from below")

func test_keyhole_cuts_rect_from_square() -> void:
	var outline := PackedVector2Array([
		Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20),
	])
	var holes: Array[Rect2] = [Rect2(8, 8, 4, 4)]
	var tri := ShipBuilder.deck_triangulation(outline, holes)
	var indices: PackedInt32Array = tri["indices"]
	var pts: PackedVector2Array = tri["points"]
	_ok(indices.size() > 0, "holey deck triangulates (%d)" % indices.size())
	var bad := _tri_centroids_in_holes(indices, pts, holes)
	_ok(bad == 0, "no triangle centroids inside hole (bad=%d)" % bad)

func test_keyhole_multiple_holes() -> void:
	var outline := PackedVector2Array([
		Vector2(0, 0), Vector2(40, 0), Vector2(40, 20), Vector2(0, 20),
	])
	var holes: Array[Rect2] = [Rect2(4, 4, 3, 3), Rect2(20, 8, 4, 6), Rect2(32, 2, 2, 2)]
	var tri := ShipBuilder.deck_triangulation(outline, holes)
	var indices: PackedInt32Array = tri["indices"]
	var pts: PackedVector2Array = tri["points"]
	_ok(indices.size() > 0, "multi-hole deck triangulates (%d)" % indices.size())
	var bad := _tri_centroids_in_holes(indices, pts, holes)
	_ok(bad == 0, "no centroids in any hole (bad=%d)" % bad)

func test_keyhole_no_holes_returns_outline() -> void:
	var outline := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10),
	])
	var holes: Array[Rect2] = []
	var tri := ShipBuilder.deck_triangulation(outline, holes)
	var pts: PackedVector2Array = tri["points"]
	_ok(pts.size() == outline.size(), "empty holes keep outline size")
	for i in outline.size():
		if not pts[i].is_equal_approx(outline[i]):
			_ok(false, "outline point %d preserved" % i)
			return
	_ok(true, "outline points preserved")

func test_ship_deck_faces_exclude_hole_centers() -> void:
	var ship = load("res://src/ship_outline.gd").new()
	var gen_script = load("res://src/room_generator.gd")
	var builder_script = load("res://src/ship_builder.gd")
	var gen = gen_script.new(ship, 1, 8)
	gen.generate()
	var builder = builder_script.new(ship, gen)
	var root: Node3D = builder.build()

	var any_hole_checked := false
	for layer in range(2, 5):
		var holes := ShipBuilder.deck_holes_for_layer(layer, gen.stairs, gen.ladders, gen.rooms)
		if holes.is_empty():
			continue
		var deck_name := "Deck%d" % layer
		var deck := root.get_node_or_null(deck_name)
		_ok(deck != null, "%s exists" % deck_name)
		if deck == null:
			continue
		var arrays: Array = deck.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var pts := PackedVector2Array()
		for v in verts:
			pts.append(Vector2(v.x, v.z))
		for h in holes:
			any_hole_checked = true
			var cen := h.get_center()
			var covered := false
			for i in range(0, indices.size(), 3):
				var a: Vector2 = pts[indices[i]]
				var b: Vector2 = pts[indices[i + 1]]
				var c: Vector2 = pts[indices[i + 2]]
				if _point_in_tri(cen, a, b, c):
					covered = true
					break
			_ok(not covered, "l%d hole center %s not covered by deck faces" % [layer, cen])
	_ok(any_hole_checked, "found at least one hole to check in generated ship")

	for layer in range(2, 5):
		var holes := ShipBuilder.deck_holes_for_layer(layer, gen.stairs, gen.ladders, gen.rooms)
		if holes.is_empty():
			continue
		var body := root.get_node_or_null("Deck%d_body" % layer)
		_ok(body != null, "Deck%d_body exists" % layer)
		if body == null:
			continue
		var col: CollisionShape3D = body.get_child(0)
		var shape: ConcavePolygonShape3D = col.shape
		var faces := shape.get_faces()
		for h in holes:
			var cen := h.get_center()
			var covered := false
			for i in range(0, faces.size(), 3):
				var a: Vector2 = Vector2(faces[i].x, faces[i].z)
				var b: Vector2 = Vector2(faces[i + 1].x, faces[i + 1].z)
				var c: Vector2 = Vector2(faces[i + 2].x, faces[i + 2].z)
				if _point_in_tri(cen, a, b, c):
					covered = true
					break
			_ok(not covered, "l%d collision excludes hole center %s" % [layer, cen])

func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _sign(p, a, b)
	var d2 := _sign(p, b, c)
	var d3 := _sign(p, c, a)
	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)

func _sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)

func _init() -> void:
	test_ladder_top_xz_sides()
	test_deck_holes_from_stairs()
	test_deck_holes_from_ladders()
	test_deck_holes_layer1_empty()
	test_keyhole_cuts_rect_from_square()
	test_keyhole_multiple_holes()
	test_keyhole_no_holes_returns_outline()
	test_ship_deck_faces_exclude_hole_centers()
	print("passed=%d failed=%d" % [_passed, _failed])
	if _failed == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("TESTS FAILED")
		quit(1)

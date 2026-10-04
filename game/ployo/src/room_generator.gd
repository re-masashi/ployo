class_name RoomGenerator
extends RefCounted

const CORRIDOR_HALF := 3.5
const OUTER_MARGIN := 1.0
const MIN_ROOM_W := 12.0
const MIN_ROOM_D := 14.0
const MIN_DECENT_W := 16.0
const WIDTH_FILL_MIN := 0.95
const WIDTH_FILL_MAX := 1.0
const STAIR_SPACING := 50.0

var _ship: ShipOutline
var _rng := RandomNumberGenerator.new()
var _support_room_count: int

var rooms: Array[Dictionary] = []
var stairs: Array[Dictionary] = []
var ladders: Array[Dictionary] = []
var corridors: Array[Dictionary] = []

func _init(ship: ShipOutline, seed_value: int, support_room_count: int) -> void:
	_ship = ship
	_rng.seed = seed_value
	_support_room_count = support_room_count

func generate() -> void:
	rooms.clear()
	stairs.clear()
	ladders.clear()
	corridors.clear()

	var assignments: Array[Dictionary] = []
	for t in RoomData.CORE_ROOMS:
		assignments.append({"type": t, "layer": _pick_layer(t)})
	for t in _pick_support_rooms():
		assignments.append({"type": t, "layer": _pick_layer(t)})

	var by_layer: Array = [[], [], [], []]
	for a in assignments:
		by_layer[a["layer"] - 1].append(a["type"])

	for low in [0, 1]:
		while by_layer[low].size() > 2:
			var moved: int = by_layer[low].pop_back()
			for higher in [2, 3]:
				if _type_allowed_on_layer(moved, higher + 1):
					by_layer[higher].append(moved)
					break

	for layer in range(1, 5):
		var poly := _ship.get_layer_polygon(layer)
		var bounds := _ship.get_bounds(layer)
		corridors.append({
			"layer": layer,
			"z_min": bounds.position.y,
			"z_max": bounds.end.y,
			"half_width": CORRIDOR_HALF,
		})

		var layer_types: Array[int] = []
		for t in by_layer[layer - 1]:
			layer_types.append(t)

		_fill_layer(poly, bounds, layer, layer_types)
		_place_stairs(poly, bounds, layer)
		_place_ladders(layer)

func _type_allowed_on_layer(type: int, layer: int) -> bool:
	var def := RoomData.get_def(type)
	if def["min_layer"] != 0 and layer < def["min_layer"]:
		return false
	if def["max_layer"] != 0 and layer > def["max_layer"]:
		return false
	return true

func _fill_layer(poly: Array[Vector2], bounds: Rect2, layer: int, types: Array[int]) -> void:
	var z_min := bounds.position.y + 3.0
	var z_max := bounds.end.y - 3.0
	if z_max <= z_min or types.is_empty():
		return

	var sorted := types.duplicate()
	sorted.sort_custom(func(a, b):
		var da := RoomData.get_def(a)
		var db := RoomData.get_def(b)
		return da["max_w"] * da["max_d"] > db["max_w"] * db["max_d"]
	)

	var side_starboard: Array[int] = []
	var side_port: Array[int] = []
	var weight_starboard := 0.0
	var weight_port := 0.0
	for type in sorted:
		var def := RoomData.get_def(type)
		var w: float = def["max_w"] * def["max_d"]
		if weight_starboard <= weight_port:
			side_starboard.append(type)
			weight_starboard += w
		else:
			side_port.append(type)
			weight_port += w

	if layer <= 2:
		if side_starboard.size() > 0:
			_place_full_space(poly, z_min, z_max, layer, 1, side_starboard[0])
		if side_port.size() > 0:
			_place_full_space(poly, z_min, z_max, layer, -1, side_port[0])
		_absorb_side_gaps(poly, layer, 1, z_min, z_max)
		_absorb_side_gaps(poly, layer, -1, z_min, z_max)
		return

	_pack_side(poly, z_min, z_max, layer, 1, side_starboard)
	_pack_side(poly, z_min, z_max, layer, -1, side_port)

func _usable_band(poly: Array[Vector2], z_min: float, z_max: float) -> Array[float]:
	var threshold := CORRIDOR_HALF + MIN_ROOM_W
	var best_lo := -1.0
	var best_hi := -1.0
	var best_score := -1.0
	var run_lo := -1.0
	var run_score := 0.0
	var z := z_min
	var step := 2.0
	while z <= z_max + 0.01:
		var hw := _halfwidth_at(poly, z)
		if hw >= threshold:
			if run_lo < 0.0:
				run_lo = z
				run_score = 0.0
			run_score += maxf(0.0, hw - CORRIDOR_HALF) * step
		else:
			if run_lo >= 0.0 and (z - run_lo) >= MIN_ROOM_D and run_score > best_score:
				best_lo = run_lo
				best_hi = z
				best_score = run_score
			run_lo = -1.0
			run_score = 0.0
		z += step
	if run_lo >= 0.0 and (z_max - run_lo) >= MIN_ROOM_D and run_score > best_score:
		best_lo = run_lo
		best_hi = z_max
		best_score = run_score
	if best_hi < 0.0 or best_hi - best_lo < MIN_ROOM_D:
		return []
	return [best_lo, best_hi]

func _place_full_space(poly: Array[Vector2], z_min: float, z_max: float, layer: int, side: int, type: int) -> void:
	var band := _usable_band(poly, z_min, z_max)
	if band.is_empty():
		return
	var b0: float = band[0]
	var b1: float = band[1]

	var best_z := (b0 + b1) * 0.5
	var best_hw := 0.0
	var steps := 12
	for si in steps + 1:
		var zz := lerpf(b0, b1, float(si) / float(steps))
		var hw := _halfwidth_at(poly, zz)
		if hw > best_hw:
			best_hw = hw
			best_z = zz

	var room_w := best_hw - CORRIDOR_HALF - OUTER_MARGIN
	if room_w < MIN_ROOM_W:
		room_w = best_hw - CORRIDOR_HALF
	if room_w < MIN_ROOM_W:
		return

	var need_hw := CORRIDOR_HALF + room_w
	var z0 := best_z
	var z1 := best_z
	var z := best_z
	while z >= b0:
		if _halfwidth_at(poly, z) < need_hw:
			break
		z0 = z
		z -= 2.0
	z = best_z
	while z <= b1:
		if _halfwidth_at(poly, z) < need_hw:
			break
		z1 = z
		z += 2.0
	var room_d := z1 - z0
	if room_d < MIN_ROOM_D:
		room_d = b1 - b0
		room_w = minf(room_w, _halfwidth_at(poly, (b0 + b1) * 0.5) - CORRIDOR_HALF)
		if room_w < MIN_ROOM_W:
			return
		z0 = b0
		z1 = b1

	var z_center := (z0 + z1) * 0.5
	var center := Vector2(side * (CORRIDOR_HALF + room_w * 0.5), z_center)
	if not ShipOutline.contains_rect(poly, center, room_w * 0.5, room_d * 0.5):
		var w2 := room_w
		while w2 >= MIN_ROOM_W:
			var c2 := Vector2(side * (CORRIDOR_HALF + w2 * 0.5), z_center)
			if ShipOutline.contains_rect(poly, c2, w2 * 0.5, room_d * 0.5):
				room_w = w2
				center = c2
				var room := {
					"type": type,
					"layer": layer,
					"center": center,
					"half_w": room_w * 0.5,
					"half_d": room_d * 0.5,
				}
				_expand_outer(poly, room)
				rooms.append(room)
				return
			w2 *= 0.92
		return

	var room := {
		"type": type,
		"layer": layer,
		"center": center,
		"half_w": room_w * 0.5,
		"half_d": room_d * 0.5,
	}
	_expand_outer(poly, room)
	rooms.append(room)

func _expand_outer(poly: Array[Vector2], room: Dictionary) -> void:
	var side: int = 1 if room["center"].x > 0.0 else -1
	var inner := CORRIDOR_HALF
	var half_d: float = room["half_d"]
	var z_center: float = room["center"].y
	var half_w: float = room["half_w"]

	var hw_center := _halfwidth_at(poly, z_center)
	var hi_w := maxf(hw_center - CORRIDOR_HALF, half_w * 2.0)
	hi_w = minf(hi_w, hw_center - 0.5)
	if hi_w <= half_w * 2.0 + 0.05:
		return

	var lo_w: float = half_w * 2.0
	var best_w := lo_w
	var best_cx := side * (inner + lo_w * 0.5)
	for _i in 10:
		var mid_w := (lo_w + hi_w) * 0.5
		var c := Vector2(side * (inner + mid_w * 0.5), z_center)
		if ShipOutline.contains_rect(poly, c, mid_w * 0.5, half_d):
			best_w = mid_w
			best_cx = c.x
			lo_w = mid_w
		else:
			hi_w = mid_w
	if best_w <= half_w * 2.0 + 0.05:
		return
	room["half_w"] = best_w * 0.5
	room["center"] = Vector2(best_cx, z_center)

func _packable_band(poly: Array[Vector2], z_min: float, z_max: float) -> Array[float]:
	var threshold := CORRIDOR_HALF + MIN_DECENT_W
	var best_lo := -1.0
	var best_hi := -1.0
	var best_score := -1.0
	var run_lo := -1.0
	var run_score := 0.0
	var step := 2.0
	var z := z_min
	while z <= z_max + 0.01:
		var hw := _halfwidth_at(poly, z)
		if hw >= threshold:
			if run_lo < 0.0:
				run_lo = z
				run_score = 0.0
			run_score += (hw - CORRIDOR_HALF) * step
		else:
			if run_lo >= 0.0 and (z - run_lo) >= MIN_ROOM_D * 2.0 and run_score > best_score:
				best_lo = run_lo
				best_hi = z
				best_score = run_score
			run_lo = -1.0
			run_score = 0.0
		z += step
	if run_lo >= 0.0 and (z_max - run_lo) >= MIN_ROOM_D * 2.0 and run_score > best_score:
		best_lo = run_lo
		best_hi = z_max
	if best_hi < 0.0 or best_hi - best_lo < MIN_ROOM_D:
		return [z_min, z_max]
	return [best_lo, best_hi]

func _pack_side(poly: Array[Vector2], z_min: float, z_max: float, layer: int, side: int, types: Array[int]) -> void:
	if types.is_empty():
		return
	var band := _packable_band(poly, z_min, z_max)
	z_min = band[0]
	z_max = band[1]
	var total_len := z_max - z_min
	if total_len < MIN_ROOM_D:
		return
	var n := types.size()

	var weights: Array[float] = []
	var total_w := 0.0
	var min_w := INF
	var max_w := 0.0
	for t in types:
		var def := RoomData.get_def(t)
		var w: float = float(def["max_w"] * def["max_d"])
		weights.append(w)
		total_w += w
		min_w = minf(min_w, w)
		max_w = maxf(max_w, w)

	var spans: Array[float] = []
	var remaining := total_len
	for i in n:
		if i == n - 1:
			spans.append(remaining)
			continue
		var want := total_len * (weights[i] / total_w)
		var min_left := MIN_ROOM_D * float(n - 1 - i)
		var span := 0.0
		if remaining - min_left >= MIN_ROOM_D:
			span = clampf(want, MIN_ROOM_D, remaining - min_left)
		else:
			span = maxf(0.0, remaining - min_left)
		spans.append(span)
		remaining -= span

	var span_z0: Array[float] = []
	var span_z1: Array[float] = []
	var z := z_min
	for i in n:
		span_z0.append(z)
		span_z1.append(z + spans[i])
		z += spans[i]

	var span_order: Array[int] = []
	var mid := n / 2
	span_order.append(mid)
	for i in range(1, n):
		if mid + i < n:
			span_order.append(mid + i)
		if mid - i >= 0:
			span_order.append(mid - i)

	for i in n:
		var si: int = span_order[i]
		if si < 0 or si >= n:
			continue
		var z0: float = span_z0[si]
		var z1: float = span_z1[si]
		var span: float = z1 - z0
		if span < MIN_ROOM_D * 0.5:
			continue

		var z_center := (z0 + z1) * 0.5
		var room_d := span

		var hw := _halfwidth_at(poly, z_center)
		var avail_w := hw - CORRIDOR_HALF - OUTER_MARGIN
		if avail_w < MIN_ROOM_W:
			avail_w = hw - CORRIDOR_HALF
		if avail_w < MIN_ROOM_W:
			continue

		var room_w := minf(avail_w, maxf(avail_w * WIDTH_FILL_MAX, MIN_ROOM_W))
		var center := Vector2(side * (CORRIDOR_HALF + room_w * 0.5), z_center)
		if not ShipOutline.contains_rect(poly, center, room_w * 0.5, room_d * 0.5):
			var w2 := room_w
			var d2 := room_d
			var fitted := false
			while w2 >= MIN_ROOM_W and d2 >= MIN_ROOM_D:
				var c2 := Vector2(side * (CORRIDOR_HALF + w2 * 0.5), z_center)
				if ShipOutline.contains_rect(poly, c2, w2 * 0.5, d2 * 0.5):
					room_w = w2
					room_d = d2
					center = c2
					fitted = true
					break
				if w2 * 0.92 >= MIN_ROOM_W:
					w2 *= 0.92
				else:
					w2 = room_w
					d2 *= 0.9
			if not fitted:
				continue

		var room := {
			"type": types[i],
			"layer": layer,
			"center": center,
			"half_w": room_w * 0.5,
			"half_d": room_d * 0.5,
		}
		_expand_outer(poly, room)
		rooms.append(room)

	_absorb_side_gaps(poly, layer, side, z_min, z_max)

func _absorb_side_gaps(poly: Array[Vector2], layer: int, side: int, z_min: float, z_max: float) -> void:
	var side_rooms: Array[Dictionary] = []
	for room in rooms:
		if room["layer"] != layer:
			continue
		var rx: float = room["center"].x
		if (rx > 0.0 and side > 0) or (rx < 0.0 and side < 0):
			side_rooms.append(room)
	if side_rooms.is_empty():
		return
	side_rooms.sort_custom(func(a, b): return a["center"].y < b["center"].y)

	var prev_end := z_min
	for room in side_rooms:
		var cz: float = room["center"].y
		var hd: float = room["half_d"]
		var r0 := cz - hd
		var r1 := cz + hd
		if r0 - prev_end > 0.5:
			_try_grow_depth(poly, room, prev_end, r0, -1)
			# refresh after grow
			cz = room["center"].y
			hd = room["half_d"]
			r0 = cz - hd
			r1 = cz + hd
		prev_end = maxf(prev_end, r1)
	if z_max - prev_end > 0.5:
		var last: Dictionary = side_rooms.back()
		var cz: float = last["center"].y
		var hd: float = last["half_d"]
		_try_grow_depth(poly, last, cz + hd, z_max, 1)

func _try_grow_depth(poly: Array[Vector2], room: Dictionary, gap0: float, gap1: float, dir: int) -> void:
	var cz: float = room["center"].y
	var hd: float = room["half_d"]
	var half_w: float = room["half_w"]
	var cx: float = room["center"].x
	var target_d := 0.0
	if dir < 0:
		target_d = cz - gap0
	else:
		target_d = gap1 - cz
	if target_d <= hd + 0.5:
		return
	var new_hd := target_d
	# shrink if hull rejects
	while new_hd > hd + 0.5:
		var c := Vector2(cx, cz)
		if ShipOutline.contains_rect(poly, c, half_w, new_hd):
			room["half_d"] = new_hd
			room["center"] = c
			return
		new_hd = lerpf(hd, new_hd, 0.85)
		if new_hd - hd < 0.5:
			break

func _halfwidth_at(poly: Array[Vector2], z: float) -> float:
	var max_hw := 0.0
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		if (a.y <= z and b.y > z) or (b.y <= z and a.y > z):
			var t := (z - a.y) / (b.y - a.y)
			var x := lerpf(a.x, b.x, t)
			max_hw = maxf(max_hw, absf(x))
	if max_hw == 0.0:
		var best_dist := INF
		for p in poly:
			var d := absf(p.y - z)
			if d < best_dist:
				best_dist = d
				max_hw = absf(p.x)
	return max_hw

func _place_stairs(poly: Array[Vector2], bounds: Rect2, layer: int) -> void:
	var layer_rooms: Array[Dictionary] = []
	for room in rooms:
		if room["layer"] == layer:
			layer_rooms.append(room)
	if layer_rooms.is_empty():
		return

	var rises := [12.0, 12.0, 18.0, 18.0]
	var rise: float = rises[layer - 1]
	var target_slope := 1.0
	var half_d: float = (rise / target_slope) * 0.5
	var half_w: float = 2.5
	var margin := 1.0

	var next_poly := poly if layer >= 4 else _ship.get_layer_polygon(layer + 1)

	var preferred_side := 1 if layer % 2 == 1 else -1
	for side in [preferred_side, -preferred_side]:
		for room in layer_rooms:
			var room_hw: float = room["half_w"]
			var room_hd: float = room["half_d"]
			if room_hw * 2.0 < half_w * 2.0 + margin * 2.0:
				continue
			if room_hd * 2.0 < half_d * 2.0 + margin * 2.0:
				continue

			var room_cx: float = room["center"].x
			var room_cz: float = room["center"].y
			var room_side: int = 1 if room_cx > 0.0 else -1
			if room_side != side:
				continue

			var stair_cx: float = side * (CORRIDOR_HALF + half_w + margin)
			var z_end: float = room_hd - half_d - margin
			var stair_cz: float = room_cz + z_end

			var center := Vector2(stair_cx, stair_cz)
			if not ShipOutline.contains_rect(poly, center, half_w, half_d):
				continue
			if not ShipOutline.contains_rect(next_poly, center, half_w, half_d):
				continue

			stairs.append({
				"from_layer": layer,
				"center": center,
				"half_w": half_w,
				"half_d": half_d,
			})
			break
		if stairs.size() > 0 and stairs.back()["from_layer"] == layer:
			break

func _place_ladders(layer: int) -> void:
	var layer_rooms: Array[int] = []
	for i in rooms.size():
		if rooms[i]["layer"] == layer:
			layer_rooms.append(i)
	if layer_rooms.is_empty():
		return
	var count := mini(2, layer_rooms.size())
	for i in count:
		var ri: int = layer_rooms[i]
		ladders.append({
			"from_layer": layer,
			"room_index": ri,
			"side": _rng.randi_range(0, 3),
		})

func _pick_support_rooms() -> Array[int]:
	var pool: Array[int] = []
	for t in RoomData.SUPPORT_ROOMS:
		pool.append(t)
	var picked: Array[int] = []
	var n: int = mini(_support_room_count, pool.size())
	for i in n:
		var idx: int = _rng.randi_range(0, pool.size() - 1)
		picked.append(pool[idx])
		pool.remove_at(idx)
	return picked

func _pick_layer(type: int) -> int:
	var def := RoomData.get_def(type)
	var candidates: Array[Dictionary] = []
	for l in range(1, 5):
		if def["min_layer"] != 0 and l < def["min_layer"]:
			continue
		if def["max_layer"] != 0 and l > def["max_layer"]:
			continue
		candidates.append({"layer": l, "weight": def["weights"][l - 1]})
	if candidates.is_empty():
		return 1
	var total := 0.0
	for c in candidates:
		total += c["weight"]
	var roll: float = _rng.randf() * total
	for c in candidates:
		roll -= c["weight"]
		if roll <= 0.0:
			return c["layer"]
	return candidates.back()["layer"]

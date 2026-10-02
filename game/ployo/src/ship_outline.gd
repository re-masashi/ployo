class_name ShipOutline
extends RefCounted

const GLB_SCALE := 3.0
# change if ship.glb changes
const STARBOARD_PROFILE: Array[Vector2] = [
	Vector2(-25.8, 0.0),
	Vector2(-22.0, 2.2),
	Vector2(-18.0, 4.2),
	Vector2(-14.0, 6.0),
	Vector2(-10.0, 7.6),
	Vector2(-6.0, 9.2),
	Vector2(-2.0, 10.4),
	Vector2(2.0, 11.4),
	Vector2(6.0, 12.4),
	Vector2(9.4, 13.1),
	Vector2(20.0, 13.1),
	Vector2(30.3, 13.1),
	Vector2(40.0, 13.0),
	Vector2(48.0, 12.2),
	Vector2(51.0, 10.8),
	Vector2(52.3, 8.5),
	Vector2(53.2, 0.0),
]

const LAYER_SCALE: Array[float] = [0.55, 0.70, 0.80, 0.90]

var _outline: Array[Vector2]
var _z_min := 0.0
var _z_max := 0.0

func _init() -> void:
	var pts: Array[Vector2] = []
	for p in STARBOARD_PROFILE:
		pts.append(Vector2(p.y * GLB_SCALE, p.x * GLB_SCALE))  # (x, z)
	for i in range(STARBOARD_PROFILE.size() - 2, 0, -1):
		pts.append(Vector2(-STARBOARD_PROFILE[i].y * GLB_SCALE, STARBOARD_PROFILE[i].x * GLB_SCALE))
	_outline = pts
	_z_min = INF
	_z_max = -INF
	for p in _outline:
		_z_min = minf(_z_min, p.y)
		_z_max = maxf(_z_max, p.y)

func get_outline() -> Array[Vector2]:
	return _outline

func get_layer_polygon(layer: int) -> Array[Vector2]:
	var s: float = LAYER_SCALE[layer - 1]
	var z_center := (_z_min + _z_max) * 0.5
	var pts: Array[Vector2] = []
	for p in _outline:
		pts.append(Vector2(p.x * s, z_center + (p.y - z_center) * s))
	return pts

func get_bounds(layer: int) -> Rect2:
	var poly := get_layer_polygon(layer)
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p in poly:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_z = min(min_z, p.y)
		max_z = max(max_z, p.y)
	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)

static func contains(poly: Array[Vector2], point: Vector2) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		if (a.y > point.y) != (b.y > point.y) and point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside

static func contains_rect(poly: Array[Vector2], center: Vector2, hw: float, hd: float) -> bool:
	for i in 8:
		var dx := hw if (i & 1) != 0 else -hw
		var dz := hd if (i & 2) != 0 else -hd
		if (i & 4) != 0:
			dx *= 0.001
			dz *= 0.001
		if not contains(poly, center + Vector2(dx, dz)):
			return false
	return true

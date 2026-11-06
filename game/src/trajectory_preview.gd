class_name TrajectoryPreview
extends Node3D

const MAX_POINTS := 28
const STEP_TIME := 0.045
const DOT_RADIUS := 0.032
const MARKER_RADIUS := 0.22
const ARC_COLOR := Color(1.0, 0.82, 0.3, 0.9)

var _dots: MultiMeshInstance3D
var _marker: MeshInstance3D
var _point_count := 0


func _ready() -> void:
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = ARC_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true

	var sphere := SphereMesh.new()
	sphere.radius = DOT_RADIUS
	sphere.height = DOT_RADIUS * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = MAX_POINTS
	mm.visible_instance_count = 0
	_dots = MultiMeshInstance3D.new()
	_dots.multimesh = mm
	_dots.material_override = mat
	_dots.top_level = true
	add_child(_dots)

	var ring := TorusMesh.new()
	ring.inner_radius = MARKER_RADIUS * 0.82
	ring.outer_radius = MARKER_RADIUS
	ring.rings = 12
	ring.ring_segments = 6
	_marker = MeshInstance3D.new()
	_marker.mesh = ring
	_marker.material_override = mat
	_marker.top_level = true
	add_child(_marker)
	visible = false


func show_arc(start: Vector3, velocity: Vector3, gravity: float, exclude: Array = []) -> void:
	if _dots == null or _marker == null:
		return
	var space := get_world_3d().direct_space_state if get_world_3d() != null else null
	var points: Array[Vector3] = [start]
	var pos := start
	var vel := velocity
	var hit_pos := Vector3.ZERO
	var hit := false
	for _i in range(MAX_POINTS - 1):
		vel.y -= gravity * STEP_TIME
		var next := pos + vel * STEP_TIME
		if space != null:
			var query := PhysicsRayQueryParameters3D.create(pos, next)
			query.exclude = exclude
			query.collide_with_areas = false
			var result := space.intersect_ray(query)
			if not result.is_empty():
				hit_pos = result["position"]
				points.append(hit_pos)
				hit = true
				break
		points.append(next)
		pos = next

	var mm := _dots.multimesh
	mm.visible_instance_count = points.size()
	for i in range(points.size()):
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
	_point_count = points.size()
	_marker.visible = hit
	if hit:
		_marker.global_position = hit_pos + Vector3.UP * 0.02
	visible = true


func hide_arc() -> void:
	_point_count = 0
	if _dots != null and _dots.multimesh != null:
		_dots.multimesh.visible_instance_count = 0
	if _marker != null:
		_marker.visible = false
	visible = false


func get_point_count() -> int:
	return _point_count

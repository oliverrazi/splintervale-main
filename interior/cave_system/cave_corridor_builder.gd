## CaveCorridorBuilder — Creates connecting passages between cave rooms.
##
## Define a corridor with a Path3D (curve) and a width, and this generates
## the floor mesh, collision walls, and navigation for the passage.
##
## Workflow:
##   1. Add a CaveCorridorBuilder to your cave scene
##   2. Add a Path3D as a child and draw the corridor curve
##   3. Set [member corridor_width] and other properties
##   4. The corridor auto-generates floor + collision + nav
##
## Corridors connect to CaveRoomBuilder rooms where they overlap.

@tool
class_name CaveCorridorBuilder
extends Node3D

# ── Configuration ─────────────────────────────────────────────────────────────

@export_group("Corridor Shape")
## Width of the corridor.
@export var corridor_width: float = 2.5
## How many segments along the length (more = smoother curves).
@export var segments: int = 20
## Floor Y position (match your CaveRoomBuilder floor_y).
@export var floor_y: float = 0.0
## Width variation (0 = constant width, >0 = organic narrowing/widening).
@export_range(0.0, 1.0) var width_variation: float = 0.2
## Seed for width variation randomness.
@export var variation_seed: int = 42

@export_group("Floor")
## Shader material for the corridor floor.
@export var floor_material: Material = null

@export_group("Collision & Navigation")
@export var generate_collision: bool = true
@export var wall_height: float = 3.0
## Disable if using a single NavigationRegion3D for the whole cave.
@export var generate_navigation: bool = false
@export var nav_agent_radius: float = 0.4

@export_group("Building")
@export var build_on_ready: bool = true
@export var rebuild_now: bool = false: set = _trigger_rebuild

# ── Internal ──────────────────────────────────────────────────────────────────

var _floor_mesh: MeshInstance3D
var _collision_body: StaticBody3D
var _nav_region: NavigationRegion3D
var _path: Path3D


func _ready() -> void:
	_find_path()
	if build_on_ready and not Engine.is_editor_hint():
		build_corridor()


func _find_path() -> void:
	for child in get_children():
		if child is Path3D:
			_path = child
			break
	if not _path:
		push_warning("CaveCorridorBuilder: No Path3D child found. Add one and draw a curve.")


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func build_corridor() -> void:
	_find_path()
	if not _path or not _path.curve or _path.curve.point_count < 2:
		push_warning("CaveCorridorBuilder: Path3D needs at least 2 curve points.")
		return

	_clear_generated()
	_build_corridor_floor()
	if generate_collision:
		_build_corridor_collision()
	if generate_navigation:
		_build_corridor_navigation()


## Get the left and right edge points of the corridor.
## Useful for placing rocks along corridor walls.
## Returns: { "left": Array[Vector3], "right": Array[Vector3] }
func get_edge_lines() -> Dictionary:
	if not _path or not _path.curve:
		return { "left": [], "right": [] }

	var left_points: Array[Vector3] = []
	var right_points: Array[Vector3] = []
	var curve := _path.curve
	var length := curve.get_baked_length()

	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed

	for i in (segments + 1):
		var t := float(i) / float(segments)
		var offset := t * length
		var pos := curve.sample_baked(offset)
		pos.y = floor_y

		# Get curve direction at this point for perpendicular
		var forward: Vector3
		if i < segments:
			var next_pos := curve.sample_baked(min(offset + 0.1, length))
			forward = (next_pos - pos).normalized()
		else:
			var prev_pos := curve.sample_baked(max(offset - 0.1, 0))
			forward = (pos - prev_pos).normalized()

		# Perpendicular on XZ plane
		var right := Vector3(forward.z, 0, -forward.x).normalized()

		# Width with variation
		var w := corridor_width * 0.5
		if width_variation > 0:
			var noise_val := sin(t * 8.0 + float(variation_seed)) * 0.5 + 0.5
			w *= (1.0 - width_variation + noise_val * width_variation * 2.0)

		left_points.append(pos - right * w + _path.global_position)
		right_points.append(pos + right * w + _path.global_position)

	return { "left": left_points, "right": right_points }


# ═══════════════════════════════════════════════════════════════════════════════
# FLOOR GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

func _build_corridor_floor() -> void:
	_floor_mesh = MeshInstance3D.new()
	_floor_mesh.name = "GeneratedCorridorFloor"

	var curve := _path.curve
	var length := curve.get_baked_length()

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed

	# Generate vertices along the corridor
	for i in (segments + 1):
		var t := float(i) / float(segments)
		var offset := t * length
		var pos := curve.sample_baked(offset)
		pos.y = floor_y

		# Direction and perpendicular
		var forward: Vector3
		if i < segments:
			var next_pos := curve.sample_baked(min(offset + 0.1, length))
			forward = (next_pos - pos).normalized()
		else:
			var prev_pos := curve.sample_baked(max(offset - 0.1, 0))
			forward = (pos - prev_pos).normalized()

		var right := Vector3(forward.z, 0, -forward.x).normalized()

		# Width with variation
		var w := corridor_width * 0.5
		if width_variation > 0:
			var noise_val := sin(t * 8.0 + float(variation_seed)) * 0.5 + 0.5
			w *= (1.0 - width_variation + noise_val * width_variation * 2.0)

		# Left and right vertices
		var left := pos - right * w
		var right_pt := pos + right * w

		vertices.append(left)
		vertices.append(right_pt)

		normals.append(Vector3.UP)
		normals.append(Vector3.UP)

		# UV: U across width, V along length
		uvs.append(Vector2(0, t * length * 0.5))
		uvs.append(Vector2(1, t * length * 0.5))

		# Vertex color alpha: 1 at center (between left/right), 0 at edges
		# For corridor, both edges are walls
		colors.append(Color(1, 1, 1, 0.1))  # Left edge (near wall)
		colors.append(Color(1, 1, 1, 0.1))  # Right edge (near wall)

	# Add center vertices for better edge-alpha gradient
	# (Re-do with 3 vertices per row: left, center, right)
	vertices.clear()
	normals.clear()
	uvs.clear()
	colors.clear()

	for i in (segments + 1):
		var t := float(i) / float(segments)
		var offset := t * length
		var pos := curve.sample_baked(offset)
		pos.y = floor_y

		var forward: Vector3
		if i < segments:
			forward = (curve.sample_baked(min(offset + 0.1, length)) - pos).normalized()
		else:
			forward = (pos - curve.sample_baked(max(offset - 0.1, 0))).normalized()

		var right := Vector3(forward.z, 0, -forward.x).normalized()
		var w := corridor_width * 0.5
		if width_variation > 0:
			var noise_val := sin(t * 8.0 + float(variation_seed)) * 0.5 + 0.5
			w *= (1.0 - width_variation + noise_val * width_variation * 2.0)

		# 3 points per row: left, center, right
		for j in 3:
			var lateral := float(j) / 2.0  # 0, 0.5, 1
			var pt := pos + right * (lateral * 2.0 - 1.0) * w
			vertices.append(pt)
			normals.append(Vector3.UP)
			uvs.append(Vector2(lateral, t * length * 0.5))
			# Alpha: 0 at edges, 1 at center
			var edge_dist :float = 1.0 - abs(lateral * 2.0 - 1.0)
			colors.append(Color(1, 1, 1, edge_dist))

	# Triangulate: 2 quads per row (left-center, center-right), each quad = 2 tris
	for i in segments:
		var row := i * 3
		var next_row := (i + 1) * 3

		# Left-to-center quad
		indices.append(row)
		indices.append(next_row)
		indices.append(row + 1)

		indices.append(row + 1)
		indices.append(next_row)
		indices.append(next_row + 1)

		# Center-to-right quad
		indices.append(row + 1)
		indices.append(next_row + 1)
		indices.append(row + 2)

		indices.append(row + 2)
		indices.append(next_row + 1)
		indices.append(next_row + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_floor_mesh.mesh = array_mesh

	if floor_material:
		_floor_mesh.material_override = floor_material
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.14, 0.13)
		mat.roughness = 0.85
		_floor_mesh.material_override = mat

	_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floor_mesh)


# ═══════════════════════════════════════════════════════════════════════════════
# COLLISION & NAVIGATION
# ═══════════════════════════════════════════════════════════════════════════════

func _build_corridor_collision() -> void:
	_collision_body = StaticBody3D.new()
	_collision_body.name = "GeneratedCorridorCollision"
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 0

	var edges := get_edge_lines()
	var left: Array = edges["left"]
	var right: Array = edges["right"]

	# ── Floor collision — single trimesh from all segments ──
	var floor_col := CollisionShape3D.new()
	floor_col.name = "CorridorFloorCollision"
	var face_points := PackedVector3Array()

	for i in range(left.size() - 1):
		var l0: Vector3 = left[i] - global_position
		var r0: Vector3 = right[i] - global_position
		var l1: Vector3 = left[i + 1] - global_position
		var r1: Vector3 = right[i + 1] - global_position

		# Two triangles per quad segment
		face_points.append(Vector3(l0.x, floor_y, l0.z))
		face_points.append(Vector3(r0.x, floor_y, r0.z))
		face_points.append(Vector3(l1.x, floor_y, l1.z))

		face_points.append(Vector3(l1.x, floor_y, l1.z))
		face_points.append(Vector3(r0.x, floor_y, r0.z))
		face_points.append(Vector3(r1.x, floor_y, r1.z))

	if face_points.size() > 0:
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(face_points)
		floor_col.shape = concave
		_collision_body.add_child(floor_col)

	# ── Wall collision along both sides ──
	for i in range(left.size() - 1):
		_create_wall_segment(left[i], left[i + 1], "LeftWall_%d" % i, true)
		_create_wall_segment(right[i], right[i + 1], "RightWall_%d" % i, false)

	add_child(_collision_body)


func _create_wall_segment(a: Vector3, b: Vector3, wall_name: String, is_left: bool) -> void:
	var shape := CollisionShape3D.new()
	shape.name = wall_name

	var mid := (a + b) * 0.5 - global_position
	var length := a.distance_to(b)
	var angle := atan2(b.x - a.x, b.z - a.z)

	# Push wall outward — thick enough to block the player
	var dir := (b - a).normalized()
	var thickness := 1.0
	var outward := Vector3(dir.z, 0, -dir.x) * (thickness * 0.5 if is_left else -thickness * 0.5)

	var box := BoxShape3D.new()
	box.size = Vector3(length + 0.2, wall_height, thickness)

	shape.position = mid + outward
	shape.position.y = floor_y + wall_height * 0.5 - 0.5
	shape.rotation.y = -angle
	shape.shape = box

	_collision_body.add_child(shape)


func _build_corridor_navigation() -> void:
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "GeneratedCorridorNav"

	var nav_mesh := NavigationMesh.new()
	var edges := get_edge_lines()
	var left: Array = edges["left"]
	var right: Array = edges["right"]

	# Shrink edges inward for agent radius
	var nav_vertices := PackedVector3Array()
	var center_points: Array[Vector3] = []

	for i in left.size():
		var l: Vector3 = left[i]
		var r: Vector3 = right[i]
		var center := (l + r) * 0.5
		var dir := (r - l).normalized()

		var half_w := l.distance_to(r) * 0.5 - nav_agent_radius
		half_w = max(half_w, 0.2)

		nav_vertices.append(center - dir * half_w)
		nav_vertices.append(center + dir * half_w)

	nav_mesh.vertices = nav_vertices

	# Triangulate as a strip
	for i in range(left.size() - 1):
		var idx := i * 2
		nav_mesh.add_polygon(PackedInt32Array([idx, idx + 2, idx + 1]))
		nav_mesh.add_polygon(PackedInt32Array([idx + 1, idx + 2, idx + 3]))

	nav_mesh.agent_radius = nav_agent_radius
	_nav_region.navigation_mesh = nav_mesh
	add_child(_nav_region)


# ═══════════════════════════════════════════════════════════════════════════════
# EDITOR & CLEANUP
# ═══════════════════════════════════════════════════════════════════════════════

func _trigger_rebuild(value: bool) -> void:
	if value:
		build_corridor()
		rebuild_now = false


func _clear_generated() -> void:
	for name in ["GeneratedCorridorFloor", "GeneratedCorridorCollision", "GeneratedCorridorNav"]:
		var node := get_node_or_null(name)
		if node:
			node.queue_free()

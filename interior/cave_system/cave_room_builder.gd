## CaveRoomBuilder — Define a cave room shape and auto-generate floor, collision, nav.
##
## THIS IS THE CORE BUILDING TOOL.
##
## Workflow:
##   1. Add this node to your cave scene
##   2. In the Inspector, edit [member room_polygon] — add Vector2 points
##      that define the room outline (top-down, XZ plane)
##   3. Click "Build Room" (or it auto-builds on ready)
##   4. The tool generates: floor mesh, collision boundary, navigation region
##   5. Place CaveRockGeometry along the edges for visual walls
##
## You can have MULTIPLE CaveRoomBuilders in one scene:
##   - One for the main hall
##   - One for a side corridor
##   - One for a secret room
##   They connect where their edges overlap.
##
## The polygon is defined as Vector2 points (X, Z) viewed from above.
## Y (height) is controlled separately.

@tool  # Runs in editor for preview
class_name CaveRoomBuilder
extends Node3D

# ── Configuration ─────────────────────────────────────────────────────────────

@export_group("Room Shape")
## The room outline as a polygon. Points are Vector2(x, z) in local space.
## Define clockwise for correct normals. At least 3 points needed.
## TIP: Start simple (rectangle), then add points for organic shapes.
@export var room_polygon: PackedVector2Array = PackedVector2Array([
	Vector2(-4, -3),
	Vector2(4, -3),
	Vector2(5, -1),
	Vector2(4, 3),
	Vector2(-4, 3),
	Vector2(-5, -1),
]): set = _set_polygon

## Optional: additional polygons that get CUT from the room (holes/pillars).
@export var hole_polygons: Array[PackedVector2Array] = []

@export_group("Floor")
## Floor Y position (0 = ground level).
@export var floor_y: float = 0.0
## Shader material for the floor. Assign cave_floor.gdshader material.
@export var floor_material: Material = null
## UV scale for the floor texture.
@export var floor_uv_scale: float = 1.0

@export_group("Collision")
## Wall height for collision (invisible walls around the room edge).
@export var wall_height: float = 3.0
## Wall thickness.
@export var wall_thickness: float = 0.3
## Generate collision walls automatically.
@export var generate_collision: bool = true

@export_group("Navigation")
## Generate a NavigationRegion3D for this room.
## WARNING: If rooms/corridors overlap, disable this and use a SINGLE
## NavigationRegion3D for the whole cave (bake manually or use CaveNavBuilder).
@export var generate_navigation: bool = false
## Agent radius for navigation (should match enemy collision radius).
@export var nav_agent_radius: float = 0.4

@export_group("Edge Detection")
## Margin around the polygon for rock placement guidance.
@export var edge_margin: float = 0.5
## Auto-generate edge markers (Marker3D) for rock placement.
@export var generate_edge_markers: bool = false
## Spacing between edge markers (meters).
@export var edge_marker_spacing: float = 1.5

@export_group("Building")
## Rebuild everything when the scene starts.
@export var build_on_ready: bool = true
## Button to manually trigger a rebuild in editor.
@export var rebuild_now: bool = false: set = _trigger_rebuild

# ── Internal references ───────────────────────────────────────────────────────

var _floor_mesh: MeshInstance3D
var _collision_body: StaticBody3D
var _nav_region: NavigationRegion3D
var _edge_markers_container: Node3D
var _debug_draw: MeshInstance3D  # Editor preview


func _ready() -> void:
	if build_on_ready and not Engine.is_editor_hint():
		build_room()
	elif Engine.is_editor_hint():
		_update_editor_preview()


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

## Build (or rebuild) the entire room: floor, collision, navigation.
func build_room() -> void:
	if room_polygon.size() < 3:
		push_warning("CaveRoomBuilder: Need at least 3 polygon points.")
		return

	_clear_generated()
	_build_floor()
	if generate_collision:
		_build_collision()
	if generate_navigation:
		_build_navigation()
	if generate_edge_markers:
		_build_edge_markers()


## Get the polygon edges as an array of line segments.
## Useful for placing rocks along walls.
## Returns Array of Dictionaries: { "start": Vector3, "end": Vector3, "normal": Vector3 }
func get_edges() -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	var count := room_polygon.size()

	for i in count:
		var a := room_polygon[i]
		var b := room_polygon[(i + 1) % count]

		var start := Vector3(a.x, floor_y, a.y) + global_position
		var end := Vector3(b.x, floor_y, b.y) + global_position

		# Calculate outward normal (perpendicular to edge, pointing outward)
		var edge_dir := (b - a).normalized()
		var normal_2d := Vector2(edge_dir.y, -edge_dir.x)  # Rotate 90° CW
		var normal := Vector3(normal_2d.x, 0, normal_2d.y)

		edges.append({
			"start": start,
			"end": end,
			"normal": normal,
			"length": start.distance_to(end),
			"midpoint": (start + end) * 0.5,
		})

	return edges


## Get sample points along all edges at the given spacing.
## Ideal for automated rock placement.
## Returns Array of Dictionaries: { "position": Vector3, "normal": Vector3 }
func get_edge_points(spacing: float = 1.0) -> Array[Dictionary]:
	var points: Array[Dictionary] = []

	for edge in get_edges():
		var start: Vector3 = edge["start"]
		var end: Vector3 = edge["end"]
		var length: float = edge["length"]
		var normal: Vector3 = edge["normal"]
		var count := int(length / spacing) + 1

		for i in count:
			var t := float(i) / float(max(count - 1, 1))
			var pos := start.lerp(end, t)
			points.append({
				"position": pos,
				"normal": normal,
			})

	return points


## Get the center of the room (average of all polygon points).
func get_center() -> Vector3:
	var sum := Vector2.ZERO
	for p in room_polygon:
		sum += p
	sum /= float(room_polygon.size())
	return Vector3(sum.x, floor_y, sum.y) + global_position


## Get the bounding box of the room.
func get_bounds() -> AABB:
	if room_polygon.size() == 0:
		return AABB()

	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p in room_polygon:
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)

	var origin := Vector3(min_p.x, floor_y - 1, min_p.y) + global_position
	var size := Vector3(max_p.x - min_p.x, wall_height + 2, max_p.y - min_p.y)
	return AABB(origin, size)


# ═══════════════════════════════════════════════════════════════════════════════
# FLOOR GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

func _build_floor() -> void:
	_floor_mesh = MeshInstance3D.new()
	_floor_mesh.name = "GeneratedFloor"
	_floor_mesh.position.y = floor_y

	# Triangulate the polygon to create a floor mesh
	var mesh := _create_polygon_mesh(room_polygon)
	_floor_mesh.mesh = mesh

	# Apply material
	if floor_material:
		_floor_mesh.material_override = floor_material
	else:
		# Default dark stone material
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.14, 0.13)
		mat.roughness = 0.85
		_floor_mesh.material_override = mat

	_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floor_mesh)


func _create_polygon_mesh(polygon: PackedVector2Array) -> ArrayMesh:
	## Triangulates a 2D polygon and creates a flat 3D mesh on the XZ plane.
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.size() == 0:
		push_error("CaveRoomBuilder: Failed to triangulate polygon. "
			+ "Check for self-intersections or wrong winding order.")
		return ArrayMesh.new()

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()

	# Calculate bounds for UV mapping and edge distance
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p in polygon:
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)
	var bounds_size := max_p - min_p

	for idx in indices:
		var p := polygon[idx]
		vertices.append(Vector3(p.x, 0, p.y))
		normals.append(Vector3(0, 1, 0))

		# UV from world position (for tiling textures)
		var uv := (p - min_p) / bounds_size * floor_uv_scale
		uvs.append(uv)

		# Vertex color alpha = distance from edge (for cave_floor.gdshader edge darkening)
		var edge_dist := _point_to_polygon_edge_distance(p, polygon)
		var edge_factor := clampf(edge_dist / 3.0, 0.0, 1.0)  # Normalize: 0=at edge, 1=center
		colors.append(Color(1, 1, 1, edge_factor))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh


func _point_to_polygon_edge_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	## Returns the minimum distance from a point to any edge of the polygon.
	var min_dist := INF
	var count := polygon.size()

	for i in count:
		var a := polygon[i]
		var b := polygon[(i + 1) % count]
		var dist := _point_to_segment_distance(point, a, b)
		min_dist = min(min_dist, dist)

	return min_dist


func _point_to_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := p - a
	var t := clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
	var closest := a + ab * t
	return p.distance_to(closest)


# ═══════════════════════════════════════════════════════════════════════════════
# COLLISION GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

func _build_collision() -> void:
	_collision_body = StaticBody3D.new()
	_collision_body.name = "GeneratedCollision"
	_collision_body.collision_layer = 1  # World collision
	_collision_body.collision_mask = 0

	# ── Floor collision matching the EXACT polygon shape ──
	# Use ConcavePolygonShape3D (trimesh) — works perfectly for static floors
	var floor_col := CollisionShape3D.new()
	floor_col.name = "FloorCollision"

	var tri_indices := Geometry2D.triangulate_polygon(room_polygon)
	if tri_indices.size() > 0:
		var face_points := PackedVector3Array()
		for idx in tri_indices:
			var p := room_polygon[idx]
			face_points.append(Vector3(p.x, floor_y, p.y))

		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(face_points)
		floor_col.shape = concave
	else:
		# Fallback: simple box
		push_warning("CaveRoomBuilder: Could not triangulate polygon for collision.")
		var box := BoxShape3D.new()
		box.size = Vector3(10, 0.1, 10)
		floor_col.shape = box

	_collision_body.add_child(floor_col)

	# ── Wall collision for each edge — thick enough to block the player ──
	var count := room_polygon.size()
	for i in count:
		var a := room_polygon[i]
		var b := room_polygon[(i + 1) % count]
		_create_wall_collision(a, b, i)

	add_child(_collision_body)


func _create_wall_collision(a: Vector2, b: Vector2, index: int) -> void:
	var shape := CollisionShape3D.new()
	shape.name = "Wall_%d" % index

	var midpoint := (a + b) * 0.5
	var length := a.distance_to(b)
	var angle := atan2(b.x - a.x, b.y - a.y)

	# Edge direction and outward normal
	var edge_dir := (b - a).normalized()
	var normal := Vector2(edge_dir.y, -edge_dir.x)

	# Thick walls — 1.0m thick, positioned ON the edge (half inside, half outside)
	var thickness := 1.0
	var box := BoxShape3D.new()
	box.size = Vector3(length + 0.2, wall_height, thickness)  # Slight overlap at corners

	shape.position = Vector3(
		midpoint.x + normal.x * thickness * 0.5,
		floor_y + wall_height * 0.5 - 0.5,  # Start slightly below floor
		midpoint.y + normal.y * thickness * 0.5
	)
	shape.rotation.y = -angle

	shape.shape = box
	_collision_body.add_child(shape)


# ═══════════════════════════════════════════════════════════════════════════════
# NAVIGATION GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

func _build_navigation() -> void:
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "GeneratedNavigation"

	var nav_mesh := NavigationMesh.new()

	# Shrink the polygon slightly for agent radius
	var shrunk := _shrink_polygon(room_polygon, nav_agent_radius)

	# Convert to 3D vertices for navigation mesh
	var nav_vertices := PackedVector3Array()
	for p in shrunk:
		nav_vertices.append(Vector3(p.x, floor_y, p.y))

	nav_mesh.vertices = nav_vertices

	# Create a single polygon face from all vertices
	var polygon_indices := PackedInt32Array()
	# Triangulate and add as polygons
	var tri_indices := Geometry2D.triangulate_polygon(shrunk)
	# NavigationMesh uses polygon faces (not triangles), so we add each triangle
	for i in range(0, tri_indices.size(), 3):
		nav_mesh.add_polygon(PackedInt32Array([tri_indices[i], tri_indices[i+1], tri_indices[i+2]]))

	# Navigation mesh parameters
	nav_mesh.agent_radius = nav_agent_radius
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.15
	nav_mesh.cell_height = 0.2

	_nav_region.navigation_mesh = nav_mesh
	add_child(_nav_region)


func _shrink_polygon(polygon: PackedVector2Array, amount: float) -> PackedVector2Array:
	## Shrink a polygon inward by [amount] (for navigation margin).
	var result := PackedVector2Array()
	var count := polygon.size()

	if count < 3:
		return polygon

	# Calculate the centroid
	var centroid := Vector2.ZERO
	for p in polygon:
		centroid += p
	centroid /= float(count)

	# Move each point toward the centroid by amount
	# (Simple approach — for complex polygons, use Clipper library)
	for i in count:
		var p := polygon[i]
		var dir_to_center := (centroid - p).normalized()
		result.append(p + dir_to_center * amount)

	return result


# ═══════════════════════════════════════════════════════════════════════════════
# EDGE MARKERS (for rock placement guidance)
# ═══════════════════════════════════════════════════════════════════════════════

func _build_edge_markers() -> void:
	_edge_markers_container = Node3D.new()
	_edge_markers_container.name = "EdgeMarkers"

	var points := get_edge_points(edge_marker_spacing)
	for i in points.size():
		var marker := Marker3D.new()
		marker.name = "Edge_%d" % i
		marker.position = points[i]["position"] - global_position
		# Orient marker to face outward (toward wall)
		var normal: Vector3 = points[i]["normal"]
		marker.rotation.y = atan2(normal.x, normal.z)
		_edge_markers_container.add_child(marker)

	add_child(_edge_markers_container)


# ═══════════════════════════════════════════════════════════════════════════════
# EDITOR SUPPORT
# ═══════════════════════════════════════════════════════════════════════════════

func _set_polygon(value: PackedVector2Array) -> void:
	room_polygon = value
	if Engine.is_editor_hint():
		_update_editor_preview()


func _trigger_rebuild(value: bool) -> void:
	if value:
		build_room()
		rebuild_now = false


func _update_editor_preview() -> void:
	## Shows a wireframe outline of the polygon in the editor.
	if not Engine.is_editor_hint():
		return
	if room_polygon.size() < 3:
		return

	# Remove old preview
	if _debug_draw and is_instance_valid(_debug_draw):
		_debug_draw.queue_free()

	_debug_draw = MeshInstance3D.new()
	_debug_draw.name = "_EditorPreview"

	var im := ImmediateMesh.new()
	_debug_draw.mesh = im

	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in room_polygon:
		im.surface_add_vertex(Vector3(p.x, floor_y + 0.05, p.y))
	# Close the loop
	im.surface_add_vertex(Vector3(room_polygon[0].x, floor_y + 0.05, room_polygon[0].y))
	im.surface_end()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.3, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_debug_draw.material_override = mat

	add_child(_debug_draw)


# ═══════════════════════════════════════════════════════════════════════════════
# CLEANUP
# ═══════════════════════════════════════════════════════════════════════════════

func _clear_generated() -> void:
	for name in ["GeneratedFloor", "GeneratedCollision", "GeneratedNavigation", "EdgeMarkers"]:
		var node := get_node_or_null(name)
		if node:
			node.queue_free()
	_floor_mesh = null
	_collision_body = null
	_nav_region = null
	_edge_markers_container = null

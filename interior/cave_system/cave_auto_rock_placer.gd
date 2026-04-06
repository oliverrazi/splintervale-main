## CaveAutoRockPlacer — Automatically places 3D rocks along cave room edges.
##
## Reads edge data from CaveRoomBuilder and CaveCorridorBuilder nodes
## and populates the CaveRockGeometry with rocks along all walls.
##
## This bridges the gap between "I defined a room shape" and
## "the room has actual 3D rock walls".
##
## Workflow:
##   1. You define room shapes with CaveRoomBuilder / CaveCorridorBuilder
##   2. Add this script alongside CaveRockGeometry
##   3. On ready, it reads all edges and places rocks automatically
##   4. Tweak density, height, overhang settings to taste

class_name CaveAutoRockPlacer
extends Node3D

# ── Configuration ─────────────────────────────────────────────────────────────

@export_group("Rock Placement")
## Reference to the CaveRockGeometry that holds our rock meshes/shader.
@export var rock_geometry: CaveRockGeometry = null
## How many rocks per meter of wall edge.
@export_range(0.5, 8.0) var rocks_per_meter: float = 3.0
## How deep/thick the rock wall is (perpendicular to edge).
@export var wall_depth: float = 2.5
## Height range of wall rocks. X = min Y, Y = max Y.
@export var wall_height_range: Vector2 = Vector2(-0.3, 3.0)
## Scale range for individual rocks.
@export var rock_scale_range: Vector2 = Vector2(0.6, 1.8)

@export_group("Overhangs")
## Place overhanging rocks that lean inward (dramatic depth effect).
@export var enable_overhangs: bool = true
## How often an overhang appears (0 = never, 1 = every edge).
@export_range(0.0, 1.0) var overhang_frequency: float = 0.3
## How far overhangs lean inward.
@export var overhang_lean: float = 1.5
## Height of overhangs.
@export var overhang_height: float = 3.0

@export_group("Ceiling Rocks")
## Place ceiling rocks/stalactites above the room.
@export var enable_ceiling_rocks: bool = true
## How many ceiling rock clusters per room.
@export var ceiling_clusters: int = 3
## Height at which ceiling rocks hang.
@export var ceiling_height: float = 4.5
## Spread of each cluster.
@export var ceiling_spread: float = 2.5

@export_group("Rock Strata")
## Add horizontal layered rock strata on walls.
@export var enable_strata: bool = true
## Frequency: 0 = never, 1 = every long wall gets strata.
@export_range(0.0, 1.0) var strata_frequency: float = 0.4
## Minimum wall length for strata to appear.
@export var strata_min_wall_length: float = 3.0

@export_group("Building")
@export var build_on_ready: bool = true
@export var random_seed: int = 12345

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if build_on_ready:
		# Wait one frame for room builders to finish
		await get_tree().process_frame
		place_all_rocks()


## Main entry point: find all room/corridor builders and place rocks.
func place_all_rocks() -> void:
	if not rock_geometry:
		rock_geometry = _find_rock_geometry()
	if not rock_geometry:
		push_error("CaveAutoRockPlacer: No CaveRockGeometry found. Assign one in the inspector.")
		return

	_rng.seed = random_seed

	# Find all room builders in the scene
	var room_builders: Array[CaveRoomBuilder] = []
	var corridor_builders: Array[CaveCorridorBuilder] = []
	_find_builders(get_parent(), room_builders, corridor_builders)

	# Place rocks for each room
	for room in room_builders:
		_place_rocks_for_room(room)

	# Place rocks for each corridor
	for corridor in corridor_builders:
		_place_rocks_for_corridor(corridor)

	# Place ceiling rocks in rooms
	if enable_ceiling_rocks:
		for room in room_builders:
			_place_ceiling_rocks_for_room(room)


func _place_rocks_for_room(room: CaveRoomBuilder) -> void:
	var edges := room.get_edges()

	for edge in edges:
		var start: Vector3 = edge["start"]
		var end: Vector3 = edge["end"]
		var normal: Vector3 = edge["normal"]
		var length: float = edge["length"]
		var midpoint: Vector3 = edge["midpoint"]

		# ── Base wall rocks ──
		var rock_count := int(length * rocks_per_meter)
		rock_count = max(rock_count, 2)

		for i in rock_count:
			var t := _rng.randf()
			var pos := start.lerp(end, t)
			# Push outward from the edge + random depth
			pos += normal * _rng.randf_range(0.2, wall_depth)
			pos.y = _rng.randf_range(wall_height_range.x, wall_height_range.y)

			var rot := atan2(normal.x, normal.z) + _rng.randf_range(-0.4, 0.4)
			rock_geometry.place_rock(pos, rot, -1, rock_scale_range)

		# ── Overhangs (occasional) ──
		if enable_overhangs and _rng.randf() < overhang_frequency and length > 2.0:
			# Lean inward (opposite of normal)
			var lean_dir := -normal
			var overhang_pos := midpoint + normal * 0.5
			rock_geometry.place_overhang(
				overhang_pos, lean_dir,
				_rng.randi_range(3, 6),
				overhang_height,
				overhang_lean
			)

		# ── Rock strata (on longer walls) ──
		if enable_strata and _rng.randf() < strata_frequency and length >= strata_min_wall_length:
			var strata_pos := midpoint + normal * 0.3
			rock_geometry.place_rock_strata(
				strata_pos, -normal,  # Face inward (toward the room)
				length * 0.6,
				_rng.randi_range(3, 5),
				_rng.randf_range(0.3, 0.5)
			)


func _place_rocks_for_corridor(corridor: CaveCorridorBuilder) -> void:
	var edges := corridor.get_edge_lines()
	var left_pts: Array = edges["left"]
	var right_pts: Array = edges["right"]

	# Place rocks along left wall
	_place_rocks_along_edge_line(left_pts, true)
	# Place rocks along right wall
	_place_rocks_along_edge_line(right_pts, false)


func _place_rocks_along_edge_line(points: Array, is_left: bool) -> void:
	for i in range(points.size() - 1):
		var start: Vector3 = points[i]
		var end: Vector3 = points[i + 1]
		var length := start.distance_to(end)
		var dir := (end - start).normalized()

		# Outward normal
		var normal: Vector3
		if is_left:
			normal = Vector3(-dir.z, 0, dir.x)  # Left side points left
		else:
			normal = Vector3(dir.z, 0, -dir.x)  # Right side points right

		var rock_count := int(length * rocks_per_meter * 0.7)  # Slightly less dense in corridors
		for j in max(rock_count, 1):
			var t := _rng.randf()
			var pos := start.lerp(end, t)
			pos += normal * _rng.randf_range(0.2, wall_depth * 0.8)
			pos.y = _rng.randf_range(wall_height_range.x, wall_height_range.y * 0.7)

			var rot := atan2(normal.x, normal.z) + _rng.randf_range(-0.3, 0.3)
			rock_geometry.place_rock(pos, rot, -1, Vector2(rock_scale_range.x, rock_scale_range.y * 0.8))


func _place_ceiling_rocks_for_room(room: CaveRoomBuilder) -> void:
	var center := room.get_center()
	var bounds := room.get_bounds()

	for i in ceiling_clusters:
		# Random position within the room bounds
		var pos := Vector3(
			_rng.randf_range(bounds.position.x + 1, bounds.end.x - 1),
			0,
			_rng.randf_range(bounds.position.z + 1, bounds.end.z - 1),
		)
		rock_geometry.place_ceiling_rocks(
			pos,
			_rng.randi_range(4, 8),
			ceiling_spread,
			ceiling_height
		)


# ── Utility ───────────────────────────────────────────────────────────────────

func _find_rock_geometry() -> CaveRockGeometry:
	# Search siblings
	if get_parent():
		for child in get_parent().get_children():
			if child is CaveRockGeometry:
				return child
	return null


func _find_builders(node: Node, rooms: Array[CaveRoomBuilder],
		corridors: Array[CaveCorridorBuilder]) -> void:
	if node is CaveRoomBuilder:
		rooms.append(node)
	if node is CaveCorridorBuilder:
		corridors.append(node)
	for child in node.get_children():
		_find_builders(child, rooms, corridors)

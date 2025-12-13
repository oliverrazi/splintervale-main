@tool
extends Node3D
class_name PlateauGenerator

class PlateauInfo:
	var center: Vector3
	var size: Vector2
	var height: float
	var corner_radius: float

var plateaus: Array[PlateauInfo] = []

@export_group("Plateaus Allgemein")
@export var plateau_count: int = 8
@export var min_size: Vector2 = Vector2(8.0, 8.0)
@export var max_size: Vector2 = Vector2(20.0, 20.0)
@export var min_height: float = 2.0
@export var max_height: float = 6.0

@export_group("Ecken")
@export var min_corner_radius: float = 2.0
@export var max_corner_radius: float = 6.0

@export_group("Detail")
@export var segment_size: float = 1.0

func generate(world_size: Vector2, ground_height: float, rng: RandomNumberGenerator, material: Material) -> void:
	# Alte Plateaus löschen
	for child: Node in get_children():
		child.queue_free()
		
	plateaus.clear()

	if plateau_count <= 0:
		return

	var container: Node3D = Node3D.new()
	container.name = "Plateaus"
	add_child(container)
	if Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root

	for i: int in range(plateau_count):
		var size: Vector2 = Vector2(
			rng.randf_range(min_size.x, max_size.x),
			rng.randf_range(min_size.y, max_size.y)
		)

		var half_x: float = size.x * 0.5
		var half_z: float = size.y * 0.5

		var center_x: float = rng.randf_range(-world_size.x * 0.5 + half_x, world_size.x * 0.5 - half_x)
		var center_z: float = rng.randf_range(-world_size.y * 0.5 + half_z, world_size.y * 0.5 - half_z)

		var height: float = rng.randf_range(min_height, max_height)
		var corner_radius: float = rng.randf_range(min_corner_radius, max_corner_radius)
		corner_radius = min(corner_radius, min(half_x, half_z) - 0.1)

		if corner_radius <= 0.0:
			corner_radius = min(half_x, half_z) * 0.5

		_create_plateau(
			container,
			Vector3(center_x, ground_height, center_z),
			size,
			height,
			corner_radius,
			material
		)
		
		# Plateau-Daten für spätere Höhenabfragen speichern
		var info := PlateauInfo.new()
		info.center = Vector3(center_x, ground_height, center_z)
		info.size = size
		info.height = height
		info.corner_radius = corner_radius
		plateaus.append(info)

func get_height_at(x: float, z: float, base_height: float) -> float:
	var result: float = base_height
	for info: PlateauInfo in plateaus:
		var h: float = _get_plateau_height_at(info, x, z, base_height)
		if h > result:
			result = h
	return result


func _get_plateau_height_at(info: PlateauInfo, x: float, z: float, base_height: float) -> float:
	var lx: float = x - info.center.x
	var lz: float = z - info.center.z

	var hx: float = info.size.x * 0.5
	var hz: float = info.size.y * 0.5
	var r: float = info.corner_radius

	# Kein Radius → einfaches Rechteck
	if r <= 0.0:
		if abs(lx) <= hx and abs(lz) <= hz:
			return base_height + info.height
		return base_height

	# Rounded-Rectangle-SDF (wie deine Mesh-Form)
	var px: float = abs(lx)
	var pz: float = abs(lz)

	var inner_x: float = hx - r
	var inner_z: float = hz - r
	if inner_x < 0.0:
		inner_x = 0.0
	if inner_z < 0.0:
		inner_z = 0.0

	var dx: float = max(px - inner_x, 0.0)
	var dz: float = max(pz - inner_z, 0.0)
	var dist: float = sqrt(dx * dx + dz * dz)

	# inside -> Plateau-Oberseite
	if dist <= r:
		return base_height + info.height

	return base_height

func _create_plateau(
	parent: Node3D,
	center: Vector3,
	size: Vector2,
	height: float,
	corner_radius: float,
	material: Material
) -> void:
	var mesh: ArrayMesh = _build_plateau_mesh(size, height, corner_radius)

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Plateau"
	mi.mesh = mesh
	mi.position = center

	mi.set_surface_override_material(0, material)

	parent.add_child(mi)
	if Engine.is_editor_hint():
		mi.owner = get_tree().edited_scene_root

	# --- Kollision aus Mesh-Geometrie ---
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Collision"

	var shape: CollisionShape3D = CollisionShape3D.new()
	var concave: ConcavePolygonShape3D = ConcavePolygonShape3D.new()

	var arrays: Array = mesh.surface_get_arrays(0)

	var vertices_arr: PackedVector3Array = PackedVector3Array()
	if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
		vertices_arr = arrays[Mesh.ARRAY_VERTEX]

	var indices: PackedInt32Array = PackedInt32Array()
	if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = arrays[Mesh.ARRAY_INDEX]

	var tri_data: PackedVector3Array = PackedVector3Array()

	if indices.size() > 0:
		for idx: int in indices:
			if idx >= 0 and idx < vertices_arr.size():
				tri_data.append(vertices_arr[idx])
	else:
		tri_data = vertices_arr

	concave.data = tri_data
	shape.shape = concave

	body.add_child(shape)
	mi.add_child(body)

	if Engine.is_editor_hint():
		body.owner = get_tree().edited_scene_root
		shape.owner = get_tree().edited_scene_root

func _add_edge(perimeter: PackedVector3Array, from: Vector3, to: Vector3, segment_len: float) -> void:
	var dx: float = to.x - from.x
	var dz: float = to.z - from.z
	var length: float = sqrt(dx*dx + dz*dz)
	var segs: int = max(1, int(round(length / segment_len)))

	for i: int in range(segs + 1):
		var t: float = float(i) / float(segs)
		var x: float = lerp(from.x, to.x, t)
		var z: float = lerp(from.z, to.z, t)
		perimeter.append(Vector3(x, from.y, z))


func _add_arc(perimeter: PackedVector3Array, center: Vector3, radius: float, start_angle: float, end_angle: float, segment_len: float) -> void:
	var arc_len: float = abs(end_angle - start_angle) * radius
	var segs: int = max(3, int(round(arc_len / segment_len)))

	for i: int in range(segs + 1):
		var t: float = float(i) / float(segs)
		var a: float = lerp(start_angle, end_angle, t)
		var x: float = center.x + cos(a) * radius
		var z: float = center.z + sin(a) * radius
		perimeter.append(Vector3(x, center.y, z))

func _build_plateau_mesh(size: Vector2, height: float, corner_radius: float) -> ArrayMesh:
	var hx: float = size.x * 0.5
	var hz: float = size.y * 0.5

	var r: float = min(corner_radius, min(hx, hz) - 0.001)
	if r < 0.0:
		r = 0.0

	var perimeter: PackedVector3Array = PackedVector3Array()
	var segment_len: float = max(segment_size, 0.25)

	var ex: float = hx - r
	var ez: float = hz - r
	if ex < 0.0:
		ex = 0.0
	if ez < 0.0:
		ez = 0.0

	# Höhe der Außenpunkte ist unten (0.0)
	var y0: float = 0.0

	# Ohne Radius → einfaches Rechteck
	if r <= 0.001:
		_add_edge(perimeter, Vector3( hx, y0,  hz), Vector3(-hx, y0,  hz), segment_len)
		_add_edge(perimeter, Vector3(-hx, y0,  hz), Vector3(-hx, y0, -hz), segment_len)
		_add_edge(perimeter, Vector3(-hx, y0, -hz), Vector3( hx, y0, -hz), segment_len)
		_add_edge(perimeter, Vector3( hx, y0, -hz), Vector3( hx, y0,  hz), segment_len)
	else:
		# Vorderseite (oben)
		_add_edge(perimeter, Vector3(ex, y0, hz), Vector3(-ex, y0, hz), segment_len)

		# Front-Links Bogen
		_add_arc(perimeter, Vector3(-hx + r, y0, hz - r), r, PI * 0.5, PI, segment_len)

		# Linke Kante
		_add_edge(perimeter, Vector3(-hx, y0, hz - r), Vector3(-hx, y0, -hz + r), segment_len)

		# Hinten-Links Bogen
		_add_arc(perimeter, Vector3(-hx + r, y0, -hz + r), r, PI, PI * 1.5, segment_len)

		# Hinterseite
		_add_edge(perimeter, Vector3(-ex, y0, -hz), Vector3(ex, y0, -hz), segment_len)

		# Hinten-Rechts Bogen
		_add_arc(perimeter, Vector3(hx - r, y0, -hz + r), r, PI * 1.5, PI * 2.0, segment_len)

		# Rechte Kante
		_add_edge(perimeter, Vector3(hx, y0, -hz + r), Vector3(hx, y0, hz - r), segment_len)

		# Front-Rechts Bogen
		_add_arc(perimeter, Vector3(hx - r, y0, hz - r), r, 0.0, PI * 0.5, segment_len)


	# ----- Mesh-Aufbau -----
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var n: int = perimeter.size()
	if n < 3:
		return ArrayMesh.new()

	# ---- TOP ----
	var center_top: Vector3 = Vector3(0.0, height, 0.0)
	var up: Vector3 = Vector3.UP

	for i: int in range(n):
		var j: int = (i + 1) % n
		var v0: Vector3 = Vector3(perimeter[i].x, height, perimeter[i].z)
		var v1: Vector3 = Vector3(perimeter[j].x, height, perimeter[j].z)

		st.set_normal(up)
		st.add_vertex(center_top)
		st.add_vertex(v0)
		st.add_vertex(v1)

	# ---- WÄNDE ----
	for i: int in range(n):
		var j: int = (i + 1) % n

		var b0: Vector3 = Vector3(perimeter[i].x, 0.0, perimeter[i].z)
		var b1: Vector3 = Vector3(perimeter[j].x, 0.0, perimeter[j].z)
		var t0: Vector3 = Vector3(perimeter[i].x, height, perimeter[i].z)
		var t1: Vector3 = Vector3(perimeter[j].x, height, perimeter[j].z)

		var edge: Vector3 = b1 - b0
		var side_normal: Vector3 = Vector3.UP.cross(edge).normalized()

		# Quad → zwei Triangles
		st.set_normal(side_normal)
		st.add_vertex(b0)
		st.add_vertex(b1)
		st.add_vertex(t1)

		st.set_normal(side_normal)
		st.add_vertex(b0)
		st.add_vertex(t1)
		st.add_vertex(t0)

	var mesh: ArrayMesh = st.commit()
	return mesh

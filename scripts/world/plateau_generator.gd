class_name PlateauGenerator
extends RefCounted

## Generiert und verwaltet Plateaus

var world_generator: WorldGenerator
var rng: RandomNumberGenerator
var plateaus: Array[Dictionary] = []
var elevation_cache := {} 



func _init(world_gen: WorldGenerator):
	world_generator = world_gen
	rng = world_gen.rng

func generate_all_plateaus():
	print("Generiere %d Plateaus..." % world_generator.num_plateaus)
	
	plateaus.clear()
	elevation_cache.clear()  # Cache leeren
	
	for i in range(world_generator.num_plateaus):
		var plateau_data = create_random_plateau_data()
		
		if plateau_data.is_empty() or not plateau_data.has("position"):
			continue
		
		if not can_place_plateau(plateau_data):
			continue
		
		plateaus.append(plateau_data)
		create_and_add_mesh(plateau_data)
		
		print("  Plateau %d erstellt" % (i + 1))
	
	# NEU: Vorberechnung für bessere Performance
	print("  Berechne Elevation-Cache...")

func get_chunk_elevation(world_pos: Vector2) -> float:
	for plateau in plateaus:
		var plateau_center_2d := Vector2(plateau.position.x, plateau.position.z)

		# 1. Grober Radius (schneller Early-Out)
		if world_pos.distance_to(plateau_center_2d) > plateau.radius * 1.05:
			continue

		# 2. Exakte Form-Prüfung
		var outline := ShapeGenerator.generate_shape_outline(plateau, 64)
		if is_point_in_plateau(world_pos, plateau.position, outline):
			return plateau.position.y + plateau.height

	return 0.0   # Grundebene
	
func clear():
	plateaus.clear()
	elevation_cache.clear()
	print("PlateauGenerator cleared")
	
# Gibt alle Böden zurück: [ { y : float, radius : float }, ... ]
func get_ground_levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = []          # leeres Typed-Array
	levels.append({ y = 0.0, radius = INF })   # Grundebene

	for p in plateaus:
		levels.append({
			y      = p.position.y + p.height,
			radius = p.radius
		})
	return levels

func can_place_plateau(new_plateau: Dictionary) -> bool:
	# Prüfe gegen ALLE existierenden Plateaus
	for existing in plateaus:
		var dist_2d = Vector2(
			new_plateau.position.x - existing.position.x,
			new_plateau.position.z - existing.position.z
		).length()
		
		var combined_radius = new_plateau.radius + existing.radius
		
		# Überschneiden sich die Plateaus horizontal?
		if dist_2d < combined_radius:
			# Sie überschneiden sich!
			
			# Berechne welches tiefer liegt (BEVOR wir die Höhe ändern!)
			var new_base_y = new_plateau.position.y
			var existing_top_y = existing.position.y + existing.height
			var existing_base_y = existing.position.y
			
			# Ist das neue Plateau vollständig im existierenden enthalten?
			var dist_from_existing_center = Vector2(
				new_plateau.position.x - existing.position.x,
				new_plateau.position.z - existing.position.z
			).length()
			
			var new_fully_in_existing = (dist_from_existing_center + new_plateau.radius) <= existing.radius
			var existing_fully_in_new = (dist_from_existing_center + existing.radius) <= new_plateau.radius
			
			# FALL 1: Neues Plateau ist vollständig im existierenden
			if new_fully_in_existing:
				# Stapele das neue OBEN auf das existierende
				new_plateau.position.y = existing_top_y
				print("    → Stapele neues Plateau auf existierendes (Y=%.1f)" % new_plateau.position.y)
				continue  # Prüfe weiter gegen andere Plateaus
			
			# FALL 2: Existierendes ist vollständig im neuen (und neues ist am Boden)
			elif existing_fully_in_new and new_base_y <= existing_base_y:
				# Das neue bildet die Basis - existierendes ist bereits oben drauf, OK
				print("    → Neues Plateau bildet Basis für existierendes")
				continue
			
			# FALL 3: Teilweise Überlappung - NICHT erlaubt!
			else:
				print("    → Ungültige Überlappung (nicht vollständig gestapelt)")
				return false
	
	return true

func create_random_plateau_data() -> Dictionary:
	var data = {}
	
	if rng == null:
		return {}
	
	var x = rng.randf_range(-world_generator.world_size.x / 2, world_generator.world_size.x / 2)
	var z = rng.randf_range(-world_generator.world_size.y / 2, world_generator.world_size.y / 2)
	data.position = Vector3(x, 0, z)  # STARTET IMMER BEI Y=0
	
	data.radius = rng.randf_range(world_generator.min_plateau_radius, world_generator.max_plateau_radius)
	data.height = rng.randf_range(world_generator.min_plateau_height, world_generator.max_plateau_height)
	
	var use_polygon = rng.randf() < 0.6
	
	if use_polygon:
		data.shape_type = 1
		data.num_sides = rng.randi_range(4, 8)
		data.corner_roundness = rng.randf_range(0.6, 0.9)
	else:
		data.shape_type = 0
		data.num_sides = 32
		data.corner_roundness = rng.randf_range(0.6, 0.9)
	
	data.irregularity = rng.randf_range(0.0, world_generator.shape_variation * 0.5)
	data.stretch_x = rng.randf_range(0.7, 1.3)
	data.stretch_y = rng.randf_range(0.7, 1.3)
	data.rotation = rng.randf() * TAU
	data.grass_overhang_variation = rng.randf_range(0.8, 1.2)
	
	return data

func create_and_add_mesh(data: Dictionary):
	var mesh_instance = create_plateau_mesh(data)
	world_generator.add_child(mesh_instance)
	
	if Engine.is_editor_hint():
		var scene_root = world_generator.get_tree().edited_scene_root
		if scene_root:
			mesh_instance.owner = scene_root

func create_plateau_mesh(data: Dictionary) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.position = data.position
	mesh_instance.name = "Plateau"
	
	var array_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	
	var radius = data.radius
	var height = data.height
	var segments = 128  # Erhöht für glattere Formen
	
	var outline_points = ShapeGenerator.generate_shape_outline(data, segments)
	
	var overhang_var = data.get("grass_overhang_variation", 1.0)
	var actual_grass_overhang = world_generator.grass_overhang if world_generator.grass_overhang != null else 0.05
	var material_data = {
		"grass_overhang": actual_grass_overhang * overhang_var,
		"height": height
	}
	
	# TOP
	var center_top = Vector3(0, height, 0)
	vertices.append(center_top)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	
	for i in range(outline_points.size()):
		var point = outline_points[i]
		vertices.append(Vector3(point.x, height, point.y))
		normals.append(Vector3.UP)
		
		var uv_x = (point.x / radius) * 0.5 + 0.5
		var uv_y = (point.y / radius) * 0.5 + 0.5
		uvs.append(Vector2(uv_x, uv_y))
	
	for i in range(outline_points.size()):
		var next_i = (i + 1) % outline_points.size()
		indices.append(0)
		indices.append(i + 1)
		indices.append(next_i + 1)
	
	# WALLS
	var accumulated_distances = PackedFloat32Array()
	accumulated_distances.append(0.0)
	var total_perimeter = 0.0
	
	for i in range(outline_points.size()):
		var next_i = (i + 1) % outline_points.size()
		var dist = outline_points[i].distance_to(outline_points[next_i])
		total_perimeter += dist
		accumulated_distances.append(total_perimeter)
	
	var wall_top_start = vertices.size()
	for i in range(outline_points.size()):
		var point = outline_points[i]
		vertices.append(Vector3(point.x, height, point.y))
		var normal = Vector3(point.x, 0, point.y).normalized()
		normals.append(normal)
		var u = accumulated_distances[i] / total_perimeter
		uvs.append(Vector2(u, 1.0))
	
	var wall_bottom_start = vertices.size()
	for i in range(outline_points.size()):
		var point = outline_points[i]
		vertices.append(Vector3(point.x, 0, point.y))
		var normal = Vector3(point.x, 0, point.y).normalized()
		normals.append(normal)
		var u = accumulated_distances[i] / total_perimeter
		uvs.append(Vector2(u, 0.0))
	
	for i in range(outline_points.size()):
		var next_i = (i + 1) % outline_points.size()
		var top_current = wall_top_start + i
		var top_next = wall_top_start + next_i
		var bottom_current = wall_bottom_start + i
		var bottom_next = wall_bottom_start + next_i
		
		indices.append(top_current)
		indices.append(bottom_current)
		indices.append(top_next)
		
		indices.append(top_next)
		indices.append(bottom_current)
		indices.append(bottom_next)
	
	# BOTTOM
	var bottom_center_index = vertices.size()
	vertices.append(Vector3(0, 0, 0))
	normals.append(Vector3.DOWN)
	uvs.append(Vector2(0.5, 0.5))
	
	for i in range(outline_points.size()):
		var next_i = (i + 1) % outline_points.size()
		var bottom_current = wall_bottom_start + i
		var bottom_next = wall_bottom_start + next_i
		
		indices.append(bottom_center_index)
		indices.append(bottom_next)
		indices.append(bottom_current)
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = array_mesh
	
	var material = create_plateau_material(material_data)
	mesh_instance.set_surface_override_material(0, material)
	
	# COLLISION
	var static_body = StaticBody3D.new()
	static_body.name = "CollisionBody"
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape"
	var shape = array_mesh.create_trimesh_shape()
	collision_shape.shape = shape
	static_body.add_child(collision_shape)
	mesh_instance.add_child(static_body)
	
	if Engine.is_editor_hint():
		var scene_root = world_generator.get_tree().edited_scene_root
		if scene_root:
			static_body.owner = scene_root
			collision_shape.owner = scene_root
	
	return mesh_instance

func create_plateau_material(material_data: Dictionary) -> Material:
	var material = ShaderMaterial.new()
	var shader = load("res://scripts/shader/plateau_shader.gdshader")
	
	if shader:
		material.shader = shader
		if world_generator.grass_texture:
			material.set_shader_parameter("grass_texture", world_generator.grass_texture)
		if world_generator.earth_texture:
			material.set_shader_parameter("earth_texture", world_generator.earth_texture)
		material.set_shader_parameter("texture_scale", world_generator.texture_scale)
		material.set_shader_parameter("grass_overhang", material_data.grass_overhang)
		material.set_shader_parameter("plateau_height", material_data.height)
	else:
		var standard = StandardMaterial3D.new()
		standard.albedo_color = Color(0.3, 0.6, 0.3)
		return standard
	
	return material


# NEU: Prüft ob Position auf Plateau liegt und gibt Höhe zurück
func get_elevation_at_position(world_pos: Vector2) -> float:
	for plateau in plateaus:
		var plateau_center = Vector2(plateau.position.x, plateau.position.z)
		var dist = world_pos.distance_to(plateau_center)
		
		# Ist Punkt im Plateau-Radius?
		if dist <= plateau.radius:
			# Prüfe ob wirklich innerhalb der Form
			var outline_points = ShapeGenerator.generate_shape_outline(plateau, 64)
			if is_point_in_plateau(world_pos, plateau.position, outline_points):
				return plateau.position.y + plateau.height
	
	return 0.0  # Boden-Höhe

func is_point_in_plateau(point_2d: Vector2, plateau_center: Vector3, outline_points: PackedVector2Array) -> bool:
	var local_point = Vector2(
		point_2d.x - plateau_center.x,
		point_2d.y - plateau_center.z
	)
	
	var inside = false
	var j = outline_points.size() - 1
	
	for i in range(outline_points.size()):
		var vi = outline_points[i]
		var vj = outline_points[j]
		
		if ((vi.y > local_point.y) != (vj.y > local_point.y)) and \
		   (local_point.x < (vj.x - vi.x) * (local_point.y - vi.y) / (vj.y - vi.y) + vi.x):
			inside = !inside
		
		j = i
	
	return inside


## Liefert die exakte Y-Höhe am gegebenen Weltpunkt (Raycast oder Fallback)
func get_ground_height(world_pos: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = world_generator.get_world_3d().direct_space_state
	var from: Vector3 = Vector3(world_pos.x, 1000.0, world_pos.z)
	var to: Vector3   = Vector3(world_pos.x, -1000.0, world_pos.z)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1                                    # nur Static-Bodies
	var hit: Dictionary = space.intersect_ray(query)

	if not hit.is_empty():
		return hit.position.y                                   # getroffenes Mesh

	# Fallback (Editor, bevor Kollisions-Shapes da sind)
	return get_elevation_at_position(Vector2(world_pos.x, world_pos.z))
	
	## Gibt den exakten Plateau-Höhenwert nur zurück, wenn die 2D-Position *innerhalb* des Plateaus liegt
func get_plateau_elevation_if_inside(world_pos: Vector2) -> float:
	for plateau: Dictionary in plateaus:
		var plateau_center: Vector2 = Vector2(plateau.position.x, plateau.position.z)
		if world_pos.distance_to(plateau_center) > plateau.radius * 1.05:
			continue

		var outline: PackedVector2Array = ShapeGenerator.generate_shape_outline(plateau, 64)
		if is_point_in_plateau(world_pos, plateau.position, outline):
			return plateau.position.y + plateau.height
	return NAN  # <- GlobalScope Konstante  # <- wichtig: kein Plateau

@tool
extends Node3D
class_name WorldGenerator

## Weltgenerierung mit Plateaus, Pfaden, Wasser, Bäumen und Gras

# Export-Variablen für einfache Anpassung
@export_group("World Settings")
@export var world_size: Vector2 = Vector2(100, 100)
@export var random_seed: int = 0
@export var generate_on_ready: bool = true
@export var regenerate_button: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			generate_world()
		regenerate_button = false

@export_group("Ground Plane")
@export var show_ground: bool = true
@export var ground_height: float = -0.5
@export var ground_texture_scale: float = 1.0  # Skalierung der Boden-Textur

@export_group("Plateau Settings")
@export var num_plateaus: int = 5
@export var min_plateau_radius: float = 8.0
@export var max_plateau_radius: float = 20.0
@export var min_plateau_height: float = 2.0
@export var max_plateau_height: float = 8.0
@export_range(0.0, 1.0) var shape_variation: float = 0.7  # 0 = nur rund, 1 = sehr vielfältig

@export_group("Textures")
@export var grass_texture: Texture2D
@export var earth_texture: Texture2D
@export var path_texture: Texture2D
@export var texture_scale: float = 1.0  # Größer = kleiner getilet
@export_range(0.0, 0.5) var grass_overhang: float = 0.05  # Gras-Überhang in Metern (absolut!)

@export_group("Path Settings")
@export var num_paths: int = 5
@export var min_path_length: float = 20.0
@export var max_path_length: float = 60.0
@export var path_width: float = 2.0
@export var path_curvature: float = 0.3  # 0 = gerade, 1 = sehr kurvig
@export var paths_can_climb_plateaus: bool = true  # Pfade können auf Plateaus gehen

# Interne Variablen
var rng: RandomNumberGenerator
var plateaus: Array[Dictionary] = []
var paths: Array[Dictionary] = []

func _init():
	# Stelle sicher dass alle Variablen initialisiert sind
	if grass_overhang == null:
		grass_overhang = 0.05
	if texture_scale == null:
		texture_scale = 1.0

func _ready():
	if random_seed == 0:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	else:
		rng = RandomNumberGenerator.new()
		rng.seed = random_seed
	
	# Generiere nur wenn gewünscht (oder nicht im Editor)
	if generate_on_ready or not Engine.is_editor_hint():
		generate_world()

func generate_world():
	print("=== Weltgenerierung gestartet ===")
	
	# Stelle sicher, dass RNG initialisiert ist
	if rng == null:
		if random_seed == 0:
			rng = RandomNumberGenerator.new()
			rng.randomize()
		else:
			rng = RandomNumberGenerator.new()
			rng.seed = random_seed
	
	clear_world()
	
	# Grundfläche generieren
	if show_ground:
		generate_ground_plane()
	
	# Schritt 1: Plateaus generieren
	generate_plateaus()
	
	# Schritt 2: Pfade generieren
	if num_paths > 0:
		generate_paths()
	
	print("=== Weltgenerierung abgeschlossen ===")

func clear_world():
	# Lösche alle Kinder
	for child in get_children():
		if Engine.is_editor_hint():
			child.queue_free()
		else:
			child.queue_free()
	
	plateaus.clear()
	paths.clear()

func generate_ground_plane():
	print("Generiere Grundfläche...")
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "GroundPlane"
	mesh_instance.position = Vector3(0, ground_height, 0)
	
	# Erstelle Plane Mesh
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(world_size.x * 1.2, world_size.y * 1.2)
	mesh_instance.mesh = plane_mesh
	
	# Material mit Gras-Textur
	var material = StandardMaterial3D.new()
	if grass_texture:
		material.albedo_texture = grass_texture
		material.uv1_scale = Vector3(world_size.x * 0.05 * ground_texture_scale, world_size.y * 0.05 * ground_texture_scale, 1.0)
	else:
		material.albedo_color = Color(0.3, 0.6, 0.3)
	
	mesh_instance.set_surface_override_material(0, material)
	add_child(mesh_instance)
	
	# === VEREINFACHTE KOLLISION ===
	# Erstelle 4 große Boxen an den Rändern statt Grid
	# Das ist performant und vermeidet Einfrieren
	var static_body = StaticBody3D.new()
	static_body.name = "GroundCollision"
	mesh_instance.add_child(static_body)
	
	# TEMPORÄR: Eine große Box für ganzen Boden
	# Spieler können unter Plateaus durchgehen ist OK für jetzt
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(world_size.x * 1.2, 0.1, world_size.y * 1.2)
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0, -0.05, 0)
	static_body.add_child(collision_shape)
	
	if Engine.is_editor_hint():
		var scene_root = get_tree().edited_scene_root
		if scene_root:
			collision_shape.owner = scene_root
			mesh_instance.owner = scene_root
			static_body.owner = scene_root
	
	print("  Boden-Kollision generiert (einfache Box)")


func generate_plateaus():
	print("Generiere %d Plateaus..." % num_plateaus)
	
	for i in range(num_plateaus):
		var plateau_data = create_random_plateau_data()
		
		# Prüfe ob Daten gültig sind
		if plateau_data.is_empty() or not plateau_data.has("position"):
			print("  Fehler: Ungültige Plateau-Daten bei Index %d" % i)
			continue
		
		# Prüfe Überschneidung mit existierenden Plateaus
		if not can_place_plateau(plateau_data):
			print("  Plateau %d überlappt ungültig - übersprungen" % (i + 1))
			continue
		
		plateaus.append(plateau_data)
		
		var plateau_mesh = create_plateau_mesh(plateau_data)
		if plateau_mesh:
			add_child(plateau_mesh)
			
			print("  Plateau %d: Position (%.1f, %.1f), Radius %.1f, Höhe %.1f" % [
				i + 1,
				plateau_data.position.x,
				plateau_data.position.z,
				plateau_data.radius,
				plateau_data.height
			])

func can_place_plateau(new_plateau: Dictionary) -> bool:
	# Prüfe gegen alle existierenden Plateaus
	for existing in plateaus:
		# Berechne 2D-Distanz zwischen Zentren (nur X und Z)
		var dist_2d = Vector2(
			new_plateau.position.x - existing.position.x,
			new_plateau.position.z - existing.position.z
		).length()
		
		# Summe der Radien
		var combined_radius = new_plateau.radius + existing.radius
		
		# Überschneiden sie sich?
		if dist_2d < combined_radius:
			# Sie überschneiden sich!
			# Regel: Unteres muss oberes KOMPLETT abdecken
			
			var new_is_lower = new_plateau.position.y < existing.position.y
			var lower_plateau = new_plateau if new_is_lower else existing
			var upper_plateau = existing if new_is_lower else new_plateau
			
			# Prüfe ob das untere das obere KOMPLETT abdeckt
			# Das obere muss KOMPLETT innerhalb des unteren liegen
			var dist_from_lower_center = Vector2(
				upper_plateau.position.x - lower_plateau.position.x,
				upper_plateau.position.z - lower_plateau.position.z
			).length()
			
			# Oberes ist komplett im unteren wenn:
			# Distanz + Radius_oben <= Radius_unten
			var is_fully_contained = (dist_from_lower_center + upper_plateau.radius) <= lower_plateau.radius
			
			if not is_fully_contained:
				# Nicht komplett abgedeckt = nicht erlaubt!
				return false
			else:
				# Komplett abgedeckt! Stapele das neue oben drauf
				if new_is_lower:
					# Neues ist unten - existing bleibt wo es ist
					pass
				else:
					# Neues ist oben - setze es auf das untere Plateau
					new_plateau.position.y = existing.position.y + existing.height
					print("  → Plateau wird gestapelt auf Y=%.1f" % new_plateau.position.y)
	
	return true

func create_random_plateau_data() -> Dictionary:
	var data = {}
	
	# Stelle sicher dass RNG existiert
	if rng == null:
		push_error("RNG ist nicht initialisiert!")
		return {}
	
	# Zufällige Position innerhalb der Weltgrenzen
	var x = rng.randf_range(-world_size.x / 2, world_size.x / 2)
	var z = rng.randf_range(-world_size.y / 2, world_size.y / 2)
	data.position = Vector3(x, 0, z)
	
	# Zufällige Größe
	data.radius = rng.randf_range(min_plateau_radius, max_plateau_radius)
	data.height = rng.randf_range(min_plateau_height, max_plateau_height)
	
	# Form-Parameter - NUR einfache Formen!
	# 60% Polygone (4-8 Ecken), 40% Kreise
	var use_polygon = rng.randf() < 0.6
	
	if use_polygon:
		data.shape_type = 1  # Polygon
		data.num_sides = rng.randi_range(4, 8)  # Viereck bis Achteck
		data.corner_roundness = rng.randf_range(0.4, 0.8)  # MEHR Variation! 0 = spitz, 1 = rund
	else:
		data.shape_type = 0  # Kreis
		data.num_sides = 32  # Viele Seiten = perfekter Kreis
		data.corner_roundness = rng.randf_range(0.4, 0.8)  # MEHR Variation! 0 = spitz, 1 = rund
	
	# MEHR Variation für sichtbare Unterschiede!
	data.irregularity = rng.randf_range(0.0, shape_variation * 0.8)
	data.stretch_x = rng.randf_range(0.6, 1.4)  # DEUTLICH mehr Streckung!
	data.stretch_y = rng.randf_range(0.6, 1.4)
	data.rotation = rng.randf() * TAU  # Zufällige Rotation
	data.grass_overhang_variation = rng.randf_range(0.8, 1.2)
	
	return data

func create_plateau_mesh(data: Dictionary) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.position = data.position
	
	# Erstelle das Mesh
	var array_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	
	# Parameter
	var radius = data.radius
	var height = data.height
	var segments = 64  # ERHÖHT von 32 auf 64 für weichere Formen!
	
	# Generiere Umriss-Punkte basierend auf Form
	var outline_points = generate_shape_outline(data, segments)
	
	# Speichere Daten für Material-Zugriff
	var overhang_var = data.get("grass_overhang_variation", 1.0)  # Default: 1.0 wenn nicht vorhanden
	var actual_grass_overhang = grass_overhang if grass_overhang != null else 0.05  # Default: 5cm
	var material_data = {
		"grass_overhang": actual_grass_overhang * overhang_var,
		"height": height
	}
	
	# === TOP-FLÄCHE (Gras) ===
	var center_top = Vector3(0, height, 0)
	vertices.append(center_top)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	
	for i in range(outline_points.size()):
		var point = outline_points[i]
		vertices.append(Vector3(point.x, height, point.y))
		normals.append(Vector3.UP)
		
		# UV basierend auf Position
		var uv_x = (point.x / radius) * 0.5 + 0.5
		var uv_y = (point.y / radius) * 0.5 + 0.5
		uvs.append(Vector2(uv_x, uv_y))
	
	# Indices für Top-Fläche (Fächer)
	for i in range(outline_points.size()):
		var next_i = (i + 1) % outline_points.size()
		indices.append(0)
		indices.append(i + 1)
		indices.append(next_i + 1)
	
	# === VERTIKALE WÄNDE (Erde) ===
	# Wir brauchen separate Vertices für die Wände mit korrekten UVs!
	
	# Berechne zunächst die akkumulierte Distanz entlang des Umfangs
	var accumulated_distances = PackedFloat32Array()
	accumulated_distances.append(0.0)
	var total_perimeter = 0.0
	
	for i in range(outline_points.size()):
		var next_i = (i + 1) % outline_points.size()
		var dist = outline_points[i].distance_to(outline_points[next_i])
		total_perimeter += dist
		accumulated_distances.append(total_perimeter)
	
	# Erstelle Top-Ring für Wände (separate von Top-Fläche!)
	var wall_top_start = vertices.size()
	for i in range(outline_points.size()):
		var point = outline_points[i]
		vertices.append(Vector3(point.x, height, point.y))
		
		# Normale zeigt nach außen
		var normal = Vector3(point.x, 0, point.y).normalized()
		normals.append(normal)
		
		# UV: U = normalisierte Position entlang Umfang, V = oben (1.0)
		var u = accumulated_distances[i] / total_perimeter
		uvs.append(Vector2(u, 1.0))
	
	# Erstelle Bottom-Ring für Wände
	var wall_bottom_start = vertices.size()
	for i in range(outline_points.size()):
		var point = outline_points[i]
		vertices.append(Vector3(point.x, 0, point.y))
		
		# Normale zeigt nach außen
		var normal = Vector3(point.x, 0, point.y).normalized()
		normals.append(normal)
		
		# UV: U = normalisierte Position entlang Umfang, V = unten (0.0)
		var u = accumulated_distances[i] / total_perimeter
		uvs.append(Vector2(u, 0.0))
	
	# Indices für Wände
	for i in range(outline_points.size()):
		var next_i = (i + 1) % outline_points.size()
		
		var top_current = wall_top_start + i
		var top_next = wall_top_start + next_i
		var bottom_current = wall_bottom_start + i
		var bottom_next = wall_bottom_start + next_i
		
		# Zwei Dreiecke pro Wand-Segment
		indices.append(top_current)
		indices.append(bottom_current)
		indices.append(top_next)
		
		indices.append(top_next)
		indices.append(bottom_current)
		indices.append(bottom_next)
	
	# === BODEN (optional, für geschlossenes Mesh) ===
	# Center unten
	var bottom_center_index = vertices.size()
	vertices.append(Vector3(0, 0, 0))
	normals.append(Vector3.DOWN)
	uvs.append(Vector2(0.5, 0.5))
	
	# Boden-Fächer - nutze die Bottom-Ring Vertices
	for i in range(outline_points.size()):
		var next_i = (i + 1) % outline_points.size()
		var bottom_current = wall_bottom_start + i
		var bottom_next = wall_bottom_start + next_i
		
		# Reihenfolge umgedreht für nach unten zeigende Fläche
		indices.append(bottom_center_index)
		indices.append(bottom_next)
		indices.append(bottom_current)
	
	# Setze Arrays
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	# Erstelle Mesh
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = array_mesh
	
	# Material mit Shader erstellen
	var material = create_plateau_material(material_data)
	mesh_instance.set_surface_override_material(0, material)
	
	# === KOLLISION hinzufügen ===
	# Erstelle StaticBody3D für Kollision
	var static_body = StaticBody3D.new()
	static_body.name = "CollisionBody"
	
	# Erstelle CollisionShape3D
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape"
	
	# WICHTIG: ConcavePolygonShape für EXAKTE Form!
	# ConvexShape vereinfacht zu sehr (macht alles rund)
	var shape = array_mesh.create_trimesh_shape()
	collision_shape.shape = shape
	
	# Füge CollisionShape zum StaticBody hinzu
	static_body.add_child(collision_shape)
	
	# Füge StaticBody zum MeshInstance hinzu
	mesh_instance.add_child(static_body)
	
	if Engine.is_editor_hint():
		var scene_root = get_tree().edited_scene_root
		if scene_root:
			mesh_instance.owner = scene_root
			static_body.owner = scene_root
			collision_shape.owner = scene_root
	
	return mesh_instance

func generate_shape_outline(data: Dictionary, segments: int) -> PackedVector2Array:
	var points = PackedVector2Array()
	var radius = data.radius
	var shape_type = data.shape_type
	var irregularity = data.irregularity
	var num_sides = data.num_sides
	var corner_roundness = data.corner_roundness
	var stretch_x = data.stretch_x
	var stretch_y = data.stretch_y
	var rotation = data.rotation
	
	if shape_type == 0:
		# === KREIS ===
		for i in range(segments):
			var angle = (float(i) / segments) * TAU
			var noise = sin(angle * 3.0) * 0.02 + sin(angle * 7.0) * 0.01
			var r = radius * (1.0 + noise * irregularity)
			
			var x = cos(angle) * r * stretch_x
			var y = sin(angle) * r * stretch_y
			var rx = x * cos(rotation) - y * sin(rotation)
			var ry = x * sin(rotation) + y * cos(rotation)
			
			points.append(Vector2(rx, ry))
	
	else:
		# === POLYGON - Komplett neue Methode! ===
		# 1. Erstelle die tatsächlichen Eckpunkte
		var corners = []
		for i in range(num_sides):
			var corner_angle = (float(i) / num_sides) * TAU
			var corner_x = cos(corner_angle) * radius
			var corner_y = sin(corner_angle) * radius
			corners.append(Vector2(corner_x, corner_y))
		
		# 2. Für jeden Punkt: Interpoliere zwischen den Ecken
		for i in range(segments):
			var angle = (float(i) / segments) * TAU
			
			# Finde die zwei nächsten Ecken
			var corner_index = int(floor((float(i) / segments) * num_sides))
			var next_corner_index = (corner_index + 1) % num_sides
			
			var corner_a = corners[corner_index]
			var corner_b = corners[next_corner_index]
			
			# Position zwischen den Ecken (0 = an corner_a, 1 = an corner_b)
			var t = fmod((float(i) / segments) * num_sides, 1.0)
			
			# Interpoliere GERADE zwischen Ecken (echte Polygonseiten!)
			var point = corner_a.lerp(corner_b, t)
			
			# Nur an Ecken: Mache sie etwas runder basierend auf corner_roundness
			if t < corner_roundness * 0.5 or t > (1.0 - corner_roundness * 0.5):
				# Nah an Ecke - ziehe leicht zum Zentrum für Rundung
				var pull_to_center = 1.0 - corner_roundness * 0.15
				point *= pull_to_center
			
			# Minimale Variation
			var noise = sin(angle * 5.0) * 0.01
			point *= (1.0 + noise * irregularity)
			
			# Anwenden von Streckung und Rotation
			var x = point.x * stretch_x
			var y = point.y * stretch_y
			var rx = x * cos(rotation) - y * sin(rotation)
			var ry = x * sin(rotation) + y * cos(rotation)
			
			points.append(Vector2(rx, ry))
	
	return points

func create_plateau_material(material_data: Dictionary) -> Material:
	var material = ShaderMaterial.new()
	
	# Lade den Shader
	var shader = load("res://scripts/shader/plateau_shader.gdshader")
	if shader:
		material.shader = shader
		
		# Setze Texturen
		if grass_texture:
			material.set_shader_parameter("grass_texture", grass_texture)
		if earth_texture:
			material.set_shader_parameter("earth_texture", earth_texture)
		
		material.set_shader_parameter("texture_scale", texture_scale)
		material.set_shader_parameter("grass_overhang", material_data.grass_overhang)
		material.set_shader_parameter("plateau_height", material_data.height)
	else:
		# Fallback zu Standard-Material
		var standard = StandardMaterial3D.new()
		standard.albedo_color = Color(0.3, 0.6, 0.3)
		return standard
	
	return material

func generate_paths():
	print("Generiere %d Pfade..." % num_paths)
	
	for i in range(num_paths):
		var path_data = create_random_path()
		
		if path_data.points.size() < 2:
			print("  Pfad %d: Zu wenige Punkte (%d), übersprungen" % [i + 1, path_data.points.size()])
			continue
		
		paths.append(path_data)
		
		var path_mesh = create_path_mesh(path_data)
		if path_mesh:
			add_child(path_mesh)
			
			# Owner NACH add_child setzen!
			if Engine.is_editor_hint():
				var scene_root = get_tree().edited_scene_root
				if scene_root:
					path_mesh.owner = scene_root
			
			print("  Pfad %d: Start (%.1f, %.1f, %.1f), Länge %.1fm, %d Segmente" % [
				i + 1,
				path_data.points[0].x,
				path_data.points[0].y,
				path_data.points[0].z,
				path_data.total_length,
				path_data.points.size()
			])
		else:
			print("  Pfad %d: Mesh-Erstellung fehlgeschlagen!" % (i + 1))

func create_random_path() -> Dictionary:
	var data = {}
	
	# Zufälliger Startpunkt
	var start_x = rng.randf_range(-world_size.x / 2, world_size.x / 2)
	var start_z = rng.randf_range(-world_size.y / 2, world_size.y / 2)
	
	# WICHTIG: Start auf ground_height, nicht auf 0!
	var start = Vector3(start_x, ground_height + 0.1, start_z)  # 10cm über Boden
	
	# Zufällige Richtung
	var direction = rng.randf() * TAU
	var target_length = rng.randf_range(min_path_length, max_path_length)
	
	# Generiere Pfadpunkte mit Kurven
	var points = []
	var current_pos = start
	var current_direction = direction
	var traveled_distance = 0.0
	
	points.append(current_pos)
	
	# Segment-Länge (größer = weniger Punkte = performanter)
	var segment_length = 5.0  # War 2.0, jetzt 5.0 für bessere Performance
	
	while traveled_distance < target_length:
		# Richtung variieren basierend auf curvature
		var direction_change = rng.randf_range(-path_curvature, path_curvature) * 0.5
		current_direction += direction_change
		
		# Nächster Punkt
		var next_pos = current_pos + Vector3(
			cos(current_direction) * segment_length,
			0,
			sin(current_direction) * segment_length
		)
		
		# WICHTIG: Pfade bleiben AUF BODENHÖHE, gehen NICHT auf Plateaus!
		next_pos.y = ground_height + 0.1
		
		# Prüfe ob nächster Punkt in Plateau läuft
		var hits_plateau = false
		if paths_can_climb_plateaus:
			for plateau in plateaus:
				var dist_to_plateau = Vector2(
					next_pos.x - plateau.position.x,
					next_pos.z - plateau.position.z
				).length()
				
				# Stoppe Pfad wenn er Plateau-Wand erreicht
				if dist_to_plateau < plateau.radius:
					hits_plateau = true
					break
		
		# Wenn Plateau getroffen: Stoppe diesen Pfad-Teil
		if hits_plateau:
			# Optional: Starte neuen Pfad-Teil AUF dem Plateau
			# Für jetzt: Pfad endet hier
			break
		
		# Prüfe Weltgrenzen
		if abs(next_pos.x) > world_size.x / 2 or abs(next_pos.z) > world_size.y / 2:
			break
		
		points.append(next_pos)
		current_pos = next_pos
		traveled_distance += segment_length
	
	data.points = points
	data.width = path_width
	data.total_length = traveled_distance
	
	return data

func get_height_at_position(x: float, z: float) -> float:
	# Prüfe ob Position auf einem Plateau liegt
	for plateau in plateaus:
		var dist_2d = Vector2(x - plateau.position.x, z - plateau.position.z).length()
		
		if dist_2d <= plateau.radius:
			# Punkt liegt auf diesem Plateau
			# Gib Top des Plateaus zurück + etwas Überhang
			var height = plateau.position.y + plateau.height + 0.1
			return height
	
	# Nicht auf Plateau = Bodenhöhe + etwas drüber
	return ground_height + 0.1

func create_path_mesh(data: Dictionary) -> MeshInstance3D:
	if data.points.size() < 2:
		print("      FEHLER: Zu wenig Punkte für Pfad-Mesh")
		return null
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Path"
	
	var array_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	
	var points = data.points
	var width = data.width
	
	print("      Erstelle Mesh mit %d Punkten, Breite %.1fm" % [points.size(), width])
	
	# Generiere Mesh entlang des Pfades
	var accumulated_distance = 0.0
	
	for i in range(points.size()):
		var pos = points[i]
		
		# Berechne Richtung für dieses Segment
		var forward = Vector3.FORWARD
		if i < points.size() - 1:
			forward = (points[i + 1] - pos).normalized()
		elif i > 0:
			forward = (pos - points[i - 1]).normalized()
		
		# Rechte Richtung (senkrecht zur Bewegung)
		var right = Vector3(forward.z, 0, -forward.x).normalized()
		
		# Zwei Vertices: links und rechts vom Pfad
		var left = pos - right * width * 0.5
		var right_pos = pos + right * width * 0.5
		
		# Y ist schon korrekt gesetzt in get_height_at_position
		# Kein zusätzlicher Offset nötig!
		
		vertices.append(left)
		vertices.append(right_pos)
		
		# Normalen zeigen nach oben
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		
		# UV entlang des Pfades
		var u_left = 0.0
		var u_right = 1.0
		var v = accumulated_distance / width  # Für Textur-Tiling
		
		uvs.append(Vector2(u_left, v))
		uvs.append(Vector2(u_right, v))
		
		if i > 0:
			accumulated_distance += points[i].distance_to(points[i - 1])
	
	# Indices für Quads zwischen Punkten
	for i in range(points.size() - 1):
		var base = i * 2
		
		# Zwei Dreiecke pro Quad
		indices.append(base)
		indices.append(base + 2)
		indices.append(base + 1)
		
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base + 3)
	
	# Setze Arrays
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	# Erstelle Mesh
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = array_mesh
	
	# Material mit Pfad-Shader für weiche Ränder
	var material = ShaderMaterial.new()
	var shader = load("res://scripts/shader/path_shader.gdshader")
	
	if shader and path_texture and grass_texture:
		material.shader = shader
		material.set_shader_parameter("path_texture", path_texture)
		material.set_shader_parameter("grass_texture", grass_texture)
		material.set_shader_parameter("edge_fade", 0.3)  # 30% Randübergang
		print("    Pfad nutzt Shader mit Rand-Überblendung")
	else:
		# Fallback: Standard-Material
		var standard = StandardMaterial3D.new()
		if path_texture:
			standard.albedo_texture = path_texture
			print("    Pfad nutzt path_texture (ohne Überblendung)")
		else:
			standard.albedo_color = Color(0.8, 0.7, 0.5)
			print("    Pfad nutzt Fallback-Farbe (hell beige)")
		
		standard.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		standard.cull_mode = BaseMaterial3D.CULL_DISABLED
		material = standard
	
	mesh_instance.set_surface_override_material(0, material)
	
	# WICHTIG: Erst add_child, DANN owner setzen!
	# (wird in generate_paths gemacht)
	
	return mesh_instance

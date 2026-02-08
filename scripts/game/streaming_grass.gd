@tool
extends Node3D
class_name StreamingGrass

## Streaming Grass System - Optimiert für keine Ruckler
## Spawnt Gras basierend auf einer Density Map (PNG)
## Verwendet vorallokierten Buffer und inkrementelle Updates

@export_group("Terrain")
@export var terrain: Node3D

@export_group("Grass Setup")
## Das Gras-Mesh (einzelner Halm oder Büschel)
@export var grass_mesh: Mesh
## Material für das Gras
@export var grass_material: Material
## Density Map (Weiß = Gras, Schwarz = kein Gras)
@export var density_map: Texture2D

@export_group("Map Settings")
## Weltgröße die die Map abdeckt (in Metern)
@export var map_world_size: Vector2 = Vector2(5000, 5000)
## Offset der Map vom World Origin
@export var map_offset: Vector2 = Vector2.ZERO

@export_group("Grass Density")
## Grashalme pro Quadratmeter bei voller Dichte (weiß)
@export var grass_per_sqm: float = 100.0
## Minimale Dichte (Graustufe) ab der Gras spawnt
@export var min_density_threshold: float = 0.1

@export_group("Grass Appearance")
## Basis-Skalierung
@export var base_scale: Vector3 = Vector3(1, 1, 1)
## Zufällige Skalierungsvarianz
@export var scale_variance: float = 0.3
## Zufällige Rotation
@export var random_rotation: bool = true
## Höhenoffset (in den Boden einsinken)
@export var height_offset: float = -0.05

@export_group("Streaming")
## Radius um Kamera in dem Gras sichtbar ist
@export var view_radius: float = 100.0
## Chunk-Größe für das Streaming (intern)
@export var chunk_size: float = 25.0
## Update-Interval in Sekunden
@export var update_interval: float = 0.3

@export_group("Performance")
## Maximale Grashalme insgesamt (Buffer-Größe)
@export var max_instances: int = 100000
## Transforms pro Frame ins MultiMesh kopieren
@export var copies_per_frame: int = 5000
## Chunks pro Frame generieren
@export var chunks_per_frame: int = 1

@export_group("Debug")
@export var debug_mode: bool = false
@export var regenerate: bool = false:
	set(value):
		if value:
			_force_regenerate()
			regenerate = false

# Interne Variablen
var _multimesh_instance: MultiMeshInstance3D
var _multimesh: MultiMesh
var _density_image: Image
var _chunk_data: Dictionary = {}  # Vector2i -> PackedFloat32Array (transforms als flat array)
var _active_chunks: Dictionary = {}  # Vector2i -> true
var _camera: Camera3D
var _last_camera_chunk: Vector2i = Vector2i(-99999, -99999)
var _update_timer: float = 0.0
var _terrain_data = null

# Für inkrementelles Update
var _pending_buffer: PackedFloat32Array  # Alle aktiven Transforms als flat array
var _pending_count: int = 0
var _copy_index: int = 0
var _is_copying: bool = false
var _needs_full_rebuild: bool = false

# Chunk-Generierung Queue
var _chunks_to_generate: Array[Vector2i] = []
var _chunks_to_remove: Array[Vector2i] = []

# Seed für konsistente Gras-Positionen
var _rng: RandomNumberGenerator


func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_setup_multimesh()
	_load_density_map()
	
	if terrain:
		_terrain_data = terrain.get("data")
	
	# Initial update
	call_deferred("_force_regenerate")


func _process(delta: float) -> void:
	# Inkrementelles Kopieren fortsetzen
	if _is_copying:
		_continue_copying()
		return
	
	# Chunk-Generierung
	if _chunks_to_generate.size() > 0:
		_process_chunk_generation()
		return
	
	# Chunk-Entfernung
	if _chunks_to_remove.size() > 0:
		_process_chunk_removal()
		return
	
	# Rebuild wenn nötig
	if _needs_full_rebuild:
		_start_rebuild()
		_needs_full_rebuild = false
		return
	
	# Kamera-Update mit Interval
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_check_camera_movement()


func _setup_multimesh() -> void:
	# Bestehendes entfernen
	for child in get_children():
		if child is MultiMeshInstance3D:
			child.queue_free()
	
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.name = "GrassMultiMesh"
	add_child(_multimesh_instance)
	
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = false
	
	if grass_mesh:
		_multimesh.mesh = grass_mesh
	
	# Buffer vorallokieren!
	_multimesh.instance_count = max_instances
	_multimesh.visible_instance_count = 0  # Erstmal nichts sichtbar
	
	_multimesh_instance.multimesh = _multimesh
	
	if grass_material:
		_multimesh_instance.material_override = grass_material
	
	# Pending buffer vorallokieren (12 floats pro Transform)
	_pending_buffer.resize(max_instances * 12)


func _load_density_map() -> void:
	if density_map == null:
		push_warning("StreamingGrass: Keine Density Map zugewiesen!")
		return
	
	_density_image = density_map.get_image()
	if _density_image == null:
		push_error("StreamingGrass: Konnte Density Map nicht laden!")
		return
	
	if _density_image.is_compressed():
		_density_image.decompress()
	
	print("StreamingGrass: Density Map geladen - ", _density_image.get_width(), "x", _density_image.get_height())


func _check_camera_movement() -> void:
	# Kamera finden
	if Engine.is_editor_hint():
		var viewport = EditorInterface.get_editor_viewport_3d()
		if viewport:
			_camera = viewport.get_camera_3d()
	else:
		_camera = get_viewport().get_camera_3d()
	
	if _camera == null:
		return
	
	var camera_pos = _camera.global_position
	var camera_chunk = Vector2i(
		int(floor(camera_pos.x / chunk_size)),
		int(floor(camera_pos.z / chunk_size))
	)
	
	# Nur wenn sich Chunk geändert hat
	if camera_chunk == _last_camera_chunk:
		return
	
	_last_camera_chunk = camera_chunk
	_update_visible_chunks(camera_pos, camera_chunk)


func _update_visible_chunks(camera_pos: Vector3, camera_chunk: Vector2i) -> void:
	var chunks_radius = int(ceil(view_radius / chunk_size)) + 1
	var needed_chunks: Dictionary = {}
	
	# Finde benötigte Chunks
	for dx in range(-chunks_radius, chunks_radius + 1):
		for dz in range(-chunks_radius, chunks_radius + 1):
			var chunk = Vector2i(camera_chunk.x + dx, camera_chunk.y + dz)
			var chunk_center = Vector3(
				chunk.x * chunk_size + chunk_size / 2.0,
				camera_pos.y,
				chunk.y * chunk_size + chunk_size / 2.0
			)
			
			var dist = Vector2(camera_pos.x, camera_pos.z).distance_to(
				Vector2(chunk_center.x, chunk_center.z)
			)
			
			if dist <= view_radius + chunk_size:
				needed_chunks[chunk] = true
	
	# Chunks zum Entfernen finden
	for chunk in _active_chunks.keys():
		if not needed_chunks.has(chunk):
			if chunk not in _chunks_to_remove:
				_chunks_to_remove.append(chunk)
	
	# Chunks zum Generieren finden
	for chunk in needed_chunks.keys():
		if not _active_chunks.has(chunk) and not _chunk_data.has(chunk):
			if chunk not in _chunks_to_generate:
				_chunks_to_generate.append(chunk)


func _process_chunk_generation() -> void:
	var generated = 0
	
	while _chunks_to_generate.size() > 0 and generated < chunks_per_frame:
		var chunk: Vector2i = _chunks_to_generate.pop_front()
		_generate_chunk_data(chunk)
		_active_chunks[chunk] = true
		generated += 1
	
	if generated > 0:
		_needs_full_rebuild = true


func _process_chunk_removal() -> void:
	var removed = 0
	
	while _chunks_to_remove.size() > 0 and removed < chunks_per_frame:
		var chunk: Vector2i = _chunks_to_remove.pop_front()
		_active_chunks.erase(chunk)
		# Chunk-Daten behalten für Cache (optional entfernen für weniger RAM)
		removed += 1
	
	if removed > 0:
		_needs_full_rebuild = true


func _generate_chunk_data(chunk: Vector2i) -> void:
	if _density_image == null:
		return
	
	# Falls bereits generiert, nutze Cache
	if _chunk_data.has(chunk):
		return
	
	var transforms: PackedFloat32Array = PackedFloat32Array()
	var chunk_world_x = chunk.x * chunk_size
	var chunk_world_z = chunk.y * chunk_size
	
	# Seed basierend auf Chunk-Position für Konsistenz
	_rng.seed = hash(chunk)
	
	var grass_count = int(chunk_size * chunk_size * grass_per_sqm)
	
	for i in range(grass_count):
		var local_x = _rng.randf() * chunk_size
		var local_z = _rng.randf() * chunk_size
		var world_x = chunk_world_x + local_x
		var world_z = chunk_world_z + local_z
		
		# Density prüfen
		var density = _sample_density(world_x, world_z)
		if density < min_density_threshold:
			continue
		
		if _rng.randf() > density:
			continue
		
		# Höhe vom Terrain
		var world_y = height_offset
		if _terrain_data and _terrain_data.has_method("get_height"):
			var h = _terrain_data.call("get_height", Vector3(world_x, 0, world_z))
			if not is_nan(h):
				world_y = h + height_offset
		
		# Transform berechnen
		var rot_y = _rng.randf() * TAU if random_rotation else 0.0
		var scale_factor = 1.0 + _rng.randf_range(-scale_variance, scale_variance)
		var scale = base_scale * scale_factor
		
		# Transform als 12 Floats (3x4 Matrix, Basis + Origin)
		var cos_r = cos(rot_y)
		var sin_r = sin(rot_y)
		
		# Basis X (column 0)
		transforms.append(cos_r * scale.x)
		transforms.append(0.0)
		transforms.append(-sin_r * scale.x)
		
		# Basis Y (column 1)
		transforms.append(0.0)
		transforms.append(scale.y)
		transforms.append(0.0)
		
		# Basis Z (column 2)
		transforms.append(sin_r * scale.z)
		transforms.append(0.0)
		transforms.append(cos_r * scale.z)
		
		# Origin (column 3)
		transforms.append(world_x)
		transforms.append(world_y)
		transforms.append(world_z)
	
	_chunk_data[chunk] = transforms
	
	if debug_mode:
		print("StreamingGrass: Chunk ", chunk, " generiert mit ", transforms.size() / 12, " Grashalmen")


func _sample_density(world_x: float, world_z: float) -> float:
	if _density_image == null:
		return 0.0
	
	var u = (world_x - map_offset.x + map_world_size.x / 2.0) / map_world_size.x
	var v = (world_z - map_offset.y + map_world_size.y / 2.0) / map_world_size.y
	
	if u < 0 or u > 1 or v < 0 or v > 1:
		return 0.0
	
	var px = int(u * (_density_image.get_width() - 1))
	var pz = int(v * (_density_image.get_height() - 1))
	
	px = clamp(px, 0, _density_image.get_width() - 1)
	pz = clamp(pz, 0, _density_image.get_height() - 1)
	
	var color = _density_image.get_pixel(px, pz)
	return color.get_luminance()


func _start_rebuild() -> void:
	# Alle aktiven Chunk-Transforms sammeln
	_pending_count = 0
	
	for chunk in _active_chunks.keys():
		if not _chunk_data.has(chunk):
			continue
		
		var chunk_transforms: PackedFloat32Array = _chunk_data[chunk]
		var chunk_grass_count = chunk_transforms.size() / 12
		
		# In pending buffer kopieren
		for i in range(chunk_transforms.size()):
			if _pending_count * 12 + (i % 12) < _pending_buffer.size():
				var grass_idx = _pending_count + (i / 12)
				if grass_idx < max_instances:
					_pending_buffer[grass_idx * 12 + (i % 12)] = chunk_transforms[i]
		
		_pending_count += chunk_grass_count
		
		if _pending_count >= max_instances:
			_pending_count = max_instances
			break
	
	# Starte inkrementelles Kopieren
	_copy_index = 0
	_is_copying = true
	
	if debug_mode:
		print("StreamingGrass: Rebuild gestartet mit ", _pending_count, " Grashalmen")


func _continue_copying() -> void:
	var end_index = min(_copy_index + copies_per_frame, _pending_count)
	
	# Kopiere Transforms ins MultiMesh
	for i in range(_copy_index, end_index):
		var transform = Transform3D()
		var base_idx = i * 12
		
		transform.basis.x = Vector3(_pending_buffer[base_idx], _pending_buffer[base_idx + 1], _pending_buffer[base_idx + 2])
		transform.basis.y = Vector3(_pending_buffer[base_idx + 3], _pending_buffer[base_idx + 4], _pending_buffer[base_idx + 5])
		transform.basis.z = Vector3(_pending_buffer[base_idx + 6], _pending_buffer[base_idx + 7], _pending_buffer[base_idx + 8])
		transform.origin = Vector3(_pending_buffer[base_idx + 9], _pending_buffer[base_idx + 10], _pending_buffer[base_idx + 11])
		
		_multimesh.set_instance_transform(i, transform)
	
	_copy_index = end_index
	
	# Update visible count progressiv
	_multimesh.visible_instance_count = _copy_index
	
	# Fertig?
	if _copy_index >= _pending_count:
		_is_copying = false
		if debug_mode:
			print("StreamingGrass: Rebuild fertig - ", _pending_count, " Grashalme sichtbar")


func _force_regenerate() -> void:
	_chunk_data.clear()
	_active_chunks.clear()
	_chunks_to_generate.clear()
	_chunks_to_remove.clear()
	_last_camera_chunk = Vector2i(-99999, -99999)
	_multimesh.visible_instance_count = 0
	_is_copying = false
	
	_load_density_map()
	
	if terrain:
		_terrain_data = terrain.get("data")
	
	print("StreamingGrass: Regenerierung gestartet")


func get_stats() -> Dictionary:
	return {
		"active_chunks": _active_chunks.size(),
		"cached_chunks": _chunk_data.size(),
		"visible_grass": _multimesh.visible_instance_count if _multimesh else 0,
		"max_instances": max_instances,
		"is_copying": _is_copying,
		"pending_generate": _chunks_to_generate.size(),
		"pending_remove": _chunks_to_remove.size()
	}

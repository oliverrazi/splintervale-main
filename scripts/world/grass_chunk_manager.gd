@tool
extends Node3D
class_name GrassChunkManager

var chunk_scene: PackedScene
var chunk_size: float = 5.0
var active_radius: float = 40.0
var unload_radius: float = 60.0
var max_chunks_per_frame: int = 1  # REDUZIERT für bessere Performance
var chunk_fade_duration: float = 0.35
var use_fade_animation: bool = false  # OPTIONAL: Animationen deaktivieren für Performance

var all_chunk_positions: Array[Dictionary] = []
var active_chunks: Dictionary = {}
var chunks_to_load: Array[Dictionary] = []
var chunks_to_unload: Array[String] = []
var grass_container: Node3D
var plateau_generator: PlateauGenerator = null
var ground_height: float = 0.0
var update_timer: float = 0.0
var update_interval: float = 0.5  # ERHÖHT für weniger häufige Updates

# Performance-Tracking
var last_camera_pos: Vector3 = Vector3.ZERO
var min_camera_move_distance: float = 5.0  # Nur updaten wenn Kamera sich bewegt hat

func _ready() -> void:
	grass_container = Node3D.new()
	grass_container.name = "Chunks"
	add_child(grass_container)
	if Engine.is_editor_hint():
		grass_container.owner = get_tree().edited_scene_root

func setup(world_size: Vector2, p_ground_height: float, plateau_gen: PlateauGenerator = null) -> void:
	ground_height = p_ground_height
	plateau_generator = plateau_gen
	
	if not chunk_scene:
		push_warning("GrassChunkManager: No chunk_scene assigned!")
		return
	
	all_chunk_positions.clear()
	
	var ext_x: int = int(world_size.x / chunk_size)
	var ext_z: int = int(world_size.y / chunk_size)
	
	# Erstelle Chunk-Positionen
	for x in range(-ext_x / 2, ext_x / 2 + 1):
		for z in range(-ext_z / 2, ext_z / 2 + 1):
			var x_pos: float = x * chunk_size
			var z_pos: float = z * chunk_size
			
			var world_pos: Vector3 = Vector3(x_pos, ground_height, z_pos)
			
			all_chunk_positions.append({
				"grid_pos": Vector2i(x, z),
				"world_pos": world_pos,
				"world_pos_2d": Vector2(x_pos, z_pos)  # Für schnellere 2D-Distanz
			})
	
	initial_load()

func clear() -> void:
	for chunk: Node in active_chunks.values():
		if is_instance_valid(chunk):
			chunk.queue_free()
	active_chunks.clear()
	chunks_to_load.clear()
	chunks_to_unload.clear()
	all_chunk_positions.clear()

func initial_load() -> void:
	if Engine.is_editor_hint():
		return
		
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		last_camera_pos = camera.global_position
		# Lade initial mehr Chunks ohne Animation für schnelleren Start
		var old_max: int = max_chunks_per_frame
		var old_anim: bool = use_fade_animation
		max_chunks_per_frame = 10
		use_fade_animation = false
		
		update_chunks(camera)
		# Prozessiere sofort
		for i in range(5):
			process_chunks(0.0)
		
		max_chunks_per_frame = old_max
		use_fade_animation = old_anim

func process_chunks(delta: float) -> void:
	# Lade Chunks (limitiert)
	var loaded: int = 0
	while chunks_to_load.size() > 0 and loaded < max_chunks_per_frame:
		var data: Dictionary = chunks_to_load.pop_front()
		var key: String = str(data.grid_pos)
		if not active_chunks.has(key):
			if use_fade_animation:
				activate_chunk_animated(data)
			else:
				activate_chunk_instant(data)
			loaded += 1
	
	# Entlade Chunks (mehr auf einmal möglich)
	var unloaded: int = 0
	var max_unloads: int = max_chunks_per_frame * 2  # Entladen geht schneller
	while chunks_to_unload.size() > 0 and unloaded < max_unloads:
		var key: String = chunks_to_unload.pop_front()
		if active_chunks.has(key):
			if use_fade_animation:
				deactivate_chunk_animated(key)
			else:
				deactivate_chunk_instant(key)
			unloaded += 1
	
	# Update nur wenn nötig
	if Engine.is_editor_hint():
		return
		
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera:
			# Nur updaten wenn Kamera sich bewegt hat
			var cam_moved: float = camera.global_position.distance_to(last_camera_pos)
			if cam_moved >= min_camera_move_distance:
				last_camera_pos = camera.global_position
				update_chunks(camera)

func update_chunks(camera: Camera3D) -> void:
	chunks_to_load.clear()
	chunks_to_unload.clear()
	
	var cam_pos_2d: Vector2 = Vector2(camera.global_position.x, camera.global_position.z)
	
	for data: Dictionary in all_chunk_positions:
		# Verwende 2D-Distanz für Performance (Höhe ist weniger wichtig für Sichtbarkeit)
		var dist: float = cam_pos_2d.distance_to(data.world_pos_2d)
		
		var key: String = str(data.grid_pos)
		
		if dist <= active_radius and not active_chunks.has(key):
			chunks_to_load.append(data)
		elif dist >= unload_radius and active_chunks.has(key):
			chunks_to_unload.append(key)
	
	# Sortiere nur wenn nötig
	if chunks_to_load.size() > max_chunks_per_frame:
		chunks_to_load.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return cam_pos_2d.distance_to(a.world_pos_2d) < cam_pos_2d.distance_to(b.world_pos_2d)
		)

func activate_chunk_instant(data: Dictionary) -> void:
	if not chunk_scene:
		return
	
	var key: String = str(data.grid_pos)
	if active_chunks.has(key):
		return
	
	var chunk: Node = chunk_scene.instantiate()
	chunk.position = data.world_pos
	
	if chunk.has_method("setup_height_provider"):
		chunk.call("setup_height_provider", plateau_generator, data.world_pos, chunk_size, ground_height)
	
	grass_container.add_child(chunk)
	
	if Engine.is_editor_hint():
		chunk.owner = get_tree().edited_scene_root
	
	active_chunks[key] = chunk

func activate_chunk_animated(data: Dictionary) -> void:
	if not chunk_scene:
		return
	
	var key: String = str(data.grid_pos)
	if active_chunks.has(key):
		return
	
	var chunk: Node = chunk_scene.instantiate()
	chunk.position = data.world_pos
	
	if chunk.has_method("setup_height_provider"):
		chunk.call("setup_height_provider", plateau_generator, data.world_pos, chunk_size, ground_height)
	
	chunk.scale = Vector3(0.01, 0.01, 0.01)
	grass_container.add_child(chunk)
	
	if Engine.is_editor_hint():
		chunk.owner = get_tree().edited_scene_root
	
	active_chunks[key] = chunk
	
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(chunk, "scale", Vector3.ONE, chunk_fade_duration)

func deactivate_chunk_instant(key: String) -> void:
	if not active_chunks.has(key):
		return
	
	var chunk: Node = active_chunks[key]
	if is_instance_valid(chunk):
		chunk.queue_free()
	
	active_chunks.erase(key)

func deactivate_chunk_animated(key: String) -> void:
	if not active_chunks.has(key):
		return
	
	var chunk: Node = active_chunks[key]
	if not is_instance_valid(chunk):
		active_chunks.erase(key)
		return
	
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(chunk, "scale", Vector3(0.01, 0.01, 0.01), chunk_fade_duration * 0.6)
	tween.tween_callback(func():
		if is_instance_valid(chunk):
			chunk.queue_free()
	)
	
	active_chunks.erase(key)

# Performance-Helper
func get_active_chunk_count() -> int:
	return active_chunks.size()

func get_pending_chunk_count() -> int:
	return chunks_to_load.size() + chunks_to_unload.size()
	
	

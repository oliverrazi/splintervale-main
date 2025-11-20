@tool  # WICHTIG!
class_name GrassChunkManager
extends Node3D

## Verwaltet das Laden/Entladen von Grass-Chunks

# Settings
var chunk_scene: PackedScene
var chunk_size: float = 5.0
var active_radius: float = 40.0
var unload_radius: float = 60.0
var use_directional_culling: bool = true
var view_angle: float = 130.0
var max_chunks_per_frame: int = 3
var chunk_fade_duration: float = 0.35

# Interne Variablen
var all_chunk_positions := []
var active_chunks := {}  # Now uses composite key: "x,z,y"
var chunk_tweens := {}
var update_timer := 0.0
var chunks_to_load := []
var chunks_to_unload := []
var grass_container: Node3D
var plateau_generator: PlateauGenerator

signal chunk_ready_for_elevation(chunk: Node3D, world_pos: Vector3)

const GrassChunk := preload("res://scripts/world/grass_chunk_dyn.gd")   # Pfad anpassen!

func _ready():
	self.chunk_ready_for_elevation.connect(_on_chunk_ready_for_elevation, CONNECT_DEFERRED)

# Helper function to create unique chunk key including elevation
func get_chunk_key(grid_pos: Vector2i, y_level: float) -> String:
	return "%d,%d,%.1f" % [grid_pos.x, grid_pos.y, y_level]

	
func setup(world_size: Vector2, ground_height: float, plateau_gen: PlateauGenerator = null):
	plateau_generator = plateau_gen
	if not chunk_scene:
		print("  Keine Grass-Chunk-Scene zugewiesen")
		return
	if not grass_container:
		grass_container = Node3D.new()
		grass_container.name = "Chunks"
		add_child(grass_container)
	
	all_chunk_positions.clear()
	
	# Get all ground levels
	var levels: Array[Dictionary] = plateau_gen.get_ground_levels() if plateau_gen else []
	if levels.is_empty():
		levels = [{ "y": ground_height, "radius": INF }]
	
	var extent_x := int(world_size.x / chunk_size)
	var extent_z := int(world_size.y / chunk_size)
	
	for x in range(-extent_x / 2, extent_x / 2):
		for z in range(-extent_z / 2, extent_z / 2):
			var world_x = x * chunk_size
			var world_z = z * chunk_size
			var chunk_center_2d = Vector2(world_x + chunk_size * 0.5, world_z + chunk_size * 0.5)
			
			# Check which levels this chunk position needs
			for lvl in levels:
				# Skip if outside radius
				if lvl.radius < INF:
					var dist := chunk_center_2d.distance_to(Vector2.ZERO)
					if dist > lvl.radius + chunk_size:
						continue
				
				# For non-ground levels, check if chunk actually overlaps plateau
				if lvl.y > ground_height and plateau_gen:
					var has_plateau = false
					# Check if any part of this chunk is on this plateau level
					for px in range(2):
						for pz in range(2):
							var test_pos = Vector2(
								world_x + px * chunk_size,
								world_z + pz * chunk_size
							)
							var elevation = plateau_gen.get_elevation_at_position(test_pos)
							if abs(elevation - lvl.y) < 0.1:
								has_plateau = true
								break
						if has_plateau:
							break
					
					if not has_plateau:
						continue
				
				var chunk_corners: Array[Vector2] = [
					Vector2(world_x, world_z),
					Vector2(world_x + chunk_size, world_z),
					Vector2(world_x, world_z + chunk_size),
					Vector2(world_x + chunk_size, world_z + chunk_size)
				]

				var plateau_area: float = 0.0
				for corner: Vector2 in chunk_corners:
					if not is_nan(plateau_gen.get_plateau_elevation_if_inside(corner)):
						plateau_area += 1.0

				var plateau_ratio: float = plateau_area / 4.0
				if plateau_ratio >= 0.25:  # mindestens 25 % des Chunks auf Plateau
					var chunk_data := {
						"grid_pos": Vector2i(x, z),
						"world_pos": Vector3(world_x, lvl.y, world_z),
						"level_y": lvl.y,
						"chunk_key": get_chunk_key(Vector2i(x, z), lvl.y)
					}
					all_chunk_positions.append(chunk_data)
	
	print("  %d Chunks auf %d Ebenen generiert" % [all_chunk_positions.size(), levels.size()])
	call_deferred("initial_load")
	
	
func setup_editor_preview(world_size: Vector2, ground_height: float, plateau_gen: PlateauGenerator = null):
	print("Bereite Editor-Vorschau (minimal)...")
	
	plateau_generator = plateau_gen
	
	if not chunk_scene:
		return
	
	if not grass_container:
		grass_container = Node3D.new()
		grass_container.name = "Chunks"
		add_child(grass_container)
	
	all_chunk_positions.clear()
	
	# Nur 3x3 Chunks
	for x in range(-1, 2):
		for z in range(-1, 2):
			var chunk_data = {
				"grid_pos": Vector2i(x, z),
				"world_pos": Vector3(x * chunk_size, ground_height, z * chunk_size)
			}
			all_chunk_positions.append(chunk_data)
			activate_chunk_instant(chunk_data)
	
	print("  9 Preview-Chunks geladen (mit Elevation)")

func clear():
	all_chunk_positions.clear()
	
	for chunk in active_chunks.values():
		if is_instance_valid(chunk):
			chunk.queue_free()
	
	active_chunks.clear()
	chunk_tweens.clear()
	chunks_to_load.clear()
	chunks_to_unload.clear()
	
	if grass_container:
		for child in grass_container.get_children():
			child.queue_free()

func initial_load():
	var camera = get_viewport().get_camera_3d()
	if camera:
		update_chunks(camera)

func process_chunks(delta: float):
	# Load chunks
	var loaded_this_frame = 0
	while chunks_to_load.size() > 0 and loaded_this_frame < max_chunks_per_frame:
		var chunk_data = chunks_to_load.pop_front()
		var chunk_key = chunk_data.chunk_key
		if not active_chunks.has(chunk_key):
			activate_chunk_animated(chunk_data)
			loaded_this_frame += 1
	
	# Unload chunks
	var unloaded_this_frame = 0
	while chunks_to_unload.size() > 0 and unloaded_this_frame < max_chunks_per_frame:
		var chunk_key = chunks_to_unload.pop_front()
		if active_chunks.has(chunk_key):
			deactivate_chunk(chunk_key)
			unloaded_this_frame += 1
	
	# Update timer
	update_timer += delta
	if update_timer < 0.25:
		return
	update_timer = 0.0
	
	var camera = get_viewport().get_camera_3d()
	if camera:
		update_chunks(camera)
		
func update_chunks(camera: Camera3D):
	var camera_pos = camera.global_position
	var camera_forward = -camera.global_transform.basis.z
	
	chunks_to_load.clear()
	chunks_to_unload.clear()
	
	for chunk_data in all_chunk_positions:
		var chunk_world_pos = chunk_data.world_pos
		var chunk_key = chunk_data.chunk_key
		var distance = camera_pos.distance_to(chunk_world_pos)
		
		var should_load = false
		
		if distance <= active_radius:
			if use_directional_culling:
				var to_chunk = (chunk_world_pos - camera_pos).normalized()
				var dot = camera_forward.dot(to_chunk)
				var angle_threshold = cos(deg_to_rad(view_angle / 2.0))
				should_load = dot > angle_threshold
			else:
				should_load = true
		
		if should_load:
			if not active_chunks.has(chunk_key):
				chunks_to_load.append(chunk_data)
		elif distance >= unload_radius:
			if active_chunks.has(chunk_key):
				chunks_to_unload.append(chunk_key)
	
	chunks_to_load.sort_custom(func(a, b):
		return camera_pos.distance_to(a.world_pos) < camera_pos.distance_to(b.world_pos)
	)

func activate_chunk_animated(chunk_data: Dictionary) -> void:
	if not chunk_scene:
		return
	var chunk_key = chunk_data.chunk_key
	if active_chunks.has(chunk_key):
		return
	
	var chunk = chunk_scene.instantiate()
	chunk.position = chunk_data.world_pos
	chunk.scale = Vector3(0.01, 0.01, 0.01)
	grass_container.add_child(chunk)
	active_chunks[chunk_key] = chunk
	
	# No elevation adjustment needed - chunk is already at correct height
	
	var tween = create_tween()
	tween.tween_property(chunk, "scale", Vector3.ONE, chunk_fade_duration)
	chunk_tweens[chunk_key] = tween
	
	
func _on_chunk_ready_for_elevation(chunk: Node3D, world_pos: Vector3) -> void:
	await chunk.ready
	await get_tree().process_frame
	if is_instance_valid(chunk) and chunk.has_method("project_grass_to_grass"):
		(chunk as GrassChunk).project_grass_to_ground()
		
func activate_chunk_instant(chunk_data: Dictionary) -> void:
	if not chunk_scene:
		return
	
	var chunk_key = chunk_data.chunk_key
	var chunk = chunk_scene.instantiate()
	chunk.position = chunk_data.world_pos
	
	grass_container.add_child(chunk)
	active_chunks[chunk_key] = chunk
	
	# No elevation adjustment needed - chunk is already at correct height
	
	if Engine.is_editor_hint():
		var scene_root = get_tree().edited_scene_root
		if scene_root:
			chunk.owner = scene_root
			

func deactivate_chunk(chunk_key: String) -> void:
	if not active_chunks.has(chunk_key):
		return
	
	var chunk = active_chunks[chunk_key]
	
	if chunk_tweens.has(chunk_key):
		var old_tween = chunk_tweens[chunk_key]
		if old_tween and old_tween.is_valid():
			old_tween.kill()
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(chunk, "scale", Vector3(0.01, 0.01, 0.01), chunk_fade_duration * 0.6)
	tween.tween_callback(func():
		if is_instance_valid(chunk):
			chunk.queue_free()
		chunk_tweens.erase(chunk_key)
	)
	
	chunk_tweens[chunk_key] = tween
	active_chunks.erase(chunk_key)

func apply_elevation_to_chunk(chunk: Node3D, chunk_base_pos: Vector3):
	print(">>> apply_elevation_to_chunk für (%.1f, %.1f) <<<" % [
		chunk_base_pos.x, chunk_base_pos.z
	])
	
	if not plateau_generator:
		print("  !!! FEHLER: Kein plateau_generator !!!")
		return
	
	if not is_instance_valid(chunk):
		print("  !!! FEHLER: Chunk ungültig !!!")
		return
	
	var chunk_center_2d = Vector2(chunk_base_pos.x, chunk_base_pos.z)
	var elevation = plateau_generator.get_chunk_elevation(chunk_center_2d)
	
	print("  Elevation: %.1f, Base: %.1f" % [elevation, chunk_base_pos.y])
	
	if elevation <= chunk_base_pos.y:
		return
	
	var height_offset = elevation - chunk_base_pos.y
	print("  !!! ANHEBUNG: %.1f Meter !!!" % height_offset)
	
	var multimesh_count = 0
	var instances_moved = 0
	
	for child in chunk.get_children():
		if child is MultiMeshInstance3D:
			multimesh_count += 1
			var mmi = child as MultiMeshInstance3D
			var mm = mmi.multimesh
			
			if not mm:
				print("    MultiMesh %d: NULL" % multimesh_count)
				continue
			
			if mm.instance_count == 0:
				print("    MultiMesh %d: 0 Instanzen" % multimesh_count)
				continue
			
			print("    MultiMesh %d: %d Instanzen - ANHEBEN" % [multimesh_count, mm.instance_count])
			
			for i in range(mm.instance_count):
				var transform = mm.get_instance_transform(i)
				var old_y = transform.origin.y
				transform.origin.y += height_offset
				mm.set_instance_transform(i, transform)
				instances_moved += 1
				
				# Debug für erste Instanz
				if i == 0:
					print("      Instanz 0: Y %.2f -> %.2f" % [old_y, transform.origin.y])
	
	print("  FERTIG: %d MultiMeshes, %d Instanzen bewegt" % [multimesh_count, instances_moved])

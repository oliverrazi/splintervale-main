@tool
extends Node3D
class_name GrassChunkPainter

## Szene mit deinem GrassChunk (res://grass_chunk.tscn)
@export var chunk_scene: PackedScene

## Muss zur tatsächlichen Größe deiner GrassChunks passen
@export var chunk_size: float = 5.0

## Radius des "Pinsels" in Metern (XZ-Ebene)
@export var brush_radius: float = 15.0

## Optional: Gras auf dem Boden einrasten lassen (per Raycast nach unten)
@export var snap_to_ground: bool = false
@export var ground_collision_mask: int = 1

## Button im Inspector: Beim Setzen auf true wird an der aktuellen Position gemalt
var _paint_circle_here: bool = false
@export var paint_circle_here: bool:
	get:
		return _paint_circle_here
	set(value):
		# Nur im Editor reagieren und nur auf den Wechsel zu true
		if value and Engine.is_editor_hint():
			_paint_circle_here = false
			_paint_circle(global_transform.origin)
		else:
			_paint_circle_here = value


func _paint_circle(center_global: Vector3) -> void:
	if chunk_scene == null:
		push_warning("chunk_scene ist nicht gesetzt!")
		return

	# Wir arbeiten in lokalen Koordinaten relativ zu diesem Node
	var center_local: Vector3 = to_local(center_global)

	var existing: Dictionary = _build_chunk_map()

	# Grenzen im Grid berechnen
	var min_x: int = int(floor((center_local.x - brush_radius) / chunk_size))
	var max_x: int = int(ceil((center_local.x + brush_radius) / chunk_size))
	var min_z: int = int(floor((center_local.z - brush_radius) / chunk_size))
	var max_z: int = int(ceil((center_local.z + brush_radius) / chunk_size))

	var center_2d: Vector2 = Vector2(center_local.x, center_local.z)

	for gx in range(min_x, max_x + 1):
		for gz in range(min_z, max_z + 1):
			var px: float = float(gx) * chunk_size
			var pz: float = float(gz) * chunk_size
			var pos_2d: Vector2 = Vector2(px, pz)

			# Nur Zellen innerhalb des Radius
			if pos_2d.distance_to(center_2d) > brush_radius:
				continue

			var key: Vector2i = Vector2i(gx, gz)

			# Schon ein Chunk an dieser Grid-Position? -> Überspringen (kein Doppel)
			if existing.has(key):
				continue

			# Neuen Chunk instanzieren
			var chunk: Node3D = chunk_scene.instantiate() as Node3D
			if chunk == null:
				continue

			add_child(chunk)
			chunk.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null

			var local_pos: Vector3 = Vector3(px, center_local.y, pz)
			chunk.position = local_pos

			if snap_to_ground:
				_snap_chunk_to_ground(chunk)


func _build_chunk_map() -> Dictionary:
	# map[Vector2i(grid_x, grid_z)] = Node3D (GrassChunk)
	var map: Dictionary = {}

	for child in get_children():
		if child is Node3D:
			var node: Node3D = child
			var p: Vector3 = node.position
			var gx: int = int(round(p.x / chunk_size))
			var gz: int = int(round(p.z / chunk_size))
			var key: Vector2i = Vector2i(gx, gz)
			map[key] = node

	return map


func _snap_chunk_to_ground(chunk: Node3D) -> void:
	if get_world_3d() == null:
		return

	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return

	var from: Vector3 = chunk.global_transform.origin + Vector3(0.0, 50.0, 0.0)
	var to: Vector3 = chunk.global_transform.origin + Vector3(0.0, -200.0, 0.0)

	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = ground_collision_mask

	var result := space_state.intersect_ray(params)
	if result.has("position"):
		var hit_pos: Vector3 = result["position"]
		var local_hit: Vector3 = to_local(hit_pos)
		var local: Vector3 = chunk.position
		local.y = local_hit.y
		chunk.position = local

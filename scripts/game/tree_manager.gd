@tool
extends Node3D
class_name TreeManager

## TreeManager-System für performante Baumdarstellung
## - Ferne Bäume: gechunktes MultiMesh (Frustum-Culling pro Chunk)
## - Nahe Bäume: echte Szenen mit Occlusion-Support (UNVERÄNDERT)
##
## CHUNKING (neu):
##   Statt EINEM MultiMesh über alle Bäume gibt es pro räumlichem Chunk einen
##   eigenen MultiMeshInstance3D mit enger AABB. Godots Frustum-Culling zeichnet
##   dann nur die sichtbaren Chunks statt aller Bäume.
##
##   Die index-basierte Real-Tree-Logik bleibt erhalten: ein globaler Baumindex
##   wird intern auf (chunk_key, local_slot) gemappt.

@export_group("Tree Setup")
@export var tree_scene: PackedScene
@export var tree_mesh: Mesh
@export var tree_material: Material

@export_group("Distances")
@export var spawn_distance: float = 20.0
@export var hysteresis: float = 5.0
@export var update_interval: float = 0.2

@export_group("Performance")
@export var max_real_trees: int = 50
@export var trees_per_frame: int = 3

@export_group("Chunking")
## Kantenlänge eines Chunks in Meter. Kleiner = besseres Culling, mehr Draw Calls.
@export var chunk_size: float = 16.0:
	set(v):
		chunk_size = max(v, 1.0)
		if Engine.is_editor_hint() and _tree_data.size() > 0:
			_rebuild_multimesh()
## Distanz (Meter), ab der ein ganzer Chunk verschwindet. 0 = aus.
@export var chunk_visible_distance: float = 0.0:
	set(v):
		chunk_visible_distance = max(v, 0.0)
		_apply_chunk_visibility()
## Fade-Breite am Sichtbarkeitsrand (Meter).
@export var chunk_fade_margin: float = 8.0

var _pool: Array[Node3D] = []
@export var pool_warmup: int = 30

# Interne Daten
var _tree_data: Array[TreeData] = []
var _real_trees: Dictionary = {}
var _player: Node3D
var _update_timer: float = 0.0

var _spawn_queue: Array[int] = []
var _despawn_queue: Array[int] = []

# --- Chunk-State (neu) ---
var _chunk_root: Node3D                          # Container aller Chunk-Instanzen
var _chunks: Dictionary = {}                     # chunk_key:Vector2i -> ChunkEntry
var _index_map: Array = []                       # global index -> {chunk_key, slot}

const POOL_HIDDEN_POS := Vector3(0.0, -100000.0, 0.0)
const HIDDEN_TRANSFORM_ORIGIN := Vector3(0, -10000, 0)

class TreeData:
	var position: Vector3
	var rotation_y: float
	var scale: float
	var is_real: bool = false

	func _init(pos: Vector3, rot: float = 0.0, scl: float = 1.0) -> void:
		position = pos
		rotation_y = rot
		scale = scl

## Ein Chunk = ein MultiMeshInstance3D + die globalen Indizes seiner Bäume.
class ChunkEntry:
	var mmi: MultiMeshInstance3D
	var indices: Array[int] = []                 # global index pro lokalem Slot


func _ready() -> void:
	_prepare_mesh_materials_for_color()
	auto_load()

	if not Engine.is_editor_hint() and tree_scene != null:
		for i in pool_warmup:
			var t := tree_scene.instantiate() as Node3D
			add_child(t)
			t.position = Vector3(0, -50, 0)
			t.visible = true
			t.process_mode = Node.PROCESS_MODE_INHERIT
			_pool.append(t)
		for f in 3:
			await get_tree().process_frame
		for t in _pool:
			t.visible = false
			t.process_mode = Node.PROCESS_MODE_DISABLED
			t.position = POOL_HIDDEN_POS

	if Engine.is_editor_hint():
		return

	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_process_queues()
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_update_tree_states()


# ============================================================
#  TREE-DATEN HINZUFÜGEN (unverändert)
# ============================================================

func add_tree(position: Vector3, rotation_deg: float = 0.0, scale: float = 1.0) -> void:
	var data := TreeData.new(position, deg_to_rad(rotation_deg), scale)
	_tree_data.append(data)


func add_trees(trees: Array) -> void:
	for tree in trees:
		if tree is Dictionary:
			var pos: Vector3 = tree.get("position", Vector3.ZERO)
			var rot: float = tree.get("rotation", randf() * 360.0)
			var scl: float = tree.get("scale", randf_range(0.8, 1.2))
			add_tree(pos, rot, scl)
		elif tree is Vector3:
			add_tree(tree, randf() * 360.0, randf_range(0.8, 1.2))


func generate_random_trees(count: int, area_min: Vector3, area_max: Vector3, terrain: Node3D = null) -> void:
	for i in count:
		var x := randf_range(area_min.x, area_max.x)
		var z := randf_range(area_min.z, area_max.z)
		var y := area_min.y
		if terrain and terrain.has_method("get_height"):
			y = terrain.call("get_height", Vector3(x, 0, z))
		add_tree(Vector3(x, y, z), randf() * 360.0, randf_range(0.8, 1.2))
	_rebuild_multimesh()


func finalize() -> void:
	_rebuild_multimesh()
	print("TreeManager: ", _tree_data.size(), " Bäume initialisiert")


# ============================================================
#  CHUNK-BASIERTES MULTIMESH (neu)
# ============================================================

func _chunk_key_for(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / chunk_size)), int(floor(pos.z / chunk_size)))


## Baut die komplette Chunk-Struktur neu auf. Ersetzt das alte _setup_multimesh
## + _rebuild_multimesh.
func _rebuild_multimesh() -> void:
	# Alten Chunk-Root entfernen
	if _chunk_root and is_instance_valid(_chunk_root):
		_chunk_root.queue_free()
	_chunks.clear()

	if tree_mesh == null:
		return

	_chunk_root = Node3D.new()
	_chunk_root.name = "TreeChunks"
	add_child(_chunk_root)

	# 1. Bäume nach Chunk gruppieren (globale Indizes sammeln)
	var grouping: Dictionary = {}                # chunk_key -> Array[int]
	for i in _tree_data.size():
		var key := _chunk_key_for(_tree_data[i].position)
		if not grouping.has(key):
			grouping[key] = []
		grouping[key].append(i)

	# 2. index_map auf die richtige Größe bringen
	_index_map.clear()
	_index_map.resize(_tree_data.size())

	# 3. Pro Chunk einen MultiMeshInstance3D mit enger AABB bauen
	for key in grouping.keys():
		var indices: Array = grouping[key]
		var cnt := indices.size()
		if cnt == 0:
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = tree_mesh
		mm.instance_count = cnt

		var aabb_min := Vector3(INF, INF, INF)
		var aabb_max := Vector3(-INF, -INF, -INF)

		var entry := ChunkEntry.new()
		entry.indices.resize(cnt)

		for slot in cnt:
			var gi: int = indices[slot]
			var data := _tree_data[gi]

			var t := Transform3D()
			if not data.is_real:
				t = t.rotated(Vector3.UP, data.rotation_y)
				t = t.scaled(Vector3.ONE * data.scale)
				t.origin = data.position
			else:
				t.origin = HIDDEN_TRANSFORM_ORIGIN

			mm.set_instance_transform(slot, t)
			mm.set_instance_color(slot, TreeVariation.instance_color_for(data.position))
			mm.set_instance_custom_data(slot, _variation_custom_for(data.position))

			# Mapping global -> (chunk, slot)
			_index_map[gi] = { "key": key, "slot": slot }
			entry.indices[slot] = gi

			# AABB (Mesh wächst um ~scale; Baumhöhe großzügig einbeziehen)
			var s := data.scale
			var mesh_aabb := tree_mesh.get_aabb()
			var lo := data.position + mesh_aabb.position * s
			var hi := lo + mesh_aabb.size * s
			aabb_min = aabb_min.min(lo)
			aabb_max = aabb_max.max(hi)

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Chunk_%d_%d" % [key.x, key.y]
		mmi.multimesh = mm
		mmi.custom_aabb = AABB(aabb_min, aabb_max - aabb_min)

		if chunk_visible_distance > 0.0:
			mmi.visibility_range_end = chunk_visible_distance
			mmi.visibility_range_end_margin = chunk_fade_margin
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

		_chunk_root.add_child(mmi)
		entry.mmi = mmi
		_chunks[key] = entry

	if not Engine.is_editor_hint():
		print("TreeManager '%s': %d Bäume in %d Chunks" % [name, _tree_data.size(), _chunks.size()])


## Variation custom data (war vorher im _rebuild über use_custom_data=false
## ausgelassen; der pinetree_variation-Shader liest INSTANCE_CUSTOM).
func _variation_custom_for(pos: Vector3) -> Color:
	# Deterministisch aus Position: Hue, Brightness, Saturation, frei.
	var h := hash(Vector2i(int(pos.x * 13.0), int(pos.z * 7.0)))
	var r := float(h & 0xFF) / 255.0
	var g := float((h >> 8) & 0xFF) / 255.0
	var b := float((h >> 16) & 0xFF) / 255.0
	return Color(r, g, b, 0.0)


func _prepare_mesh_materials_for_color() -> void:
	if tree_mesh == null:
		return
	for s in tree_mesh.get_surface_count():
		var mat := tree_mesh.surface_get_material(s)
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).vertex_color_use_as_albedo = false


## Setzt einen einzelnen Baum im MultiMesh sichtbar/unsichtbar — jetzt über
## das (chunk, slot)-Mapping statt globalem Index.
func _update_multimesh_instance(index: int, data: TreeData, visible: bool) -> void:
	if index < 0 or index >= _index_map.size():
		return
	var map = _index_map[index]
	if map == null:
		return
	var entry: ChunkEntry = _chunks.get(map["key"])
	if entry == null or not is_instance_valid(entry.mmi):
		return
	var mm := entry.mmi.multimesh
	var slot: int = map["slot"]
	if slot >= mm.instance_count:
		return

	var t := Transform3D()
	if visible:
		t = t.rotated(Vector3.UP, data.rotation_y)
		t = t.scaled(Vector3.ONE * data.scale)
		t.origin = data.position
	else:
		t.origin = HIDDEN_TRANSFORM_ORIGIN

	mm.set_instance_transform(slot, t)
	mm.set_instance_color(slot, TreeVariation.instance_color_for(data.position))


func _apply_chunk_visibility() -> void:
	if not _chunk_root or not is_instance_valid(_chunk_root):
		return
	for child in _chunk_root.get_children():
		if child is MultiMeshInstance3D:
			if chunk_visible_distance > 0.0:
				child.visibility_range_end = chunk_visible_distance
				child.visibility_range_end_margin = chunk_fade_margin
				child.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			else:
				child.visibility_range_end = 0.0


# ============================================================
#  REAL-TREE LOGIK (unverändert — nur _update_multimesh_instance
#  ist jetzt chunk-aware, der Aufruf bleibt gleich)
# ============================================================

func _update_tree_states() -> void:
	if _player == null:
		return

	var player_pos := _player.global_position
	var spawn_dist_sq := spawn_distance * spawn_distance
	var despawn_dist_sq := (spawn_distance + hysteresis) * (spawn_distance + hysteresis)

	var spawn_candidates: Array[Dictionary] = []
	var real_trees_by_dist: Array[Dictionary] = []

	for i in _tree_data.size():
		var data := _tree_data[i]
		var dist_sq := player_pos.distance_squared_to(data.position)

		if data.is_real:
			real_trees_by_dist.append({"index": i, "dist_sq": dist_sq})
			if dist_sq > despawn_dist_sq:
				if i not in _despawn_queue and i not in _spawn_queue:
					_despawn_queue.append(i)
		else:
			if dist_sq < spawn_dist_sq:
				if i not in _spawn_queue and i not in _despawn_queue:
					spawn_candidates.append({"index": i, "dist_sq": dist_sq})

	spawn_candidates.sort_custom(func(a, b): return a.dist_sq < b.dist_sq)
	real_trees_by_dist.sort_custom(func(a, b): return a.dist_sq > b.dist_sq)

	var available_slots := max_real_trees - _real_trees.size() - _spawn_queue.size() + _despawn_queue.size()

	for candidate in spawn_candidates:
		if available_slots > 0:
			_spawn_queue.append(candidate.index)
			available_slots -= 1
		elif real_trees_by_dist.size() > 0:
			var furthest := real_trees_by_dist[0]
			if candidate.dist_sq < furthest.dist_sq:
				if furthest.index not in _despawn_queue:
					_despawn_queue.append(furthest.index)
					_spawn_queue.append(candidate.index)
					real_trees_by_dist.remove_at(0)


func _process_queues() -> void:
	var spawned := 0
	while _spawn_queue.size() > 0 and spawned < trees_per_frame:
		var index: int = _spawn_queue.pop_front()
		_spawn_real_tree(index)
		spawned += 1

	var despawned := 0
	while _despawn_queue.size() > 0 and despawned < trees_per_frame:
		var index: int = _despawn_queue.pop_front()
		_despawn_real_tree(index)
		despawned += 1


func _spawn_real_tree(index: int) -> void:
	if tree_scene == null:
		return
	var data := _tree_data[index]
	if data.is_real:
		return

	var tree_instance: Node3D
	if _pool.size() > 0:
		tree_instance = _pool.pop_back()
	else:
		tree_instance = tree_scene.instantiate() as Node3D
		add_child(tree_instance)

	tree_instance.position = data.position
	tree_instance.rotation.y = data.rotation_y
	tree_instance.scale = Vector3.ONE * data.scale

	_apply_color_to_real_tree(tree_instance, data.position)

	tree_instance.visible = true
	tree_instance.process_mode = Node.PROCESS_MODE_INHERIT

	_real_trees[index] = tree_instance
	data.is_real = true

	_hide_multimesh_slot_deferred(index, data)


func _hide_multimesh_slot_deferred(index: int, data: TreeData) -> void:
	await get_tree().process_frame
	if data.is_real:
		_update_multimesh_instance(index, data, false)


func _despawn_real_tree(index: int) -> void:
	var data := _tree_data[index]
	if not data.is_real:
		return

	data.is_real = false
	_update_multimesh_instance(index, data, true)

	if _real_trees.has(index):
		var tree_instance: Node3D = _real_trees[index]
		_real_trees.erase(index)
		_hide_real_tree_deferred(tree_instance)


func _hide_real_tree_deferred(tree_instance: Node3D) -> void:
	await get_tree().process_frame
	if is_instance_valid(tree_instance):
		tree_instance.visible = false
		tree_instance.process_mode = Node.PROCESS_MODE_DISABLED
		tree_instance.position = POOL_HIDDEN_POS
		_pool.append(tree_instance)


# ============================================================
#  STATS / LADEN (unverändert)
# ============================================================

func get_stats() -> Dictionary:
	return {
		"total_trees": _tree_data.size(),
		"real_trees": _real_trees.size(),
		"spawn_queue": _spawn_queue.size(),
		"despawn_queue": _despawn_queue.size(),
		"chunks": _chunks.size(),
	}


func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("TreeManager: Datei nicht gefunden: " + path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TreeManager: Konnte Datei nicht öffnen: " + path)
		return false
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK:
		push_error("TreeManager: JSON Parse Error: " + json.get_error_message())
		return false
	var data: Array = json.data
	_tree_data.clear()
	for entry in data:
		var pos := Vector3(entry.x, entry.y, entry.z)
		var rot: float = entry.get("rotation", 0.0)
		var scl: float = entry.get("scale", 1.0)
		add_tree(pos, rot, scl)
	_rebuild_multimesh()
	print("TreeManager: ", _tree_data.size(), " Bäume geladen aus ", path)
	return true


func auto_load() -> bool:
	var scene_name := ""
	if Engine.is_editor_hint():
		var edited_root = get_tree().edited_scene_root
		if edited_root != null:
			scene_name = edited_root.name
	else:
		var scene_root := get_tree().current_scene
		if scene_root != null:
			scene_name = scene_root.name
	if scene_name == "":
		return false
	var path := "res://data/trees/" + scene_name + "_" + name + ".json"
	return load_from_file(path)


func _apply_color_to_real_tree(scene_root: Node3D, pos: Vector3) -> void:
	var tint := TreeVariation.instance_color_for(pos)
	_tint_meshes_recursive(scene_root, tint)


func _tint_meshes_recursive(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if not mi.is_in_group("no_wind"):
			mi.set_instance_shader_parameter("instance_tint", Vector3(tint.r, tint.g, tint.b))
	for child in node.get_children():
		_tint_meshes_recursive(child, tint)

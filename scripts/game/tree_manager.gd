@tool
extends Node3D
class_name TreeManager

## Das TreeManager-System für performante Baumdarstellung
## - Ferne Bäume: MultiMesh (ein Draw Call für tausende Bäume)
## - Nahe Bäume: Echte Szenen mit Occlusion-Support

@export_group("Tree Setup")
## Die Baum-Szene die für nahe Bäume gespawnt wird
@export var tree_scene: PackedScene
## Das Mesh für die MultiMesh-Darstellung (sollte dem Baum ähneln)
@export var tree_mesh: Mesh
## Material für das MultiMesh (optional - sonst wird Mesh-Material genutzt)
@export var tree_material: Material

@export_group("Distances")
## Ab dieser Distanz werden echte Szenen gespawnt (mit Occlusion)
@export var spawn_distance: float = 20.0
## Hysterese um ständiges Spawnen/Despawnen zu vermeiden
@export var hysteresis: float = 5.0
## Wie oft pro Sekunde die Distanzen geprüft werden
@export var update_interval: float = 0.2

@export_group("Performance")
## Maximale Anzahl echter Baum-Szenen gleichzeitig
@export var max_real_trees: int = 50
## Bäume pro Frame spawnen/despawnen (um Lag-Spikes zu vermeiden)
@export var trees_per_frame: int = 3

var _pool: Array[Node3D] = []
@export var pool_warmup: int = 30

# Interne Daten
var _tree_data: Array[TreeData] = []  # Alle Baumpositionen
var _multimesh_instance: MultiMeshInstance3D
var _real_trees: Dictionary = {}  # index -> Node3D
var _player: Node3D
var _update_timer: float = 0.0

# Queues für graduelles Spawnen/Despawnen
var _spawn_queue: Array[int] = []
var _despawn_queue: Array[int] = []

const POOL_HIDDEN_POS := Vector3(0.0, -100000.0, 0.0)

class TreeData:
	var position: Vector3
	var rotation_y: float
	var scale: float
	var is_real: bool = false  # true wenn echte Szene aktiv
	
	func _init(pos: Vector3, rot: float = 0.0, scl: float = 1.0) -> void:
		position = pos
		rotation_y = rot
		scale = scl


func _ready() -> void:
	_setup_multimesh()
	auto_load()
	
	
	if not Engine.is_editor_hint() and tree_scene != null:
		for i in pool_warmup:
			var t := tree_scene.instantiate() as Node3D
			add_child(t)
			t.position = POOL_HIDDEN_POS
			t.visible = false
			t.process_mode = Node.PROCESS_MODE_DISABLED
			_pool.append(t)
	
	# Im Editor nicht nach Spieler suchen
	if Engine.is_editor_hint():
		return
	
	# Spieler finden
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")



func _process(delta: float) -> void:
	# Im Editor nichts tun
	if Engine.is_editor_hint():
		return
	
	# Spawn/Despawn Queue abarbeiten
	_process_queues()
	
	# Distanz-Check mit Interval
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_update_tree_states()


## Fügt einen Baum hinzu (Position, Y-Rotation in Grad, Skalierung)
func add_tree(position: Vector3, rotation_deg: float = 0.0, scale: float = 1.0) -> void:
	var data := TreeData.new(position, deg_to_rad(rotation_deg), scale)
	_tree_data.append(data)


## Fügt mehrere Bäume auf einmal hinzu (effizienter)
func add_trees(trees: Array) -> void:
	for tree in trees:
		if tree is Dictionary:
			var pos: Vector3 = tree.get("position", Vector3.ZERO)
			var rot: float = tree.get("rotation", randf() * 360.0)
			var scl: float = tree.get("scale", randf_range(0.8, 1.2))
			add_tree(pos, rot, scl)
		elif tree is Vector3:
			add_tree(tree, randf() * 360.0, randf_range(0.8, 1.2))


## Generiert Bäume zufällig in einem Bereich
func generate_random_trees(count: int, area_min: Vector3, area_max: Vector3, terrain: Node3D = null) -> void:
	for i in count:
		var x := randf_range(area_min.x, area_max.x)
		var z := randf_range(area_min.z, area_max.z)
		var y := area_min.y
		
		# Optional: Y-Position vom Terrain holen
		if terrain and terrain.has_method("get_height"):
			y = terrain.call("get_height", Vector3(x, 0, z))
		
		add_tree(Vector3(x, y, z), randf() * 360.0, randf_range(0.8, 1.2))
	
	# MultiMesh aktualisieren nach Batch-Add
	_rebuild_multimesh()


## Muss aufgerufen werden nachdem alle Bäume hinzugefügt wurden
func finalize() -> void:
	_rebuild_multimesh()
	print("TreeManager: ", _tree_data.size(), " Bäume initialisiert")


func _setup_multimesh() -> void:
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.name = "TreeMultiMesh"
	add_child(_multimesh_instance)
	
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = false
	
	if tree_mesh:
		mm.mesh = tree_mesh
	
	_multimesh_instance.multimesh = mm
	
	if tree_material:
		_multimesh_instance.material_override = tree_material


func _rebuild_multimesh() -> void:
	if _multimesh_instance == null or _multimesh_instance.multimesh == null:
		return
	
	var mm := _multimesh_instance.multimesh
	mm.instance_count = _tree_data.size()
	
	for i in _tree_data.size():
		var data := _tree_data[i]
		_update_multimesh_instance(i, data, not data.is_real)


func _update_multimesh_instance(index: int, data: TreeData, visible: bool) -> void:
	var mm := _multimesh_instance.multimesh
	if index >= mm.instance_count:
		return
	
	var transform := Transform3D()
	
	if visible:
		transform = transform.rotated(Vector3.UP, data.rotation_y)
		transform = transform.scaled(Vector3.ONE * data.scale)
		transform.origin = data.position
	else:
		# Unsichtbar: Skalierung auf 0 oder weit weg verschieben
		transform.origin = Vector3(0, -10000, 0)
	
	mm.set_instance_transform(index, transform)


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
			# Normale Despawn-Logik
			if dist_sq > despawn_dist_sq:
				if i not in _despawn_queue and i not in _spawn_queue:
					_despawn_queue.append(i)
		else:
			if dist_sq < spawn_dist_sq:
				if i not in _spawn_queue and i not in _despawn_queue:
					spawn_candidates.append({"index": i, "dist_sq": dist_sq})
	
	# Sortiere: Spawn-Kandidaten nach Nähe, echte Bäume nach Entfernung
	spawn_candidates.sort_custom(func(a, b): return a.dist_sq < b.dist_sq)
	real_trees_by_dist.sort_custom(func(a, b): return a.dist_sq > b.dist_sq)  # Entfernteste zuerst
	
	# Wenn ein Spawn-Kandidat näher ist als der entfernteste echte Baum: tauschen!
	var available_slots := max_real_trees - _real_trees.size() - _spawn_queue.size() + _despawn_queue.size()
	
	for candidate in spawn_candidates:
		if available_slots > 0:
			_spawn_queue.append(candidate.index)
			available_slots -= 1
		elif real_trees_by_dist.size() > 0:
			# Prüfe ob Kandidat näher ist als entferntester echter Baum
			var furthest := real_trees_by_dist[0]
			if candidate.dist_sq < furthest.dist_sq:
				# Tausche: Despawne den entfernten, spawne den nahen
				if furthest.index not in _despawn_queue:
					_despawn_queue.append(furthest.index)
					_spawn_queue.append(candidate.index)
					real_trees_by_dist.remove_at(0)


func _process_queues() -> void:
	# Spawnen
	var spawned := 0
	while _spawn_queue.size() > 0 and spawned < trees_per_frame:
		var index: int = _spawn_queue.pop_front()
		_spawn_real_tree(index)
		spawned += 1
	
	# Despawnen
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

	# 1) Transform zuerst — der Baum sitzt bereits am Zielort,
	#    bevor er für den Renderer auftaucht
	tree_instance.position = data.position
	tree_instance.rotation.y = data.rotation_y
	tree_instance.scale = Vector3.ONE * data.scale

	# 2) Dann erst Visibility + Process aktivieren
	tree_instance.visible = true
	tree_instance.process_mode = Node.PROCESS_MODE_INHERIT

	_real_trees[index] = tree_instance
	data.is_real = true
	_update_multimesh_instance(index, data, false)


func _despawn_real_tree(index: int) -> void:
	var data := _tree_data[index]
	if not data.is_real:
		return  # Bereits despawnt
	
	# Echte Szene entfernen
	if _real_trees.has(index):
		var tree_instance: Node3D = _real_trees[index]
		if is_instance_valid(tree_instance):
			tree_instance.visible = false
			tree_instance.process_mode = Node.PROCESS_MODE_DISABLED
			tree_instance.position = POOL_HIDDEN_POS
			_pool.append(tree_instance)
		_real_trees.erase(index)
	
	data.is_real = false
	_update_multimesh_instance(index, data, true)


## Debug: Zeigt Statistiken
func get_stats() -> Dictionary:
	return {
		"total_trees": _tree_data.size(),
		"real_trees": _real_trees.size(),
		"spawn_queue": _spawn_queue.size(),
		"despawn_queue": _despawn_queue.size()
	}


## Lädt Bäume aus einer JSON-Datei (vom Tree Painter gespeichert)
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


## Automatisches Laden beim Start (sucht nach passender JSON-Datei)
func auto_load() -> bool:
	var scene_name := ""
	
	# Im Editor: edited_scene_root verwenden
	if Engine.is_editor_hint():
		var edited_root = get_tree().edited_scene_root
		if edited_root != null:
			scene_name = edited_root.name
	else:
		# Im Spiel: current_scene verwenden
		var scene_root := get_tree().current_scene
		if scene_root != null:
			scene_name = scene_root.name
	
	if scene_name == "":
		return false
	
	# Node-Name für separate Dateien pro TreeManager
	var path := "res://data/trees/" + scene_name + "_" + name + ".json"
	return load_from_file(path)

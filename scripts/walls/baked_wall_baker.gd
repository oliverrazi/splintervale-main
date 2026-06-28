@tool
class_name BakedWallBaker
extends Node3D

## EDITOR-TOOL. Generischer Batcher fuer statische Wand-/Prop-Verkleidung.
## Ein System, viele Bakes: pro Bereich (Wasserfall, Hoehle, ...) ein eigener
## Baker-Node mit eigenen Modellen und eigener Output-.tres.
##
## Platziere darunter MeshInstance3D-Nodes (frei rotiert/skaliert). Beim Bake
## werden sie nach Mesh-Ressource gruppiert -> ein MultiMesh + eine gecookte
## Collision-Shape pro Modell. Editor-Nodes bleiben unangetastet.
##
## Sichtbarkeit/Streaming macht dieses Tool NICHT. -> BakedWallRuntime + dein
## bestehendes Zone-System.

enum ColliderType { CONVEX, TRIMESH }

# --- Inspector: Aktionen ---

## Scannt die Kinder und befuellt collider_types mit allen gefundenen Modellen
## (Default Convex), ohne zu baken. Erst aufrufen, dann pro Modell Trimesh waehlen.
@export var discover_models: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_discover_models()
		discover_models = false

## Loest den Bake aus.
@export var bake: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_bake()
		bake = false

@export var output_path: String = "res://data/wall_bakes/baked_walls.tres"

@export_group("Collider Per Model")
## Mesh-Dateipfad -> ColliderType. Per discover_models befuellen,
## dann konkave Modelle auf Trimesh stellen. Zuordnung haengt am Pfad,
## bleibt also ueber Re-Bakes stabil.
@export var collider_types: Dictionary = {}
## Wenn aus: keine Collision erzeugt (nur sichtbare Geometrie).
@export var generate_collision: bool = true

@export_group("Color Variation")
@export var enable_color_variation: bool = true
@export_range(0.0, 0.5, 0.01) var brightness_jitter: float = 0.12
@export_range(0.0, 0.2, 0.005) var hue_jitter: float = 0.02
@export_range(0.0, 0.5, 0.01) var saturation_jitter: float = 0.06
@export var color_seed: int = 1337


func _discover_models() -> void:
	var sources := _collect_wall_instances()
	if sources.is_empty():
		push_warning("BakedWallBaker: keine MeshInstance3D mit Mesh unter '%s'." % name)
		return
	var found := 0
	for mi in sources:
		var path := _mesh_key(mi.mesh)
		if path == "":
			push_warning("BakedWallBaker: Mesh ohne stabilen Pfad (built-in?) bei '%s' - Trimesh/Convex-Zuordnung instabil." % mi.name)
			continue
		if not collider_types.has(path):
			collider_types[path] = ColliderType.CONVEX
			found += 1
	notify_property_list_changed()
	print("BakedWallBaker: %d neue Modelle entdeckt. collider_types hat jetzt %d Eintraege." % [found, collider_types.size()])


func _bake() -> void:
	var sources := _collect_wall_instances()
	if sources.is_empty():
		push_warning("BakedWallBaker: keine MeshInstance3D mit Mesh unter '%s'." % name)
		return

	# Nach Mesh gruppieren.
	var buckets: Dictionary = {}   # Mesh -> Array[MeshInstance3D]
	for mi in sources:
		var mesh: Mesh = mi.mesh
		if not buckets.has(mesh):
			buckets[mesh] = []
		buckets[mesh].append(mi)

	var rng := RandomNumberGenerator.new()
	rng.seed = color_seed

	var data := BakedWallData.new()

	for mesh in buckets.keys():
		var instances: Array = buckets[mesh]
		var group := _bake_group(mesh, instances, rng)
		data.groups.append(group)

	_ensure_dir(output_path)
	var err := ResourceSaver.save(data, output_path)
	if err != OK:
		push_error("BakedWallBaker: Speichern fehlgeschlagen (%d) -> %s" % [err, output_path])
		return

	print("BakedWallBaker: %d Modell-Gruppen gebaked -> %s" % [data.groups.size(), output_path])
	print("  Draw Calls (min, 1 Surface/Modell): %d  |  Instanzen gesamt: %d" % [
		data.groups.size(), sources.size()
	])


func _bake_group(mesh: Mesh, instances: Array, rng: RandomNumberGenerator) -> BakedWallGroup:
	var group := BakedWallGroup.new()
	group.source_mesh_path = _mesh_key(mesh)

	# --- MultiMesh ---
	# WICHTIG: frische MultiMesh, use_colors VOR instance_count.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = enable_color_variation
	mm.mesh = mesh
	mm.instance_count = instances.size()

	var baker_inv := global_transform.affine_inverse()

	for i in instances.size():
		var mi: MeshInstance3D = instances[i]
		var local_xform := baker_inv * mi.global_transform
		mm.set_instance_transform(i, local_xform)
		if enable_color_variation:
			mm.set_instance_color(i, _jittered_color(rng))
		group.transforms.append(local_xform)

	group.multimesh = mm

	# --- Collision: Typ pro Modell, Cook beim Bake ---
	if generate_collision:
		group.collision_shape = _cook_shape(mesh)

	return group


func _cook_shape(mesh: Mesh) -> Shape3D:
	var path := _mesh_key(mesh)
	var ctype: int = collider_types.get(path, ColliderType.CONVEX)
	if ctype == ColliderType.TRIMESH:
		var tri := mesh.create_trimesh_shape()  # ConcavePolygonShape3D, gecookt
		if tri == null:
			push_warning("BakedWallBaker: Trimesh-Cook fehlgeschlagen fuer %s, fallback Convex." % path)
			return mesh.create_convex_shape(true, true)
		return tri
	else:
		var cvx := mesh.create_convex_shape(true, true)  # clean, simplify
		if cvx == null:
			push_warning("BakedWallBaker: Convex-Cook fehlgeschlagen fuer %s." % path)
		return cvx


func _jittered_color(rng: RandomNumberGenerator) -> Color:
	var h := wrapf(rng.randf_range(-hue_jitter, hue_jitter), 0.0, 1.0)
	var s := clampf(rng.randf_range(-saturation_jitter, saturation_jitter), 0.0, 1.0)
	var v := clampf(1.0 + rng.randf_range(-brightness_jitter, brightness_jitter), 0.0, 1.0)
	return Color.from_hsv(h, s, v)


func _collect_wall_instances() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in get_children():
		if child is MeshInstance3D and child.mesh != null:
			result.append(child)
	return result


func _mesh_key(mesh: Mesh) -> String:
	# Stabiler Schluessel = Ressourcen-Pfad. Built-in/eingebettete Meshes ohne
	# Pfad liefern "" -> Aufrufer warnt.
	if mesh == null:
		return ""
	return mesh.resource_path


func _ensure_dir(path: String) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

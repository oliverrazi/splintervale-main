@tool
class_name BakedPropBaker
extends Node3D

## EDITOR-TOOL. Generischer Batcher fuer statische, hand-platzierte Props
## (Waende, Farne, Felsen, Faesser, ...).
## Ein System, viele Bakes: pro Bereich/Art ein eigener Baker-Node mit eigenen
## Modellen und eigener Output-.tres.
##
## Platziere darunter MeshInstance3D-Nodes (frei rotiert/skaliert). Beim Bake
## werden sie nach Mesh-Ressource gruppiert -> ein MultiMesh + (optional) eine
## gecookte Collision-Shape + das eingefrorene Material pro Modell.
## Editor-Nodes bleiben unangetastet.
##
## v2: Material-Transfer. Das Surface-Override-/Instanz-Material der Quell-
##     MeshInstance3D wird pro Gruppe abgegriffen und gespeichert, sonst waeren
##     gebakte MultiMeshes materiallos (weiss).
##
## Sichtbarkeit/Streaming macht dieses Tool NICHT. -> BakedPropRuntime + dein
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

@export var output_path: String = "res://data/prop_bakes/baked_props.tres"

@export_group("Collider Per Model")
## Mesh-Dateipfad -> ColliderType. Per discover_models befuellen,
## dann konkave Modelle auf Trimesh stellen. Zuordnung haengt am Pfad,
## bleibt also ueber Re-Bakes stabil. Ignoriert wenn generate_collision aus.
@export var collider_types: Dictionary = {}
## Wenn aus: keine Collision erzeugt (z.B. fuer Farne/Vegetation).
@export var generate_collision: bool = true

@export_group("Color Variation")
@export var enable_color_variation: bool = true
@export_range(0.0, 0.5, 0.01) var brightness_jitter: float = 0.12
@export_range(0.0, 0.2, 0.005) var hue_jitter: float = 0.02
@export_range(0.0, 0.5, 0.01) var saturation_jitter: float = 0.06
@export var color_seed: int = 1337


func _discover_models() -> void:
	var sources := _collect_instances()
	if sources.is_empty():
		push_warning("BakedPropBaker: keine MeshInstance3D mit Mesh unter '%s'." % name)
		return
	var found := 0
	for mi in sources:
		var path := _mesh_key(mi.mesh)
		if path == "":
			push_warning("BakedPropBaker: Mesh ohne stabilen Pfad (built-in?) bei '%s' - Trimesh/Convex-Zuordnung instabil." % mi.name)
			continue
		if not collider_types.has(path):
			collider_types[path] = ColliderType.CONVEX
			found += 1
	notify_property_list_changed()
	print("BakedPropBaker: %d neue Modelle entdeckt. collider_types hat jetzt %d Eintraege." % [found, collider_types.size()])


func _bake() -> void:
	var sources := _collect_instances()
	if sources.is_empty():
		push_warning("BakedPropBaker: keine MeshInstance3D mit Mesh unter '%s'." % name)
		return

	# Gruppierung nach Mesh UND Material.
	# Ein MultiMesh hat GENAU EIN Material fuer alle Instanzen. Instanzen mit
	# gleichem Mesh, aber unterschiedlichem Material (eigenes Override vs. geerbt)
	# muessen daher in getrennte MultiMeshes - sonst erbt die ganze Gruppe das
	# Material der ersten Instanz, und Objekte mit abweichendem Material rendern
	# falsch. Der Bucket-Key kombiniert Mesh und effektives Material.
	var buckets: Dictionary = {}   # key -> Array[MeshInstance3D]
	var bucket_meshes: Dictionary = {}  # key -> Mesh (fuer den Bake-Aufruf)
	for mi in sources:
		var mesh: Mesh = mi.mesh
		var mat := _extract_material(mi)
		var key := [mesh, mat]  # Array als zusammengesetzter Dictionary-Key
		if not buckets.has(key):
			buckets[key] = []
			bucket_meshes[key] = mesh
		buckets[key].append(mi)

	var rng := RandomNumberGenerator.new()
	rng.seed = color_seed

	var data := BakedPropData.new()

	for key in buckets.keys():
		var instances: Array = buckets[key]
		var mesh: Mesh = bucket_meshes[key]
		var group := _bake_group(mesh, instances, rng)
		data.groups.append(group)

	_ensure_dir(output_path)
	var err := ResourceSaver.save(data, output_path)
	if err != OK:
		push_error("BakedPropBaker: Speichern fehlgeschlagen (%d) -> %s" % [err, output_path])
		return

	print("BakedPropBaker: %d Modell-Gruppen gebaked -> %s" % [data.groups.size(), output_path])
	print("  Draw Calls (min, 1 Surface/Modell): %d  |  Instanzen gesamt: %d" % [
		data.groups.size(), sources.size()
	])


func _bake_group(mesh: Mesh, instances: Array, rng: RandomNumberGenerator) -> BakedPropGroup:
	var group := BakedPropGroup.new()
	group.source_mesh_path = _mesh_key(mesh)

	# --- Material einfrieren ---
	# MultiMeshInstance3D rendert NICHT die Per-Instance-Overrides der Quell-
	# Nodes. Ohne diesen Transfer waeren gebakte Props materiallos (weiss).
	# Prioritaet: material_override > Surface-Override[0] > Mesh-Surface-Material.
	# Wenn das Mesh sein Material selbst traegt und kein Override existiert,
	# bleibt material == null und das MMI rendert korrekt aus dem Mesh.
	group.material = _extract_material(instances[0] as MeshInstance3D)
	if group.material == null and _mesh_has_no_material(mesh):
		push_warning(
			"BakedPropBaker: Modell '%s' hat weder Override noch Mesh-Material - MMI bleibt weiss."
			% group.source_mesh_path)

	# --- MultiMesh ---
	# WICHTIG: frische MultiMesh, use_colors VOR instance_count.
	#
	# KRITISCH fuer Vertex-Color-Shader (z.B. der Wand-Shader mit COLOR-Maske):
	# MultiMesh-Instanz-Farben und Mesh-Vertex-Farben teilen sich denselben
	# COLOR-Input im Shader. Ist use_colors=false, ist COLOR im Shader NICHT
	# die Mesh-Vertex-Farbe, sondern undefiniert (oft schwarz) -> Masken-Logik
	# wie "1.0 - min(COLOR.g, COLOR.b)" kippt auf 1.0 -> Gras ueberall.
	# Ist use_colors=true mit Instanz-Farbe, wird die Vertex-Farbe MULTIPLIZIERT
	# und die Maske ebenfalls verfaelscht.
	# Loesung: Bei aktiver Variation Instanz-Farbe setzen (fuer Shader, die COLOR
	# als Tint nutzen). Bei INAKTIVER Variation trotzdem use_colors=true und
	# pro Instanz WEISS setzen -> COLOR ist garantiert (1,1,1), die Maske liest
	# "unbemalt" korrekt UND der Multiplikator ist neutral (Vertex-Farbe bleibt).
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true  # IMMER an: garantiert definiertes COLOR im Shader.
	mm.mesh = mesh
	mm.instance_count = instances.size()

	var baker_inv := global_transform.affine_inverse()

	for i in instances.size():
		var mi: MeshInstance3D = instances[i]
		var local_xform := baker_inv * mi.global_transform
		mm.set_instance_transform(i, local_xform)
		if enable_color_variation:
			mm.set_instance_color(i, _jittered_color(rng))
		else:
			mm.set_instance_color(i, Color.WHITE)  # neutral, Vertex-Farbe bleibt
		group.transforms.append(local_xform)

	group.multimesh = mm

	# --- Collision: Typ pro Modell, Cook beim Bake ---
	if generate_collision:
		group.collision_shape = _cook_shape(mesh)

	return group


## Greift das effektive Material einer Quell-Instanz ab.
## Reihenfolge entspricht der Godot-Renderprioritaet.
func _extract_material(mi: MeshInstance3D) -> Material:
	if mi == null:
		return null
	# 1) Node-weiter Override (hoechste Prioritaet beim Rendern).
	if mi.material_override != null:
		return mi.material_override
	# 2) Surface-Override an der Instanz (dein Cliff-Material sitzt hier).
	for s in mi.get_surface_override_material_count():
		var m := mi.get_surface_override_material(s)
		if m != null:
			return m
	# 3) Material direkt im Mesh (Surface 0).
	if mi.mesh != null and mi.mesh.get_surface_count() > 0:
		return mi.mesh.surface_get_material(0)
	return null


func _mesh_has_no_material(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return true
	return mesh.surface_get_material(0) == null


func _cook_shape(mesh: Mesh) -> Shape3D:
	var path := _mesh_key(mesh)
	var ctype: int = collider_types.get(path, ColliderType.CONVEX)
	if ctype == ColliderType.TRIMESH:
		var tri := mesh.create_trimesh_shape()  # ConcavePolygonShape3D, gecookt
		if tri == null:
			push_warning("BakedPropBaker: Trimesh-Cook fehlgeschlagen fuer %s, fallback Convex." % path)
			return mesh.create_convex_shape(true, true)
		return tri
	else:
		var cvx := mesh.create_convex_shape(true, true)  # clean, simplify
		if cvx == null:
			push_warning("BakedPropBaker: Convex-Cook fehlgeschlagen fuer %s." % path)
		return cvx


func _jittered_color(rng: RandomNumberGenerator) -> Color:
	var h := wrapf(rng.randf_range(-hue_jitter, hue_jitter), 0.0, 1.0)
	var s := clampf(rng.randf_range(-saturation_jitter, saturation_jitter), 0.0, 1.0)
	var v := clampf(1.0 + rng.randf_range(-brightness_jitter, brightness_jitter), 0.0, 1.0)
	return Color.from_hsv(h, s, v)


func _collect_instances() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_recursive(self, result)
	return result


func _collect_recursive(node: Node, result: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			result.append(child)
		# Rekursiv in Node3D-Gruppen absteigen (deine Ordner-Struktur).
		if child.get_child_count() > 0:
			_collect_recursive(child, result)
	return


func _mesh_key(mesh: Mesh) -> String:
	if mesh == null:
		return ""
	return mesh.resource_path


func _ensure_dir(path: String) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

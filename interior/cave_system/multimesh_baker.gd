@tool
class_name MultiMeshBaker
extends Node3D
## ═══════════════════════════════════════════════════════════════
## MultiMeshBaker — Manuell platzierte Meshes → MultiMesh
## ═══════════════════════════════════════════════════════════════
## WORKFLOW:
##   1. Platziere MeshInstance3D-Kinder ganz normal im Editor
##   2. Positioniere, rotiere, skaliere frei
##   3. Im Spiel: bake() konvertiert alles zu MultiMeshes
##
## Ergebnis: Statt 300 Draw Calls → 1 pro Mesh-Variante
## ═══════════════════════════════════════════════════════════════

## Automatisch beim Spielstart baken?
@export var bake_on_ready: bool = true

## Original-Nodes nach dem Baken verstecken?
@export var hide_originals: bool = true

## Im Editor baken (für Preview)?
@export var bake_in_editor: bool = false: set = _set_bake_in_editor

var _baked_nodes: Array[Node] = []


func _ready() -> void:
	if not Engine.is_editor_hint() and bake_on_ready:
		# Ein Frame warten damit alle Kinder geladen sind
		await get_tree().process_frame
		bake()


func bake() -> void:
	# Alte Bakes entfernen
	_clear_baked()

	# Alle MeshInstance3D-Kinder sammeln
	var mesh_map: Dictionary = {}  # Mesh-Resource → Array[Transform3D]
	var material_map: Dictionary = {}  # Mesh-Resource → Material

	for child in get_children():
		if not child is MeshInstance3D:
			continue
		var mi := child as MeshInstance3D
		if not mi.mesh:
			continue

		# Mesh als Key (gleiche Mesh-Resource = gleicher MultiMesh)
		var mesh_key := mi.mesh
		if not mesh_map.has(mesh_key):
			mesh_map[mesh_key] = []
			material_map[mesh_key] = mi.material_override

		# Transform relativ zu diesem Node
		mesh_map[mesh_key].append(mi.transform)

		# Original verstecken
		if hide_originals:
			mi.visible = false

	# Pro Mesh-Typ ein MultiMesh erzeugen
	var idx := 0
	for mesh_key in mesh_map:
		var transforms: Array = mesh_map[mesh_key]
		if transforms.is_empty():
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh_key
		mm.instance_count = transforms.size()

		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Baked_%d" % idx
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		if material_map[mesh_key]:
			mmi.material_override = material_map[mesh_key]

		add_child(mmi)
		_baked_nodes.append(mmi)
		idx += 1

	print("MultiMeshBaker: %d Mesh-Typen → %d Draw Calls (vorher: %d)" % [
		idx, idx, mesh_map.values().reduce(func(a, b): return a + b.size(), 0)
	])


func unbake() -> void:
	_clear_baked()
	# Originale wieder sichtbar
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = true


func _clear_baked() -> void:
	for node in _baked_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_baked_nodes.clear()
	for child in get_children():
		if child is MultiMeshInstance3D:
			child.queue_free()


func _set_bake_in_editor(v: bool) -> void:
	bake_in_editor = v
	if v and Engine.is_editor_hint():
		bake()
	elif not v and Engine.is_editor_hint():
		unbake()

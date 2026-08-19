@tool
class_name BakedPropRuntime
extends Node3D
## RUNTIME-Node fuer eine gebakte Prop-Gruppe (Waende, Farne, Felsen, ...).
## Pro Modell: ein MultiMeshInstance3D (1 Draw Call/Surface) + optional
## CollisionShape3Ds (geteilte, vorgekochte Shape) unter EINEM StaticBody3D.
##
## Entkoppelt vom Streaming. Dein Zone-/Trigger-System ruft set_active(bool).
## Startet standardmaessig inaktiv (unsichtbar, Collision aus).
##
## v2-Fixes:
##  - Material aus BakedPropGroup wird als material_override aufs MMI gesetzt
##    (sonst rendern gebakte MultiMeshes weiss).
##  - Erzeugte Kinder bekommen NIE owner -> landen nie in der Szenendatei.
##    Zusaetzlich Purge beim _ready fuer Altlasten aus frueheren Sessions.
##  - Optional: erzwingt beim _ready das Ausblenden eines Source-Geschwister-
##    Nodes, damit Source-Meshes und Bake nie gleichzeitig rendern (Z-Fight).

@export var bake_data: BakedPropData:
	set(value):
		bake_data = value
		if is_inside_tree() and not Engine.is_editor_hint():
			_rebuild()

@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1
@export var active_on_ready: bool = false

## Optional. NodePath auf den zugehoerigen BakedPropBaker (die Source-Meshes).
## Wird im Spiel beim _ready zwangsweise ausgeblendet, damit nie Source + Bake
## gleichzeitig rendern. Leer lassen, wenn du die Source manuell verwaltest.
@export var source_to_hide: Node3D

var _multimesh_nodes: Array[MultiMeshInstance3D] = []
var _static_body: StaticBody3D
var _active: bool = false


func _ready() -> void:
	_purge_saved_children()
	_hide_source()
	_rebuild()
	set_active(active_on_ready)


## Entfernt Nodes, die faelschlich aus einer frueheren Session in die Szene
## gespeichert wurden. Runtime-Geometrie gehoert NIE in die Szenendatei.
func _purge_saved_children() -> void:
	for child in get_children():
		if child is MultiMeshInstance3D or child is StaticBody3D:
			remove_child(child)
			child.queue_free()


## Blendet den zugehoerigen Source-Baker im Spiel aus. Verhindert, dass die
## editierbaren Quell-Meshes zusammen mit dem Bake rendern (Doppel-Darstellung
## und Z-Fighting). Nur zur Laufzeit, damit du im Editor weiter authoren kannst.
func _hide_source() -> void:
	if Engine.is_editor_hint():
		return
	if source_to_hide != null:
		source_to_hide.visible = false


func _rebuild() -> void:
	if Engine.is_editor_hint():
		return
	for n in _multimesh_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_multimesh_nodes.clear()

	if is_instance_valid(_static_body):
		_static_body.queue_free()
		_static_body = null

	if bake_data == null or bake_data.groups.is_empty():
		return

	# StaticBody nur anlegen, wenn ueberhaupt eine Gruppe Collision hat.
	var needs_body := false
	for group in bake_data.groups:
		if group.collision_shape != null:
			needs_body = true
			break

	if needs_body:
		_static_body = StaticBody3D.new()
		_static_body.name = "PropCollision"
		_static_body.collision_layer = collision_layer
		_static_body.collision_mask = collision_mask
		# INTERNAL_MODE_BACK: taucht nicht im Szene-Dock auf, wird nie gespeichert.
		add_child(_static_body, false, Node.INTERNAL_MODE_BACK)

	for gi in bake_data.groups.size():
		var group: BakedPropGroup = bake_data.groups[gi]
		if group.multimesh == null:
			continue

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "PropMesh_%d" % gi
		mmi.multimesh = group.multimesh
		# Material aus dem Bake anwenden. Ohne das: weisses MultiMesh.
		if group.material != null:
			mmi.material_override = group.material
		add_child(mmi, false, Node.INTERNAL_MODE_BACK)
		_multimesh_nodes.append(mmi)

		if group.collision_shape != null and _static_body != null:
			for xform in group.transforms:
				var cs := CollisionShape3D.new()
				cs.shape = group.collision_shape  # geteilte Referenz
				cs.transform = xform
				_static_body.add_child(cs, false, Node.INTERNAL_MODE_BACK)

	_apply_active_state()


## Einzige Streaming-Schnittstelle. Vom Zone-Trigger aufrufen.
func set_active(value: bool) -> void:
	_active = value
	_apply_active_state()


func is_active() -> bool:
	return _active


func _apply_active_state() -> void:
	visible = _active
	if is_instance_valid(_static_body):
		_static_body.process_mode = (
			Node.PROCESS_MODE_INHERIT if _active else Node.PROCESS_MODE_DISABLED
		)
		for cs in _static_body.get_children():
			if cs is CollisionShape3D:
				cs.disabled = not _active

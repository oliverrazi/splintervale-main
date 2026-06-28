@tool
class_name BakedPropRuntime
extends Node3D

## RUNTIME-Node fuer eine gebakte Prop-Gruppe (Waende, Farne, Felsen, ...).
## Pro Modell: ein MultiMeshInstance3D (1 Draw Call/Surface) + optional
## CollisionShape3Ds (geteilte, vorgekochte Shape) unter EINEM StaticBody3D.
##
## Entkoppelt vom Streaming. Dein Zone-/Trigger-System ruft set_active(bool).
## Startet standardmaessig inaktiv (unsichtbar, Collision aus).

@export var bake_data: BakedPropData:
	set(value):
		bake_data = value
		if is_inside_tree():
			_rebuild()

@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

@export var active_on_ready: bool = false

var _multimesh_nodes: Array[MultiMeshInstance3D] = []
var _static_body: StaticBody3D
var _active: bool = false


func _ready() -> void:
	_rebuild()
	set_active(active_on_ready)


func _rebuild() -> void:
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
		add_child(_static_body)
		if Engine.is_editor_hint():
			_static_body.owner = self

	for gi in bake_data.groups.size():
		var group: BakedPropGroup = bake_data.groups[gi]
		if group.multimesh == null:
			continue

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "PropMesh_%d" % gi
		mmi.multimesh = group.multimesh
		add_child(mmi)
		if Engine.is_editor_hint():
			mmi.owner = self
		_multimesh_nodes.append(mmi)

		if group.collision_shape != null and _static_body != null:
			for xform in group.transforms:
				var cs := CollisionShape3D.new()
				cs.shape = group.collision_shape  # geteilte Referenz
				cs.transform = xform
				_static_body.add_child(cs)
				if Engine.is_editor_hint():
					cs.owner = self

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

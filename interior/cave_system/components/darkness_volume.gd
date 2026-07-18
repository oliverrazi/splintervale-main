@tool
class_name DarknessVolume
extends Node3D
## Autorierbare Dunkelheits-Box. Im Editor platzieren, ziehen, rotieren.
## Rendert selbst nichts - wird vom DarknessRenderer der Szene eingesammelt.
## WICHTIG: Groesse ueber 'size' einstellen, nicht ueber Node-Scale
## (Scale wird zwar verrechnet, aber size haelt das Gizmo sauber).

const PREVIEW_NAME := "__darkness_preview"

@export var size: Vector3 = Vector3(10.0, 8.0, 10.0):
	set(value):
		size = value.max(Vector3(0.1, 0.1, 0.1))
		_update_preview()

## Breite des Uebergangs von "voll sichtbar" zu "voll dunkel", in Metern.
## Der Falloff liegt INNERHALB der Box: Aussenkante = Beginn der Dunkelheit.
@export var edge_softness: float = 3.0:
	set(value):
		edge_softness = maxf(value, 0.01)

var _preview: MeshInstance3D = null


func _enter_tree() -> void:
	add_to_group("darkness_volumes")
	if Engine.is_editor_hint():
		set_notify_transform(true)
		_build_preview()


func _exit_tree() -> void:
	remove_from_group("darkness_volumes")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		# Renderer aktualisiert im Editor ohnehin pro Frame - nichts zu tun.
		pass


## Liefert die Shader-Daten dieses Volumes.
## Achsen sind orthonormalisiert, Node-Scale wird in die Extents gefaltet.
func get_volume_data() -> Dictionary:
	var gt := global_transform
	var basis_ortho := gt.basis.orthonormalized()
	var node_scale := gt.basis.get_scale()
	return {
		"pos": gt.origin,
		"axis_x": basis_ortho.x,
		"axis_y": basis_ortho.y,
		"axis_z": basis_ortho.z,
		"extents": size * 0.5 * node_scale,
		"softness": edge_softness,
	}


# --- Editor-Preview (niemals owner setzen -> wird nie mitgespeichert) ---

func _build_preview() -> void:
	# Alte generierte Kinder per Namens-Praefix aufraeumen
	for child in get_children():
		if child.name.begins_with(PREVIEW_NAME):
			child.queue_free()

	_preview = MeshInstance3D.new()
	_preview.name = PREVIEW_NAME
	var box := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.05, 0.1, 0.35, 0.25)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat
	_preview.mesh = box
	add_child(_preview)  # KEIN owner-Assignment!
	_update_preview()


func _update_preview() -> void:
	if _preview and is_instance_valid(_preview):
		(_preview.mesh as BoxMesh).size = size

extends Node3D
class_name Occludable

#HELP: In der MeshInstance-Scene rechts neben Inspektor auf Node gehen und zu Foliage hinzufügen
const FOLIAGE_GROUP := "foliage"

func _ready() -> void:
	_setup_materials(self)
	

func _setup_materials(node: Node) -> void:
	if node is MeshInstance3D:
		if node.is_in_group(FOLIAGE_GROUP):
			_convert_material(node as MeshInstance3D)
	for child in node.get_children():
		_setup_materials(child)

func _convert_material(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for surface_idx in mi.mesh.get_surface_count():
		var orig: Material = mi.get_surface_override_material(surface_idx)
		if orig == null:
			orig = mi.mesh.surface_get_material(surface_idx)
		if orig == null:
			continue
		if orig is BaseMaterial3D:
			var shader_mat := TreeOcclusionManager.get_or_create_material(orig)
			if shader_mat != null:
				mi.set_surface_override_material(surface_idx, shader_mat)

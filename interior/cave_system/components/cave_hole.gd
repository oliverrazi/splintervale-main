@tool
class_name CaveHole
extends Node3D

@export var hole_depth: float = -1.0:
	set(v): hole_depth = v; _notify_parent()

## Material für die Lochwände (zum Dekorieren).
@export var wall_material: Material = null:
	set(v): wall_material = v; _notify_parent()

## Zackigkeit der Lochränder (wie edge_subdivisions im CavePiece).
@export_range(0, 12) var edge_subdivisions: int = 3:
	set(v): edge_subdivisions = v; _notify_parent()

@export_range(0.0, 2.0, 0.05) var edge_noise_strength: float = 0.2:
	set(v): edge_noise_strength = v; _notify_parent()


func get_hole_polygon() -> PackedVector2Array:
	var result := PackedVector2Array()
	for child in get_children():
		if child is Marker3D:
			# Position relativ zum PARENT (CavePiece), inkl. eigener Node-Position
			var world_offset : Variant= position + child.position
			result.append(Vector2(world_offset.x, world_offset.z))
	return result


func _notify_parent() -> void:
	var p := get_parent()
	if p and p.has_method("mark_dirty"):
		p.mark_dirty()


func _ready() -> void:
	child_entered_tree.connect(func(_n): _notify_parent())
	child_exiting_tree.connect(func(_n): _notify_parent())


func create_markers(points: PackedVector2Array) -> void:
	for child in get_children():
		if child is Marker3D:
			child.queue_free()
	for i in range(points.size()):
		var m := Marker3D.new()
		m.name = "H%02d" % i
		m.position = Vector3(points[i].x, 0.0, points[i].y)
		add_child(m)
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			m.owner = get_tree().edited_scene_root
	_notify_parent()

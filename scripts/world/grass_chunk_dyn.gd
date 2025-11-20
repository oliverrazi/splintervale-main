@tool
extends Node3D
class_name GrassChunk

@export var lod_switch: float = 10.0
@export var impostor_fade_in_start: float = 5.0
@export var impostor_fade_in_end: float = 10.0
@export var grass_fade_out_start: float = 10.0
@export var grass_fade_out_end: float = 20.0

var grass_multimesh_full: MultiMesh
var grass_multimesh_simple: MultiMesh
var is_using_simple: bool = false

func _ready() -> void:
	grass_multimesh_full  = load("res://assets/base_tiles/grass/grass_multimesh.tres") as MultiMesh
	grass_multimesh_simple = load("res://assets/base_tiles/grass/grass_multimesh_simple.tres") as MultiMesh

## Projiziert jedes Gras-Blade einzeln auf das darunter liegende Mesh
func project_grass_to_ground() -> void:
	await ready
	await get_tree().process_frame
	if not is_inside_tree():
		return

	var plateau_gen: PlateauGenerator = get_parent().get_node("..").plateau_generator
	if not plateau_gen:
		return

	for child: Node3D in get_children():
		if child is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = child as MultiMeshInstance3D
			var mm: MultiMesh = mmi.multimesh
			if mm == null or mm.instance_count == 0:
				continue

			for i: int in range(mm.instance_count):
				var tr: Transform3D = mm.get_instance_transform(i)
				var world_y: float = plateau_gen.get_ground_height(global_position + tr.origin)
				tr.origin.y = world_y - global_position.y      # relativ zum Chunk
				mm.set_instance_transform(i, tr)

func _process(delta: float) -> void:
	var camera_pos: Vector3 = (
		EditorInterface.get_editor_viewport_3d().get_camera_3d().global_position
		if Engine.is_editor_hint() else
		get_viewport().get_camera_3d().global_position
	)

	var camera_distance: float = global_position.distance_to(camera_pos)

	if camera_distance < lod_switch and is_using_simple:
		%Grass.multimesh = grass_multimesh_full
		is_using_simple = false
	elif camera_distance >= lod_switch and not is_using_simple:
		%Grass.multimesh = grass_multimesh_simple
		is_using_simple = true

	var start_to_mid: float = smoothstep(impostor_fade_in_start, impostor_fade_in_end, camera_distance)
	var mid_to_end: float  = smoothstep(grass_fade_out_start, grass_fade_out_end, camera_distance)

	%Grass.visible = mid_to_end < 1.0
	%Impostor.visible = mid_to_end >= 1.0

	%Impostor.set_instance_shader_parameter("alpha", start_to_mid)
	%Grass.set_instance_shader_parameter("alpha", 1.0 - mid_to_end)
	
	
	## Löscht oder verschiebt Gras-Instanzen, die *nicht* auf dem Plateau liegen
func clip_grass_to_plateau_outline() -> void:
	var plateau_gen: PlateauGenerator = get_parent().get_parent().plateau_generator
	if not plateau_gen:
		return

	for child: Node3D in get_children():
		if child is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = child as MultiMeshInstance3D
			var mm: MultiMesh = mmi.multimesh
			if mm == null or mm.instance_count == 0:
				continue

			var new_transforms: Array[Transform3D] = []
			for i: int in range(mm.instance_count):
				var tr: Transform3D = mm.get_instance_transform(i)
				var world_xz: Vector2 = Vector2(global_position.x + tr.origin.x, global_position.z + tr.origin.z)
				var plateau_y: float = plateau_gen.get_plateau_elevation_if_inside(world_xz)

				if not is_nan(plateau_y):
					# Punkt liegt auf Plateau -> Y anpassen
					tr.origin.y = plateau_y - global_position.y
					new_transforms.append(tr)
				# else: außerhalb -> wird ignoriert (nicht übernommen)

			# Neue Instance-Anzahl setzen
			mm.instance_count = new_transforms.size()
			for j: int in range(new_transforms.size()):
				mm.set_instance_transform(j, new_transforms[j])

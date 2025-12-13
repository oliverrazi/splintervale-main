@tool
extends Node3D
class_name GrassChunkDyn

@export_group("LOD / Fade")
@export var lod_switch: float = 10.0
@export var impostor_fade_in_start: float = 5.0
@export var impostor_fade_in_end: float = 10.0
@export var grass_fade_out_start: float = 10.0
@export var grass_fade_out_end: float = 20.0

@export_group("Grass Distribution")
@export var instances_full: int = 200
@export var instances_simple: int = 80
@export var random_seed_offset: int = 0

# MultiMesh-Templates aus deinen Ressourcen
var grass_multimesh_full_template: MultiMesh
var grass_multimesh_simple_template: MultiMesh

# Runtime-MultiMeshes mit prozeduralen Positionen
var grass_multimesh_full_runtime: MultiMesh
var grass_multimesh_simple_runtime: MultiMesh

var is_using_simple: bool = false

# Höheninfos / Chunk-Kontext
var plateau_generator: PlateauGenerator = null
var chunk_center: Vector3 = Vector3.ZERO
var chunk_size: float = 5.0
var base_ground_height: float = 0.0

var rng: RandomNumberGenerator


func _ready() -> void:
	# Templates EINMAL laden (mesh aus deinen .tres)
	grass_multimesh_full_template = load("res://assets/base_tiles/grass/grass_multimesh.tres")
	grass_multimesh_simple_template = load("res://assets/base_tiles/grass/grass_multimesh_simple.tres")

	# Runtime-MultiMeshes anlegen
	grass_multimesh_full_runtime = MultiMesh.new()
	grass_multimesh_simple_runtime = MultiMesh.new()

	# Mesh aus Templates übernehmen (falls vorhanden)
	if grass_multimesh_full_template:
		grass_multimesh_full_runtime.mesh = grass_multimesh_full_template.mesh
	if grass_multimesh_simple_template:
		grass_multimesh_simple_runtime.mesh = grass_multimesh_simple_template.mesh
	elif grass_multimesh_full_template:
		# Fallback: simple nutzt gleiches Mesh, wenn kein eigenes vorhanden
		grass_multimesh_simple_runtime.mesh = grass_multimesh_full_template.mesh

	# $Grass initial auf "full" setzen
	if has_node("Grass"):
		var grass_mmi := $Grass as MultiMeshInstance3D
		grass_mmi.multimesh = grass_multimesh_full_runtime

	if rng == null:
		rng = RandomNumberGenerator.new()


# Wird vom GrassChunkManager aufgerufen!
func setup_height_provider(p_gen: PlateauGenerator, center: Vector3, size: float) -> void:
	print("GrassChunk dynamic OK:", center)
	plateau_generator = p_gen
	chunk_center = center
	chunk_size = size
	base_ground_height = center.y

	# Seed abhängig von Position, damit Chunks unterschiedlich aussehen
	var seed_val: int = int(center.x * 73856093.0) ^ int(center.z * 19349663.0) ^ random_seed_offset
	rng.seed = seed_val
	
	_generate_grass()


func _generate_grass() -> void:
	if grass_multimesh_full_runtime == null or grass_multimesh_simple_runtime == null:
		return

	# FULL-Lod verteilen
	grass_multimesh_full_runtime.instance_count = instances_full
	for i: int in range(instances_full):
		_set_instance_for_multimesh(grass_multimesh_full_runtime, i)

	# SIMPLE-Lod (z.B. weniger Instanzen)
	grass_multimesh_simple_runtime.instance_count = instances_simple
	for i: int in range(instances_simple):
		_set_instance_for_multimesh(grass_multimesh_simple_runtime, i)


func _set_instance_for_multimesh(mm: MultiMesh, idx: int) -> void:
	# Zufällige Position im Chunk (lokale Koordinaten)
	var lx: float = rng.randf_range(-chunk_size * 0.5, chunk_size * 0.5)
	var lz: float = rng.randf_range(-chunk_size * 0.5, chunk_size * 0.5)

	var world_x: float = chunk_center.x + lx
	var world_z: float = chunk_center.z + lz

	var world_y: float = base_ground_height

	# Plateau-Höhe abfragen, falls vorhanden
	if plateau_generator != null:
		world_y = plateau_generator.get_height_at(world_x, world_z, base_ground_height)

	# Lokale Y-Höhe relativ zum Chunk-Mittelpunkt
	var local_y: float = world_y - chunk_center.y

	var transform: Transform3D = Transform3D.IDENTITY
	transform.origin = Vector3(lx, local_y, lz)

	# Zufällige Rotation für Variation
	var angle: float = rng.randf() * TAU
	transform = transform.rotated(Vector3.UP, angle)

	mm.set_instance_transform(idx, transform)


func _process(delta: float) -> void:
	if grass_multimesh_full_runtime == null or grass_multimesh_simple_runtime == null:
		return
	if not has_node("Grass") or not has_node("Impostor"):
		return

	var grass_mmi := $Grass as MultiMeshInstance3D
	var impostor_mmi := $Impostor

	var camera_pos: Vector3

	if Engine.is_editor_hint():
		var editor_viewport := EditorInterface.get_editor_viewport_3d()
		if editor_viewport and editor_viewport.get_camera_3d():
			camera_pos = editor_viewport.get_camera_3d().global_position
		else:
			return
	else:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		camera_pos = cam.global_position

	var camera_distance: float = global_position.distance_to(camera_pos)

	# LOD-Umschaltung nur bei Bedarf
	if camera_distance < lod_switch and is_using_simple:
		grass_mmi.multimesh = grass_multimesh_full_runtime
		is_using_simple = false
	elif camera_distance >= lod_switch and not is_using_simple:
		grass_mmi.multimesh = grass_multimesh_simple_runtime
		is_using_simple = true

	# Fade-Logik wie bisher
	var start_to_mid: float = smoothstep(impostor_fade_in_start, impostor_fade_in_end, camera_distance)
	var mid_to_end: float = smoothstep(grass_fade_out_start, grass_fade_out_end, camera_distance)

	grass_mmi.visible = mid_to_end < 1.0
	impostor_mmi.visible = mid_to_end >= 1.0

	# Shader-Parameter (alpha) setzen, falls vorhanden
	if impostor_mmi.has_method("set_instance_shader_parameter"):
		impostor_mmi.set_instance_shader_parameter("alpha", start_to_mid)
	if grass_mmi.has_method("set_instance_shader_parameter"):
		grass_mmi.set_instance_shader_parameter("alpha", 1.0 - mid_to_end)

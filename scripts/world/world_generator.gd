@tool
extends Node3D
class_name WorldGenerator

## Hauptklasse für Weltgenerierung

# ============================================
# EXPORT VARIABLEN
# ============================================

@export_group("World Settings")
@export var world_size: Vector2 = Vector2(100, 100)
@export var random_seed: int = 0
@export var generate_on_ready: bool = true
@export var regenerate_button: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			call_deferred("generate_world")
		regenerate_button = false

@export_group("Ground Plane")
@export var show_ground: bool = true
@export var ground_height: float = -0.5
@export var ground_texture_scale: float = 1.0

@export_group("Grass Chunk Settings")
@export var grass_chunk_scene: PackedScene
@export var chunk_size: float = 5.0
@export var active_radius: float = 40.0
@export var unload_radius: float = 60.0
@export var use_directional_culling: bool = true
@export var view_angle: float = 130.0
@export var max_chunks_per_frame: int = 3
@export var chunk_fade_duration: float = 0.35

@export_group("Plateau Settings")
@export var num_plateaus: int = 5
@export var min_plateau_radius: float = 8.0
@export var max_plateau_radius: float = 20.0
@export var min_plateau_height: float = 2.0
@export var max_plateau_height: float = 8.0
@export_range(0.0, 1.0) var shape_variation: float = 0.7

@export_group("Textures")
@export var grass_texture: Texture2D
@export var earth_texture: Texture2D
@export var texture_scale: float = 1.0
@export_range(0.0, 0.5) var grass_overhang: float = 0.05


# ============================================
# INTERNE VARIABLEN
# ============================================

var rng: RandomNumberGenerator
var plane: MeshInstance3D
var plateau_gen: PlateauGenerator
var grass_manager: GrassChunkManager
var is_initialized := false

# ============================================
# LIFECYCLE
# ============================================

func _init():
	if grass_overhang == null:
		grass_overhang = 0.05
	if texture_scale == null:
		texture_scale = 1.0

func _ready():
	
	# Im Editor: Warte einen Frame
	if Engine.is_editor_hint():
		await get_tree().process_frame
	
	initialize_systems()
	
	# Nur im Spiel automatisch generieren
	if not Engine.is_editor_hint() and generate_on_ready:
		call_deferred("generate_world")

func initialize_systems():
	if is_initialized:
		return
	
	# RNG initialisieren
	if rng == null:
		if random_seed == 0:
			rng = RandomNumberGenerator.new()
			rng.randomize()
		else:
			rng = RandomNumberGenerator.new()
			rng.seed = random_seed
	
	# Plateau Generator
	plateau_gen = PlateauGenerator.new(self)
	
	# Grass Manager - nur erstellen, nicht direkt adden
	if not has_node("GrassManager"):
		grass_manager = GrassChunkManager.new()
		grass_manager.name = "GrassManager"
		add_child(grass_manager)
		
		# Owner setzen im Editor
		if Engine.is_editor_hint():
			var scene_root = get_tree().edited_scene_root
			if scene_root:
				grass_manager.owner = scene_root
	else:
		grass_manager = get_node("GrassManager")
	
	# Settings übertragen
	if grass_manager:
		grass_manager.chunk_scene = grass_chunk_scene
		grass_manager.chunk_size = chunk_size
		grass_manager.active_radius = active_radius
		grass_manager.unload_radius = unload_radius
		grass_manager.use_directional_culling = use_directional_culling
		grass_manager.view_angle = view_angle
		grass_manager.max_chunks_per_frame = max_chunks_per_frame
		grass_manager.chunk_fade_duration = chunk_fade_duration
	
	# Process nur im Spiel
	set_process(not Engine.is_editor_hint())
	
	is_initialized = true

func _process(delta: float):
	if grass_manager:
		grass_manager.process_chunks(delta)

# ============================================
# WORLD GENERATION
# ============================================
var is_generating := false

func generate_world():
	
	if is_generating:
		print("!!! WARNUNG: generate_world läuft bereits !!!")
		return
		
	is_generating = true
	
	if not is_initialized:
		initialize_systems()
	
	print("=== Weltgenerierung gestartet ===")
	
	clear_world()
	
	if show_ground:
		generate_ground_plane()
	
	if plateau_gen:
		plateau_gen.generate_all_plateaus()
		print("DEBUG: %d Plateaus generiert" % plateau_gen.plateaus.size())
	
	# Plateau-Böden finden -> tiefsten Punkt ermitteln
	var lowest_plateau_base := ground_height
	if plateau_gen and not plateau_gen.plateaus.is_empty():
		for p in plateau_gen.plateaus:
			lowest_plateau_base = min(lowest_plateau_base, p.position.y)

	grass_manager.setup(world_size, lowest_plateau_base, plateau_gen)
	
	# Grass Setup im Editor: MINIMALE Vorschau
	if grass_manager:
		if Engine.is_editor_hint():
			grass_manager.setup_editor_preview(world_size, ground_height)
		else:
			grass_manager.setup(world_size, ground_height, plateau_gen)
	
	print("=== Weltgenerierung abgeschlossen ===")
	is_generating = false

func clear_world():
	print("=== CLEARING WORLD ===")
	
	# Plateau Generator clearen!
	if plateau_gen:
		plateau_gen.clear()
	
	# Grass Manager clearen
	if grass_manager:
		grass_manager.clear()
	
	# Alle anderen Kinder löschen
	for child in get_children():
		if child != grass_manager:
			print("  Lösche: %s" % child.name)
			child.queue_free()
	
	print("=== CLEAR COMPLETE ===")


func generate_ground_plane():
	print("Generiere Grundfläche...")
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.position = Vector3(0, ground_height, 0)
	mesh_instance.name = "GroundPlane"
	
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(world_size.x * 1.2, world_size.y * 1.2)
	mesh_instance.mesh = plane_mesh
	
	var material = StandardMaterial3D.new()
	if grass_texture:
		material.albedo_texture = grass_texture
		material.uv1_scale = Vector3(
			world_size.x * 0.05 * ground_texture_scale,
			world_size.y * 0.05 * ground_texture_scale,
			1.0
		)
	else:
		material.albedo_color = Color(0.3, 0.6, 0.3)
	
	mesh_instance.set_surface_override_material(0, material)
	plane = mesh_instance
	add_child(mesh_instance)
	
	# Kollision
	var static_body = StaticBody3D.new()
	static_body.name = "GroundCollision"
	mesh_instance.add_child(static_body)
	
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(world_size.x * 1.2, 0.1, world_size.y * 1.2)
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0, -0.05, 0)
	static_body.add_child(collision_shape)
	
	if Engine.is_editor_hint():
		var scene_root = get_tree().edited_scene_root
		if scene_root:
			collision_shape.owner = scene_root
			mesh_instance.owner = scene_root
			static_body.owner = scene_root
	
	print("  Boden generiert")

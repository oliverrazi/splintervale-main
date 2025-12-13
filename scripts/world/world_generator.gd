@tool
extends Node3D
class_name WorldGenerator

@export_group("World")
@export var world_size: Vector2 = Vector2(100, 100)
@export var random_seed: int = 0
@export var generate_on_ready: bool = true

@export_group("Ground Textures")
@export var ground_height: float = -0.5
@export var grass_texture: Texture2D
@export var earth_texture: Texture2D
@export var path_texture: Texture2D

@export_group("Grass Chunks")
@export var grass_chunk_scene: PackedScene
@export var chunk_size: float = 5.0
@export var active_radius: float = 40.0
@export var unload_radius: float = 60.0
@export var max_chunks_per_frame: int = 3
@export var chunk_fade_duration: float = 0.35

@export_group("Plateaus")
@export var use_plateaus: bool = true
@export var plateau_generator: PlateauGenerator

@export_group("Material Tuning")
@export var tex_scale: float = 0.15

@export var global_brightness: float = 0.85
@export var global_contrast: float = 1.1
@export var global_saturation: float = 1.0

@export var grass_brightness: float = 1.0
@export var earth_brightness: float = 0.9
@export var path_brightness: float = 1.0

# Erde nur auf steilen Flächen:
@export var earth_start_deg: float = 45.0
@export var earth_blend_deg: float = 5.0

# Einfacher Pfad als Band entlang der Z-Achse (in local_pos.z)
@export var path_center_z: float = 0.0
@export var path_half_width: float = 2.0
@export var path_edge_softness: float = 1.0  # Übergang: größer = weicher

var rng: RandomNumberGenerator
var grass_manager: GrassChunkManager
var ground_material: ShaderMaterial


func _ready() -> void:
	if Engine.is_editor_hint():
		await get_tree().process_frame
	initialize_systems()
	if not Engine.is_editor_hint() and generate_on_ready:
		call_deferred("generate_world")


func initialize_systems() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = random_seed if random_seed != 0 else randi()

	# --- Multi-Layer Shader: Gras + Erde + Pfad ---
	var shader: Shader = Shader.new()
	shader.code = """
shader_type spatial;

uniform sampler2D grass_tex;
uniform sampler2D earth_tex;
uniform sampler2D path_tex;

uniform float tex_scale = 0.15;

// globale Farbtuning
uniform float global_brightness = 1.0;
uniform float global_contrast  = 1.0;
uniform float global_saturation = 1.0;

// Layer-spezifische Helligkeit
uniform float grass_brightness = 1.0;
uniform float earth_brightness = 1.0;
uniform float path_brightness  = 1.0;

// Erde-Mix (per Winkel)
uniform float earth_start_deg = 45.0;
uniform float earth_blend_deg = 5.0;

// Pfad-Parameter (Band entlang Z-Achse)
uniform float path_center_z = 0.0;
uniform float path_half_width = 2.0;
uniform float path_edge_softness = 1.0;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
    local_pos = VERTEX;
    local_normal = NORMAL;
}

vec3 triplanar_sample(sampler2D tex, vec3 pos, vec3 nrm) {
    vec3 an = abs(nrm);
    an = max(an, vec3(0.0001));
    an /= (an.x + an.y + an.z);

    vec2 uv_x = pos.zy * tex_scale;
    vec2 uv_y = pos.xz * tex_scale;
    vec2 uv_z = pos.xy * tex_scale;

    vec3 cx = texture(tex, uv_x).rgb;
    vec3 cy = texture(tex, uv_y).rgb;
    vec3 cz = texture(tex, uv_z).rgb;

    return cx * an.x + cy * an.y + cz * an.z;
}

vec3 apply_color_grade(vec3 col, float br, float ct, float sat) {
    // brightness
    col *= br;

    // contrast um 0.5 herum
    col = (col - 0.5) * ct + 0.5;

    // saturation
    float gray = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(gray), col, sat);

    return col;
}

void fragment() {
    vec3 n = normalize(local_normal);
    vec3 p = local_pos;

    // 1) Erde-Gewicht (per Neigung)
    float ny = clamp(abs(n.y), 0.0, 1.0);
    float angle_deg = degrees(acos(ny)); // 0° flach, 90° Wand

    float earth_t = smoothstep(
        earth_start_deg - earth_blend_deg,
        earth_start_deg + earth_blend_deg,
        angle_deg
    );

    // 2) Pfad-Maske als Band entlang Z
    float dist_z = abs(p.z - path_center_z);
    // innen: dist_z ~ 0, außen: dist_z > path_half_width
    float edge = max(path_half_width, 0.0001);
    float path_mask = 1.0 - smoothstep(edge - path_edge_softness, edge + path_edge_softness, dist_z);
    // Pfad nur auf eher flachen Flächen:
    path_mask *= (1.0 - earth_t);

    // 3) Raw-Layer-Farben
    vec3 grass_col = triplanar_sample(grass_tex, p, n) * grass_brightness;
    vec3 earth_col = triplanar_sample(earth_tex, p, n) * earth_brightness;
    vec3 path_col  = triplanar_sample(path_tex,  p, n) * path_brightness;

    // 4) Layer-Gewichte
    float w_path  = clamp(path_mask, 0.0, 1.0);
    float w_earth = clamp((1.0 - w_path) * earth_t, 0.0, 1.0);
    float w_grass = 1.0 - w_path - w_earth;

    // Sicherheit
    w_grass = clamp(w_grass, 0.0, 1.0);

    float w_sum = w_grass + w_earth + w_path;
    if (w_sum > 0.0001) {
        w_grass /= w_sum;
        w_earth /= w_sum;
        w_path  /= w_sum;
    }

    vec3 col = grass_col * w_grass + earth_col * w_earth + path_col * w_path;

    // 5) globales Color Grading
    col = apply_color_grade(col, global_brightness, global_contrast, global_saturation);

    ALBEDO = col;
}
"""

	ground_material = ShaderMaterial.new()
	ground_material.shader = shader

	if grass_texture:
		ground_material.set_shader_parameter("grass_tex", grass_texture)
	if earth_texture:
		ground_material.set_shader_parameter("earth_tex", earth_texture)
	if path_texture:
		ground_material.set_shader_parameter("path_tex", path_texture)

	ground_material.set_shader_parameter("tex_scale", tex_scale)

	ground_material.set_shader_parameter("global_brightness", global_brightness)
	ground_material.set_shader_parameter("global_contrast", global_contrast)
	ground_material.set_shader_parameter("global_saturation", global_saturation)

	ground_material.set_shader_parameter("grass_brightness", grass_brightness)
	ground_material.set_shader_parameter("earth_brightness", earth_brightness)
	ground_material.set_shader_parameter("path_brightness", path_brightness)

	ground_material.set_shader_parameter("earth_start_deg", earth_start_deg)
	ground_material.set_shader_parameter("earth_blend_deg", earth_blend_deg)

	ground_material.set_shader_parameter("path_center_z", path_center_z)
	ground_material.set_shader_parameter("path_half_width", path_half_width)
	ground_material.set_shader_parameter("path_edge_softness", path_edge_softness)

	# --- Grass-Manager ---
	grass_manager = GrassChunkManager.new()
	grass_manager.name = "GrassManager"
	add_child(grass_manager)
	if Engine.is_editor_hint():
		grass_manager.owner = get_tree().edited_scene_root

	grass_manager.chunk_scene = grass_chunk_scene
	grass_manager.chunk_size = chunk_size
	grass_manager.active_radius = active_radius
	grass_manager.unload_radius = unload_radius
	grass_manager.max_chunks_per_frame = max_chunks_per_frame
	grass_manager.chunk_fade_duration = chunk_fade_duration

	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	if grass_manager:
		grass_manager.process_chunks(delta)


func generate_world() -> void:
	clear_world()
	generate_ground()

	if use_plateaus and plateau_generator:
		plateau_generator.generate(world_size, ground_height, rng, ground_material)

	if grass_manager:
		grass_manager.setup(world_size, ground_height, plateau_generator)


func clear_world() -> void:
	for child: Node in get_children():
		if child != grass_manager and child != plateau_generator:
			child.queue_free()
	if grass_manager:
		grass_manager.clear()


func generate_ground() -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Ground"
	mesh.position = Vector3(0.0, ground_height, 0.0)

	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = world_size
	mesh.mesh = plane

	mesh.set_surface_override_material(0, ground_material)
	add_child(mesh)
	if Engine.is_editor_hint():
		mesh.owner = get_tree().edited_scene_root

	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(world_size.x, 0.1, world_size.y)
	shape.shape = box
	body.add_child(shape)
	mesh.add_child(body)

	if Engine.is_editor_hint():
		body.owner = get_tree().edited_scene_root
		shape.owner = get_tree().edited_scene_root

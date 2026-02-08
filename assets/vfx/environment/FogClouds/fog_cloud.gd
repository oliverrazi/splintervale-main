extends Node3D

@export var move_speed: float = 0.5
@export var move_direction: Vector3 = Vector3(1, 0, 0.3)
@export var bobbing_speed: float = 0.3
@export var bobbing_amount: float = 0.2
@export var rotation_speed: float = 0.1
@export var fade_at_edges: bool = true
@export var area_bounds: Vector3 = Vector3(50, 10, 50)

var _start_pos: Vector3
var _time: float = 0.0
var _phase: float = 0.0


func _ready() -> void:
	_start_pos = position
	_phase = randf() * TAU
	_time = randf() * 100.0  # Zufälliger Startpunkt
	
	_setup_fog_material()


func _process(delta: float) -> void:
	_time += delta
	
	# Langsame Bewegung
	position += move_direction.normalized() * move_speed * delta
	
	# Sanftes Auf und Ab
	position.y = _start_pos.y + sin(_time * bobbing_speed + _phase) * bobbing_amount
	
	# Langsame Rotation
	rotation.y += rotation_speed * delta
	
	# Wrap around wenn außerhalb der Bounds
	if fade_at_edges:
		_wrap_position()


func _wrap_position() -> void:
	var half_bounds := area_bounds / 2.0
	
	if position.x > half_bounds.x:
		position.x = -half_bounds.x
	elif position.x < -half_bounds.x:
		position.x = half_bounds.x
	
	if position.z > half_bounds.z:
		position.z = -half_bounds.z
	elif position.z < -half_bounds.z:
		position.z = half_bounds.z
		
func _setup_fog_material() -> void:
	var mesh_instance: MeshInstance3D = $MeshInstance3D
	if mesh_instance == null:
		return
	
	# QuadMesh erstellen falls nicht vorhanden
	if mesh_instance.mesh == null:
		var quad := QuadMesh.new()
		quad.size = Vector2(4.0, 2.0)
		mesh_instance.mesh = quad
	
	# Fog Shader
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 fog_color : source_color = vec4(0.8, 0.85, 0.9, 0.3);
uniform sampler2D noise_texture : hint_default_white;
uniform float noise_scale : hint_range(0.1, 5.0) = 1.0;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.5;
uniform float time_scale : hint_range(0.0, 1.0) = 0.1;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Billboard - immer zur Kamera schauen (nur Y-Achse)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(1.0, 0.0, 0.0, 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 uv = UV;
	
	// Animiertes Noise für Wolkeneffekt
	vec2 noise_uv = uv * noise_scale + vec2(TIME * time_scale, TIME * time_scale * 0.5);
	float noise = texture(noise_texture, noise_uv).r;
	
	// Weiche Kanten (radial fade)
	vec2 center = uv - vec2(0.5);
	float dist = length(center) * 2.0;
	float edge_fade = 1.0 - smoothstep(0.3, 1.0, dist);
	
	// Noise in die Transparenz einbauen
	float alpha = fog_color.a * edge_fade * (0.5 + noise * 0.5);
	alpha *= smoothstep(0.0, edge_softness, edge_fade);
	
	ALBEDO = fog_color.rgb;
	ALPHA = alpha;
}
"""
	
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("fog_color", Color(0.8, 0.85, 0.9, 0.4))
	mat.set_shader_parameter("noise_scale", 1.5)
	mat.set_shader_parameter("edge_softness", 0.4)
	mat.set_shader_parameter("time_scale", 0.05)
	
	# Noise Texture generieren
	var noise_tex := _create_noise_texture()
	mat.set_shader_parameter("noise_texture", noise_tex)
	
	mesh_instance.material_override = mat


func _create_noise_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	
	return tex

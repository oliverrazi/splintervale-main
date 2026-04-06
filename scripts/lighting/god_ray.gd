## A single God Ray beam.
## Place in your scene, adjust height/width/angle.
## Uses a QuadMesh with the god_ray shader for a soft volumetric light beam effect.
@tool
class_name GodRay
extends Node3D

@export_group("Beam Shape")
## Total height of the light beam
@export var beam_height: float = 8.0:
	set(v):
		beam_height = v
		_update_mesh()
## Width of the beam at the bottom
@export var beam_width: float = 2.0:
	set(v):
		beam_width = v
		_update_mesh()

@export_group("Appearance")
@export var ray_color: Color = Color(1.0, 0.95, 0.8, 0.3):
	set(v):
		ray_color = v
		_update_shader_params()
@export_range(0.0, 2.0) var intensity: float = 0.5:
	set(v):
		intensity = v
		_update_shader_params()
@export_range(0.0, 1.0) var edge_softness: float = 0.3:
	set(v):
		edge_softness = v
		_update_shader_params()
@export_range(0.0, 1.0) var bottom_fade: float = 0.4:
	set(v):
		bottom_fade = v
		_update_shader_params()

@export_group("Animation")
@export_range(0.0, 2.0) var sway_speed: float = 0.3:
	set(v):
		sway_speed = v
		_update_shader_params()
@export_range(0.0, 0.2) var sway_amount: float = 0.05:
	set(v):
		sway_amount = v
		_update_shader_params()
@export_range(0.0, 0.5) var flicker_amount: float = 0.15:
	set(v):
		flicker_amount = v
		_update_shader_params()

@export_group("Dust Particles")
@export var dust_enabled: bool = true:
	set(v):
		dust_enabled = v
		_update_shader_params()
@export_range(0.0, 2.0) var dust_brightness: float = 0.6:
	set(v):
		dust_brightness = v
		_update_shader_params()

var _mesh_instance: MeshInstance3D
var _shader_mat: ShaderMaterial

const SHADER_CODE := """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 ray_color : source_color = vec4(1.0, 0.95, 0.8, 0.3);
uniform float intensity : hint_range(0.0, 2.0) = 0.5;
uniform float fade_top : hint_range(0.0, 1.0) = 0.1;
uniform float fade_bottom : hint_range(0.0, 1.0) = 0.4;
uniform float fade_edges : hint_range(0.0, 1.0) = 0.3;
uniform float sway_speed : hint_range(0.0, 2.0) = 0.3;
uniform float sway_amount : hint_range(0.0, 0.2) = 0.05;
uniform float flicker_speed : hint_range(0.0, 5.0) = 1.5;
uniform float flicker_amount : hint_range(0.0, 0.5) = 0.15;
uniform bool dust_enabled = true;
uniform float dust_density : hint_range(0.0, 100.0) = 40.0;
uniform float dust_brightness : hint_range(0.0, 2.0) = 0.6;
uniform float dust_speed : hint_range(0.0, 2.0) = 0.5;
uniform float dust_size : hint_range(0.001, 0.02) = 0.006;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float dust_pattern(vec2 uv, float time_val) {
	float dust = 0.0;
	for (float i = 0.0; i < 3.0; i += 1.0) {
		vec2 offset = vec2(
			sin(time_val * dust_speed * (0.5 + i * 0.3) + i * 1.7) * 0.1,
			-time_val * dust_speed * (0.3 + i * 0.2)
		);
		vec2 grid_uv = (uv + offset) * dust_density * (1.0 + i * 0.5);
		vec2 cell = floor(grid_uv);
		vec2 local_uv = fract(grid_uv) - 0.5;
		float h = hash(cell + i * 100.0);
		vec2 particle_pos = vec2(h, fract(h * 37.0)) - 0.5;
		float d = length(local_uv - particle_pos * 0.4);
		dust += smoothstep(dust_size, 0.0, d) * h;
	}
	return dust;
}

void fragment() {
	vec2 uv = UV;
	float vertical = smoothstep(0.0, fade_top, uv.y) * smoothstep(1.0, 1.0 - fade_bottom, uv.y);
	float beam_width_local = mix(0.3, 0.5, uv.y);
	float dist_from_center = abs(uv.x - 0.5);
	float horizontal = smoothstep(beam_width_local, beam_width_local - fade_edges, dist_from_center);
	float beam = vertical * horizontal;
	float sway = sin(TIME * sway_speed + uv.y * 2.0) * sway_amount;
	beam *= smoothstep(beam_width_local + sway, beam_width_local - fade_edges + sway, dist_from_center);
	float flicker = 1.0 - flicker_amount * (sin(TIME * flicker_speed) * 0.5 + 0.5)
					* (sin(TIME * flicker_speed * 1.7 + 1.0) * 0.5 + 0.5);
	float dust = 0.0;
	if (dust_enabled) {
		dust = dust_pattern(uv, TIME) * dust_brightness * beam;
	}
	ALBEDO = ray_color.rgb;
	ALPHA = (beam * intensity * flicker + dust) * ray_color.a;
}
"""


func _ready() -> void:
	_create_mesh()
	_update_shader_params()


func _create_mesh() -> void:
	if _mesh_instance:
		_mesh_instance.queue_free()

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "GodRayMesh"

	var quad := QuadMesh.new()
	quad.size = Vector2(beam_width, beam_height)
	# Center the mesh so top is at y=0 (origin) and beam goes downward
	quad.center_offset = Vector3(0.0, -beam_height / 2.0, 0.0)
	_mesh_instance.mesh = quad

	# Create shader material
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader

	_mesh_instance.material_override = _shader_mat

	# Face the camera (Y-billboard only — stays vertical but rotates toward camera)
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(_mesh_instance)


func _update_mesh() -> void:
	if not _mesh_instance or not _mesh_instance.mesh:
		return
	var quad: QuadMesh = _mesh_instance.mesh as QuadMesh
	if quad:
		quad.size = Vector2(beam_width, beam_height)
		quad.center_offset = Vector3(0.0, -beam_height / 2.0, 0.0)


func _update_shader_params() -> void:
	if not _shader_mat:
		return
	_shader_mat.set_shader_parameter("ray_color", ray_color)
	_shader_mat.set_shader_parameter("intensity", intensity)
	_shader_mat.set_shader_parameter("fade_edges", edge_softness)
	_shader_mat.set_shader_parameter("fade_bottom", bottom_fade)
	_shader_mat.set_shader_parameter("sway_speed", sway_speed)
	_shader_mat.set_shader_parameter("sway_amount", sway_amount)
	_shader_mat.set_shader_parameter("flicker_amount", flicker_amount)
	_shader_mat.set_shader_parameter("dust_enabled", dust_enabled)
	_shader_mat.set_shader_parameter("dust_brightness", dust_brightness)


func _process(_delta: float) -> void:
	# Billboard: always face camera but stay vertical
	if not Engine.is_editor_hint() and _mesh_instance:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var cam_pos := cam.global_position
			var my_pos := global_position
			var dir := Vector2(cam_pos.x - my_pos.x, cam_pos.z - my_pos.z)
			if dir.length_squared() > 0.001:
				_mesh_instance.rotation.y = atan2(dir.x, dir.y)

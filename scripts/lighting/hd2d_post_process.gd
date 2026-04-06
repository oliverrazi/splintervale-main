## HD-2D Post-Process Manager
## Creates a full-screen overlay with vignette + color grading.
## Shader is embedded — no external .gdshader file needed.
## Add this to your main scene or as an Autoload.

class_name HD2DPostProcess
extends CanvasLayer

@export_group("Vignette")
@export var vignette_intensity: float = 0.35
@export var vignette_softness: float = 0.45

@export_group("Color Grading")
@export var warmth: float = 0.08
@export var shadow_coolness: float = 0.12
@export var highlight_warmth: float = 0.1

@export_group("Film Grain")
@export var grain_intensity: float = 0.02

var _color_rect: ColorRect
var _shader_mat: ShaderMaterial

const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.45;
uniform vec3 vignette_color : source_color = vec3(0.02, 0.02, 0.05);

uniform float warmth : hint_range(-0.5, 0.5) = 0.08;
uniform float shadow_coolness : hint_range(0.0, 0.5) = 0.12;
uniform float highlight_warmth : hint_range(0.0, 0.5) = 0.1;

uniform float grain_intensity : hint_range(0.0, 0.1) = 0.02;
uniform float grain_speed : hint_range(0.0, 10.0) = 3.0;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;

	// Vignette
	vec2 center_uv = SCREEN_UV - 0.5;
	float dist = length(center_uv);
	float vignette = smoothstep(vignette_softness, vignette_softness + 0.5, dist);
	col = mix(col, vignette_color, vignette * vignette_intensity);

	// Shadow / Highlight Color Split
	float luminance = dot(col, vec3(0.299, 0.587, 0.114));

	vec3 shadow_tint = vec3(-shadow_coolness * 0.5, -shadow_coolness * 0.3, shadow_coolness);
	col += shadow_tint * (1.0 - luminance) * (1.0 - luminance);

	vec3 highlight_tint = vec3(highlight_warmth, highlight_warmth * 0.7, -highlight_warmth * 0.3);
	col += highlight_tint * luminance * luminance;

	col.r += warmth * 0.5;
	col.g += warmth * 0.25;
	col.b -= warmth * 0.3;

	// Film Grain
	if (grain_intensity > 0.0) {
		float grain = random(SCREEN_UV + fract(TIME * grain_speed)) * 2.0 - 1.0;
		col += grain * grain_intensity;
	}

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
"""


func _ready() -> void:
	layer = 100
	_setup_overlay()


func _setup_overlay() -> void:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	
	_shader_mat.set_shader_parameter("vignette_intensity", vignette_intensity)
	_shader_mat.set_shader_parameter("vignette_softness", vignette_softness)
	_shader_mat.set_shader_parameter("warmth", warmth)
	_shader_mat.set_shader_parameter("shadow_coolness", shadow_coolness)
	_shader_mat.set_shader_parameter("highlight_warmth", highlight_warmth)
	_shader_mat.set_shader_parameter("grain_intensity", grain_intensity)
	
	_color_rect = ColorRect.new()
	_color_rect.name = "PostProcessOverlay"
	_color_rect.material = _shader_mat
	_color_rect.color = Color.WHITE
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	add_child(_color_rect)
	
	print("[HD2DPostProcess] Overlay active")


## Dynamically adjust vignette
func set_vignette(intensity: float, duration: float = 0.5) -> void:
	if not _shader_mat:
		return
	var tween := create_tween()
	tween.tween_method(
		func(val: float): _shader_mat.set_shader_parameter("vignette_intensity", val),
		_shader_mat.get_shader_parameter("vignette_intensity") as float,
		intensity,
		duration
	)


## Dynamically adjust warmth
func set_warmth(value: float, duration: float = 1.0) -> void:
	if not _shader_mat:
		return
	var tween := create_tween()
	tween.tween_method(
		func(val: float): _shader_mat.set_shader_parameter("warmth", val),
		_shader_mat.get_shader_parameter("warmth") as float,
		value,
		duration
	)

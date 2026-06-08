## HD-2D Post-Process Manager (aufgewertet)
## Drop-in-Ersatz für euer bisheriges HD2DPostProcess.
## Vollbild-Overlay: filmische Vignette + Color Grading + Korn.
##
## Neu ggü. der alten Version:
##  - Seitenverhältnis-korrekte, KREISRUNDE Vignette (vorher elliptisch verzerrt)
##  - getrennte Regler: radius / feather / curve / intensity
##  - optionale Rand-Entsättigung (zieht den Blick filmisch zur Mitte)
##  - optionale dezente Chromatic Aberration am Rand
## Add this to your main scene or as an Autoload.
class_name HD2DPostProcessCutscene
extends CanvasLayer

@export_group("Vignette")
## Wie stark die Ecken abgedunkelt werden (0..1).
@export_range(0.0, 1.0) var vignette_intensity: float = 0.55
## Radius des hellen Mittenbereichs. Kleiner = engerer Tunnel.
@export_range(0.1, 1.5) var vignette_radius: float = 0.75
## Weichheit des Übergangs von hell -> dunkel.
@export_range(0.05, 1.5) var vignette_feather: float = 0.55
## Kurve des Abfalls. >1 = lange dunkle Ecken (filmischer), <1 = harter Rand.
@export_range(0.3, 4.0) var vignette_curve: float = 1.6
## Farbe der Vignette (leicht bläulich-schwarz wirkt edler als reines Schwarz).
@export var vignette_color: Color = Color(0.015, 0.015, 0.03)
## Entsättigung zum Rand hin (0 = aus).
@export_range(0.0, 1.0) var vignette_desaturation: float = 0.25

@export_group("Color Grading")
@export_range(-0.5, 0.5) var warmth: float = 0.08
@export_range(0.0, 0.5) var shadow_coolness: float = 0.12
@export_range(0.0, 0.5) var highlight_warmth: float = 0.1

@export_group("Chromatic Aberration")
## Sehr dezent halten (0.0–0.004). Trennt nur die Ränder minimal auf.
@export_range(0.0, 0.01) var aberration: float = 0.0

@export_group("Film Grain")
@export_range(0.0, 0.1) var grain_intensity: float = 0.02
@export_range(0.0, 10.0) var grain_speed: float = 3.0

var _color_rect: ColorRect
var _shader_mat: ShaderMaterial

const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 viewport_size = vec2(1920.0, 1080.0);

uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.55;
uniform float vignette_radius : hint_range(0.1, 1.5) = 0.75;
uniform float vignette_feather : hint_range(0.05, 1.5) = 0.55;
uniform float vignette_curve : hint_range(0.3, 4.0) = 1.6;
uniform vec3 vignette_color : source_color = vec3(0.015, 0.015, 0.03);
uniform float vignette_desaturation : hint_range(0.0, 1.0) = 0.25;

uniform float warmth : hint_range(-0.5, 0.5) = 0.08;
uniform float shadow_coolness : hint_range(0.0, 0.5) = 0.12;
uniform float highlight_warmth : hint_range(0.0, 0.5) = 0.1;

uniform float aberration : hint_range(0.0, 0.01) = 0.0;
uniform float grain_intensity : hint_range(0.0, 0.1) = 0.02;
uniform float grain_speed : hint_range(0.0, 10.0) = 3.0;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float aspect = viewport_size.x / max(viewport_size.y, 1.0);

	// Seitenverhältnis-korrigierter Abstand zur Mitte -> KREISRUND
	vec2 c = SCREEN_UV - 0.5;
	c.x *= aspect;
	float dist = length(c) / max(aspect, 1.0);

	// --- Basisfarbe (optional mit Chromatic Aberration am Rand) ----
	vec3 col;
	if (aberration > 0.0) {
		vec2 dir = SCREEN_UV - 0.5;
		float amt = aberration * dist * 4.0;
		col.r = texture(screen_texture, SCREEN_UV - dir * amt).r;
		col.g = texture(screen_texture, SCREEN_UV).g;
		col.b = texture(screen_texture, SCREEN_UV + dir * amt).b;
	} else {
		col = texture(screen_texture, SCREEN_UV).rgb;
	}

	// --- Color Grading ---------------------------------------------
	float luminance = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 shadow_tint = vec3(-shadow_coolness * 0.5, -shadow_coolness * 0.3, shadow_coolness);
	col += shadow_tint * (1.0 - luminance) * (1.0 - luminance);
	vec3 highlight_tint = vec3(highlight_warmth, highlight_warmth * 0.7, -highlight_warmth * 0.3);
	col += highlight_tint * luminance * luminance;
	col.r += warmth * 0.5;
	col.g += warmth * 0.25;
	col.b -= warmth * 0.3;

	// WICHTIG: vor der Vignette clampen. Das Color-Grading (Shadow-Tint
	// subtrahiert!) kann Kanäle negativ ziehen; ungeclampt entstehen sonst
	// die "negativen Farben" im dunklen Rand. Erst clampen, dann tönen.
	col = clamp(col, vec3(0.0), vec3(1.0));

	// --- Vignette: 1 in der Mitte, 0 am Rand -----------------------
	float vig = 1.0 - smoothstep(vignette_radius, vignette_radius + vignette_feather, dist);
	vig = pow(vig, vignette_curve);

	// Rand-Entsättigung
	float lum2 = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum2), (1.0 - vig) * vignette_desaturation);

	// Abdunkeln/Tönen zur Vignette-Farbe
	float darken = mix(1.0, vig, vignette_intensity);
	col = mix(vignette_color, col, darken);

	// --- Film Grain ------------------------------------------------
	if (grain_intensity > 0.0) {
		float grain = random(SCREEN_UV + fract(TIME * grain_speed)) * 2.0 - 1.0;
		col += grain * grain_intensity;
	}

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
"""


func _ready() -> void:
	layer = 10
	_setup_overlay()
	get_tree().root.size_changed.connect(_update_viewport_size)


func _setup_overlay() -> void:
	var shader := Shader.new()
	shader.code = SHADER_CODE

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_push_all_params()

	_color_rect = ColorRect.new()
	_color_rect.name = "PostProcessOverlay"
	_color_rect.material = _shader_mat
	_color_rect.color = Color.WHITE
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(_color_rect)
	_update_viewport_size()
	print("[HD2DPostProcess] Overlay active")


func _push_all_params() -> void:
	_shader_mat.set_shader_parameter("vignette_intensity", vignette_intensity)
	_shader_mat.set_shader_parameter("vignette_radius", vignette_radius)
	_shader_mat.set_shader_parameter("vignette_feather", vignette_feather)
	_shader_mat.set_shader_parameter("vignette_curve", vignette_curve)
	_shader_mat.set_shader_parameter("vignette_color", vignette_color)
	_shader_mat.set_shader_parameter("vignette_desaturation", vignette_desaturation)
	_shader_mat.set_shader_parameter("warmth", warmth)
	_shader_mat.set_shader_parameter("shadow_coolness", shadow_coolness)
	_shader_mat.set_shader_parameter("highlight_warmth", highlight_warmth)
	_shader_mat.set_shader_parameter("aberration", aberration)
	_shader_mat.set_shader_parameter("grain_intensity", grain_intensity)
	_shader_mat.set_shader_parameter("grain_speed", grain_speed)


func _update_viewport_size() -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter("viewport_size", Vector2(get_viewport().get_visible_rect().size))


## Vignette-Intensität sanft faden (z.B. dunkler Tunnel im Intro).
func set_vignette(intensity: float, duration: float = 0.5) -> void:
	if not _shader_mat:
		return
	var t := create_tween()
	t.tween_method(
		func(val: float) -> void: _shader_mat.set_shader_parameter("vignette_intensity", val),
		_shader_mat.get_shader_parameter("vignette_intensity") as float,
		intensity, duration
	)


## Vignette-Radius faden (enger ziehen = mehr Druck/Fokus).
func set_vignette_radius(radius: float, duration: float = 0.5) -> void:
	if not _shader_mat:
		return
	var t := create_tween()
	t.tween_method(
		func(val: float) -> void: _shader_mat.set_shader_parameter("vignette_radius", val),
		_shader_mat.get_shader_parameter("vignette_radius") as float,
		radius, duration
	)


func set_warmth(value: float, duration: float = 1.0) -> void:
	if not _shader_mat:
		return
	var t := create_tween()
	t.tween_method(
		func(val: float) -> void: _shader_mat.set_shader_parameter("warmth", val),
		_shader_mat.get_shader_parameter("warmth") as float,
		value, duration
	)

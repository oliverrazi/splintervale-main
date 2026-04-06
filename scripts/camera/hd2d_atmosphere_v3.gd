@tool
class_name HD2DAtmosphere
extends CanvasLayer

enum Preset {
	CUSTOM,
	WARM_DAYLIGHT,
	COOL_FOREST,
	SUNSET,
	DUNGEON,
	NONE,
}

@export var preset: Preset = Preset.WARM_DAYLIGHT : set = _set_preset

@export_group("Vignette")
@export var vignette_enabled: bool = true : set = _set_vignette_enabled
@export_range(0.0, 1.5, 0.05) var vignette_intensity: float = 0.4 : set = _set_vignette_intensity
@export_range(0.0, 1.0, 0.05) var vignette_size: float = 0.5 : set = _set_vignette_size
@export_range(0.01, 1.0, 0.05) var vignette_softness: float = 0.45 : set = _set_vignette_softness
@export var vignette_color: Color = Color(0.05, 0.02, 0.01) : set = _set_vignette_color

@export_group("Color Grading")
@export var grading_enabled: bool = true : set = _set_grading_enabled
@export_range(-0.5, 0.5, 0.01) var warmth: float = 0.08 : set = _set_warmth
@export_range(0.5, 1.5, 0.05) var contrast: float = 1.05 : set = _set_contrast
@export_range(0.0, 2.0, 0.05) var saturation: float = 1.1 : set = _set_saturation
@export_range(-0.5, 0.5, 0.01) var brightness: float = 0.0 : set = _set_brightness

@export_group("Ambient Light")
@export var ambient_enabled: bool = true : set = _set_ambient_enabled
@export var ambient_color: Color = Color(1.0, 0.92, 0.8) : set = _set_ambient_color
@export_range(0.0, 0.5, 0.01) var ambient_strength: float = 0.05 : set = _set_ambient_strength

var _rect: ColorRect
var _material: ShaderMaterial
var _shader_path: String = "res://scripts/camera/hd2d_atmosphere_v3.gdshader"


func _ready() -> void:
	layer = 100
	_setup_rect()
	_apply_preset(preset)


func _setup_rect() -> void:
	_rect = get_node_or_null("AtmosphereRect") as ColorRect
	if _rect == null:
		_rect = ColorRect.new()
		_rect.name = "AtmosphereRect"
		add_child(_rect)

	_rect.anchors_preset = Control.PRESET_FULL_RECT
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_material = ShaderMaterial.new()
	var shader = load(_shader_path) as Shader
	if shader == null:
		push_warning("HD2DAtmosphere: Shader nicht gefunden: %s" % _shader_path)
		return

	_material.shader = shader
	_rect.material = _material
	_sync_all()


func _p(name: String, value) -> void:
	if _material:
		_material.set_shader_parameter(name, value)


func _sync_all() -> void:
	_p("vignette_enabled", vignette_enabled)
	_p("vignette_intensity", vignette_intensity)
	_p("vignette_size", vignette_size)
	_p("vignette_softness", vignette_softness)
	_p("vignette_color", vignette_color)
	_p("grading_enabled", grading_enabled)
	_p("warmth", warmth)
	_p("contrast", contrast)
	_p("saturation", saturation)
	_p("brightness", brightness)
	_p("ambient_enabled", ambient_enabled)
	_p("ambient_color", ambient_color)
	_p("ambient_strength", ambient_strength)


func _set_vignette_enabled(v): vignette_enabled = v; _p("vignette_enabled", v)
func _set_vignette_intensity(v): vignette_intensity = v; _p("vignette_intensity", v)
func _set_vignette_size(v): vignette_size = v; _p("vignette_size", v)
func _set_vignette_softness(v): vignette_softness = v; _p("vignette_softness", v)
func _set_vignette_color(v): vignette_color = v; _p("vignette_color", v)
func _set_grading_enabled(v): grading_enabled = v; _p("grading_enabled", v)
func _set_warmth(v): warmth = v; _p("warmth", v)
func _set_contrast(v): contrast = v; _p("contrast", v)
func _set_saturation(v): saturation = v; _p("saturation", v)
func _set_brightness(v): brightness = v; _p("brightness", v)
func _set_ambient_enabled(v): ambient_enabled = v; _p("ambient_enabled", v)
func _set_ambient_color(v): ambient_color = v; _p("ambient_color", v)
func _set_ambient_strength(v): ambient_strength = v; _p("ambient_strength", v)

func _set_preset(value: Preset) -> void:
	preset = value
	_apply_preset(value)


func _apply_preset(p: Preset) -> void:
	match p:
		Preset.WARM_DAYLIGHT:
			vignette_enabled = true; vignette_intensity = 0.4; vignette_size = 0.5
			vignette_softness = 0.45; vignette_color = Color(0.05, 0.02, 0.01)
			grading_enabled = true; warmth = 0.08; contrast = 1.05
			saturation = 1.1; brightness = 0.0
			ambient_enabled = true; ambient_color = Color(1.0, 0.92, 0.8)
			ambient_strength = 0.05
		Preset.COOL_FOREST:
			vignette_enabled = true; vignette_intensity = 0.5; vignette_size = 0.45
			vignette_softness = 0.5; vignette_color = Color(0.01, 0.03, 0.05)
			grading_enabled = true; warmth = -0.05; contrast = 1.08
			saturation = 1.15; brightness = -0.02
			ambient_enabled = true; ambient_color = Color(0.85, 0.95, 1.0)
			ambient_strength = 0.06
		Preset.SUNSET:
			vignette_enabled = true; vignette_intensity = 0.55; vignette_size = 0.4
			vignette_softness = 0.5; vignette_color = Color(0.08, 0.02, 0.01)
			grading_enabled = true; warmth = 0.18; contrast = 1.1
			saturation = 1.2; brightness = 0.02
			ambient_enabled = true; ambient_color = Color(1.0, 0.8, 0.6)
			ambient_strength = 0.1
		Preset.DUNGEON:
			vignette_enabled = true; vignette_intensity = 0.8; vignette_size = 0.35
			vignette_softness = 0.5; vignette_color = Color(0.0, 0.0, 0.02)
			grading_enabled = true; warmth = -0.03; contrast = 1.15
			saturation = 0.85; brightness = -0.08
			ambient_enabled = true; ambient_color = Color(0.7, 0.75, 0.9)
			ambient_strength = 0.08
		Preset.NONE:
			vignette_enabled = false; grading_enabled = false; ambient_enabled = false
		Preset.CUSTOM:
			pass
	_sync_all()


func transition_to(target: Preset, duration: float = 1.0) -> void:
	var props := [
		"vignette_intensity", "vignette_size", "vignette_softness",
		"warmth", "contrast", "saturation", "brightness", "ambient_strength"
	]
	var from := {}
	for p in props:
		from[p] = get(p)

	_apply_preset(target)
	var to := {}
	for p in props:
		to[p] = get(p)

	for p in props:
		set(p, from[p])
	_sync_all()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	for p in props:
		tween.tween_property(self, p, to[p], duration)
	preset = target

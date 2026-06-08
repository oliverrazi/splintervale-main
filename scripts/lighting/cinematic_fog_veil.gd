extends CanvasLayer
class_name CinematicFogVeil
## Bildschirmfüllender Nebelvorhang fürs Intro.
##
## Layering: `veil_layer` NIEDRIGER setzen als HUD/Bars, damit diese drueber
## liegen.
##
## Bei reveal = 0 ist der Schirm KOMPLETT opak (nichts sichtbar).
## Beim Hochtweenen loest sich der Nebel noise-artig auf: dünne Stellen zuerst.

@export var fog_shader: Shader
@export var fog_color: Color = Color(0.60, 0.68, 0.78)

## Wabern-Tempo des Veils. 0 = ganz still.
@export_range(0.0, 0.5) var anim_speed: float = 0.03

## Größe der Nebelschwaden. Klein = riesige Wolken, groß = feine Struktur.
@export_range(0.5, 8.0) var noise_scale: float = 2.5

## Wie weich die Aufloesungs-Front ist. Hoch = lange Übergangszone, mehr
## Stellen lösen sich gleichzeitig auf. Niedrig = scharfe Kanten.
@export_range(0.05, 1.0) var softness: float = 0.45

## CanvasLayer-Index. Niedriger als HUD/Bars setzen.
@export var veil_layer: int = 0:
	set(v):
		veil_layer = v
		layer = v

var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = veil_layer

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE

	_mat = ShaderMaterial.new()
	_mat.shader = fog_shader
	_mat.set_shader_parameter("fog_color", fog_color)
	_mat.set_shader_parameter("reveal", 0.0)           # START: alles dicht
	_mat.set_shader_parameter("anim_speed", anim_speed)
	_mat.set_shader_parameter("noise_scale", noise_scale)
	_mat.set_shader_parameter("softness", softness)
	_rect.material = _mat

	add_child(_rect)


## reveal: 0 = komplett opak, 1 = komplett frei.
func tween_reveal(target: float, duration: float) -> void:
	if _mat == null:
		return
	var from: float = _mat.get_shader_parameter("reveal")
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(func(v): _mat.set_shader_parameter("reveal", v), from, target, duration)
	await t.finished


func set_reveal(v: float) -> void:
	if _mat:
		_mat.set_shader_parameter("reveal", v)

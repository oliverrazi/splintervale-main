## SmoothPixelUI
##
## Einfach an ein TextureRect, Sprite2D oder NinePatchRect hängen.
## Wendet automatisch den Smooth-Pixel-Shader an.
##
## WICHTIG: Textur-Import muss auf "Linear" stehen!
## Alternativ: Textur über das "override_texture" Property zuweisen
## (dann wird Linear im Shader erzwungen, Import egal).

@tool
class_name SmoothPixelUI
extends Node

enum FilterAlgorithm {
	SMOOTHSTEP,  ## Weichste Kanten (empfohlen)
	IQ_LINEAR,   ## Etwas schärfer
	FLOOR_FWIDTH,## Minimal, schnellste Variante
}

@export var filter_algorithm: FilterAlgorithm = FilterAlgorithm.SMOOTHSTEP : set = _set_filter
@export_range(0.3, 3.0, 0.1) var aa_sharpness: float = 1.2 : set = _set_aa

## Optional: Textur hier zuweisen erzwingt Linear-Filter (überschreibt Node-Textur).
## Wenn leer, wird die Node-eigene Textur verwendet (Import muss Linear sein!).
@export var override_texture: Texture2D : set = _set_override_texture

var _material: ShaderMaterial
var _shader_path: String = "res://menu/shaders/pixel_art_smooth_2d.gdshader"
var _parent: CanvasItem = null


func _ready() -> void:
	_parent = get_parent() as CanvasItem
	if _parent == null:
		push_warning("SmoothPixelUI: Parent muss ein CanvasItem sein (TextureRect, Sprite2D, etc.)")
		return
	_apply_shader()


func _apply_shader() -> void:
	if _parent == null:
		return

	_material = ShaderMaterial.new()
	var shader = load(_shader_path) as Shader
	if shader == null:
		push_warning("SmoothPixelUI: Shader nicht gefunden: %s" % _shader_path)
		return

	_material.shader = shader
	_material.set_shader_parameter("filter_mode", int(filter_algorithm))
	_material.set_shader_parameter("aa_sharpness", aa_sharpness)

	if override_texture:
		_material.set_shader_parameter("use_node_texture", false)
		_material.set_shader_parameter("sprite_texture", override_texture)
	else:
		_material.set_shader_parameter("use_node_texture", true)

	_parent.material = _material


func _set_filter(value: FilterAlgorithm) -> void:
	filter_algorithm = value
	if _material:
		_material.set_shader_parameter("filter_mode", int(value))


func _set_aa(value: float) -> void:
	aa_sharpness = value
	if _material:
		_material.set_shader_parameter("aa_sharpness", value)


func _set_override_texture(value: Texture2D) -> void:
	override_texture = value
	if _material:
		if value:
			_material.set_shader_parameter("use_node_texture", false)
			_material.set_shader_parameter("sprite_texture", value)
		else:
			_material.set_shader_parameter("use_node_texture", true)

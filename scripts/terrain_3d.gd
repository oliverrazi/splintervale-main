@tool
extends Terrain3D

## aktiviert/ deaktiviert den Autoshader generell
@export var enable_auto_shader := true:
	set(value):
		enable_auto_shader = value
		_apply_settings()

## 0.0 = sehr weich, 1.0 = sehr harte Kante
@export_range(0.0, 1.0, 0.01)
var blend_sharpness := 0.95:
	set(value):
		blend_sharpness = value
		_apply_settings()

## Height-based Blending (für weichere Übergänge) an/aus
@export var height_blending := false:
	set(value):
		height_blending = value
		_apply_settings()

func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_settings()

func _apply_settings() -> void:
	if material == null:
		return

	# Autoshader in der Material-Resource aktivieren
	material.auto_shader = enable_auto_shader

	# interne Shader-Parameter setzen (Namen müssen exakt stimmen)
	material.set_shader_param("blend_sharpness", blend_sharpness)
	material.set_shader_param("height_blending", height_blending)

	# Material neu in den Shader schieben
	material.update()

# hd2d_sprite.gd
extends Node3D
class_name HD2DSprite

@export var texture: Texture2D:
	set(value):
		texture = value
		_update_texture()

@export var hframes: int = 1
@export var vframes: int = 1
@export var frame: int = 0:
	set(value):
		frame = value
		_update_frame()

@export var pixel_size: float = 0.01
@export var flip_h: bool = false:
	set(value):
		flip_h = value
		if _mesh:
			_material.set_shader_parameter("flip_h", flip_h)

@export_group("HD-2D Korrektur")
@export_range(0.0, 1.0) var correction_strength: float = 0.6

var _mesh: MeshInstance3D
var _material: ShaderMaterial


func _ready() -> void:
	_create_mesh()
	_update_texture()


func _create_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.orientation = PlaneMesh.FACE_Z
	_mesh.mesh = quad
	
	_material = ShaderMaterial.new()
	_material.shader = preload("res://assets/characters/npcs/hd2d_sprite.gdshader")
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(_mesh)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	
	# Bildschirmposition berechnen
	var screen_pos := camera.unproject_position(global_position)
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_y :float = clamp(screen_pos.y / viewport_size.y, 0.0, 1.0)
	
	_material.set_shader_parameter("screen_y", screen_y)
	_material.set_shader_parameter("correction_strength", correction_strength)


func _update_texture() -> void:
	if _material == null or texture == null:
		return
	_material.set_shader_parameter("sprite_texture", texture)
	_update_frame()


func _update_frame() -> void:
	if _material == null or texture == null:
		return
	
	var tex_size := texture.get_size()
	var fw := tex_size.x / float(hframes)
	var fh := tex_size.y / float(vframes)
	
	(_mesh.mesh as QuadMesh).size = Vector2(fw, fh) * pixel_size
	
	var fx := frame % hframes
	var fy := frame / hframes
	_material.set_shader_parameter("frame_size", Vector2(1.0 / hframes, 1.0 / vframes))
	_material.set_shader_parameter("frame_offset", Vector2(float(fx) / hframes, float(fy) / vframes))

extends Node

var _player: Node3D
var _camera: Camera3D
var _material_cache: Dictionary = {}  # source-material-id -> ShaderMaterial

@export_group("Shader Resources")
@export var occlusion_shader: Shader = preload("res://assets/base_tiles/trees/tree_occlusion.gdshader")
@export var edge_noise: Texture2D = preload("res://assets/base_tiles/trees/edge_noise.tres")  # falls du den Pfad weißt

@export_group("Occlusion")
@export var occlusion_radius      := 2.5
@export var occlusion_softness    := 1.5
@export var min_alpha             := 0.0
@export var height_threshold      := -0.3
@export var height_softness       := 0.6
@export var behind_player_falloff := 1.0

@export_group("Polish")
@export var noise_strength    := 0.15
@export var noise_strength_2  := 0.10
@export var wobble_speed      := 0.15
@export var wobble_scale      := 0.12
@export var rim_strength      := 0.0


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	RenderingServer.global_shader_parameter_set("player_world_position", Vector3(99999.0, 0.0, 99999.0))
	RenderingServer.global_shader_parameter_set("camera_world_position", Vector3(99999.0, 0.0, 99999.0))

func register_player(player: Node3D) -> void:
	_player = player

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null: return
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if _camera == null: return
	RenderingServer.global_shader_parameter_set("player_world_position", _player.global_position)
	RenderingServer.global_shader_parameter_set("camera_world_position", _camera.global_position)

## Liefert ein ShaderMaterial für das Quellmaterial - cached nach erstem Aufruf.
func get_or_create_material(source: BaseMaterial3D) -> ShaderMaterial:
	if source == null:
		return null
	var key := source.get_instance_id()
	if _material_cache.has(key):
		return _material_cache[key]

	var sm := ShaderMaterial.new()
	sm.shader = occlusion_shader

	# Quell-spezifisch
	sm.set_shader_parameter("albedo_texture", source.albedo_texture)
	sm.set_shader_parameter("albedo_color",   source.albedo_color)
	sm.set_shader_parameter("roughness",      source.roughness)
	sm.set_shader_parameter("metallic",       source.metallic)
	sm.set_shader_parameter("specular",       source.metallic_specular)

	# Global geteilt
	sm.set_shader_parameter("edge_noise",            edge_noise)
	sm.set_shader_parameter("occlusion_radius",      occlusion_radius)
	sm.set_shader_parameter("occlusion_softness",    occlusion_softness)
	sm.set_shader_parameter("min_alpha",             min_alpha)
	sm.set_shader_parameter("height_threshold",      height_threshold)
	sm.set_shader_parameter("height_softness",       height_softness)
	sm.set_shader_parameter("behind_player_falloff", behind_player_falloff)
	sm.set_shader_parameter("noise_strength",        noise_strength)
	sm.set_shader_parameter("noise_strength_2",      noise_strength_2)
	sm.set_shader_parameter("wobble_speed",          wobble_speed)
	sm.set_shader_parameter("wobble_scale",          wobble_scale)
	sm.set_shader_parameter("rim_strength",          rim_strength)

	_material_cache[key] = sm
	return sm

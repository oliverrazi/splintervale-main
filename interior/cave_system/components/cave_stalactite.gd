## CaveStalactite — Overhead ceiling decoration rendered above the player layer.
##
## In 2.5D top-down, stalactites are sprites positioned at a high Y value
## so they render "on top of" the player, creating the illusion of
## overhanging cave ceiling. They can also cast shadows on the floor.
##
## This component handles:
##   • Sprite setup with correct render ordering
##   • Optional shadow projection on the floor below
##   • Drip particle effect (water drops falling from the tip)
##   • Gentle sway animation

class_name CaveStalactite
extends Node3D

@export_group("Appearance")
@export var stalactite_texture: Texture2D = null
@export var stalactite_shader: Shader = null  # cave_stalactite.gdshader
@export var tint: Color = Color(0.2, 0.19, 0.18)
@export var sprite_size: float = 1.0
@export var pixel_size: float = 0.01
## Y height of the stalactite. Higher = more "on top" of the player.
@export var height: float = 3.0
@export var opacity: float = 0.9

@export_group("Shadow")
@export var cast_shadow: bool = true
@export var shadow_opacity: float = 0.25
@export var shadow_scale: float = 0.7
@export var shadow_y: float = 0.01  # Just above floor

@export_group("Drip")
@export var drip_enabled: bool = true
@export var drip_interval_min: float = 3.0
@export var drip_interval_max: float = 8.0
@export var drip_color: Color = Color(0.4, 0.5, 0.6, 0.6)

@export_group("Animation")
@export var sway_enabled: bool = false
@export var sway_amount: float = 0.02
@export var sway_speed: float = 1.5

var _sprite: Sprite3D
var _shadow_sprite: Sprite3D
var _drip_timer: float
var _drip_particles: GPUParticles3D


func _ready() -> void:
	_create_stalactite_sprite()
	if cast_shadow and stalactite_texture:
		_create_shadow()
	if drip_enabled:
		_create_drip_system()
		_drip_timer = randf_range(drip_interval_min, drip_interval_max)


func _process(delta: float) -> void:
	# Sway animation
	if sway_enabled and _sprite:
		var sway := sin((Time.get_ticks_msec() / 1000.0) * sway_speed + global_position.x * 2.0) * sway_amount
		_sprite.position.x = sway

	# Drip timer
	if drip_enabled and _drip_particles:
		_drip_timer -= delta
		if _drip_timer <= 0:
			_drip_timer = randf_range(drip_interval_min, drip_interval_max)
			_emit_drip()


func _create_stalactite_sprite() -> void:
	_sprite = Sprite3D.new()
	_sprite.name = "StalactiteSprite"
	if stalactite_texture:
		_sprite.texture = stalactite_texture
	_sprite.pixel_size = pixel_size
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_sprite.render_priority = 10  # Render above player
	_sprite.position.y = height
	_sprite.scale = Vector3.ONE * sprite_size

	# Apply shader or simple material
	if stalactite_shader:
		var mat := ShaderMaterial.new()
		mat.shader = stalactite_shader
		mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		mat.set_shader_parameter("opacity", opacity)
		mat.set_shader_parameter("enable_sway", sway_enabled)
		mat.set_shader_parameter("sway_amount", sway_amount)
		mat.set_shader_parameter("sway_speed", sway_speed)
		mat.set_shader_parameter("brightness", 0.5)
		_sprite.material_override = mat
	else:
		_sprite.modulate = Color(tint.r, tint.g, tint.b, opacity)
		_sprite.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	add_child(_sprite)


func _create_shadow() -> void:
	# A darkened, flattened copy of the sprite on the floor
	_shadow_sprite = Sprite3D.new()
	_shadow_sprite.name = "StalactiteShadow"
	if stalactite_texture:
		_shadow_sprite.texture = stalactite_texture
	_shadow_sprite.pixel_size = pixel_size
	_shadow_sprite.modulate = Color(0, 0, 0, shadow_opacity)
	_shadow_sprite.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_shadow_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_shadow_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED

	# Position on the floor, slightly scaled
	_shadow_sprite.position.y = shadow_y
	_shadow_sprite.scale = Vector3.ONE * sprite_size * shadow_scale
	# Rotate to lay flat on the ground
	_shadow_sprite.rotation.x = -PI / 2.0

	add_child(_shadow_sprite)


func _create_drip_system() -> void:
	_drip_particles = GPUParticles3D.new()
	_drip_particles.name = "DripParticles"
	_drip_particles.amount = 3
	_drip_particles.lifetime = 0.8
	_drip_particles.one_shot = true
	_drip_particles.explosiveness = 1.0
	_drip_particles.emitting = false
	_drip_particles.position.y = height - (sprite_size * 0.5)  # Tip of stalactite

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -8.0, 0)
	mat.spread = 5.0
	mat.scale_min = 0.01
	mat.scale_max = 0.025
	mat.color = drip_color

	# Fade trail
	var ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.add_point(0.0, drip_color)
	grad.add_point(0.8, drip_color)
	grad.add_point(1.0, Color(drip_color.r, drip_color.g, drip_color.b, 0.0))
	ramp.gradient = grad
	mat.color_ramp = ramp

	_drip_particles.process_material = mat

	# Elongated particle for drip look
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.06)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = draw_mat
	_drip_particles.draw_pass_1 = quad

	add_child(_drip_particles)


func _emit_drip() -> void:
	if _drip_particles:
		_drip_particles.restart()
		_drip_particles.emitting = true

## CaveAtmosphere — Manages all atmospheric particle effects inside a cave.
##
## Automatically creates and manages:
##   • Floating dust motes (always present)
##   • Water drip particles (near water sources)
##   • Ground-level mist / fog particles
##   • Light beam dust (where light enters)
##   • Firefly / bioluminescent particles (optional)
##
## Add as a child of your CaveSystem node.
## Particles follow the camera / player automatically.

class_name CaveAtmosphere
extends Node3D

# ── Configuration ─────────────────────────────────────────────────────────────

@export_group("Dust Motes")
@export var dust_enabled: bool = true
@export var dust_amount: int = 40
@export var dust_area_size: Vector3 = Vector3(16, 6, 16)
@export var dust_color: Color = Color(0.35, 0.33, 0.3, 0.15)
@export var dust_size_range: Vector2 = Vector2(0.02, 0.06)

@export_group("Water Drips")
@export var drips_enabled: bool = true
@export var drip_amount: int = 8
@export var drip_area_size: Vector3 = Vector3(12, 4, 12)
@export var drip_color: Color = Color(0.4, 0.5, 0.6, 0.5)

@export_group("Ground Mist")
@export var mist_enabled: bool = true
@export var mist_amount: int = 20
@export var mist_area_size: Vector3 = Vector3(20, 0.5, 20)
@export var mist_color: Color = Color(0.12, 0.13, 0.15, 0.12)
@export var mist_height: float = 0.1

@export_group("Bioluminescence")
@export var fireflies_enabled: bool = false
@export var firefly_amount: int = 12
@export var firefly_color: Color = Color(0.3, 0.8, 0.5, 0.6)
@export var firefly_area_size: Vector3 = Vector3(14, 3, 14)

@export_group("Performance")
## Camera reference — particles follow this. If null, tries to find one automatically.
@export var camera_target: Camera3D = null
## Update interval for repositioning particles around camera.
@export var follow_interval: float = 0.5

var _follow_timer: float = 0.0
var _dust_particles: GPUParticles3D
var _drip_particles: GPUParticles3D
var _mist_particles: GPUParticles3D
var _firefly_particles: GPUParticles3D


func _ready() -> void:
	if dust_enabled:
		_dust_particles = _create_dust_system()
		add_child(_dust_particles)

	if drips_enabled:
		_drip_particles = _create_drip_system()
		add_child(_drip_particles)

	if mist_enabled:
		_mist_particles = _create_mist_system()
		add_child(_mist_particles)

	if fireflies_enabled:
		_firefly_particles = _create_firefly_system()
		add_child(_firefly_particles)


func _process(delta: float) -> void:
	# Follow camera/player position so particles are always around the visible area
	_follow_timer += delta
	if _follow_timer >= follow_interval:
		_follow_timer = 0.0
		_update_particle_positions()


func _update_particle_positions() -> void:
	if not camera_target:
		camera_target = get_viewport().get_camera_3d()
	if not camera_target:
		return

	# For top-down 2.5D, we want particles centered on the camera's look-at point
	# which is roughly the player position
	var player := get_tree().get_first_node_in_group("player")
	var center: Vector3
	if player:
		center = player.global_position
	else:
		center = camera_target.global_position

	global_position = center


# ═══════════════════════════════════════════════════════════════════════════════
# PARTICLE SYSTEM BUILDERS
# ═══════════════════════════════════════════════════════════════════════════════

func _create_dust_system() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "DustMotes"
	particles.amount = dust_amount
	particles.lifetime = 6.0
	particles.explosiveness = 0.0
	particles.randomness = 0.8
	particles.fixed_fps = 30
	particles.visibility_aabb = AABB(-dust_area_size / 2, dust_area_size)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = dust_area_size / 2.0

	# Slow, drifting movement
	mat.direction = Vector3(0, 0.2, 0)
	mat.initial_velocity_min = 0.02
	mat.initial_velocity_max = 0.08
	mat.gravity = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.angular_velocity_min = -20.0
	mat.angular_velocity_max = 20.0

	# Gentle turbulence
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.3
	mat.turbulence_noise_speed_random = 0.5
	mat.turbulence_noise_scale = 4.0
	mat.turbulence_influence_min = 0.1
	mat.turbulence_influence_max = 0.3

	mat.scale_min = dust_size_range.x
	mat.scale_max = dust_size_range.y

	# Fade in/out
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.add_point(0.0, Color(dust_color.r, dust_color.g, dust_color.b, 0.0))
	grad.add_point(0.2, dust_color)
	grad.add_point(0.8, dust_color)
	grad.add_point(1.0, Color(dust_color.r, dust_color.g, dust_color.b, 0.0))
	color_ramp.gradient = grad
	mat.color_ramp = color_ramp

	particles.process_material = mat
	particles.draw_pass_1 = _make_particle_quad(dust_size_range.y * 10.0)
	return particles


func _create_drip_system() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "WaterDrips"
	particles.amount = drip_amount
	particles.lifetime = 1.2
	particles.explosiveness = 0.0
	particles.randomness = 0.9
	particles.fixed_fps = 30
	particles.visibility_aabb = AABB(-drip_area_size / 2, drip_area_size)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(drip_area_size.x / 2, 0.1, drip_area_size.z / 2)

	# Drips fall straight down
	mat.direction = Vector3(0, -1, 0)
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -6.0, 0)
	mat.spread = 3.0

	mat.scale_min = 0.015
	mat.scale_max = 0.03

	# Start from ceiling height
	particles.position.y = drip_area_size.y / 2.0

	# Fade trail
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.add_point(0.0, drip_color)
	grad.add_point(0.7, drip_color)
	grad.add_point(1.0, Color(drip_color.r, drip_color.g, drip_color.b, 0.0))
	color_ramp.gradient = grad
	mat.color_ramp = color_ramp

	particles.process_material = mat
	particles.draw_pass_1 = _make_particle_quad(0.08, true)  # Elongated for drip look
	return particles


func _create_mist_system() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "GroundMist"
	particles.amount = mist_amount
	particles.lifetime = 8.0
	particles.explosiveness = 0.0
	particles.randomness = 0.6
	particles.fixed_fps = 20
	particles.position.y = mist_height
	particles.visibility_aabb = AABB(-mist_area_size / 2, mist_area_size)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(mist_area_size.x / 2, 0.05, mist_area_size.z / 2)

	# Very slow horizontal drift
	mat.direction = Vector3(1, 0, 0.3)
	mat.initial_velocity_min = 0.02
	mat.initial_velocity_max = 0.1
	mat.gravity = Vector3(0, 0, 0)
	mat.spread = 90.0

	mat.scale_min = 1.5
	mat.scale_max = 3.5

	# Turbulence for organic flow
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.15
	mat.turbulence_noise_speed_random = 0.3
	mat.turbulence_noise_scale = 6.0

	# Very subtle fade
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.add_point(0.0, Color(mist_color.r, mist_color.g, mist_color.b, 0.0))
	grad.add_point(0.15, mist_color)
	grad.add_point(0.85, mist_color)
	grad.add_point(1.0, Color(mist_color.r, mist_color.g, mist_color.b, 0.0))
	color_ramp.gradient = grad
	mat.color_ramp = color_ramp

	particles.process_material = mat
	particles.draw_pass_1 = _make_particle_quad(3.5)
	return particles


func _create_firefly_system() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Bioluminescence"
	particles.amount = firefly_amount
	particles.lifetime = 5.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0
	particles.fixed_fps = 30
	particles.visibility_aabb = AABB(-firefly_area_size / 2, firefly_area_size)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = firefly_area_size / 2.0

	# Lazy, wandering movement
	mat.direction = Vector3(0, 0.3, 0)
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.15
	mat.gravity = Vector3(0, 0, 0)
	mat.spread = 180.0

	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.6
	mat.turbulence_noise_speed_random = 0.8
	mat.turbulence_noise_scale = 3.0
	mat.turbulence_influence_min = 0.3
	mat.turbulence_influence_max = 0.7

	mat.scale_min = 0.04
	mat.scale_max = 0.1

	# Pulsing glow — fades in and out
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.add_point(0.0, Color(firefly_color.r, firefly_color.g, firefly_color.b, 0.0))
	grad.add_point(0.15, firefly_color)
	grad.add_point(0.5, Color(firefly_color.r, firefly_color.g, firefly_color.b, firefly_color.a * 0.3))
	grad.add_point(0.7, firefly_color)
	grad.add_point(1.0, Color(firefly_color.r, firefly_color.g, firefly_color.b, 0.0))
	color_ramp.gradient = grad
	mat.color_ramp = color_ramp

	particles.process_material = mat

	# Fireflies get an additive-blended quad for glow
	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.albedo_color = Color.WHITE
	quad.material = draw_mat
	particles.draw_pass_1 = quad

	return particles


# ── Utility ───────────────────────────────────────────────────────────────────

func _make_particle_quad(size: float, elongated: bool = false) -> QuadMesh:
	var quad := QuadMesh.new()
	if elongated:
		quad.size = Vector2(size * 0.3, size)
	else:
		quad.size = Vector2(size, size)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = false
	quad.material = mat

	return quad


## Dynamically enable/disable subsystems (e.g., near water, enable drips).
func set_drips_active(active: bool) -> void:
	if _drip_particles:
		_drip_particles.emitting = active

func set_mist_active(active: bool) -> void:
	if _mist_particles:
		_mist_particles.emitting = active

func set_fireflies_active(active: bool) -> void:
	if _firefly_particles:
		_firefly_particles.emitting = active

## CaveLightingRig — Dramatic, cinematic lighting setup for AAA cave scenes.
##
## Inspired by the reference screenshot where a strong directional/spot light
## casts from above, creating dramatic shadows and a focused pool of light
## on the cave floor while everything else falls into darkness.
##
## This system manages:
##   • Primary spotlight (the main "cave opening" light beam)
##   • Shadow-casting configuration optimized for caves
##   • Fill lights for subtle visibility in dark areas
##   • Post-processing: vignette, color grading, depth of field
##   • Light beam volumetric effect (god rays approximation)
##   • Dynamic adjustment based on player position (optional)
##
## Add this as a child of CaveSystem, alongside CaveLightingManager.
## This handles the "big picture" lighting; CaveLightingManager handles
## individual torches/crystals.

class_name CaveLightingRig
extends Node3D

# ── Configuration ─────────────────────────────────────────────────────────────

@export_group("Primary Spotlight")
## Enable the dramatic overhead spotlight.
@export var spotlight_enabled: bool = true
## World position of the spotlight (typically high above a cave opening).
@export var spotlight_position: Vector3 = Vector3(0, 8, -2)
## Direction the spotlight points. Default: straight down with slight angle.
@export var spotlight_direction: Vector3 = Vector3(0, -1, 0.15)
## Spotlight color — warm for torchlit, cool-white for moonlight/skylight.
@export var spotlight_color: Color = Color(0.85, 0.82, 0.75)
## Spotlight energy (brightness). 2-4 for dramatic effect.
@export var spotlight_energy: float = 3.0
## Cone angle in degrees. Smaller = more focused beam.
@export_range(5.0, 90.0) var spotlight_angle: float = 35.0
## Attenuation — how quickly light falls off. Higher = sharper falloff.
@export_range(0.1, 4.0) var spotlight_attenuation: float = 1.2
## Range of the spotlight.
@export var spotlight_range: float = 15.0
## Enable shadows from the spotlight (expensive but dramatic).
@export var spotlight_shadows: bool = true

@export_group("Fill Light")
## Subtle ambient fill so players can barely see in dark areas.
@export var fill_enabled: bool = true
## Fill light color — cool blue for underground feel.
@export var fill_color: Color = Color(0.08, 0.10, 0.15)
## Fill energy — very low, just enough to see shapes.
@export var fill_energy: float = 0.08
## Height of the fill light above the scene.
@export var fill_height: float = 6.0

@export_group("Post-Processing")
## Enable cinematic vignette (darkened edges).
@export var vignette_enabled: bool = true
## Vignette intensity (0 = none, 1 = very dark edges).
@export_range(0.0, 1.0) var vignette_intensity: float = 0.45
## Vignette softness (how gradual the darkening is).
@export_range(0.1, 2.0) var vignette_softness: float = 0.6

@export_group("Color Grading")
## Overall scene color temperature. < 0 = cooler, > 0 = warmer.
@export_range(-1.0, 1.0) var color_temperature: float = -0.15
## Saturation adjustment. < 1 = desaturated (moody), > 1 = vivid.
@export_range(0.0, 2.0) var saturation: float = 0.75
## Contrast boost for dramatic shadows.
@export_range(0.5, 2.0) var contrast: float = 1.15

@export_group("Depth of Field")
## Enable DoF blur for depth. Subtle use makes it cinematic.
@export var dof_enabled: bool = false
## Distance from camera that is in focus.
@export var dof_focus_distance: float = 8.0
## How blurry the out-of-focus areas get.
@export_range(0.0, 2.0) var dof_blur_amount: float = 0.3

@export_group("Volumetric Light Beam")
## Simulate a light beam / god ray from the spotlight.
@export var light_beam_enabled: bool = true
## Beam opacity.
@export_range(0.0, 0.5) var beam_opacity: float = 0.08
## Beam color (usually matches spotlight with lower saturation).
@export var beam_color: Color = Color(0.7, 0.68, 0.6, 0.08)
## Number of dust particles in the beam.
@export var beam_dust_amount: int = 30

@export_group("Player Follow")
## If true, the spotlight subtly follows the player (like a dynamic light well).
@export var follow_player: bool = false
## How quickly the light follows (0 = instant, higher = more lag).
@export var follow_smoothing: float = 3.0

# ── Internal ──────────────────────────────────────────────────────────────────

var _spotlight: SpotLight3D
var _fill_light: DirectionalLight3D
var _beam_particles: GPUParticles3D
var _beam_mesh: MeshInstance3D
var _vignette_overlay: CanvasLayer
var _env: Environment
var _player: Node3D
var _target_spotlight_pos: Vector3


func _ready() -> void:
	_target_spotlight_pos = spotlight_position

	if spotlight_enabled:
		_create_spotlight()
	if fill_enabled:
		_create_fill_light()
	if light_beam_enabled:
		_create_light_beam()
	_apply_post_processing()
	if vignette_enabled:
		_create_vignette_overlay()


func _process(delta: float) -> void:
	if follow_player and _spotlight:
		if not _player:
			_player = get_tree().get_first_node_in_group("player")
		if _player:
			# Move spotlight toward player XZ, keep the Y height
			_target_spotlight_pos.x = _player.global_position.x + spotlight_position.x
			_target_spotlight_pos.z = _player.global_position.z + spotlight_position.z
			_spotlight.global_position = _spotlight.global_position.lerp(
				_target_spotlight_pos, delta * follow_smoothing)


# ═══════════════════════════════════════════════════════════════════════════════
# SPOTLIGHT — The Hero Light
# ═══════════════════════════════════════════════════════════════════════════════

func _create_spotlight() -> void:
	_spotlight = SpotLight3D.new()
	_spotlight.name = "CaveSpotlight"
	_spotlight.light_color = spotlight_color
	_spotlight.light_energy = spotlight_energy
	_spotlight.spot_range = spotlight_range
	_spotlight.spot_angle = spotlight_angle
	_spotlight.spot_attenuation = spotlight_attenuation

	# Position and direction
	_spotlight.position = spotlight_position
	# Look in the configured direction
	var target := spotlight_position + spotlight_direction.normalized() * 5.0
	_spotlight.look_at(target, Vector3.UP)

	# Shadow configuration — critical for drama
	_spotlight.shadow_enabled = spotlight_shadows
	if spotlight_shadows:
		_spotlight.shadow_bias = 0.03
		_spotlight.shadow_normal_bias = 2.0
		# Higher shadow resolution for crisp shadows
		_spotlight.shadow_blur = 0.8

	# Light parameters for realistic falloff
	_spotlight.light_indirect_energy = 0.3
	_spotlight.light_volumetric_fog_energy = 1.0
	_spotlight.light_angular_distance = 0.0  # Point light (sharp shadow edges)

	add_child(_spotlight)


# ═══════════════════════════════════════════════════════════════════════════════
# FILL LIGHT — Subtle Ambient Visibility
# ═══════════════════════════════════════════════════════════════════════════════

func _create_fill_light() -> void:
	_fill_light = DirectionalLight3D.new()
	_fill_light.name = "CaveFillLight"
	_fill_light.light_color = fill_color
	_fill_light.light_energy = fill_energy
	_fill_light.shadow_enabled = false  # Fill doesn't need shadows

	# Point slightly downward and to the side
	_fill_light.rotation.x = -PI * 0.4
	_fill_light.rotation.y = PI * 0.15
	_fill_light.position.y = fill_height

	# Very soft, non-directional feel
	_fill_light.light_indirect_energy = 0.0
	_fill_light.light_angular_distance = 3.0  # Soft shadow if enabled

	add_child(_fill_light)


# ═══════════════════════════════════════════════════════════════════════════════
# LIGHT BEAM / GOD RAYS (Particle-based)
# ═══════════════════════════════════════════════════════════════════════════════

func _create_light_beam() -> void:
	if not spotlight_enabled:
		return

	# ── Beam cone mesh (translucent cone to simulate volumetric light) ──
	_beam_mesh = MeshInstance3D.new()
	_beam_mesh.name = "LightBeamCone"

	# Create a cylinder that narrows = cone shape
	var cone := CylinderMesh.new()
	cone.top_radius = 0.2  # Narrow at the light source
	cone.bottom_radius = tan(deg_to_rad(spotlight_angle)) * spotlight_range * 0.5
	cone.height = spotlight_range * 0.7
	cone.radial_segments = 12
	cone.rings = 1
	_beam_mesh.mesh = cone

	# Position at spotlight, pointing down
	_beam_mesh.position = spotlight_position
	_beam_mesh.position.y -= cone.height * 0.5

	# Translucent additive material
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = beam_color
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.no_depth_test = false
	beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_beam_mesh.material_override = beam_mat
	_beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(_beam_mesh)

	# ── Dust particles floating in the beam ──
	_beam_particles = GPUParticles3D.new()
	_beam_particles.name = "BeamDust"
	_beam_particles.amount = beam_dust_amount
	_beam_particles.lifetime = 4.0
	_beam_particles.explosiveness = 0.0
	_beam_particles.randomness = 0.8
	_beam_particles.fixed_fps = 30
	_beam_particles.position = spotlight_position
	_beam_particles.position.y -= spotlight_range * 0.35

	var beam_radius := tan(deg_to_rad(spotlight_angle)) * spotlight_range * 0.3
	var vis_size := Vector3(beam_radius * 2, spotlight_range * 0.8, beam_radius * 2)
	_beam_particles.visibility_aabb = AABB(-vis_size / 2, vis_size)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(beam_radius, spotlight_range * 0.3, beam_radius)

	# Slow drift
	mat.direction = Vector3(0, -0.3, 0)
	mat.initial_velocity_min = 0.02
	mat.initial_velocity_max = 0.08
	mat.gravity = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.scale_min = 0.02
	mat.scale_max = 0.06

	# Turbulence for organic movement
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.2
	mat.turbulence_noise_speed_random = 0.4
	mat.turbulence_noise_scale = 4.0

	# Color — bright when in beam, fade at edges
	var dust_color := Color(spotlight_color.r, spotlight_color.g, spotlight_color.b, 0.25 * beam_opacity * 10.0)
	var ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.add_point(0.0, Color(dust_color.r, dust_color.g, dust_color.b, 0.0))
	grad.add_point(0.15, dust_color)
	grad.add_point(0.85, dust_color)
	grad.add_point(1.0, Color(dust_color.r, dust_color.g, dust_color.b, 0.0))
	ramp.gradient = grad
	mat.color_ramp = ramp

	_beam_particles.process_material = mat

	# Additive blended quads
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = draw_mat
	_beam_particles.draw_pass_1 = quad

	add_child(_beam_particles)


# ═══════════════════════════════════════════════════════════════════════════════
# POST-PROCESSING — Vignette, Color Grading, DoF
# ═══════════════════════════════════════════════════════════════════════════════

func _apply_post_processing() -> void:
	## Finds the WorldEnvironment in the scene and applies cinematic settings.
	var world_env := _find_world_environment()
	if not world_env:
		push_warning("CaveLightingRig: No WorldEnvironment found. "
			+ "Post-processing settings won't be applied.")
		return

	_env = world_env.environment
	if not _env:
		_env = Environment.new()
		world_env.environment = _env

	# ── Tonemap — ACES for cinematic contrast ──
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.0
	_env.tonemap_white = 1.5  # Bright areas stay bright

	# ── Glow — for light bloom effect ──
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_strength = 0.9
	_env.glow_bloom = 0.15
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.glow_hdr_threshold = 0.8
	_env.set_glow_level(0, true)
	_env.set_glow_level(1, true)
	_env.set_glow_level(2, true)
	_env.set_glow_level(3, true)
	_env.set_glow_level(4, false)

	# ── Adjustments (color grading) ──
	_env.adjustment_enabled = true
	_env.adjustment_brightness = 1.0
	_env.adjustment_contrast = contrast
	_env.adjustment_saturation = saturation

	# ── Color temperature via color correction ──
	# (Godot doesn't have a direct temperature slider, so we use adjustment)
	# We shift the ambient slightly:
	if color_temperature < 0:
		# Cooler — shift ambient toward blue
		_env.ambient_light_color = _env.ambient_light_color.lerp(
			Color(0.05, 0.07, 0.12), abs(color_temperature))
	else:
		# Warmer — shift toward orange
		_env.ambient_light_color = _env.ambient_light_color.lerp(
			Color(0.15, 0.10, 0.06), color_temperature)

	# ── SSAO — depth in crevices ──
	_env.ssao_enabled = true
	_env.ssao_radius = 0.5
	_env.ssao_intensity = 2.0
	_env.ssao_power = 1.5
	_env.ssao_detail = 0.5
	_env.ssao_light_affect = 0.3

	# ── SSIL — subtle indirect lighting bounce ──
	_env.ssil_enabled = true
	_env.ssil_radius = 3.0
	_env.ssil_intensity = 0.5
	_env.ssil_normal_rejection = 1.0

	# ── Depth of Field ──
	if dof_enabled:
		# Far DoF blur (things behind focus point)
		_env.dof_blur_far_enabled = true
		_env.dof_blur_far_distance = dof_focus_distance + 5.0
		_env.dof_blur_far_transition = 3.0
		# Near DoF blur (things in front of focus point)
		_env.dof_blur_near_enabled = true
		_env.dof_blur_near_distance = max(1.0, dof_focus_distance - 3.0)
		_env.dof_blur_near_transition = 2.0
		_env.dof_blur_amount = dof_blur_amount

	# ── Fog — subtle atmospheric depth ──
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.03, 0.035, 0.05)
	_env.fog_light_energy = 0.15
	_env.fog_density = 0.01


# ═══════════════════════════════════════════════════════════════════════════════
# VIGNETTE (Screen-Space Overlay)
# ═══════════════════════════════════════════════════════════════════════════════

func _create_vignette_overlay() -> void:
	## Creates a screen-space vignette using a shader on a ColorRect.
	_vignette_overlay = CanvasLayer.new()
	_vignette_overlay.name = "VignetteLayer"
	_vignette_overlay.layer = 90  # Below fade overlay (100) but above game

	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = _get_vignette_shader_code()

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("intensity", vignette_intensity)
	mat.set_shader_parameter("softness", vignette_softness)
	mat.set_shader_parameter("color", Vector3(0.0, 0.0, 0.0))
	rect.material = mat

	_vignette_overlay.add_child(rect)
	add_child(_vignette_overlay)


func _get_vignette_shader_code() -> String:
	return """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.45;
uniform float softness : hint_range(0.1, 2.0) = 0.6;
uniform vec3 color : source_color = vec3(0.0, 0.0, 0.0);
uniform float roundness : hint_range(0.5, 2.0) = 1.0;

void fragment() {
	vec2 uv = UV;
	vec2 center = vec2(0.5);
	
	// Elliptical distance from center
	vec2 dist = (uv - center) * vec2(roundness, 1.0);
	float d = length(dist) * 2.0;
	
	// Smooth vignette curve
	float vignette = smoothstep(1.0 - softness, 1.0 + softness * 0.5, d);
	vignette *= intensity;
	
	COLOR = vec4(color, vignette);
}
"""


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

## Move the spotlight to a new position (e.g., for a different cave room).
func move_spotlight_to(pos: Vector3, duration: float = 1.5) -> void:
	if not _spotlight:
		return
	var tween := create_tween()
	tween.tween_property(_spotlight, "position", pos, duration)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	if _beam_mesh:
		tween.parallel().tween_property(_beam_mesh, "position",
			Vector3(pos.x, pos.y - (_beam_mesh.mesh.get("height") if _beam_mesh.mesh.get("height") else 5.0) * 0.5, pos.z),
			duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	if _beam_particles:
		tween.parallel().tween_property(_beam_particles, "position",
			Vector3(pos.x, pos.y - spotlight_range * 0.35, pos.z),
			duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)


## Change spotlight intensity (e.g., when torch is lit/extinguished).
func set_spotlight_intensity(energy: float, duration: float = 0.5) -> void:
	if not _spotlight:
		return
	var tween := create_tween()
	tween.tween_property(_spotlight, "light_energy", energy, duration)


## Change vignette intensity (e.g., darker when entering deep cave).
func set_vignette(new_intensity: float, duration: float = 1.0) -> void:
	if not _vignette_overlay:
		return
	var rect: ColorRect = _vignette_overlay.get_child(0)
	if rect and rect.material is ShaderMaterial:
		var tween := create_tween()
		tween.tween_method(
			func(val: float): rect.material.set_shader_parameter("intensity", val),
			rect.material.get_shader_parameter("intensity"),
			new_intensity,
			duration
		)


## Dramatically change the cave mood (e.g., boss room reveal).
func dramatic_reveal(target_energy: float = 5.0, duration: float = 2.0) -> void:
	if _spotlight:
		var tween := create_tween()
		# Brief flash then settle
		tween.tween_property(_spotlight, "light_energy", target_energy * 1.5, duration * 0.2)
		tween.tween_property(_spotlight, "light_energy", target_energy, duration * 0.8)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	if _env:
		# Brief bloom surge
		var old_bloom := _env.glow_bloom
		var tween2 := create_tween()
		tween2.tween_property(_env, "glow_bloom", 0.5, duration * 0.3)
		tween2.tween_property(_env, "glow_bloom", old_bloom, duration * 0.7)


## Enable/disable volumetric beam.
func set_beam_visible(visible_state: bool) -> void:
	if _beam_mesh:
		_beam_mesh.visible = visible_state
	if _beam_particles:
		_beam_particles.emitting = visible_state


# ── Utility ───────────────────────────────────────────────────────────────────

func _find_world_environment() -> WorldEnvironment:
	# Search up the tree for a WorldEnvironment
	var node := get_parent()
	while node:
		for child in node.get_children():
			if child is WorldEnvironment:
				return child
		node = node.get_parent()
	# Search whole scene as fallback
	return get_tree().current_scene.find_child("*", true, false) as WorldEnvironment if get_tree().current_scene else null

## HD-2D World Environment Setup
## Add this as a child of your main scene or level root.
##
## DOF MODEL (Godot 4.5 CameraAttributesPractical):
##
##   Camera                                                              
##     |---- blur ----|-- near trans --|--- SHARP ---|-- far trans --|--- blur  
##     0              n_d-n_t          n_d           f_d             f_d+f_t
##
##   - < (near_distance - near_transition)     → fully blurred
##   - (near_distance - near_transition) .. n_d → fades in
##   - near_distance .. far_distance            → SHARP
##   - far_distance .. (far_distance + far_trans) → fades out
##   - > (far_distance + far_transition)        → fully blurred
##
## The auto-focus anchors the SHARP ZONE around the player:
##   near_distance = player_dist - dof_near_focus_margin  (sharp starts)
##   far_distance  = player_dist + dof_far_focus_margin   (sharp ends)
##
## IMPORTANT — for smooth DoF instead of a visible banded "line":
## Set these Project Settings (rendering > camera > depth_of_field):
##   - depth_of_field_bokeh_shape   = Circle
##   - depth_of_field_bokeh_quality = High (or Ultra)
##   - depth_of_field_use_jitter    = true
## Without these the transition will always look stepped, regardless of
## what this script does.

class_name HD2DWorldEnvironment
extends Node3D

@export var player: Node3D  ## Auto-detected via "player" group if not assigned

@export_group("Depth of Field")
@export var dof_enabled: bool = true
## Fallback focus distance when no player is found.
@export_range(1.0, 50.0, 0.5) var dof_focus_distance: float = 12.0
## Overall blur strength. 0.06–0.10 = filmic tilt-shift. 0.15+ = miniature/diorama.
## If you see a visible "line" in the transition, the cause is usually bokeh
## quality (see project settings above), NOT this value.
@export_range(0.0, 0.5, 0.01) var dof_blur_amount: float = 0.08

@export_subgroup("Far (background) blur")
## Distance BEHIND the player that stays sharp. Raise this so nearby NPCs
## and enemies don't get blurred. ~4–7m works well for HD-2D cameras.
@export_range(0.0, 20.0, 0.25) var dof_far_focus_margin: float = 5.0
## Length of the fade from sharp → fully blurred into the background.
## Long = cinematic, short = punchy tilt-shift. 15–25m is a good range.
@export_range(1.0, 50.0, 0.5) var dof_far_transition: float = 20.0

@export_subgroup("Near (foreground) blur")
## Distance IN FRONT of the player that stays sharp. Smaller = more of
## the foreground blurs. 1–2m keeps the player crisp but blurs everything closer.
@export_range(0.0, 10.0, 0.25) var dof_near_focus_margin: float = 1.0
## Length of the fade from sharp → fully blurred in the foreground.
## MUST cover the full visible foreground or you'll see a line where the
## transition ends and full blur begins. 15–25m is typical.
@export_range(1.0, 40.0, 0.5) var dof_near_transition: float = 20.0

@export_subgroup("Auto-focus")
## Auto-adjust DoF focus to player distance from camera.
@export var dof_auto_focus: bool = true
## How snappily the focus tracks the player. Lower = cinematic rack focus,
## higher = glued to the player.
@export_range(0.5, 20.0, 0.25) var dof_focus_speed: float = 4.0

@export_group("Color Grading")
@export var saturation: float = 1.15
@export var contrast: float = 1.08
@export var brightness: float = 1.0
## Warm color correction — shifts shadows cool, highlights warm
@export var color_correction_enabled: bool = true

@export_group("Bloom")
@export var bloom_enabled: bool = true
@export var bloom_intensity: float = 0.15
@export var bloom_threshold: float = 0.9

@export_group("Vignette")
@export var vignette_enabled: bool = true
@export var vignette_intensity: float = 0.35

@export_group("Volumetric Fog")
## Enable volumetric fog (density/color managed by FogManager)
@export var volumetric_fog_enabled: bool = true

@export_group("Ambient & Sky")
@export var ambient_color: Color = Color(0.25, 0.28, 0.4, 1.0)  # Cool blue ambient
@export var ambient_energy: float = 0.4

@export_group("SSAO")
@export var ssao_enabled: bool = true
@export var ssao_intensity: float = 2.0
@export var ssao_radius: float = 1.5

@export_group("Debug")
## Prints the live DoF values once per second — useful for verifying that
## inspector changes are actually propagating to the camera.
@export var debug_print_dof: bool = false

var _world_env: WorldEnvironment
var _environment: Environment
var _camera: Camera3D
var _cam_attributes: CameraAttributesPractical
var _debug_timer: float = 0.0


func _ready() -> void:
	_setup_environment()
	call_deferred("_deferred_init")
	get_tree().tree_changed.connect(_on_tree_changed)


var _tree_change_pending: bool = false

func _on_tree_changed() -> void:
	if _tree_change_pending:
		return
	_tree_change_pending = true
	call_deferred("_check_refs")


func _check_refs() -> void:
	_tree_change_pending = false
	if not is_inside_tree():
		return
	if not is_instance_valid(player) or not player.is_inside_tree():
		player = null
		_find_player()
	var new_cam := get_viewport().get_camera_3d()
	if new_cam != _camera:
		_camera = new_cam
		if _camera and dof_enabled:
			_setup_dof()


func _deferred_init() -> void:
	_find_camera()
	_find_player()


func _find_player() -> void:
	if is_instance_valid(player) and player.is_inside_tree():
		return

	player = null

	if not is_inside_tree():
		return

	var pm := get_node_or_null("/root/PlayerManager")
	if pm and "player_instance" in pm:
		var inst: Node3D = pm.player_instance
		if is_instance_valid(inst) and inst.is_inside_tree():
			player = inst
			return

	var found := get_tree().get_first_node_in_group("player")
	if found is Node3D:
		player = found
		return

	get_tree().process_frame.connect(_retry_find_player, CONNECT_ONE_SHOT)


func _retry_find_player() -> void:
	if is_instance_valid(player) and player.is_inside_tree():
		return

	var found := get_tree().get_first_node_in_group("player")
	if found is Node3D:
		player = found
	else:
		if is_inside_tree():
			get_tree().create_timer(0.1).timeout.connect(_retry_find_player, CONNECT_ONE_SHOT)


func _find_camera() -> void:
	_camera = get_viewport().get_camera_3d()
	if _camera and dof_enabled:
		_setup_dof()


func _setup_dof() -> void:
	_cam_attributes = CameraAttributesPractical.new()

	_cam_attributes.dof_blur_far_enabled = true
	_cam_attributes.dof_blur_near_enabled = true

	# Seed with sensible initial values — _process() will refine from here.
	var initial_dist := dof_focus_distance
	_cam_attributes.dof_blur_far_distance = initial_dist + dof_far_focus_margin
	_cam_attributes.dof_blur_near_distance = max(0.5, initial_dist - dof_near_focus_margin)
	_cam_attributes.dof_blur_far_transition = dof_far_transition
	_cam_attributes.dof_blur_near_transition = dof_near_transition
	_cam_attributes.dof_blur_amount = dof_blur_amount

	_camera.attributes = _cam_attributes


func _setup_environment() -> void:
	_environment = Environment.new()

	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.12, 0.14, 0.18)

	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = ambient_color
	_environment.ambient_light_energy = ambient_energy

	_environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_environment.tonemap_white = 6.0
	_environment.tonemap_exposure = 1.0

	_environment.adjustment_enabled = color_correction_enabled
	_environment.adjustment_saturation = saturation
	_environment.adjustment_contrast = contrast
	_environment.adjustment_brightness = brightness

	_environment.glow_enabled = bloom_enabled
	_environment.glow_intensity = bloom_intensity
	_environment.glow_bloom = 0.1
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_environment.glow_hdr_threshold = bloom_threshold
	_environment.glow_hdr_scale = 2.0
	_environment.set_glow_level(0, true)
	_environment.set_glow_level(1, true)
	_environment.set_glow_level(2, true)
	_environment.set_glow_level(3, false)
	_environment.set_glow_level(4, false)

	_environment.volumetric_fog_enabled = volumetric_fog_enabled
	_environment.volumetric_fog_length = 80.0
	_environment.volumetric_fog_anisotropy = 0.6

	_environment.ssao_enabled = ssao_enabled
	_environment.ssao_intensity = ssao_intensity
	_environment.ssao_radius = ssao_radius
	_environment.ssao_light_affect = 0.5

	_environment.ssil_enabled = true
	_environment.ssil_intensity = 0.8
	_environment.ssil_radius = 3.0

	_environment.ssr_enabled = false

	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"
	_world_env.environment = _environment
	add_child(_world_env)


func _process(delta: float) -> void:
	if not dof_enabled or not _cam_attributes:
		return

	# ---------------------------------------------------------------
	# ALWAYS sync the tunable params, regardless of auto_focus state.
	# Without this, inspector edits were silently ignored when
	# auto_focus was off. That was the "can't adjust anything" bug.
	# ---------------------------------------------------------------
	_cam_attributes.dof_blur_amount = dof_blur_amount
	_cam_attributes.dof_blur_far_transition = dof_far_transition
	_cam_attributes.dof_blur_near_transition = dof_near_transition

	# Determine focus anchor
	var focus_dist: float = dof_focus_distance
	var have_tracking_target := false

	if dof_auto_focus:
		if not is_instance_valid(player) or not player.is_inside_tree():
			player = null
			_find_player()
		elif is_instance_valid(_camera):
			focus_dist = _camera.global_position.distance_to(player.global_position)
			have_tracking_target = true
		else:
			_camera = get_viewport().get_camera_3d()

	var target_far: float = focus_dist + dof_far_focus_margin
	var target_near: float = max(0.5, focus_dist - dof_near_focus_margin)

	if have_tracking_target:
		# Framerate-independent smoothing.
		var t: float = 1.0 - exp(-dof_focus_speed * delta)
		_cam_attributes.dof_blur_far_distance = lerpf(
			_cam_attributes.dof_blur_far_distance, target_far, t
		)
		_cam_attributes.dof_blur_near_distance = lerpf(
			_cam_attributes.dof_blur_near_distance, target_near, t
		)
	else:
		# No player — apply exact values so inspector tweaks are immediate.
		_cam_attributes.dof_blur_far_distance = target_far
		_cam_attributes.dof_blur_near_distance = target_near

	if debug_print_dof:
		_debug_timer += delta
		if _debug_timer >= 1.0:
			_debug_timer = 0.0
			print_debug("[DoF] focus=%.2f  near=[%.2f .. %.2f]  far=[%.2f .. %.2f]  amount=%.3f" % [
				focus_dist,
				_cam_attributes.dof_blur_near_distance - _cam_attributes.dof_blur_near_transition,
				_cam_attributes.dof_blur_near_distance,
				_cam_attributes.dof_blur_far_distance,
				_cam_attributes.dof_blur_far_distance + _cam_attributes.dof_blur_far_transition,
				_cam_attributes.dof_blur_amount,
			])


## Transition environment for area changes (e.g., forest → cave)
func transition_to_preset(preset: Dictionary, duration: float = 2.0) -> void:
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT)

	if preset.has("ambient_color"):
		tween.tween_property(_environment, "ambient_light_color", preset.ambient_color, duration)
	if preset.has("ambient_energy"):
		tween.tween_property(_environment, "ambient_light_energy", preset.ambient_energy, duration)
	if preset.has("saturation"):
		tween.tween_property(_environment, "adjustment_saturation", preset.saturation, duration)
	if preset.has("contrast"):
		tween.tween_property(_environment, "adjustment_contrast", preset.contrast, duration)
	if preset.has("bloom_intensity"):
		tween.tween_property(_environment, "glow_intensity", preset.bloom_intensity, duration)
	if preset.has("dof_blur_amount"):
		tween.tween_method(
			func(v: float) -> void: dof_blur_amount = v,
			dof_blur_amount, preset.dof_blur_amount, duration
		)
	if preset.has("dof_near_transition"):
		tween.tween_method(
			func(v: float) -> void: dof_near_transition = v,
			dof_near_transition, preset.dof_near_transition, duration
		)
	if preset.has("dof_far_transition"):
		tween.tween_method(
			func(v: float) -> void: dof_far_transition = v,
			dof_far_transition, preset.dof_far_transition, duration
		)
	if preset.has("dof_far_focus_margin"):
		tween.tween_method(
			func(v: float) -> void: dof_far_focus_margin = v,
			dof_far_focus_margin, preset.dof_far_focus_margin, duration
		)
	if preset.has("dof_near_focus_margin"):
		tween.tween_method(
			func(v: float) -> void: dof_near_focus_margin = v,
			dof_near_focus_margin, preset.dof_near_focus_margin, duration
		)


## Convenience presets (fog managed by FogManager/FogZones)
static var PRESET_FOREST: Dictionary = {
	"ambient_color": Color(0.2, 0.3, 0.15),
	"ambient_energy": 0.35,
	"saturation": 1.2,
	"dof_blur_amount": 0.08,
	"dof_near_transition": 20.0,
	"dof_far_transition": 20.0,
	"dof_near_focus_margin": 1.0,
	"dof_far_focus_margin": 5.0,
}

static var PRESET_CAVE: Dictionary = {
	"ambient_color": Color(0.1, 0.1, 0.15),
	"ambient_energy": 0.15,
	"saturation": 0.9,
	"contrast": 1.15,
	"dof_blur_amount": 0.06,
	"dof_near_transition": 15.0,
	"dof_far_transition": 14.0,
	"dof_near_focus_margin": 0.75,
	"dof_far_focus_margin": 3.5,
}

static var PRESET_SUNSET: Dictionary = {
	"ambient_color": Color(0.4, 0.25, 0.15),
	"ambient_energy": 0.5,
	"saturation": 1.3,
	"bloom_intensity": 0.25,
	"dof_blur_amount": 0.11,
	"dof_near_transition": 25.0,
	"dof_far_transition": 25.0,
	"dof_near_focus_margin": 1.5,
	"dof_far_focus_margin": 7.0,
}

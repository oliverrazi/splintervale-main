## HD-2D World Environment Setup
## Add this as a child of your main scene or level root.
## It creates and configures a WorldEnvironment with all the post-processing
## needed for the Octopath Traveler-style look:
## - Tilt-shift depth of field (foreground + background blur)
## - Warm color grading
## - Subtle bloom
## - Vignette
## - Volumetric fog/atmosphere
## - SSAO for contact shadows
## - SDFGI or VoxelGI ambient

class_name HD2DWorldEnvironment
extends Node3D

@export var player: Node3D  ## Auto-detected via "player" group if not assigned

@export_group("Depth of Field")
@export var dof_enabled: bool = true
## Distance from camera where focus is sharpest
@export var dof_focus_distance: float = 12.0
## How much blur (applies to both near and far)
@export var dof_blur_amount: float = 0.06
@export var dof_far_transition: float = 8.0
## How much the foreground blurs
@export var dof_near_distance: float = 2.0
@export var dof_near_transition: float = 3.0
## Auto-adjust DoF focus to player distance from camera
@export var dof_auto_focus: bool = true

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

var _world_env: WorldEnvironment
var _environment: Environment
var _camera: Camera3D
var _cam_attributes: CameraAttributesPractical


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
	# Camera may also change after scene load
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
	
	# Try PlayerManager autoload first
	var pm := get_node_or_null("/root/PlayerManager")
	if pm and pm.has_method("get") == false and "player_instance" in pm:
		var inst: Node3D = pm.player_instance
		if is_instance_valid(inst) and inst.is_inside_tree():
			player = inst
			return
	
	# Fallback: search by group
	var found := get_tree().get_first_node_in_group("player")
	if found is Node3D:
		player = found
		return
	
	# Player not yet spawned — wait and retry
	get_tree().process_frame.connect(_retry_find_player, CONNECT_ONE_SHOT)


func _retry_find_player() -> void:
	if is_instance_valid(player) and player.is_inside_tree():
		return
	
	var found := get_tree().get_first_node_in_group("player")
	if found is Node3D:
		player = found
	else:
		# Keep retrying for up to ~2 seconds
		if is_inside_tree():
			get_tree().create_timer(0.1).timeout.connect(_retry_find_player, CONNECT_ONE_SHOT)


func _find_camera() -> void:
	_camera = get_viewport().get_camera_3d()
	if _camera and dof_enabled:
		_setup_dof()


func _setup_dof() -> void:
	_cam_attributes = CameraAttributesPractical.new()
	
	# Far DoF (background blur)
	_cam_attributes.dof_blur_far_enabled = true
	_cam_attributes.dof_blur_far_distance = dof_focus_distance + dof_far_transition
	_cam_attributes.dof_blur_far_transition = dof_far_transition
	
	# Near DoF (foreground blur) — tilt-shift / miniature look
	_cam_attributes.dof_blur_near_enabled = true
	_cam_attributes.dof_blur_near_distance = dof_near_distance
	_cam_attributes.dof_blur_near_transition = dof_near_transition
	
	# Blur amount (shared for near/far in Godot 4)
	_cam_attributes.dof_blur_amount = dof_blur_amount
	
	_camera.attributes = _cam_attributes


func _setup_environment() -> void:
	_environment = Environment.new()
	
	# --- Background ---
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.12, 0.14, 0.18)
	
	# --- Ambient Light ---
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = ambient_color
	_environment.ambient_light_energy = ambient_energy
	
	# --- Tonemap ---
	_environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_environment.tonemap_white = 6.0
	_environment.tonemap_exposure = 1.0
	
	# --- Color Adjustments ---
	_environment.adjustment_enabled = color_correction_enabled
	_environment.adjustment_saturation = saturation
	_environment.adjustment_contrast = contrast
	_environment.adjustment_brightness = brightness
	
	# --- Bloom / Glow ---
	_environment.glow_enabled = bloom_enabled
	_environment.glow_intensity = bloom_intensity
	_environment.glow_bloom = 0.1
	_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_environment.glow_hdr_threshold = bloom_threshold
	_environment.glow_hdr_scale = 2.0
	# Set glow levels for soft, wide bloom
	_environment.set_glow_level(0, true)
	_environment.set_glow_level(1, true)
	_environment.set_glow_level(2, true)
	_environment.set_glow_level(3, false)
	_environment.set_glow_level(4, false)
	
	# --- Depth of Field: configured via CameraAttributesPractical in _setup_dof() ---
	
	# --- Volumetric Fog: managed by FogManager, just enable it here ---
	_environment.volumetric_fog_enabled = volumetric_fog_enabled
	_environment.volumetric_fog_length = 80.0
	_environment.volumetric_fog_anisotropy = 0.6  # Forward scattering
	
	# --- SSAO ---
	_environment.ssao_enabled = ssao_enabled
	_environment.ssao_intensity = ssao_intensity
	_environment.ssao_radius = ssao_radius
	_environment.ssao_light_affect = 0.5
	
	# --- SSIL (Screen Space Indirect Lighting) ---
	_environment.ssil_enabled = true
	_environment.ssil_intensity = 0.8
	_environment.ssil_radius = 3.0
	
	# --- SSR (subtle reflections on wet/shiny surfaces) ---
	_environment.ssr_enabled = false  # Enable if you have reflective surfaces
	
	# Create WorldEnvironment node
	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"
	_world_env.environment = _environment
	add_child(_world_env)


func _process(delta: float) -> void:
	if not dof_auto_focus or not dof_enabled:
		return
	if not _cam_attributes:
		return
	if not is_instance_valid(player) or not player.is_inside_tree():
		player = null
		_find_player()
		return
	if not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if not _camera:
			return
	
	# Calculate distance from camera to player for auto-focus
	var dist: float = _camera.global_position.distance_to(player.global_position)
	
	# Smoothly adjust DoF focus distances
	var target_far: float = dist + dof_far_transition
	var target_near: float = max(0.5, dist - dof_near_transition - 2.0)
	
	_cam_attributes.dof_blur_far_distance = lerpf(
		_cam_attributes.dof_blur_far_distance, target_far, 3.0 * delta
	)
	_cam_attributes.dof_blur_near_distance = lerpf(
		_cam_attributes.dof_blur_near_distance, target_near, 3.0 * delta
	)


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


## Convenience presets (fog managed by FogManager/FogZones)
static var PRESET_FOREST: Dictionary = {
	"ambient_color": Color(0.2, 0.3, 0.15),
	"ambient_energy": 0.35,
	"saturation": 1.2,
}

static var PRESET_CAVE: Dictionary = {
	"ambient_color": Color(0.1, 0.1, 0.15),
	"ambient_energy": 0.15,
	"saturation": 0.9,
	"contrast": 1.15,
}

static var PRESET_SUNSET: Dictionary = {
	"ambient_color": Color(0.4, 0.25, 0.15),
	"ambient_energy": 0.5,
	"saturation": 1.3,
	"bloom_intensity": 0.25,
}

## HD-2D Player Light Rig
## Attach this to your Player node. It creates and manages a lighting rig
## that follows the player, mimicking the Octopath Traveler-style spotlight effect.
##
## The rig consists of:
## - A warm key SpotLight3D shining down on the player
## - A soft fill OmniLight3D for ambient warmth around the player
## - Smooth follow with slight lag for cinematic feel

class_name HD2DPlayerLightRig
extends Node3D

## Reference to the player node (auto-detected via "player" group if not set)
@export var player: Node3D

## --- Key Light (Spotlight from above) ---
@export_group("Key Light")
@export var key_light_enabled: bool = true
@export var key_light_color: Color = Color(1.0, 0.92, 0.75, 1.0)  # Warm golden
@export var key_light_energy: float = 2.5
@export var key_light_range: float = 18.0
@export var key_light_angle: float = 35.0  # Spot cone angle in degrees
@export var key_light_attenuation: float = 0.8
@export var key_light_offset: Vector3 = Vector3(-2.0, 12.0, 4.0)  # Slightly angled
@export var key_light_shadow_enabled: bool = true
@export var key_light_shadow_bias: float = 0.05

## --- Fill Light (Omni around player) ---
@export_group("Fill Light")
@export var fill_light_enabled: bool = true
@export var fill_light_color: Color = Color(0.85, 0.9, 1.0, 1.0)  # Cool blue fill
@export var fill_light_energy: float = 0.6
@export var fill_light_range: float = 10.0
@export var fill_light_attenuation: float = 1.5
@export var fill_light_offset: Vector3 = Vector3(0.0, 3.0, 0.0)

## --- Follow Behavior ---
@export_group("Follow")
@export var follow_smoothing: float = 8.0  # Higher = snappier follow
@export var follow_enabled: bool = true

## --- Intensity Variation (subtle breathing effect) ---
@export_group("Atmosphere")
@export var breathing_enabled: bool = true
@export var breathing_speed: float = 0.5
@export var breathing_intensity: float = 0.1  # 10% variation

var _key_light: SpotLight3D
var _fill_light: OmniLight3D
var _base_key_energy: float
var _base_fill_energy: float
var _time: float = 0.0
var _needs_snap: bool = true


func _ready() -> void:
	_setup_key_light()
	_setup_fill_light()
	
	_base_key_energy = key_light_energy
	_base_fill_energy = fill_light_energy
	
	if not player:
		call_deferred("_find_player")
	
	# Re-initialize on scene changes
	get_tree().tree_changed.connect(_on_tree_changed)


var _tree_change_pending: bool = false

func _on_tree_changed() -> void:
	# Debounce: tree_changed fires many times per frame
	if _tree_change_pending:
		return
	_tree_change_pending = true
	call_deferred("_check_player_still_valid")


func _check_player_still_valid() -> void:
	_tree_change_pending = false
	if not is_inside_tree():
		return
	if not is_instance_valid(player) or not player.is_inside_tree():
		player = null
		_find_player()


func _find_player() -> void:
	if is_instance_valid(player) and player.is_inside_tree():
		return
	
	player = null
	
	# Not in tree yet — can't search
	if not is_inside_tree():
		return
	
	# Check if we're a child of the player already
	var parent := get_parent()
	if parent is CharacterBody3D:
		player = parent
		_needs_snap = true
		return
	
	# Try PlayerManager autoload
	var pm := get_node_or_null("/root/PlayerManager")
	if pm and "player_instance" in pm:
		var inst: Node3D = pm.player_instance
		if is_instance_valid(inst) and inst.is_inside_tree():
			player = inst
			_needs_snap = true
			return
	
	# Search by group
	var found := get_tree().get_first_node_in_group("player")
	if found is Node3D:
		player = found
		_needs_snap = true
		return
	
	# Retry next frame
	get_tree().process_frame.connect(_find_player, CONNECT_ONE_SHOT)


func _setup_key_light() -> void:
	_key_light = SpotLight3D.new()
	_key_light.name = "HD2D_KeyLight"
	_key_light.light_color = key_light_color
	_key_light.light_energy = key_light_energy
	_key_light.spot_range = key_light_range
	_key_light.spot_angle = key_light_angle
	_key_light.spot_attenuation = key_light_attenuation
	_key_light.shadow_enabled = key_light_shadow_enabled
	_key_light.shadow_bias = key_light_shadow_bias
	_key_light.light_bake_mode = Light3D.BAKE_DISABLED
	_key_light.visible = key_light_enabled
	
	# Volumetric fog interaction — set to 0 to avoid visible light cone in fog
	_key_light.light_volumetric_fog_energy = 0.0
	
	add_child(_key_light)


func _setup_fill_light() -> void:
	_fill_light = OmniLight3D.new()
	_fill_light.name = "HD2D_FillLight"
	_fill_light.light_color = fill_light_color
	_fill_light.light_energy = fill_light_energy
	_fill_light.omni_range = fill_light_range
	_fill_light.omni_attenuation = fill_light_attenuation
	_fill_light.shadow_enabled = false  # Fill doesn't need shadows
	_fill_light.light_bake_mode = Light3D.BAKE_DISABLED
	_fill_light.light_volumetric_fog_energy = 0.0
	_fill_light.visible = fill_light_enabled
	
	add_child(_fill_light)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or not player.is_inside_tree():
		player = null
		_find_player()
		return
	
	var target_pos: Vector3 = player.global_position
	
	if _needs_snap:
		global_position = target_pos
		_needs_snap = false
	elif follow_enabled:
		global_position = global_position.lerp(target_pos, follow_smoothing * delta)
	else:
		global_position = target_pos
	
	_key_light.position = key_light_offset
	_fill_light.position = fill_light_offset
	
	var look_target: Vector3 = target_pos + Vector3(0.0, 0.5, 0.0)
	var light_global_pos: Vector3 = _key_light.global_position
	if light_global_pos.distance_squared_to(look_target) > 0.01:
		_key_light.look_at(look_target)


func _process(delta: float) -> void:
	if breathing_enabled:
		_time += delta * breathing_speed
		var breath: float = sin(_time * TAU) * breathing_intensity
		_key_light.light_energy = _base_key_energy * (1.0 + breath)
		_fill_light.light_energy = _base_fill_energy * (1.0 + breath * 0.5)


## Call this to smoothly transition light intensity (e.g., entering caves)
func transition_intensity(key_mult: float, fill_mult: float, duration: float = 1.0) -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_key_light, "light_energy", _base_key_energy * key_mult, duration)
	tween.tween_property(_fill_light, "light_energy", _base_fill_energy * fill_mult, duration)


## Call this to change light color (e.g., time of day)
func transition_color(key_col: Color, fill_col: Color, duration: float = 1.5) -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_key_light, "light_color", key_col, duration)
	tween.tween_property(_fill_light, "light_color", fill_col, duration)

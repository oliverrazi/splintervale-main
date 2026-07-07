@tool
## HD-2D Player Light Rig
## Attach this to your Player node (or anywhere in the scene). It creates and
## manages a lighting rig that follows the player — Octopath / Adventures of
## Elliot style: a small warm light pool around the character with a soft edge.
##
## NEW in this version:
## - key/fill_light_cull_mask: control WHICH render layers each light affects.
##   Standard HD-2D setup: player sprite on layer 2 only, key light excludes
##   layer 2 -> the key paints its pool on the ground without touching the
##   sprite. Sprite brightness is then controlled independently via fill +
##   scene lighting.
## - key/fill_light_specular: intensity of specular highlights (e.g. the fill
##   reflection streak on water) — independent from diffuse brightness.

class_name HD2DPlayerLightRig
extends Node3D

## Reference to the player node (auto-detected via "player" group if not set)
@export var player: Node3D

## --- Key Light (warm pool from above) ---
@export_group("Key Light")
@export var key_light_enabled: bool = true
@export var key_light_color: Color = Color(1.0, 0.92, 0.75)  # Warm golden
@export var key_light_energy: float = 2.2
@export var key_light_range: float = 4.0
@export_range(5.0, 80.0) var key_light_angle: float = 38.0  # Half-angle in degrees
@export var key_light_attenuation: float = 1.4
## Soft edge of the light pool. Higher = softer falloff toward the cone edge.
@export_range(0.0, 4.0) var key_light_angle_attenuation: float = 2.0
## Miniature scale: ~2 m above the player, slightly toward the camera.
@export var key_light_offset: Vector3 = Vector3(-0.35, 2.2, 0.9)
@export var key_light_shadow_enabled: bool = true
@export var key_light_shadow_bias: float = 0.03
## Which render layers the key light affects. To keep the key OFF the player
## sprite: put the sprite on layer 2 (only) and uncheck layer 2 here.
@export_flags_3d_render var key_light_cull_mask: int = 0xFFFFF
## Specular highlight intensity of the key light (0 = diffuse only).
@export_range(0.0, 16.0) var key_light_specular: float = 0.5

## --- Fill Light (subtle cool ambience around player) ---
@export_group("Fill Light")
@export var fill_light_enabled: bool = true
@export var fill_light_color: Color = Color(0.85, 0.9, 1.0)  # Cool blue fill
@export var fill_light_energy: float = 0.15
@export var fill_light_range: float = 8.0
@export var fill_light_attenuation: float = 0.8
@export var fill_light_offset: Vector3 = Vector3(0.0, 1.2, 0.0)
## Which render layers the fill light affects. Usually all layers, so it
## keeps gently lifting the player sprite.
@export_flags_3d_render var fill_light_cull_mask: int = 0xFFFFF
## Specular highlight intensity — controls e.g. the brightness of the fill's
## reflection streak on water, independent from its diffuse energy.
@export_range(0.0, 16.0) var fill_light_specular: float = 1.0

## --- Follow Behavior ---
@export_group("Follow")
@export var follow_smoothing: float = 8.0  # Higher = snappier follow
@export var follow_enabled: bool = true

## --- Intensity Variation (subtle breathing effect) ---
@export_group("Atmosphere")
@export var breathing_enabled: bool = true
@export var breathing_speed: float = 0.5
@export var breathing_intensity: float = 0.06  # 6% variation — keep it subtle

var _key_light: SpotLight3D
var _fill_light: OmniLight3D
var _time: float = 0.0
var _needs_snap: bool = true
var _tree_change_pending: bool = false


func _ready() -> void:
	_setup_lights()
	_apply_light_settings()

	if Engine.is_editor_hint():
		return  # No player search / signals in the editor — preview only

	if not player:
		call_deferred("_find_player")

	get_tree().tree_changed.connect(_on_tree_changed)


func _setup_lights() -> void:
	_key_light = SpotLight3D.new()
	_key_light.name = "HD2D_KeyLight"
	_key_light.light_bake_mode = Light3D.BAKE_DISABLED
	_key_light.light_volumetric_fog_energy = 0.0
	add_child(_key_light)  # No owner assignment -> never saved into the scene

	_fill_light = OmniLight3D.new()
	_fill_light.name = "HD2D_FillLight"
	_fill_light.shadow_enabled = false
	_fill_light.light_bake_mode = Light3D.BAKE_DISABLED
	_fill_light.light_volumetric_fog_energy = 0.0
	add_child(_fill_light)


## Pushes ALL exported values onto the lights. Called every frame (a handful
## of property sets — negligible cost) so tuning is always live.
func _apply_light_settings() -> void:
	_key_light.visible = key_light_enabled
	_key_light.light_color = key_light_color
	_key_light.spot_range = key_light_range
	_key_light.spot_angle = key_light_angle
	_key_light.spot_attenuation = key_light_attenuation
	_key_light.spot_angle_attenuation = key_light_angle_attenuation
	_key_light.shadow_enabled = key_light_shadow_enabled
	_key_light.shadow_bias = key_light_shadow_bias
	_key_light.position = key_light_offset
	_key_light.light_cull_mask = key_light_cull_mask
	_key_light.light_specular = key_light_specular

	_fill_light.visible = fill_light_enabled
	_fill_light.light_color = fill_light_color
	_fill_light.omni_range = fill_light_range
	_fill_light.omni_attenuation = fill_light_attenuation
	_fill_light.position = fill_light_offset
	_fill_light.light_cull_mask = fill_light_cull_mask
	_fill_light.light_specular = fill_light_specular


func _process(delta: float) -> void:
	if not is_instance_valid(_key_light):
		return

	_apply_light_settings()

	# Breathing multiplies the CURRENT exported energy — never a cached copy.
	var key_energy := key_light_energy
	var fill_energy := fill_light_energy
	if breathing_enabled and not Engine.is_editor_hint():
		_time += delta * breathing_speed
		var breath: float = sin(_time * TAU) * breathing_intensity
		key_energy *= 1.0 + breath
		fill_energy *= 1.0 + breath * 0.5

	_key_light.light_energy = key_energy
	_fill_light.light_energy = fill_energy


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		_aim_key_light(global_position + Vector3(0.0, 0.15, 0.0))
		return

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

	# Aim at mid-body of the 0.3 m sprite, not at its feet.
	_aim_key_light(target_pos + Vector3(0.0, 0.15, 0.0))


func _aim_key_light(look_target: Vector3) -> void:
	var dir: Vector3 = look_target - _key_light.global_position
	if dir.length_squared() < 0.0001:
		return
	# look_at fails when the direction is parallel to the UP vector
	if absf(dir.normalized().dot(Vector3.UP)) > 0.999:
		_key_light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	else:
		_key_light.look_at(look_target)


## --- Player tracking -------------------------------------------------------

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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		print("--- CullMask Debug ---")
		print("Key cull_mask (binär): ", String.num_int64(_key_light.light_cull_mask, 2))
		if is_instance_valid(player):
			for child in player.find_children("*", "VisualInstance3D", true, false):
				print(child.name, " -> layers (binär): ", String.num_int64(child.layers, 2))


## --- Public API -------------------------------------------------------------

## Smoothly transition light intensity (e.g., entering caves).
## Tweens the EXPORTED values, so live tuning and breathing stay consistent.
func transition_intensity(key_mult: float, fill_mult: float, duration: float = 1.0) -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "key_light_energy", key_light_energy * key_mult, duration)
	tween.tween_property(self, "fill_light_energy", fill_light_energy * fill_mult, duration)


## Change light color (e.g., time of day)
func transition_color(key_col: Color, fill_col: Color, duration: float = 1.5) -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "key_light_color", key_col, duration)
	tween.tween_property(self, "fill_light_color", fill_col, duration)

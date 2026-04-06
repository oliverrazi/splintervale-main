## God Ray Cluster — spawns multiple god rays over an area.
## Place this where you want a group of light beams (e.g., over a lake).
## Rays are randomly distributed within the defined radius.
@tool
class_name GodRayCluster
extends Node3D

@export_group("Distribution")
## Number of god rays to spawn
@export var ray_count: int = 5:
	set(v):
		ray_count = clampi(v, 1, 30)
		if is_inside_tree():
			_rebuild()
## Radius of the area to distribute rays in
@export var area_radius: float = 8.0:
	set(v):
		area_radius = v
		if is_inside_tree():
			_rebuild()
## Random seed for consistent placement
@export var placement_seed: int = 42:
	set(v):
		placement_seed = v
		if is_inside_tree():
			_rebuild()

@export_group("Ray Appearance")
@export var ray_color: Color = Color(1.0, 0.95, 0.8, 0.25):
	set(v):
		ray_color = v
		_update_all_rays()
@export_range(0.0, 2.0) var base_intensity: float = 0.4:
	set(v):
		base_intensity = v
		_update_all_rays()
@export var min_height: float = 6.0
@export var max_height: float = 12.0
@export var min_width: float = 1.0
@export var max_width: float = 3.0

@export_group("Variation")
## How much intensity varies between rays (0 = all same, 1 = big variation)
@export_range(0.0, 1.0) var intensity_variation: float = 0.3
## How much sway speed varies
@export_range(0.0, 1.0) var sway_variation: float = 0.5

@export_group("Dust")
@export var dust_enabled: bool = true
@export_range(0.0, 2.0) var dust_brightness: float = 0.5

## Regenerate rays (press in editor to re-randomize)
@export var regenerate: bool = false:
	set(v):
		if v and is_inside_tree():
			_rebuild()

var _rays: Array[GodRay] = []
var _rng: RandomNumberGenerator


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	# Clear existing
	for ray in _rays:
		if is_instance_valid(ray):
			ray.queue_free()
	_rays.clear()

	_rng = RandomNumberGenerator.new()
	_rng.seed = placement_seed

	for i in ray_count:
		var ray := GodRay.new()

		# Random position within circle
		var angle := _rng.randf() * TAU
		var dist := sqrt(_rng.randf()) * area_radius  # sqrt for uniform distribution
		ray.position = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		# Random size variation
		ray.beam_height = _rng.randf_range(min_height, max_height)
		ray.beam_width = _rng.randf_range(min_width, max_width)

		# Color and intensity with variation
		ray.ray_color = ray_color
		var intensity_mult := 1.0 - _rng.randf() * intensity_variation
		ray.intensity = base_intensity * intensity_mult

		# Sway variation — each ray sways slightly differently
		ray.sway_speed = 0.3 * (1.0 + _rng.randf() * sway_variation)
		ray.sway_amount = 0.05 * (1.0 + _rng.randf() * sway_variation)
		ray.flicker_amount = 0.15 * (1.0 + _rng.randf() * 0.5)

		# Dust
		ray.dust_enabled = dust_enabled
		ray.dust_brightness = dust_brightness

		# Slight random Y rotation for variety
		ray.rotation.y = _rng.randf() * TAU

		_rays.append(ray)
		add_child(ray)


func _update_all_rays() -> void:
	for ray in _rays:
		if is_instance_valid(ray):
			ray.ray_color = ray_color
			ray.intensity = base_intensity


## Editor gizmo — show the area in editor
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if ray_count <= 0:
		warnings.append("Ray count must be at least 1")
	return warnings

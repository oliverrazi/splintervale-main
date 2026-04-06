## HD-2D Directional Sun Light
## Adds a global directional light for the "sun" that provides
## the base illumination and long shadows visible in HD-2D games.
## Place this in your main scene.

class_name HD2DSunLight
extends DirectionalLight3D

@export_group("HD-2D Sun Settings")
## Sun angle — for top-down 2.5D, angle from above-behind works best
@export var sun_pitch: float = -55.0  # Degrees rotation on X
@export var sun_yaw: float = -30.0    # Degrees rotation on Y

@export var sun_color_day: Color = Color(1.0, 0.95, 0.85)
@export var sun_energy_day: float = 1.2

## Shadow quality settings
@export_group("Shadow Quality")
@export var shadow_quality_high: bool = true

## Time-of-day support (optional)
@export_group("Time of Day")
@export var time_of_day_enabled: bool = false
@export_range(0.0, 24.0) var current_hour: float = 14.0  # 2 PM default


func _ready() -> void:
	# Base setup
	light_color = sun_color_day
	light_energy = sun_energy_day
	light_bake_mode = Light3D.BAKE_DISABLED
	
	# Shadow setup
	shadow_enabled = true
	shadow_bias = 0.05
	shadow_normal_bias = 2.0
	
	# Volumetric fog interaction — keep low to avoid visible light beams in fog
	light_volumetric_fog_energy = 0.2
	
	if shadow_quality_high:
		directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		directional_shadow_max_distance = 60.0
	else:
		directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		directional_shadow_max_distance = 40.0
	
	# Set rotation
	rotation_degrees = Vector3(sun_pitch, sun_yaw, 0.0)


func _process(delta: float) -> void:
	if not time_of_day_enabled:
		return
	
	# Simple time-of-day color/intensity mapping
	var t := current_hour
	
	# Sun angle follows time
	var pitch := remap(t, 6.0, 18.0, -15.0, -75.0)
	pitch = clampf(pitch, -75.0, -15.0)
	rotation_degrees.x = pitch
	
	# Color temperature shifts
	if t < 7.0 or t > 18.0:
		# Night / twilight
		light_energy = lerpf(light_energy, 0.1, 2.0 * delta)
		light_color = light_color.lerp(Color(0.3, 0.3, 0.5), 2.0 * delta)
	elif t < 9.0:
		# Morning — warm orange
		light_energy = lerpf(light_energy, 0.8, 2.0 * delta)
		light_color = light_color.lerp(Color(1.0, 0.8, 0.5), 2.0 * delta)
	elif t > 16.0:
		# Late afternoon — golden hour
		light_energy = lerpf(light_energy, 1.0, 2.0 * delta)
		light_color = light_color.lerp(Color(1.0, 0.75, 0.4), 2.0 * delta)
	else:
		# Midday
		light_energy = lerpf(light_energy, sun_energy_day, 2.0 * delta)
		light_color = light_color.lerp(sun_color_day, 2.0 * delta)

@tool
## HD-2D Directional Sun Light (v3)
## Adds a global directional light for the "sun" that provides
## the base illumination and long shadows visible in HD-2D games.
## Place this in your main scene.
##
## v3: Werte werden über SETTER angewendet (genau beim Ändern), NICHT mehr
## jeden Frame. Damit sind Inspector, Transform und alle nativen
## Light3D-Felder wieder frei editierbar — v2 hat sie durch das
## Per-Frame-Apply im Editor effektiv gesperrt.
##
## Tuning-Regeln:
## - sun_pitch / sun_yaw / sun_color_day / sun_energy_day / sun_specular
##   wirken sofort beim Ändern (Editor UND Remote-Inspector im Spiel).
## - Native Light3D-Felder direkt zu ändern funktioniert jetzt auch,
##   wird aber beim nächsten Export-Ändern überschrieben — Exports sind
##   die "Quelle der Wahrheit".
## - Bei aktivem Time-of-Day übernimmt die Tageszeit-Logik Rotation,
##   Farbe und Energy zur Laufzeit.

class_name HD2DSunLight
extends DirectionalLight3D

@export_group("HD-2D Sun Settings")
## Sun angle — for top-down 2.5D, angle from above-behind works best
@export var sun_pitch: float = -55.0 : set = _set_sun_pitch
@export var sun_yaw: float = -30.0 : set = _set_sun_yaw
@export var sun_color_day: Color = Color(1.0, 0.95, 0.85) : set = _set_sun_color
@export var sun_energy_day: float = 1.2 : set = _set_sun_energy
## Specular highlight intensity (drives e.g. water glints from this light)
@export_range(0.0, 16.0) var sun_specular: float = 1.0 : set = _set_sun_specular

@export_group("Shadow Quality")
@export var shadow_quality_high: bool = true : set = _set_shadow_quality

@export_group("Time of Day")
@export var time_of_day_enabled: bool = false
@export_range(0.0, 24.0) var current_hour: float = 14.0  # 2 PM default


func _ready() -> void:
	light_bake_mode = Light3D.BAKE_DISABLED
	shadow_enabled = true
	shadow_bias = 0.05
	shadow_normal_bias = 2.0

	# Volumetric fog interaction — keep low to avoid visible light beams in fog
	light_volumetric_fog_energy = 0.2

	_apply_rotation()
	light_color = sun_color_day
	light_energy = sun_energy_day
	light_specular = sun_specular
	_apply_shadow_quality()


# ─── Setter: wenden Werte GENAU EINMAL beim Ändern an ───

func _set_sun_pitch(value: float) -> void:
	sun_pitch = value
	_apply_rotation()

func _set_sun_yaw(value: float) -> void:
	sun_yaw = value
	_apply_rotation()

func _set_sun_color(value: Color) -> void:
	sun_color_day = value
	if is_node_ready() and not time_of_day_enabled:
		light_color = sun_color_day

func _set_sun_energy(value: float) -> void:
	sun_energy_day = value
	if is_node_ready() and not time_of_day_enabled:
		light_energy = sun_energy_day

func _set_sun_specular(value: float) -> void:
	sun_specular = value
	if is_node_ready():
		light_specular = sun_specular

func _set_shadow_quality(value: bool) -> void:
	shadow_quality_high = value
	if is_node_ready():
		_apply_shadow_quality()


func _apply_rotation() -> void:
	if not is_node_ready():
		return
	if time_of_day_enabled and not Engine.is_editor_hint():
		return  # Time-of-Day besitzt die Rotation zur Laufzeit
	rotation_degrees = Vector3(sun_pitch, sun_yaw, 0.0)


func _apply_shadow_quality() -> void:
	if shadow_quality_high:
		directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		directional_shadow_max_distance = 60.0
	else:
		directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		directional_shadow_max_distance = 40.0


# ─── Time of Day (läuft nur im Spiel, nie im Editor) ───

func _process(delta: float) -> void:
	if not time_of_day_enabled or Engine.is_editor_hint():
		return

	var t := current_hour

	# Sun angle follows time
	var pitch := remap(t, 6.0, 18.0, -15.0, -75.0)
	pitch = clampf(pitch, -75.0, -15.0)
	rotation_degrees = Vector3(pitch, sun_yaw, 0.0)

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

extends Node

## Verwaltet alle VistaZones und stellt smooth-interpolierte Kamera/Fog-Werte bereit.
## Als Autoload registrieren.

# === DEFAULT CAMERA VALUES ===
## Diese Werte sollten den Defaults deiner Kamera entsprechen
@export_group("Default Camera")
@export var default_fov: float = 65.0
@export var default_camera_distance: float = 8.0
@export var default_camera_pitch: float = -50.0
@export var default_camera_offset: Vector3 = Vector3.ZERO

@export_group("Transition")
@export var transition_speed: float = 2.0

# === CURRENT VALUES (von Kamera abfragbar) ===
var current_fov: float = 65.0
var current_camera_distance: float = 8.0
var current_camera_pitch: float = -50.0
var current_camera_offset: Vector3 = Vector3.ZERO

# Fog-Override-Werte (nur aktiv wenn eine VistaZone Fog überschreibt)
var current_fog_density: float = 0.0
var current_fog_color: Color = Color.BLACK
var current_fog_emission: Color = Color.BLACK
var current_fog_emission_energy: float = 0.0
var fog_override_influence: float = 0.0  # 0 = kein Override, 1 = voll

## Wird emittiert wenn sich Vista-Werte ändern (optional, falls Kamera per Signal arbeitet)
signal vista_changed()

var _zones: Array = []  # Array[VistaZone]
var _player: Node3D = null


func _ready() -> void:
	current_fov = default_fov
	current_camera_distance = default_camera_distance
	current_camera_pitch = default_camera_pitch
	current_camera_offset = default_camera_offset
	call_deferred("_find_player")


func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player")


func register_zone(zone) -> void:
	if zone not in _zones:
		_zones.append(zone)


func unregister_zone(zone) -> void:
	_zones.erase(zone)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_find_player()
		return

	var player_pos := _player.global_position

	# Ziel-Werte starten bei Defaults
	var target_fov := default_fov
	var target_distance := default_camera_distance
	var target_pitch := default_camera_pitch
	var target_offset := default_camera_offset

	# Fog-Override-Tracking
	var target_fog_density := 0.0
	var target_fog_color := Color.BLACK
	var target_fog_emission := Color.BLACK
	var target_fog_emission_energy := 0.0
	var total_fog_influence := 0.0

	# Aktive Zonen sammeln
	var active_zones: Array[Dictionary] = []

	for zone in _zones:
		if not is_instance_valid(zone):
			continue

		var influence: float = zone.get_influence(player_pos)
		if influence > 0.001:
			active_zones.append({
				"zone": zone,
				"influence": influence,
				"priority": zone.zone_priority
			})

	# Nach Priorität sortieren (höchste zuerst)
	active_zones.sort_custom(func(a, b): return a.priority > b.priority)

	if active_zones.size() > 0:
		# Gewichtete Kamera-Werte berechnen
		var total_cam_weight := 0.0
		var weighted_fov := 0.0
		var weighted_distance := 0.0
		var weighted_pitch := 0.0
		var weighted_offset := Vector3.ZERO

		for zone_data in active_zones:
			var zone = zone_data.zone
			var influence: float = zone_data.influence

			# Kamera-Overrides
			if zone.override_fov:
				weighted_fov += zone.fov * influence
				total_cam_weight = max(total_cam_weight, influence)
			if zone.override_distance:
				weighted_distance += zone.camera_distance * influence
				total_cam_weight = max(total_cam_weight, influence)
			if zone.override_pitch:
				weighted_pitch += zone.camera_pitch * influence
				total_cam_weight = max(total_cam_weight, influence)
			if zone.override_offset:
				weighted_offset += zone.camera_offset * influence
				total_cam_weight = max(total_cam_weight, influence)

			# Fog-Overrides
			if zone.override_fog:
				target_fog_density += zone.fog_density * influence
				target_fog_color += zone.fog_color * influence
				target_fog_emission += zone.fog_emission * influence
				target_fog_emission_energy += zone.fog_emission_energy * influence
				total_fog_influence += influence

		# Kamera-Werte normalisieren und mit Default blenden
		var cam_blend: float = clamp(total_cam_weight, 0.0, 1.0)

		if total_cam_weight > 0.0:
			# Nur überschriebene Werte blenden, Rest bleibt Default
			var fov_sum := 0.0
			var fov_weight := 0.0
			var dist_sum := 0.0
			var dist_weight := 0.0
			var pitch_sum := 0.0
			var pitch_weight := 0.0
			var offset_sum := Vector3.ZERO
			var offset_weight := 0.0

			for zone_data in active_zones:
				var zone = zone_data.zone
				var influence: float = zone_data.influence
				if zone.override_fov:
					fov_sum += zone.fov * influence
					fov_weight += influence
				if zone.override_distance:
					dist_sum += zone.camera_distance * influence
					dist_weight += influence
				if zone.override_pitch:
					pitch_sum += zone.camera_pitch * influence
					pitch_weight += influence
				if zone.override_offset:
					offset_sum += zone.camera_offset * influence
					offset_weight += influence

			if fov_weight > 0.0:
				var blended_fov := fov_sum / fov_weight
				target_fov = lerp(default_fov, blended_fov, clamp(fov_weight, 0.0, 1.0))
			if dist_weight > 0.0:
				var blended_dist := dist_sum / dist_weight
				target_distance = lerp(default_camera_distance, blended_dist, clamp(dist_weight, 0.0, 1.0))
			if pitch_weight > 0.0:
				var blended_pitch := pitch_sum / pitch_weight
				target_pitch = lerp(default_camera_pitch, blended_pitch, clamp(pitch_weight, 0.0, 1.0))
			if offset_weight > 0.0:
				var blended_offset := offset_sum / offset_weight
				target_offset = default_camera_offset.lerp(blended_offset, clamp(offset_weight, 0.0, 1.0))

		# Fog normalisieren
		if total_fog_influence > 0.0:
			target_fog_density /= total_fog_influence
			target_fog_color /= total_fog_influence
			target_fog_emission /= total_fog_influence
			target_fog_emission_energy /= total_fog_influence

	# Smooth interpolation
	var t: float = clamp(delta * transition_speed, 0.0, 1.0)

	current_fov = lerp(current_fov, target_fov, t)
	current_camera_distance = lerp(current_camera_distance, target_distance, t)
	current_camera_pitch = lerp(current_camera_pitch, target_pitch, t)
	current_camera_offset = current_camera_offset.lerp(target_offset, t)

	# Fog-Override smooth blenden
	var target_fog_inf : Variant= clamp(total_fog_influence, 0.0, 1.0)
	fog_override_influence = lerp(fog_override_influence, target_fog_inf, t)
	if total_fog_influence > 0.0:
		current_fog_density = lerp(current_fog_density, target_fog_density, t)
		current_fog_color = current_fog_color.lerp(target_fog_color, t)
		current_fog_emission = current_fog_emission.lerp(target_fog_emission, t)
		current_fog_emission_energy = lerp(current_fog_emission_energy, target_fog_emission_energy, t)

	vista_changed.emit()


# === HELPER FÜR KAMERA-SCRIPT ===

## Gibt true zurück wenn mindestens eine VistaZone aktiv ist
func has_active_override() -> bool:
	return fog_override_influence > 0.01 or \
		abs(current_fov - default_fov) > 0.1 or \
		abs(current_camera_distance - default_camera_distance) > 0.1 or \
		abs(current_camera_pitch - default_camera_pitch) > 0.1 or \
		current_camera_offset.length() > 0.01


## Gibt true zurück wenn Fog überschrieben wird
func has_fog_override() -> bool:
	return fog_override_influence > 0.01

extends Node

@export_group("Default Fog")
@export var default_density: float = 0.01
@export var default_color: Color = Color(0.6, 0.65, 0.7)
@export var default_emission: Color = Color(0.0, 0.0, 0.0)
@export var default_emission_energy: float = 0.0

@export_group("Transition")
@export var transition_speed: float = 2.0  # Wie schnell der Fog sich ändert

var _environment: Environment = null
var _player: Node3D = null
var _fog_zones: Array[FogZone] = []

# Aktuelle Werte (für smooth lerping)
var _current_density: float = 0.01
var _current_color: Color = Color(0.6, 0.65, 0.7)
var _current_emission: Color = Color(0.0, 0.0, 0.0)
var _current_emission_energy: float = 0.0


func _ready() -> void:
	# Initialisierung verzögern
	call_deferred("_initialize")


func _initialize() -> void:
	_find_environment()
	_find_player()
	_find_fog_zones()
	
	# Startwerte setzen
	_current_density = default_density
	_current_color = default_color
	_current_emission = default_emission
	_current_emission_energy = default_emission_energy
	
	_apply_fog_settings()


func _find_environment() -> void:
	var world_env := get_tree().current_scene.find_child("WorldEnvironment", true, false)
	if world_env and world_env is WorldEnvironment:
		_environment = world_env.environment
		
		# Volumetric Fog aktivieren falls nicht aktiv
		if _environment and not _environment.volumetric_fog_enabled:
			_environment.volumetric_fog_enabled = true
			print("FogManager: Volumetric Fog enabled")
	
	if _environment:
		print("FogManager: Environment found")
	else:
		push_warning("FogManager: No WorldEnvironment found!")


func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		print("FogManager: Player found")


func _find_fog_zones() -> void:
	_fog_zones.clear()
	var zones := get_tree().get_nodes_in_group("fog_zone")
	for zone in zones:
		if zone is FogZone:
			_fog_zones.append(zone)
	print("FogManager: Found ", _fog_zones.size(), " fog zones")


func register_fog_zone(zone: FogZone) -> void:
	if zone not in _fog_zones:
		_fog_zones.append(zone)


func unregister_fog_zone(zone: FogZone) -> void:
	_fog_zones.erase(zone)


func _process(delta: float) -> void:
	if _environment == null:
		_find_environment()
		return
	
	if _player == null or not is_instance_valid(_player):
		_find_player()
		return
	
	# Ziel-Werte berechnen
	var target_density := default_density
	var target_color := default_color
	var target_emission := default_emission
	var target_emission_energy := default_emission_energy
	
	# Alle Zonen sammeln und gewichtet mischen
	var total_influence := 0.0
	var weighted_density := 0.0
	var weighted_color := Color(0, 0, 0, 0)
	var weighted_emission := Color(0, 0, 0, 0)
	var weighted_emission_energy := 0.0
	
	var player_pos := _player.global_position
	
	# Zonen nach Priorität sortieren
	var active_zones: Array[Dictionary] = []
	
	for zone in _fog_zones:
		if not is_instance_valid(zone):
			continue
		
		var influence := zone.get_influence(player_pos)
		if influence > 0.001:
			active_zones.append({
				"zone": zone,
				"influence": influence,
				"priority": zone.zone_priority
			})
	
	# Nach Priorität sortieren (höchste zuerst)
	active_zones.sort_custom(func(a, b): return a.priority > b.priority)
	
	if active_zones.size() > 0:
		# Gewichtete Mischung aller aktiven Zonen
		for zone_data in active_zones:
			var zone: FogZone = zone_data.zone
			var influence: float = zone_data.influence
			
			weighted_density += zone.fog_density * influence
			weighted_color += zone.fog_color * influence
			weighted_emission += zone.fog_emission * influence
			weighted_emission_energy += zone.fog_emission_energy * influence
			total_influence += influence
		
		if total_influence > 0:
			# Normalisieren
			weighted_density /= total_influence
			weighted_color /= total_influence
			weighted_emission /= total_influence
			weighted_emission_energy /= total_influence
			
			# Mit Default mischen basierend auf Gesamteinfluss
			var blend :Variant = min(total_influence, 1.0)
			target_density = lerp(default_density, weighted_density, blend)
			target_color = default_color.lerp(weighted_color, blend)
			target_emission = default_emission.lerp(weighted_emission, blend)
			target_emission_energy = lerp(default_emission_energy, weighted_emission_energy, blend)
	
	# Smooth interpolation zu Zielwerten
	var t :Variant = clamp(delta * transition_speed, 0.0, 1.0)
	_current_density = lerp(_current_density, target_density, t)
	_current_color = _current_color.lerp(target_color, t)
	_current_emission = _current_emission.lerp(target_emission, t)
	_current_emission_energy = lerp(_current_emission_energy, target_emission_energy, t)
	
	# Fog anwenden
	_apply_fog_settings()


func _apply_fog_settings() -> void:
	if _environment == null:
		return
	
	_environment.volumetric_fog_density = _current_density
	_environment.volumetric_fog_albedo = _current_color
	_environment.volumetric_fog_emission = _current_emission
	_environment.volumetric_fog_emission_energy = _current_emission_energy

extends Node

# Spieler-Daten (global zugänglich)
var player_data: PlayerData
var is_loading: bool = false

var _pending_player_position: Vector3 = Vector3.ZERO
var _has_pending_position: bool = false

const SAVE_PATH := "user://savegame.json"


func _ready() -> void:
	# Neue Spieler-Daten erstellen
	player_data = PlayerData.new()
	player_data.recalculate_stats()
	
	if LoadingScreen:
		LoadingScreen.loading_finished.connect(_on_loading_finished)


func _on_loading_finished() -> void:
	# Position setzen nachdem Szene geladen ist
	_apply_pending_position()
	
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("reset_death_state"):
		player.reset_death_state()
	
	
	is_loading = false
	print("Loading complete!")

func new_game() -> void:
	player_data = PlayerData.new()
	player_data.recalculate_stats()

var player_scene_path: String = ""

func save_game() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	
	var save_dict := {
		"version": 1,
		"timestamp": Time.get_datetime_string_from_system(),
		"player": _serialize_player_data(),
		"world": {
			"scene": get_tree().current_scene.scene_file_path,
			"position": {
				"x": player.global_position.x if player else 0.0,
				"y": player.global_position.y if player else 0.0,
				"z": player.global_position.z if player else 0.0
			}
		}
	}
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open save file: ", FileAccess.get_open_error())
		return false
	
	var json_string := JSON.stringify(save_dict, "\t")
	file.store_string(json_string)
	file.close()
	
	print("Game saved successfully!")
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("No save file found at: ", SAVE_PATH)
		return false
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open save file: ", FileAccess.get_open_error())
		return false
	
	var json_string := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var parse_result := json.parse(json_string)
	if parse_result != OK:
		push_error("Failed to parse save file: ", json.get_error_message())
		return false
	
	var save_dict: Dictionary = json.data
	
	is_loading = true
	
	# Player Data laden
	if save_dict.has("player"):
		_deserialize_player_data(save_dict["player"])
	
	# World/Scene laden
	if save_dict.has("world"):
		var world_data: Dictionary = save_dict["world"]
		var saved_scene: String = world_data.get("scene", "")
		var pos_data: Dictionary = world_data.get("position", {})
		
		_pending_player_position = Vector3(
			pos_data.get("x", 0.0),
			pos_data.get("y", 0.0) + 3.0,  # Höher spawnen für Sicherheit
			pos_data.get("z", 0.0)
		)
		_has_pending_position = true
				
		if saved_scene != "":
			get_tree().paused = false
			
			# Szene laden, dann Player positionieren
			LoadingScreen.load_scene(saved_scene)
			
			# Nach dem Laden den Player auf Boden setzen
			_schedule_player_ground_snap()
			return true
	
	is_loading = false
	return true
	
func _schedule_player_ground_snap() -> void:
	# Warte mehrere Frames für Scene-Load
	for i in range(10):
		await get_tree().process_frame
	
	# Zusätzliche Wartezeit für Terrain3D
	await get_tree().create_timer(0.5).timeout
	
	var player := get_tree().get_first_node_in_group("player")
	if player and _has_pending_position:
		_snap_player_to_ground(player)


func _snap_player_to_ground(player: Node3D) -> void:
	# Mehrere Versuche mit steigender Wartezeit
	for attempt in range(5):
		var space_state := player.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			_pending_player_position + Vector3(0, 10.0, 0),
			_pending_player_position + Vector3(0, -30.0, 0)
		)
		query.exclude = [player]
		
		var result := space_state.intersect_ray(query)
		
		if not result.is_empty():
			# Player-Offset berücksichtigen (falls Origin nicht am Fuß)
			var player_ground_offset: float = 0.0
			if player.has_method("get_ground_offset"):
				player_ground_offset = player.get_ground_offset()
			
			player.global_position = result.position + Vector3(0, player_ground_offset, 0)
			if player.has_method("set_velocity"):
				player.velocity = Vector3.ZERO
			_has_pending_position = false
			is_loading = false
			print("Player snapped to ground at: ", player.global_position)
			return
		
		# Warten und nochmal versuchen
		print("Ground snap attempt ", attempt + 1, " failed, waiting...")
		await get_tree().create_timer(0.3 * (attempt + 1)).timeout
	
	# Fallback
	player.global_position = _pending_player_position
	_has_pending_position = false
	is_loading = false
	push_warning("Could not find ground, using saved position")

func _apply_pending_position() -> void:
	if not _has_pending_position:
		return
	
	# Spieler finden und Position setzen
	var player := get_tree().get_first_node_in_group("player")
	if player and _pending_player_position != Vector3.ZERO:
		player.global_position = _pending_player_position
		print("Player position set to: ", _pending_player_position)
	
	_has_pending_position = false
	_pending_player_position = Vector3.ZERO


func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		var err := DirAccess.remove_absolute(SAVE_PATH)
		return err == OK
	return false


func _serialize_player_data() -> Dictionary:
	var pd := player_data
	return {
		# Level & Experience
		"level": pd.level,
		"current_exp": pd.current_exp,
		
		# Resources
		"current_hp": pd.current_hp,
		"current_mp": pd.current_mp,
		"current_stamina": pd.current_stamina,
		"gold": pd.gold,
		
		# Base Stats
		"base_health": pd.base_health,
		"base_magic": pd.base_magic,
		"base_strength": pd.base_strength,
		"base_defense": pd.base_defense,
		"base_endurance": pd.base_endurance,
	}


func _deserialize_player_data(data: Dictionary) -> void:
	var pd := player_data
	
	# Level & Experience
	pd.level = data.get("level", 1)
	pd.current_exp = data.get("current_exp", 0)
	
	# Base Stats (vor recalculate!)
	pd.base_health = data.get("base_health", 10)
	pd.base_magic = data.get("base_magic", 5)
	pd.base_strength = data.get("base_strength", 5)
	pd.base_defense = data.get("base_defense", 5)
	pd.base_endurance = data.get("base_endurance", 5)
	
	# Stats neu berechnen (max_hp, max_mp, etc.)
	pd.recalculate_stats()
	
	# Current Resources (nach recalculate!)
	pd.current_hp = data.get("current_hp", pd.max_hp)
	pd.current_mp = data.get("current_mp", pd.max_mp)
	pd.current_stamina = data.get("current_stamina", pd.max_stamina)
	pd.gold = data.get("gold", 0)
	
	# Alle Signals feuern um UI zu aktualisieren
	pd.hp_changed.emit(pd.current_hp, pd.max_hp)
	pd.exp_changed.emit(pd.current_exp, pd.exp_to_next_level)
	pd.level_changed.emit(pd.level)
	pd.gold_changed.emit(pd.gold)

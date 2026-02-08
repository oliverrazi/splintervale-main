extends Node

# Spieler-Daten (global zugänglich)
var player_data: PlayerData
var is_loading: bool = false

var _pending_player_position: Vector3 = Vector3.ZERO
var _has_pending_position: bool = false


var _flags: Dictionary = {}

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
		},
		"inventory": InventoryManager.get_save_data(),
		"flags": _flags.duplicate(),
		"quests": QuestManager.get_save_data() 
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
	
	if save_dict.has("flags"):
		_flags = save_dict["flags"].duplicate()
		
	if save_dict.has("quests"):
		QuestManager.load_save_data(save_dict["quests"])
	
	if save_dict.has("inventory"):
		InventoryManager.load_save_data(save_dict["inventory"])
	
	# World/Scene laden
	if save_dict.has("world"):
		var world_data: Dictionary = save_dict["world"]
		var saved_scene: String = world_data.get("scene", "")
		var pos_data: Dictionary = world_data.get("position", {})
		
		_pending_player_position = Vector3(
			pos_data.get("x", 0.0),
			pos_data.get("y", 0.0),
			pos_data.get("z", 0.0)
		)
		_has_pending_position = true
		
		var _current_scene_path := ""
		if get_tree().current_scene:
			_current_scene_path = get_tree().current_scene.scene_file_path
		
		if saved_scene != "":
			# Szene immer neu laden (für Gegner-Respawn etc.)
			get_tree().paused = false
			LoadingScreen.load_scene(saved_scene)
			return true
	
	is_loading = false
	return true

func set_flag(flag_name: String, value: bool = true) -> void:
	_flags[flag_name] = value


func get_flag(flag_name: String) -> bool:
	return _flags.get(flag_name, false)


func clear_flag(flag_name: String) -> void:
	_flags.erase(flag_name)

func _apply_pending_position() -> void:
	if not _has_pending_position:
		return
	
	var player := get_tree().get_first_node_in_group("player")
	if player and _pending_player_position != Vector3.ZERO:
		# Spieler leicht über der gespeicherten Position spawnen
		# damit er sanft auf den Boden fällt (falls Terrain noch lädt)
		player.global_position = _pending_player_position + Vector3(0, 0.5, 0)
		
		# Velocity zurücksetzen damit er nicht weiterfliegt
		if "velocity" in player:
			player.velocity = Vector3.ZERO
		
		print("Player position set to: ", player.global_position)
	
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
		"current_resonance": pd.current_resonance,
		"gold": pd.gold,
		
		# Base Stats
		"base_vitality": pd.base_vitality,
		"base_strength": pd.base_strength,
		"base_attunement": pd.base_attunement,
		"base_attack_speed": pd.base_attack_speed,
		
		# Unspent Points
		"stat_points": pd.stat_points,
		"skill_points": pd.skill_points,
	}


func _deserialize_player_data(data: Dictionary) -> void:
	var pd := player_data
	
	# Level & Experience
	pd.level = data.get("level", 1)
	pd.current_exp = data.get("current_exp", 0)
	
	# Base Stats (vor recalculate!)
	pd.base_vitality = data.get("base_vitality", 6)
	pd.base_strength = data.get("base_strength", 3)
	pd.base_attunement = data.get("base_attunement", 3)
	pd.base_attack_speed = data.get("base_attack_speed", 3)
	
	# Unspent Points
	pd.stat_points = data.get("stat_points", 0)
	pd.skill_points = data.get("skill_points", 0)
	
	# Stats neu berechnen (max_hp, max_resonance, etc.)
	pd.recalculate_stats()
	
	# Current Resources (nach recalculate!)
	pd.current_hp = data.get("current_hp", pd.max_hp)
	pd.current_resonance = data.get("current_resonance", pd.max_resonance)
	pd.gold = data.get("gold", 0)
	
	# Alle Signals feuern um UI zu aktualisieren
	pd.hp_changed.emit(pd.current_hp, pd.max_hp)
	pd.resonance_changed.emit(pd.current_resonance, pd.max_resonance)
	pd.exp_changed.emit(pd.current_exp, pd.exp_to_next_level)
	pd.level_changed.emit(pd.level)
	pd.gold_changed.emit(pd.gold)
	pd.stat_points_changed.emit(pd.stat_points)
	pd.skill_points_changed.emit(pd.skill_points)

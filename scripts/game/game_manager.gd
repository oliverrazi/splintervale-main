extends Node

# Spieler-Daten (global zugänglich)
var player_data: PlayerData

const SAVE_PATH := "user://savegame.json"


func _ready() -> void:
	# Neue Spieler-Daten erstellen
	player_data = PlayerData.new()
	player_data.recalculate_stats()


func new_game() -> void:
	player_data = PlayerData.new()
	player_data.recalculate_stats()


func save_game() -> void:
	var save_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if save_file:
		var data := player_data.to_dict()
		save_file.store_string(JSON.stringify(data, "\t"))
		save_file.close()
		print("Game saved!")


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		print("No save file found")
		return false
	
	var save_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if save_file:
		var json_string := save_file.get_as_text()
		save_file.close()
		
		var data = JSON.parse_string(json_string)
		if data is Dictionary:
			player_data.from_dict(data)
			print("Game loaded!")
			return true
	
	return false


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("Save deleted")

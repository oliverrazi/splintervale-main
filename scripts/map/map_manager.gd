extends Node

## MapManager - Autoload für Karten-Verwaltung
## Verwaltet Fog of War, Spieler-Tracking und Karten-Daten

signal fog_updated()
signal map_ready()

# Einstellungen
@export var reveal_radius: float = 30.0  # Wie viel der Spieler aufdeckt (in Metern)
@export var update_interval: float = 0.5  # Wie oft Fog aktualisiert wird

# Karten-Daten
var map_data: MapData = null
var map_texture: Texture2D = null  # Die vorgerenderte Karten-Textur
var fog_texture: ImageTexture = null

# Intern
var _player: Node3D = null
var _update_timer: float = 0.0
var _last_player_pos: Vector3 = Vector3.ZERO
var _is_ready: bool = false

const MAP_TEXTURE_PATH := "user://map_texture.png"
const MAP_DATA_PATH := "user://map_data.json"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_or_create_map_data()


func _process(delta: float) -> void:
	if not _is_ready:
		return
	
	_update_timer += delta
	if _update_timer >= update_interval:
		_update_timer = 0.0
		_update_fog_of_war()


func _load_or_create_map_data() -> void:
	# Versuche gespeicherte Map-Daten zu laden
	if FileAccess.file_exists(MAP_DATA_PATH):
		var file := FileAccess.open(MAP_DATA_PATH, FileAccess.READ)
		if file:
			var json := JSON.new()
			var result := json.parse(file.get_as_text())
			file.close()
			
			if result == OK:
				map_data = MapData.new()
				map_data.from_dict(json.data)
				print("MapManager: Loaded existing map data")
	
	# Neue Map-Daten erstellen falls nicht vorhanden
	if map_data == null:
		map_data = MapData.new()
		print("MapManager: Created new map data")
	
	# Karten-Textur laden falls vorhanden
	if FileAccess.file_exists(MAP_TEXTURE_PATH):
		var img := Image.load_from_file(MAP_TEXTURE_PATH)
		if img:
			map_texture = ImageTexture.create_from_image(img)
			print("MapManager: Loaded map texture")
	
	_update_fog_texture()
	_is_ready = true
	map_ready.emit()


func _update_fog_of_war() -> void:
	if map_data == null:
		return
	
	# Spieler finden
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	
	if _player == null:
		return
	
	# Nur updaten wenn Spieler sich bewegt hat
	var player_pos := _player.global_position
	if player_pos.distance_to(_last_player_pos) < 1.0:
		return
	
	_last_player_pos = player_pos
	
	# Bereich aufdecken
	map_data.reveal_area(player_pos, reveal_radius)
	_update_fog_texture()
	fog_updated.emit()


func _update_fog_texture() -> void:
	if map_data:
		fog_texture = map_data.get_fog_texture()


func save_map_data() -> void:
	if map_data == null:
		return
	
	var file := FileAccess.open(MAP_DATA_PATH, FileAccess.WRITE)
	if file:
		var json_str := JSON.stringify(map_data.to_dict())
		file.store_string(json_str)
		file.close()
		print("MapManager: Saved map data")


func reset_fog_of_war() -> void:
	if map_data:
		map_data.reset_fog()
		_update_fog_texture()
		fog_updated.emit()


func set_map_texture(texture: Texture2D) -> void:
	map_texture = texture
	
	# Auch als Datei speichern
	if texture:
		var img := texture.get_image()
		if img:
			img.save_png(MAP_TEXTURE_PATH)
			print("MapManager: Saved map texture to ", MAP_TEXTURE_PATH)


func get_player_map_position() -> Vector2:
	# Gibt die Spieler-Position als normalisierte Karten-Koordinate (0-1) zurück
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	
	if _player == null or map_data == null:
		return Vector2(0.5, 0.5)
	
	var pos := _player.global_position
	var norm_x := (pos.x - map_data.world_min.x) / (map_data.world_max.x - map_data.world_min.x)
	var norm_y := (pos.z - map_data.world_min.y) / (map_data.world_max.y - map_data.world_min.y)
	
	return Vector2(clamp(norm_x, 0.0, 1.0), clamp(norm_y, 0.0, 1.0))


func get_player_rotation() -> float:
	# Gibt die Spieler-Rotation (Y-Achse) in Grad zurück
	if _player == null or not is_instance_valid(_player):
		return 0.0
	
	return _player.rotation.y


func world_to_map_position(world_pos: Vector3) -> Vector2:
	# Welt-Position zu normalisierter Karten-Position
	if map_data == null:
		return Vector2(0.5, 0.5)
	
	var norm_x := (world_pos.x - map_data.world_min.x) / (map_data.world_max.x - map_data.world_min.x)
	var norm_y := (world_pos.z - map_data.world_min.y) / (map_data.world_max.y - map_data.world_min.y)
	
	return Vector2(clamp(norm_x, 0.0, 1.0), clamp(norm_y, 0.0, 1.0))

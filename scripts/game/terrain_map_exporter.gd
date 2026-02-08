@tool
extends Node3D
class_name TerrainMapExporter

## Exportiert Referenz-Maps von Terrain3D für Grass Painting
## Generiert Höhenkarte und Textur-Übersicht als PNG

@export_group("Terrain")
@export var terrain: Node3D

@export_group("Export Settings")
## Auflösung der exportierten Map (z.B. 2048 für 2048x2048)
@export var map_resolution: int = 2048
## Bereich der exportiert wird (in Metern, vom Origin aus)
@export var export_area: Vector2 = Vector2(5000, 5000)
## Offset vom Origin
@export var area_offset: Vector2 = Vector2.ZERO

@export_group("Export")
## Exportiert Höhenkarte als Graustufen-PNG
@export var export_heightmap: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_export_heightmap()
			export_heightmap = false

## Exportiert Textur-ID Map als farbige PNG
@export var export_texture_map: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_export_texture_map()
			export_texture_map = false

## Exportiert beides kombiniert (Heightmap mit Textur-Overlay)
@export var export_combined: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_export_combined()
			export_combined = false

# Farben für verschiedene Textur-IDs
const TEXTURE_COLORS = [
	Color(0.2, 0.7, 0.2),   # 0: Grün (Wiese)
	Color(0.5, 0.35, 0.2),  # 1: Braun (Erde/Wände)
	Color(0.6, 0.55, 0.4),  # 2: Hellbraun (Wege)
	Color(0.5, 0.5, 0.5),   # 3: Grau (Stein)
	Color(0.8, 0.7, 0.5),   # 4: Sand
	Color(0.1, 0.5, 0.1),   # 5: Dunkelgrün (Wald)
	Color(0.65, 0.65, 0.7), # 6: Hellgrau (Fels)
	Color(0.35, 0.25, 0.15),# 7: Dunkelbraun
	Color(0.9, 0.9, 0.95),  # 8: Fast weiß (Schnee)
	Color(0.1, 0.3, 0.6),   # 9: Blau (Wasser)
	Color(0.7, 0.2, 0.2),   # 10: Rot
	Color(0.7, 0.5, 0.7),   # 11: Lila
]

var _terrain_data = null
var _terrain_util = null


func _export_heightmap() -> void:
	if not _setup_terrain():
		return
	
	print("TerrainMapExporter: Exportiere Höhenkarte...")
	
	var image = Image.create(map_resolution, map_resolution, false, Image.FORMAT_RGB8)
	var half_area = export_area / 2.0
	var pixel_size = export_area / float(map_resolution)
	
	# Min/Max Höhe finden
	var min_height = INF
	var max_height = -INF
	
	# Erster Pass: Min/Max ermitteln (grobes Sampling)
	for y in range(0, map_resolution, 8):
		for x in range(0, map_resolution, 8):
			var world_pos = _pixel_to_world(x, y, half_area, pixel_size)
			var height = _get_terrain_height(world_pos)
			if not is_nan(height) and is_finite(height):
				min_height = min(min_height, height)
				max_height = max(max_height, height)
	
	if min_height == INF or not is_finite(min_height):
		min_height = 0
		max_height = 100
	
	var height_range = max_height - min_height
	if height_range < 0.01:
		height_range = 1.0
	
	print("  Höhenbereich: ", min_height, " bis ", max_height)
	
	# Zweiter Pass: Bild erstellen
	for y in range(map_resolution):
		for x in range(map_resolution):
			var world_pos = _pixel_to_world(x, y, half_area, pixel_size)
			var height = _get_terrain_height(world_pos)
			
			if is_nan(height) or not is_finite(height):
				image.set_pixel(x, y, Color.BLACK)
			else:
				var normalized = (height - min_height) / height_range
				normalized = clamp(normalized, 0.0, 1.0)
				image.set_pixel(x, y, Color(normalized, normalized, normalized))
		
		if y % 200 == 0:
			print("  Progress: ", int(float(y) / map_resolution * 100), "%")
	
	_save_image(image, "heightmap")


func _export_texture_map() -> void:
	if not _setup_terrain():
		return
	
	print("TerrainMapExporter: Exportiere Textur-Map...")
	
	var image = Image.create(map_resolution, map_resolution, false, Image.FORMAT_RGB8)
	var half_area = export_area / 2.0
	var pixel_size = export_area / float(map_resolution)
	
	for y in range(map_resolution):
		for x in range(map_resolution):
			var world_pos = _pixel_to_world(x, y, half_area, pixel_size)
			var texture_id = _get_texture_id(world_pos)
			
			if texture_id < 0 or texture_id >= TEXTURE_COLORS.size():
				# Unbekannte ID - benutze Index modulo
				if texture_id >= 0:
					var color_idx = texture_id % TEXTURE_COLORS.size()
					image.set_pixel(x, y, TEXTURE_COLORS[color_idx])
				else:
					image.set_pixel(x, y, Color.MAGENTA)
			else:
				image.set_pixel(x, y, TEXTURE_COLORS[texture_id])
		
		if y % 200 == 0:
			print("  Progress: ", int(float(y) / map_resolution * 100), "%")
	
	_save_image(image, "texture_map")


func _export_combined() -> void:
	if not _setup_terrain():
		return
	
	print("TerrainMapExporter: Exportiere kombinierte Map...")
	
	var image = Image.create(map_resolution, map_resolution, false, Image.FORMAT_RGB8)
	var half_area = export_area / 2.0
	var pixel_size = export_area / float(map_resolution)
	
	# Min/Max Höhe finden
	var min_height = INF
	var max_height = -INF
	
	for y in range(0, map_resolution, 8):
		for x in range(0, map_resolution, 8):
			var world_pos = _pixel_to_world(x, y, half_area, pixel_size)
			var height = _get_terrain_height(world_pos)
			if not is_nan(height) and is_finite(height):
				min_height = min(min_height, height)
				max_height = max(max_height, height)
	
	if min_height == INF or not is_finite(min_height):
		min_height = 0
		max_height = 100
	
	var height_range = max_height - min_height
	if height_range < 0.01:
		height_range = 1.0
	
	print("  Höhenbereich: ", min_height, " bis ", max_height)
	
	# Bild erstellen
	for y in range(map_resolution):
		for x in range(map_resolution):
			var world_pos = _pixel_to_world(x, y, half_area, pixel_size)
			var height = _get_terrain_height(world_pos)
			var texture_id = _get_texture_id(world_pos)
			
			# Basis-Farbe von Textur
			var base_color: Color
			if texture_id >= 0 and texture_id < TEXTURE_COLORS.size():
				base_color = TEXTURE_COLORS[texture_id]
			elif texture_id >= 0:
				base_color = TEXTURE_COLORS[texture_id % TEXTURE_COLORS.size()]
			else:
				base_color = Color(0.3, 0.3, 0.3)
			
			# Mit Höhe modulieren (Schatten/Licht Effekt)
			if not is_nan(height) and is_finite(height):
				var normalized = (height - min_height) / height_range
				normalized = clamp(normalized, 0.0, 1.0)
				var brightness = 0.5 + normalized * 0.5
				base_color = Color(
					clamp(base_color.r * brightness, 0, 1),
					clamp(base_color.g * brightness, 0, 1),
					clamp(base_color.b * brightness, 0, 1)
				)
			
			image.set_pixel(x, y, base_color)
		
		if y % 200 == 0:
			print("  Progress: ", int(float(y) / map_resolution * 100), "%")
	
	_save_image(image, "combined_map")


func _pixel_to_world(px: int, py: int, half_area: Vector2, pixel_size: Vector2) -> Vector3:
	var world_x = -half_area.x + area_offset.x + px * pixel_size.x
	var world_z = -half_area.y + area_offset.y + py * pixel_size.y
	return Vector3(world_x, 0, world_z)


func _setup_terrain() -> bool:
	if terrain == null:
		push_error("TerrainMapExporter: Kein Terrain zugewiesen!")
		return false
	
	_terrain_data = terrain.get("data")
	if _terrain_data == null:
		push_error("TerrainMapExporter: Terrain hat keine 'data' Property!")
		return false
	
	# Terrain3DUtil holen
	if ClassDB.class_exists("Terrain3DUtil"):
		_terrain_util = ClassDB.instantiate("Terrain3DUtil")
		print("TerrainMapExporter: Terrain3DUtil gefunden")
	else:
		_terrain_util = null
		print("TerrainMapExporter: Terrain3DUtil nicht gefunden, verwende Fallback")
	
	return true


func _get_terrain_height(pos: Vector3) -> float:
	if _terrain_data == null:
		return NAN
	
	if _terrain_data.has_method("get_height"):
		return _terrain_data.call("get_height", pos)
	
	return NAN


func _get_texture_id(pos: Vector3) -> int:
	if _terrain_data == null:
		return -1
	
	if not _terrain_data.has_method("get_control"):
		return -1
	
	var control: Color = _terrain_data.call("get_control", pos)
	
	# Methode 1: Terrain3DUtil verwenden (bevorzugt)
	if _terrain_util != null and _terrain_util.has_method("get_base_id"):
		return _terrain_util.call("get_base_id", control)
	
	# Methode 2: Manuelles Dekodieren
	# Control Map Format: R-Kanal enthält uint32 als float interpretiert
	# Base ID sind Bits 27-31 (oberste 5 Bits)
	# Dekodierung: (x >> 27) & 0x1F
	var raw_float = control.r
	if is_nan(raw_float):
		return -1
	
	# Float-Bits als uint32 interpretieren
	var bytes = PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, raw_float)
	var as_uint: int = bytes.decode_u32(0)
	
	# Base ID extrahieren (Bits 27-31)
	var base_id = (as_uint >> 27) & 0x1F
	
	return base_id


func _save_image(image: Image, name: String) -> void:
	var dir_path = "res://data/terrain_maps/"
	DirAccess.make_dir_recursive_absolute(dir_path)
	
	var scene_name = "terrain"
	if Engine.is_editor_hint():
		var edited = get_tree().edited_scene_root
		if edited:
			scene_name = edited.name
	
	var file_path = dir_path + scene_name + "_" + name + ".png"
	
	var error = image.save_png(file_path)
	if error == OK:
		print("TerrainMapExporter: Gespeichert nach ", file_path)
		print("  Auflösung: ", map_resolution, "x", map_resolution)
		print("  Bereich: ", export_area.x, "x", export_area.y, " Meter")
		print("  1 Pixel = ", snapped(export_area.x / map_resolution, 0.01), " Meter")
	else:
		push_error("TerrainMapExporter: Fehler beim Speichern: " + str(error))

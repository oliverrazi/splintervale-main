extends Resource
class_name MapData

## Speichert Fog of War Fortschritt und Karten-Metadaten

# Karten-Einstellungen
@export var world_min: Vector2 = Vector2(-125, 50) 
@export var world_max: Vector2 =   Vector2(75, 250)
@export var fog_resolution: int = 256  # Pixel für Fog-Textur

# Fog of War Daten (1D Array, 0 = verdeckt, 255 = sichtbar)
@export var fog_data: PackedByteArray = PackedByteArray()

# Entdeckte Orte
@export var discovered_locations: Array[String] = []


func _init() -> void:
	_initialize_fog()


func _initialize_fog() -> void:
	var size := fog_resolution * fog_resolution
	fog_data.resize(size)
	fog_data.fill(0)  # Alles verdeckt


func reset_fog() -> void:
	_initialize_fog()
	discovered_locations.clear()


func world_to_fog_coords(world_pos: Vector3) -> Vector2i:
	# Welt-Position (X, Z) zu Fog-Textur Pixel
	var normalized_x := (world_pos.x - world_min.x) / (world_max.x - world_min.x)
	var normalized_y := (world_pos.z - world_min.y) / (world_max.y - world_min.y)
	
	var fog_x := int(clamp(normalized_x * fog_resolution, 0, fog_resolution - 1))
	var fog_y := int(clamp(normalized_y * fog_resolution, 0, fog_resolution - 1))
	
	return Vector2i(fog_x, fog_y)


func reveal_area(world_pos: Vector3, radius_world: float) -> void:
	# Bereich um Position herum aufdecken
	var center := world_to_fog_coords(world_pos)
	
	# Radius in Fog-Pixel umrechnen
	var world_size := world_max.x - world_min.x
	var radius_pixels := int((radius_world / world_size) * fog_resolution)
	
	# Kreis aufdecken
	for y in range(-radius_pixels, radius_pixels + 1):
		for x in range(-radius_pixels, radius_pixels + 1):
			if x * x + y * y <= radius_pixels * radius_pixels:
				var px := center.x + x
				var py := center.y + y
				
				if px >= 0 and px < fog_resolution and py >= 0 and py < fog_resolution:
					var idx := py * fog_resolution + px
					fog_data[idx] = 255


func is_revealed(world_pos: Vector3) -> bool:
	var coords := world_to_fog_coords(world_pos)
	var idx := coords.y * fog_resolution + coords.x
	
	if idx >= 0 and idx < fog_data.size():
		return fog_data[idx] > 0
	return false


func get_fog_texture() -> ImageTexture:
	# Erstellt eine Textur aus den Fog-Daten
	var img := Image.create(fog_resolution, fog_resolution, false, Image.FORMAT_L8)
	
	for y in range(fog_resolution):
		for x in range(fog_resolution):
			var idx := y * fog_resolution + x
			var value := fog_data[idx]
			img.set_pixel(x, y, Color(value / 255.0, value / 255.0, value / 255.0, 1.0))
	
	var texture := ImageTexture.create_from_image(img)
	return texture


func discover_location(location_id: String) -> void:
	if location_id not in discovered_locations:
		discovered_locations.append(location_id)


func is_location_discovered(location_id: String) -> bool:
	return location_id in discovered_locations


# === SAVE / LOAD ===

func to_dict() -> Dictionary:
	return {
		"world_min": [world_min.x, world_min.y],
		"world_max": [world_max.x, world_max.y],
		"fog_resolution": fog_resolution,
		"fog_data": Marshalls.raw_to_base64(fog_data),
		"discovered_locations": discovered_locations.duplicate()
	}


func from_dict(data: Dictionary) -> void:
	if data.has("world_min"):
		var wmin = data["world_min"]
		world_min = Vector2(wmin[0], wmin[1])
	
	if data.has("world_max"):
		var wmax = data["world_max"]
		world_max = Vector2(wmax[0], wmax[1])
	
	fog_resolution = data.get("fog_resolution", 256)
	
	if data.has("fog_data"):
		fog_data = Marshalls.base64_to_raw(data["fog_data"])
	else:
		_initialize_fog()
	
	discovered_locations.clear()
	if data.has("discovered_locations"):
		for loc in data["discovered_locations"]:
			discovered_locations.append(loc)

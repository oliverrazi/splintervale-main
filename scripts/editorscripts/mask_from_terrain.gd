@tool
extends Node

@export var terrain: Terrain3D

@export_group("Terrain Bounds (Manuell einstellen)")
@export var world_size := Vector2(1024, 1024)  # Standard: 1 Region = 1024x1024
@export var world_offset := Vector2(0, 0)  # Wo dein Terrain beginnt
@export var mask_resolution := 512

@export_category("Texture IDs")
@export var path_texture_id := 2
@export var rock_texture_id := 3
@export var water_texture_id := 4

@export_category("Output")
@export var save_path := "res://terrain/grass_mask.png"
@export var auto_assign_to_grass := true
@export var grass_material: ShaderMaterial

@export_category("Debug & Info")
@export var show_terrain_properties := false:
	set(value):
		if value and Engine.is_editor_hint():
			_show_all_properties()
			show_terrain_properties = false

@export var test_position := Vector3(0, 0, 0)
@export var test_texture_at_position := false:
	set(value):
		if value and Engine.is_editor_hint():
			_test_position()
			test_texture_at_position = false

@export_category("Actions")
@export var generate_simple_mask := false:
	set(value):
		if value and Engine.is_editor_hint():
			_generate_simple()
			generate_simple_mask = false

func _show_all_properties():
	"""Zeigt ALLE Properties und Methoden von Terrain3D"""
	if not terrain:
		print("Kein Terrain!")
		return
	
	print("\n========== TERRAIN3D ANALYSE ==========")
	print("Klasse: ", terrain.get_class())
	
	print("\n--- PROPERTIES ---")
	var props = terrain.get_property_list()
	for prop in props:
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE or prop.usage & PROPERTY_USAGE_STORAGE:
			var value = terrain.get(prop.name)
			if value != null:
				print("  ", prop.name, " = ", value, " (", typeof(value), ")")
	
	print("\n--- METHODEN ---")
	var methods = terrain.get_method_list()
	for method in methods:
		if not method.name.begins_with("_") and not method.name.begins_with("get_"):
			print("  ", method.name, "()")
	
	print("\n--- SPEZIELLE GET-METHODEN ---")
	for method in methods:
		if method.name.begins_with("get_") and not method.name in ["get_class", "get_instance_id"]:
			print("  ", method.name, "()")
	
	# Versuche bekannte Terrain3D Properties
	print("\n--- TERRAIN3D SPEZIFISCHE PROPERTIES ---")
	var check_props = ["storage", "data", "material", "region_size", "mesh_size"]
	for prop_name in check_props:
		var val = terrain.get(prop_name)
		if val != null:
			print("  ✓ ", prop_name, " = ", val)
			
			# Wenn es ein Objekt ist, zeige dessen Methoden
			if typeof(val) == TYPE_OBJECT:
				print("    Typ: ", val.get_class())
				var sub_methods = val.get_method_list()
				for sm in sub_methods:
					if not sm.name.begins_with("_"):
						print("      - ", sm.name, "()")
	
	print("\n========================================")

func _test_position():
	"""Testet ob wir Texture-Daten an einer Position auslesen können"""
	if not terrain:
		print("Kein Terrain!")
		return
	
	print("\n--- TEST AN POSITION ", test_position, " ---")
	
	# Versuche verschiedene Zugriffsmethoden
	var storage = terrain.get("storage")
	var data = terrain.get("data")
	
	if storage and storage.has_method("get_control"):
		var control = storage.get_control(test_position)
		var texture_id = control & 0x1F
		print("✓ Via storage.get_control(): Texture ID = ", texture_id)
	elif storage:
		print("✗ storage existiert, aber hat keine get_control() Methode")
	
	if data and data.has_method("get_control"):
		var control = data.get_control(test_position)
		var texture_id = control & 0x1F
		print("✓ Via data.get_control(): Texture ID = ", texture_id)
	elif data:
		print("✗ data existiert, aber hat keine get_control() Methode")
	
	# Versuche andere Methoden
	if terrain.has_method("get_texture"):
		var tex = terrain.get_texture(test_position)
		print("✓ Via terrain.get_texture(): ", tex)
	
	if terrain.has_method("get_pixel"):
		var pix = terrain.get_pixel(test_position)
		print("✓ Via terrain.get_pixel(): ", pix)

func _generate_simple():
	"""Generiert eine einfache Test-Maske"""
	print("\nGeneriere einfache Test-Maske...")
	print("  Auflösung: ", mask_resolution, "x", mask_resolution)
	print("  World Size: ", world_size)
	print("  World Offset: ", world_offset)
	
	var img = Image.create(mask_resolution, mask_resolution, false, Image.FORMAT_RGB8)
	
	# Erstelle ein Schachbrett-Muster zum Testen
	for x in mask_resolution:
		for y in mask_resolution:
			var checker = ((x / 32) + (y / 32)) % 2
			if checker == 0:
				img.set_pixel(x, y, Color.WHITE)  # Gras
			else:
				img.set_pixel(x, y, Color.BLACK)  # Kein Gras
	
	var err = img.save_png(save_path)
	if err == OK:
		print("✓ Test-Maske gespeichert: ", save_path)
	else:
		push_error("Fehler beim Speichern!")
		return
	
	if auto_assign_to_grass and grass_material:
		call_deferred("_assign_to_material")

func _assign_to_material():
	await get_tree().process_frame
	var texture = load(save_path) as Texture2D
	if texture:
		grass_material.set_shader_parameter("mask_texture", texture)
		grass_material.set_shader_parameter("world_size", world_size)
		grass_material.set_shader_parameter("world_offset", world_offset)
		print("✓ Test-Maske dem Material zugewiesen")

@tool
extends Node3D
class_name MapCaptureCamera

## Editor-Tool um eine Karte von oben zu fotografieren
## Füge dieses Script zu einem Node3D in deiner Hauptszene hinzu
## Klicke auf "Capture Map" im Inspector

@export_group("Capture Settings")
@export var map_size: Vector2 = Vector2(220, 220)  ## Größe der Welt in Metern
@export var map_center: Vector3 = Vector3(-25, 0, 150)  ## Zentrum der Karte
@export var capture_height: float = 150.0  ## Höhe der Kamera
@export var output_resolution: Vector2i = Vector2i(2048, 2048)  ## Auflösung der Karte
@export var output_path: String = "res://assets/map/world_map.png"

@export_group("Visual Settings")
@export var include_trees: bool = true
@export var include_buildings: bool = true
@export var background_color: Color = Color(0.2, 0.3, 0.5, 1.0)  ## Wasser/Hintergrund

@export_group("Actions")
@export var capture_map: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_do_capture()
		capture_map = false

var _capture_camera: Camera3D
var _sub_viewport: SubViewport


func _do_capture() -> void:
	print("=== Starting Map Capture ===")
	print("Map size: ", map_size)
	print("Center: ", map_center)
	print("Resolution: ", output_resolution)
	
	# SubViewport erstellen
	_sub_viewport = SubViewport.new()
	_sub_viewport.size = output_resolution
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sub_viewport.transparent_bg = false
	add_child(_sub_viewport)
	
	# Kamera erstellen
	_capture_camera = Camera3D.new()
	_capture_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	
	# Orthografische Größe berechnen (halbe Breite)
	var ortho_size: float = max(map_size.x, map_size.y) / 2.0
	_capture_camera.size = ortho_size * 2.0
	
	# Kamera positionieren (von oben nach unten schauend)
	_capture_camera.position = Vector3(map_center.x, capture_height, map_center.z)
	_capture_camera.rotation_degrees = Vector3(-65, 0, 0)  # Schaut nach unten
	
	# Far plane groß genug für die Höhe
	_capture_camera.far = capture_height + 100.0
	_capture_camera.near = 1.0
	
	_sub_viewport.add_child(_capture_camera)
	
	# Warten und dann capturen
	_capture_camera.current = true
	
	# Muss auf nächsten Frame warten
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Screenshot machen
	var image: Image = _sub_viewport.get_texture().get_image()
	
	if image:
		# Verzeichnis erstellen falls nötig
		var dir_path := output_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)
		
		# Speichern
		var error := image.save_png(output_path)
		if error == OK:
			print("=== Map captured successfully! ===")
			print("Saved to: ", output_path)
			print("Resolution: ", image.get_width(), "x", image.get_height())
		else:
			push_error("Failed to save map image: " + str(error))
	else:
		push_error("Failed to capture map image!")
	
	# Aufräumen
	_sub_viewport.queue_free()
	_capture_camera = null
	_sub_viewport = null
	
	print("=== Map Capture Complete ===")


## Hilfsfunktion um die Capture-Grenzen im Editor anzuzeigen
func _draw_gizmo() -> void:
	pass  # Könnte später Gizmo-Zeichnung hinzufügen


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if map_size.x <= 0 or map_size.y <= 0:
		warnings.append("Map size must be positive!")
	
	if output_resolution.x <= 0 or output_resolution.y <= 0:
		warnings.append("Output resolution must be positive!")
	
	return warnings

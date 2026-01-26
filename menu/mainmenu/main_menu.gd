extends Control

## Hauptmenü mit 3D-Hintergrund und sanfter Kamera-Bewegung

# Pfade zu deinen Szenen anpassen
@export var game_scene_path: String = "res://demo.tscn"
@export var options_scene_path: String = "res://scenes/ui/options/options.tscn"

# Kamera-Bewegung
@export var camera_sway_speed: float = 0.3
@export var camera_sway_amount: float = 2.0  # Grad

# Font-Einstellungen
const FONT_PATH = "res://menu/assets/fonts/Merriweather-Regular.ttf"
const FONT_COLOR = Color("ffead5")
const OUTLINE_COLOR = Color("4e2700")
const OUTLINE_SIZE = 4

# Button-Styling
const BUTTON_BG_COLOR = Color(1.0, 1.0, 1.0, 0.15)
const BUTTON_HOVER_COLOR = Color(1.0, 1.0, 1.0, 0.25)
const BUTTON_PRESSED_COLOR = Color(1.0, 1.0, 1.0, 0.35)
const BUTTON_CORNER_RADIUS = 8

# Referenzen
@onready var camera_pivot: Node3D = $SubViewportContainer/SubViewport/MenuScene3D/CameraPivot
@onready var sub_viewport: SubViewport = $SubViewportContainer/SubViewport
@onready var button_start: Button = $Overlay/UIRoot/MarginContainer/VBoxContainer/MenuContainer/ButtonStart
@onready var button_load: Button = $Overlay/UIRoot/MarginContainer/VBoxContainer/MenuContainer/ButtonLoad
@onready var button_options: Button = $Overlay/UIRoot/MarginContainer/VBoxContainer/MenuContainer/ButtonOptions
@onready var button_quit: Button = $Overlay/UIRoot/MarginContainer/VBoxContainer/MenuContainer/ButtonQuit

var time_elapsed: float = 0.0
var base_font: Font


func _ready() -> void:
	
	if has_node("/root/Hud"):
		get_node("/root/Hud").hide()
	
	_load_font()
	_setup_buttons()
	_connect_signals()
	_update_viewport_size()
	
	# Viewport-Größe bei Fensteränderung aktualisieren
	get_tree().root.size_changed.connect(_update_viewport_size)


func _process(delta: float) -> void:
	_update_camera_sway(delta)


func _load_font() -> void:
	if ResourceLoader.exists(FONT_PATH):
		base_font = load(FONT_PATH)
	else:
		push_warning("Font nicht gefunden: %s - Verwende Standard-Font" % FONT_PATH)
		base_font = ThemeDB.fallback_font



func _setup_buttons() -> void:
	var buttons = [button_start, button_load, button_options, button_quit]
	
	for button in buttons:
		_style_button(button)


func _style_button(button: Button) -> void:
	# Font-Einstellungen
	button.add_theme_font_override("font", base_font)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", FONT_COLOR)
	button.add_theme_color_override("font_hover_color", FONT_COLOR)
	button.add_theme_color_override("font_pressed_color", FONT_COLOR)
	button.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	button.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	
	# Normal StyleBox
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = BUTTON_BG_COLOR
	style_normal.corner_radius_top_left = BUTTON_CORNER_RADIUS
	style_normal.corner_radius_top_right = BUTTON_CORNER_RADIUS
	style_normal.corner_radius_bottom_left = BUTTON_CORNER_RADIUS
	style_normal.corner_radius_bottom_right = BUTTON_CORNER_RADIUS
	style_normal.content_margin_left = 20
	style_normal.content_margin_right = 20
	style_normal.content_margin_top = 12
	style_normal.content_margin_bottom = 12
	
	# Hover StyleBox
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = BUTTON_HOVER_COLOR
	
	# Pressed StyleBox
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = BUTTON_PRESSED_COLOR
	
	# Focus StyleBox (gleich wie hover)
	var style_focus = style_hover.duplicate()
	
	# Styles anwenden
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("focus", style_focus)


func _connect_signals() -> void:
	button_start.pressed.connect(_on_start_pressed)
	button_load.pressed.connect(_on_load_pressed)
	button_options.pressed.connect(_on_options_pressed)
	button_quit.pressed.connect(_on_quit_pressed)


func _update_viewport_size() -> void:
	# SubViewport an Fenstergröße anpassen
	var window_size = get_viewport().get_visible_rect().size
	sub_viewport.size = Vector2i(window_size)


func _update_camera_sway(delta: float) -> void:
	time_elapsed += delta
	
	# Sanfte Sinus-Bewegung für natürliches Schwanken
	var sway_x = sin(time_elapsed * camera_sway_speed) * camera_sway_amount
	var sway_y = sin(time_elapsed * camera_sway_speed * 0.7) * camera_sway_amount * 0.5
	
	camera_pivot.rotation_degrees.y = sway_x
	camera_pivot.rotation_degrees.x = sway_y


# === Button Callbacks ===

func _on_start_pressed() -> void:

	if has_node("/root/Hud"):
		get_node("/root/Hud").show()

	get_tree().change_scene_to_file(game_scene_path)
	



func _on_load_pressed() -> void:
	print("Load button pressed!")
	
	if not GameManager.has_save_file():
		#_show_notification("No save file found!")
		return
	
	# Menü schließen BEVOR wir laden (falls Szene wechselt)
	#_is_open = false
	visible = false
	get_tree().paused = false
	
	# Laden (kann Szene wechseln)
	if await GameManager.load_game():
		if has_node("/root/Hud"):
			get_node("/root/Hud").show()
	
		get_tree().change_scene_to_file(game_scene_path)
	else:
		# Falls Laden fehlschlägt, Menü wieder öffnen
		visible = true
		get_tree().paused = true
		#_show_notification("Load Failed!")


func _on_options_pressed() -> void:
	print("Öffne Optionen...")
	# TODO: Options-Menü als Overlay oder Szene
	# Beispiel: get_tree().change_scene_to_file(options_scene_path)


func _on_quit_pressed() -> void:
	print("Spiel wird beendet...")
	get_tree().quit()

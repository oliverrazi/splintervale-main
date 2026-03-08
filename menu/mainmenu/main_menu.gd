extends Control

## Hauptmenü mit 3D-Hintergrund und sanfter Kamera-Bewegung

# Pfade zu deinen Szenen anpassen
@export var game_scene_path: String = "res://demo.tscn"
@export var options_scene_path: String = "res://scenes/ui/options/options.tscn"
@export var select_sound: AudioStream
@export var confirm_sound: AudioStream
var _select_player: AudioStreamPlayer
var _confirm_player: AudioStreamPlayer
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
const BUTTON_FOCUS_COLOR = Color(1.0, 1.0, 1.0, 0.3)
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
var menu_buttons: Array[Button] = []

var _initial_focus_done: bool = false
var _last_focused_button: Button = null
var _block_select_sound: bool = false


func _ready() -> void:
	if has_node("/root/Hud"):
		get_node("/root/Hud").hide()
	
	_load_font()
	_setup_sounds()
	_setup_buttons()
	_setup_navigation()
	_connect_signals()
	_update_viewport_size()
	
	get_tree().root.size_changed.connect(_update_viewport_size)
	
	# Ersten Button fokussieren nach kurzer Verzögerung
	await get_tree().process_frame
	button_start.grab_focus()
	await get_tree().process_frame
	_initial_focus_done = true


func _process(delta: float) -> void:
	_update_camera_sway(delta)


func _setup_sounds() -> void:
	_select_player = AudioStreamPlayer.new()
	_select_player.bus = "UI"
	_select_player.stream = select_sound
	add_child(_select_player)
	
	_confirm_player = AudioStreamPlayer.new()
	_confirm_player.bus = "UI"
	_confirm_player.stream = confirm_sound
	add_child(_confirm_player)



func _on_button_focused(button: Button) -> void:
	if not _initial_focus_done or _block_select_sound:
		_last_focused_button = button
		return
	if button != _last_focused_button:
		if _select_player and _select_player.stream:
			_select_player.play()
		_last_focused_button = button


func _play_confirm_sound() -> void:
	if _confirm_player and _confirm_player.stream:
		_block_select_sound = true
		_confirm_player.play()
		get_tree().create_timer(0.15).timeout.connect(func(): _block_select_sound = false)


func _load_font() -> void:
	if ResourceLoader.exists(FONT_PATH):
		base_font = load(FONT_PATH)
	else:
		push_warning("Font nicht gefunden: %s - Verwende Standard-Font" % FONT_PATH)
		base_font = ThemeDB.fallback_font


func _setup_buttons() -> void:
	menu_buttons = [button_start, button_load, button_options, button_quit]
	
	for button in menu_buttons:
		_style_button(button)
		button.focus_entered.connect(_on_button_focused.bind(button))
		button.pressed.connect(_play_confirm_sound)


func _setup_navigation() -> void:
	# Vertikale Navigation zwischen Buttons einrichten
	for i in range(menu_buttons.size()):
		var button = menu_buttons[i]
		
		# Vorheriger Button (nach oben)
		var prev_index = i - 1 if i > 0 else menu_buttons.size() - 1
		button.focus_neighbor_top = menu_buttons[prev_index].get_path()
		
		# Nächster Button (nach unten)
		var next_index = i + 1 if i < menu_buttons.size() - 1 else 0
		button.focus_neighbor_bottom = menu_buttons[next_index].get_path()
		
		# Links/Rechts auf sich selbst (verhindert ungewollte Navigation)
		button.focus_neighbor_left = button.get_path()
		button.focus_neighbor_right = button.get_path()


func _style_button(button: Button) -> void:
	# Font-Einstellungen
	button.add_theme_font_override("font", base_font)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", FONT_COLOR)
	button.add_theme_color_override("font_hover_color", FONT_COLOR)
	button.add_theme_color_override("font_pressed_color", FONT_COLOR)
	button.add_theme_color_override("font_focus_color", FONT_COLOR)
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
	
	# Focus StyleBox - deutlich sichtbar für Gamepad/Tastatur
	var style_focus = style_normal.duplicate()
	style_focus.bg_color = BUTTON_FOCUS_COLOR
	style_focus.border_width_left = 3
	style_focus.border_width_right = 3
	style_focus.border_width_top = 3
	style_focus.border_width_bottom = 3
	style_focus.border_color = FONT_COLOR
	
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
	var window_size = get_viewport().get_visible_rect().size
	sub_viewport.size = Vector2i(window_size)


func _update_camera_sway(delta: float) -> void:
	time_elapsed += delta
	
	var sway_x = sin(time_elapsed * camera_sway_speed) * camera_sway_amount
	var sway_y = sin(time_elapsed * camera_sway_speed * 0.7) * camera_sway_amount * 0.5
	
	camera_pivot.rotation_degrees.y = sway_x
	camera_pivot.rotation_degrees.x = sway_y


# === Button Callbacks ===

func _on_start_pressed() -> void:
	if has_node("/root/SceneTransition"):
		get_node("/root/SceneTransition").transition_to_game(game_scene_path)
	else:
		_simple_transition(game_scene_path)


func _on_load_pressed() -> void:
	if not GameManager.has_save_file():
		return
	
	if has_node("/root/SceneTransition"):
		get_node("/root/SceneTransition").transition_to_game(game_scene_path, true)
	else:
		await GameManager.load_game()
		_simple_transition(game_scene_path)


func _simple_transition(scene_path: String) -> void:
	if has_node("/root/Hud"):
		get_node("/root/Hud").show()
	get_tree().change_scene_to_file(scene_path)


func _on_options_pressed() -> void:
	print("Öffne Optionen...")


func _on_quit_pressed() -> void:
	get_tree().quit()

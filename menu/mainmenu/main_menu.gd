extends Control

## Hauptmenü mit 3D-Hintergrund und sanfter Kamera-Bewegung
## Im Amber/Braun-Stil. Options werden als Overlay über SettingsUI angezeigt.

# ══════════════════════════════════════════════════════════════
#  EXPORTS
# ══════════════════════════════════════════════════════════════

@export var game_scene_path: String = "res://demo.tscn"
@export var select_sound: AudioStream
@export var confirm_sound: AudioStream

@export var camera_sway_speed: float = 0.3
@export var camera_sway_amount: float = 2.0


# ══════════════════════════════════════════════════════════════
#  FARBEN
# ══════════════════════════════════════════════════════════════

const C_BG_DEEP     := Color("14100a")
const C_BORDER_OUT  := Color("5c3d1e")
const C_AMBER       := Color("c4923a")
const C_TEXT_LIGHT  := Color("d4b880")
const C_TEXT_MID    := Color("8a7050")
const C_TEXT_MUTED  := Color("6b5030")
const C_DANGER      := Color("c46a3a")


# ══════════════════════════════════════════════════════════════
#  FONT
# ══════════════════════════════════════════════════════════════

const FONT_PATH := "res://menu/assets/fonts/Merriweather-Regular.ttf"


# ══════════════════════════════════════════════════════════════
#  STATE
# ══════════════════════════════════════════════════════════════

var _select_player: AudioStreamPlayer  = null
var _confirm_player: AudioStreamPlayer = null

var time_elapsed: float     = 0.0
var base_font: Font         = null
var menu_buttons: Array[Button] = []

var _initial_focus_done: bool    = false
var _last_focused_button: Button = null
var _block_select_sound: bool    = false

# Options-Overlay
var _options_overlay: Control   = null
var _options_dim: ColorRect     = null
var _options_ui: SettingsUI     = null
var _options_open: bool         = false


# ══════════════════════════════════════════════════════════════
#  NODE REFERENZEN
# ══════════════════════════════════════════════════════════════

@onready var camera_pivot: Node3D          = $SubViewportContainer/SubViewport/MenuScene3D/CameraPivot
@onready var sub_viewport: SubViewport     = $SubViewportContainer/SubViewport
@onready var button_start: Button          = $Overlay/UIRoot/MarginContainer/VBoxContainer/MenuContainer/ButtonStart
@onready var button_load: Button           = $Overlay/UIRoot/MarginContainer/VBoxContainer/MenuContainer/ButtonLoad
@onready var button_options: Button        = $Overlay/UIRoot/MarginContainer/VBoxContainer/MenuContainer/ButtonOptions
@onready var button_quit: Button           = $Overlay/UIRoot/MarginContainer/VBoxContainer/MenuContainer/ButtonQuit


# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════

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
	
	if not GameManager.has_save_file():
		_set_button_disabled(button_load, true)
	
	# Zwei Frames warten bis Layout vollständig steht, dann Focus setzen
	await get_tree().process_frame
	await get_tree().process_frame
	button_start.grab_focus()
	_initial_focus_done = true


func _process(delta: float) -> void:
	_update_camera_sway(delta)


func _unhandled_input(event: InputEvent) -> void:
	# ESC schließt das Options-Overlay
	if _options_open and event.is_action_pressed("ui_cancel", false):
		_close_options_overlay()
		get_viewport().set_input_as_handled()


func _load_font() -> void:
	if ResourceLoader.exists(FONT_PATH):
		base_font = load(FONT_PATH)
	else:
		push_warning("Font nicht gefunden: %s" % FONT_PATH)
		base_font = ThemeDB.fallback_font


# ══════════════════════════════════════════════════════════════
#  SOUNDS
# ══════════════════════════════════════════════════════════════

func _setup_sounds() -> void:
	_select_player = AudioStreamPlayer.new()
	_select_player.bus    = "UI"
	_select_player.stream = select_sound
	add_child(_select_player)
	
	_confirm_player = AudioStreamPlayer.new()
	_confirm_player.bus    = "UI"
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


# ══════════════════════════════════════════════════════════════
#  BUTTONS
# ══════════════════════════════════════════════════════════════

func _setup_buttons() -> void:
	menu_buttons = [button_start, button_load, button_options, button_quit]
	
	_style_menu_button(button_start,   C_AMBER)
	_style_menu_button(button_load,    C_AMBER)
	_style_menu_button(button_options, C_AMBER)
	_style_menu_button(button_quit,    C_DANGER)
	
	for button in menu_buttons:
		button.focus_entered.connect(_on_button_focused.bind(button))
		button.pressed.connect(_play_confirm_sound)


func _style_menu_button(btn: Button, accent_color: Color) -> void:
	btn.custom_minimum_size = Vector2(260, 52)
	btn.focus_mode = Control.FOCUS_ALL
	
	var normal := StyleBoxFlat.new()
	normal.bg_color              = Color(C_BG_DEEP.r, C_BG_DEEP.g, C_BG_DEEP.b, 0.85)
	normal.border_color          = C_BORDER_OUT
	normal.border_width_left     = 2
	normal.border_width_top      = 1
	normal.border_width_right    = 1
	normal.border_width_bottom   = 1
	normal.content_margin_left   = 22
	normal.content_margin_right  = 22
	normal.content_margin_top    = 12
	normal.content_margin_bottom = 12
	
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color            = Color(accent_color.r, accent_color.g, accent_color.b, 0.15)
	hover.border_color        = accent_color
	hover.border_width_left   = 3
	hover.content_margin_left = 21
	
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.28)
	
	var focus := hover.duplicate() as StyleBoxFlat
	
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color     = Color(C_BG_DEEP.r, C_BG_DEEP.g, C_BG_DEEP.b, 0.4)
	disabled.border_color = Color(C_BORDER_OUT, 0.4)
	
	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed)
	btn.add_theme_stylebox_override("focus",    focus)
	btn.add_theme_stylebox_override("disabled", disabled)
	
	if base_font:
		btn.add_theme_font_override("font", base_font)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color",          C_TEXT_MID)
	btn.add_theme_color_override("font_hover_color",    accent_color)
	btn.add_theme_color_override("font_pressed_color",  C_TEXT_LIGHT)
	btn.add_theme_color_override("font_focus_color",    accent_color)
	btn.add_theme_color_override("font_disabled_color", Color(C_TEXT_MUTED, 0.4))
	
	btn.remove_theme_color_override("font_outline_color")
	btn.remove_theme_constant_override("outline_size")


func _set_button_disabled(btn: Button, disabled: bool) -> void:
	btn.disabled = disabled
	# focus_mode bleibt FOCUS_ALL — Godot skippt disabled Buttons
	# automatisch bei Navigation; Tastatur/Gamepad funktionieren weiter.


func _setup_navigation() -> void:
	# Alle Buttons in die Navigations-Kette. Godot skippt disabled Buttons
	# beim Navigieren automatisch — keine manuelle Filterung nötig.
	for i in range(menu_buttons.size()):
		var button := menu_buttons[i]
		var prev_index: int = i - 1 if i > 0 else menu_buttons.size() - 1
		var next_index: int = i + 1 if i < menu_buttons.size() - 1 else 0
		button.focus_neighbor_top    = menu_buttons[prev_index].get_path()
		button.focus_neighbor_bottom = menu_buttons[next_index].get_path()
		button.focus_neighbor_left   = button.get_path()
		button.focus_neighbor_right  = button.get_path()


# ══════════════════════════════════════════════════════════════
#  SIGNALS + VIEWPORT
# ══════════════════════════════════════════════════════════════

func _connect_signals() -> void:
	button_start.pressed.connect(_on_start_pressed)
	button_load.pressed.connect(_on_load_pressed)
	button_options.pressed.connect(_on_options_pressed)
	button_quit.pressed.connect(_on_quit_pressed)


func _update_viewport_size() -> void:
	var window_size := get_viewport().get_visible_rect().size
	sub_viewport.size = Vector2i(window_size)


func _update_camera_sway(delta: float) -> void:
	time_elapsed += delta
	var sway_x: float = sin(time_elapsed * camera_sway_speed)       * camera_sway_amount
	var sway_y: float = sin(time_elapsed * camera_sway_speed * 0.7) * camera_sway_amount * 0.5
	camera_pivot.rotation_degrees.y = sway_x
	camera_pivot.rotation_degrees.x = sway_y


# ══════════════════════════════════════════════════════════════
#  OPTIONS OVERLAY
# ══════════════════════════════════════════════════════════════

func _open_options_overlay() -> void:
	if _options_open:
		return
	_options_open = true
	
	if _options_overlay == null:
		_build_options_overlay()
	
	_options_overlay.visible = true
	_options_overlay.modulate.a = 0.0
	
	var tween := create_tween()
	tween.tween_property(_options_overlay, "modulate:a", 1.0, 0.2)
	tween.tween_callback(func():
		if _options_ui:
			_options_ui.focus_first()
	)


func _close_options_overlay() -> void:
	if not _options_open:
		return
	_options_open = false
	
	var tween := create_tween()
	tween.tween_property(_options_overlay, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func():
		_options_overlay.visible = false
		button_options.grab_focus()
	)


func _build_options_overlay() -> void:
	# CanvasLayer garantiert dass wir über ALLEM anderen liegen,
	# unabhängig vom Parent-Tree. z_index auf Controls reicht nicht
	# wenn die Buttons in einem anderen Sub-Tree liegen.
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	
	_options_overlay = Control.new()
	_options_overlay.name = "OptionsOverlay"
	_options_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options_overlay.visible = false
	_options_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(_options_overlay)
	
	# Dim-Layer
	_options_dim = ColorRect.new()
	_options_dim.color = Color(0, 0, 0, 0.6)
	_options_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_options_overlay.add_child(_options_dim)
	
	# Zentriertes Panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options_overlay.add_child(center)
	
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 560)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color              = C_BG_DEEP
	sb.border_color          = C_BORDER_OUT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left   = 24
	sb.content_margin_right  = 24
	sb.content_margin_top    = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	
	# SettingsUI im Standalone-Modus
	_options_ui = SettingsUI.new()
	_options_ui.name = "OptionsUI"
	_options_ui.show_save_load = false
	_options_ui.standalone_mode = true
	_options_ui.close_requested.connect(_close_options_overlay)
	panel.add_child(_options_ui)


# ══════════════════════════════════════════════════════════════
#  BUTTON HANDLERS
# ══════════════════════════════════════════════════════════════

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
	_open_options_overlay()


func _on_quit_pressed() -> void:
	get_tree().quit()

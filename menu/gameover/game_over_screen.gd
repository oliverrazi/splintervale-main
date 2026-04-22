extends CanvasLayer

## Game Over Screen im Menü-Stil
## Drei Aktionen: Load Last Save / Return to Title / Quit to Desktop
## Autobuild: baut alle Child-Nodes selbst auf, Scene-Tree kann leer sein
## (nur dieser Script am Root-CanvasLayer nötig)

signal load_pressed
signal title_pressed
signal quit_pressed


# ══════════════════════════════════════════════════════════════
#  EXPORTS
# ══════════════════════════════════════════════════════════════

@export var select_sound_path: String  = "res://menu/assets/sounds/select.wav"
@export var confirm_sound_path: String = "res://menu/assets/sounds/confirm.wav"
@export var title_scene_path: String   = "res://menu/mainmenu/main_menu.tscn"
@export var player_name: String        = "Daryn"


# ══════════════════════════════════════════════════════════════
#  FARBEN (synchron mit Pause-Menü)
# ══════════════════════════════════════════════════════════════

const C_BG_DARK     := Color("0a0605", 0.96)
const C_BG_DEEP     := Color("14100a")
const C_BORDER_OUT  := Color("5c3d1e")
const C_AMBER       := Color("c4923a")
const C_TEXT_LIGHT  := Color("d4b880")
const C_TEXT_MID    := Color("8a7050")
const C_TEXT_MUTED  := Color("6b5030")
const C_DANGER      := Color("c46a3a")
const C_BLOOD       := Color("a04235")    # Titel-Farbe, gedämpftes Blutrot


# ══════════════════════════════════════════════════════════════
#  STATE
# ══════════════════════════════════════════════════════════════

var _font: FontFile = null
var _menu_buttons: Array[Button] = []
var _initial_focus_done: bool  = false
var _last_focused_button: Button = null
var _block_select_sound: bool   = false

var select_sound: AudioStreamPlayer  = null
var confirm_sound: AudioStreamPlayer = null

# UI
var _background: ColorRect   = null
var _content: Control        = null
var _title_label: Label      = null
var _subtitle_label: Label   = null
var _load_button: Button     = null
var _title_button: Button    = null
var _quit_button: Button     = null


# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════

func _ready() -> void:
	layer = 100
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_load_font()
	_clear_existing_children()
	_build_ui()
	_setup_sounds()
	_setup_navigation()
	
	# Start-Zustand
	_background.modulate.a = 0.0
	_content.modulate.a    = 0.0


func _load_font() -> void:
	var path := "res://menu/assets/fonts/Merriweather-Regular.ttf"
	if ResourceLoader.exists(path):
		_font = load(path) as FontFile


func _clear_existing_children() -> void:
	# Alte editor-gebaute Struktur aufräumen
	for child in get_children():
		child.queue_free()


# ══════════════════════════════════════════════════════════════
#  UI AUFBAU
# ══════════════════════════════════════════════════════════════

func _build_ui() -> void:
	# ── Hintergrund (voll opak, sehr dunkel) ─────────────
	_background = ColorRect.new()
	_background.color = C_BG_DARK
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP   # blockiert Click auf Spielwelt
	add_child(_background)
	
	# ── Content-Ebene (Titel + Buttons) ──────────────────
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.add_child(center)
	
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(360, 0)
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)
	
	# ── Titel ────────────────────────────────────────────
	_build_title_block(vbox)
	
	# ── Spacer ───────────────────────────────────────────
	var sep := ColorRect.new()
	sep.color                 = Color(C_BORDER_OUT, 0.5)
	sep.custom_minimum_size   = Vector2(0, 1)
	vbox.add_child(sep)
	
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 12
	vbox.add_child(spacer)
	
	# ── Buttons ──────────────────────────────────────────
	_load_button  = _build_menu_button("Load Last Save",    C_AMBER)
	_title_button = _build_menu_button("Return to Title",   C_AMBER)
	_quit_button  = _build_menu_button("Quit to Desktop",   C_DANGER)
	
	_menu_buttons = [_load_button, _title_button, _quit_button]
	
	for btn in _menu_buttons:
		vbox.add_child(btn)
	
	_load_button.pressed.connect(_on_load_pressed)
	_title_button.pressed.connect(_on_title_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	
	for btn in _menu_buttons:
		btn.focus_entered.connect(_on_button_focused.bind(btn))
		btn.pressed.connect(_play_confirm_sound)


func _build_title_block(parent: VBoxContainer) -> void:
	
	# Haupt-Titel "GAME OVER"
	_title_label = Label.new()
	_title_label.text                 = "GAME OVER"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 40)
	_title_label.add_theme_color_override("font_color", C_BLOOD)
	if _font:
		_title_label.add_theme_font_override("font", _font)
	parent.add_child(_title_label)
	
	# Untertitel
	_subtitle_label = Label.new()
	_subtitle_label.text                 = "%s's journey ends here..." % player_name
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 13)
	_subtitle_label.add_theme_color_override("font_color", C_TEXT_MUTED)
	if _font:
		_subtitle_label.add_theme_font_override("font", _font)
	parent.add_child(_subtitle_label)
	
	# Kleiner Abstand vor dem Separator
	var pad := Control.new()
	pad.custom_minimum_size.y = 8
	parent.add_child(pad)


func _build_menu_button(label: String, accent_color: Color) -> Button:
	var btn := Button.new()
	btn.text                      = label
	btn.custom_minimum_size       = Vector2(0, 46)
	btn.size_flags_horizontal     = Control.SIZE_EXPAND_FILL
	btn.focus_mode                = Control.FOCUS_ALL
	
	var normal := StyleBoxFlat.new()
	normal.bg_color              = C_BG_DEEP
	normal.border_color          = C_BORDER_OUT
	normal.border_width_left     = 2
	normal.border_width_top      = 1
	normal.border_width_right    = 1
	normal.border_width_bottom   = 1
	normal.content_margin_left   = 20
	normal.content_margin_right  = 20
	normal.content_margin_top    = 10
	normal.content_margin_bottom = 10
	
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color            = Color(accent_color.r, accent_color.g, accent_color.b, 0.08)
	hover.border_color        = accent_color
	hover.border_width_left   = 3
	hover.content_margin_left = 19
	
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.18)
	
	var focus := hover.duplicate() as StyleBoxFlat
	
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus",   focus)
	
	btn.add_theme_color_override("font_color",         C_TEXT_MID)
	btn.add_theme_color_override("font_hover_color",   accent_color)
	btn.add_theme_color_override("font_pressed_color", C_TEXT_LIGHT)
	btn.add_theme_color_override("font_focus_color",   accent_color)
	btn.add_theme_font_size_override("font_size", 14)
	if _font:
		btn.add_theme_font_override("font", _font)
	
	return btn


# ══════════════════════════════════════════════════════════════
#  NAVIGATION + SOUNDS
# ══════════════════════════════════════════════════════════════

func _setup_navigation() -> void:
	for i in range(_menu_buttons.size()):
		var btn := _menu_buttons[i]
		btn.focus_neighbor_top    = _menu_buttons[i - 1].get_path() if i > 0 else btn.get_path()
		btn.focus_neighbor_bottom = _menu_buttons[i + 1].get_path() if i < _menu_buttons.size() - 1 else btn.get_path()
		btn.focus_neighbor_left   = btn.get_path()
		btn.focus_neighbor_right  = btn.get_path()


func _setup_sounds() -> void:
	select_sound = AudioStreamPlayer.new()
	select_sound.bus = "UI"
	if ResourceLoader.exists(select_sound_path):
		select_sound.stream = load(select_sound_path)
	add_child(select_sound)
	
	confirm_sound = AudioStreamPlayer.new()
	confirm_sound.bus = "UI"
	if ResourceLoader.exists(confirm_sound_path):
		confirm_sound.stream = load(confirm_sound_path)
	add_child(confirm_sound)


func _on_button_focused(button: Button) -> void:
	if not _initial_focus_done:
		_last_focused_button = button
		return
	if _block_select_sound:
		_last_focused_button = button
		return
	if button != _last_focused_button:
		if select_sound and select_sound.stream:
			select_sound.play()
		_last_focused_button = button


func _play_confirm_sound() -> void:
	if confirm_sound and confirm_sound.stream:
		_block_select_sound = true
		confirm_sound.play()
		get_tree().create_timer(0.15).timeout.connect(func(): _block_select_sound = false)


# ══════════════════════════════════════════════════════════════
#  SHOW / HIDE
# ══════════════════════════════════════════════════════════════

func show_game_over(delay: float = 2.0) -> void:
	visible = true
	
	# Nach dem Delay: langsamer Fade-In
	await get_tree().create_timer(delay).timeout
	
	var tween := create_tween()
	tween.tween_property(_background, "modulate:a", 1.0, 1.0)
	tween.tween_interval(0.5)
	tween.tween_property(_content, "modulate:a", 1.0, 0.6)
	tween.tween_callback(func():
		if _load_button:
			_load_button.grab_focus()
		await get_tree().process_frame
		_initial_focus_done = true
	)


func hide_game_over() -> void:
	_initial_focus_done = false
	var tween := create_tween()
	tween.parallel().tween_property(_content, "modulate:a", 0.0, 0.2)
	tween.parallel().tween_property(_background, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		visible = false
	)


# ══════════════════════════════════════════════════════════════
#  BUTTON HANDLERS
# ══════════════════════════════════════════════════════════════

func _on_load_pressed() -> void:
	load_pressed.emit()
	hide_game_over()
	
	if GameManager.has_save_file():
		GameManager.load_game()
	else:
		# Kein Save File - aktuelle Szene neu laden
		var current_scene := get_tree().current_scene.scene_file_path
		if has_node("/root/LoadingScreen"):
			LoadingScreen.load_scene(current_scene)
		else:
			get_tree().change_scene_to_file(current_scene)


func _on_title_pressed() -> void:
	title_pressed.emit()
	hide_game_over()
	
	if ResourceLoader.exists(title_scene_path):
		if has_node("/root/LoadingScreen"):
			LoadingScreen.load_scene(title_scene_path)
		else:
			get_tree().change_scene_to_file(title_scene_path)
	else:
		push_warning("Title scene not found: %s" % title_scene_path)


func _on_quit_pressed() -> void:
	quit_pressed.emit()
	get_tree().quit()

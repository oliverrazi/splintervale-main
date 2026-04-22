extends Control
class_name SettingsUI

## Settings UI für das Pause-Menü
## Hauptansicht: Save / Load / Settings / Quit
## Sub-View: Audio / Display / Controls (Placeholders)

signal save_requested
signal load_requested
signal quit_requested
signal close_requested

# ══════════════════════════════════════════════════════════════
#  FARBEN (synchron mit Menü)
# ══════════════════════════════════════════════════════════════

const C_BG_DEEP     := Color("14100a")
const C_BG_TOME     := Color("1e1810", 0.9)
const C_BORDER      := Color("2e1f0e")
const C_BORDER_OUT  := Color("5c3d1e")
const C_AMBER       := Color("c4923a")
const C_AMBER_DIM   := Color("c4923a", 0.20)
const C_AMBER_FAINT := Color("c4923a", 0.06)
const C_TEXT_LIGHT  := Color("d4b880")
const C_TEXT_MID   := Color("8a7050")
const C_TEXT_MUTED  := Color("6b5030")
const C_DANGER      := Color("c46a3a")


# ══════════════════════════════════════════════════════════════
#  STATE
# ══════════════════════════════════════════════════════════════

enum View { MAIN, SETTINGS }

var _current_view: View = View.MAIN
var _font: FontFile = null

var _main_buttons: Array[Button]     = []
var _settings_controls: Array[Control] = []

# Confirm Dialog state
var _confirm_active: bool          = false
var _confirm_callback: Callable    = Callable()


# ══════════════════════════════════════════════════════════════
#  UI REFERENZEN
# ══════════════════════════════════════════════════════════════

var _main_view: Control          = null
var _settings_view: Control      = null

var _save_btn: Button            = null
var _load_btn: Button            = null
var _settings_btn: Button        = null
var _quit_btn: Button            = null

# Settings controls
var _master_slider: HSlider      = null
var _music_slider: HSlider       = null
var _sfx_slider: HSlider         = null
var _fullscreen_check: CheckButton = null
var _back_btn: Button            = null

# Toast
var _toast_panel: PanelContainer = null
var _toast_label: Label          = null
var _toast_tween: Tween          = null

# Confirm dialog
var _confirm_overlay: Control    = null
var _confirm_yes_btn: Button     = null
var _confirm_no_btn: Button      = null
var _confirm_title: Label        = null


@export var show_save_load: bool = true
@export var standalone_mode: bool = false

# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_font()
	_build_ui()
	
	if show_save_load:
		_show_main_view()
	else:
		# Standalone-Modus: Main-View komplett ausblenden,
		# direkt Settings zeigen. Back-Button emittiert close_requested.
		_main_view.visible = false
		_show_settings_view()


func _load_font() -> void:
	var path := "res://menu/assets/fonts/Merriweather-Regular.ttf"
	if ResourceLoader.exists(path):
		_font = load(path) as FontFile
		var t := Theme.new()
		t.default_font      = _font
		t.default_font_size = 13
		theme = t


# ══════════════════════════════════════════════════════════════
#  UI AUFBAU
# ══════════════════════════════════════════════════════════════

func _build_ui() -> void:
	_build_main_view()
	_build_settings_view()
	_build_toast()
	_build_confirm_dialog()


# ── MAIN VIEW (Save / Load / Settings / Quit) ─────────────────
func _build_main_view() -> void:
	_main_view = Control.new()
	_main_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_view.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_main_view)
	
	# Zentriertes Layout
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_view.add_child(center)
	
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(280, 0)
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)
	
	# Section-Header "MENU" oben
	vbox.add_child(_build_section_header("Menu"))
	
	# Spacing
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size.y = 8
	vbox.add_child(top_spacer)
	
	# Buttons
	_save_btn     = _build_menu_button("Save Game",  C_AMBER)
	_load_btn     = _build_menu_button("Load Game",  C_AMBER)
	_settings_btn = _build_menu_button("Settings",   C_AMBER)
	_quit_btn     = _build_menu_button("Quit",       C_DANGER)
	
	_main_buttons = [_save_btn, _load_btn, _settings_btn, _quit_btn]
	
	for btn in _main_buttons:
		vbox.add_child(btn)
	
	_save_btn.pressed.connect(_on_save_pressed)
	_load_btn.pressed.connect(_on_load_pressed)
	_settings_btn.pressed.connect(_on_settings_pressed)
	_quit_btn.pressed.connect(_on_quit_pressed)
	
	_setup_main_navigation()


func _build_menu_button(label: String, accent_color: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 46)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	
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
	hover.bg_color          = Color(accent_color.r, accent_color.g, accent_color.b, 0.08)
	hover.border_color      = accent_color
	hover.border_width_left = 3
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


func _setup_main_navigation() -> void:
	for i in range(_main_buttons.size()):
		var btn := _main_buttons[i]
		btn.focus_neighbor_top    = _main_buttons[i - 1].get_path() if i > 0 else btn.get_path()
		btn.focus_neighbor_bottom = _main_buttons[i + 1].get_path() if i < _main_buttons.size() - 1 else btn.get_path()
		btn.focus_neighbor_left   = btn.get_path()
		btn.focus_neighbor_right  = btn.get_path()


# ── SETTINGS VIEW ──────────────────────────────────────────────
func _build_settings_view() -> void:
	_settings_view = Control.new()
	_settings_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_view.visible = false
	_settings_view.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_settings_view)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_view.add_child(center)
	
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
	
	vbox.add_child(_build_section_header("Settings"))
	
	# ── AUDIO ─────────────────────────────────────────
	var audio_section := VBoxContainer.new()
	audio_section.add_theme_constant_override("separation", 10)
	vbox.add_child(audio_section)
	audio_section.add_child(_build_subsection_header("Audio"))
	
	_master_slider = _build_slider_row(audio_section, "Master Volume", 80, "master")
	_music_slider  = _build_slider_row(audio_section, "Music",          70, "music")
	_sfx_slider    = _build_slider_row(audio_section, "Sound Effects",  80, "sfx")
	
	# ── DISPLAY ───────────────────────────────────────
	var display_section := VBoxContainer.new()
	display_section.add_theme_constant_override("separation", 10)
	vbox.add_child(display_section)
	display_section.add_child(_build_subsection_header("Display"))
	
	_fullscreen_check = _build_toggle_row(display_section, "Fullscreen",
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	
	# ── CONTROLS ──────────────────────────────────────
	var controls_section := VBoxContainer.new()
	controls_section.add_theme_constant_override("separation", 10)
	vbox.add_child(controls_section)
	controls_section.add_child(_build_subsection_header("Controls"))
	
	var coming_soon := Label.new()
	coming_soon.text = "Key bindings coming soon."
	coming_soon.add_theme_color_override("font_color", C_TEXT_MUTED)
	coming_soon.add_theme_font_size_override("font_size", 12)
	if _font:
		coming_soon.add_theme_font_override("font", _font)
	controls_section.add_child(coming_soon)
	
	# ── BACK ──────────────────────────────────────────
	var back_spacer := Control.new()
	back_spacer.custom_minimum_size.y = 12
	vbox.add_child(back_spacer)
	
	_back_btn = _build_menu_button("Back", C_AMBER)
	vbox.add_child(_back_btn)
	_back_btn.pressed.connect(_show_main_view)
	
	# Liste der fokussierbaren Settings-Elemente
	_settings_controls = [_master_slider, _music_slider, _sfx_slider,
							_fullscreen_check, _back_btn]
	_setup_settings_navigation()


func _build_subsection_header(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var dia := Label.new()
	dia.text = "◆"
	dia.add_theme_font_size_override("font_size", 6)
	dia.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	dia.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(C_AMBER, 0.65))
	if _font:
		lbl.add_theme_font_override("font", _font)
	
	var line := ColorRect.new()
	line.color                 = Color(C_BORDER_OUT, 0.5)
	line.custom_minimum_size   = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	
	row.add_child(dia)
	row.add_child(lbl)
	row.add_child(line)
	return row


func _build_slider_row(parent: VBoxContainer, label_text: String,
						initial_value: int, bus_name: String) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140
	lbl.add_theme_color_override("font_color", C_TEXT_MID)
	lbl.add_theme_font_size_override("font_size", 13)
	if _font:
		lbl.add_theme_font_override("font", _font)
	row.add_child(lbl)
	
	var slider := HSlider.new()
	slider.min_value            = 0
	slider.max_value            = 100
	slider.value                = initial_value
	slider.step                 = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size   = Vector2(0, 20)
	slider.focus_mode            = Control.FOCUS_ALL
	slider.set_meta("bus_name", bus_name)
	_style_slider(slider)
	row.add_child(slider)
	
	var val_lbl := Label.new()
	val_lbl.custom_minimum_size.x = 32
	val_lbl.text = str(initial_value)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_color_override("font_color", C_TEXT_LIGHT)
	val_lbl.add_theme_font_size_override("font_size", 13)
	if _font:
		val_lbl.add_theme_font_override("font", _font)
	row.add_child(val_lbl)
	
	slider.value_changed.connect(func(v: float):
		val_lbl.text = str(int(v))
		_apply_volume(bus_name, v / 100.0)
	)
	
	# Initial anwenden
	_apply_volume(bus_name, initial_value / 100.0)
	
	return slider


func _style_slider(slider: HSlider) -> void:
	# Track background
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = C_BG_DEEP
	bg_sb.border_color = C_BORDER_OUT
	bg_sb.set_border_width_all(1)
	bg_sb.set_corner_radius_all(2)
	bg_sb.content_margin_top    = 6
	bg_sb.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", bg_sb)
	
	# Fill (grabber-gefüllter Bereich)
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = C_AMBER
	fill_sb.set_corner_radius_all(2)
	slider.add_theme_stylebox_override("grabber_area", fill_sb)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_sb)
	
	# Grabber (runder Knopf)
	var grabber_sb := StyleBoxFlat.new()
	grabber_sb.bg_color = C_TEXT_LIGHT
	grabber_sb.border_color = C_AMBER
	grabber_sb.set_border_width_all(1)
	grabber_sb.set_corner_radius_all(8)
	grabber_sb.content_margin_left   = 8
	grabber_sb.content_margin_right  = 8
	grabber_sb.content_margin_top    = 8
	grabber_sb.content_margin_bottom = 8
	slider.add_theme_stylebox_override("grabber", grabber_sb)
	slider.add_theme_stylebox_override("grabber_highlight", grabber_sb)


func _build_toggle_row(parent: VBoxContainer, label_text: String,
						initial_state: bool) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", C_TEXT_MID)
	lbl.add_theme_font_size_override("font_size", 13)
	if _font:
		lbl.add_theme_font_override("font", _font)
	row.add_child(lbl)
	
	var check := CheckButton.new()
	check.button_pressed = initial_state
	check.focus_mode = Control.FOCUS_ALL
	check.add_theme_color_override("font_color",         C_TEXT_MID)
	check.add_theme_color_override("font_hover_color",   C_TEXT_LIGHT)
	check.add_theme_color_override("font_pressed_color", C_AMBER)
	check.add_theme_font_size_override("font_size", 13)
	if _font:
		check.add_theme_font_override("font", _font)
	row.add_child(check)
	
	return check


func _setup_settings_navigation() -> void:
	for i in range(_settings_controls.size()):
		var ctrl := _settings_controls[i]
		if i > 0:
			ctrl.focus_neighbor_top = _settings_controls[i - 1].get_path()
		else:
			ctrl.focus_neighbor_top = ctrl.get_path()
		
		if i < _settings_controls.size() - 1:
			ctrl.focus_neighbor_bottom = _settings_controls[i + 1].get_path()
		else:
			ctrl.focus_neighbor_bottom = ctrl.get_path()


# ── TOAST ──────────────────────────────────────────────────────
func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.visible = false
	_toast_panel.z_index = 100
	_toast_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toast_panel.position = Vector2(-260, 20)
	_toast_panel.custom_minimum_size = Vector2(240, 0)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color              = Color(C_BG_DEEP.r, C_BG_DEEP.g, C_BG_DEEP.b, 0.95)
	sb.border_color          = C_AMBER
	sb.border_width_left     = 3
	sb.border_width_top      = 1
	sb.border_width_right    = 1
	sb.border_width_bottom   = 1
	sb.set_corner_radius_all(2)
	sb.content_margin_left   = 14
	sb.content_margin_right  = 14
	sb.content_margin_top    = 10
	sb.content_margin_bottom = 10
	_toast_panel.add_theme_stylebox_override("panel", sb)
	add_child(_toast_panel)
	
	_toast_label = Label.new()
	_toast_label.add_theme_color_override("font_color", C_TEXT_LIGHT)
	_toast_label.add_theme_font_size_override("font_size", 13)
	if _font:
		_toast_label.add_theme_font_override("font", _font)
	_toast_panel.add_child(_toast_label)


func show_toast(text: String, is_error: bool = false) -> void:
	if _toast_panel == null:
		return
	
	_toast_label.text = text
	
	# Accent-Farbe je nach Typ
	var sb := _toast_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		var new_sb := sb.duplicate() as StyleBoxFlat
		new_sb.border_color = C_DANGER if is_error else C_AMBER
		_toast_panel.add_theme_stylebox_override("panel", new_sb)
	
	_toast_panel.visible = true
	_toast_panel.modulate.a = 0.0
	
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func(): _toast_panel.visible = false)


# ── CONFIRM DIALOG ─────────────────────────────────────────────
func _build_confirm_dialog() -> void:
	_confirm_overlay = Control.new()
	_confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.visible = false
	_confirm_overlay.z_index = 90
	add_child(_confirm_overlay)
	
	# Dunkle Hintergrund-Ebene
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_overlay.add_child(dim)
	
	# Zentrierter Dialog
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(center)
	
	var dialog := PanelContainer.new()
	dialog.custom_minimum_size = Vector2(340, 0)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color              = C_BG_DEEP
	dsb.border_color          = C_AMBER
	dsb.set_border_width_all(1)
	dsb.set_corner_radius_all(2)
	dsb.content_margin_left   = 24
	dsb.content_margin_right  = 24
	dsb.content_margin_top    = 20
	dsb.content_margin_bottom = 20
	dialog.add_theme_stylebox_override("panel", dsb)
	center.add_child(dialog)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	dialog.add_child(vbox)
	
	_confirm_title = Label.new()
	_confirm_title.text = ""
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_title.add_theme_color_override("font_color", C_TEXT_LIGHT)
	_confirm_title.add_theme_font_size_override("font_size", 15)
	if _font:
		_confirm_title.add_theme_font_override("font", _font)
	vbox.add_child(_confirm_title)
	
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	
	_confirm_no_btn = _build_menu_button("No",  C_AMBER)
	_confirm_no_btn.custom_minimum_size = Vector2(120, 40)
	btn_row.add_child(_confirm_no_btn)
	
	_confirm_yes_btn = _build_menu_button("Yes", C_DANGER)
	_confirm_yes_btn.custom_minimum_size = Vector2(120, 40)
	btn_row.add_child(_confirm_yes_btn)
	
	# Navigation
	_confirm_no_btn.focus_neighbor_right = _confirm_yes_btn.get_path()
	_confirm_yes_btn.focus_neighbor_left = _confirm_no_btn.get_path()
	
	_confirm_no_btn.pressed.connect(_close_confirm)
	_confirm_yes_btn.pressed.connect(_accept_confirm)


func _show_confirm(title: String, callback: Callable) -> void:
	_confirm_title.text = title
	_confirm_callback = callback
	_confirm_active = true
	_confirm_overlay.visible = true
	await get_tree().process_frame
	_confirm_no_btn.grab_focus()   # Default: "No" fokussiert


func _close_confirm() -> void:
	_confirm_active = false
	_confirm_overlay.visible = false
	_confirm_callback = Callable()
	# Fokus zurück zum auslösenden Button (falls möglich)
	_return_focus_after_dialog()


func _accept_confirm() -> void:
	var cb := _confirm_callback
	_close_confirm()
	if cb.is_valid():
		cb.call()


func _return_focus_after_dialog() -> void:
	# Im MAIN View → passender Main-Button; im SETTINGS View → erster Settings-Control
	if _current_view == View.MAIN:
		_quit_btn.grab_focus()
	else:
		if _settings_controls.size() > 0:
			_settings_controls[0].grab_focus()


# ══════════════════════════════════════════════════════════════
#  SECTION-HEADER (Menu-Stil)
# ══════════════════════════════════════════════════════════════

func _build_section_header(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var line_l := ColorRect.new()
	line_l.color                 = Color(C_BORDER_OUT, 0.7)
	line_l.custom_minimum_size   = Vector2(8, 1)
	line_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_l.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	
	var dia_l := Label.new()
	dia_l.text = "◆"
	dia_l.add_theme_font_size_override("font_size", 8)
	dia_l.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	
	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(C_AMBER, 0.85))
	if _font:
		lbl.add_theme_font_override("font", _font)
	
	var dia_r := Label.new()
	dia_r.text = "◆"
	dia_r.add_theme_font_size_override("font_size", 8)
	dia_r.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	
	var line_r := ColorRect.new()
	line_r.color                 = Color(C_BORDER_OUT, 0.7)
	line_r.custom_minimum_size   = Vector2(8, 1)
	line_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_r.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	
	row.add_child(line_l)
	row.add_child(dia_l)
	row.add_child(lbl)
	row.add_child(dia_r)
	row.add_child(line_r)
	return row


# ══════════════════════════════════════════════════════════════
#  VIEW SWITCHING
# ══════════════════════════════════════════════════════════════

func _show_main_view() -> void:
	if not show_save_load:
		# Im Standalone-Modus: Back = Fenster schließen
		close_requested.emit()
		return
	
	_current_view = View.MAIN
	_main_view.visible = true
	_settings_view.visible = false
	await get_tree().process_frame
	if _save_btn:
		_save_btn.grab_focus()


func _show_settings_view() -> void:
	_current_view = View.SETTINGS
	_main_view.visible = false
	_settings_view.visible = true
	await get_tree().process_frame
	if _master_slider:
		_master_slider.grab_focus()


# ══════════════════════════════════════════════════════════════
#  BUTTON HANDLERS
# ══════════════════════════════════════════════════════════════

func _on_save_pressed() -> void:
	save_requested.emit()


func _on_load_pressed() -> void:
	_show_confirm("Load the last save?\nUnsaved progress will be lost.",
		Callable(self, "_emit_load"))


func _emit_load() -> void:
	load_requested.emit()


func _on_settings_pressed() -> void:
	_show_settings_view()


func _on_quit_pressed() -> void:
	_show_confirm("Quit to desktop?",
		Callable(self, "_emit_quit"))


func _emit_quit() -> void:
	quit_requested.emit()


# ══════════════════════════════════════════════════════════════
#  AUDIO / DISPLAY
# ══════════════════════════════════════════════════════════════

func _apply_volume(bus_name: String, value: float) -> void:
	var bus_display := bus_name.capitalize()
	var idx := AudioServer.get_bus_index(bus_display)
	
	# Fallback: Master-Bus immer Index 0
	if idx < 0 and bus_name == "master":
		idx = 0
	
	if idx < 0:
		return
	
	if value <= 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(value))


func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# ══════════════════════════════════════════════════════════════
#  PUBLIC API (für pause_menu.gd)
# ══════════════════════════════════════════════════════════════

# Wird von pause_menu.gd beim Betreten des Settings-Tabs aufgerufen
func focus_first() -> void:
	if _current_view == View.MAIN:
		if _save_btn:
			_save_btn.grab_focus()
	else:
		if _master_slider:
			_master_slider.grab_focus()


# Wird von pause_menu.gd bei ESC aufgerufen
# Gibt true zurück wenn der ESC-Druck "verbraucht" wurde
# (weil Confirm offen war oder Settings-View offen war)
func handle_back() -> bool:
	if _confirm_active:
		_close_confirm()
		return true
	if _current_view == View.SETTINGS:
		_show_main_view()
		return true
	return false


func get_focusable_controls() -> Array[Control]:
	if _current_view == View.MAIN:
		var result: Array[Control] = []
		for btn in _main_buttons:
			result.append(btn)
		return result
	else:
		return _settings_controls.duplicate()

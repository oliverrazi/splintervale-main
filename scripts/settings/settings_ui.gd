extends Control
class_name SettingsUI

## Settings UI für das Pause-Menü
##
## Hauptansicht: Save / Load / Settings / Quit
## Sub-View: Tab-System mit Audio / Graphics / Display / Controls
##
## Navigation:
##   - Hauptansicht: Pfeil-Hoch/Runter
##   - Settings-View: Pfeil-Hoch/Runter wechselt den aktiven Tab in der Tab-Liste
##   - Enter / Pfeil-Rechts: geht vom Tab in den Tab-Inhalt
##   - Im Tab-Inhalt: Pfeil-Hoch/Runter zwischen Optionen, Pfeil-Hoch ganz oben → zurück zur Tab-Liste
##   - ESC: Back (vom Tab-Inhalt zur Tab-Liste, von Settings zur Hauptansicht, von Hauptansicht raus)

signal save_requested
signal load_requested
signal quit_requested
signal close_requested

# ══════════════════════════════════════════════════════════════
#  FARBEN
# ══════════════════════════════════════════════════════════════

const C_BG_DEEP     := Color("14100a")
const C_BG_TOME     := Color("1e1810", 0.9)
const C_BORDER      := Color("2e1f0e")
const C_BORDER_OUT  := Color("5c3d1e")
const C_AMBER       := Color("c4923a")
const C_AMBER_DIM   := Color("c4923a", 0.20)
const C_AMBER_FAINT := Color("c4923a", 0.06)
const C_TEXT_LIGHT  := Color("d4b880")
const C_TEXT_MID    := Color("8a7050")
const C_TEXT_MUTED  := Color("6b5030")
const C_DANGER      := Color("c46a3a")


# ══════════════════════════════════════════════════════════════
#  STATE
# ══════════════════════════════════════════════════════════════

enum View { MAIN, SETTINGS }
enum SettingsTab { AUDIO, GRAPHICS, DISPLAY, CONTROLS }

var _current_view: View = View.MAIN
var _current_tab: SettingsTab = SettingsTab.AUDIO
var _font: FontFile = null

var _main_buttons: Array[Button]            = []
var _tab_buttons: Array[Button]             = []
var _tab_panels: Array[Control]             = []  # Inhalt jedes Tabs
var _tab_focusables: Array[Array]           = []  # Pro Tab: focusable Controls

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

# Settings tab content
var _tab_list: VBoxContainer     = null
var _tab_content: Control        = null
var _back_btn: Button            = null

# Audio
var _master_slider: HSlider      = null
var _music_slider: HSlider       = null
var _sfx_slider: HSlider         = null

# Graphics
var _dof_shape_option: OptionButton   = null
var _dof_quality_option: OptionButton = null
var _dof_jitter_check: CheckButton    = null

# Display
var _fullscreen_check: CheckButton    = null
var _vsync_check: CheckButton         = null

var _toast_panel: PanelContainer = null
var _toast_label: Label          = null
var _toast_tween: Tween          = null

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


# ── MAIN VIEW ──────────────────────────────────────────────────
func _build_main_view() -> void:
	_main_view = Control.new()
	_main_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_view.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_main_view)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_view.add_child(center)
	
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(280, 0)
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)
	
	vbox.add_child(_build_section_header("Menu"))
	
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size.y = 8
	vbox.add_child(top_spacer)
	
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


# ── SETTINGS VIEW (Tab-System) ─────────────────────────────────
func _build_settings_view() -> void:
	_settings_view = Control.new()
	_settings_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_view.visible = false
	_settings_view.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_settings_view)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_view.add_child(center)
	
	var outer := VBoxContainer.new()
	outer.custom_minimum_size = Vector2(620, 0)
	outer.add_theme_constant_override("separation", 14)
	center.add_child(outer)
	
	outer.add_child(_build_section_header("Settings"))
	
	# Hauptbereich: Tab-Liste links + Tab-Inhalt rechts
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(hbox)
	
	_build_tab_list(hbox)
	_build_tab_content_area(hbox)


func _build_tab_list(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 280)
	panel.size_flags_vertical = Control.SIZE_FILL
	
	var sb := StyleBoxFlat.new()
	sb.bg_color              = C_BG_DEEP
	sb.border_color          = Color(C_BORDER_OUT, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left   = 8
	sb.content_margin_right  = 8
	sb.content_margin_top    = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	
	_tab_list = VBoxContainer.new()
	_tab_list.add_theme_constant_override("separation", 4)
	panel.add_child(_tab_list)
	
	# Tabs in Reihenfolge: Audio, Graphics, Display, Controls
	_tab_buttons = [
		_build_tab_button("Audio",    SettingsTab.AUDIO),
		_build_tab_button("Graphics", SettingsTab.GRAPHICS),
		_build_tab_button("Display",  SettingsTab.DISPLAY),
		_build_tab_button("Controls", SettingsTab.CONTROLS),
	]
	for btn in _tab_buttons:
		_tab_list.add_child(btn)
	
	# Tab-Liste Navigation: nur hoch/runter
	for i in range(_tab_buttons.size()):
		var b := _tab_buttons[i]
		b.focus_neighbor_top    = _tab_buttons[i - 1].get_path() if i > 0 else b.get_path()
		b.focus_neighbor_bottom = _tab_buttons[i + 1].get_path() if i < _tab_buttons.size() - 1 else b.get_path()
		b.focus_neighbor_left   = b.get_path()
		# Pfeil-Rechts auf einem Tab: in den Tab-Inhalt rein
		# (wird per script gesetzt sobald Tab-Inhalte gebaut sind, in _link_tab_to_content)


func _build_tab_button(label: String, tab_id: SettingsTab) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.set_meta("tab_id", tab_id)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	# Stylebox-Set für Tab-Button
	var normal := StyleBoxFlat.new()
	normal.bg_color              = Color(0, 0, 0, 0)
	normal.border_color          = Color(C_BORDER_OUT, 0.0)
	normal.border_width_left     = 2
	normal.set_corner_radius_all(2)
	normal.content_margin_left   = 12
	normal.content_margin_right  = 8
	normal.content_margin_top    = 6
	normal.content_margin_bottom = 6
	
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color     = C_AMBER_FAINT
	hover.border_color = Color(C_AMBER, 0.5)
	
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = C_AMBER_DIM
	
	var focus := hover.duplicate() as StyleBoxFlat
	focus.bg_color     = C_AMBER_FAINT
	focus.border_color = C_AMBER
	
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus",   focus)
	
	btn.add_theme_color_override("font_color",         C_TEXT_MID)
	btn.add_theme_color_override("font_hover_color",   C_AMBER)
	btn.add_theme_color_override("font_pressed_color", C_TEXT_LIGHT)
	btn.add_theme_color_override("font_focus_color",   C_AMBER)
	btn.add_theme_font_size_override("font_size", 13)
	if _font:
		btn.add_theme_font_override("font", _font)
	
	btn.pressed.connect(_on_tab_pressed.bind(tab_id))
	btn.focus_entered.connect(_on_tab_focused.bind(tab_id))
	
	return btn


func _build_tab_content_area(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 280)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_FILL
	
	var sb := StyleBoxFlat.new()
	sb.bg_color              = C_BG_DEEP
	sb.border_color          = Color(C_BORDER_OUT, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left   = 20
	sb.content_margin_right  = 20
	sb.content_margin_top    = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	
	# Innerer VBox: Tab-Inhalt oben + Back-Button unten rechts
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	
	# Tab-Content-Container (alle Panels werden hier gestackt)
	_tab_content = Control.new()
	_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tab_content)
	
	# Initial-Werte aus Settings-Autoload
	var s_master: float    = 0.8
	var s_music: float     = 0.7
	var s_sfx: float       = 0.8
	var s_fullscreen: bool = false
	var s_vsync: bool      = false
	var s_dof_shape: int   = 1
	var s_dof_quality: int = 2
	var s_dof_jitter: bool = false
	
	if has_node("/root/Settings"):
		var st: Node = get_node("/root/Settings")
		s_master      = st.master_volume
		s_music       = st.music_volume
		s_sfx         = st.sfx_volume
		s_fullscreen  = st.fullscreen
		s_vsync       = st.vsync_enabled
		s_dof_shape   = st.dof_bokeh_shape
		s_dof_quality = st.dof_bokeh_quality
		s_dof_jitter  = st.dof_use_jitter
	
	# Tabs aufbauen — pro Tab ein Panel + Liste der Focusables
	_tab_panels = []
	_tab_focusables = []
	
	# AUDIO
	var audio_panel := _build_audio_panel(s_master, s_music, s_sfx)
	_tab_content.add_child(audio_panel)
	_tab_panels.append(audio_panel)
	_tab_focusables.append([_master_slider, _music_slider, _sfx_slider])
	
	# GRAPHICS
	var graphics_panel := _build_graphics_panel(s_dof_shape, s_dof_quality, s_dof_jitter)
	_tab_content.add_child(graphics_panel)
	_tab_panels.append(graphics_panel)
	_tab_focusables.append([_dof_shape_option, _dof_quality_option, _dof_jitter_check])
	
	# DISPLAY
	var display_panel := _build_display_panel(s_fullscreen, s_vsync)
	_tab_content.add_child(display_panel)
	_tab_panels.append(display_panel)
	_tab_focusables.append([_fullscreen_check, _vsync_check])
	
	# CONTROLS (Placeholder)
	var controls_panel := _build_controls_panel()
	_tab_content.add_child(controls_panel)
	_tab_panels.append(controls_panel)
	_tab_focusables.append([])  # nichts focusable
	
	# Back-Button unten rechts
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(back_row)
	
	_back_btn = _build_menu_button("Back", C_AMBER)
	_back_btn.custom_minimum_size = Vector2(140, 40)
	_back_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	back_row.add_child(_back_btn)
	_back_btn.pressed.connect(_on_back_pressed)
	
	# Initial-Tab anzeigen
	_select_tab(SettingsTab.AUDIO)
	
	# Tab → Tab-Inhalt Verlinkung (Pfeil-Rechts vom Tab springt zum ersten Element)
	_link_tab_navigation()

func _on_back_pressed() -> void:
	# Gleiche Logik wie ESC: hierarchisch zurück
	# Tab-Inhalt → Tab-Liste, Tab-Liste → Main-View / Overlay schließen
	if not handle_back():
		# handle_back gab false zurück → manuell den View-Wechsel auslösen
		_show_main_view()

func _link_tab_navigation() -> void:
	for i in range(_tab_buttons.size()):
		var tab_btn := _tab_buttons[i]
		var focusables: Array = _tab_focusables[i]
		
		if focusables.is_empty():
			# Kein Inhalt → Pfeil-Rechts geht direkt zum Back-Button
			tab_btn.focus_neighbor_right = _back_btn.get_path()
		else:
			# Pfeil-Rechts auf Tab → erstes Element des Tabs
			var first: Control = focusables[0]
			tab_btn.focus_neighbor_right = first.get_path()
		
		# Innerhalb des Tabs: Pfeil-Hoch/Runter zwischen Elementen,
		# Pfeil-Hoch ganz oben → zurück zum Tab-Button (links)
		# Pfeil-Runter ganz unten → Back-Button
		# Pfeil-Links überall → zurück zum Tab-Button
		for j in range(focusables.size()):
			var ctrl: Control = focusables[j]
			
			# Hoch
			if j > 0:
				ctrl.focus_neighbor_top = focusables[j - 1].get_path()
			else:
				# Erstes Element: hoch → Tab-Button (links)
				ctrl.focus_neighbor_top = tab_btn.get_path()
			
			# Runter
			if j < focusables.size() - 1:
				ctrl.focus_neighbor_bottom = focusables[j + 1].get_path()
			else:
				# Letztes Element: runter → Back-Button
				ctrl.focus_neighbor_bottom = _back_btn.get_path()
			
			# Links → zurück zur Tab-Liste
			ctrl.focus_neighbor_left = tab_btn.get_path()
			# Rechts → bleibt (Trap rechts)
			ctrl.focus_neighbor_right = ctrl.get_path()
	
	# Back-Button: Hoch → letztes Element des aktiven Tabs (dynamisch),
	# Links → Tab-Liste (aktueller Tab), Runter/Rechts → bleibt
	# Wir setzen das beim Tab-Wechsel in _select_tab()


# ── AUDIO PANEL ───────────────────────────────────────────────
func _build_audio_panel(s_master: float, s_music: float, s_sfx: float) -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	
	vbox.add_child(_build_subsection_header("Audio"))
	
	_master_slider = _build_slider_row(vbox, "Master Volume", int(s_master * 100), "master")
	_music_slider  = _build_slider_row(vbox, "Music",         int(s_music * 100),  "music")
	_sfx_slider    = _build_slider_row(vbox, "Sound Effects", int(s_sfx * 100),    "sfx")
	
	return panel


# ── GRAPHICS PANEL ────────────────────────────────────────────
func _build_graphics_panel(s_shape: int, s_quality: int, s_jitter: bool) -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	
	vbox.add_child(_build_subsection_header("Graphics"))
	
	_dof_shape_option = _build_option_row(vbox, "Depth of Field Shape",
		["Box", "Hexagon", "Circle"], s_shape)
	_dof_shape_option.item_selected.connect(_on_dof_shape_selected)
	
	_dof_quality_option = _build_option_row(vbox, "Depth of Field Quality",
		["Very Low", "Low", "Medium", "High"], s_quality)
	_dof_quality_option.item_selected.connect(_on_dof_quality_selected)
	
	_dof_jitter_check = _build_toggle_row(vbox, "DoF Use Jitter", s_jitter)
	_dof_jitter_check.toggled.connect(_on_dof_jitter_toggled)
	
	return panel


# ── DISPLAY PANEL ─────────────────────────────────────────────
func _build_display_panel(s_fullscreen: bool, s_vsync: bool) -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	
	vbox.add_child(_build_subsection_header("Display"))
	
	_fullscreen_check = _build_toggle_row(vbox, "Fullscreen", s_fullscreen)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	
	_vsync_check = _build_toggle_row(vbox, "VSync", s_vsync)
	_vsync_check.toggled.connect(_on_vsync_toggled)
	
	return panel


# ── CONTROLS PANEL ────────────────────────────────────────────
func _build_controls_panel() -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	
	vbox.add_child(_build_subsection_header("Controls"))
	
	var coming_soon := Label.new()
	coming_soon.text = "Key bindings coming soon."
	coming_soon.add_theme_color_override("font_color", C_TEXT_MUTED)
	coming_soon.add_theme_font_size_override("font_size", 12)
	if _font:
		coming_soon.add_theme_font_override("font", _font)
	vbox.add_child(coming_soon)
	
	return panel


# ── HEADERS / ROWS ────────────────────────────────────────────
func _build_subsection_header(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var dia := Label.new()
	dia.text = "◆"
	dia.add_theme_font_size_override("font_size", 7)
	dia.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	dia.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(C_AMBER, 0.75))
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
	lbl.custom_minimum_size.x = 160
	lbl.add_theme_color_override("font_color", C_TEXT_MID)
	lbl.add_theme_font_size_override("font_size", 13)
	if _font:
		lbl.add_theme_font_override("font", _font)
	row.add_child(lbl)
	
	var slider := HSlider.new()
	slider.min_value             = 0
	slider.max_value             = 100
	slider.value                 = initial_value
	slider.step                  = 1
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
	
	return slider


func _style_slider(slider: HSlider) -> void:
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = C_BG_DEEP
	bg_sb.border_color = C_BORDER_OUT
	bg_sb.set_border_width_all(1)
	bg_sb.set_corner_radius_all(2)
	bg_sb.content_margin_top    = 6
	bg_sb.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", bg_sb)
	
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = C_AMBER
	fill_sb.set_corner_radius_all(2)
	slider.add_theme_stylebox_override("grabber_area", fill_sb)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_sb)
	
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
	lbl.custom_minimum_size.x = 160
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


func _build_option_row(parent: VBoxContainer, label_text: String,
						items: Array, initial_index: int) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 160
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", C_TEXT_MID)
	lbl.add_theme_font_size_override("font_size", 13)
	if _font:
		lbl.add_theme_font_override("font", _font)
	row.add_child(lbl)
	
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_ALL
	opt.custom_minimum_size = Vector2(140, 28)
	for i in range(items.size()):
		opt.add_item(str(items[i]), i)
	opt.selected = clamp(initial_index, 0, items.size() - 1)
	_style_option_button(opt)
	row.add_child(opt)
	
	return opt


func _style_option_button(opt: OptionButton) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color              = C_BG_DEEP
	normal.border_color          = C_BORDER_OUT
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left   = 10
	normal.content_margin_right  = 10
	normal.content_margin_top    = 4
	normal.content_margin_bottom = 4
	
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color     = C_AMBER_FAINT
	hover.border_color = C_AMBER
	
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = C_AMBER_DIM
	
	var focus := hover.duplicate() as StyleBoxFlat
	
	opt.add_theme_stylebox_override("normal",  normal)
	opt.add_theme_stylebox_override("hover",   hover)
	opt.add_theme_stylebox_override("pressed", pressed)
	opt.add_theme_stylebox_override("focus",   focus)
	
	opt.add_theme_color_override("font_color",         C_TEXT_LIGHT)
	opt.add_theme_color_override("font_hover_color",   C_AMBER)
	opt.add_theme_color_override("font_pressed_color", C_TEXT_LIGHT)
	opt.add_theme_color_override("font_focus_color",   C_TEXT_LIGHT)
	opt.add_theme_font_size_override("font_size", 12)
	if _font:
		opt.add_theme_font_override("font", _font)


# ══════════════════════════════════════════════════════════════
#  TAB SWITCHING
# ══════════════════════════════════════════════════════════════

func _on_tab_pressed(tab_id: SettingsTab) -> void:
	_select_tab(tab_id)
	# Beim Drücken (Enter) → ersten Inhalt fokussieren falls vorhanden
	var focusables: Array = _tab_focusables[tab_id]
	if not focusables.is_empty():
		await get_tree().process_frame
		focusables[0].grab_focus()


func _on_tab_focused(tab_id: SettingsTab) -> void:
	# Beim Fokussieren: Tab-Inhalt sichtbar machen, aber Focus bleibt auf Tab-Button
	_select_tab(tab_id)


func _select_tab(tab_id: SettingsTab) -> void:
	_current_tab = tab_id
	for i in range(_tab_panels.size()):
		_tab_panels[i].visible = (i == int(tab_id))
	
	# Back-Button-Navigation aktualisieren: Hoch → letztes focusable des aktiven Tabs
	# Links → aktiver Tab-Button
	var focusables: Array = _tab_focusables[tab_id]
	if focusables.is_empty():
		_back_btn.focus_neighbor_top = _tab_buttons[tab_id].get_path()
	else:
		_back_btn.focus_neighbor_top = focusables[focusables.size() - 1].get_path()
	_back_btn.focus_neighbor_left   = _tab_buttons[tab_id].get_path()
	_back_btn.focus_neighbor_right  = _back_btn.get_path()
	_back_btn.focus_neighbor_bottom = _back_btn.get_path()


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
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_overlay.add_child(dim)
	
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
	
	# Yes LINKS, No RECHTS
	_confirm_yes_btn = _build_menu_button("Yes", C_DANGER)
	_confirm_yes_btn.custom_minimum_size = Vector2(120, 40)
	btn_row.add_child(_confirm_yes_btn)
	
	_confirm_no_btn = _build_menu_button("No",  C_AMBER)
	_confirm_no_btn.custom_minimum_size = Vector2(120, 40)
	btn_row.add_child(_confirm_no_btn)
	
	# Focus-Trap: Yes ↔ No, kein Ausbrechen
	_confirm_yes_btn.focus_neighbor_left   = _confirm_yes_btn.get_path()
	_confirm_yes_btn.focus_neighbor_right  = _confirm_no_btn.get_path()
	_confirm_yes_btn.focus_neighbor_top    = _confirm_yes_btn.get_path()
	_confirm_yes_btn.focus_neighbor_bottom = _confirm_yes_btn.get_path()
	_confirm_no_btn.focus_neighbor_left    = _confirm_yes_btn.get_path()
	_confirm_no_btn.focus_neighbor_right   = _confirm_no_btn.get_path()
	_confirm_no_btn.focus_neighbor_top     = _confirm_no_btn.get_path()
	_confirm_no_btn.focus_neighbor_bottom  = _confirm_no_btn.get_path()
	
	_confirm_no_btn.pressed.connect(_close_confirm)
	_confirm_yes_btn.pressed.connect(_accept_confirm)


func _show_confirm(title: String, callback: Callable) -> void:
	_confirm_title.text = title
	_confirm_callback = callback
	_confirm_active = true
	_confirm_overlay.visible = true
	await get_tree().process_frame
	_confirm_no_btn.grab_focus()


func _close_confirm() -> void:
	_confirm_active = false
	_confirm_overlay.visible = false
	_confirm_callback = Callable()
	_return_focus_after_dialog()


func _accept_confirm() -> void:
	var cb := _confirm_callback
	_close_confirm()
	if cb.is_valid():
		cb.call()


func _return_focus_after_dialog() -> void:
	if _current_view == View.MAIN:
		_quit_btn.grab_focus()
	else:
		if _tab_buttons.size() > 0:
			_tab_buttons[_current_tab].grab_focus()


# ══════════════════════════════════════════════════════════════
#  SECTION-HEADER
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
	# Initial: Audio-Tab fokussieren
	await get_tree().process_frame
	_select_tab(SettingsTab.AUDIO)
	if _tab_buttons.size() > 0:
		_tab_buttons[0].grab_focus()


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
#  AUDIO / DISPLAY / GRAPHICS
# ══════════════════════════════════════════════════════════════

func _apply_volume(bus_name: String, value: float) -> void:
	if has_node("/root/Settings"):
		var s: Node = get_node("/root/Settings")
		match bus_name:
			"master":
				s.master_volume = value
			"music":
				s.music_volume = value
			"sfx":
				s.sfx_volume = value
		return
	
	# Fallback ohne Autoload
	var bus_display := bus_name.capitalize()
	var idx := AudioServer.get_bus_index(bus_display)
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
	if has_node("/root/Settings"):
		get_node("/root/Settings").fullscreen = pressed
		return
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_vsync_toggled(pressed: bool) -> void:
	if has_node("/root/Settings"):
		get_node("/root/Settings").vsync_enabled = pressed
		return
	if pressed:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _on_dof_shape_selected(idx: int) -> void:
	if has_node("/root/Settings"):
		get_node("/root/Settings").dof_bokeh_shape = idx


func _on_dof_quality_selected(idx: int) -> void:
	if has_node("/root/Settings"):
		get_node("/root/Settings").dof_bokeh_quality = idx


func _on_dof_jitter_toggled(pressed: bool) -> void:
	if has_node("/root/Settings"):
		get_node("/root/Settings").dof_use_jitter = pressed


# ══════════════════════════════════════════════════════════════
#  PUBLIC API (für pause_menu.gd)
# ══════════════════════════════════════════════════════════════

func focus_first() -> void:
	if _current_view == View.MAIN:
		if _save_btn:
			_save_btn.grab_focus()
	else:
		if _tab_buttons.size() > 0:
			_tab_buttons[0].grab_focus()


# Wird von pause_menu.gd bei ESC aufgerufen.
# Gibt true zurück wenn ESC verbraucht wurde.
func handle_back() -> bool:
	# Confirm offen → schließen
	if _confirm_active:
		_close_confirm()
		return true
	
	# Settings-View: prüfen ob Focus im Tab-Inhalt liegt
	if _current_view == View.SETTINGS:
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		if focus_owner:
			# Wenn Focus im Tab-Inhalt oder beim Back-Button → zurück zum Tab-Button
			var on_tab_button: bool = _tab_buttons.has(focus_owner)
			if not on_tab_button:
				if _tab_buttons.size() > 0:
					_tab_buttons[_current_tab].grab_focus()
				return true
		# Focus liegt auf Tab-Button → kompletten Settings-View verlassen
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
		var result: Array[Control] = []
		for btn in _tab_buttons:
			result.append(btn)
		return result

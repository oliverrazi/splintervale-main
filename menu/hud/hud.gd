extends CanvasLayer

## HUD — komplett codebasiert
##
## Scene-Tree kann leer sein (nur dieser CanvasLayer als Root).
## Alle Nodes werden im Code erstellt:
##   - Character-Pod (Portrait mit portrait_hud.gdshader + SmoothPixelUI, Bars)
##   - D-Pad Hotbar mit Keycaps
##   - Delay-Bars für Schaden/Ressourcen-Verlust

# ══════════════════════════════════════════════════════════════
#  KONFIGURATION
# ══════════════════════════════════════════════════════════════

const PORTRAIT_SHADER_PATH: String     = "res://menu/hud/shaders/portrait_hud.gdshader"
const SMOOTH_PIXEL_SCRIPT_PATH: String = "res://menu/shaders/smooth_pixel_ui.gd"
const PORTRAIT_PATH: String            = "res://assets/characters/portraits/daryn.png"

const HEART_ICON_PATH: String = "res://assets/icons/heart.png"
const RESONANCE_ICON_PATH: String = "res://assets/icons/resonance.png"

const PORTRAIT_SIZE: float = 76.0
const BAR_WIDTH: float     = 220.0
const BAR_HEIGHT: float    = 20.0
const SLOT_SIZE: float     = 48.0
const KEYCAP_SIZE: float   = 18.0
const DPAD_GAP: float      = 10.0

# Editor-Werte deines Portrait-Shaders (aus dem Screenshot übernommen)
const PORTRAIT_RING_GRADIENT_START  := Color("c4923a")
const PORTRAIT_RING_GRADIENT_END    := Color("e6c580")
const PORTRAIT_RING_INACTIVE_COLOR  := Color("2a1f12")
const PORTRAIT_RING_WIDTH: float    = 0.01
const PORTRAIT_BG_COLOR_A           := Color("5c3d1e")
const PORTRAIT_BG_COLOR_B           := Color("2a1f12", 0.5)
const PORTRAIT_NOISE_SCALE: float   = 6.0
const PORTRAIT_NOISE_INTENSITY: float = 0.822
const PORTRAIT_TIME_SCALE: float    = 0.08

# Menü-Farbpalette
const C_BG_DEEP     := Color("14100a")
const C_BG_TOME     := Color("1e1810", 0.9)
const C_BORDER      := Color("2e1f0e")
const C_BORDER_OUT  := Color("5c3d1e")
const C_AMBER       := Color("c4923a")
const C_AMBER_FAINT := Color("c4923a", 0.14)
const C_TEXT_LIGHT  := Color("d4b880")
const C_TEXT_MID    := Color("8a7050")

# Multi-Color Gradients für Bars
const HP_GRADIENT_STOPS: Array = [
	Color("4a1818"),
	Color("7a2020"),
	Color("b02a2a"),
	Color("d44040"),
	Color("e66060"),
	Color("f5a060"),
]

const RP_GRADIENT_STOPS: Array = [
	Color("162448"),
	Color("233a6e"),
	Color("3a5a8e"),
	Color("5478ad"),
	Color("7a9bc8"),
	Color("b5cce0"),
]

# Delay-Bar Gradient: warmer Amber/Gold-Verlauf, passend zur Menü-Palette
const DELAY_GRADIENT_STOPS: Array = [
	Color("5c3d1e"),   # tief-Amber (Shadow)
	Color("8a5e28"),
	Color("b57a2e"),
	Color("d49a3e"),
	Color("e8c96a"),
	Color("f5e4a0"),   # heller Gold-Schimmer (Top-Highlight)
]

const COMBO_FONT_PATH: String = "res://menu/assets/fonts/Cinzel-Bold.ttf"

@export_group("Delay Bar")
@export var delay_bar_color: Color = Color("e8c96a", 0.85)   # Warmes Gelb/Amber
@export var delay_bar_wait: float  = 0.3
@export var delay_bar_speed: float = 0.5


# ══════════════════════════════════════════════════════════════
#  STATE
# ══════════════════════════════════════════════════════════════

var _font: FontFile       = null
var _portrait_shader: Shader = null
var _smooth_pixel_script: Script = null

# Stats
var max_hp: int            = 100
var current_hp: int        = 100
var max_resonance: int     = 30
var current_resonance: int = 30
var max_exp: int           = 100
var current_exp: int       = 0
var gold: int              = 0
var level: int             = 1

# UI Refs
var _hud_root: Control            = null
var _portrait_wrap: Control       = null
var _portrait_circle: TextureRect = null
var _level_label: Label           = null

var _hp_bar: ProgressBar       = null
var _hp_delay_bar: ProgressBar = null
var _rp_bar: ProgressBar       = null
var _rp_delay_bar: ProgressBar = null

var _action_slots: Array[PanelContainer] = []
var _hotbar_icons: Array[TextureRect]    = []

# Delay Bar State
var _hp_delay_tween: Tween = null
var _rp_delay_tween: Tween = null
var _rp_anim_tween: Tween  = null
var _rp_tween_target: int  = -99999   # Aktueller Ziel-Wert des laufenden RP-Tweens

# Slot-0 Interaktions-Icon
var _interact_icon: Texture2D = null
var _action_icon: Texture2D   = null
var _cached_slot_0_texture: Texture2D = null

var _combo_widget: Control = null
var _combo_label: Label = null
var _multiplier_label: Label = null
var _combo_vbox: VBoxContainer = null
var _current_combo_count: int = 0

var _heart_icon: Texture2D = null
var _resonance_icon: Texture2D = null
# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("hud")
	
	_load_font()
	_load_icons()
	_load_portrait_shader()
	_load_smooth_pixel_script()
	_clear_existing_children()
	#_build_ui()
	
	call_deferred("_connect_to_player_data")
	call_deferred("_connect_to_inventory")
	call_deferred("_setup_portrait_texture")
	
	if has_node("/root/LoadingScreen"):
		LoadingScreen.loading_finished.connect(_on_loading_finished)
		
	if has_node("/root/SceneTransition"):
		var st = get_node("/root/SceneTransition")
		if st.has_signal("scene_transition_completed"):
			st.scene_transition_completed.connect(_on_scene_transition_completed)
	
	
	
func _on_scene_transition_completed() -> void:
	# Nach jedem Szenen-Wechsel: HUD-Connections neu aufbauen
	_connect_to_player_data()
	_connect_to_inventory()
	_connect_to_synergy_manager()

func _process(_delta: float) -> void:
	_update_slot_w_interaction_state()
	_update_hp_display()
	_update_resonance_display()


func _load_font() -> void:
	var path := "res://menu/assets/fonts/Merriweather-Regular.ttf"
	if ResourceLoader.exists(path):
		_font = load(path) as FontFile


func _load_icons() -> void:
	var interact_path := "res://assets/icons/talk_icon.png"
	if ResourceLoader.exists(interact_path):
		_interact_icon = load(interact_path)
	var action_path := "res://assets/icons/action_icon.png"
	if ResourceLoader.exists(action_path):
		_action_icon = load(action_path)
	if ResourceLoader.exists(HEART_ICON_PATH):
		_heart_icon = load(HEART_ICON_PATH) as Texture2D
	if ResourceLoader.exists(RESONANCE_ICON_PATH):
		_resonance_icon = load(RESONANCE_ICON_PATH) as Texture2D


func _load_portrait_shader() -> void:
	if ResourceLoader.exists(PORTRAIT_SHADER_PATH):
		_portrait_shader = load(PORTRAIT_SHADER_PATH) as Shader
	else:
		push_warning("HUD: Portrait-Shader nicht gefunden: %s" % PORTRAIT_SHADER_PATH)


func _load_smooth_pixel_script() -> void:
	if ResourceLoader.exists(SMOOTH_PIXEL_SCRIPT_PATH):
		_smooth_pixel_script = load(SMOOTH_PIXEL_SCRIPT_PATH)
	else:
		push_warning("HUD: SmoothPixelUI-Script nicht gefunden: %s" % SMOOTH_PIXEL_SCRIPT_PATH)


func _clear_existing_children() -> void:
	for child in get_children():
		child.queue_free()


# ══════════════════════════════════════════════════════════════
#  UI AUFBAU
# ══════════════════════════════════════════════════════════════

func _build_ui() -> void:
	_hud_root = Control.new()
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_root)
	
	_build_character_pod()
	_build_hotbar_dpad()
	_build_combo_widget() 

# ── CHARACTER POD ──────────────────────────────────────────────
func _build_character_pod() -> void:
	var pod := HBoxContainer.new()
	pod.add_theme_constant_override("separation", 14)
	pod.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pod.position = Vector2(20, 20)
	_hud_root.add_child(pod)
	
	_build_portrait(pod)
	_build_bars(pod)


func _build_portrait(parent: HBoxContainer) -> void:
	_portrait_wrap = Control.new()
	_portrait_wrap.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_portrait_wrap)
	
	# PortraitCircle — dein exaktes Editor-Setup nachgebaut
	_portrait_circle = TextureRect.new()
	_portrait_circle.name = "PortraitCircle"
	_portrait_circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_circle.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_circle.stretch_mode   = TextureRect.STRETCH_SCALE
	_portrait_circle.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait_circle.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_portrait_wrap.add_child(_portrait_circle)
	
	# Portrait-Shader mit allen Editor-Werten zuweisen
	if _portrait_shader:
		var mat := ShaderMaterial.new()
		mat.shader = _portrait_shader
		mat.set_shader_parameter("progress",             0.0)
		mat.set_shader_parameter("ring_gradient_start", PORTRAIT_RING_GRADIENT_START)
		mat.set_shader_parameter("ring_gradient_end",   PORTRAIT_RING_GRADIENT_END)
		mat.set_shader_parameter("ring_inactive_color", PORTRAIT_RING_INACTIVE_COLOR)
		mat.set_shader_parameter("ring_width",          PORTRAIT_RING_WIDTH)
		mat.set_shader_parameter("bg_color_a",          PORTRAIT_BG_COLOR_A)
		mat.set_shader_parameter("bg_color_b",          PORTRAIT_BG_COLOR_B)
		mat.set_shader_parameter("noise_scale",         PORTRAIT_NOISE_SCALE)
		mat.set_shader_parameter("noise_intensity",     PORTRAIT_NOISE_INTENSITY)
		mat.set_shader_parameter("time_scale",          PORTRAIT_TIME_SCALE)
		_portrait_circle.material = mat
	
	# KEIN SmoothPixelUI auf dem Portrait — der portrait_hud.gdshader
	# handled das Rendering selbst (im Editor-Setup war auch kein
	# SmoothPixelUI als Child am PortraitCircle).
	
	# Level-Badge (unten rechts, überlappt Ring)
	var badge_size: float = 24.0
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(badge_size, badge_size)
	badge.size                = Vector2(badge_size, badge_size)
	badge.position = Vector2(
		PORTRAIT_SIZE - badge_size + 4,
		PORTRAIT_SIZE - badge_size + 4
	)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.z_index = 10
	
	var badge_sb := StyleBoxFlat.new()
	badge_sb.bg_color     = C_BG_DEEP
	badge_sb.border_color = C_AMBER
	badge_sb.set_border_width_all(2)
	badge_sb.set_corner_radius_all(int(badge_size / 2))
	badge.add_theme_stylebox_override("panel", badge_sb)
	_portrait_wrap.add_child(badge)
	
	_level_label = Label.new()
	_level_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_level_label.text                 = str(level)
	_level_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_level_label.add_theme_color_override("font_color", C_AMBER)
	_level_label.add_theme_font_size_override("font_size", 12)
	if _font:
		_level_label.add_theme_font_override("font", _font)
	badge.add_child(_level_label)


func _attach_smooth_pixel(target: CanvasItem) -> void:
	if _smooth_pixel_script == null or target == null:
		return
	var smooth: Node = _smooth_pixel_script.new()
	smooth.name = "SmoothPixel"
	target.add_child(smooth)


# ── BARS ───────────────────────────────────────────────────────
func _build_bars(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(vbox)
	
	# HP Row: Herz-Icon + Bar (mit Delay-Bar für Schaden-Anzeige)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hp_row)
	hp_row.add_child(_build_bar_icon(true))
	var hp_pair: Array = _build_bar(HP_GRADIENT_STOPS, true)
	_hp_bar       = hp_pair[0]
	_hp_delay_bar = hp_pair[1]
	hp_row.add_child(hp_pair[2])
	
	# RP Row: Kristall-Icon + Bar (OHNE Delay-Bar — Resonance regeneriert,
	# keine Schaden-Anzeige nötig)
	var rp_row := HBoxContainer.new()
	rp_row.add_theme_constant_override("separation", 8)
	rp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rp_row)
	rp_row.add_child(_build_bar_icon(false))
	var rp_pair: Array = _build_bar(RP_GRADIENT_STOPS, false)
	_rp_bar       = rp_pair[0]
	_rp_delay_bar = rp_pair[1]
	rp_row.add_child(rp_pair[2])


func _build_bar_icon(is_hp: bool) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(18, 18)
	wrap.size                = Vector2(18, 18)
	wrap.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	
	if is_hp:
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.texture = _heart_icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(icon)
	else:
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.texture = _resonance_icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(icon)
	
	return wrap


# Rückgabe: [main_bar, delay_bar_or_null, container]
func _build_bar(color_stops: Array, include_delay: bool = true) -> Array:
	# Der Bar-"Container" ist ein Control mit fester Größe
	# (PanelContainer würde die Bar auf Auto-Größe zwingen und die Borders
	# ungleichmäßig aussehen lassen — deshalb hier explizites Control)
	var container := Control.new()
	container.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	container.size                = Vector2(BAR_WIDTH, BAR_HEIGHT)
	container.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	
	# Dunkler Frame als eigener Panel hinter den Bars
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color      = Color("0a0604")
	frame_sb.border_color  = Color("5c3d1e")
	frame_sb.set_border_width_all(1)
	frame_sb.set_corner_radius_all(2)
	frame_sb.shadow_color  = Color(0, 0, 0, 0.55)
	frame_sb.shadow_size   = 3
	frame_sb.shadow_offset = Vector2(0, 1)
	frame.add_theme_stylebox_override("panel", frame_sb)
	container.add_child(frame)
	
	# Innerer Bar-Bereich — 2px Abstand zum Frame
	var inner := Control.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left   = 2
	inner.offset_right  = -2
	inner.offset_top    = 2
	inner.offset_bottom = -2
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(inner)
	
	# Delay-Bar hinter Haupt-Bar (optional)
	# Als eigenes Child VOR der Haupt-Bar hinzufügen → rendert zuerst → ist hinten
	# KEIN show_behind_parent nötig (das geht nur relativ zum Parent-Control)
	var delay_bar: ProgressBar = null
	if include_delay:
		delay_bar = ProgressBar.new()
		delay_bar.show_percentage = false
		delay_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
		delay_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		# Background transparent — zeigt den Frame-Hintergrund durch
		var delay_bg := StyleBoxFlat.new()
		delay_bg.bg_color = Color(0, 0, 0, 0)
		delay_bar.add_theme_stylebox_override("background", delay_bg)
		
		# Fill mit Gradient-Textur, passend zum Stil der HP/RP-Bars
		var delay_fill := StyleBoxTexture.new()
		delay_fill.texture = _build_multi_color_gradient_texture(DELAY_GRADIENT_STOPS)
		delay_fill.set_content_margin_all(0)
		delay_bar.add_theme_stylebox_override("fill", delay_fill)
		inner.add_child(delay_bar)
	
	# Haupt-Bar mit Multi-Color-Gradient — wird NACH Delay-Bar added → liegt davor
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Background der Haupt-Bar TRANSPARENT lassen — sonst würde der
	# leere Bereich der Haupt-Bar die Delay-Bar überdecken
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0)
	bar.add_theme_stylebox_override("background", bar_bg)
	
	var fill_sb := StyleBoxTexture.new()
	fill_sb.texture = _build_multi_color_gradient_texture(color_stops)
	fill_sb.set_content_margin_all(0)
	bar.add_theme_stylebox_override("fill", fill_sb)
	inner.add_child(bar)
	
	return [bar, delay_bar, container]


func _build_multi_color_gradient_texture(stops: Array) -> ImageTexture:
	var w := 4
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	
	if stops.is_empty():
		img.fill(Color.WHITE)
		return ImageTexture.create_from_image(img)
	
	var n_stops: int = stops.size()
	for y in range(h):
		var t: float     = 1.0 - (float(y) / float(h - 1))
		var idx_f: float = t * float(n_stops - 1)
		var idx_lo: int  = clamp(int(floor(idx_f)), 0, n_stops - 1)
		var idx_hi: int  = clamp(idx_lo + 1, 0, n_stops - 1)
		var frac: float  = idx_f - float(idx_lo)
		var col: Color   = (stops[idx_lo] as Color).lerp(stops[idx_hi] as Color, frac)
		for x in range(w):
			img.set_pixel(x, y, col)
	
	return ImageTexture.create_from_image(img)


# ── D-PAD HOTBAR ───────────────────────────────────────────────
func _build_hotbar_dpad() -> void:
	var dpad_size: float = SLOT_SIZE * 3 + DPAD_GAP * 2
	
	var dpad := Control.new()
	dpad.custom_minimum_size = Vector2(dpad_size, dpad_size)
	dpad.size                = Vector2(dpad_size, dpad_size)
	dpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dpad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	dpad.offset_left   = 22
	dpad.offset_right  = 22 + dpad_size
	dpad.offset_top    = -dpad_size - 22
	dpad.offset_bottom = -22
	_hud_root.add_child(dpad)
	
	var center_x: float = (dpad_size - SLOT_SIZE) / 2.0
	var center_y: float = (dpad_size - SLOT_SIZE) / 2.0
	
	var slot_w := _build_slot()
	slot_w.position = Vector2(center_x, 0)
	dpad.add_child(slot_w)
	
	var slot_a := _build_slot()
	slot_a.position = Vector2(0, center_y)
	dpad.add_child(slot_a)
	
	var slot_s := _build_slot()
	slot_s.position = Vector2(center_x, dpad_size - SLOT_SIZE)
	dpad.add_child(slot_s)
	
	var slot_d := _build_slot()
	slot_d.position = Vector2(dpad_size - SLOT_SIZE, center_y)
	dpad.add_child(slot_d)
	
	_action_slots = [slot_w, slot_a, slot_s, slot_d]
	_hotbar_icons = []
	for slot in _action_slots:
		var icon := _make_slot_icon()
		slot.add_child(icon)
		_hotbar_icons.append(icon)
	
	# Keycap-Tabs — halb überlappend mit Slot-Rand, zur Mitte zeigend
	_add_keycap(dpad, "W",
		Vector2(center_x + SLOT_SIZE / 2.0 - KEYCAP_SIZE / 2.0,
				SLOT_SIZE - KEYCAP_SIZE / 2.0))
	_add_keycap(dpad, "A",
		Vector2(SLOT_SIZE - KEYCAP_SIZE / 2.0,
				center_y + SLOT_SIZE / 2.0 - KEYCAP_SIZE / 2.0))
	_add_keycap(dpad, "S",
		Vector2(center_x + SLOT_SIZE / 2.0 - KEYCAP_SIZE / 2.0,
				dpad_size - SLOT_SIZE - KEYCAP_SIZE / 2.0))
	_add_keycap(dpad, "D",
		Vector2(dpad_size - SLOT_SIZE - KEYCAP_SIZE / 2.0,
				center_y + SLOT_SIZE / 2.0 - KEYCAP_SIZE / 2.0))


func _build_slot() -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.size                = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var sb := StyleBoxFlat.new()
	sb.bg_color     = Color(C_BG_DEEP.r, C_BG_DEEP.g, C_BG_DEEP.b, 0.85)
	sb.border_color = Color(C_BORDER_OUT, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.shadow_color  = Color(0, 0, 0, 0.5)
	sb.shadow_size   = 4
	sb.shadow_offset = Vector2(0, 2)
	slot.add_theme_stylebox_override("panel", sb)
	return slot


func _make_slot_icon() -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Mehr Padding zum Slot-Rand — lässt Items etwas kleiner wirken
	icon.offset_left   = 9
	icon.offset_right  = -9
	icon.offset_top    = 9
	icon.offset_bottom = -9
	icon.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	return icon


func _add_keycap(parent: Control, letter: String, pos: Vector2) -> void:
	var cap := PanelContainer.new()
	cap.custom_minimum_size = Vector2(KEYCAP_SIZE, KEYCAP_SIZE)
	cap.size                = Vector2(KEYCAP_SIZE, KEYCAP_SIZE)
	cap.position            = pos
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.z_index = 3
	
	var sb := StyleBoxFlat.new()
	sb.bg_color     = C_BG_DEEP
	sb.border_color = Color(C_AMBER, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size  = 2
	cap.add_theme_stylebox_override("panel", sb)
	parent.add_child(cap)
	
	var lbl := Label.new()
	lbl.text                 = letter
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_color", C_TEXT_LIGHT)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.add_theme_font_size_override("font_size", 10)
	if _font:
		lbl.add_theme_font_override("font", _font)
	cap.add_child(lbl)


# ══════════════════════════════════════════════════════════════
#  PORTRAIT TEXTURE
# ══════════════════════════════════════════════════════════════

func _setup_portrait_texture() -> void:
	if ResourceLoader.exists(PORTRAIT_PATH) and _portrait_circle:
		_portrait_circle.texture = load(PORTRAIT_PATH)


# ══════════════════════════════════════════════════════════════
#  PLAYER DATA
# ══════════════════════════════════════════════════════════════

func _on_loading_finished() -> void:
	_connect_to_player_data()
	_connect_to_inventory()
	_connect_to_synergy_manager()


func _connect_to_player_data() -> void:
	await get_tree().process_frame
	if GameManager == null or GameManager.player_data == null:
		return
	
	var pd: PlayerData = GameManager.player_data
	_safe_connect(pd.hp_changed,        _on_hp_changed)
	_safe_connect(pd.resonance_changed, _on_resonance_changed)
	_safe_connect(pd.exp_changed,       _on_exp_changed)
	_safe_connect(pd.level_changed,     _on_level_changed)
	_safe_connect(pd.gold_changed,      _on_gold_changed)
	
	_update_all_displays()


func _safe_connect(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)


func _update_all_displays() -> void:
	if GameManager == null or GameManager.player_data == null:
		return
	var pd: PlayerData = GameManager.player_data
	update_hp(pd.current_hp, pd.max_hp)
	update_resonance(int(pd.current_resonance), pd.max_resonance)
	update_exp(pd.current_exp, pd.exp_to_next_level)
	set_level(pd.level)
	update_gold(pd.gold)
	
	if _hp_delay_bar:
		_hp_delay_bar.max_value = pd.max_hp
		_hp_delay_bar.value     = pd.current_hp


# ══════════════════════════════════════════════════════════════
#  UPDATES
# ══════════════════════════════════════════════════════════════

func update_hp(current: int, maximum: int) -> void:
	current_hp = current
	max_hp     = maximum
	if _hp_bar:
		_hp_bar.max_value = maximum
		_hp_bar.value     = current


func update_resonance(current: int, maximum: int) -> void:
	current_resonance = current
	max_resonance     = maximum
	if _rp_bar:
		_rp_bar.max_value = maximum
		_rp_bar.value     = current


func update_exp(current: int, maximum: int) -> void:
	current_exp = current
	max_exp     = maximum
	_update_exp_ring(current)


func _update_exp_ring(exp_value: int) -> void:
	if _portrait_circle and _portrait_circle.material is ShaderMaterial and max_exp > 0:
		var p: float = clamp(float(exp_value) / float(max_exp), 0.0, 1.0)
		(_portrait_circle.material as ShaderMaterial).set_shader_parameter("progress", p)


func update_gold(amount: int) -> void:
	gold = amount


func set_level(new_level: int) -> void:
	level = new_level
	if _level_label:
		_level_label.text = str(level)
	update_exp(current_exp, max_exp)


func animate_hp_change(new_hp: int) -> void:
	if _hp_bar == null:
		return
	var old_hp: int = current_hp
	_hp_bar.max_value = max_hp
	
	# Haupt-Bar springt SOFORT auf neuen Wert — das ist der Punkt der Delay-Bar:
	# Haupt-Bar kurz/spring, Delay-Bar bleibt stehen und schließt verzögert nach.
	# Wenn auch die Haupt-Bar tweent, kleben beide zusammen und der gelbe
	# Streifen ist nie sichtbar.
	_hp_bar.value = new_hp
	current_hp    = new_hp
	
	if _hp_delay_bar:
		if new_hp < old_hp:
			_trigger_delay_bar(_hp_delay_bar, _hp_delay_tween, old_hp, new_hp, max_hp, true)
		else:
			_hp_delay_bar.value = new_hp


func animate_resonance_change(new_rp: int) -> void:
	if _rp_bar == null:
		return
	_rp_bar.max_value = max_resonance
	current_resonance = new_rp
	
	# Wenn ein Tween auf gleiches Ziel schon läuft, nicht neu starten
	if _rp_anim_tween and _rp_anim_tween.is_valid() and _rp_tween_target == new_rp:
		return
	
	# Alten Tween killen, neuen starten
	if _rp_anim_tween and _rp_anim_tween.is_valid():
		_rp_anim_tween.kill()
	
	_rp_tween_target = new_rp
	_rp_anim_tween = create_tween()
	_rp_anim_tween.tween_property(_rp_bar, "value", float(new_rp), 0.25)


func animate_exp_change(new_exp: int) -> void:
	var tween := create_tween()
	tween.tween_method(func(val: float):
		current_exp = int(val)
		_update_exp_ring(int(val))
	, float(current_exp), float(new_exp), 0.5)
	current_exp = new_exp


func _trigger_delay_bar(bar: ProgressBar, tween_ref: Tween,
						old_val: int, new_val: int, maximum: int, is_hp: bool) -> void:
	if bar == null:
		return
	if tween_ref and tween_ref.is_valid():
		tween_ref.kill()
	
	bar.max_value = maximum
	bar.value     = old_val
	
	var t := create_tween()
	t.tween_interval(delay_bar_wait)
	t.tween_property(bar, "value", new_val, delay_bar_speed) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_QUAD)
	
	if is_hp:
		_hp_delay_tween = t
	else:
		_rp_delay_tween = t


# ══════════════════════════════════════════════════════════════
#  SIGNAL HANDLERS
# ══════════════════════════════════════════════════════════════

func _on_hp_changed(_current: int, _maximum: int) -> void:
	# No-op: wird vom Polling in _update_hp_display() gehandelt.
	# Signal + Polling doppelt würde die Delay-Bar sofort überschreiben.
	pass


func _on_resonance_changed(_current: int, _maximum: int) -> void:
	# No-op: wird vom Polling in _update_resonance_display() gehandelt.
	pass


func _on_exp_changed(current: int, needed: int) -> void:
	max_exp = needed
	animate_exp_change(current)


func _on_level_changed(new_level: int) -> void:
	set_level(new_level)


func _on_gold_changed(amount: int) -> void:
	update_gold(amount)


func _update_hp_display() -> void:
	# Polling statt Signal-only: erkennt auch "stille" HP-Änderungen
	if GameManager == null or GameManager.player_data == null:
		return
	var pd: PlayerData = GameManager.player_data
	var new_hp: int = pd.current_hp
	
	if new_hp != current_hp or pd.max_hp != max_hp:
		var old_hp: int = current_hp
		max_hp = pd.max_hp
		
		# Delay Bar nur bei SCHADEN triggern
		if new_hp < old_hp:
			_trigger_delay_bar(_hp_delay_bar, _hp_delay_tween,
				old_hp, new_hp, pd.max_hp, true)
		elif new_hp > old_hp and _hp_delay_bar:
			_hp_delay_bar.value = new_hp
		
		# Haupt-Bar animiert auf neuen Wert (tween statt direkt)
		animate_hp_change(new_hp)


func _update_resonance_display() -> void:
	if GameManager == null or GameManager.player_data == null:
		return
	var pd: PlayerData = GameManager.player_data
	var new_rp: int = int(pd.current_resonance)
	
	# Nur wenn sich der Wert wirklich ändert → neuen Tween starten
	if new_rp != current_resonance or pd.max_resonance != max_resonance:
		max_resonance = pd.max_resonance
		animate_resonance_change(new_rp)


# ══════════════════════════════════════════════════════════════
#  INVENTORY / HOTBAR
# ══════════════════════════════════════════════════════════════

func _connect_to_inventory() -> void:
	await get_tree().process_frame
	var inv := get_node_or_null("/root/InventoryManager")
	if inv:
		if not inv.hotbar_changed.is_connected(_on_hotbar_changed):
			inv.hotbar_changed.connect(_on_hotbar_changed)
		_update_all_hotbar_slots()


func _update_all_hotbar_slots() -> void:
	for i in range(_hotbar_icons.size()):
		_update_hotbar_slot(i)


func _update_hotbar_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _hotbar_icons.size():
		return
	var icon := _hotbar_icons[slot_index]
	if icon == null:
		return
	
	var inv := get_node_or_null("/root/InventoryManager")
	if inv == null:
		return
	
	var item_id: String = inv.get_hotbar_item(slot_index)
	var item_data: ItemData = inv.get_item_data(item_id) if item_id != "" else null
	
	if item_data and item_data.icon:
		icon.texture = item_data.icon
		icon.visible = true
	else:
		icon.texture = null


func _on_hotbar_changed(slot_index: int, _item_id: String) -> void:
	_update_hotbar_slot(slot_index)
	
	if slot_index == 0:
		var inv := get_node_or_null("/root/InventoryManager")
		if inv:
			var item_id: String = inv.get_hotbar_item(0)
			var item_data: ItemData = inv.get_item_data(item_id) if item_id != "" else null
			_cached_slot_0_texture = item_data.icon if (item_data and item_data.icon) else null


func _update_slot_w_interaction_state() -> void:
	if _hotbar_icons.is_empty():
		return
	var icon: TextureRect = _hotbar_icons[0]
	if icon == null:
		return
	
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	
	var can_interact: bool = false
	if player.has_method("can_interact_with_npc"):
		can_interact = player.can_interact_with_npc()
	var can_chest: bool = false
	if player.has_method("can_interact_with_chest"):
		can_chest = player.can_interact_with_chest()
	
	if can_interact:
		if _cached_slot_0_texture == null and icon.texture != _interact_icon:
			_cached_slot_0_texture = icon.texture
		if _interact_icon:
			icon.texture = _interact_icon
	elif can_chest:
		if _cached_slot_0_texture == null and icon.texture != _action_icon:
			_cached_slot_0_texture = icon.texture
		if _action_icon:
			icon.texture = _action_icon
	else:
		if _cached_slot_0_texture != null:
			icon.texture = _cached_slot_0_texture
		else:
			_update_hotbar_slot(0)

func _build_combo_widget() -> void:
	var cinzel_font: FontFile = null
	if ResourceLoader.exists(COMBO_FONT_PATH):
		cinzel_font = load(COMBO_FONT_PATH) as FontFile
	
	# Container — oben Mitte
	_combo_widget = Control.new()
	_combo_widget.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_combo_widget.offset_top = 20
	_combo_widget.custom_minimum_size = Vector2(200, 100)
	_combo_widget.size = Vector2(200, 100)
	_combo_widget.position.x -= 100  # Zentrieren (halbe Breite)
	_combo_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_widget.modulate.a = 0.0  # Initial unsichtbar
	_hud_root.add_child(_combo_widget)
	
	# VBoxContainer für Combo + Multiplier
	_combo_vbox = VBoxContainer.new()
	_combo_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_combo_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_combo_vbox.add_theme_constant_override("separation", 2)
	_combo_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_widget.add_child(_combo_vbox)
	
	# Combo-Label (große römische Zahl, gold mit outline)
	_combo_label = Label.new()
	_combo_label.text = ""
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	_combo_label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 1.0))
	_combo_label.add_theme_constant_override("outline_size", 6)
	_combo_label.add_theme_font_size_override("font_size", 64)
	if cinzel_font:
		_combo_label.add_theme_font_override("font", cinzel_font)
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_vbox.add_child(_combo_label)
	
	# Multiplier-Label (kleine Prozentangabe darunter)
	_multiplier_label = Label.new()
	_multiplier_label.text = ""
	_multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_multiplier_label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 1.0))
	_multiplier_label.add_theme_constant_override("outline_size", 3)
	_multiplier_label.add_theme_font_size_override("font_size", 24)
	if cinzel_font:
		_multiplier_label.add_theme_font_override("font", cinzel_font)
	_multiplier_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_vbox.add_child(_multiplier_label)
	
func update_combo(combo: int, multiplier: float) -> void:
	if combo <= 0:
		_hide_combo()
		return
	
	var was_increase: bool = combo > _current_combo_count
	var was_change: bool = combo != _current_combo_count
	_current_combo_count = combo
	
	_combo_label.text = _to_roman(combo)
	_multiplier_label.text = _format_multiplier(multiplier)
	_multiplier_label.add_theme_color_override("font_color", _color_for_multiplier(multiplier))
	
	_show_combo()
	
	if was_increase:
		_play_combo_pop_animation()
	elif was_change:
		_play_combo_penalty_animation()


func _show_combo() -> void:
	if _combo_widget == null or _combo_widget.modulate.a >= 1.0:
		return
	var tween := create_tween()
	tween.tween_property(_combo_widget, "modulate:a", 1.0, 0.15)


func _hide_combo() -> void:
	if _combo_widget == null:
		return
	_current_combo_count = 0
	var tween := create_tween()
	tween.tween_property(_combo_widget, "modulate:a", 0.0, 0.4)


func _play_combo_pop_animation() -> void:
	if _combo_vbox == null:
		return
	_combo_vbox.pivot_offset = _combo_vbox.size * 0.5
	_combo_vbox.scale = Vector2(1.4, 1.4)
	var tween := create_tween()
	tween.tween_property(_combo_vbox, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_combo_penalty_animation() -> void:
	if _combo_vbox == null:
		return
	var original_pos: Vector2 = _combo_vbox.position
	var tween := create_tween()
	tween.tween_property(_combo_vbox, "position", original_pos + Vector2(6, 0), 0.04)
	tween.tween_property(_combo_vbox, "position", original_pos + Vector2(-6, 0), 0.04)
	tween.tween_property(_combo_vbox, "position", original_pos + Vector2(4, 0), 0.04)
	tween.tween_property(_combo_vbox, "position", original_pos, 0.04)


func _to_roman(num: int) -> String:
	if num <= 0:
		return ""
	if num > 39:
		return str(num)
	
	var values: Array[int] = [10, 9, 5, 4, 1]
	var symbols: Array[String] = ["X", "IX", "V", "IV", "I"]
	var result: String = ""
	
	for i in range(values.size()):
		while num >= values[i]:
			result += symbols[i]
			num -= values[i]
	
	return result


func _format_multiplier(mult: float) -> String:
	# Immer im Format x1.00 anzeigen, auch bei Combo I (Multiplier 1.0).
	return "x%.2f" % mult


func _color_for_multiplier(mult: float) -> Color:
	if mult >= 1.30:
		return Color(1.0, 0.85, 0.2, 1.0)
	elif mult >= 1.15:
		return Color(0.6, 1.0, 0.4, 1.0)
	elif mult > 1.0:
		return Color(0.8, 1.0, 0.6, 1.0)
	elif mult >= 0.85:
		return Color(1.0, 0.6, 0.3, 1.0)
	else:
		return Color(1.0, 0.3, 0.2, 1.0)
		
func _connect_to_synergy_manager() -> void:
	# Warte einen Frame, damit Player + Components garantiert ready sind
	await get_tree().process_frame

	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("HUD: Kein Player für SynergyManager-Connection gefunden")
		return
	
	var synergy_manager: Node = player.get_node_or_null("SynergyManager")
	if synergy_manager == null:
		push_warning("HUD: Kein SynergyManager am Player gefunden")
		return
		
	if synergy_manager.has_method("get_combo_count"):
		var combo: int = synergy_manager.get_combo_count()
		var mult: float = synergy_manager.get_current_multiplier()
		update_combo(combo, mult)
	
	# Combo-Widget Connection (eigene Methode am HUD) //KOMMENTAR NACH VIDEO WIEDER RAUS
	if not synergy_manager.combo_changed.is_connected(update_combo):
		synergy_manager.combo_changed.connect(update_combo)
	
	# Heat-Bar Connection (separate Komponente am Player)
	var heat_bar: Node = player.get_node_or_null("HeatBar3D")
	if heat_bar == null:
		push_warning("HUD: Keine HeatBar3D am Player gefunden")
		return
	print("OK")
	if not synergy_manager.heat_changed.is_connected(_on_heat_changed):
		synergy_manager.heat_changed.connect(_on_heat_changed.bind(heat_bar))
	if not synergy_manager.overheat_started.is_connected(_on_overheat_started):
		synergy_manager.overheat_started.connect(_on_overheat_started.bind(heat_bar))
	if not synergy_manager.overheat_ended.is_connected(_on_overheat_ended):
		synergy_manager.overheat_ended.connect(_on_overheat_ended.bind(heat_bar))


func _on_heat_changed(heat: float, max_h: float, heat_bar: Node) -> void:
	if is_instance_valid(heat_bar):
		heat_bar.set_heat(heat / max_h)


func _on_overheat_started(_duration: float, heat_bar: Node) -> void:
	if is_instance_valid(heat_bar):
		heat_bar.start_overheat()


func _on_overheat_ended(heat_bar: Node) -> void:
	if is_instance_valid(heat_bar):
		heat_bar.end_overheat()



func hide_for_intro() -> void:
	visible = false
	if _hud_root:
		_hud_root.modulate.a = 0.0
 
 

func reveal_after_intro(duration: float = 0.8) -> void:
	visible = true
	if _hud_root == null:
		return
	_hud_root.modulate.a = 0.0
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_hud_root, "modulate:a", 1.0, duration)

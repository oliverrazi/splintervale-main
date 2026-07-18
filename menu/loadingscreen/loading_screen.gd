extends CanvasLayer

## Loading Screen
##
## Zeigt einen zufälligen Screenshot aus res://assets/loading_screens/
## - Unten links: Hint (zum Screenshot zugewiesen)
## - Unten rechts: Loading-Bar
## - Fade-Out (black) vor Szenen-Wechsel, Fade-In (aus black) danach
##
## Scene-Tree (Root: LoadingScreen als CanvasLayer, Rest wird per Code gebaut)

signal loading_finished


# ══════════════════════════════════════════════════════════════
#  KONFIGURATION
# ══════════════════════════════════════════════════════════════

const LOADING_SCREENS_DIR: String = "res://assets/loading_screens/"

# Hints pro Screenshot-Datei (nur Dateiname, kein Pfad).
# Wenn eine Datei hier nicht gelistet ist, wird ein generischer Hint gezeigt.
const SCREEN_HINTS: Dictionary = {
	"waterfall.png": "If you attack enemies they get hurt.",
	"forest.png": "Don't forget to brush your teeth.",
	"village.png": "Talk always with the villagers. They can be helpful.",
	"cave.png": "Don't get lost in puzzles.",
}

const GENERIC_HINTS: Array[String] = [
	"The realm remembers those who wander with purpose.",
	"Every relic once belonged to someone who fell for it.",
	"Not all who whisper in the dark mean harm.",
]


# Farben (synchron zum Menü-System)
const C_BG_DEEP     := Color("14100a")
const C_BORDER_OUT  := Color("5c3d1e")
const C_AMBER       := Color("c4923a")
const C_TEXT_LIGHT  := Color("d4b880")
const C_TEXT_MID    := Color("8a7050")
 
# Bar-Gradient (Amber, subtil)
const BAR_GRADIENT_STOPS: Array = [
	Color("5c3d1e"),
	Color("8a5e28"),
	Color("b57a2e"),
	Color("d49a3e"),
	Color("e8c96a"),
]
 
const BAR_WIDTH: float  = 260.0
const BAR_HEIGHT: float = 8.0
 
 
# ══════════════════════════════════════════════════════════════
#  STATE
# ══════════════════════════════════════════════════════════════
 
var _target_scene: String   = ""
var _progress: Array        = []
var _font: FontFile         = null
 
# UI Refs (per Code gebaut)
var _screenshot_rect: TextureRect = null
var _black_overlay: ColorRect     = null
var _bottom_gradient: TextureRect = null
var _hint_label: Label            = null
var _progress_bar: ProgressBar    = null
 
 
# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════
 
func _ready() -> void:
	layer = 100
	visible = false
	
	_load_font()
	_clear_existing_children()
	_build_ui()
 
 
func _load_font() -> void:
	var path := "res://menu/assets/fonts/Merriweather-Regular.ttf"
	if ResourceLoader.exists(path):
		_font = load(path) as FontFile
 
 
func _clear_existing_children() -> void:
	for child in get_children():
		child.queue_free()
 
 
# ══════════════════════════════════════════════════════════════
#  UI AUFBAU
# ══════════════════════════════════════════════════════════════
 
func _build_ui() -> void:
	# Vollflächiger Screenshot als Hintergrund
	_screenshot_rect = TextureRect.new()
	_screenshot_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screenshot_rect.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	_screenshot_rect.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_screenshot_rect.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	add_child(_screenshot_rect)
	
	# Dunkler Gradient unten (damit Hint & Bar lesbar bleiben)
	_bottom_gradient = TextureRect.new()
	_bottom_gradient.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_gradient.offset_top     = -180
	_bottom_gradient.offset_bottom  = 0
	_bottom_gradient.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	_bottom_gradient.stretch_mode   = TextureRect.STRETCH_SCALE
	_bottom_gradient.texture        = _build_bottom_gradient_texture()
	_bottom_gradient.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom_gradient)
	
	# Hint unten links
	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint_label.offset_left   = 32
	_hint_label.offset_right  = 640
	_hint_label.offset_top    = -70
	_hint_label.offset_bottom = -32
	_hint_label.autowrap_mode          = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment   = HORIZONTAL_ALIGNMENT_LEFT
	_hint_label.vertical_alignment     = VERTICAL_ALIGNMENT_BOTTOM
	_hint_label.mouse_filter           = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_color_override("font_color", C_TEXT_LIGHT)
	_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_hint_label.add_theme_font_size_override("font_size", 15)
	if _font:
		_hint_label.add_theme_font_override("font", _font)
	add_child(_hint_label)
	
	# Loading-Bar unten rechts (mit Frame + Amber-Gradient)
	var bar_container := Control.new()
	bar_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bar_container.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar_container.offset_left   = -(BAR_WIDTH + 32)
	bar_container.offset_right  = -32
	bar_container.offset_top    = -(BAR_HEIGHT + 40)
	bar_container.offset_bottom = -40
	bar_container.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(bar_container)
	
	# Frame um die Bar
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color            = Color("0a0604", 0.85)
	frame_sb.border_color        = Color(C_BORDER_OUT, 0.9)
	frame_sb.set_border_width_all(1)
	frame_sb.set_corner_radius_all(1)
	frame_sb.content_margin_left   = 1
	frame_sb.content_margin_right  = 1
	frame_sb.content_margin_top    = 1
	frame_sb.content_margin_bottom = 1
	frame.add_theme_stylebox_override("panel", frame_sb)
	bar_container.add_child(frame)
	
	# Progress-Bar mit Amber-Gradient
	_progress_bar = ProgressBar.new()
	_progress_bar.show_percentage = false
	_progress_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_progress_bar.offset_left   = 1
	_progress_bar.offset_right  = -1
	_progress_bar.offset_top    = 1
	_progress_bar.offset_bottom = -1
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value     = 0.0
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0)
	_progress_bar.add_theme_stylebox_override("background", bar_bg)
	
	var bar_fill := StyleBoxTexture.new()
	bar_fill.texture = _build_gradient_texture(BAR_GRADIENT_STOPS)
	bar_fill.set_content_margin_all(0)
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	bar_container.add_child(_progress_bar)
	
	# Schwarzes Overlay ganz oben (für Fades)
	_black_overlay = ColorRect.new()
	_black_overlay.color = Color(0, 0, 0, 1.0)
	_black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black_overlay)
 
 
# ══════════════════════════════════════════════════════════════
#  TEXTUREN
# ══════════════════════════════════════════════════════════════
 
func _build_gradient_texture(stops: Array) -> ImageTexture:
	# Vertikal, y=0 oben = letzter Stop, y=h-1 unten = erster Stop
	var w := 4
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	if stops.is_empty():
		img.fill(Color.WHITE)
		return ImageTexture.create_from_image(img)
	
	var n: int = stops.size()
	for y in range(h):
		var t: float = 1.0 - (float(y) / float(h - 1))
		var idx_f: float = t * float(n - 1)
		var idx_lo: int = clamp(int(floor(idx_f)), 0, n - 1)
		var idx_hi: int = clamp(idx_lo + 1, 0, n - 1)
		var frac: float = idx_f - float(idx_lo)
		var col: Color = (stops[idx_lo] as Color).lerp(stops[idx_hi] as Color, frac)
		for x in range(w):
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
 
 
func _build_bottom_gradient_texture() -> ImageTexture:
	# Vertikaler Gradient: oben transparent → unten schwarz-opak
	var w := 4
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var t: float = float(y) / float(h - 1)
		# Kurve: bis Mitte schwach, dann steiler
		var alpha: float = pow(t, 1.4) * 0.85
		var col := Color(0, 0, 0, alpha)
		for x in range(w):
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
 
 
# ══════════════════════════════════════════════════════════════
#  SCREENSHOT-AUSWAHL
# ══════════════════════════════════════════════════════════════
 
func _pick_random_screenshot() -> String:
	# Sucht alle Bild-Dateien im LOADING_SCREENS_DIR
	var files: Array[String] = []
	var dir := DirAccess.open(LOADING_SCREENS_DIR)
	if dir:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if not dir.current_is_dir():
				var lower := name.to_lower()
				if lower.ends_with(".png") or lower.ends_with(".jpg") \
						or lower.ends_with(".jpeg") or lower.ends_with(".webp"):
					files.append(name)
			name = dir.get_next()
	
	if files.is_empty():
		return ""
	files.shuffle()
	return files[0]
 
 
func _get_hint_for(screenshot_name: String) -> String:
	if SCREEN_HINTS.has(screenshot_name):
		return SCREEN_HINTS[screenshot_name]
	# Fallback: generischen Hint zufällig wählen
	if not GENERIC_HINTS.is_empty():
		return GENERIC_HINTS[randi() % GENERIC_HINTS.size()]
	return ""
 
 
func _apply_random_screenshot() -> void:
	var name := _pick_random_screenshot()
	if name == "":
		# Kein Screenshot verfügbar — leerer Hintergrund (schwarz)
		_screenshot_rect.texture = null
		_hint_label.text = ""
		return
	
	var path := LOADING_SCREENS_DIR + name
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_screenshot_rect.texture = tex
	
	_hint_label.text = _get_hint_for(name)
 
 
# ══════════════════════════════════════════════════════════════
#  LOADING-FLOW
# ══════════════════════════════════════════════════════════════
 
func load_scene(scene_path: String) -> void:
	_target_scene = scene_path
	visible = true
	
	# Screenshot + Hint würfeln
	_apply_random_screenshot()
	
	# Progress-Bar reset
	_progress_bar.value = 0.0
	
	# Schwarzes Overlay startet opak → wird ausgeblendet damit der Screenshot sichtbar wird
	_black_overlay.color.a = 1.0
	
	var tween := create_tween()
	tween.tween_property(_black_overlay, "color:a", 0.0, 0.4)
	tween.tween_callback(_start_loading)
 
 
func _start_loading() -> void:
	ResourceLoader.load_threaded_request(_target_scene)
	set_process(true)
 
 
func _process(_delta: float) -> void:
	var status := ResourceLoader.load_threaded_get_status(_target_scene, _progress)
	
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if _progress.size() > 0:
				_progress_bar.value = _progress[0]
		
		ResourceLoader.THREAD_LOAD_LOADED:
			set_process(false)
			_on_loading_complete()
		
		ResourceLoader.THREAD_LOAD_FAILED:
			set_process(false)
			push_error("Failed to load scene: %s" % _target_scene)
 
 
func _on_loading_complete() -> void:
	_progress_bar.value = 1.0
	
	# Kurzer Moment damit die volle Bar sichtbar ist
	await get_tree().create_timer(0.25).timeout
	
	# Fade zu schwarz vor Szenen-Wechsel
	var out_tween := create_tween()
	out_tween.tween_property(_black_overlay, "color:a", 1.0, 0.35)
	await out_tween.finished
	
	# Loading-Screen-Elemente SOFORT unsichtbar machen — der schwarze Overlay
	# bleibt drüber und verdeckt alles. Damit ist der Loading-Kram beim
	# Szenen-Wechsel definitiv nicht mehr zu sehen.
	_screenshot_rect.visible = false
	_bottom_gradient.visible = false
	_hint_label.visible      = false
	_progress_bar.visible    = false
	
	# Szenen-Wechsel im schwarzen Frame
	var packed_scene: PackedScene = ResourceLoader.load_threaded_get(_target_scene)
	get_tree().change_scene_to_packed(packed_scene)
	
	# Der neuen Szene Zeit geben sich zu initialisieren:
	# - Kamera-Positionierung
	# - HUD-Setup
	# - Erste Frames rendern
	# Wir warten mehrere Frames + einen kleinen Timer.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	
	loading_finished.emit()
	
	# Nochmal 2 Frames damit alle loading_finished-Handler durchlaufen
	# (Kamera-Snap, HUD-Refresh, etc.)
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Erst JETZT fadet der schwarze Overlay aus → man sieht die stabile
	# neue Szene, nicht den Kamera-Scroll oder Loading-Reste.
	var in_tween := create_tween()
	in_tween.tween_property(_black_overlay, "color:a", 0.0, 0.4)
	in_tween.tween_callback(func():
		visible = false
		# Elemente wieder zurücksetzen für nächstes Laden
		_screenshot_rect.visible = true
		_bottom_gradient.visible = true
		_hint_label.visible      = true
		_progress_bar.visible    = true
	)

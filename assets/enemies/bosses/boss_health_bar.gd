class_name BossHealthBar
extends CanvasLayer

const FONT_MAIN_PATH  := "res://menu/assets/fonts/Merriweather-Regular.ttf"
const FONT_TITLE_PATH := "res://menu/assets/fonts/Cinzel-Bold.ttf"

const C_FRAME_BG    := Color("0a0604")
const C_BORDER_OUT  := Color("5c3d1e")
const C_BORDER_IN   := Color("8a6a30", 0.9)   # Amber-Innenakzent (Doppelrahmen)
const C_TEXT_LIGHT  := Color("d4b880")

# Roter HP-Verlauf — unverändert (HUD-konsistent)
const HP_GRADIENT_STOPS: Array = [
	Color("4a1818"), Color("7a2020"), Color("b02a2a"),
	Color("d44040"), Color("e66060"), Color("f5a060"),
]
# Dunkler, kühler Stahl — Blau/Indigo subtil in den Mitten, kräftiger Kontrast
const ARMOR_GRADIENT_STOPS: Array = [
	Color("0f1014"), Color("191c24"), Color("262b38"),
	Color("363d4e"), Color("4a5468"), Color("717f96"),
]

const HP_EDGE_COL    := Color("ffce98", 0.95)
const ARMOR_EDGE_COL := Color("c6d2e6", 0.95)

var _root: Control
var _hp_fill: ProgressBar
var _armor_fill: ProgressBar
var _hp_edge: ColorRect
var _armor_edge: ColorRect
var _name_label: Label
var _bar_w: float = 0.0
var _bar_h: float = 0.0
var _hp_ratio: float = 1.0
var _armor_ratio: float = 1.0

var _font_main: FontFile = null
var _font_title: FontFile = null
var _hp_tween: Tween = null
var _armor_tween: Tween = null


func _ready() -> void:
	layer = 50
	if ResourceLoader.exists(FONT_MAIN_PATH):
		_font_main = load(FONT_MAIN_PATH)
	if ResourceLoader.exists(FONT_TITLE_PATH):
		_font_title = load(FONT_TITLE_PATH)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	add_child(_root)

	var vp := get_viewport().get_visible_rect().size
	_bar_w = vp.x * 0.35
	_bar_h = 26.0
	var top := 30.0
	var x := (vp.x - _bar_w) * 0.5

	# Äußerer Rahmen — dicker (2px), kräftigerer Schatten
	var frame := Panel.new()
	frame.position = Vector2(x - 4, top - 4)
	frame.size = Vector2(_bar_w + 8, _bar_h + 8)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = C_FRAME_BG
	fsb.border_color = C_BORDER_OUT
	fsb.set_border_width_all(2)
	fsb.set_corner_radius_all(3)
	fsb.shadow_color = Color(0, 0, 0, 0.65)
	fsb.shadow_size = 5
	fsb.shadow_offset = Vector2(0, 2)
	frame.add_theme_stylebox_override("panel", fsb)
	_root.add_child(frame)

	# Innerer Amber-Hairline → Doppelrahmen-Optik (ornamenter, AAA)
	var accent := Panel.new()
	accent.position = Vector2(x - 1, top - 1)
	accent.size = Vector2(_bar_w + 2, _bar_h + 2)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var asb := StyleBoxFlat.new()
	asb.bg_color = Color(0, 0, 0, 0)
	asb.border_color = C_BORDER_IN
	asb.set_border_width_all(1)
	asb.set_corner_radius_all(2)
	accent.add_theme_stylebox_override("panel", asb)
	_root.add_child(accent)

	var inner := Control.new()
	inner.position = Vector2(x, top)
	inner.size = Vector2(_bar_w, _bar_h)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(inner)

	_hp_fill = _make_fill_bar(HP_GRADIENT_STOPS)
	inner.add_child(_hp_fill)
	_hp_edge = _make_edge(HP_EDGE_COL)
	inner.add_child(_hp_edge)

	_armor_fill = _make_fill_bar(ARMOR_GRADIENT_STOPS)
	inner.add_child(_armor_fill)
	_armor_edge = _make_edge(ARMOR_EDGE_COL)
	inner.add_child(_armor_edge)

	# Glanz-Sheen über allem — das, was Balken „glasig/metallisch" macht
	var gloss := TextureRect.new()
	gloss.texture = _gloss_tex()
	gloss.set_anchors_preset(Control.PRESET_FULL_RECT)
	gloss.stretch_mode = TextureRect.STRETCH_SCALE
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(gloss)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.position = Vector2(x, top + _bar_h + 7)
	_name_label.size = Vector2(_bar_w, 30)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_color_override("font_color", C_TEXT_LIGHT)
	_name_label.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.0, 1.0))
	_name_label.add_theme_constant_override("outline_size", 5)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 2)
	_name_label.add_theme_font_size_override("font_size", 24)
	if _font_title:
		_name_label.add_theme_font_override("font", _font_title)
	elif _font_main:
		_name_label.add_theme_font_override("font", _font_main)
	_root.add_child(_name_label)

	_set_hp(1.0)
	_set_armor_val(1.0)


func _make_fill_bar(stops: Array) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.set_anchors_preset(Control.PRESET_FULL_RECT)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0)
	pb.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxTexture.new()
	fill.texture = _gradient_tex(stops)
	fill.set_content_margin_all(0)
	pb.add_theme_stylebox_override("fill", fill)
	return pb


func _make_edge(col: Color) -> ColorRect:
	var e := ColorRect.new()
	e.color = col
	e.size = Vector2(2, _bar_h)
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	e.visible = false
	return e


func _gradient_tex(stops: Array) -> ImageTexture:
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
		var lo: int = clamp(int(floor(idx_f)), 0, n - 1)
		var hi: int = clamp(lo + 1, 0, n - 1)
		var frac: float = idx_f - float(lo)
		var col: Color = (stops[lo] as Color).lerp(stops[hi] as Color, frac)
		for px in range(w):
			img.set_pixel(px, y, col)
	return ImageTexture.create_from_image(img)


func _gloss_tex() -> ImageTexture:
	var w := 4
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var v := float(y) / float(h - 1)   # 0=oben .. 1=unten
		var a := 0.0
		if v < 0.5:
			a = lerpf(0.20, 0.0, v / 0.5)        # Spiegel-Sheen oben
		elif v > 0.85:
			a = lerpf(0.0, 0.07, (v - 0.85) / 0.15)  # leichtes Bottom-Rim-Light
		for px in range(w):
			img.set_pixel(px, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _update_edge(edge: ColorRect, r: float) -> void:
	if edge == null:
		return
	edge.visible = r > 0.02 and r < 0.985
	edge.position = Vector2(clampf(r, 0.0, 1.0) * _bar_w - 1.0, 0.0)


func _set_hp(r: float) -> void:
	if _hp_fill: _hp_fill.value = r
	_update_edge(_hp_edge, r)


func _set_armor_val(r: float) -> void:
	if _armor_fill: _armor_fill.value = r
	_update_edge(_armor_edge, r)


func bind(boss_name: String) -> void:
	if _name_label:
		_name_label.text = boss_name


func set_health(cur: int, maxv: int) -> void:
	if _hp_fill == null:
		return
	var target := clampf(float(cur) / maxf(float(maxv), 1.0), 0.0, 1.0)
	if _hp_tween and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = create_tween()
	_hp_tween.tween_method(_set_hp, _hp_ratio, target, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hp_ratio = target


func set_armor(cur: int, maxv: int) -> void:
	if _armor_fill == null:
		return
	if maxv <= 0:
		_armor_fill.visible = false
		_armor_edge.visible = false
		return
	var target := clampf(float(cur) / maxf(float(maxv), 1.0), 0.0, 1.0)
	_armor_fill.visible = target > 0.0
	if _armor_tween and _armor_tween.is_valid():
		_armor_tween.kill()
	_armor_tween = create_tween()
	_armor_tween.tween_method(_set_armor_val, _armor_ratio, target, 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_armor_ratio = target


func appear() -> void:
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.4)


func vanish() -> void:
	create_tween().tween_property(_root, "modulate:a", 0.0, 0.4)

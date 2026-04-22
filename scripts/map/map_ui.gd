extends Control
class_name MapUI

## MapUI für das Pause-Menü (Medieval Fantasy Stil)
## Features:
##   - Karte ohne Pergament-Rahmen, integriert ins Menü-Farbschema
##   - Fog of War in warmem Braun statt Grau
##   - Kleiner, unauffälliger Player-Marker (nicht pulsierend)
##   - Quest-Marker als amber-farbene Rauten
##   - POI-Liste rechts zum Navigieren via Pfeiltasten

signal poi_selected(poi_id: String)


# ══════════════════════════════════════════════════════════════
#  EXPORTS
# ══════════════════════════════════════════════════════════════

@export_group("Map Settings")
@export var map_texture_path: String = "res://assets/map/world_map.png"
@export var world_x_min: float = -135.0
@export var world_x_max: float = 85.0
@export var world_z_min: float = 40.0
@export var world_z_max: float = 260.0

@export_group("Player Marker")
@export var player_icon_path: String = "res://menu/assets/icons/player_icon.png"
@export var player_marker_size: float = 14.0

@export_group("Fog of War")
@export var fog_enabled: bool = true
@export var fog_color: Color = Color("1e1810", 1.0)
@export var reveal_radius: float = 10.0


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
const C_QUEST       := Color("e2b05e")
const C_TEXT_LIGHT  := Color("d4b880")
const C_TEXT_MID    := Color("8a7050")
const C_TEXT_MUTED  := Color("6b5030")


# ══════════════════════════════════════════════════════════════
#  POI-DATENSTRUKTUR
# ══════════════════════════════════════════════════════════════

enum POIType { PLAYER, QUEST }

class POI:
	var id: String        = ""
	var type: POIType     = POIType.QUEST
	var display_name: String = ""
	var description: String  = ""
	var world_pos: Vector3   = Vector3.ZERO
	var marker_node: Control = null
	var list_button: Button  = null


# ══════════════════════════════════════════════════════════════
#  INTERNAL STATE
# ══════════════════════════════════════════════════════════════

const FOG_RESOLUTION: int = 256
const FOG_SAVE_PATH: String = "user://fog_data.png"

var _font: FontFile = null
var _pois: Array = []   # Array[POI]
var _selected_poi_id: String = ""

# UI-Referenzen
var _map_container: Control        = null
var _map_texture_rect: TextureRect = null
var _fog_rect: ColorRect           = null
var _poi_layer: Control            = null
var _compass: Control              = null
var _region_label: Label           = null

var _side_panel: PanelContainer   = null
var _selected_card: PanelContainer = null
var _selected_name: Label         = null
var _selected_type: Label         = null
var _selected_desc: Label         = null
var _selected_dist_val: Label     = null
var _selected_dist_label: Label   = null
var _poi_list_vbox: VBoxContainer = null
var _hint_label: Label            = null

# Fog
var _fog_image: Image               = null
var _fog_texture: ImageTexture      = null
var _player_icon_texture: Texture2D = null

var _selection_ring: Control = null
var _ring_pulse_time: float = 0.0


# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_font()
	_load_player_icon()
	_build_ui()
	_load_map_texture()
	_setup_fog_of_war()
	_connect_quest_signals()
	
	# Initial POIs aufbauen nach einem Frame (damit UI-Sizes stimmen)
	await get_tree().process_frame
	_rebuild_pois()


func _load_font() -> void:
	var path := "res://menu/assets/fonts/Merriweather-Regular.ttf"
	if ResourceLoader.exists(path):
		_font = load(path) as FontFile


func _load_player_icon() -> void:
	if player_icon_path != "" and ResourceLoader.exists(player_icon_path):
		_player_icon_texture = load(player_icon_path)


# ══════════════════════════════════════════════════════════════
#  UI AUFBAU
# ══════════════════════════════════════════════════════════════

func _build_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	add_child(hbox)
	
	# ── LINKS: Karte ─────────────────────────────────────────
	_map_container = Control.new()
	_map_container.name = "MapContainer"
	_map_container.clip_contents = true
	_map_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_container.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_map_container.mouse_filter          = Control.MOUSE_FILTER_PASS
	hbox.add_child(_map_container)
	
	# Map-Hintergrund (dunkel, damit Fog und Karte integriert wirken)
	var bg := ColorRect.new()
	bg.color        = C_BG_DEEP
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_container.add_child(bg)
	
	# Karten-Textur
	_map_texture_rect = TextureRect.new()
	_map_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_texture_rect.expand_mode     = TextureRect.EXPAND_IGNORE_SIZE
	_map_texture_rect.stretch_mode    = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_texture_rect.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	_map_texture_rect.texture_filter  = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_container.add_child(_map_texture_rect)
	
	# Fog of War Overlay
	_fog_rect = ColorRect.new()
	_fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_container.add_child(_fog_rect)
	
	# POI-Layer (zeichnet Marker über dem Fog)
	_poi_layer = Control.new()
	_poi_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_poi_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_container.add_child(_poi_layer)
	
	
	_selection_ring = Control.new()
	_selection_ring.size = Vector2(28, 28)
	_selection_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_ring.z_index = 7
	_selection_ring.visible = false
	_selection_ring.draw.connect(_draw_selection_ring)
	_poi_layer.add_child(_selection_ring)
	
	# Kompass
	_build_compass()
	
	# Region-Label
	_build_region_label()
	
	# ── RECHTS: Side-Panel ───────────────────────────────────
	_build_side_panel(hbox)

func _draw_selection_ring() -> void:
	var center := _selection_ring.size / 2.0
	var base_r: float = 12.0
	# Puls zwischen 0.7 und 1.3 über einen 1.8s Zyklus
	var pulse: float = 1.0 + 0.3 * sin(_ring_pulse_time * TAU / 1.8)
	var r: float = base_r * pulse
	var alpha: float = 0.8 - 0.4 * (pulse - 0.7) / 0.6  # transparenter wenn größer
	
	# Äußerer Ring
	_selection_ring.draw_arc(center, r,       0.0, TAU, 48, Color(C_AMBER, alpha),       2.0, true)
	# Innerer Akzent
	_selection_ring.draw_arc(center, r - 3.0, 0.0, TAU, 48, Color(C_AMBER, alpha * 0.4), 1.0, true)


func _build_compass() -> void:
	_compass = Control.new()
	_compass.size = Vector2(56, 56)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.z_index = 5
	_map_container.add_child(_compass)
	_compass.position = Vector2(14, 14)
	
	# Hintergrund-Kreis
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color     = Color(C_BG_DEEP.r, C_BG_DEEP.g, C_BG_DEEP.b, 0.85)
	sb.border_color = Color(C_AMBER, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	_compass.add_child(panel)
	
	# Nadel-Zeichnung
	var needle := Control.new()
	needle.set_anchors_preset(Control.PRESET_FULL_RECT)
	needle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	needle.draw.connect(_draw_compass_needle.bind(needle))
	_compass.add_child(needle)
	
	# Himmelsrichtung-Labels
	_add_compass_direction("N", Vector2(0, -1))
	_add_compass_direction("S", Vector2(0,  1))
	_add_compass_direction("E", Vector2( 1, 0))
	_add_compass_direction("W", Vector2(-1, 0))


func _draw_compass_needle(needle: Control) -> void:
	var center := needle.size / 2.0
	var length: float = 18.0
	
	# Nord-Zeiger (oben, amber)
	var n_tip := center + Vector2(0, -length)
	var n_base_l := center + Vector2(-4, -2)
	var n_base_r := center + Vector2( 4, -2)
	var n_pts := PackedVector2Array([n_tip, n_base_l, center, n_base_r])
	needle.draw_colored_polygon(n_pts, C_AMBER)
	
	# Süd-Zeiger (unten, gedämpft)
	var s_tip := center + Vector2(0, length)
	var s_base_l := center + Vector2(-4, 2)
	var s_base_r := center + Vector2( 4, 2)
	var s_pts := PackedVector2Array([s_tip, s_base_l, center, s_base_r])
	needle.draw_colored_polygon(s_pts, Color(C_TEXT_MUTED, 0.8))
	
	# Mittelpunkt
	needle.draw_circle(center, 2.0, C_AMBER)
	needle.draw_circle(center, 1.0, C_BG_DEEP)


func _add_compass_direction(letter: String, dir: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = letter
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(10, 10)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var is_north: bool = (letter == "N")
	var color: Color = C_AMBER if is_north else Color(C_TEXT_MID, 0.65)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 8)
	if _font:
		lbl.add_theme_font_override("font", _font)
	
	_compass.add_child(lbl)
	
	# Position: 22px vom Zentrum in Richtung dir
	var center := Vector2(28, 28) - lbl.size / 2.0
	lbl.position = center + dir * 22.0


func _build_region_label() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 5
	
	var sb := StyleBoxFlat.new()
	sb.bg_color              = Color(C_BG_DEEP.r, C_BG_DEEP.g, C_BG_DEEP.b, 0.7)
	sb.border_color          = Color(C_AMBER, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left   = 10
	sb.content_margin_right  = 10
	sb.content_margin_top    = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	
	_region_label = Label.new()
	_region_label.text = "◆ NORVALE"
	_region_label.add_theme_color_override("font_color", Color(C_AMBER, 0.75))
	_region_label.add_theme_font_size_override("font_size", 10)
	if _font:
		_region_label.add_theme_font_override("font", _font)
	_region_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_region_label)
	
	_map_container.add_child(panel)
	# Position: unten-links (via Anchor)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(12, -36)


func _build_side_panel(parent: HBoxContainer) -> void:
	_side_panel = PanelContainer.new()
	_side_panel.custom_minimum_size.x = 240
	_side_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_side_panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	
	var sb := StyleBoxFlat.new()
	sb.bg_color              = C_BG_DEEP
	sb.border_color          = Color(C_BORDER_OUT, 0.6)
	sb.border_width_left     = 1
	sb.content_margin_left   = 14
	sb.content_margin_right  = 14
	sb.content_margin_top    = 14
	sb.content_margin_bottom = 14
	_side_panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(_side_panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_side_panel.add_child(vbox)
	
	# ── POI-Liste OBEN ─────────────────────────────────────
	var list_section := VBoxContainer.new()
	list_section.add_theme_constant_override("separation", 8)
	vbox.add_child(list_section)
	list_section.add_child(_build_section_header("Markers"))
	
	_poi_list_vbox = VBoxContainer.new()
	_poi_list_vbox.add_theme_constant_override("separation", 2)
	list_section.add_child(_poi_list_vbox)
	
	# ── Selected POI DARUNTER ─────────────────────────────
	var sel_section := VBoxContainer.new()
	sel_section.add_theme_constant_override("separation", 8)
	sel_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(sel_section)
	sel_section.add_child(_build_section_header("Selected"))
	
	_selected_card = PanelContainer.new()
	var scb := StyleBoxFlat.new()
	scb.bg_color              = C_AMBER_FAINT
	scb.border_color          = C_AMBER_DIM
	scb.set_border_width_all(1)
	scb.set_corner_radius_all(2)
	scb.content_margin_left   = 12
	scb.content_margin_right  = 12
	scb.content_margin_top    = 10
	scb.content_margin_bottom = 10
	_selected_card.add_theme_stylebox_override("panel", scb)
	sel_section.add_child(_selected_card)
	
	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 4)
	_selected_card.add_child(card_vbox)
	
	_selected_name = Label.new()
	_selected_name.text = "—"
	_selected_name.add_theme_color_override("font_color", C_TEXT_LIGHT)
	_selected_name.add_theme_font_size_override("font_size", 14)
	if _font:
		_selected_name.add_theme_font_override("font", _font)
	card_vbox.add_child(_selected_name)
	
	_selected_type = Label.new()
	_selected_type.text = ""
	_selected_type.add_theme_color_override("font_color", Color(C_AMBER, 0.65))
	_selected_type.add_theme_font_size_override("font_size", 9)
	if _font:
		_selected_type.add_theme_font_override("font", _font)
	card_vbox.add_child(_selected_type)
	
	_selected_desc = Label.new()
	_selected_desc.text = ""
	_selected_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_desc.add_theme_color_override("font_color", C_TEXT_MID)
	_selected_desc.add_theme_font_size_override("font_size", 12)
	if _font:
		_selected_desc.add_theme_font_override("font", _font)
	card_vbox.add_child(_selected_desc)
	
	var dist_sep := ColorRect.new()
	dist_sep.color = Color(C_BORDER_OUT, 0.4)
	dist_sep.custom_minimum_size = Vector2(0, 1)
	card_vbox.add_child(dist_sep)
	
	var dist_row := HBoxContainer.new()
	card_vbox.add_child(dist_row)
	
	_selected_dist_label = Label.new()
	_selected_dist_label.text = "Distance"
	_selected_dist_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selected_dist_label.add_theme_color_override("font_color", C_TEXT_MUTED)
	_selected_dist_label.add_theme_font_size_override("font_size", 11)
	if _font:
		_selected_dist_label.add_theme_font_override("font", _font)
	dist_row.add_child(_selected_dist_label)
	
	_selected_dist_val = Label.new()
	_selected_dist_val.text = "—"
	_selected_dist_val.add_theme_color_override("font_color", C_TEXT_LIGHT)
	_selected_dist_val.add_theme_font_size_override("font_size", 11)
	if _font:
		_selected_dist_val.add_theme_font_override("font", _font)
	dist_row.add_child(_selected_dist_val)
	
	# ── Hint ──────────────────────────────────────────────
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	_hint_label = Label.new()
	_hint_label.text = "↑ ↓  cycle markers"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", C_TEXT_MUTED)
	_hint_label.add_theme_font_size_override("font_size", 10)
	if _font:
		_hint_label.add_theme_font_override("font", _font)
	vbox.add_child(_hint_label)


func _build_section_header(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	
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
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(C_AMBER, 0.75))
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
#  POI SYSTEM
# ══════════════════════════════════════════════════════════════

func _connect_quest_signals() -> void:
	var qm := get_node_or_null("/root/QuestManager")
	if qm == null:
		return
	
	if not qm.quest_added.is_connected(_on_quests_changed):
		qm.quest_added.connect(_on_quests_changed)
	if not qm.quest_turned_in.is_connected(_on_quest_turned_in):
		qm.quest_turned_in.connect(_on_quest_turned_in)


func _on_quests_changed(_quest_id: String) -> void:
	_rebuild_pois()


func _on_quest_turned_in(_quest_id: String) -> void:
	_rebuild_pois()


func _rebuild_pois() -> void:
	# Alte POIs weg
	for poi in _pois:
		if poi.marker_node and is_instance_valid(poi.marker_node):
			poi.marker_node.queue_free()
		if poi.list_button and is_instance_valid(poi.list_button):
			poi.list_button.queue_free()
	_pois.clear()
	
	# Player-POI als erstes
	var player_poi := POI.new()
	player_poi.id           = "_player"
	player_poi.type         = POIType.PLAYER
	player_poi.display_name = "You"
	player_poi.description  = "Your current position."
	player_poi.world_pos    = _get_player_position()
	_pois.append(player_poi)
	
	# Quest-Targets
	var qm := get_node_or_null("/root/QuestManager")
	if qm:
		var active_quests: Array = qm.get_active_quests()
		for qid in active_quests:
			var qdata: QuestData = qm.get_quest_data(qid)
			if qdata == null:
				continue
			
			var target_pos: Vector3 = _resolve_quest_target_position(qdata)
			if target_pos == Vector3.INF:
				continue   # kein Ort bekannt → überspringen
			
			var poi := POI.new()
			poi.id           = qid
			poi.type         = POIType.QUEST
			poi.display_name = qdata.quest_name if qdata.quest_name != "" else qid
			poi.description  = qdata.description
			poi.world_pos    = target_pos
			_pois.append(poi)
	
	# UI neu aufbauen
	_rebuild_poi_markers()
	_rebuild_poi_list()
	
	# Selektion wiederherstellen oder auf Player default
	if _selected_poi_id == "" or _find_poi(_selected_poi_id) == null:
		_select_poi("_player")
	else:
		_update_selected_details()


func _resolve_quest_target_position(qdata: QuestData) -> Vector3:
	# Versuche über `target_id` einen QuestObject-Node in der Scene zu finden
	# oder nutze alternativ die Position des NPCs.
	var tree := get_tree()
	if tree == null:
		return Vector3.INF
	
	# 1. QuestObject in der Welt suchen (object_id == target_id)
	for node in tree.get_nodes_in_group("quest_object"):
		if node is Node3D and node.has_method("get"):
			var obj_id = node.get("object_id")
			if obj_id != null and str(obj_id) == qdata.target_id:
				return (node as Node3D).global_position
	
	# 2. NPC via giver_npc_id / turn_in_npc_id
	var npc_id: String = qdata.turn_in_npc_id if qdata.turn_in_npc_id != "" else qdata.giver_npc_id
	if npc_id != "":
		for node in tree.get_nodes_in_group("npc"):
			if node is Node3D and node.has_method("get"):
				var nid = node.get("npc_id")
				if nid != null and str(nid) == npc_id:
					return (node as Node3D).global_position
	
	return Vector3.INF


func _rebuild_poi_markers() -> void:
	for poi in _pois:
		var marker: Control
		if poi.type == POIType.PLAYER:
			marker = _build_player_marker()
		else:
			marker = _build_quest_marker()
		
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.z_index = 10 if poi.type == POIType.PLAYER else 8
		_poi_layer.add_child(marker)
		poi.marker_node = marker


func _build_player_marker() -> Control:
	var wrap := Control.new()
	wrap.size = Vector2(player_marker_size, player_marker_size * 1.4)
	
	if _player_icon_texture:
		var tex := TextureRect.new()
		tex.texture        = _player_icon_texture
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(tex)
	else:
		# Fallback: kleiner Amber-Punkt
		var dot := Panel.new()
		dot.size = Vector2(8, 8)
		var sb := StyleBoxFlat.new()
		sb.bg_color     = C_AMBER
		sb.border_color = C_BG_DEEP
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		dot.add_theme_stylebox_override("panel", sb)
		dot.position = (wrap.size - dot.size) / 2.0
		wrap.add_child(dot)
	
	return wrap


func _build_quest_marker() -> Control:
	var wrap := Control.new()
	wrap.size = Vector2(12, 12)
	
	# Raute: Panel das um 45° gedreht ist
	var diamond := Panel.new()
	diamond.size = Vector2(8, 8)
	diamond.pivot_offset = Vector2(4, 4)
	diamond.rotation = deg_to_rad(45)
	diamond.position = Vector2(2, 2)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color     = C_QUEST
	sb.border_color = C_BG_DEEP
	sb.set_border_width_all(1)
	diamond.add_theme_stylebox_override("panel", sb)
	wrap.add_child(diamond)
	
	return wrap


func _rebuild_poi_list() -> void:
	for child in _poi_list_vbox.get_children():
		child.queue_free()
	
	for poi in _pois:
		var btn := _build_poi_list_item(poi)
		_poi_list_vbox.add_child(btn)
		poi.list_button = btn
	
	_setup_list_navigation()


func _build_poi_list_item(poi: POI) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 28)
	btn.flat = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.set_meta("poi_id", poi.id)
	
	# Styleboxes: unauffällig normal, amber-Glow bei Hover/Focus
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.TRANSPARENT
	normal.content_margin_left   = 12
	normal.content_margin_right  = 12
	normal.content_margin_top    = 8
	normal.content_margin_bottom = 8
	
	var hover := StyleBoxFlat.new()
	hover.bg_color           = C_AMBER_FAINT
	hover.border_color       = C_AMBER
	hover.border_width_left  = 2
	hover.content_margin_left   = 10   # -2 wegen Border
	hover.content_margin_right  = 12
	hover.content_margin_top    = 8
	hover.content_margin_bottom = 8
	
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("focus",   hover)
	btn.add_theme_stylebox_override("pressed", hover)
	
	
	# Inneres Layout: Icon + Name + Distanz
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	hbox.anchor_left = 0.0
	hbox.anchor_top = 0.0
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0

	hbox.offset_left = 12
	hbox.offset_right = -12
	hbox.offset_top = 4
	hbox.offset_bottom = -4
	btn.add_child(hbox)
	
	# Name
	var name_lbl := Label.new()
	name_lbl.text = poi.display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", C_TEXT_LIGHT)
	name_lbl.add_theme_font_size_override("font_size", 12)
	if _font:
		name_lbl.add_theme_font_override("font", _font)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_lbl)
	
	# Distanz
	var dist_lbl := Label.new()
	dist_lbl.name = "_DistLabel"
	dist_lbl.text = ""
	dist_lbl.add_theme_color_override("font_color", C_TEXT_MUTED)
	dist_lbl.add_theme_font_size_override("font_size", 10)
	if _font:
		dist_lbl.add_theme_font_override("font", _font)
	dist_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dist_lbl)
	
	btn.pressed.connect(_on_poi_list_pressed.bind(poi.id))
	btn.focus_entered.connect(_on_poi_list_focused.bind(poi.id))
	
	return btn


func _setup_list_navigation() -> void:
	var buttons: Array[Button] = []
	for poi in _pois:
		if poi.list_button:
			buttons.append(poi.list_button)
	
	for i in range(buttons.size()):
		var btn := buttons[i]
		if i > 0:
			btn.focus_neighbor_top = buttons[i - 1].get_path()
		else:
			btn.focus_neighbor_top = btn.get_path()
		
		if i < buttons.size() - 1:
			btn.focus_neighbor_bottom = buttons[i + 1].get_path()
		else:
			btn.focus_neighbor_bottom = btn.get_path()
		
		btn.focus_neighbor_left  = btn.get_path()
		btn.focus_neighbor_right = btn.get_path()


func _on_poi_list_pressed(poi_id: String) -> void:
	_select_poi(poi_id)


func _on_poi_list_focused(poi_id: String) -> void:
	_select_poi(poi_id)


func _select_poi(poi_id: String) -> void:
	_selected_poi_id = poi_id
	_update_selected_details()
	poi_selected.emit(poi_id)


func _find_poi(poi_id: String) -> POI:
	for poi in _pois:
		if poi.id == poi_id:
			return poi
	return null


# ══════════════════════════════════════════════════════════════
#  UPDATES
# ══════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not visible:
		return
	
	_ring_pulse_time += delta
	
	# Player-POI Position live aktualisieren
	var player_poi := _find_poi("_player")
	if player_poi:
		player_poi.world_pos = _get_player_position()
	
	_update_marker_positions()
	_update_selection_ring()
	_update_fog()
	_update_distances()

func _update_selection_ring() -> void:
	if _selection_ring == null:
		return
	
	var sel := _find_poi(_selected_poi_id)
	if sel == null or sel.marker_node == null:
		_selection_ring.visible = false
		return
	
	_selection_ring.visible = true
	# Ring um den Marker zentrieren
	var marker_center: Vector2 = sel.marker_node.position + sel.marker_node.size / 2.0
	_selection_ring.position = marker_center - _selection_ring.size / 2.0
	_selection_ring.queue_redraw()


func _update_marker_positions() -> void:
	var container_size := _map_container.size
	if container_size.x <= 0 or container_size.y <= 0:
		return
	
	for poi in _pois:
		if poi.marker_node == null:
			continue
		var norm := _world_to_map_normalized(poi.world_pos)
		var pos  := Vector2(norm.x * container_size.x, norm.y * container_size.y)
		poi.marker_node.position = pos - poi.marker_node.size / 2.0


func _update_distances() -> void:
	var player_pos: Vector3 = _get_player_position()
	
	for poi in _pois:
		if poi.list_button == null:
			continue
		var dist_lbl := poi.list_button.find_child("_DistLabel", true, false) as Label
		if dist_lbl == null:
			continue
		
		if poi.type == POIType.PLAYER:
			dist_lbl.text = "here"
		else:
			var d: float = player_pos.distance_to(poi.world_pos)
			dist_lbl.text = "%dm" % int(d)
	
	# Selektion
	if _selected_dist_val:
		var sel := _find_poi(_selected_poi_id)
		if sel:
			if sel.type == POIType.PLAYER:
				_selected_dist_label.text = "Coordinates"
				_selected_dist_val.text   = "%d, %d" % [int(sel.world_pos.x), int(sel.world_pos.z)]
			else:
				_selected_dist_label.text = "Distance"
				var d: float = player_pos.distance_to(sel.world_pos)
				_selected_dist_val.text = "%dm" % int(d)


func _update_selected_details() -> void:
	var poi := _find_poi(_selected_poi_id)
	if poi == null:
		_selected_name.text = "—"
		_selected_type.text = ""
		_selected_desc.text = ""
		return
	
	_selected_name.text = poi.display_name
	_selected_desc.text = poi.description
	
	match poi.type:
		POIType.PLAYER:
			_selected_type.text = "◆ YOUR POSITION"
		POIType.QUEST:
			_selected_type.text = "◆ ACTIVE QUEST"


# ══════════════════════════════════════════════════════════════
#  WORLD → MAP KOORDINATEN
# ══════════════════════════════════════════════════════════════

func _world_to_map_normalized(world_pos: Vector3) -> Vector2:
	var nx: float = (world_pos.x - world_x_min) / (world_x_max - world_x_min)
	var ny: float = 1.0 - (world_pos.z - world_z_min) / (world_z_max - world_z_min)
	return Vector2(clamp(nx, 0.0, 1.0), clamp(ny, 0.0, 1.0))


func _get_player_position() -> Vector3:
	var tree := get_tree()
	if tree == null:
		return Vector3.ZERO
	var player := tree.get_first_node_in_group("player")
	if player is Node3D:
		return (player as Node3D).global_position
	return Vector3.ZERO


# ══════════════════════════════════════════════════════════════
#  KARTENTEXTUR + FOG OF WAR
# ══════════════════════════════════════════════════════════════

func _load_map_texture() -> void:
	if ResourceLoader.exists(map_texture_path):
		var tex = load(map_texture_path)
		if tex:
			_map_texture_rect.texture = tex
			return
	# Fallback
	var img := Image.create(512, 512, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.18, 0.14))
	_map_texture_rect.texture = ImageTexture.create_from_image(img)


func _setup_fog_of_war() -> void:
	if not fog_enabled:
		_fog_rect.visible = false
		return
	
	_fog_image = Image.create(FOG_RESOLUTION, FOG_RESOLUTION, false, Image.FORMAT_L8)
	_fog_image.fill(Color.BLACK)
	_load_fog_data()
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	
	var shader_code := """
shader_type canvas_item;
uniform sampler2D fog_texture : filter_linear;
uniform vec4 fog_color : source_color = vec4(0.12, 0.10, 0.06, 1.0);
uniform float edge_softness : hint_range(0.01, 0.3) = 0.55;
void fragment() {
	float revealed = texture(fog_texture, UV).r;
	float alpha = 1.0 - smoothstep(0.0, edge_softness, revealed);
	COLOR = vec4(fog_color.rgb, alpha);
}
"""
	var shader := Shader.new()
	shader.code = shader_code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("fog_color",     fog_color)
	mat.set_shader_parameter("fog_texture",   _fog_texture)
	mat.set_shader_parameter("edge_softness", 0.55)
	_fog_rect.material = mat


func _update_fog() -> void:
	if not fog_enabled or _fog_image == null:
		return
	var player_pos: Vector3 = _get_player_position()
	if player_pos == Vector3.ZERO:
		return
	_reveal_fog_at(player_pos)


func _reveal_fog_at(world_pos: Vector3) -> void:
	var map_pos := _world_to_map_normalized(world_pos)
	var cx := int(map_pos.x * FOG_RESOLUTION)
	var cy := int(map_pos.y * FOG_RESOLUTION)
	
	var world_size: float = max(world_x_max - world_x_min, world_z_max - world_z_min)
	var base_r: float = max((reveal_radius / world_size) * FOG_RESOLUTION, 5.0)
	var rx := base_r
	var ry := base_r * 2.4
	
	var changed := false
	var ix := int(ceil(rx))
	var iy := int(ceil(ry))
	
	for dy in range(-iy, iy + 1):
		for dx in range(-ix, ix + 1):
			var nx: float = dx / rx
			var ny: float = dy / ry
			var d2: float = nx * nx + ny * ny
			if d2 > 1.0:
				continue
			var px := cx + dx
			var py := cy + dy
			if px < 0 or px >= FOG_RESOLUTION or py < 0 or py >= FOG_RESOLUTION:
				continue
			var current := _fog_image.get_pixel(px, py)
			if current.r >= 0.99:
				continue
			var edge: float = 1.0 - sqrt(d2)
			var new_val: float = max(current.r, edge)
			_fog_image.set_pixel(px, py, Color(new_val, new_val, new_val))
			changed = true
	
	if changed:
		_fog_texture.update(_fog_image)


func _load_fog_data() -> void:
	if FileAccess.file_exists(FOG_SAVE_PATH):
		var loaded := Image.load_from_file(FOG_SAVE_PATH)
		if loaded:
			if loaded.get_width() != FOG_RESOLUTION:
				loaded.resize(FOG_RESOLUTION, FOG_RESOLUTION)
			_fog_image = loaded


func save_fog_data() -> void:
	if _fog_image:
		_fog_image.save_png(FOG_SAVE_PATH)


func reset_fog() -> void:
	if _fog_image:
		_fog_image.fill(Color.BLACK)
		_fog_texture.update(_fog_image)
	if FileAccess.file_exists(FOG_SAVE_PATH):
		DirAccess.remove_absolute(FOG_SAVE_PATH)


# ══════════════════════════════════════════════════════════════
#  PUBLIC API (für pause_menu.gd)
# ══════════════════════════════════════════════════════════════

func refresh() -> void:
	_rebuild_pois()


# Fokussiert beim Betreten des Map-Tabs den Player-Eintrag
func focus_player() -> void:
	var player_poi := _find_poi("_player")
	if player_poi and player_poi.list_button:
		player_poi.list_button.grab_focus()


func get_poi_buttons() -> Array[Button]:
	var result: Array[Button] = []
	for poi in _pois:
		if poi.list_button:
			result.append(poi.list_button)
	return result

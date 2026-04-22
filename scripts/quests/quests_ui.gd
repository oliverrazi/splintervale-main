extends Control
class_name QuestsUI

signal quest_selected(quest_id: String)

enum QuestFilter { ACTIVE, COMPLETED, ALL }


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
const C_TEXT_MID    := Color("8a7050")
const C_TEXT_MUTED  := Color("6b5030")

# Quest-State Farben
const C_QUEST_ACTIVE    := Color("d4b880")
const C_QUEST_COMPLETE  := Color("8fb565")   # gedämpftes Grün, passt zum HP-Bar
const C_QUEST_TURNED_IN := Color("c4923a")   # Amber = abgegeben


# ══════════════════════════════════════════════════════════════
#  STATE
# ══════════════════════════════════════════════════════════════

var _current_filter: QuestFilter = QuestFilter.ACTIVE
var _selected_quest_id: String   = ""
var _quest_buttons: Array[Button] = []
var _filter_buttons: Array[Button] = []
var _font: FontFile = null


# ══════════════════════════════════════════════════════════════
#  UI REFERENZEN
# ══════════════════════════════════════════════════════════════

var _filter_active_btn: Button    = null
var _filter_completed_btn: Button = null
var _filter_all_btn: Button       = null

var _quest_list_vbox: VBoxContainer = null
var _quest_scroll: ScrollContainer  = null
var _no_quests_label: Label         = null

var _detail_title: Label            = null
var _detail_type: Label             = null
var _detail_description: RichTextLabel = null
var _detail_objective_box: VBoxContainer = null
var _detail_rewards_box: VBoxContainer   = null

var _status_badge: PanelContainer = null
var _status_label: Label          = null


# ══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_font()
	_build_ui()
	_connect_signals()
	_update_quest_list()


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
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	add_child(hbox)
	
	_build_left_panel(hbox)
	_build_right_panel(hbox)


# ── LINKE SEITE ────────────────────────────────────────────────
func _build_left_panel(parent: HBoxContainer) -> void:
	var left := PanelContainer.new()
	left.custom_minimum_size.x = 280
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	
	var sb := StyleBoxFlat.new()
	sb.bg_color              = Color.TRANSPARENT
	sb.border_color          = Color(C_BORDER_OUT, 0.6)
	sb.border_width_right    = 1
	sb.content_margin_left   = 18
	sb.content_margin_right  = 18
	sb.content_margin_top    = 18
	sb.content_margin_bottom = 18
	left.add_theme_stylebox_override("panel", sb)
	parent.add_child(left)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(vbox)
	
	# Section Header
	vbox.add_child(_build_section_header("Journal"))
	
	# Filter Buttons
	_build_filter_buttons(vbox)
	
	# Quest-Liste (scrollbar)
	_quest_scroll = ScrollContainer.new()
	_quest_scroll.size_flags_vertical        = Control.SIZE_EXPAND_FILL
	_quest_scroll.horizontal_scroll_mode     = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_quest_scroll)
	
	_quest_list_vbox = VBoxContainer.new()
	_quest_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_list_vbox.add_theme_constant_override("separation", 4)
	_quest_scroll.add_child(_quest_list_vbox)
	
	# Empty-State
	_no_quests_label = Label.new()
	_no_quests_label.text                 = "No quests in your journal."
	_no_quests_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_quests_label.add_theme_color_override("font_color", C_TEXT_MUTED)
	_no_quests_label.add_theme_font_size_override("font_size", 12)
	if _font:
		_no_quests_label.add_theme_font_override("font", _font)
	_no_quests_label.visible = false
	vbox.add_child(_no_quests_label)


func _build_filter_buttons(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	
	_filter_active_btn    = _build_filter_button("Active")
	_filter_completed_btn = _build_filter_button("Done")
	_filter_all_btn       = _build_filter_button("All")
	
	_filter_buttons = [_filter_active_btn, _filter_completed_btn, _filter_all_btn]
	
	for btn in _filter_buttons:
		row.add_child(btn)
	
	_filter_active_btn.button_pressed = true
	
	_filter_active_btn.pressed.connect(func(): _set_filter(QuestFilter.ACTIVE))
	_filter_completed_btn.pressed.connect(func(): _set_filter(QuestFilter.COMPLETED))
	_filter_all_btn.pressed.connect(func(): _set_filter(QuestFilter.ALL))


func _build_filter_button(label: String) -> Button:
	var btn := Button.new()
	btn.text                      = label
	btn.toggle_mode               = true
	btn.size_flags_horizontal     = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size       = Vector2(0, 28)
	btn.focus_mode                = Control.FOCUS_ALL
	
	var normal := StyleBoxFlat.new()
	normal.bg_color              = C_BG_DEEP
	normal.border_color          = C_BORDER_OUT
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left   = 8
	normal.content_margin_right  = 8
	normal.content_margin_top    = 4
	normal.content_margin_bottom = 4
	
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color     = C_AMBER_FAINT
	hover.border_color = Color(C_AMBER, 0.5)
	
	# Pressed = aktiver Filter (heller Amber-Ton)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color     = Color(C_AMBER, 0.15)
	pressed.border_color = C_AMBER
	
	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed)
	btn.add_theme_stylebox_override("focus",    hover)
	
	btn.add_theme_color_override("font_color",         C_TEXT_MID)
	btn.add_theme_color_override("font_hover_color",   C_TEXT_LIGHT)
	btn.add_theme_color_override("font_pressed_color", C_AMBER)
	btn.add_theme_font_size_override("font_size", 11)
	if _font:
		btn.add_theme_font_override("font", _font)
	
	return btn


# ── RECHTE SEITE (Details) ─────────────────────────────────────
func _build_right_panel(parent: HBoxContainer) -> void:
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	
	var sb := StyleBoxFlat.new()
	sb.bg_color              = Color.TRANSPARENT
	sb.content_margin_left   = 22
	sb.content_margin_right  = 22
	sb.content_margin_top    = 18
	sb.content_margin_bottom = 18
	right.add_theme_stylebox_override("panel", sb)
	parent.add_child(right)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	right.add_child(vbox)
	
	# ── Title-Zeile: Titel links, Status-Badge rechts ─────
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	vbox.add_child(title_row)
	
	_detail_title = Label.new()
	_detail_title.text                     = "Select a quest"
	_detail_title.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	_detail_title.size_flags_vertical      = Control.SIZE_SHRINK_CENTER
	_detail_title.add_theme_color_override("font_color", C_TEXT_LIGHT)
	_detail_title.add_theme_font_size_override("font_size", 20)
	if _font:
		_detail_title.add_theme_font_override("font", _font)
	title_row.add_child(_detail_title)
	
	_build_status_badge(title_row)
	
	# Type-Label (z.B. "◆ COLLECT QUEST")
	_detail_type = Label.new()
	_detail_type.text = ""
	_detail_type.add_theme_color_override("font_color", Color(C_AMBER, 0.65))
	_detail_type.add_theme_font_size_override("font_size", 10)
	if _font:
		_detail_type.add_theme_font_override("font", _font)
	vbox.add_child(_detail_type)
	
	# Trennlinie
	var sep := ColorRect.new()
	sep.color                 = Color(C_BORDER_OUT, 0.4)
	sep.custom_minimum_size   = Vector2(0, 1)
	vbox.add_child(sep)
	
	# Description-Section
	vbox.add_child(_build_subsection_header("Description"))
	_detail_description = RichTextLabel.new()
	_detail_description.bbcode_enabled        = true
	_detail_description.fit_content           = true
	_detail_description.autowrap_mode         = TextServer.AUTOWRAP_WORD_SMART
	_detail_description.custom_minimum_size.y = 40
	_detail_description.add_theme_font_size_override("normal_font_size", 13)
	_detail_description.add_theme_color_override("default_color", C_TEXT_MID)
	if _font:
		_detail_description.add_theme_font_override("normal_font", _font)
	vbox.add_child(_detail_description)
	
	# Objectives-Section
	vbox.add_child(_build_subsection_header("Objective"))
	_detail_objective_box = VBoxContainer.new()
	_detail_objective_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_detail_objective_box)
	
	# Rewards-Section
	vbox.add_child(_build_subsection_header("Rewards"))
	_detail_rewards_box = VBoxContainer.new()
	_detail_rewards_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_detail_rewards_box)
	
	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)


func _build_status_badge(parent: HBoxContainer) -> void:
	_status_badge = PanelContainer.new()
	_status_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_badge.visible = false
	
	var sb := StyleBoxFlat.new()
	sb.bg_color              = C_AMBER_FAINT
	sb.border_color          = C_AMBER_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left   = 10
	sb.content_margin_right  = 10
	sb.content_margin_top    = 4
	sb.content_margin_bottom = 4
	_status_badge.add_theme_stylebox_override("panel", sb)
	parent.add_child(_status_badge)
	
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_color_override("font_color", C_AMBER)
	_status_label.add_theme_font_size_override("font_size", 10)
	if _font:
		_status_label.add_theme_font_override("font", _font)
	_status_badge.add_child(_status_label)


# ── Section-Header mit Rauten (wie im Rest des Menüs) ──────────
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


# Kleinerer Subsection-Header (links-ausgerichtet, ohne zentrale Rauten)
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


# ══════════════════════════════════════════════════════════════
#  QUEST-LISTEN-ITEM
# ══════════════════════════════════════════════════════════════

func _create_quest_button(quest_id: String) -> Button:
	var qm := get_node_or_null("/root/QuestManager")
	var qdata: QuestData = qm.get_quest_data(quest_id) if qm else null
	var qstate = qm.get_quest_state(quest_id) if qm else null
	
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size   = Vector2(0, 44)
	btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode            = Control.FOCUS_ALL
	btn.set_meta("quest_id", quest_id)
	
	# Status bestimmen
	var is_turned_in: bool = qm and qm.is_quest_turned_in(quest_id)
	var is_complete: bool  = qstate and qstate.is_complete
	var indicator_color: Color = C_QUEST_ACTIVE
	if is_turned_in:
		indicator_color = C_QUEST_TURNED_IN
	elif is_complete:
		indicator_color = C_QUEST_COMPLETE
	
	# Styleboxes mit linker Akzentlinie
	var normal := StyleBoxFlat.new()
	normal.bg_color              = Color.TRANSPARENT
	normal.border_color          = indicator_color
	normal.border_width_left     = 2
	normal.set_corner_radius_all(0)
	normal.content_margin_left   = 12
	normal.content_margin_right  = 10
	normal.content_margin_top    = 8
	normal.content_margin_bottom = 8
	
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color          = C_AMBER_FAINT
	hover.border_color      = C_AMBER
	hover.border_width_left = 3
	hover.content_margin_left = 11
	
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(C_AMBER, 0.15)
	
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("focus",   hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	
	# Button-Inhalt per Text (nicht über Custom-Children, damit Layout sauber bleibt)
	var quest_name: String = qdata.quest_name if qdata else quest_id
	
	# Zweizeiliges Layout via Text + Custom-Font-Size geht nicht sauber,
	# daher nutzen wir ein Overlay aus zwei Labels die über dem Button liegen
	btn.text = ""
	_add_quest_button_content(btn, quest_name, qdata, qstate, is_turned_in, is_complete)
	
	btn.pressed.connect(_on_quest_button_pressed.bind(quest_id))
	btn.focus_entered.connect(_on_quest_button_focused.bind(quest_id))
	
	return btn


func _add_quest_button_content(btn: Button, quest_name: String, qdata: QuestData,
								qstate, is_turned_in: bool, is_complete: bool) -> void:
	# MarginContainer respektiert die Button-StyleBox content_margins nicht,
	# deshalb legen wir die Labels direkt ins Button-Layout via VBoxContainer
	# mit manuellen Margins.
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	# Position wird durch Button-StyleBox-Margins gesetzt; Größe via anchors
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left   = 12
	v.offset_right  = -10
	v.offset_top    = 8
	v.offset_bottom = -8
	btn.add_child(v)
	
	# Oben: Quest-Name
	var name_lbl := Label.new()
	name_lbl.text = quest_name
	name_lbl.add_theme_color_override("font_color", C_TEXT_LIGHT)
	name_lbl.add_theme_font_size_override("font_size", 13)
	if _font:
		name_lbl.add_theme_font_override("font", _font)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lbl)
	
	# Unten: Status-Zeile (klein, gedämpft)
	var status_lbl := Label.new()
	status_lbl.add_theme_font_size_override("font_size", 10)
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font:
		status_lbl.add_theme_font_override("font", _font)
	
	if is_turned_in:
		status_lbl.text = "Turned in"
		status_lbl.add_theme_color_override("font_color", Color(C_QUEST_TURNED_IN, 0.7))
	elif is_complete:
		status_lbl.text = "Ready to turn in"
		status_lbl.add_theme_color_override("font_color", Color(C_QUEST_COMPLETE, 0.8))
	elif qstate and qdata and qdata.target_amount > 1:
		status_lbl.text = "%d / %d" % [qstate.current_amount, qdata.target_amount]
		status_lbl.add_theme_color_override("font_color", C_TEXT_MUTED)
	else:
		status_lbl.text = "In progress"
		status_lbl.add_theme_color_override("font_color", C_TEXT_MUTED)
	
	v.add_child(status_lbl)


# ══════════════════════════════════════════════════════════════
#  QUEST-LISTE UPDATE
# ══════════════════════════════════════════════════════════════

func _update_quest_list() -> void:
	# Alte Buttons entfernen
	while _quest_list_vbox.get_child_count() > 0:
		var c := _quest_list_vbox.get_child(0)
		_quest_list_vbox.remove_child(c)
		c.queue_free()
	_quest_buttons.clear()
	
	var qm := get_node_or_null("/root/QuestManager")
	if qm == null:
		_no_quests_label.visible = true
		_clear_details()
		return
	
	var quests_to_show: Array[String] = []
	match _current_filter:
		QuestFilter.ACTIVE:
			quests_to_show = qm.get_active_quests()
		QuestFilter.COMPLETED:
			quests_to_show = qm.get_completed_quests()
		QuestFilter.ALL:
			quests_to_show = qm.get_active_quests()
			for q in qm.get_completed_quests():
				if q not in quests_to_show:
					quests_to_show.append(q)
	
	_no_quests_label.visible = quests_to_show.is_empty()
	
	for quest_id in quests_to_show:
		var btn := _create_quest_button(quest_id)
		_quest_list_vbox.add_child(btn)
		_quest_buttons.append(btn)
	
	_setup_button_navigation()
	
	# Erste Quest automatisch selektieren
	if _quest_buttons.size() > 0:
		_select_quest(_get_quest_id_from_button(_quest_buttons[0]))
	else:
		_clear_details()


func _setup_button_navigation() -> void:
	for i in range(_quest_buttons.size()):
		var btn := _quest_buttons[i]
		btn.focus_neighbor_top    = _quest_buttons[i - 1].get_path() if i > 0 else btn.get_path()
		btn.focus_neighbor_bottom = _quest_buttons[i + 1].get_path() if i < _quest_buttons.size() - 1 else btn.get_path()
		btn.focus_neighbor_left   = btn.get_path()
		btn.focus_neighbor_right  = btn.get_path()


func _get_quest_id_from_button(btn: Button) -> String:
	return btn.get_meta("quest_id", "")


# ══════════════════════════════════════════════════════════════
#  DETAIL-VIEW
# ══════════════════════════════════════════════════════════════

func _select_quest(quest_id: String) -> void:
	_selected_quest_id = quest_id
	_update_quest_details()
	quest_selected.emit(quest_id)


func _clear_details() -> void:
	_detail_title.text        = "Select a quest"
	_detail_type.text         = ""
	_detail_description.text  = ""
	_status_badge.visible     = false
	_clear_vbox(_detail_objective_box)
	_clear_vbox(_detail_rewards_box)


func _clear_vbox(box: VBoxContainer) -> void:
	while box.get_child_count() > 0:
		var c := box.get_child(0)
		box.remove_child(c)
		c.queue_free()


func _update_quest_details() -> void:
	_clear_vbox(_detail_objective_box)
	_clear_vbox(_detail_rewards_box)
	
	if _selected_quest_id == "":
		_clear_details()
		return
	
	var qm := get_node_or_null("/root/QuestManager")
	if qm == null:
		return
	
	var qdata: QuestData = qm.get_quest_data(_selected_quest_id)
	var qstate = qm.get_quest_state(_selected_quest_id)
	
	if qdata == null:
		_detail_title.text        = _selected_quest_id
		_detail_type.text         = ""
		_detail_description.text  = "No details available."
		_status_badge.visible     = false
		return
	
	# Titel
	_detail_title.text = qdata.quest_name
	
	# Typ
	_detail_type.text = "◆ " + _get_quest_type_text(qdata.quest_type)
	
	# Status-Badge
	_update_status_badge(qdata, qstate)
	
	# Beschreibung
	_detail_description.text = qdata.description
	
	# Objectives
	_build_objective_entry(qdata, qstate)
	
	# Rewards
	_build_rewards(qdata)


func _get_quest_type_text(t: int) -> String:
	match t:
		QuestData.QuestType.TALK:    return "TALK"
		QuestData.QuestType.COLLECT: return "COLLECT"
		QuestData.QuestType.KILL:    return "HUNT"
		QuestData.QuestType.EXPLORE: return "EXPLORE"
		QuestData.QuestType.DELIVER: return "DELIVER"
	return "QUEST"


func _update_status_badge(qdata: QuestData, qstate) -> void:
	var qm := get_node_or_null("/root/QuestManager")
	var is_turned_in: bool = qm and qm.is_quest_turned_in(_selected_quest_id)
	var is_complete: bool  = qstate and qstate.is_complete
	
	if is_turned_in:
		_status_label.text = "TURNED IN"
		_set_badge_color(C_QUEST_TURNED_IN)
		_status_badge.visible = true
	elif is_complete:
		_status_label.text = "COMPLETE"
		_set_badge_color(C_QUEST_COMPLETE)
		_status_badge.visible = true
	else:
		_status_badge.visible = false


func _set_badge_color(color: Color) -> void:
	var sb := _status_badge.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	var new_sb := sb.duplicate() as StyleBoxFlat
	new_sb.bg_color     = Color(color.r, color.g, color.b, 0.12)
	new_sb.border_color = Color(color.r, color.g, color.b, 0.45)
	_status_badge.add_theme_stylebox_override("panel", new_sb)
	_status_label.add_theme_color_override("font_color", color)


func _build_objective_entry(qdata: QuestData, qstate) -> void:
	var current: int = qstate.current_amount if qstate else 0
	var target: int  = qdata.target_amount
	
	var obj_text: String = ""
	var show_progress: bool = false
	
	match qdata.quest_type:
		QuestData.QuestType.COLLECT:
			obj_text = "Collect %s" % qdata.target_id
			show_progress = target > 1
		QuestData.QuestType.KILL:
			obj_text = "Defeat %s" % qdata.target_id
			show_progress = target > 1
		QuestData.QuestType.TALK:
			obj_text = "Speak with %s" % qdata.target_id
		QuestData.QuestType.EXPLORE:
			obj_text = "Discover %s" % qdata.target_id
		QuestData.QuestType.DELIVER:
			obj_text = "Deliver %s to %s" % [qdata.target_id, qdata.turn_in_npc_id]
	
	var is_done: bool = current >= target
	
	# Row: Bullet + Text + optional Progress
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_detail_objective_box.add_child(row)
	
	# Bullet / Check
	var bullet := Label.new()
	bullet.text = "✓" if is_done else "◆"
	bullet.add_theme_font_size_override("font_size", 12)
	bullet.add_theme_color_override("font_color",
		C_QUEST_COMPLETE if is_done else Color(C_AMBER, 0.6))
	bullet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bullet)
	
	# Text
	var lbl := Label.new()
	lbl.text = obj_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color",
		C_TEXT_LIGHT if is_done else C_TEXT_MID)
	if _font:
		lbl.add_theme_font_override("font", _font)
	row.add_child(lbl)
	
	if show_progress:
		var progress := Label.new()
		progress.text = "%d / %d" % [current, target]
		progress.add_theme_font_size_override("font_size", 12)
		progress.add_theme_color_override("font_color",
			C_QUEST_COMPLETE if is_done else C_AMBER)
		if _font:
			progress.add_theme_font_override("font", _font)
		row.add_child(progress)


func _build_rewards(qdata: QuestData) -> void:
	var has_rewards: bool = false
	
	if qdata.reward_exp > 0:
		_add_reward_row(qdata.reward_exp, "XP", C_AMBER)
		has_rewards = true
	
	if qdata.reward_gold > 0:
		_add_reward_row(qdata.reward_gold, "Gold", Color("d4b34a"))
		has_rewards = true
	
	for item_id in qdata.reward_items:
		var item_name: String = item_id
		var inv := get_node_or_null("/root/InventoryManager")
		if inv:
			var item_data = inv.get_item_data(item_id)
			if item_data != null:
				item_name = item_data.item_name
		_add_reward_row(1, item_name, C_TEXT_LIGHT)
		has_rewards = true
	
	if not has_rewards:
		var lbl := Label.new()
		lbl.text = "None"
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", C_TEXT_MUTED)
		if _font:
			lbl.add_theme_font_override("font", _font)
		_detail_rewards_box.add_child(lbl)


func _add_reward_row(amount: int, label: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_detail_rewards_box.add_child(row)
	
	var bullet := Label.new()
	bullet.text = "◆"
	bullet.add_theme_font_size_override("font_size", 8)
	bullet.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	bullet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bullet)
	
	var amount_lbl := Label.new()
	amount_lbl.text = str(amount)
	amount_lbl.add_theme_font_size_override("font_size", 13)
	amount_lbl.add_theme_color_override("font_color", color)
	if _font:
		amount_lbl.add_theme_font_override("font", _font)
	row.add_child(amount_lbl)
	
	var label_lbl := Label.new()
	label_lbl.text = label
	label_lbl.add_theme_font_size_override("font_size", 13)
	label_lbl.add_theme_color_override("font_color", C_TEXT_MID)
	if _font:
		label_lbl.add_theme_font_override("font", _font)
	row.add_child(label_lbl)


# ══════════════════════════════════════════════════════════════
#  FILTER
# ══════════════════════════════════════════════════════════════

func _set_filter(f: QuestFilter) -> void:
	_current_filter = f
	_filter_active_btn.button_pressed    = (f == QuestFilter.ACTIVE)
	_filter_completed_btn.button_pressed = (f == QuestFilter.COMPLETED)
	_filter_all_btn.button_pressed       = (f == QuestFilter.ALL)
	_update_quest_list()


# ══════════════════════════════════════════════════════════════
#  SIGNALS
# ══════════════════════════════════════════════════════════════

func _connect_signals() -> void:
	var qm := get_node_or_null("/root/QuestManager")
	if qm:
		qm.quest_added.connect(_on_quest_added)
		qm.quest_completed.connect(_on_quest_completed)
		qm.quest_updated.connect(_on_quest_updated)
		qm.quest_turned_in.connect(_on_quest_turned_in)


func _on_quest_added(_quest_id: String) -> void:
	_update_quest_list()


func _on_quest_completed(_quest_id: String) -> void:
	_update_quest_list()
	if _selected_quest_id == _quest_id:
		_update_quest_details()


func _on_quest_updated(quest_id: String, _current: int, _target: int) -> void:
	_update_quest_list()
	if _selected_quest_id == quest_id:
		_update_quest_details()


func _on_quest_turned_in(_quest_id: String) -> void:
	_update_quest_list()


# ══════════════════════════════════════════════════════════════
#  BUTTON HANDLERS
# ══════════════════════════════════════════════════════════════

func _on_quest_button_pressed(quest_id: String) -> void:
	_select_quest(quest_id)


func _on_quest_button_focused(quest_id: String) -> void:
	_select_quest(quest_id)


# ══════════════════════════════════════════════════════════════
#  PUBLIC API
# ══════════════════════════════════════════════════════════════

func refresh() -> void:
	_update_quest_list()


func focus_first_quest() -> void:
	if _quest_buttons.size() > 0:
		_quest_buttons[0].grab_focus()


func get_quest_buttons() -> Array[Button]:
	return _quest_buttons

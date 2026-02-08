extends Control
class_name QuestsUI

signal quest_selected(quest_id: String)

enum QuestFilter {
	ACTIVE,
	COMPLETED,
	ALL
}

@export var quest_item_scene: PackedScene = null

var _current_filter: QuestFilter = QuestFilter.ACTIVE
var _selected_quest_id: String = ""
var _quest_buttons: Array[Button] = []

# Node References
var filter_container: HBoxContainer = null
var filter_active_btn: Button = null
var filter_completed_btn: Button = null
var filter_all_btn: Button = null

var quest_list_container: VBoxContainer = null
var quest_scroll: ScrollContainer = null

var detail_panel: PanelContainer = null
var detail_title: Label = null
var detail_description: RichTextLabel = null
var detail_objectives: VBoxContainer = null
var detail_rewards: VBoxContainer = null

var no_quests_label: Label = null

var _font: FontFile
var font_color: Color = Color8(255, 234, 213)

func load_font() -> void:
	var font_path := "res://menu/assets/fonts/Merriweather-Regular.ttf"
	if ResourceLoader.exists(font_path):
		_font = load(font_path) as FontFile


func _ready() -> void:

	load_font()

	if _font:
		var t := Theme.new()
		t.default_font = _font
		t.default_font_size = 14

		# Optional, aber hilfreich (explizit je Control-Typ)
		t.set_font("font", "Label", _font)
		t.set_font("font", "Button", _font)
		t.set_font("normal_font", "RichTextLabel", _font)

		theme = t

	_create_ui()
	_connect_signals()
	_update_quest_list()
	



func _create_ui() -> void:
	# Haupt-Container: HSplitContainer (Liste links, Details rechts)
	var main_split := HSplitContainer.new()
	main_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_split.split_offset = 250
	add_child(main_split)
	
	# === LINKE SEITE: Quest Liste ===
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size.x = 200
	main_split.add_child(left_panel)
	
	var left_vbox := VBoxContainer.new()
	left_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_panel.add_child(left_vbox)
	
	var left_margin := MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 10)
	left_margin.add_theme_constant_override("margin_right", 10)
	left_margin.add_theme_constant_override("margin_top", 10)
	left_margin.add_theme_constant_override("margin_bottom", 10)
	left_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(left_margin)
	
	var left_content := VBoxContainer.new()
	left_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_margin.add_child(left_content)
	
	# Filter Buttons
	filter_container = HBoxContainer.new()
	filter_container.add_theme_constant_override("separation", 5)
	left_content.add_child(filter_container)
	
	filter_active_btn = Button.new()
	filter_active_btn.text = "Active"
	filter_active_btn.toggle_mode = true
	filter_active_btn.button_pressed = true
	filter_active_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_container.add_child(filter_active_btn)
	
	filter_completed_btn = Button.new()
	filter_completed_btn.text = "Done"
	filter_completed_btn.toggle_mode = true
	filter_completed_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_container.add_child(filter_completed_btn)
	
	filter_all_btn = Button.new()
	filter_all_btn.text = "All"
	filter_all_btn.toggle_mode = true
	filter_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_container.add_child(filter_all_btn)
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	left_content.add_child(spacer)
	
	# Quest Liste (scrollbar)
	quest_scroll = ScrollContainer.new()
	quest_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quest_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_content.add_child(quest_scroll)
	
	quest_list_container = VBoxContainer.new()
	quest_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_list_container.add_theme_constant_override("separation", 5)
	quest_scroll.add_child(quest_list_container)
	
	# "Keine Quests" Label
	no_quests_label = Label.new()
	no_quests_label.text = "There are no quests"
	no_quests_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_quests_label.modulate = Color(0.6, 0.6, 0.6)
	no_quests_label.visible = false
	left_content.add_child(no_quests_label)
	
	# === RECHTE SEITE: Quest Details ===
	detail_panel = PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.add_child(detail_panel)
	
	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 15)
	right_margin.add_theme_constant_override("margin_right", 15)
	right_margin.add_theme_constant_override("margin_top", 15)
	right_margin.add_theme_constant_override("margin_bottom", 15)
	right_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail_panel.add_child(right_margin)
	
	var right_vbox := VBoxContainer.new()
	right_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	right_vbox.add_theme_constant_override("separation", 10)
	right_margin.add_child(right_vbox)
	
	# Quest Titel
	detail_title = Label.new()
	detail_title.text = "Select a quest"
	detail_title.add_theme_font_size_override("font_size", 24)
	detail_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	right_vbox.add_child(detail_title)
	
	# Trennlinie
	var separator := HSeparator.new()
	right_vbox.add_child(separator)
	
	# Beschreibung
	var desc_label := Label.new()
	desc_label.text = "Description:"
	desc_label.add_theme_font_size_override("font_size", 16)
	desc_label.modulate = Color(0.8, 0.8, 0.8)
	right_vbox.add_child(desc_label)
	
	detail_description = RichTextLabel.new()
	detail_description.bbcode_enabled = true
	detail_description.fit_content = true
	detail_description.custom_minimum_size.y = 80
	detail_description.add_theme_font_size_override("normal_font_size", 14)
	right_vbox.add_child(detail_description)
	
	# Ziele
	var obj_label := Label.new()
	obj_label.text = "Goals:"
	obj_label.add_theme_font_size_override("font_size", 16)
	obj_label.modulate = Color(0.8, 0.8, 0.8)
	right_vbox.add_child(obj_label)
	
	detail_objectives = VBoxContainer.new()
	detail_objectives.add_theme_constant_override("separation", 5)
	right_vbox.add_child(detail_objectives)
	
	# Belohnungen
	var reward_label := Label.new()
	reward_label.text = "Rewards:"
	reward_label.add_theme_font_size_override("font_size", 16)
	reward_label.modulate = Color(0.8, 0.8, 0.8)
	right_vbox.add_child(reward_label)
	
	detail_rewards = VBoxContainer.new()
	detail_rewards.add_theme_constant_override("separation", 3)
	right_vbox.add_child(detail_rewards)
	
	# Spacer für Layout
	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(bottom_spacer)


func _connect_signals() -> void:
	filter_active_btn.pressed.connect(_on_filter_active)
	filter_completed_btn.pressed.connect(_on_filter_completed)
	filter_all_btn.pressed.connect(_on_filter_all)
	
	# QuestManager Signals
	var quest_manager: Node = get_node_or_null("/root/QuestManager")
	if quest_manager:
		quest_manager.quest_added.connect(_on_quest_added)
		quest_manager.quest_completed.connect(_on_quest_completed)
		quest_manager.quest_updated.connect(_on_quest_updated)
		quest_manager.quest_turned_in.connect(_on_quest_turned_in)


func _on_filter_active() -> void:
	_set_filter(QuestFilter.ACTIVE)


func _on_filter_completed() -> void:
	_set_filter(QuestFilter.COMPLETED)


func _on_filter_all() -> void:
	_set_filter(QuestFilter.ALL)


func _set_filter(filter: QuestFilter) -> void:
	_current_filter = filter
	
	# Toggle Buttons aktualisieren
	filter_active_btn.button_pressed = (filter == QuestFilter.ACTIVE)
	filter_completed_btn.button_pressed = (filter == QuestFilter.COMPLETED)
	filter_all_btn.button_pressed = (filter == QuestFilter.ALL)
	
	_update_quest_list()


func _update_quest_list() -> void:
	# Alte Buttons entfernen
	for child in quest_list_container.get_children():
		child.queue_free()
	
	_quest_buttons.clear()
	
	var quest_manager: Node = get_node_or_null("/root/QuestManager")
	if quest_manager == null:
		no_quests_label.visible = true
		return
	
	var quests_to_show: Array[String] = []
	
	match _current_filter:
		QuestFilter.ACTIVE:
			quests_to_show = quest_manager.get_active_quests()
		QuestFilter.COMPLETED:
			quests_to_show = quest_manager.get_completed_quests()
		QuestFilter.ALL:
			quests_to_show = quest_manager.get_active_quests()
			for q in quest_manager.get_completed_quests():
				if q not in quests_to_show:
					quests_to_show.append(q)
	
	no_quests_label.visible = quests_to_show.is_empty()
	
	for quest_id in quests_to_show:
		var button := _create_quest_button(quest_id)
		quest_list_container.add_child(button)
		_quest_buttons.append(button)
	
	# Navigation zwischen Buttons
	_setup_button_navigation()
	
	# Erste Quest auswählen falls vorhanden
	if _quest_buttons.size() > 0:
		_select_quest(_get_quest_id_from_button(_quest_buttons[0]))


func _create_quest_button(quest_id: String) -> Button:
	var quest_manager: Node = get_node_or_null("/root/QuestManager")
	var quest_data: QuestData = quest_manager.get_quest_data(quest_id) if quest_manager else null
	var quest_state = quest_manager.get_quest_state(quest_id) if quest_manager else null
	
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	# Quest Name
	var quest_name: String = quest_data.quest_name if quest_data else quest_id
	
	# Status Icon
	var status_icon: String = ""
	if quest_state and quest_state.is_complete:
		status_icon = "✓ "
		button.modulate = Color(0.6, 1.0, 0.6)  # Grünlich
	elif quest_manager.is_quest_turned_in(quest_id):
		status_icon = "★ "
		button.modulate = Color(1.0, 0.85, 0.4)  # Gold
	else:
		status_icon = "● "
	
	button.text = status_icon + quest_name
	button.set_meta("quest_id", quest_id)
	
	button.pressed.connect(_on_quest_button_pressed.bind(quest_id))
	button.focus_entered.connect(_on_quest_button_focused.bind(quest_id))
	
	return button


func _get_quest_id_from_button(button: Button) -> String:
	return button.get_meta("quest_id", "")


func _setup_button_navigation() -> void:
	for i in range(_quest_buttons.size()):
		var btn: Button = _quest_buttons[i]
		
		if i > 0:
			btn.focus_neighbor_top = _quest_buttons[i - 1].get_path()
		else:
			btn.focus_neighbor_top = btn.get_path()
		
		if i < _quest_buttons.size() - 1:
			btn.focus_neighbor_bottom = _quest_buttons[i + 1].get_path()
		else:
			btn.focus_neighbor_bottom = btn.get_path()
		
		btn.focus_neighbor_left = btn.get_path()
		btn.focus_neighbor_right = btn.get_path()


func _on_quest_button_pressed(quest_id: String) -> void:
	_select_quest(quest_id)


func _on_quest_button_focused(quest_id: String) -> void:
	_select_quest(quest_id)


func _select_quest(quest_id: String) -> void:
	_selected_quest_id = quest_id
	_update_quest_details()
	quest_selected.emit(quest_id)


func _update_quest_details() -> void:
	# Details leeren
	for child in detail_objectives.get_children():
		child.queue_free()
	for child in detail_rewards.get_children():
		child.queue_free()
	
	if _selected_quest_id == "":
		detail_title.text = "Select a quest"
		detail_description.text = ""
		return
	
	var quest_manager: Node = get_node_or_null("/root/QuestManager")
	if quest_manager == null:
		return
	
	var quest_data: QuestData = quest_manager.get_quest_data(_selected_quest_id)
	var quest_state = quest_manager.get_quest_state(_selected_quest_id)
	
	if quest_data == null:
		detail_title.text = _selected_quest_id
		detail_description.text = "No details available."
		return
	
	# Titel
	detail_title.text = quest_data.quest_name
	
	# Status hinzufügen
	if quest_manager.is_quest_turned_in(_selected_quest_id):
		detail_title.text += " [Delivered]"
	elif quest_state and quest_state.is_complete:
		detail_title.text += " [Solved]"
	
	# Beschreibung
	detail_description.text = quest_data.description
	
	# Ziele
	var objective_label := Label.new()
	var current: int = quest_state.current_amount if quest_state else 0
	var target: int = quest_data.target_amount
	
	var objective_text: String = ""
	match quest_data.quest_type:
		QuestData.QuestType.COLLECT:
			objective_text = "Collect: %s (%d/%d)" % [quest_data.target_id, current, target]
		QuestData.QuestType.KILL:
			objective_text = "Kill: %s (%d/%d)" % [quest_data.target_id, current, target]
		QuestData.QuestType.TALK:
			objective_text = "Talk with: %s" % quest_data.target_id
			if current >= target:
				objective_text += " ✓"
		QuestData.QuestType.EXPLORE:
			objective_text = "Find: %s" % quest_data.target_id
			if current >= target:
				objective_text += " ✓"
		QuestData.QuestType.DELIVER:
			objective_text = "Deliver: %s an %s" % [quest_data.target_id, quest_data.turn_in_npc_id]
	
	objective_label.text = "• " + objective_text
	
	# Farbe basierend auf Fortschritt
	if quest_state and quest_state.is_complete:
		objective_label.modulate = Color(0.5, 1.0, 0.5)
	
	detail_objectives.add_child(objective_label)
	
	# Belohnungen
	if quest_data.reward_exp > 0:
		var exp_label := Label.new()
		exp_label.text = "• %d Experience" % quest_data.reward_exp
		exp_label.modulate = Color(0.7, 0.7, 1.0)
		detail_rewards.add_child(exp_label)
	
	if quest_data.reward_gold > 0:
		var gold_label := Label.new()
		gold_label.text = "• %d Gold" % quest_data.reward_gold
		gold_label.modulate = Color(1.0, 0.85, 0.4)
		detail_rewards.add_child(gold_label)
	
	for item_id in quest_data.reward_items:
		var item_label := Label.new()
		item_label.text = "• " + item_id
		item_label.modulate = Color(0.8, 0.8, 0.8)
		detail_rewards.add_child(item_label)


# === Signal Handler ===

func _on_quest_added(_quest_id: String) -> void:
	_update_quest_list()


func _on_quest_completed(_quest_id: String) -> void:
	_update_quest_list()
	if _selected_quest_id == _quest_id:
		_update_quest_details()


func _on_quest_updated(quest_id: String, _current: int, _target: int) -> void:
	if _selected_quest_id == quest_id:
		_update_quest_details()


func _on_quest_turned_in(_quest_id: String) -> void:
	_update_quest_list()


# === Public Methods ===

func refresh() -> void:
	_update_quest_list()


func focus_first_quest() -> void:
	if _quest_buttons.size() > 0:
		_quest_buttons[0].grab_focus()


func get_quest_buttons() -> Array[Button]:
	return _quest_buttons

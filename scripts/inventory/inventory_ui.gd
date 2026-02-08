extends Control
class_name InventoryUI

signal item_selected(item_id: String)

const GRID_COLUMNS: int = 6
const SLOT_SIZE: Vector2 = Vector2(64, 64)
const SLOT_SPACING: int = 8

var _item_slots: Array[Button] = []
var _selected_item_id: String = ""
var _selected_slot_index: int = -1

# Node References
var grid_container: GridContainer = null
var detail_panel: PanelContainer = null
var detail_icon: TextureRect = null
var detail_name: Label = null
var detail_description: RichTextLabel = null
var detail_type: Label = null

var hotbar_container: HBoxContainer = null
var hotbar_slots: Array[PanelContainer] = []
var hotbar_labels: Array[Label] = []

var assign_hint: Label = null

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
	_update_inventory_grid()
	_update_hotbar_display()
	
	set_process_input(false)
	
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			# Input nur aktiv wenn sichtbar
			set_process_input(is_visible_in_tree())
			
			# Auswahl zurücksetzen wenn versteckt
			if not is_visible_in_tree():
				_selected_item_id = ""
				_selected_slot_index = -1


func _create_ui() -> void:
	# Haupt-Container
	var main_hbox := HBoxContainer.new()
	main_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 15)
	add_child(main_hbox)
	
	# === LINKE SEITE: Inventar Grid ===
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(left_panel)
	
	var left_margin := MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 10)
	left_margin.add_theme_constant_override("margin_right", 10)
	left_margin.add_theme_constant_override("margin_top", 10)
	left_margin.add_theme_constant_override("margin_bottom", 10)
	left_panel.add_child(left_margin)
	
	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 10)
	left_margin.add_child(left_vbox)
	
	# Titel
	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 20)
	left_vbox.add_child(title)
	
	# Grid ScrollContainer
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vbox.add_child(scroll)
	
	var grid_margin := MarginContainer.new()
	grid_margin.add_theme_constant_override("margin_left", 8)
	grid_margin.add_theme_constant_override("margin_right", 8)
	grid_margin.add_theme_constant_override("margin_top", 8)
	grid_margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(grid_margin)

	grid_container = GridContainer.new()
	grid_container.columns = GRID_COLUMNS
	grid_container.add_theme_constant_override("h_separation", SLOT_SPACING)
	grid_container.add_theme_constant_override("v_separation", SLOT_SPACING)
	grid_margin.add_child(grid_container)
	
	# Hotbar Zuweisung
	var hotbar_section := VBoxContainer.new()
	hotbar_section.add_theme_constant_override("separation", 5)
	left_vbox.add_child(hotbar_section)
	
	var hotbar_title := Label.new()
	hotbar_title.text = "Quick Select"
	hotbar_title.add_theme_font_size_override("font_size", 16)
	hotbar_section.add_child(hotbar_title)
	
	hotbar_container = HBoxContainer.new()
	hotbar_container.add_theme_constant_override("separation", 10)
	hotbar_section.add_child(hotbar_container)
	
	# 4 Hotbar Slots erstellen (W, A, S, D)
	var slot_keys: Array[String] = ["W", "A", "S", "D"]
	for i in range(4):
		var slot_vbox := VBoxContainer.new()
		slot_vbox.add_theme_constant_override("separation", 2)
		hotbar_container.add_child(slot_vbox)
		
		var key_label := Label.new()
		key_label.text = slot_keys[i]
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 14)
		slot_vbox.add_child(key_label)
		
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(48, 48)
		slot_vbox.add_child(slot)
		hotbar_slots.append(slot)
		
		# Icon Container
		var icon_container := Control.new()
		icon_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(icon_container)
		
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon_container.add_child(icon)
		
		hotbar_labels.append(key_label)
	
	# Zuweisungs-Hinweis
	assign_hint = Label.new()
	assign_hint.text = "Select an item and press W/A/S/D to assign"
	assign_hint.add_theme_font_size_override("font_size", 12)
	assign_hint.modulate = Color(0.7, 0.7, 0.7)
	hotbar_section.add_child(assign_hint)
	
	# === RECHTE SEITE: Item Details ===
	detail_panel = PanelContainer.new()
	detail_panel.custom_minimum_size.x = 200
	main_hbox.add_child(detail_panel)
	
	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 15)
	right_margin.add_theme_constant_override("margin_right", 15)
	right_margin.add_theme_constant_override("margin_top", 15)
	right_margin.add_theme_constant_override("margin_bottom", 15)
	detail_panel.add_child(right_margin)
	
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 10)
	right_margin.add_child(right_vbox)
	
	# Item Icon
	var icon_center := CenterContainer.new()
	right_vbox.add_child(icon_center)
	
	detail_icon = TextureRect.new()
	detail_icon.custom_minimum_size = Vector2(64, 64)
	detail_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED#
	detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	icon_center.add_child(detail_icon)
	
	# Item Name
	detail_name = Label.new()
	detail_name.text = "Select an item"
	detail_name.add_theme_font_size_override("font_size", 18)
	detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(detail_name)
	
	# Item Type
	detail_type = Label.new()
	detail_type.text = ""
	detail_type.add_theme_font_size_override("font_size", 12)
	detail_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_type.modulate = Color(0.7, 0.7, 0.7)
	right_vbox.add_child(detail_type)
	
	# Separator
	var sep := HSeparator.new()
	right_vbox.add_child(sep)
	
	# Item Description
	detail_description = RichTextLabel.new()
	detail_description.bbcode_enabled = true
	detail_description.fit_content = true
	detail_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_description.add_theme_font_size_override("normal_font_size", 14)
	right_vbox.add_child(detail_description)


func _connect_signals() -> void:
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager:
		inv_manager.inventory_changed.connect(_on_inventory_changed)
		inv_manager.hotbar_changed.connect(_on_hotbar_changed)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if _selected_item_id == "":
		return
	
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		return
	
	# Hotbar Zuweisung mit W/A/S/D - im Menü SOLL verschoben werden
	if event is InputEventKey and event.pressed and not event.echo:
		var assigned: bool = false
		
		match event.keycode:
			KEY_W:
				inv_manager.assign_to_hotbar(0, _selected_item_id, true)  # true = verschieben
				assigned = true
			KEY_A:
				inv_manager.assign_to_hotbar(1, _selected_item_id, true)
				assigned = true
			KEY_S:
				inv_manager.assign_to_hotbar(2, _selected_item_id, true)
				assigned = true
			KEY_D:
				inv_manager.assign_to_hotbar(3, _selected_item_id, true)
				assigned = true
		
		if assigned:
			get_viewport().set_input_as_handled()


func _update_inventory_grid() -> void:
	# Alte Slots entfernen
	for child in grid_container.get_children():
		child.queue_free()
	
	_item_slots.clear()
	
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		return
	
	var items: Dictionary = inv_manager.get_all_items()
	var index: int = 0
	
	for item_id in items:
		var amount: int = items[item_id]
		var item_data: ItemData = inv_manager.get_item_data(item_id)
		
		var slot := _create_item_slot(item_id, item_data, amount, index)
		grid_container.add_child(slot)
		_item_slots.append(slot)
		index += 1
	
	# Leere Slots auffüllen (mindestens 24 Slots)
	var min_slots: int = 24
	while index < min_slots:
		var empty_slot := _create_empty_slot(index)
		grid_container.add_child(empty_slot)
		_item_slots.append(empty_slot)
		index += 1
	
	# Navigation Setup
	_setup_grid_navigation()


func _create_item_slot(item_id: String, item_data: ItemData, amount: int, index: int) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.set_meta("item_id", item_id)
	slot.set_meta("slot_index", index)
	
	# Container für Icon und Anzahl
	var container := MarginContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Padding innerhalb der Kachel:
	container.add_theme_constant_override("margin_left", 6)
	container.add_theme_constant_override("margin_right", 6)
	container.add_theme_constant_override("margin_top", 6)
	container.add_theme_constant_override("margin_bottom", 6)

	slot.add_child(container)

	
	# Icon
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	
	if item_data and item_data.icon:
		icon.texture = item_data.icon
	
	container.add_child(icon)
	
	# Anzahl Label
	if amount > 1:
		var amount_label := Label.new()
		amount_label.text = str(amount)
		amount_label.add_theme_font_size_override("font_size", 12)
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		amount_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(amount_label)
	
	# Rarität-Farbe am Rand
	if item_data:
		var color: Color = item_data.get_rarity_color()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
		style.border_width_bottom = 3
		style.border_color = color
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		slot.add_theme_stylebox_override("normal", style)
		
		var hover_style := style.duplicate()
		hover_style.bg_color = Color(0.25, 0.25, 0.25, 0.9)
		slot.add_theme_stylebox_override("hover", hover_style)
		
		var focus_style := style.duplicate()
		focus_style.bg_color = Color(0.3, 0.3, 0.35, 0.9)
		focus_style.border_width_top = 2
		focus_style.border_width_left = 2
		focus_style.border_width_right = 2
		slot.add_theme_stylebox_override("focus", focus_style)
	
	# Callbacks
	slot.pressed.connect(_on_slot_pressed.bind(item_id, index))
	slot.focus_entered.connect(_on_slot_focused.bind(item_id, index))
	
	return slot


func _create_empty_slot(index: int) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.set_meta("item_id", "")
	slot.set_meta("slot_index", index)
	slot.disabled = true
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slot.add_theme_stylebox_override("normal", style)
	slot.add_theme_stylebox_override("disabled", style)
	
	return slot


func _setup_grid_navigation() -> void:
	for i in range(_item_slots.size()):
		var slot: Button = _item_slots[i]
		if slot.disabled:
			continue
		
		var row: int = i / GRID_COLUMNS
		var col: int = i % GRID_COLUMNS
		
		# Oben
		if row > 0:
			var up_index: int = i - GRID_COLUMNS
			if up_index >= 0 and up_index < _item_slots.size():
				slot.focus_neighbor_top = _item_slots[up_index].get_path()
		
		# Unten
		var down_index: int = i + GRID_COLUMNS
		if down_index < _item_slots.size():
			slot.focus_neighbor_bottom = _item_slots[down_index].get_path()
		
		# Links
		if col > 0:
			slot.focus_neighbor_left = _item_slots[i - 1].get_path()
		
		# Rechts
		if col < GRID_COLUMNS - 1 and i + 1 < _item_slots.size():
			slot.focus_neighbor_right = _item_slots[i + 1].get_path()


func _on_slot_pressed(item_id: String, index: int) -> void:
	_select_item(item_id, index)


func _on_slot_focused(item_id: String, index: int) -> void:
	_select_item(item_id, index)


func _select_item(item_id: String, index: int) -> void:
	_selected_item_id = item_id
	_selected_slot_index = index
	_update_item_details()
	item_selected.emit(item_id)


func _update_item_details() -> void:
	if _selected_item_id == "":
		detail_name.text = "Select an item"
		detail_type.text = ""
		detail_description.text = ""
		detail_icon.texture = null
		assign_hint.text = "Select an item and press W/A/S/D to assign"
		return
	
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		return
	
	var item_data: ItemData = inv_manager.get_item_data(_selected_item_id)
	
	if item_data == null:
		detail_name.text = _selected_item_id
		detail_type.text = ""
		detail_description.text = "No details available."
		detail_icon.texture = null
		return
	
	detail_name.text = item_data.item_name
	detail_name.modulate = item_data.get_rarity_color()
	
	# Type
	var type_text: String = ""
	match item_data.item_type:
		ItemData.ItemType.WEAPON:
			type_text = "Weapon"
		ItemData.ItemType.CONSUMABLE:
			type_text = "Consumable"
		ItemData.ItemType.KEY_ITEM:
			type_text = "Key item"
		ItemData.ItemType.MATERIAL:
			type_text = "Material"
	detail_type.text = type_text
	
	detail_description.text = item_data.description
	detail_icon.texture = item_data.icon
	
	# Hinweis aktualisieren
	if item_data.usable:
		assign_hint.text = "Select W/A/S/D to assign"
		assign_hint.modulate = Color(0.8, 0.9, 0.8)
	else:
		assign_hint.text = "Cannot be assigned"
		assign_hint.modulate = Color(0.7, 0.5, 0.5)


func _update_hotbar_display() -> void:
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		return
	
	for i in range(hotbar_slots.size()):
		var slot: PanelContainer = hotbar_slots[i]
		var icon: TextureRect = slot.get_node_or_null("Control/Icon") as TextureRect
		
		if icon == null:
			# Fallback: Direkt suchen
			for child in slot.get_children():
				if child is Control:
					for subchild in child.get_children():
						if subchild is TextureRect:
							icon = subchild
							break
		
		var item_id: String = inv_manager.get_hotbar_item(i)
		var item_data: ItemData = inv_manager.get_item_data(item_id) if item_id != "" else null
		
		if icon:
			if item_data and item_data.icon:
				icon.texture = item_data.icon
			else:
				icon.texture = null


func _on_inventory_changed() -> void:
	_update_inventory_grid()


func _on_hotbar_changed(_slot_index: int, _item_id: String) -> void:
	_update_hotbar_display()


# === Public Methods ===

func refresh() -> void:
	_update_inventory_grid()
	_update_hotbar_display()


func focus_first_item() -> void:
	for slot in _item_slots:
		if not slot.disabled:
			slot.grab_focus()
			return


func get_item_slots() -> Array[Button]:
	return _item_slots

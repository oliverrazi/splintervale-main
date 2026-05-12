extends Control
class_name InventoryUI

signal item_selected(item_id: String)

# ── LAYOUT ─────────────────────────────────────────────────────
const SLOTS_PER_ROW: int    = 8
const SLOT_SIZE: Vector2    = Vector2(44, 44)
const SLOT_SPACING: int     = 4
const HOTBAR_SLOT_SIZE: Vector2 = Vector2(40, 40)

# ── FARBEN ─────────────────────────────────────────────────────
const C_BG_TOME     := Color("1e1810", 0.9)
const C_BG_DEEP     := Color("14100a")
const C_BG_SLOT     := Color("231c13")
const C_BORDER      := Color("2e1f0e")
const C_BORDER_OUT  := Color("5c3d1e")
const C_AMBER       := Color("c4923a")
const C_AMBER_DIM   := Color("c4923a", 0.20)
const C_AMBER_FAINT := Color("c4923a", 0.06)
const C_TEXT_LIGHT  := Color("d4b880")
const C_TEXT_MID    := Color("8a7050")
const C_TEXT_MUTED  := Color("6b5030")

# ── ZUSTAND ────────────────────────────────────────────────────
var _item_slots: Array[Button] = []
var _selected_item_id: String  = ""
var _selected_slot_index: int  = -1
var _font: FontFile             = null

# ── UI-REFERENZEN ──────────────────────────────────────────────
var weapons_grid: GridContainer     = null
var relics_grid: GridContainer      = null
var collectables_grid: GridContainer = null
var key_items_grid: GridContainer   = null

var detail_panel: PanelContainer    = null
var detail_icon: TextureRect        = null
var detail_name: Label              = null
var detail_description: RichTextLabel = null
var detail_type: Label              = null

var hotbar_slots: Array[PanelContainer] = []
var hotbar_labels: Array[Label]         = []
var assign_hint: Label                  = null


# ═══════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════

func _ready() -> void:
	_load_font()
	if _font:
		var t := Theme.new()
		t.default_font      = _font
		t.default_font_size = 13
		theme = t
	
	_create_ui()
	_connect_signals()
	refresh()
	
	set_process_input(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process_input(is_visible_in_tree())
		if not is_visible_in_tree():
			_selected_item_id    = ""
			_selected_slot_index = -1


func _load_font() -> void:
	var path := "res://menu/assets/fonts/Merriweather-Regular.ttf"
	if ResourceLoader.exists(path):
		_font = load(path) as FontFile


# ═══════════════════════════════════════════════════════════════
#  UI-AUFBAU
# ═══════════════════════════════════════════════════════════════

func _create_ui() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left",   16)
	root.add_theme_constant_override("margin_right",  16)
	root.add_theme_constant_override("margin_top",    12)
	root.add_theme_constant_override("margin_bottom", 12)
	add_child(root)
	
	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 16)
	root.add_child(main_hbox)
	
	# === LINKS: 4 Kategorien-Reihen + Hotbar ===
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 14)
	main_hbox.add_child(left_vbox)
	
	weapons_grid      = _build_category_section(left_vbox, "Weapons")
	relics_grid       = _build_category_section(left_vbox, "Relics")
	collectables_grid = _build_category_section(left_vbox, "Collectables")
	key_items_grid    = _build_category_section(left_vbox, "Key Items")
	
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(spacer)
	
	_build_hotbar_section(left_vbox)
	_build_detail_panel(main_hbox)


func _build_category_section(parent: VBoxContainer, title: String) -> GridContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	parent.add_child(section)
	
	section.add_child(_build_section_header(title))
	
	var grid := GridContainer.new()
	grid.columns = SLOTS_PER_ROW
	grid.add_theme_constant_override("h_separation", SLOT_SPACING)
	grid.add_theme_constant_override("v_separation", SLOT_SPACING)
	section.add_child(grid)
	
	return grid


func _build_section_header(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	
	var line_l := ColorRect.new()
	line_l.color                 = Color(C_BORDER_OUT, 0.7)
	line_l.custom_minimum_size   = Vector2(8, 1)
	line_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_l.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	
	var diamond_l := Label.new()
	diamond_l.text = "◆"
	diamond_l.add_theme_font_size_override("font_size", 8)
	diamond_l.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	
	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(C_AMBER, 0.75))
	if _font:
		lbl.add_theme_font_override("font", _font)
	
	var diamond_r := Label.new()
	diamond_r.text = "◆"
	diamond_r.add_theme_font_size_override("font_size", 8)
	diamond_r.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	
	var line_r := ColorRect.new()
	line_r.color                 = Color(C_BORDER_OUT, 0.7)
	line_r.custom_minimum_size   = Vector2(8, 1)
	line_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_r.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	
	row.add_child(line_l)
	row.add_child(diamond_l)
	row.add_child(lbl)
	row.add_child(diamond_r)
	row.add_child(line_r)
	return row


func _build_hotbar_section(parent: VBoxContainer) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	parent.add_child(section)
	
	section.add_child(_build_section_header("Quick Select"))
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	section.add_child(hbox)
	
	var keys: Array[String] = ["W", "A", "S", "D"]
	for i in range(4):
		var slot_vbox := VBoxContainer.new()
		slot_vbox.add_theme_constant_override("separation", 3)
		hbox.add_child(slot_vbox)
		
		var key_lbl := Label.new()
		key_lbl.text                 = keys[i]
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_lbl.add_theme_font_size_override("font_size", 11)
		key_lbl.add_theme_color_override("font_color", Color(C_AMBER, 0.7))
		if _font:
			key_lbl.add_theme_font_override("font", _font)
		slot_vbox.add_child(key_lbl)
		hotbar_labels.append(key_lbl)
		
		var slot := PanelContainer.new()
		slot.custom_minimum_size = HOTBAR_SLOT_SIZE
		_apply_slot_style(slot, false)
		slot_vbox.add_child(slot)
		hotbar_slots.append(slot)
		
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(center)
		
		var icon := TextureRect.new()
		icon.name                 = "Icon"
		icon.custom_minimum_size  = Vector2(28, 28)
		icon.expand_mode          = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode         = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter       = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		center.add_child(icon)
	
	assign_hint = Label.new()
	assign_hint.text                 = "Select an item and press W/A/S/D to assign"
	assign_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	assign_hint.add_theme_font_size_override("font_size", 11)
	assign_hint.add_theme_color_override("font_color", C_TEXT_MID)
	if _font:
		assign_hint.add_theme_font_override("font", _font)
	section.add_child(assign_hint)


func _build_detail_panel(parent: HBoxContainer) -> void:
	detail_panel = PanelContainer.new()
	detail_panel.custom_minimum_size.x = 240
	detail_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	
	var sb := StyleBoxFlat.new()
	sb.bg_color              = C_BG_DEEP
	sb.border_color          = Color(C_BORDER_OUT, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left   = 16
	sb.content_margin_right  = 16
	sb.content_margin_top    = 16
	sb.content_margin_bottom = 16
	detail_panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(detail_panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	detail_panel.add_child(vbox)
	
	var icon_center := CenterContainer.new()
	vbox.add_child(icon_center)
	
	detail_icon = TextureRect.new()
	detail_icon.custom_minimum_size = Vector2(64, 64)
	detail_icon.expand_mode         = TextureRect.EXPAND_IGNORE_SIZE
	detail_icon.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_icon.texture_filter      = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_center.add_child(detail_icon)
	
	detail_name = Label.new()
	detail_name.text                 = "Select an item"
	detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_name.add_theme_font_size_override("font_size", 15)
	detail_name.add_theme_color_override("font_color", C_TEXT_LIGHT)
	if _font:
		detail_name.add_theme_font_override("font", _font)
	vbox.add_child(detail_name)
	
	detail_type = Label.new()
	detail_type.text                 = ""
	detail_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_type.add_theme_font_size_override("font_size", 10)
	detail_type.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	if _font:
		detail_type.add_theme_font_override("font", _font)
	vbox.add_child(detail_type)
	
	var sep := ColorRect.new()
	sep.color                     = Color(C_BORDER_OUT, 0.4)
	sep.custom_minimum_size       = Vector2(0, 1)
	vbox.add_child(sep)
	
	detail_description = RichTextLabel.new()
	detail_description.bbcode_enabled       = true
	detail_description.fit_content          = true
	detail_description.size_flags_vertical  = Control.SIZE_EXPAND_FILL
	detail_description.add_theme_font_size_override("normal_font_size", 12)
	detail_description.add_theme_color_override("default_color", C_TEXT_MID)
	if _font:
		detail_description.add_theme_font_override("normal_font", _font)
	vbox.add_child(detail_description)


# ═══════════════════════════════════════════════════════════════
#  SLOT-STYLING
# ═══════════════════════════════════════════════════════════════

func _build_slot_stylebox(state: int, rarity_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(2)
	sb.set_border_width_all(1)
	
	match state:
		0:
			sb.bg_color     = C_BG_SLOT
			sb.border_color = C_BORDER_OUT
		1:
			sb.bg_color     = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.08)
			sb.border_color = Color(rarity_color, 0.5)
		2:
			sb.bg_color          = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.15)
			sb.border_color      = rarity_color
			sb.set_border_width_all(1)
			sb.border_width_bottom = 2
	return sb


func _apply_slot_style(panel: PanelContainer, has_item: bool, rarity_color: Color = C_BORDER_OUT) -> void:
	var color: Color = rarity_color if has_item else C_BORDER_OUT
	panel.add_theme_stylebox_override("panel", _build_slot_stylebox(0, color))


# ═══════════════════════════════════════════════════════════════
#  INVENTAR-GRID AUFBAU
# ═══════════════════════════════════════════════════════════════

func _update_inventory_grid() -> void:
	for grid in [weapons_grid, relics_grid, collectables_grid, key_items_grid]:
		if grid == null:
			continue
		while grid.get_child_count() > 0:
			var child : Variant = grid.get_child(0)
			grid.remove_child(child)
			child.queue_free()
	_item_slots.clear()
	
	var inv_manager := get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		return
	
	var items: Dictionary = inv_manager.get_all_items()
	
	var weapons: Array      = []
	var relics: Array       = []
	var collectables: Array = []
	var key_items: Array    = []
	
	for item_id in items:
		var data: ItemData = inv_manager.get_item_data(item_id)
		var amount: int    = items[item_id]
		var entry: Dictionary = {"id": item_id, "data": data, "amount": amount}
		
		if data == null:
			collectables.append(entry)
			continue
		
		match data.item_type:
			ItemData.ItemType.WEAPON:
				weapons.append(entry)
			ItemData.ItemType.EQUIPMENT:
				relics.append(entry)
			ItemData.ItemType.KEY_ITEM:
				key_items.append(entry)
			_:
				collectables.append(entry)
	
	_fill_category_grid(weapons_grid,      weapons)
	_fill_category_grid(relics_grid,       relics)
	_fill_category_grid(collectables_grid, collectables)
	_fill_category_grid(key_items_grid,    key_items)
	
	_setup_grid_navigation()


func _fill_category_grid(grid: GridContainer, entries: Array) -> void:
	if grid == null:
		return
	
	if entries.is_empty():
		var slot := _create_empty_slot()
		grid.add_child(slot)
		_item_slots.append(slot)
		return
	
	for e in entries:
		var slot := _create_item_slot(e["id"], e["data"], e["amount"])
		grid.add_child(slot)
		_item_slots.append(slot)


func _create_item_slot(item_id: String, data: ItemData, amount: int) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.set_meta("item_id", item_id)
	
	var rarity_color: Color = C_AMBER
	if data != null:
		rarity_color = data.get_rarity_color()
	
	slot.add_theme_stylebox_override("normal",   _build_slot_stylebox(0, rarity_color))
	slot.add_theme_stylebox_override("hover",    _build_slot_stylebox(1, rarity_color))
	slot.add_theme_stylebox_override("pressed",  _build_slot_stylebox(2, rarity_color))
	slot.add_theme_stylebox_override("focus",    _build_slot_stylebox(2, rarity_color))
	
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left",   4)
	margin.add_theme_constant_override("margin_right",  4)
	margin.add_theme_constant_override("margin_top",    4)
	margin.add_theme_constant_override("margin_bottom", 4)
	slot.add_child(margin)
	
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode   = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	if data and data.icon:
		icon.texture = data.icon
	margin.add_child(icon)
	
	if amount > 1:
		var amount_lbl := Label.new()
		amount_lbl.text                 = str(amount)
		amount_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
		amount_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		amount_lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		amount_lbl.add_theme_font_size_override("font_size", 10)
		amount_lbl.add_theme_color_override("font_color", C_TEXT_LIGHT)
		if _font:
			amount_lbl.add_theme_font_override("font", _font)
		margin.add_child(amount_lbl)
	
	slot.pressed.connect(_on_slot_pressed.bind(item_id))
	slot.focus_entered.connect(_on_slot_focused.bind(item_id))
	return slot


func _create_empty_slot() -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.set_meta("item_id", "")
	slot.disabled = true
	
	var sb := StyleBoxFlat.new()
	sb.bg_color     = Color(C_BG_DEEP.r, C_BG_DEEP.g, C_BG_DEEP.b, 0.6)
	sb.border_color = Color(C_BORDER, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	
	slot.add_theme_stylebox_override("normal",   sb)
	slot.add_theme_stylebox_override("disabled", sb)
	return slot


# ═══════════════════════════════════════════════════════════════
#  NAVIGATION (Focus-Trap + Hoch/Runter zwischen Reihen)
# ═══════════════════════════════════════════════════════════════

func _setup_grid_navigation() -> void:
	# Aktive Slots in visueller Reihenfolge sammeln
	# (Weapons → Relics → Collectables → Key Items)
	var active: Array[Button] = []
	for slot in _item_slots:
		if not slot.disabled:
			active.append(slot)
	
	if active.is_empty():
		return
	
	# Reihen-Aufbau: jede "Reihe" hat max. SLOTS_PER_ROW Items.
	# Beim Wechsel auf ein neues Grid (Kategorie) beginnt eine neue Reihe.
	var rows: Array = []
	var current_row: Array[Button] = []
	var col_count: int = 0
	var prev_grid: GridContainer = null
	
	for slot in active:
		var grid: GridContainer = _find_parent_grid(slot)
		if grid != prev_grid or col_count >= SLOTS_PER_ROW:
			if not current_row.is_empty():
				rows.append(current_row)
			current_row = []
			col_count = 0
			prev_grid = grid
		current_row.append(slot)
		col_count += 1
	
	if not current_row.is_empty():
		rows.append(current_row)
	
	# Navigation pro Slot setzen: links/rechts innerhalb der Reihe,
	# hoch/runter zwischen Reihen, Trap an allen Außenrändern
	for r in range(rows.size()):
		var row: Array = rows[r]
		for c in range(row.size()):
			var slot: Button = row[c]
			
			# LINKS
			if c > 0:
				slot.focus_neighbor_left = row[c - 1].get_path()
			else:
				slot.focus_neighbor_left = slot.get_path()
			
			# RECHTS
			if c < row.size() - 1:
				slot.focus_neighbor_right = row[c + 1].get_path()
			else:
				slot.focus_neighbor_right = slot.get_path()
			
			# HOCH: gleiche Spalte in vorheriger Reihe (oder letzter Slot davon)
			if r > 0:
				var prev_row: Array = rows[r - 1]
				var target_idx: int = min(c, prev_row.size() - 1)
				slot.focus_neighbor_top = prev_row[target_idx].get_path()
			else:
				slot.focus_neighbor_top = slot.get_path()
			
			# RUNTER: gleiche Spalte in nächster Reihe (oder letzter Slot davon)
			if r < rows.size() - 1:
				var next_row: Array = rows[r + 1]
				var target_idx: int = min(c, next_row.size() - 1)
				slot.focus_neighbor_bottom = next_row[target_idx].get_path()
			else:
				slot.focus_neighbor_bottom = slot.get_path()


func _find_parent_grid(slot: Button) -> GridContainer:
	var p: Node = slot.get_parent()
	while p != null:
		if p is GridContainer:
			return p as GridContainer
		p = p.get_parent()
	return null


# ═══════════════════════════════════════════════════════════════
#  SELECTION + DETAIL-UPDATE
# ═══════════════════════════════════════════════════════════════

func _on_slot_pressed(item_id: String) -> void:
	_select_item(item_id)


func _on_slot_focused(item_id: String) -> void:
	_select_item(item_id)


func _select_item(item_id: String) -> void:
	_selected_item_id = item_id
	_update_item_details()
	item_selected.emit(item_id)


func _update_item_details() -> void:
	if _selected_item_id == "":
		detail_name.text         = "Select an item"
		detail_type.text         = ""
		detail_description.text  = ""
		detail_icon.texture      = null
		assign_hint.text         = "Select an item and press W/A/S/D to assign"
		assign_hint.add_theme_color_override("font_color", C_TEXT_MID)
		return
	
	var inv := get_node_or_null("/root/InventoryManager")
	if inv == null:
		return
	
	var data: ItemData = inv.get_item_data(_selected_item_id)
	if data == null:
		detail_name.text        = _selected_item_id
		detail_type.text        = ""
		detail_description.text = "No details available."
		detail_icon.texture     = null
		return
	
	detail_name.text = data.item_name
	detail_name.add_theme_color_override("font_color", data.get_rarity_color())
	
	var type_text := ""
	match data.item_type:
		ItemData.ItemType.WEAPON:     type_text = "Weapon"
		ItemData.ItemType.CONSUMABLE: type_text = "Consumable"
		ItemData.ItemType.EQUIPMENT:   type_text = "Relic"
		ItemData.ItemType.MATERIAL:   type_text = "Material"
		ItemData.ItemType.KEY_ITEM:   type_text = "Key Item"
	detail_type.text = type_text.to_upper()
	
	detail_description.text = data.description
	detail_icon.texture     = data.icon
	
	if data.usable:
		assign_hint.text = "Press W / A / S / D to assign"
		assign_hint.add_theme_color_override("font_color", Color(C_AMBER, 0.75))
	else:
		assign_hint.text = "Cannot be assigned"
		assign_hint.add_theme_color_override("font_color", C_TEXT_MUTED)


# ═══════════════════════════════════════════════════════════════
#  HOTBAR
# ═══════════════════════════════════════════════════════════════

func _update_hotbar_display() -> void:
	var inv := get_node_or_null("/root/InventoryManager")
	if inv == null:
		return
	
	for i in range(hotbar_slots.size()):
		var slot := hotbar_slots[i]
		var icon: TextureRect = null
		for child in slot.get_children():
			if child is CenterContainer:
				for sub in child.get_children():
					if sub is TextureRect:
						icon = sub
						break
		
		var item_id: String = inv.get_hotbar_item(i)
		var data: ItemData  = inv.get_item_data(item_id) if item_id != "" else null
		
		if icon:
			icon.texture = data.icon if data else null
		
		var has_item := data != null
		var rarity: Color = data.get_rarity_color() if has_item else C_BORDER_OUT
		_apply_slot_style(slot, has_item, rarity)


# ═══════════════════════════════════════════════════════════════
#  INPUT + SIGNALS
# ═══════════════════════════════════════════════════════════════

func _connect_signals() -> void:
	var inv := get_node_or_null("/root/InventoryManager")
	if inv:
		inv.inventory_changed.connect(_on_inventory_changed)
		inv.hotbar_changed.connect(_on_hotbar_changed)


func _input(event: InputEvent) -> void:
	if not visible or _selected_item_id == "":
		return
	
	var inv := get_node_or_null("/root/InventoryManager")
	if inv == null:
		return
	
	if event is InputEventKey and event.pressed and not event.echo:
		var assigned := false
		match event.keycode:
			KEY_W:
				inv.assign_to_hotbar(0, _selected_item_id, true); assigned = true
			KEY_A:
				inv.assign_to_hotbar(1, _selected_item_id, true); assigned = true
			KEY_S:
				inv.assign_to_hotbar(2, _selected_item_id, true); assigned = true
			KEY_D:
				inv.assign_to_hotbar(3, _selected_item_id, true); assigned = true
		if assigned:
			get_viewport().set_input_as_handled()


func _on_inventory_changed() -> void:
	_update_inventory_grid()


func _on_hotbar_changed(_slot: int, _id: String) -> void:
	_update_hotbar_display()


# ═══════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════

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

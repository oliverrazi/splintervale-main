extends CanvasLayer

@onready var left_panel: PanelContainer = $MainContainer/LeftPanel
@onready var right_panel: PanelContainer = $MainContainer/RightPanel
@onready var bottom_panel: PanelContainer = $MainContainer/BottomPanel

# References - Main Bars
@onready var hp_bar: ProgressBar = $MainContainer/LeftPanel/Control/StatsContainer/HPBar
@onready var hp_label: Label = $MainContainer/LeftPanel/Control/StatsContainer/HPBar/Label
@onready var resonance_bar: ProgressBar = $MainContainer/LeftPanel/Control/StatsContainer/ResonanceBar
@onready var resonance_label: Label = $MainContainer/LeftPanel/Control/StatsContainer/ResonanceBar/Label
@onready var exp_bar: ProgressBar = $MainContainer/LeftPanel/Control/StatsContainer/HBoxContainer/Control2/EXPBar
@onready var exp_label: Label = $MainContainer/LeftPanel/Control/StatsContainer/HBoxContainer/Control2/EXPBar/Label
@onready var lvl_label: Label = $MainContainer/LeftPanel/Control/StatsContainer/HBoxContainer/PanelContainer/Control/LvlLabel
@onready var gold_label: Label = $MainContainer/RightPanel/GoldContainer/GoldAmount

# Delay Bars (weiße Nachzieh-Balken)
var hp_delay_bar: ProgressBar = null
var resonance_delay_bar: ProgressBar = null

@onready var action_slots: Array[PanelContainer] = [
	$MainContainer/LeftPanel/Control/MarginContainer/ActionSlots/HBoxContainer/Slot1,
	$MainContainer/LeftPanel/Control/MarginContainer/ActionSlots/HBoxContainer2/Slot2,
	$MainContainer/LeftPanel/Control/MarginContainer/ActionSlots/HBoxContainer3/Slot4,
	$MainContainer/LeftPanel/Control/MarginContainer/ActionSlots/HBoxContainer2/Slot3
]

# Delay Bar Settings
@export_group("Delay Bar")
@export var delay_bar_color: Color = Color(0.5, 0.5, 0.5, 0.6)  # Weiß
@export var delay_bar_wait: float = 0.3    # Wartezeit bevor Delay-Bar schrumpft
@export var delay_bar_speed: float = 0.5   # Dauer des Schrumpfens

# Stats
var max_hp: int = 100
var current_hp: int = 100
var max_resonance: int = 30
var current_resonance: int = 30
var max_exp: int = 100
var current_exp: int = 0
var gold: int = 0
var level: int = 1

# Delay Bar State
var _hp_delay_tween: Tween = null
var _resonance_delay_tween: Tween = null

var _hotbar_icons: Array[TextureRect] = []

var _interact_icon: Texture2D = null
var _cached_slot_0_texture: Texture2D = null


func _process(_delta: float) -> void:
	_update_slot_w_interaction_state()
	_update_resonance_display()


func _update_resonance_display() -> void:
	# Live-Update der Resonance (wegen Regeneration)
	if GameManager == null or GameManager.player_data == null:
		return
	
	var pd: PlayerData = GameManager.player_data
	var new_resonance: int = int(pd.current_resonance)
	
	# Nur updaten wenn sich was geändert hat
	if new_resonance != current_resonance or pd.max_resonance != max_resonance:
		var old_resonance: int = current_resonance
		
		# Delay Bar nur bei VERLUST triggern, bei Regeneration mitziehen
		if new_resonance < old_resonance:
			# Verlust -> Delay Bar Animation starten
			_trigger_resonance_delay_bar(old_resonance, new_resonance)
		elif new_resonance > old_resonance and resonance_delay_bar:
			# Regeneration -> Delay Bar sofort mitziehen
			resonance_delay_bar.value = new_resonance
		
		update_resonance(new_resonance, pd.max_resonance)


func _update_slot_w_interaction_state() -> void:
	if action_slots.is_empty() or _hotbar_icons.is_empty():
		return
	
	if _hotbar_icons.size() == 0:
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
	
	if can_interact:
		if _cached_slot_0_texture == null and icon.texture != _interact_icon:
			_cached_slot_0_texture = icon.texture
		
		if _interact_icon:
			icon.texture = _interact_icon
	else:
		if _cached_slot_0_texture != null:
			icon.texture = _cached_slot_0_texture
		else:
			_update_hotbar_slot(0)


func _ready() -> void:
	add_to_group("hud")
	
	var icon_path: String = "res://assets/icons/talk_icon.png"
	if ResourceLoader.exists(icon_path):
		_interact_icon = load(icon_path)
		print("Interact icon loaded: ", icon_path)
	else:
		print("Interact icon NOT found at: ", icon_path)
	
	# Delay Bars erstellen
	call_deferred("_setup_delay_bars")
	
	# Styles anwenden
	call_deferred("_apply_resonance_bar_style")
	
	call_deferred("_connect_to_player_data")
	call_deferred("_connect_to_inventory")
	
	if LoadingScreen:
		LoadingScreen.loading_finished.connect(_on_loading_finished)


func _setup_delay_bars() -> void:
	"""Erstellt die weißen Delay-Balken hinter den Hauptbalken"""
	# HP Delay Bar
	#if hp_bar:
		#hp_delay_bar = _create_delay_bar_for(hp_bar)
	
	# Resonance Delay Bar
	if resonance_bar:
		resonance_delay_bar = _create_delay_bar_for(resonance_bar)


func _create_delay_bar_for(main_bar: ProgressBar) -> ProgressBar:
	"""Erstellt einen Delay-Balken als Child des Hauptbalkens (dahinter)"""
	var delay_bar := ProgressBar.new()
	delay_bar.name = "DelayBar"
	
	# Werte synchronisieren
	delay_bar.min_value = main_bar.min_value
	delay_bar.max_value = main_bar.max_value
	delay_bar.value = main_bar.value
	delay_bar.show_percentage = false
	
	# WICHTIG: Hinter dem Parent rendern
	delay_bar.show_behind_parent = true
	
	# Vollständig ausfüllen (gleiche Größe wie Parent)
	delay_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	delay_bar.offset_left = 1
	delay_bar.offset_top = 1
	delay_bar.offset_right = 1
	delay_bar.offset_bottom = 1
	
	# Style: Weiß/Halbtransparent
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent
	delay_bar.add_theme_stylebox_override("background", bg_style)
	
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = delay_bar_color
	fill_style.corner_radius_top_left = 8
	fill_style.corner_radius_top_right = 8
	fill_style.corner_radius_bottom_left = 8
	fill_style.corner_radius_bottom_right = 8
	delay_bar.add_theme_stylebox_override("fill", fill_style)
	
	# Als Child des Hauptbalkens hinzufügen
	main_bar.add_child(delay_bar)
	
	return delay_bar


func _trigger_hp_delay_bar(old_value: int, new_value: int) -> void:
	"""Startet die Delay-Bar Animation für HP"""
	if hp_delay_bar == null:
		return
	
	# Alten Tween abbrechen
	if _hp_delay_tween and _hp_delay_tween.is_valid():
		_hp_delay_tween.kill()
	
	# Delay Bar auf alten Wert setzen
	hp_delay_bar.max_value = max_hp
	hp_delay_bar.value = old_value
	
	# Tween: Warten, dann schrumpfen
	_hp_delay_tween = create_tween()
	_hp_delay_tween.tween_interval(delay_bar_wait)
	_hp_delay_tween.tween_property(hp_delay_bar, "value", new_value, delay_bar_speed).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _trigger_resonance_delay_bar(old_value: int, new_value: int) -> void:
	"""Startet die Delay-Bar Animation für Resonance"""
	if resonance_delay_bar == null:
		return
	
	# Alten Tween abbrechen
	if _resonance_delay_tween and _resonance_delay_tween.is_valid():
		_resonance_delay_tween.kill()
	
	# Delay Bar auf alten Wert setzen
	resonance_delay_bar.max_value = max_resonance
	resonance_delay_bar.value = old_value
	
	# Tween: Warten, dann schrumpfen
	_resonance_delay_tween = create_tween()
	_resonance_delay_tween.tween_interval(delay_bar_wait)
	_resonance_delay_tween.tween_property(resonance_delay_bar, "value", new_value, delay_bar_speed).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _on_loading_finished() -> void:
	_reconnect_to_player_data()
	_connect_to_inventory()


func _connect_to_player_data() -> void:
	await get_tree().process_frame
	
	if GameManager == null:
		push_error("GameManager not found!")
		return
	
	if GameManager.player_data == null:
		push_error("PlayerData not initialized!")
		return
	
	var pd: PlayerData = GameManager.player_data
	
	if not pd.hp_changed.is_connected(_on_hp_changed):
		pd.hp_changed.connect(_on_hp_changed)
	if not pd.resonance_changed.is_connected(_on_resonance_changed):
		pd.resonance_changed.connect(_on_resonance_changed)
	if not pd.exp_changed.is_connected(_on_exp_changed):
		pd.exp_changed.connect(_on_exp_changed)
	if not pd.level_changed.is_connected(_on_level_changed):
		pd.level_changed.connect(_on_level_changed)
	if not pd.gold_changed.is_connected(_on_gold_changed):
		pd.gold_changed.connect(_on_gold_changed)
	
	_update_all_displays()


func _reconnect_to_player_data() -> void:
	await get_tree().process_frame
	
	if GameManager == null or GameManager.player_data == null:
		return
	
	var pd: PlayerData = GameManager.player_data
	
	if not pd.hp_changed.is_connected(_on_hp_changed):
		pd.hp_changed.connect(_on_hp_changed)
	if not pd.resonance_changed.is_connected(_on_resonance_changed):
		pd.resonance_changed.connect(_on_resonance_changed)
	if not pd.exp_changed.is_connected(_on_exp_changed):
		pd.exp_changed.connect(_on_exp_changed)
	if not pd.level_changed.is_connected(_on_level_changed):
		pd.level_changed.connect(_on_level_changed)
	if not pd.gold_changed.is_connected(_on_gold_changed):
		pd.gold_changed.connect(_on_gold_changed)
	
	_update_all_displays()


func _update_all_displays() -> void:
	if GameManager == null or GameManager.player_data == null:
		return
	
	var pd: PlayerData = GameManager.player_data
	update_hp(pd.current_hp, pd.max_hp)
	update_resonance(int(pd.current_resonance), pd.max_resonance)
	update_exp(pd.current_exp, pd.exp_to_next_level)
	set_level(pd.level)
	update_gold(pd.gold)
	
	# Delay Bars synchronisieren
	if hp_delay_bar:
		hp_delay_bar.max_value = pd.max_hp
		hp_delay_bar.value = pd.current_hp
	if resonance_delay_bar:
		resonance_delay_bar.max_value = pd.max_resonance
		resonance_delay_bar.value = int(pd.current_resonance)


func _apply_panel_styles() -> void:
	var glass_style := _create_glass_panel_style()
	
	if left_panel:
		left_panel.add_theme_stylebox_override("panel", glass_style)
	if right_panel:
		right_panel.add_theme_stylebox_override("panel", glass_style.duplicate())
	if bottom_panel:
		bottom_panel.add_theme_stylebox_override("panel", glass_style.duplicate())


func _apply_bar_styles() -> void:
	if hp_bar:
		hp_bar.add_theme_stylebox_override("background", _create_hp_bar_bg_style())
		hp_bar.add_theme_stylebox_override("fill", _create_hp_bar_fill_style())
	
	if exp_bar:
		exp_bar.add_theme_stylebox_override("background", _create_exp_bar_bg_style())
		exp_bar.add_theme_stylebox_override("fill", _create_exp_bar_fill_style())
	

func _apply_slot_styles() -> void:
	var slot_style := _create_slot_style()
	for slot in action_slots:
		if slot:
			slot.add_theme_stylebox_override("panel", slot_style.duplicate())


func _create_glass_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.9, 0.9, 0.9, 0.35)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_color = Color(0.9, 0.9, 0.9, 0.35)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	style.shadow_size = 6
	style.shadow_offset = Vector2(2, 3)
	return style


func _create_hp_bar_bg_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.05, 0.05, 0.9)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_color = Color(0.9, 0.3, 0.3, 0.4)
	return style


func _create_hp_bar_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.65, 0.15, 0.15, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _create_exp_bar_bg_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.15, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_color = Color(0.3, 0.5, 0.9, 0.4)
	return style


func _create_exp_bar_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.45, 0.9, 1.0)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _create_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.01, 0.01, 0.4)
	style.corner_radius_top_left = 50
	style.corner_radius_top_right = 50
	style.corner_radius_bottom_left = 50
	style.corner_radius_bottom_right = 50
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(0.6, 0.5, 0.3, 0.6)
	return style


func update_hp(current: int, maximum: int) -> void:
	current_hp = current
	max_hp = maximum
	
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current
	
	if hp_label:
		hp_label.text = "%d / %d" % [current, maximum]


func update_resonance(current: int, maximum: int) -> void:
	current_resonance = current
	max_resonance = maximum
	
	if resonance_bar:
		resonance_bar.max_value = maximum
		resonance_bar.value = current
	
	if resonance_label:
		resonance_label.text = "%d / %d" % [current, maximum]


func update_exp(current: int, maximum: int) -> void:
	current_exp = current
	max_exp = maximum

	if exp_bar:
		exp_bar.max_value = maximum
		exp_bar.value = current
	
	if exp_label:
		exp_label.text = "Lv.%d  %d / %d" % [level, current, maximum]


func update_gold(amount: int) -> void:
	gold = amount
	
	if gold_label:
		gold_label.text = "%d" % amount


func set_level(new_level: int) -> void:
	level = new_level
	if lvl_label:
		lvl_label.text = "%d" % level
	update_exp(current_exp, max_exp)


func animate_hp_change(new_hp: int) -> void:
	if not hp_bar:
		return
	
	var old_hp: int = current_hp
	
	hp_bar.max_value = max_hp
	
	var tween := create_tween()
	tween.tween_method(func(val: float): 
		hp_bar.value = val
		if hp_label:
			hp_label.text = "%d / %d" % [int(val), max_hp]
	, float(hp_bar.value), float(new_hp), 0.3)
	
	current_hp = new_hp
	
	# Delay Bar Verhalten
	if hp_delay_bar:
		if new_hp < old_hp:
			# Schaden -> Delay Bar Animation starten
			_trigger_hp_delay_bar(old_hp, new_hp)
		else:
			# Heilung -> Delay Bar sofort mitziehen
			hp_delay_bar.value = new_hp


func animate_resonance_change(new_resonance: int) -> void:
	if not resonance_bar:
		return
	
	resonance_bar.max_value = max_resonance
	
	var tween := create_tween()
	tween.tween_method(func(val: float):
		resonance_bar.value = val
		if resonance_label:
			resonance_label.text = "%d / %d" % [int(val), max_resonance]
	, float(current_resonance), float(new_resonance), 0.2)
	current_resonance = new_resonance


func animate_exp_change(new_exp: int) -> void:
	if not exp_bar:
		return
	
	exp_bar.max_value = max_exp
	
	var tween := create_tween()
	tween.tween_method(func(val: float):
		exp_bar.value = val
	, float(current_exp), float(new_exp), 0.5)
	current_exp = new_exp


func animate_gold_change(new_gold: int) -> void:
	if not gold_label:
		return
	
	var tween := create_tween()
	tween.tween_method(func(val: float):
		gold_label.text = "%d" % int(val)
	, float(gold), float(new_gold), 0.3)
	gold = new_gold


func _on_hp_changed(current: int, maximum: int) -> void:
	max_hp = maximum
	
	if hp_bar:
		hp_bar.max_value = maximum 
	animate_hp_change(current)


func _on_resonance_changed(current: int, maximum: int) -> void:
	max_resonance = maximum
	
	if resonance_bar:
		resonance_bar.max_value = maximum
	
	# Delay Bar Verhalten
	if resonance_delay_bar:
		if current < current_resonance:
			# Verlust -> Delay Bar Animation
			_trigger_resonance_delay_bar(current_resonance, current)
		else:
			# Regeneration/Wiederherstellung -> Delay Bar mitziehen
			resonance_delay_bar.value = current
	
	update_resonance(current, maximum)


func _on_exp_changed(current: int, needed: int) -> void:
	max_exp = needed
	
	if exp_bar:
		exp_bar.max_value = max_exp 
	animate_exp_change(current)


func _on_level_changed(new_level: int) -> void:
	set_level(new_level)


func _on_gold_changed(amount: int) -> void:
	animate_gold_change(amount)


func _connect_to_inventory() -> void:
	await get_tree().process_frame
	
	_hotbar_icons.clear()
	for slot in action_slots:
		if slot:
			var icon: TextureRect = _find_icon_in_slot(slot)
			_hotbar_icons.append(icon)
	
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager:
		if not inv_manager.hotbar_changed.is_connected(_on_hotbar_changed):
			inv_manager.hotbar_changed.connect(_on_hotbar_changed)
		
		_update_all_hotbar_slots()


func _find_icon_in_slot(slot: PanelContainer) -> TextureRect:
	var control: Control = slot.get_node_or_null("Control")
	if control:
		var icon: TextureRect = control.get_node_or_null("Icon") as TextureRect
		if icon:
			return icon
	
	return _find_texture_rect_recursive(slot)


func _find_texture_rect_recursive(node: Node) -> TextureRect:
	for child in node.get_children():
		if child is TextureRect:
			return child as TextureRect
		var found: TextureRect = _find_texture_rect_recursive(child)
		if found:
			return found
	return null


func _update_all_hotbar_slots() -> void:
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		return
	
	for i in range(_hotbar_icons.size()):
		_update_hotbar_slot(i)


func _update_hotbar_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _hotbar_icons.size():
		return
	
	var icon: TextureRect = _hotbar_icons[slot_index]
	if icon == null:
		return
	
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		return
	
	var item_id: String = inv_manager.get_hotbar_item(slot_index)
	var item_data: ItemData = inv_manager.get_item_data(item_id) if item_id != "" else null
	
	if item_data and item_data.icon:
		icon.texture = item_data.icon
		icon.visible = true
	else:
		icon.texture = null


func _on_hotbar_changed(slot_index: int, _item_id: String) -> void:
	_update_hotbar_slot(slot_index)
	
	if slot_index == 0:
		var inv_manager: Node = get_node_or_null("/root/InventoryManager")
		if inv_manager:
			var item_id: String = inv_manager.get_hotbar_item(0)
			var item_data: ItemData = inv_manager.get_item_data(item_id) if item_id != "" else null
			if item_data and item_data.icon:
				_cached_slot_0_texture = item_data.icon
			else:
				_cached_slot_0_texture = null

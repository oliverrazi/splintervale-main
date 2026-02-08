extends CanvasLayer

enum Tab { STATS, INVENTORY, MAP, QUESTS, SETTINGS }
enum FocusLevel { TABS, CONTENT }

@export var select_sound_path: String = "res://menu/assets/sounds/select.wav"
@export var confirm_sound_path: String = "res://menu/assets/sounds/confirm.wav"

var _current_tab: Tab = Tab.STATS
var _focus_level: FocusLevel = FocusLevel.TABS
var _is_open: bool = false
var _initial_focus_done: bool = false

var _map_ui: MapUI = null
var _quests_ui: QuestsUI = null
var _inventory_ui: InventoryUI = null

# Node References
var tab_map: Button
var tab_stats: Button
var tab_inventory: Button
var tab_quests: Button
var tab_settings: Button

var content_panel: PanelContainer
var map_content: Control
var stats_content: Control
var inventory_content: Control
var quests_content: Control
var settings_content: Control

var background: ColorRect

# Navigation
var tab_buttons: Array[Button] = []
var settings_buttons: Array[Button] = []
var select_sound: AudioStreamPlayer
var confirm_sound: AudioStreamPlayer
var _last_focused_button: Button = null
var _block_select_sound: bool = false


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_find_nodes()
	_setup_map_content()
	_setup_quests_content()
	_setup_inventory_content()
	_setup_sounds()
	_connect_tabs()
	_apply_styles()
	_setup_settings_buttons()
	_setup_tab_navigation()
	_switch_tab(Tab.STATS)
	
	load_font()
	apply_to_all_labels(self)
	
	# Direkt auf Viewport Input hören
	set_process_input(false)
	set_process_unhandled_input(true)


func _setup_sounds() -> void:
	select_sound = AudioStreamPlayer.new()
	select_sound.bus = "UI"
	if ResourceLoader.exists(select_sound_path):
		select_sound.stream = load(select_sound_path)
	add_child(select_sound)
	
	confirm_sound = AudioStreamPlayer.new()
	confirm_sound.bus = "UI"
	if ResourceLoader.exists(confirm_sound_path):
		confirm_sound.stream = load(confirm_sound_path)
	add_child(confirm_sound)


func _setup_tab_navigation() -> void:
	# Tab Buttons Array aufbauen
	tab_buttons = []
	if tab_stats: tab_buttons.append(tab_stats)
	if tab_inventory: tab_buttons.append(tab_inventory)
	if tab_map: tab_buttons.append(tab_map)
	if tab_quests: tab_buttons.append(tab_quests)
	if tab_settings: tab_buttons.append(tab_settings)
	
	# Horizontale Navigation für Tabs
	for i in range(tab_buttons.size()):
		var button = tab_buttons[i]
		
		button.focus_entered.connect(_on_button_focused.bind(button))
		
		# Vorheriger Tab (nach links)
		var prev_index = i - 1 if i > 0 else tab_buttons.size() - 1
		button.focus_neighbor_left = tab_buttons[prev_index].get_path()
		
		# Nächster Tab (nach rechts)
		var next_index = i + 1 if i < tab_buttons.size() - 1 else 0
		button.focus_neighbor_right = tab_buttons[next_index].get_path()
		
		# Oben/Unten bleiben auf sich selbst (Content wird mit Enter betreten)
		button.focus_neighbor_top = button.get_path()
		button.focus_neighbor_bottom = button.get_path()


func _setup_settings_buttons() -> void:
	if settings_content == null:
		return
	
	var save_btn: Button = _find_node_recursive(settings_content, "SaveButton") as Button
	var load_btn: Button = _find_node_recursive(settings_content, "LoadButton") as Button
	var quit_btn: Button = _find_node_recursive(settings_content, "QuitButton") as Button
	
	settings_buttons = []
	if save_btn: settings_buttons.append(save_btn)
	if load_btn: settings_buttons.append(load_btn)
	if quit_btn: settings_buttons.append(quit_btn)
	
	# Vertikale Navigation für Settings-Buttons
	for i in range(settings_buttons.size()):
		var button = settings_buttons[i]
		
		button.focus_entered.connect(_on_button_focused.bind(button))
		
		# Vertikal
		var prev_index = i - 1 if i > 0 else settings_buttons.size() - 1
		button.focus_neighbor_top = settings_buttons[prev_index].get_path()
		
		var next_index = i + 1 if i < settings_buttons.size() - 1 else 0
		button.focus_neighbor_bottom = settings_buttons[next_index].get_path()
		
		# Links/Rechts auf sich selbst
		button.focus_neighbor_left = button.get_path()
		button.focus_neighbor_right = button.get_path()
	
	# Button-Callbacks
	if save_btn:
		save_btn.pressed.connect(func(): _play_confirm_sound(); _on_save_pressed())
	if load_btn:
		load_btn.pressed.connect(func(): _play_confirm_sound(); _on_load_pressed())
	if quit_btn:
		quit_btn.pressed.connect(func(): _play_confirm_sound(); _on_quit_pressed())


func _on_button_focused(button: Button) -> void:
	if not _initial_focus_done:
		_last_focused_button = button
		return
	
	# Nicht abspielen wenn nach Confirm blockiert
	if _block_select_sound:
		_last_focused_button = button
		return
	
	# Nur Sound wenn sich der Fokus tatsächlich geändert hat
	if button != _last_focused_button:
		if select_sound and select_sound.stream:
			select_sound.play()
		_last_focused_button = button


func _play_confirm_sound() -> void:
	if confirm_sound and confirm_sound.stream:
		_block_select_sound = true
		confirm_sound.play()
		# Nach kurzer Zeit wieder erlauben
		get_tree().create_timer(0.15).timeout.connect(func(): _block_select_sound = false)


var _font: FontFile
var font_color: Color = Color(255, 234, 213)


func load_font() -> void:
	var font_path: String = "res://menu/assets/fonts/Merriweather-Regular.ttf"
	if ResourceLoader.exists(font_path):
		_font = load(font_path)


func apply_to_all_labels(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			apply_label_style(child)
		elif child is RichTextLabel:
			apply_richtext_style(child)
		
		if child.get_child_count() > 0:
			apply_to_all_labels(child)


func apply_label_style(label: Label) -> void:
	if _font:
		label.add_theme_font_override("font", _font)
	label.add_theme_color_override("font_color", font_color)


func apply_richtext_style(label: RichTextLabel) -> void:
	if _font:
		label.add_theme_font_override("normal_font", _font)
	label.add_theme_color_override("default_color", font_color)


func _find_nodes() -> void:
	background = get_node_or_null("Background")
	
	if background == null:
		push_error("Background not found!")
		return
	
	tab_stats = _find_node_recursive(background, "TabStats") as Button
	tab_inventory = _find_node_recursive(background, "TabInventory") as Button
	tab_map = _find_node_recursive(background, "TabMap") as Button
	tab_quests = _find_node_recursive(background, "TabQuests") as Button
	tab_settings = _find_node_recursive(background, "TabSettings") as Button
	
	content_panel = _find_node_recursive(background, "ContentPanel") as PanelContainer
	map_content = _find_node_recursive(background, "MapContent") as Control
	stats_content = _find_node_recursive(background, "StatsContent") as Control
	inventory_content = _find_node_recursive(background, "InventoryContent") as Control
	quests_content = _find_node_recursive(background, "QuestsContent") as Control
	settings_content = _find_node_recursive(background, "SettingsContent") as Control


func _setup_quests_content() -> void:
	if quests_content == null:
		return
	
	# Vorhandene Kinder entfernen
	for child in quests_content.get_children():
		child.queue_free()
	
	await get_tree().process_frame
	
	# QuestsUI erstellen
	_quests_ui = QuestsUI.new()
	_quests_ui.name = "QuestsUI"
	_quests_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	quests_content.add_child(_quests_ui)
	
	print("QuestsUI initialized")

func _setup_map_content() -> void:
	if map_content == null:
		return
	
	# Vorhandene Kinder entfernen
	for child in map_content.get_children():
		child.queue_free()
	
	# Einen Frame warten bis Children entfernt sind
	await get_tree().process_frame
	
	# MapUI erstellen
	_map_ui = MapUI.new()
	_map_ui.name = "MapUI"
	
	# === WICHTIG: Pfad zur Karten-Textur ===
	_map_ui.map_texture_path = "res://assets/map/world_map.png"
	
	# === WICHTIG: Welt-Grenzen (aus deinen MapCaptureCamera Settings) ===
	# Map Center: X=-25, Z=150 | Map Size: 220x220
	# Also: center ± (size/2)
	_map_ui.world_x_min = -305.0  # -25 - 110
	_map_ui.world_x_max = 235.0    # -25 + 110
	_map_ui.world_z_min = 210.0    # 150 + 110
	_map_ui.world_z_max = -55.0   # 150 - 110
	
	# Optional: Custom Player Icon
	# _map_ui.player_icon_path = "res://assets/ui/map_player_icon.png"
	
	map_content.add_child(_map_ui)
	print("MapUI initialized")
	
func _setup_inventory_content() -> void:
	if inventory_content == null:
		return
	
	for child in inventory_content.get_children():
		child.queue_free()
	
	await get_tree().process_frame
	
	_inventory_ui = InventoryUI.new()
	_inventory_ui.name = "InventoryUI"
	_inventory_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	inventory_content.add_child(_inventory_ui)
	
	print("InventoryUI initialized")

func _find_node_recursive(parent: Node, node_name: String) -> Node:
	var found := parent.find_child(node_name, true, false)
	if found:
		return found
	return null


func _connect_tabs() -> void:
	# Tabs wechseln den Tab UND betreten den Content
	if tab_stats:
		tab_stats.pressed.connect(func(): _play_confirm_sound(); _switch_tab(Tab.STATS); _enter_content())
	if tab_inventory:
		tab_inventory.pressed.connect(func(): _play_confirm_sound(); _switch_tab(Tab.INVENTORY); _enter_content())
	if tab_map:
		tab_map.pressed.connect(func(): _play_confirm_sound(); _switch_tab(Tab.MAP); _enter_content())
	if tab_quests:
		tab_quests.pressed.connect(func(): _play_confirm_sound(); _switch_tab(Tab.QUESTS); _enter_content())
	if tab_settings:
		tab_settings.pressed.connect(func(): _play_confirm_sound(); _switch_tab(Tab.SETTINGS); _enter_content())



func _unhandled_input(event: InputEvent) -> void:
	# === ESC / Cancel ===
	if event.is_action_pressed("ui_cancel", false):  # false = kein echo
		# Dialog Check
		var dialogue_manager: Node = get_node_or_null("/root/DialogueManager")
		if dialogue_manager:
			if dialogue_manager.is_dialogue_active() or dialogue_manager.is_on_cooldown():
				return
		
		if _is_open:
			if _focus_level == FocusLevel.CONTENT:
				# Im Content: zurück zu Tabs
				_exit_content()
			else:
				# Auf Tab-Ebene: Menü schließen
				close_menu()
		else:
			open_menu()
		
		get_viewport().set_input_as_handled()
		return
	
	# === Rest nur wenn Menü offen ===
	if not _is_open:
		return
	
	# Tab-Wechsel mit Schultertasten (nur auf Tab-Ebene)
	if _focus_level == FocusLevel.TABS:
		if event.is_action_pressed("ui_focus_prev", false):
			_play_confirm_sound()
			_previous_tab()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_focus_next", false):
			_play_confirm_sound()
			_next_tab()
			get_viewport().set_input_as_handled()


func _enter_content() -> void:
	# Fokus auf erstes Element im Content setzen
	match _current_tab:
		Tab.STATS:
			var first_stat_btn: Button = _find_node_recursive(stats_content, "VitalityAdd") as Button
			if first_stat_btn and not first_stat_btn.disabled:
				_focus_level = FocusLevel.CONTENT
				first_stat_btn.grab_focus()
				print("Focus level set to CONTENT, focusing first stat button")
			else:
				print("No stat points available, staying on TABS level")
		Tab.MAP:
			if _map_ui:
				_focus_level = FocusLevel.CONTENT
				# Map hat keine fokussierbaren Elemente, aber wir sind "im Content"
				print("Entered map content")
		Tab.QUESTS:  # NEU
			if _quests_ui:
				var quest_buttons := _quests_ui.get_quest_buttons()
				if quest_buttons.size() > 0:
					_focus_level = FocusLevel.CONTENT
					_quests_ui.focus_first_quest()
				else:
					print("No quests to focus")
		Tab.INVENTORY:
			if _inventory_ui:
				var item_slots := _inventory_ui.get_item_slots()
				if item_slots.size() > 0:
					_focus_level = FocusLevel.CONTENT
					_inventory_ui.focus_first_item()
		Tab.SETTINGS:
			if settings_buttons.size() > 0:
				_focus_level = FocusLevel.CONTENT
				settings_buttons[0].grab_focus()
				print("Focus level set to CONTENT, focusing first settings button")
		_:
			# Andere Tabs haben (noch) keine fokussierbaren Elemente
			# Bleiben wir auf Tab-Ebene
			print("No focusable content, staying on TABS level")


func _exit_content() -> void:
	# Zurück zur Tab-Ebene
	_focus_level = FocusLevel.TABS
	_block_select_sound = true
	_focus_current_tab()
	_play_confirm_sound()


func open_menu() -> void:
	_is_open = true
	_initial_focus_done = false
	_focus_level = FocusLevel.TABS
	visible = true
	get_tree().paused = true
	
	if _current_tab == Tab.STATS:
		_update_stats_content()
	
	# Fokus auf aktuellen Tab setzen
	await get_tree().process_frame
	_focus_current_tab()
	await get_tree().process_frame
	_initial_focus_done = true
	
	if background:
		var tween := create_tween()
		background.modulate.a = 0.0
		tween.tween_property(background, "modulate:a", 1.0, 0.15)


func close_menu() -> void:
	_initial_focus_done = false
	if background:
		var tween := create_tween()
		tween.tween_property(background, "modulate:a", 0.0, 0.1)
		tween.tween_callback(func():
			_is_open = false
			visible = false
			get_tree().paused = false
		)
	else:
		_is_open = false
		visible = false
		get_tree().paused = false


func _focus_current_tab() -> void:
	match _current_tab:
		Tab.MAP:
			if tab_map: tab_map.grab_focus()
		Tab.STATS:
			if tab_stats: tab_stats.grab_focus()
		Tab.INVENTORY:
			if tab_inventory: tab_inventory.grab_focus()
		Tab.QUESTS:
			if tab_quests: tab_quests.grab_focus()
		Tab.SETTINGS:
			if tab_settings: tab_settings.grab_focus()


func _switch_tab(tab: Tab) -> void:
	_current_tab = tab
	
	# Alle Content Panels verstecken
	if map_content:
		map_content.visible = false
	if stats_content:
		stats_content.visible = false
	if inventory_content:
		inventory_content.visible = false
	if quests_content:
		quests_content.visible = false
	if settings_content:
		settings_content.visible = false
	
	# Alle Tab-Buttons deselektieren
	if tab_map:
		tab_map.button_pressed = false
	if tab_stats:
		tab_stats.button_pressed = false
	if tab_inventory:
		tab_inventory.button_pressed = false
	if tab_quests:
		tab_quests.button_pressed = false
	if tab_settings:
		tab_settings.button_pressed = false
	
	# Aktuellen Tab anzeigen
	match tab:
		Tab.MAP:
			if map_content:
				map_content.visible = true
			if tab_map:
				tab_map.button_pressed = true
		Tab.STATS:
			if stats_content:
				stats_content.visible = true
			if tab_stats:
				tab_stats.button_pressed = true
			_update_stats_content()
		Tab.INVENTORY:
			if inventory_content:
				inventory_content.visible = true
			if tab_inventory:
				tab_inventory.button_pressed = true
			if _inventory_ui:
				_inventory_ui.refresh()
		Tab.QUESTS:
			if quests_content:
				quests_content.visible = true
			if tab_quests:
				tab_quests.button_pressed = true
			if _quests_ui:
				_quests_ui.refresh() 
		Tab.SETTINGS:
			if settings_content:
				settings_content.visible = true
			if tab_settings:
				tab_settings.button_pressed = true


func _next_tab() -> void:
	var next := (_current_tab + 1) % Tab.size()
	_switch_tab(next as Tab)
	_focus_current_tab()


func _previous_tab() -> void:
	var prev := (_current_tab - 1)
	if prev < 0:
		prev = Tab.size() - 1
	_switch_tab(prev as Tab)
	_focus_current_tab()


# ============ CONTENT UPDATES ============

var _stats_buttons_connected: bool = false

func _update_stats_content() -> void:
	if stats_content == null:
		return
	
	if GameManager == null or GameManager.player_data == null:
		return
	
	var pd: PlayerData = GameManager.player_data
	
	# === Linke Spalte: Ressourcen ===
	var level_label: Label = _find_node_recursive(stats_content, "LevelValue") as Label
	var exp_label: Label = _find_node_recursive(stats_content, "ExpValue") as Label
	var hp_label: Label = _find_node_recursive(stats_content, "HPValue") as Label
	var resonance_label: Label = _find_node_recursive(stats_content, "ResonanceValue") as Label
	var gold_label: Label = _find_node_recursive(stats_content, "GoldValue") as Label
	
	if level_label:
		level_label.text = str(pd.level)
	if exp_label:
		exp_label.text = "%d / %d" % [pd.current_exp, pd.exp_to_next_level]
	if hp_label:
		hp_label.text = "%d / %d" % [pd.current_hp, pd.max_hp]
	if resonance_label:
		resonance_label.text = "%d / %d" % [pd.current_resonance, pd.max_resonance]
	if gold_label:
		gold_label.text = str(pd.gold)
	
	# === Mittlere Spalte: Attribute ===
	var stat_points_label: Label = _find_node_recursive(stats_content, "StatPointsValue") as Label
	var vitality_label: Label = _find_node_recursive(stats_content, "VitalityValue") as Label
	var strength_label: Label = _find_node_recursive(stats_content, "StrengthValue") as Label
	var attunement_label: Label = _find_node_recursive(stats_content, "AttunementValue") as Label
	var attack_speed_label: Label = _find_node_recursive(stats_content, "AttackSpeedValue") as Label
	
	if stat_points_label:
		stat_points_label.text = str(pd.stat_points)
	if vitality_label:
		vitality_label.text = str(pd.base_vitality)
	if strength_label:
		strength_label.text = str(pd.base_strength)
	if attunement_label:
		attunement_label.text = str(pd.base_attunement)
	if attack_speed_label:
		attack_speed_label.text = str(pd.base_attack_speed)
	
	# === Rechte Spalte: Skills ===
	var skill_points_label: Label = _find_node_recursive(stats_content, "SkillPointsValue") as Label
	if skill_points_label:
		skill_points_label.text = str(pd.skill_points)
	
	# === Buttons verbinden (nur einmal) ===
	if not _stats_buttons_connected:
		_connect_stat_buttons()
	
	# === Buttons aktivieren/deaktivieren basierend auf verfügbaren Punkten ===
	_update_stat_buttons_state()


func _connect_stat_buttons() -> void:
	var vitality_btn: Button = _find_node_recursive(stats_content, "VitalityAdd") as Button
	var strength_btn: Button = _find_node_recursive(stats_content, "StrengthAdd") as Button
	var attunement_btn: Button = _find_node_recursive(stats_content, "AttunementAdd") as Button
	var attack_speed_btn: Button = _find_node_recursive(stats_content, "AttackSpeedAdd") as Button
	
	var stat_buttons: Array[Button] = []
	if vitality_btn: stat_buttons.append(vitality_btn)
	if strength_btn: stat_buttons.append(strength_btn)
	if attunement_btn: stat_buttons.append(attunement_btn)
	if attack_speed_btn: stat_buttons.append(attack_speed_btn)
	
	# Vertikale Navigation einrichten
	for i in range(stat_buttons.size()):
		var button = stat_buttons[i]
		
		# Callbacks
		button.focus_entered.connect(_on_button_focused.bind(button))
		
		# Navigation
		var prev_index = i - 1 if i > 0 else stat_buttons.size() - 1
		var next_index = i + 1 if i < stat_buttons.size() - 1 else 0
		
		button.focus_neighbor_top = stat_buttons[prev_index].get_path()
		button.focus_neighbor_bottom = stat_buttons[next_index].get_path()
		button.focus_neighbor_left = button.get_path()
		button.focus_neighbor_right = button.get_path()
	
	# Button-spezifische Callbacks
	if vitality_btn:
		vitality_btn.pressed.connect(_on_vitality_add)
	if strength_btn:
		strength_btn.pressed.connect(_on_strength_add)
	if attunement_btn:
		attunement_btn.pressed.connect(_on_attunement_add)
	if attack_speed_btn:
		attack_speed_btn.pressed.connect(_on_attack_speed_add)
	
	_stats_buttons_connected = true


func _update_stat_buttons_state() -> void:
	var has_points: bool = GameManager.player_data.stat_points > 0
	
	var vitality_btn: Button = _find_node_recursive(stats_content, "VitalityAdd") as Button
	var strength_btn: Button = _find_node_recursive(stats_content, "StrengthAdd") as Button
	var attunement_btn: Button = _find_node_recursive(stats_content, "AttunementAdd") as Button
	var attack_speed_btn: Button = _find_node_recursive(stats_content, "AttackSpeedAdd") as Button
	
	if vitality_btn:
		vitality_btn.disabled = not has_points
	if strength_btn:
		strength_btn.disabled = not has_points
	if attunement_btn:
		attunement_btn.disabled = not has_points
	if attack_speed_btn:
		attack_speed_btn.disabled = not has_points


func _on_vitality_add() -> void:
	_play_confirm_sound()
	if GameManager.player_data.spend_stat_point_vitality():
		_update_stats_content()


func _on_strength_add() -> void:
	_play_confirm_sound()
	if GameManager.player_data.spend_stat_point_strength():
		_update_stats_content()


func _on_attunement_add() -> void:
	_play_confirm_sound()
	if GameManager.player_data.spend_stat_point_attunement():
		_update_stats_content()


func _on_attack_speed_add() -> void:
	_play_confirm_sound()
	if GameManager.player_data.spend_stat_point_attack_speed():
		_update_stats_content()


# ============ STYLES ============

func _apply_styles() -> void:
	if background:
		background.color = Color(0, 0, 0, 0)
		UIUtils.add_background_blur(background, 3.0)


# ============ SETTINGS ACTIONS ============

func _on_save_pressed() -> void:
	GameManager.save_game()
	
	if _map_ui:
		_map_ui.save_fog_data()
	
	_show_notification("Game Saved!")


func _on_load_pressed() -> void:
	if not GameManager.has_save_file():
		_show_notification("No save file found!")
		return
	
	_is_open = false
	visible = false
	get_tree().paused = false
	
	if await GameManager.load_game():
		print("Load successful!")
	else:
		_is_open = true
		visible = true
		get_tree().paused = true
		_show_notification("Load Failed!")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _show_notification(text: String) -> void:
	if settings_content == null:
		return
	
	var notif_label: Label = _find_node_recursive(settings_content, "NotificationLabel") as Label
	if notif_label:
		notif_label.text = text
		notif_label.visible = true
		notif_label.modulate.a = 1.0
		
		var tween := create_tween()
		tween.tween_interval(2.0)
		tween.tween_property(notif_label, "modulate:a", 0.0, 0.5)
		tween.tween_callback(func():
			notif_label.visible = false
			notif_label.modulate.a = 1.0
		)
		

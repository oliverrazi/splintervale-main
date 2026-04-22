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
var _settings_ui: SettingsUI = null

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

# ── FARB-PALETTE ───────────────────────────────────────────────
const C_BG_TOME    := Color("1e1810", 0.9)        # Haupt-Panel
const C_BG_TABBAR  := Color("18130c", 0.9)        # Tab-Leiste
const C_BG_DEEP    := Color("14100a")        # tiefstes Dunkel (Skill-Slots, Bars)
const C_BORDER     := Color("2e1f0e")        # interne Trennlinien
const C_BORDER_OUT := Color("5c3d1e")        # äußerer Rahmen
const C_AMBER      := Color("c4923a")        # Hauptakzent
const C_AMBER_DIM  := Color("c4923a", 0.20)
const C_AMBER_FAINT:= Color("c4923a", 0.06)
const C_TEXT_LIGHT := Color("d4b880")        # Werte / helle Texte
const C_TEXT_MID   := Color("8a7050")        # Labels (italic)
const C_TEXT_TAB   := Color("6b5030")        # inaktive Tab-Labels
const C_HP_BAR     := Color("5a8e4a")
const C_RES_BAR    := Color("3a5a8e")
 


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50 
	
	_find_nodes()
	_setup_map_content()
	_setup_quests_content()
	_setup_inventory_content()
	_setup_settings_content()

	_setup_sounds()
	_connect_tabs()
	_setup_tab_navigation()  # ← ERST navigation (füllt tab_buttons)
	_apply_styles()           # ← DANN styles (nutzt tab_buttons)
	_switch_tab(Tab.STATS)
	
	load_font()
	apply_to_all_labels(self)
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


func _setup_settings_content() -> void:
	if settings_content == null:
		return
	
	# Alte Children entfernen
	for child in settings_content.get_children():
		child.queue_free()
	
	await get_tree().process_frame
	
	_settings_ui = SettingsUI.new()
	_settings_ui.name = "SettingsUI"
	_settings_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_content.add_child(_settings_ui)
	
	_settings_ui.save_requested.connect(_on_save_pressed)
	_settings_ui.load_requested.connect(_on_load_pressed)
	_settings_ui.quit_requested.connect(_on_quit_pressed)
	
	print("SettingsUI initialized")

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
var font_color: Color = Color("d4b880")


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
	if _font and not label.has_theme_font_override("font"):
		label.add_theme_font_override("font", _font)
	if not label.has_theme_color_override("font_color"):
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
		
		if _is_open and _current_tab == Tab.SETTINGS and _settings_ui:
			if _settings_ui.handle_back():
				get_viewport().set_input_as_handled()
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
				_map_ui.focus_player()
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
			if _settings_ui:
				_focus_level = FocusLevel.CONTENT
				_settings_ui.focus_first()
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
			if _map_ui:
				_map_ui.refresh() 
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
				
	for btn in tab_buttons:
		_update_tab_glow(btn)


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
	
	_refine_stats_layout()
	
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
		
	_ensure_resource_bars()
	_update_resource_bar("EXPProgressBar",       pd.current_exp,       pd.exp_to_next_level)
	_update_resource_bar("HPProgressBar",        pd.current_hp,        pd.max_hp)
	_update_resource_bar("ResonanceProgressBar", pd.current_resonance, pd.max_resonance)
	
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
		
	var stat_badge = _find_node_recursive(stats_content, "StatPointsBadgeValue") as Label
	if stat_badge:
		stat_badge.text = str(pd.stat_points)
	var skill_badge = _find_node_recursive(stats_content, "SkillPointsBadgeValue") as Label
	if skill_badge:
		skill_badge.text = str(pd.skill_points)
	
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
	
	for btn in stat_buttons:
		_style_add_button(btn)
	
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
		# Getönter Hintergrund: dunkles Braun mit leichter Transparenz für den Blur
		background.color = Color("1e1810", 0.74)
		UIUtils.add_background_blur(background, 3.0)
		
	var main: Control = _find_node_recursive(background, "MainContainer") as Control
	if main:
		main.set_anchors_preset(Control.PRESET_FULL_RECT)
		main.offset_left   = 48
		main.offset_top    = 48
		main.offset_right  = -48
		main.offset_bottom = -48
	
	_style_tab_bar()
	_style_tab_buttons()
	_setup_tab_glows()
	_style_content_panel()
	# _style_outer_frame()       ← weglassen
	# _style_column_separators() ← weglassen (machen wir später sauber)
	# _add_corner_ornaments()    ← weglassen (war die Ursache!)


func _setup_outer_margin() -> void:
	var main: Control = _find_node_recursive(background, "MainContainer") as Control
	if main == null:
		return
	var parent := main.get_parent()
	if parent == null or parent.name == "_OuterMargin":
		return   # bereits gewrappt
	
	var wrap := MarginContainer.new()
	wrap.name = "_OuterMargin"
	wrap.add_theme_constant_override("margin_left",   48)
	wrap.add_theme_constant_override("margin_right",  48)
	wrap.add_theme_constant_override("margin_top",    32)
	wrap.add_theme_constant_override("margin_bottom", 32)
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var idx := main.get_index()
	parent.remove_child(main)
	wrap.add_child(main)
	parent.add_child(wrap)
	parent.move_child(wrap, idx)

# ============ SETTINGS ACTIONS ============

func _on_save_pressed() -> void:
	GameManager.save_game()
	if _map_ui:
		_map_ui.save_fog_data()
	if _settings_ui:
		_settings_ui.show_toast("Game saved")


func _on_load_pressed() -> void:
	if not GameManager.has_save_file():
		if _settings_ui:
			_settings_ui.show_toast("No save file found", true)
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
		if _settings_ui:
			_settings_ui.show_toast("Load failed", true)


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
		

# ── ÄUSSERER RAHMEN ────────────────────────────────────────────
func _style_outer_frame() -> void:
	var frame: Control = _find_node_recursive(background, "MainContainer") as Control
	if frame == null:
		return

	if frame is PanelContainer:
		var sb := StyleBoxFlat.new()
		sb.bg_color     = C_BG_TOME
		sb.border_color = C_BORDER_OUT
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		frame.add_theme_stylebox_override("panel", sb)
	# Falls VBoxContainer/MarginContainer: Hintergrund über ColorRect
	else:
		var bg := ColorRect.new()
		bg.color        = C_BG_TOME
		bg.z_index      = -1
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.add_child(bg)
		frame.move_child(bg, 0)
 
 
# ── TAB-LEISTE ─────────────────────────────────────────────────
func _style_tab_bar() -> void:
	var bar: Control = _find_node_recursive(background, "TabBarPanel") as Control
	if bar == null:
		return
	bar.theme = null
	
	var sb := StyleBoxFlat.new()
	sb.bg_color           = C_BG_TABBAR
	sb.border_color       = C_BORDER_OUT
	sb.set_border_width_all(1)
	# Explizit: kein Innenabstand, damit Buttons bündig zum Rahmen sitzen
	sb.content_margin_left   = 0
	sb.content_margin_right  = 0
	sb.content_margin_top    = 0
	sb.content_margin_bottom = 0
	sb.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("panel", sb)
	
	for child in bar.get_children():
		if child is HBoxContainer:
			(child as HBoxContainer).add_theme_constant_override("separation", 0)
			break
 
 
# ── TAB-BUTTONS ────────────────────────────────────────────────
func _style_tab_buttons() -> void:
	for i in range(tab_buttons.size()):
		var btn: Button = tab_buttons[i]
		var is_last: bool = (i == tab_buttons.size() - 1)
		
		_apply_tab_stylebox(btn, is_last)
		_rebuild_tab_layout(btn)
		
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size   = Vector2(0, 120)   # deutlich höher





# ── TAB-LAYOUT UMBAU (Icon oben, Text unten) ──────────────────
func _rebuild_tab_layout(btn: Button) -> void:
	# Idempotent: Wenn schon umgebaut, skip
	if btn.find_child("_TabContent", false, false) != null:
		return
	
	# Icon + Text aus dem Button extrahieren und "leeren"
	var tex: Texture2D = btn.icon
	var txt: String    = btn.text
	btn.icon = null
	btn.text = ""
	
	# Container: vertikal, zentriert
	var vbox := VBoxContainer.new()
	vbox.name          = "_TabContent"
	vbox.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment     = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	
	# Icon
	if tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture            = tex
		icon_rect.mouse_filter       = Control.MOUSE_FILTER_IGNORE
		icon_rect.stretch_mode       = TextureRect.STRETCH_KEEP_CENTERED
		icon_rect.texture_filter     = CanvasItem.TEXTURE_FILTER_NEAREST  # Pixel-Art scharf
		icon_rect.custom_minimum_size = Vector2(44, 44)
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon_rect)
	
	# Label
	var lbl := Label.new()
	lbl.name                 = "_TabLabel"
	lbl.text                 = txt
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", C_TEXT_TAB)
	if _font:
		lbl.add_theme_font_override("font", _font)
	vbox.add_child(lbl)
	
	btn.add_child(vbox)
 
 
func _apply_tab_stylebox(btn: Button, is_last: bool) -> void:
	var right_border: int = 0 if is_last else 1
	
	var normal := StyleBoxFlat.new()
	normal.bg_color           = C_BG_TABBAR
	normal.border_color       = C_BORDER
	normal.border_width_right = right_border
	normal.set_corner_radius_all(0)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color           = Color("c4923a", 0.05)
	hover.border_color       = C_BORDER
	hover.border_width_right = right_border
	hover.set_corner_radius_all(0)
	
	# Pressed (aktiver Tab): deutlich heller, KEINE Extra-Border
	var pressed := StyleBoxFlat.new()
	pressed.bg_color           = Color("c4923a", 0.13)
	pressed.border_color       = C_BORDER
	pressed.border_width_right = right_border
	pressed.set_corner_radius_all(0)
	
	# Klick / Focus: noch etwas heller
	var focus := StyleBoxFlat.new()
	focus.bg_color           = Color("c4923a", 0.20)
	focus.border_color       = C_BORDER
	focus.border_width_right = right_border
	focus.set_corner_radius_all(0)
	
	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed)
	btn.add_theme_stylebox_override("focus",    focus)
	btn.add_theme_stylebox_override("disabled", normal)
 
 
# ── CONTENT PANEL ──────────────────────────────────────────────
func _style_content_panel() -> void:
	if content_panel == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color            = C_BG_TOME
	sb.border_color        = C_BORDER_OUT
	sb.border_width_left   = 1
	sb.border_width_right  = 1
	sb.border_width_bottom = 1
	# content_margin explizit setzen damit keine unerwünschten Offsets entstehen
	sb.content_margin_left   = 0
	sb.content_margin_right  = 0
	sb.content_margin_top    = 0
	sb.content_margin_bottom = 0
	sb.set_corner_radius_all(0)
	content_panel.add_theme_stylebox_override("panel", sb)
 
 
# ── SPALTEN-TRENNER ────────────────────────────────────────────
# Falls deine Spalten HSeparator/VSeparator-Nodes haben, stile sie hier.
# Sonst werden die Abstände über Padding geregelt (kein Action needed).
func _style_column_separators() -> void:
	var seps: Array = []
	_collect_nodes_by_type(content_panel, "VSeparator", seps)
	for sep in seps:
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_BORDER
		(sep as VSeparator).add_theme_stylebox_override("separator", sb)
		(sep as VSeparator).add_theme_constant_override("separation", 1)
 
 
func _setup_tab_glows() -> void:
	for btn: Button in tab_buttons:
		# Alten Glow entfernen falls vorhanden (bei Re-Init)
		var old = btn.find_child("_ActiveGlow", false, false)
		if old:
			old.queue_free()
		
		var glow := TextureRect.new()
		glow.name          = "_ActiveGlow"
		glow.texture       = _build_line_gradient(C_AMBER)
		glow.mouse_filter  = Control.MOUSE_FILTER_IGNORE
		glow.stretch_mode  = TextureRect.STRETCH_SCALE
		glow.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
		
		# GANZ UNTEN am Button, nur 2px hoch — sitzt direkt auf
		# der Trennlinie zwischen TabBar und ContentPanel
		glow.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		glow.offset_top    = -2
		glow.offset_bottom = 0
		glow.z_index       = 10
		glow.modulate.a    = 0.0
		
		btn.add_child(glow)
		
		# Signal nur einmal verbinden
		if not btn.toggled.is_connected(_on_tab_toggled):
			btn.toggled.connect(_on_tab_toggled.bind(btn))
		
		_update_tab_glow(btn)

func _on_tab_toggled(_pressed: bool, btn: Button) -> void:
	_update_tab_glow(btn)


func _update_tab_glow(btn: Button) -> void:
	var glow: TextureRect = btn.find_child("_ActiveGlow", false, false) as TextureRect
	if glow:
		var target_a: float = 1.0 if btn.button_pressed else 0.0
		var tween := create_tween()
		tween.tween_property(glow, "modulate:a", target_a, 0.15)
	
	var lbl: Label = btn.find_child("_TabLabel", false, false) as Label
	if lbl:
		var target_color: Color = C_AMBER if btn.button_pressed else C_TEXT_TAB
		lbl.add_theme_color_override("font_color", target_color)


func _build_line_gradient(color: Color) -> ImageTexture:
	var w := 256
	var h := 2
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for x in range(w):
		var t: float = float(x) / float(w - 1)
		var factor: float = 1.0 - abs(t * 2.0 - 1.0)
		factor = pow(factor, 1.2)
		for y in range(h):
			img.set_pixel(x, y, Color(color.r, color.g, color.b, factor))
	return ImageTexture.create_from_image(img)

func _collect_nodes_by_type(parent: Node, type_name: String, result: Array) -> void:
	for child in parent.get_children():
		if child.get_class() == type_name:
			result.append(child)
		if child.get_child_count() > 0:
			_collect_nodes_by_type(child, type_name, result)
 
 
# ── ECKEN-ORNAMENTE + NIETEN ───────────────────────────────────
func _add_corner_ornaments() -> void:
	var target: Control = _find_node_recursive(background, "MenuPanel") as Control
	if target == null:
		target = _find_node_recursive(background, "MainPanel") as Control
	if target == null:
		target = content_panel
	if target == null:
		return
 
	_make_corner_lines(target, true,  true)
	_make_corner_lines(target, true,  false)
	_make_corner_lines(target, false, true)
	_make_corner_lines(target, false, false)
	_make_rivet(target, true,  true)
	_make_rivet(target, true,  false)
	_make_rivet(target, false, true)
	_make_rivet(target, false, false)
 
 
func _make_corner_lines(parent: Control, top: bool, left: bool) -> void:
	const SZ   := 16
	const ALFA := 0.45
 
	var h := ColorRect.new()
	h.color        = Color(C_AMBER, ALFA)
	h.size         = Vector2(SZ, 1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.z_index      = 10
 
	var v := ColorRect.new()
	v.color        = Color(C_AMBER, ALFA)
	v.size         = Vector2(1, SZ)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.z_index      = 10
 
	parent.add_child(h)
	parent.add_child(v)
 
	await get_tree().process_frame
 
	var pw := parent.size.x
	var ph := parent.size.y
	h.position = Vector2(0 if left else pw - SZ,   0 if top else ph - 1)
	v.position = Vector2(0 if left else pw - 1,    0 if top else ph - SZ)
 
 
func _make_rivet(parent: Control, top: bool, left: bool) -> void:
	# Kleiner runder Nagel in den Ecken
	var dot := ColorRect.new()
	dot.color        = Color("5c3d1e")
	dot.size         = Vector2(5, 5)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.z_index      = 11
	parent.add_child(dot)
 
	await get_tree().process_frame
	var pw := parent.size.x
	var ph := parent.size.y
	dot.position = Vector2(
		5 if left  else pw - 10,
		5 if top   else ph - 10
	)
 
 
# ── SECTION-HEADER ─────────────────────────────────────────────
# Aufruf: var header = _make_section_header(my_vbox, "Resources")
# Gibt den HBoxContainer zurück (für Layout-Anpassungen).
func _make_section_header(parent: Control, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
 
	var line_l := _make_separator_line(true)
	var diamond_l := _make_diamond()
	var lbl := _make_header_label(title)
	var diamond_r := _make_diamond()
	var line_r := _make_separator_line(false)
 
	row.add_child(line_l)
	row.add_child(diamond_l)
	row.add_child(lbl)
	row.add_child(diamond_r)
	row.add_child(line_r)
 
	parent.add_child(row)
	return row
 
 
func _make_separator_line(expand_left: bool) -> Control:
	var c := ColorRect.new()
	c.color = C_BORDER_OUT
	c.custom_minimum_size = Vector2(8, 1)
	c.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c
 
 
func _make_diamond() -> Control:
	# 4×4 Raute als rotiertes ColorRect-Wrapper
	# (ColorRect kann nicht rotiert werden → kleines Panel mit Label-Trick)
	# Einfachere Alternative: TextureRect mit 1×1 Pixel-Textur, oder Label
	var lbl := Label.new()
	lbl.text = "◆"
	lbl.add_theme_font_size_override("font_size", 6)
	lbl.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return lbl
 
 
func _make_header_label(title: String) -> Label:
	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.add_theme_color_override("font_color", Color(C_AMBER, 0.70))
	lbl.add_theme_font_size_override("font_size", 8)
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return lbl
 
 
# ── POINTS BADGE ───────────────────────────────────────────────
# Aufruf: var badge = _make_points_badge(my_vbox, "Available Points", 0)
# Zum Aktualisieren: (badge.find_child("BadgeValue") as Label).text = str(n)
func _make_points_badge(parent: Control, key: String, value: int) -> PanelContainer:
	var panel := PanelContainer.new()
 
	var sb := StyleBoxFlat.new()
	sb.bg_color     = C_AMBER_FAINT
	sb.border_color = C_AMBER_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_top    = 4
	sb.content_margin_bottom = 4
	sb.content_margin_left   = 10
	sb.content_margin_right  = 10
	panel.add_theme_stylebox_override("panel", sb)
 
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
 
	var key_lbl := Label.new()
	key_lbl.text = key.to_upper()
	key_lbl.add_theme_font_size_override("font_size", 8)
	key_lbl.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	if _font:
		key_lbl.add_theme_font_override("font", _font)
	key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 
	var val_lbl := Label.new()
	val_lbl.name = "BadgeValue"
	val_lbl.text = str(value)
	val_lbl.add_theme_font_size_override("font_size", 15)
	val_lbl.add_theme_color_override("font_color", C_AMBER)
	if _font:
		val_lbl.add_theme_font_override("font", _font)
 
	hbox.add_child(key_lbl)
	hbox.add_child(val_lbl)
	panel.add_child(hbox)
	parent.add_child(panel)
	return panel
 
 
# ── STAT-ROW STYLING ───────────────────────────────────────────
# Stile alle Label-Paare (Name + Wert) in einer Zeile.
# Aufruf einmalig nach dem Aufbau von stats_content.
func _style_stat_labels() -> void:
	if stats_content == null:
		return
 
	# Label-Namen der linken Spalte (Bezeichner)
	var label_names := [
		"LevelLabel",   "ExpLabel",  "HPLabel",
		"ResonanceLabel", "GoldLabel",
		"VitalityLabel", "StrengthLabel",
		"AttunementLabel", "AttackSpeedLabel"
	]
	for n in label_names:
		var lbl: Label = _find_node_recursive(stats_content, n) as Label
		if lbl:
			lbl.add_theme_color_override("font_color", C_TEXT_MID)
			lbl.add_theme_font_size_override("font_size", 12)
			if _font:
				lbl.add_theme_font_override("font", _font)
 
	# Label-Namen der rechten Spalte (Werte)
	var value_names := [
		"LevelValue",  "ExpValue",   "HPValue",
		"ResonanceValue", "GoldValue",
		"VitalityValue", "StrengthValue",
		"AttunementValue", "AttackSpeedValue",
		"StatPointsValue", "SkillPointsValue"
	]
	for n in value_names:
		var lbl: Label = _find_node_recursive(stats_content, n) as Label
		if lbl:
			lbl.add_theme_color_override("font_color", C_TEXT_LIGHT)
			lbl.add_theme_font_size_override("font_size", 12)
			if _font:
				lbl.add_theme_font_override("font", _font)
 
	# Gold und Level bekommen den Amber-Akzent
	for accent_name in ["LevelValue", "GoldValue"]:
		var lbl: Label = _find_node_recursive(stats_content, accent_name) as Label
		if lbl:
			lbl.add_theme_color_override("font_color", C_AMBER)
 
 
# ── HP/RESONANCE PROGRESSBARS ──────────────────────────────────
# In _update_stats_content() aufrufen nachdem Labels gesetzt wurden:
#
#   _ensure_resource_bars()
#   _update_resource_bar("HPProgressBar",        pd.current_hp,        pd.max_hp)
#   _update_resource_bar("ResonanceProgressBar", pd.current_resonance, pd.max_resonance)
 
func _ensure_resource_bars() -> void:
	_ensure_bar_after_label(stats_content, "EXPProgressBar",       C_AMBER,   "ExpValue")
	_ensure_bar_after_label(stats_content, "HPProgressBar",        C_HP_BAR,  "HPValue")
	_ensure_bar_after_label(stats_content, "ResonanceProgressBar", C_RES_BAR, "ResonanceValue")
 
func _update_resource_bar(bar_name: String, current: float, maximum: float) -> void:
	var bar: ProgressBar = _find_node_recursive(stats_content, bar_name) as ProgressBar
	if bar:
		bar.max_value = maximum
		bar.value     = current
 
 
func _ensure_bar_after_label(parent: Control, bar_name: String,
							  fill_color: Color, anchor_name: String) -> void:
	if _find_node_recursive(parent, bar_name) != null:
		return
	
	var anchor: Label = _find_node_recursive(parent, anchor_name) as Label
	if anchor == null:
		return
	
	# Value-Label ist in einer Row (z.B. HPRow), die wiederum in einer Column
	var row: Control = anchor.get_parent() as Control
	if row == null:
		return
	var column: Control = row.get_parent() as Control
	if column == null:
		return
	
	var bar := ProgressBar.new()
	bar.name                = bar_name
	bar.show_percentage     = false
	bar.custom_minimum_size = Vector2(0, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = C_BG_DEEP
	bg_sb.border_color = C_BORDER
	bg_sb.set_border_width_all(1)
	bg_sb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg_sb)
	
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = fill_color
	fill_sb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill_sb)
	
	column.add_child(bar)
	column.move_child(bar, row.get_index() + 1)
 
 
# ── ADD-BUTTONS (+ Stat-Punkte) ────────────────────────────────
# In _connect_stat_buttons() vor _stats_buttons_connected = true:
#
#   for btn in stat_buttons:
#       _style_add_button(btn)
 
func _style_add_button(btn: Button) -> void:
	# Feste Größe, damit das + schön zentriert ist
	btn.custom_minimum_size = Vector2(28, 28)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color     = C_AMBER_FAINT
	normal.border_color = Color(C_AMBER, 0.45)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.content_margin_top    = 2
	normal.content_margin_bottom = 2
	normal.content_margin_left   = 4
	normal.content_margin_right  = 4
	
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color     = Color(C_AMBER, 0.22)
	hover.border_color = Color(C_AMBER, 0.80)
	
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color     = Color(C_AMBER, 0.35)
	pressed.border_color = C_AMBER
	
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color     = Color(C_AMBER, 0.04)
	disabled.border_color = Color(C_AMBER, 0.20)
	
	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus",    hover)
	
	btn.add_theme_color_override("font_color",          C_AMBER)
	btn.add_theme_color_override("font_hover_color",    C_TEXT_LIGHT)
	btn.add_theme_color_override("font_pressed_color",  C_TEXT_LIGHT)
	btn.add_theme_color_override("font_disabled_color", Color(C_AMBER, 0.35))
	btn.add_theme_font_size_override("font_size", 20)
 

 
func _style_settings_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color     = C_BG_DEEP
	normal.border_color = C_BORDER_OUT
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_top    = 8
	normal.content_margin_bottom = 8
	normal.content_margin_left   = 18
	normal.content_margin_right  = 18
 
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color     = C_AMBER_FAINT
	hover.border_color = Color(C_AMBER, 0.4)
 
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color     = Color(C_AMBER, 0.12)
	pressed.border_color = C_AMBER
 
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus",   hover)
 
	btn.add_theme_color_override("font_color",         C_TEXT_MID)
	btn.add_theme_color_override("font_hover_color",   C_AMBER)
	btn.add_theme_color_override("font_pressed_color", C_TEXT_LIGHT)
	btn.add_theme_font_size_override("font_size", 11)
	if _font:
		btn.add_theme_font_override("font", _font)
 
 
# ── TAB-ICONS: PIXEL-ART SPRITES ──────────────────────────────
# Lege deine Sprites unter res://menu/assets/icons/ ab.
# Die Funktion setzt das Icon-Texture eines Buttons und
# aktiviert pixelgenaues Rendering.
#
# Aufruf in _setup_tab_navigation() oder _ready():
#   _set_tab_icon(tab_stats,     "res://menu/assets/icons/icon_character.png")
#   _set_tab_icon(tab_inventory, "res://menu/assets/icons/icon_inventory.png")
#   _set_tab_icon(tab_map,       "res://menu/assets/icons/icon_map.png")
#   _set_tab_icon(tab_quests,    "res://menu/assets/icons/icon_quests.png")
#   _set_tab_icon(tab_settings,  "res://menu/assets/icons/icon_options.png")
 
func _set_tab_icon(btn: Button, texture_path: String) -> void:
	if btn == null or not ResourceLoader.exists(texture_path):
		return
 
	var tex: Texture2D = load(texture_path)
	btn.icon = tex
 
	# Pixel-Art: kein Filtering
	if tex is ImageTexture or tex is CompressedTexture2D:
		# Importeinstellung "Filter" muss im .import auf "Nearest" stehen —
		# das lässt sich zur Laufzeit nicht überschreiben.
		# Alternativ: Texture2D in ein ImageTexture umwandeln:
		var img: Image = tex.get_image()
		img.generate_mipmaps()   # optional, für bessere Darstellung bei Skalierung
		var img_tex := ImageTexture.create_from_image(img)
		btn.icon = img_tex
 
	# Icon-Größe und Ausrichtung
	btn.expand_icon         = false
	btn.icon_alignment      = HORIZONTAL_ALIGNMENT_CENTER
	# Vertical: Icon oben, Text darunter
	btn.alignment           = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_constant_override("icon_max_width", 32)
 
	# Inaktiv: Icon leicht gedimmt
	# (aktiver Tab hat button_pressed = true → pressed-StyleBox = heller Hintergrund)
	btn.add_theme_color_override("icon_normal_color",   Color(1, 1, 1, 0.35))
	btn.add_theme_color_override("icon_hover_color",    Color(1, 1, 1, 0.70))
	btn.add_theme_color_override("icon_pressed_color",  Color(1, 1, 1, 1.00))
	btn.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.15))
 
 
# ── SKILL SLOTS STYLEN ─────────────────────────────────────────
# Falls du die Skill-Slots per Code erzeugst, nutze diese Funktion.
# Aufruf: _style_skill_slot(my_panel)
func _style_skill_slot(slot: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color     = C_BG_DEEP
	sb.border_color = Color(C_BORDER_OUT, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	slot.add_theme_stylebox_override("panel", sb)
	
# ═══════════════════════════════════════════════════════════════
#  STATS-LAYOUT VERFEINERUNG
#  Füge diesen Block ans Ende deiner pause_menu.gd
# ═══════════════════════════════════════════════════════════════

var _stats_layout_refined: bool = false


# ── HAUPT-REFINEMENT ──────────────────────────────────────────
# Verbirgt die alten HSeparator-Zeilen, ersetzt "— Ressources —"-Labels
# durch ornamentale Section-Header, und wandelt die PointsRow in ein
# amber-getöntes Badge um. Ruft am Ende die Label-Styling-Funktion auf.
func _refine_stats_layout() -> void:
	if _stats_layout_refined or stats_content == null:
		return
	
	
	# 2. Alle HSeparator-Nodes verstecken
	_hide_all_separators(stats_content)
	
	# 3. Alte Titel-Labels durch ornamentale Headers ersetzen
	_replace_title_with_header(stats_content, "ResourcesTitle",  "Resources")
	_replace_title_with_header(stats_content, "StatsTitle",      "Attributes")
	_replace_title_with_header(stats_content, "SkillsTitle",     "Skills")
	_replace_title_with_header(stats_content, "ResourcesLabel",  "Resources")
	_replace_title_with_header(stats_content, "AttributesLabel", "Attributes")
	_replace_title_with_header(stats_content, "SkillsLabel",     "Skills")
	
	# 4. PointsRow und SkillPointsRow durch Badges ersetzen
	_replace_row_with_badge(stats_content, "PointsRow",      "Available Points",
		"StatPointsBadgeValue")
	_replace_row_with_badge(stats_content, "SkillPointsRow", "Skill Points",
		"SkillPointsBadgeValue")
	
	# 5. Stat-Row Labels styling
	_style_stat_labels()
	
	# 6. Vertikale Trenner dimmen
	_style_column_separators_dim()
	
	_stats_layout_refined = true


# ── ALLE SEPARATORS VERSTECKEN ────────────────────────────────
func _hide_all_separators(parent: Node) -> void:
	for child in parent.get_children():
		if child is HSeparator:
			child.visible = false
		if child.get_child_count() > 0:
			_hide_all_separators(child)


# ── TITEL-LABEL DURCH SECTION-HEADER ERSETZEN ─────────────────
func _replace_title_with_header(parent: Node, node_name: String, display: String) -> void:
	var title: Label = _find_node_recursive(parent, node_name) as Label
	if title == null:
		return
	
	var title_parent := title.get_parent() as Control
	if title_parent == null:
		return
	
	# Neuen Header direkt an derselben Position einfügen
	var idx := title.get_index()
	var header := _build_section_header(display)
	
	title_parent.add_child(header)
	title_parent.move_child(header, idx)
	title.visible = false


func _build_section_header(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var line_l := ColorRect.new()
	line_l.color = Color(C_BORDER_OUT, 0.7)
	line_l.custom_minimum_size = Vector2(8, 1)
	line_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_l.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	
	var diamond_l := Label.new()
	diamond_l.text = "◆"
	diamond_l.add_theme_font_size_override("font_size", 8)
	diamond_l.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	diamond_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(C_AMBER, 0.75))
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var diamond_r := Label.new()
	diamond_r.text = "◆"
	diamond_r.add_theme_font_size_override("font_size", 8)
	diamond_r.add_theme_color_override("font_color", Color(C_AMBER, 0.55))
	diamond_r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var line_r := ColorRect.new()
	line_r.color = Color(C_BORDER_OUT, 0.7)
	line_r.custom_minimum_size = Vector2(8, 1)
	line_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_r.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	
	row.add_child(line_l)
	row.add_child(diamond_l)
	row.add_child(lbl)
	row.add_child(diamond_r)
	row.add_child(line_r)
	return row


# ── POINTS-ROW DURCH BADGE ERSETZEN ────────────────────────────
func _replace_row_with_badge(parent: Node, row_name: String,
							  badge_label: String, value_node_name: String) -> void:
	var row: Control = _find_node_recursive(parent, row_name) as Control
	if row == null:
		return
	
	var row_parent := row.get_parent() as Control
	if row_parent == null:
		return
	
	var idx := row.get_index()
	var badge := _build_points_badge(badge_label, value_node_name)
	
	row_parent.add_child(badge)
	row_parent.move_child(badge, idx)
	row.visible = false


func _build_points_badge(key_text: String, value_node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var sb := StyleBoxFlat.new()
	sb.bg_color     = C_AMBER_FAINT
	sb.border_color = C_AMBER_DIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_top    = 6
	sb.content_margin_bottom = 6
	sb.content_margin_left   = 12
	sb.content_margin_right  = 12
	panel.add_theme_stylebox_override("panel", sb)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var key_lbl := Label.new()
	key_lbl.text = key_text.to_upper()
	key_lbl.add_theme_font_size_override("font_size", 10)
	key_lbl.add_theme_color_override("font_color", Color(C_AMBER, 0.65))
	if _font:
		key_lbl.add_theme_font_override("font", _font)
	key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var val_lbl := Label.new()
	val_lbl.name = value_node_name
	val_lbl.text = "0"
	val_lbl.add_theme_font_size_override("font_size", 16)
	val_lbl.add_theme_color_override("font_color", C_AMBER)
	if _font:
		val_lbl.add_theme_font_override("font", _font)
	
	hbox.add_child(key_lbl)
	hbox.add_child(val_lbl)
	panel.add_child(hbox)
	return panel


# ── VERTIKALE SPALTENTRENNER DIMMEN ───────────────────────────
func _style_column_separators_dim() -> void:
	var seps: Array = []
	_collect_nodes_by_type(stats_content, "VSeparator", seps)
	for sep in seps:
		var sb := StyleBoxLine.new()
		sb.color     = Color(C_BORDER_OUT, 0.5)
		sb.thickness = 1
		sb.vertical  = true
		(sep as VSeparator).add_theme_stylebox_override("separator", sb)

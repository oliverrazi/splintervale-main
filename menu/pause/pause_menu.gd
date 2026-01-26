extends CanvasLayer

enum Tab { MAP, STATS, INVENTORY, QUESTS, SETTINGS }

var _current_tab: Tab = Tab.STATS
var _is_open: bool = false

# Node References - werden in _ready() geholt
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


func _ready() -> void:
	# Versteckt starten
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Nodes finden
	_find_nodes()
	
	#_setup_layout()
	
	# Tab Buttons verbinden
	_connect_tabs()
	
	# Styles anwenden
	_apply_styles()
	
	# Settings Buttons verbinden
	_connect_settings_buttons()
	
	# Initial Tab
	_switch_tab(Tab.STATS)
	
	load_font()
	apply_to_all_labels(self)


var _font: FontFile
var font_color: Color = Color(255, 234, 213)
func load_font() -> void:
	var font_path: String = "res://menu/assets/fonts/Merriweather-Regular.ttf"
	_font = load(font_path)

func apply_to_all_labels(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			apply_label_style(child)
		elif child is RichTextLabel:
			apply_richtext_style(child)

		# Rekursiv weiter durchsuchen
		if child.get_child_count() > 0:
			apply_to_all_labels(child)

func apply_label_style(label: Label) -> void:
	label.add_theme_font_override("font", _font)
	label.add_theme_color_override("font_color", font_color)

func apply_richtext_style(label: RichTextLabel) -> void:
	label.add_theme_font_override("normal_font", _font)
	label.add_theme_color_override("default_color", font_color)


func _find_nodes() -> void:
	background = get_node_or_null("Background")
	
	if background == null:
		push_error("Background not found!")
		return
	
	# Versuche verschiedene mögliche Pfade
	# Passe diese an deine tatsächliche Struktur an!
	
	# Tab Buttons
	tab_map = _find_node_recursive(background, "TabMap") as Button
	tab_stats = _find_node_recursive(background, "TabStats") as Button
	tab_inventory = _find_node_recursive(background, "TabInventory") as Button
	tab_quests = _find_node_recursive(background, "TabQuests") as Button
	tab_settings = _find_node_recursive(background, "TabSettings") as Button
	
	# Content Panels
	content_panel = _find_node_recursive(background, "ContentPanel") as PanelContainer
	map_content = _find_node_recursive(background, "MapContent") as Control
	stats_content = _find_node_recursive(background, "StatsContent") as Control
	inventory_content = _find_node_recursive(background, "InventoryContent") as Control
	quests_content = _find_node_recursive(background, "QuestsContent") as Control
	settings_content = _find_node_recursive(background, "SettingsContent") as Control
	


func _find_node_recursive(parent: Node, node_name: String) -> Node:
	# Sucht rekursiv nach einem Node mit dem Namen
	var found := parent.find_child(node_name, true, false)
	if found:
		return found
	return null


func _connect_tabs() -> void:
	if tab_map:
		tab_map.pressed.connect(func(): _switch_tab(Tab.MAP))
	if tab_stats:
		tab_stats.pressed.connect(func(): _switch_tab(Tab.STATS))
	if tab_inventory:
		tab_inventory.pressed.connect(func(): _switch_tab(Tab.INVENTORY))
	if tab_quests:
		tab_quests.pressed.connect(func(): _switch_tab(Tab.QUESTS))
	if tab_settings:
		tab_settings.pressed.connect(func(): _switch_tab(Tab.SETTINGS))


func _connect_settings_buttons() -> void:
	if settings_content == null:
		return
	
	var save_btn: Button = _find_node_recursive(settings_content, "SaveButton") as Button
	var load_btn: Button = _find_node_recursive(settings_content, "LoadButton") as Button
	var quit_btn: Button = _find_node_recursive(settings_content, "QuitButton") as Button
	
	if save_btn:
		save_btn.pressed.connect(_on_save_pressed)
	if load_btn:
		load_btn.pressed.connect(_on_load_pressed)
	if quit_btn:
		quit_btn.pressed.connect(_on_quit_pressed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if _is_open:
			close_menu()
		else:
			open_menu()
	
	if _is_open:
		if event.is_action_pressed("ui_focus_prev"):
			_previous_tab()
		elif event.is_action_pressed("ui_focus_next"):
			_next_tab()


func open_menu() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
	
	if _current_tab == Tab.STATS:
		_update_stats_content()
	
	if background:
		var tween := create_tween()
		background.modulate.a = 0.0
		tween.tween_property(background, "modulate:a", 1.0, 0.15)


func close_menu() -> void:
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
		Tab.QUESTS:
			if quests_content:
				quests_content.visible = true
			if tab_quests:
				tab_quests.button_pressed = true
		Tab.SETTINGS:
			if settings_content:
				settings_content.visible = true
			if tab_settings:
				tab_settings.button_pressed = true


func _next_tab() -> void:
	var next := (_current_tab + 1) % Tab.size()
	_switch_tab(next as Tab)


func _previous_tab() -> void:
	var prev := (_current_tab - 1)
	if prev < 0:
		prev = Tab.size() - 1
	_switch_tab(prev as Tab)


# ============ CONTENT UPDATES ============

func _update_stats_content() -> void:
	if stats_content == null:
		return
	
	if GameManager == null or GameManager.player_data == null:
		return
	
	var pd := GameManager.player_data
	
	var level_label: Label = _find_node_recursive(stats_content, "LevelValue") as Label
	var hp_label: Label = _find_node_recursive(stats_content, "HPValue") as Label
	var mp_label: Label = _find_node_recursive(stats_content, "MPValue") as Label
	var exp_label: Label = _find_node_recursive(stats_content, "EXPValue") as Label
	var str_label: Label = _find_node_recursive(stats_content, "STRValue") as Label
	var def_label: Label = _find_node_recursive(stats_content, "DEFValue") as Label
	var mag_label: Label = _find_node_recursive(stats_content, "MAGValue") as Label
	var end_label: Label = _find_node_recursive(stats_content, "ENDValue") as Label
	var vit_label: Label = _find_node_recursive(stats_content, "VITValue") as Label
	
	if level_label:
		level_label.text = str(pd.level)
	if hp_label:
		hp_label.text = "%d / %d" % [pd.current_hp, pd.max_hp]
	if mp_label:
		mp_label.text = "%d / %d" % [pd.current_mp, pd.max_mp]
	if exp_label:
		exp_label.text = "%d / %d" % [pd.current_exp, pd.exp_to_next_level]
	if str_label:
		str_label.text = str(pd.base_strength)
	if def_label:
		def_label.text = str(pd.base_defense)
	if mag_label:
		mag_label.text = str(pd.base_magic)
	if end_label:
		end_label.text = str(pd.base_endurance)
	if vit_label:
		vit_label.text = str(pd.base_health)


# ============ STYLES ============

func _apply_styles() -> void:
	
	if background:
		# Hintergrund komplett transparent machen
		background.color = Color(0, 0, 0, 0)
		# Blur auf den GESAMTEN Hintergrund anwenden
		UIUtils.add_background_blur(background, 3.0)
	
	var tab_bar_panel: PanelContainer = _find_node_recursive(background, "TabBarPanel") as PanelContainer
	
	# Glass-Style für Panels (halbtransparent, kein extra Blur nötig)
	var glass_style: StyleBoxFlat = UIUtils.create_glass_style(Color(0.08, 0.1, 0.14, 0.9), 12)
	var glass_style_darker: StyleBoxFlat = UIUtils.create_glass_style(Color(0.06, 0.08, 0.12, 0.95), 12)
	
	#if content_panel:
		#content_panel.add_theme_stylebox_override("panel", glass_style)
	
	#if tab_bar_panel:
		#tab_bar_panel.add_theme_stylebox_override("panel", glass_style_darker)
	
	# Tab Buttons
	var tab_buttons := [tab_map, tab_stats, tab_inventory, tab_quests, tab_settings]
	#for btn in tab_buttons:
		#if btn:
			#_style_tab_button(btn)
	

	
func _setup_layout() -> void:
	# MainContainer sollte zentriert und groß sein
	var main_container: Control = _find_node_recursive(background, "MainContainer") as Control
	if main_container:
		main_container.set_anchors_preset(Control.PRESET_CENTER)
		main_container.custom_minimum_size = Vector2(900, 500)
		main_container.size = Vector2(900, 500)
		print("MainContainer size set to: ", main_container.size)
	
	# TabBarPanel Größe
	var tab_bar_panel: PanelContainer = _find_node_recursive(background, "TabBarPanel") as PanelContainer
	if tab_bar_panel:
		tab_bar_panel.custom_minimum_size = Vector2(200, 500)
		print("TabBarPanel min size set to: ", tab_bar_panel.custom_minimum_size)
	
	# ContentPanel soll sich ausdehnen
	if content_panel:
		content_panel.custom_minimum_size = Vector2(680, 500)
		content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		print("ContentPanel min size set to: ", content_panel.custom_minimum_size)


func _create_transparent_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# KOMPLETT TRANSPARENT - der Blur macht den Hintergrund!
	style.bg_color = Color(0, 0, 0, 0)
	
	# Runde Ecken
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	
	# Sichtbarer Border für den Glas-Effekt
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_color = Color(1.0, 1.0, 1.0, 0.3)
	
	# Content Margins
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.content_margin_left = 16
	style.content_margin_right = 16
	
	return style


func _style_tab_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	normal.border_width_left = 3
	normal.border_color = Color(0.3, 0.3, 0.35, 0.5)
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	
	var hover := normal.duplicate()
	hover.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	hover.border_color = Color(0.5, 0.45, 0.3, 0.8)
	
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.2, 0.18, 0.15, 0.95)
	pressed.border_color = Color(0.8, 0.7, 0.4, 1.0)
	pressed.border_width_left = 4
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", pressed.duplicate())
	btn.toggle_mode = true


# ============ SETTINGS ACTIONS ============

func _on_save_pressed() -> void:
	GameManager.save_game()
	_show_notification("Game Saved!")


func _on_load_pressed() -> void:
	print("Load button pressed!")
	
	if not GameManager.has_save_file():
		_show_notification("No save file found!")
		return
	
	# Menü schließen BEVOR wir laden (falls Szene wechselt)
	_is_open = false
	visible = false
	get_tree().paused = false
	
	# Laden (kann Szene wechseln)
	if await GameManager.load_game():
		print("Load successful!")
	else:
		# Falls Laden fehlschlägt, Menü wieder öffnen
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

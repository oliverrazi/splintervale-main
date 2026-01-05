extends CanvasLayer

@onready var left_panel: PanelContainer = $MainContainer/LeftPanel
@onready var right_panel: PanelContainer = $MainContainer/RightPanel
@onready var bottom_panel: PanelContainer = $MainContainer/BottomPanel

# References
@onready var hp_bar: ProgressBar = $MainContainer/LeftPanel/Control/StatsContainer/HPBar
@onready var hp_label: Label = $MainContainer/LeftPanel/Control/StatsContainer/HPBar/Label
@onready var exp_bar: ProgressBar = $MainContainer/LeftPanel/Control/StatsContainer/HBoxContainer/Control2/EXPBar
@onready var exp_label: Label = $MainContainer/LeftPanel/StatsContainer/EXPBar/Label
@onready var lvl_label: Label = $MainContainer/LeftPanel/Control/StatsContainer/HBoxContainer/PanelContainer/Control/LvlLabel
@onready var gold_label: Label = $MainContainer/RightPanel/GoldContainer/GoldAmount

@onready var action_slots: Array[PanelContainer] = [
	$MainContainer/BottomPanel/MarginContainer/ActionSlots/Slot1,
	$MainContainer/BottomPanel/MarginContainer/ActionSlots/Slot2,
	$MainContainer/BottomPanel/MarginContainer/ActionSlots/Slot3,
	$MainContainer/BottomPanel/MarginContainer/ActionSlots/Slot4
]

# Stats
var max_hp: int = 100
var current_hp: int = 100
var max_exp: int = 100
var current_exp: int = 0
var gold: int = 0
var level: int = 1




func _ready() -> void:
	
	add_to_group("hud")
	
	call_deferred("_connect_to_player_data")
	
	#_apply_panel_styles()
	#_apply_bar_styles()
	#_apply_slot_styles()

func _connect_to_player_data() -> void:
	# Sicherheitscheck
	if GameManager == null:
		push_error("GameManager not found!")
		return
	
	if GameManager.player_data == null:
		push_error("PlayerData not initialized!")
		return
	
	# Mit PlayerData Signals verbinden
	GameManager.player_data.hp_changed.connect(_on_hp_changed)
	GameManager.player_data.exp_changed.connect(_on_exp_changed)
	GameManager.player_data.level_changed.connect(_on_level_changed)
	GameManager.player_data.gold_changed.connect(_on_gold_changed)
	
	# Initiale Werte setzen
	var pd := GameManager.player_data
	update_hp(pd.current_hp, pd.max_hp)
	update_exp(pd.current_exp, pd.exp_to_next_level)
	set_level(pd.level)
	update_gold(pd.gold)
	

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
	print(slot_style)
	for slot in action_slots:
		if slot:
			slot.add_theme_stylebox_override("panel", slot_style.duplicate())

func _create_glass_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	
	# Halbtransparenter dunkler Hintergrund
	style.bg_color = Color(0.9, 0.9, 0.9, 0.35)
	
	# Runde Ecken
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	
	# Heller Rand (Glas-Effekt)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_color = Color(0.9, 0.9, 0.9, 0.35)
	
	# Subtiler Schatten
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
	style.border_color = Color(0.6, 0.5, 0.3, 0.6)  # Goldener Rand für JRPG-Style
	return style


func update_hp(current: int, maximum: int) -> void:
	current_hp = current
	max_hp = maximum
	
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current
	
	if hp_label:
		hp_label.text = "%d / %d" % [current, maximum]


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
	lvl_label.text =  "%d" % level
	update_exp(current_exp, max_exp)


# Animation für HP Änderung
func animate_hp_change(new_hp: int) -> void:
	if not hp_bar:
		return
		
	hp_bar.max_value = max_hp
	
	var tween := create_tween()
	tween.tween_method(func(val: float): 
		hp_bar.value = val
		hp_label.text = "%d / %d" % [int(val), max_hp]
	, float(hp_bar.value), float(new_hp), 0.3)
	current_hp = new_hp


# Animation für EXP Änderung
func animate_exp_change(new_exp: int) -> void:
	
	exp_bar.max_value = max_exp
	
	var tween := create_tween()
	tween.tween_method(func(val: float):
		exp_bar.value = val
		#exp_label.text = "Lv.%d  %d / %d" % [level, int(val), max_exp]
	, float(current_exp), float(new_exp), 0.5)
	current_exp = new_exp


# Animation für Gold Änderung
func animate_gold_change(new_gold: int) -> void:
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


func _on_exp_changed(current: int, needed: int) -> void:
	max_exp = needed
	
	if exp_bar:
		exp_bar.max_value = max_exp 
	animate_exp_change(current)


func _on_level_changed(new_level: int) -> void:
	set_level(new_level)
	# Optional: Level-Up Effekt anzeigen
	_show_level_up_effect()


func _on_gold_changed(amount: int) -> void:
	animate_gold_change(amount)


func _show_level_up_effect() -> void:
	# Optional: Visueller Effekt für Level Up
	print("LEVEL UP!")
	# Hier könntest du eine Animation oder Sound abspielen

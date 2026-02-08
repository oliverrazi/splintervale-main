extends CanvasLayer

signal load_pressed
signal quit_pressed

@export var select_sound_path: String = "res://menu/assets/sounds/select.wav"
@export var confirm_sound_path: String = "res://menu/assets/sounds/confirm.wav"

@onready var background: ColorRect = $ColorRect
@onready var container: VBoxContainer = $ColorRect/VBoxContainer
@onready var game_over_label: Label = $ColorRect/VBoxContainer/GameOverLabel
@onready var load_button: Button = $ColorRect/VBoxContainer/LoadButton
@onready var quit_button: Button = $ColorRect/VBoxContainer/QuitButton

var menu_buttons: Array[Button] = []
var select_sound: AudioStreamPlayer
var confirm_sound: AudioStreamPlayer
var _initial_focus_done: bool = false
var _last_focused_button: Button = null
var _block_select_sound: bool = false


func _ready() -> void:
	layer = 100
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_setup_sounds()
	_setup_buttons()
	_setup_navigation()
	
	# Buttons verbinden
	load_button.pressed.connect(_on_load_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Alles versteckt starten
	background.modulate.a = 0.0
	container.modulate.a = 0.0


func _setup_sounds() -> void:
	# Select Sound
	select_sound = AudioStreamPlayer.new()
	select_sound.bus = "UI"
	if ResourceLoader.exists(select_sound_path):
		select_sound.stream = load(select_sound_path)
	add_child(select_sound)
	
	# Confirm Sound
	confirm_sound = AudioStreamPlayer.new()
	confirm_sound.bus = "UI"
	if ResourceLoader.exists(confirm_sound_path):
		confirm_sound.stream = load(confirm_sound_path)
	add_child(confirm_sound)


func _setup_buttons() -> void:
	menu_buttons = [load_button, quit_button]
	
	for button in menu_buttons:
		button.focus_entered.connect(_on_button_focused.bind(button))
		button.pressed.connect(_play_confirm_sound)


func _setup_navigation() -> void:
	for i in range(menu_buttons.size()):
		var button = menu_buttons[i]
		
		# Vorheriger Button (nach oben)
		var prev_index = i - 1 if i > 0 else menu_buttons.size() - 1
		button.focus_neighbor_top = menu_buttons[prev_index].get_path()
		
		# Nächster Button (nach unten)
		var next_index = i + 1 if i < menu_buttons.size() - 1 else 0
		button.focus_neighbor_bottom = menu_buttons[next_index].get_path()
		
		# Links/Rechts auf sich selbst
		button.focus_neighbor_left = button.get_path()
		button.focus_neighbor_right = button.get_path()


func _on_button_focused(button: Button) -> void:
	if not _initial_focus_done:
		_last_focused_button = button
		return
	
	if _block_select_sound:
		_last_focused_button = button
		return
	
	if button != _last_focused_button:
		if select_sound and select_sound.stream:
			select_sound.play()
		_last_focused_button = button


func _play_confirm_sound() -> void:
	if confirm_sound and confirm_sound.stream:
		_block_select_sound = true
		confirm_sound.play()
		get_tree().create_timer(0.15).timeout.connect(func(): _block_select_sound = false)


func show_game_over(delay: float = 2.0) -> void:
	visible = true
	
	# Warten bevor Fade beginnt
	await get_tree().create_timer(delay).timeout
	
	# Background fade in
	var tween := create_tween()
	tween.tween_property(background, "modulate:a", 1.0, 1.0)
	
	# Warten, dann Text + Buttons einblenden
	tween.tween_interval(0.5)
	tween.tween_property(container, "modulate:a", 1.0, 0.5)
	
	# Ersten Button fokussieren nach Fade
	tween.tween_callback(func():
		load_button.grab_focus()
		await get_tree().process_frame
		_initial_focus_done = true
	)


func hide_game_over() -> void:
	_initial_focus_done = false
	var tween := create_tween()
	tween.tween_property(background, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		visible = false
		container.modulate.a = 0.0
	)


func _on_load_pressed() -> void:
	load_pressed.emit()
	hide_game_over()
	
	if GameManager.has_save_file():
		GameManager.load_game()
	else:
		# Kein Save File - Szene neu laden
		var current_scene := get_tree().current_scene.scene_file_path
		LoadingScreen.load_scene(current_scene)


func _on_quit_pressed() -> void:
	quit_pressed.emit()
	get_tree().quit()

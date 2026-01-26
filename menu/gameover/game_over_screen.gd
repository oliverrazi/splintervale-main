extends CanvasLayer

signal load_pressed
signal quit_pressed

@onready var background: ColorRect = $ColorRect
@onready var container: VBoxContainer = $ColorRect/VBoxContainer
@onready var game_over_label: Label = $ColorRect/VBoxContainer/GameOverLabel
@onready var load_button: Button = $ColorRect/VBoxContainer/LoadButton
@onready var quit_button: Button = $ColorRect/VBoxContainer/QuitButton


func _ready() -> void:
	layer = 100
	visible = false
	
	
	# Buttons verbinden
	load_button.pressed.connect(_on_load_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Alles versteckt starten
	background.modulate.a = 0.0
	container.modulate.a = 0.0


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


func hide_game_over() -> void:
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

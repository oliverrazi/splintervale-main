extends CanvasLayer

## Autoload für Szenen-Übergänge mit Fade-Effekt und Sound
## Füge als Autoload hinzu: Project Settings > Autoload > Name: "SceneTransition"

@export var fade_duration: float = 0.5
@export var start_sound_path: String = "res://menu/assets/sounds/start.wav"

var fade_overlay: ColorRect
var start_sound: AudioStreamPlayer
var _is_transitioning: bool = false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_setup_overlay()
	_setup_sound()


func _setup_overlay() -> void:
	fade_overlay = ColorRect.new()
	fade_overlay.name = "FadeOverlay"
	fade_overlay.color = Color.BLACK
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_overlay)
	
	# Vollbild - manuell setzen
	fade_overlay.anchor_left = 0.0
	fade_overlay.anchor_top = 0.0
	fade_overlay.anchor_right = 1.0
	fade_overlay.anchor_bottom = 1.0
	fade_overlay.offset_left = 0.0
	fade_overlay.offset_top = 0.0
	fade_overlay.offset_right = 0.0
	fade_overlay.offset_bottom = 0.0
	
	# Startet unsichtbar
	fade_overlay.modulate.a = 0.0


func _setup_sound() -> void:
	start_sound = AudioStreamPlayer.new()
	start_sound.bus = "UI"
	if ResourceLoader.exists(start_sound_path):
		start_sound.stream = load(start_sound_path)
	add_child(start_sound)


func fade_in(duration: float = -1.0) -> void:
	if duration < 0:
		duration = fade_duration
	
	var tween := create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 0.0, duration)


func fade_out(duration: float = -1.0) -> Signal:
	if duration < 0:
		duration = fade_duration
	
	var tween := create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 1.0, duration)
	return tween.finished


## Übergang zu einer Szene mit Fade und optionalem Sound
func transition_to(scene_path: String, play_sound: bool = true) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	
	# Sound abspielen
	if play_sound and start_sound and start_sound.stream:
		start_sound.play()
	
	# Fade Out
	await fade_out()
	
	# Szene wechseln
	get_tree().change_scene_to_file(scene_path)
	
	# Warten bis Szene geladen
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Fade In
	fade_in()
	
	_is_transitioning = false


## Übergang zum Spiel (zeigt HUD, optional lädt Save)
func transition_to_game(scene_path: String, load_save: bool = false) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	
	# Sound abspielen
	if start_sound and start_sound.stream:
		start_sound.play()
	
	# Fade Out
	await fade_out()
	
	# Save laden falls gewünscht
	if load_save and has_node("/root/GameManager"):
		await get_node("/root/GameManager").load_game()
	
	# HUD anzeigen
	if has_node("/root/Hud"):
		get_node("/root/Hud").show()
	
	# Szene wechseln
	get_tree().change_scene_to_file(scene_path)
	
	# Warten bis Szene geladen
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Fade In
	fade_in()
	
	_is_transitioning = false


## Setzt Overlay sofort auf Schwarz
func set_black() -> void:
	fade_overlay.modulate.a = 1.0


## Setzt Overlay sofort auf transparent
func set_clear() -> void:
	fade_overlay.modulate.a = 0.0


## Prüft ob gerade ein Übergang läuft
func is_transitioning() -> bool:
	return _is_transitioning

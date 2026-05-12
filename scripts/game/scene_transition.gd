extends CanvasLayer

## Autoload für Szenen-Übergänge mit Fade-Effekt und Sound
## Füge als Autoload hinzu: Project Settings > Autoload > Name: "SceneTransition"

@export var fade_duration: float = 0.5
@export var start_sound_path: String = "res://menu/assets/sounds/start.wav"

var fade_overlay: ColorRect
var start_sound: AudioStreamPlayer
var _is_transitioning: bool = false


signal scene_transition_completed

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
	
	scene_transition_completed.emit()


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
	
	scene_transition_completed.emit()


## Setzt Overlay sofort auf Schwarz
func set_black() -> void:
	fade_overlay.modulate.a = 1.0


## Setzt Overlay sofort auf transparent
func set_clear() -> void:
	fade_overlay.modulate.a = 0.0


## Prüft ob gerade ein Übergang läuft
func is_transitioning() -> bool:
	return _is_transitioning
	
	
func transition_to_with_spawn(scene_path: String, spawn_point_id: String, play_sound: bool = false) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	if play_sound and start_sound and start_sound.stream:
		start_sound.play()

	await fade_out()

	# Spawn-ID an GlobalCaveData übergeben — PlayerManager liest das
	if has_node("/root/GlobalCaveData"):
		get_node("/root/GlobalCaveData").pending_spawn_id = spawn_point_id

	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame

	fade_in()
	_is_transitioning = false
	
	scene_transition_completed.emit()


func _position_player_at_spawn(spawn_id: String) -> void:
	if spawn_id.is_empty():
		return

	# Player über PlayerManager holen
	var player: Node3D = null
	if has_node("/root/PlayerManager"):
		player = get_node("/root/PlayerManager").player_instance

	# Player SOFORT verstecken bevor er sichtbar wird
	if player:
		player.visible = false
		# Physics deaktivieren damit er nicht kurz mit dem Boden kollidiert
		if player is CharacterBody3D:
			player.set_physics_process(false)

	# Warten bis PlayerManager den Player in die neue Szene eingefügt hat
	await get_tree().process_frame
	await get_tree().process_frame

	var scene := get_tree().current_scene
	if not scene:
		return

	var spawn := scene.find_child(spawn_id, true, false)
	if not spawn or not spawn is Node3D:
		push_warning("SceneTransition: Spawn-Point '%s' nicht gefunden" % spawn_id)
		if player:
			player.visible = true
			if player is CharacterBody3D:
				player.set_physics_process(true)
		return

	# Fallback falls PlayerManager nicht da ist
	if not player:
		player = scene.find_child("Player", true, false)
		if player:
			player.visible = false
			if player is CharacterBody3D:
				player.set_physics_process(false)

	if player:
		# Position + optional Rotation übernehmen
		player.global_position = (spawn as Node3D).global_position
		if spawn is Node3D:
			player.global_rotation.y = (spawn as Node3D).global_rotation.y

		# Velocity auf null (falls CharacterBody3D)
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO

		# Ein Frame warten damit der Transform "settled" ist
		await get_tree().process_frame

		# Wieder sichtbar machen + Physik an
		player.visible = true
		if player is CharacterBody3D:
			player.set_physics_process(true)

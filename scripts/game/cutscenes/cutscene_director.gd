extends Node3D
class_name CutsceneDirector3D
## Intro-Choreografie (HD-2D: 3D-Welt, 2D-Sprites). Variante A:
## eigene Szene IntroCutscene.tscn, die am Ende in die Spielszene wechselt.
##
## Ablauf:
##   nur Nebel -> Nebel lichtet sich -> Player geht vor -> Greif sichtbar
##   -> Stop -> Dialog -> Aufladen (Licht+Sound) -> Blitz -> Schwarz
##   -> Wechsel zur Spielszene.
##
## Nutzt eure Player-API: set_cinematic_mode(), cinematic_face(),
## cinematic_walk_to() (Snippet), cinematic_set_dark() (Snippet, optional).

@export_group("Szenenwechsel")
## Pfad zur Spielszene, die NACH dem Intro geladen wird.
@export_file("*.tscn") var game_scene_path: String = "res://demo.tscn"

@export_group("HUD / Overlays / Audio")
@export var fade_overlay: ColorRect      ## schwarz, A=255 im Editor!
@export var flash_overlay: ColorRect     ## weiss, A=0 im Editor
@export var fog_veil: CinematicFogVeil
@export var bars: CinematicBars
## Wie lange die Zeile stehen bleibt, NACHDEM sie fertig getippt ist
## (geführtes Intro = automatisch weiter, kein Tastendruck noetig).
@export var dialog_hold_after: float = 2.0
## Fade-Zeit fuer den Dialog im Cinematic-Modus.
@export var dialog_fade_duration: float = 0.5
@export var wind: AudioStreamPlayer
@export var music: AudioStreamPlayer
@export var charge_sfx: AudioStreamPlayer   ## Aufladesound

@export_group("Welt")
@export var camera: Camera3D                ## optional (Push-In); SpringArm folgt sonst eh
@export var griffin: Node3D                 ## Fokus, Player schaut dorthin
@export var griffin_light: OmniLight3D       ## Licht das sich aufbaut (Energy 0 start)
## Optionaler Marker3D: Position, an die der Player beim Intro-Start
## teleportiert wird (sonst spawnt er an seiner Default-Position).
@export var player_spawn: Marker3D

@export_group("Lighting-Hooks")
@export var sun: DirectionalLight3D
@export var player_light: Node              ## HD2DPlayerLightRig
@export var post: Node                      ## HD2DPostProcess

@export_group("Choreografie")
## Walk 1: Player kommt von hinten ins Bild, Kamera bleibt stehen.
## Distanz so wählen, dass er mittig vor der Kamera zum Stehen kommt.
@export var walk_to_center_distance: float = 3.0
## Walk 2: Player läuft Richtung Greif, Kamera folgt.
@export var walk_to_griffin_distance: float = 4.0
## Walk 3: Nach dem Dialog noch ein paar Schritte vor.
@export var walk_after_dialog_distance: float = 1.5
@export var walk_speed: float = 6.0
## Animation-Geschwindigkeit der Lauf-Frames (1.0 = normal, 0.5 = halb so
## schnell). Für filmische Slow-Walks gleich niedrig wie walk_speed halten.
@export_range(0.1, 2.0) var anim_speed_scale: float = 0.6
## Wie stark die Kamera dem Player folgt. 0 = steht, 1 = klebt am Player.
## Für Walk 2 und 3 verwendet; Walk 1 läuft immer mit follow=0.
@export_range(0.0, 1.0) var camera_follow_ratio: float = 0.7
@export var dialog_line: String = "So this is what they feared…"

@export_group("Kamera-Framing")
## Kamera-Position automatisch berechnen. Der Director platziert die
## Cinematic-Kamera so, dass der Player nach Walk 1 mittig im Bild steht
## – kein manuelles Positionieren, kein Schleifen, kein Drift.
@export var auto_frame_camera: bool = true
## Abstand der Kamera HINTER dem mittigen Standpunkt (in Richtung weg vom Greif).
@export var camera_back_offset: float = 6.0
## Höhe der Kamera über dem Standpunkt. Höher = mehr Topdown-Anteil.
@export var camera_height_offset: float = 4.0
## Wohin die Kamera blickt: Höhe über dem Standpunkt (Look-At-Anker).
## ~1.0 = Kopf-/Brusthöhe des Players, 0.0 = Boden.
@export var camera_look_height: float = 1.0

@export_group("Intro-Look")
@export var intro_sun_energy: float = 0.15
@export var intro_vignette: float = 0.7
@export var charge_vignette: float = 0.92   ## während Aufladen enger ziehen
## Player-Sprite NUR für die Cutscene austauschen (z.B. Robe-Spritesheet).
@export var cutscene_player_texture: Texture2D
## Modulate-Abdunklung des Players. Wenn ein cutscene_player_texture (Robe)
## gesetzt ist, brauchst du das normalerweise nicht – default off.
@export var force_silhouette: bool = false
@export var silhouette_color: Color = Color(0.06, 0.06, 0.09, 1.0)

@export_group("Finale (Aufladen + Fade to White)")
@export var charge_time: float = 3.0
@export var charge_light_energy: float = 8.0
@export var flash_light_energy: float = 40.0
## Dauer des Fade-to-White nach dem Aufladen. Bleibt während des
## Szenenwechsels weiß auf dem Bildschirm – verdeckt z.B. "Player fällt
## durch Boden" am Ende.
@export var fade_to_white_duration: float = 1.2
## Wie lange weiß stehen bleiben, BEVOR die Szene wechselt.
@export var white_hold_duration: float = 0.5

@export_group("Audio (dB)")
@export var wind_target_db: float = -6.0
@export var music_target_db: float = -9.0
@export var silence_db: float = -50.0

@export_group("Optionen")
@export var allow_skip: bool = false

var _player: Node3D
var _skip := false
var _dimmed: Dictionary = {}


func _ready() -> void:
	
	if music:
		music.bus = "Music"
	if wind:
		wind.bus = "SFX"
	if charge_sfx:
		charge_sfx.bus = "SFX"
	# --- Startzustand HART setzen ------------------------------------
	if fade_overlay:
		fade_overlay.color = Color(0, 0, 0, 1)
		fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# flash_overlay: wenn nicht zugewiesen, ERZEUGE eins. So kann der
	# "Fade to White" am Ende auf keinen Fall ausfallen.
	if flash_overlay == null:
		_create_fallback_flash_overlay()
	flash_overlay.color = Color(1, 1, 1, 0)
	flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if bars:
		bars.bar_height = 0.0
	if wind:
		wind.volume_db = silence_db
	if music:
		music.volume_db = silence_db
	if charge_sfx:
		charge_sfx.volume_db = silence_db
	if griffin_light:
		griffin_light.light_energy = 0.0

	# Dunkler Intro-Look über euer Licht.
	if sun:
		sun.light_energy = intro_sun_energy
	if player_light and player_light.has_method("transition_intensity"):
		player_light.transition_intensity(0.0, 0.0, 0.01)
	if post and post.has_method("set_vignette"):
		post.set_vignette(intro_vignette, 0.01)

	# HUD ausblenden (euer Autoload heisst "Hud").
	if has_node("/root/Hud"):
		get_node("/root/Hud").hide()

	# --- Auf den (asynchron geladenen) Player warten -----------------
	_player = await _await_player(5.0)
	_enter_cinematic()

	await get_tree().process_frame
	await get_tree().process_frame
	_play()


func _unhandled_input(event: InputEvent) -> void:
	if allow_skip and event.is_action_pressed("ui_cancel"):
		_skip = true


# ---------------------------------------------------------------------
#  Player finden / warten   (Antwort auf "Player ist nicht im Tree")
# ---------------------------------------------------------------------

func _await_player(timeout: float) -> Node3D:
	# Der PlayerManager spawnt den Player asynchron. Wir pollen, bis er
	# im Tree ist (oder timeout). So greifen wir nie auf etwas zu, das
	# noch nicht existiert.
	var elapsed := 0.0
	while elapsed < timeout:
		var p := _resolve_player()
		if p:
			return p
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	push_warning("CutsceneDirector3D: Player nicht gefunden (timeout).")
	return null


func _resolve_player() -> Node3D:
	var pm := get_node_or_null("/root/PlayerManager")
	if pm and "player_instance" in pm:
		var inst = pm.player_instance
		if is_instance_valid(inst) and inst.is_inside_tree():
			return inst
	var found := get_tree().get_first_node_in_group("player")
	if found is Node3D:
		return found
	return null


func _enter_cinematic() -> void:
	if has_node("/root/BattlePause"):
		BattlePause.set_cutscene_active(true)
	
	if not _player:
		return
	if _player.has_method("set_cinematic_mode"):
		_player.set_cinematic_mode(true)
	else:
		_player.set_physics_process(false)

	# Variante A: Spielszene und Intro-Szene sind verschiedene Welten.
	# Der PlayerManager spawnt den Player an seiner Default-Position;
	# wir teleportieren ihn vor die Statue / den Greif.
	if player_spawn:
		_player.global_position = player_spawn.global_position
		if _player is CharacterBody3D:
			_player.velocity = Vector3.ZERO

	# WICHTIG: Cinematic-Kamera erzwingen. Der Player-SpringArm setzt seine
	# eigene Camera3D oft NACH unserem _ready() auf current=true und ueber-
	# schreibt die Editor-Einstellung. Hier zwingen wir die Cutscene-Kamera
	# aktiv und schalten alle anderen Camera3Ds im Player-Tree ab.
	if camera:
		_disable_player_cameras()
		if auto_frame_camera:
			_frame_camera_to_center()
		camera.make_current()
		# Dem WorldEnvironment Zeit geben, sich auf die neue Kamera einzu-
		# pendeln, und es explizit anstossen (DoF setzt sonst aus, wenn die
		# Cutscene per Szenenwechsel aus dem Menue kommt).
		await get_tree().process_frame
		_kick_world_environment()

	_face_griffin()

	# Cutscene-Sprite (z.B. Robe) anlegen, falls gewuenscht.
	if cutscene_player_texture and _player.has_method("cinematic_set_texture"):
		_player.cinematic_set_texture(cutscene_player_texture)

	# Silhouette: bevorzugt eure Player-Methode, sonst Fallback ueber modulate.
	if force_silhouette:
		if _player.has_method("cinematic_set_dark"):
			_player.cinematic_set_dark(silhouette_color)
		else:
			_dim_sprites(_player, true)


func _exit_cinematic() -> void:
	if has_node("/root/BattlePause"):
		BattlePause.set_cutscene_active(false)
	
	
	if not _player:
		return
	if force_silhouette:
		if _player.has_method("cinematic_restore_color"):
			_player.cinematic_restore_color()
		else:
			_dim_sprites(_player, false)
	if cutscene_player_texture and _player.has_method("cinematic_restore_texture"):
		_player.cinematic_restore_texture()
	if player_light and player_light.has_method("transition_intensity"):
		player_light.transition_intensity(1.0, 1.0, 1.0)
	if _player.has_method("set_cinematic_mode"):
		_player.set_cinematic_mode(false)
	else:
		_player.set_physics_process(true)


func _face_griffin() -> void:
	if not _player or not _player.has_method("cinematic_face"):
		return
	var dir := Vector3.FORWARD
	if griffin:
		dir = griffin.global_position - _player.global_position
		dir.y = 0.0
	if dir.length_squared() > 0.0001:
		_player.cinematic_face(dir.normalized())


func _dim_sprites(root: Node, on: bool) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D and "modulate" in child:
			if on:
				_dimmed[child] = child.modulate
				child.modulate = silhouette_color
			elif _dimmed.has(child):
				child.modulate = _dimmed[child]
		_dim_sprites(child, on)


## Alle Camera3D-Instanzen im Player-Baum deaktivieren, damit die
## Cinematic-Kamera nicht direkt nach dem Spawn ueberschrieben wird.
func _disable_player_cameras() -> void:
	if not _player:
		return
	for cam in _player.find_children("*", "Camera3D", true, false):
		cam.current = false


## HD2DWorldEnvironment-Knoten in der Szene anstossen, damit er DoF auf
## die jetzt aktive Cutscene-Kamera neu setzt. Ohne das bleibt das DoF
## haengen, wenn die Cutscene per Szenenwechsel aus dem Menue startet:
## die Welt-Environment-_ready laeuft, BEVOR irgendeine Kamera current
## ist, und der tree_changed-Recovery greift nicht zuverlaessig.
func _kick_world_environment() -> void:
	for env in get_tree().get_root().find_children("*", "Node3D", true, false):
		if env.get_script() == null:
			continue
		# Methodenpruefung statt is-Vergleich -> kein class_name-Import noetig
		if env.has_method("_check_refs"):
			env._check_refs()


## Berechnet exakt, wo der Player nach Walk 1 stehen wird, und platziert
## die Kamera so dahinter, dass dieser Standpunkt mittig im Bild liegt.
## Kamera bleibt eingefroren – kein Drift, kein Schleifen.
func _frame_camera_to_center() -> void:
	if not camera or not _player:
		return

	# Richtung Greif (vom Spawn aus). Fallback: Player-Forward.
	var dir := Vector3.FORWARD
	if griffin:
		dir = griffin.global_position - _player.global_position
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -_player.global_transform.basis.z
		dir.y = 0.0
	dir = dir.normalized()

	# Standpunkt = Spawn + Walk 1 in Richtung Greif
	var center_point := _player.global_position + dir * walk_to_center_distance

	# Kamera-Position: HINTER dem Standpunkt (also ENTGEGEN der Laufrichtung)
	# und um camera_height_offset darueber.
	var cam_pos := center_point - dir * camera_back_offset
	cam_pos.y += camera_height_offset
	camera.global_position = cam_pos

	# Blickrichtung auf den Standpunkt (auf Look-Hoehe)
	var look_at := center_point
	look_at.y += camera_look_height
	camera.look_at(look_at, Vector3.UP)


# ---------------------------------------------------------------------
#  Ablauf
# ---------------------------------------------------------------------

func _play() -> void:
	# --- Beat 0: nur Dunkelheit + Wind --------------------------------
	if wind:
		wind.play()
		_tween_db(wind, wind_target_db, 3.0)
	await _wait(2.0)

	# --- Beat 1: Schwarz weg -> man sieht NUR NEBEL -------------------
	if music:
		music.play()
		_tween_db(music, music_target_db, 5.0)
	if bars:
		bars.show_bars(60.0, 1.6)
	if fade_overlay:
		var rev := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		rev.tween_property(fade_overlay, "color:a", 0.0, 4.0)
		await rev.finished
	await _wait(1.5)

	# --- Beat 2: Nebel löst sich auf -> Greif sichtbar ----------------
	# Kamera steht zwischen Player-Spawn und Greif, blickt auf den Greif.
	# Der Greif schält sich aus dem Nebel, bevor der Player loslaeuft.
	if fog_veil:
		await fog_veil.tween_reveal(0.85, 5.0)
	await _wait(0.5)

	# --- Beat 3: Player kommt von hinten ins Bild --------------------
	# Kamera bleibt stehen (follow=0). Player läuft bis er mittig steht.
	# Letzter Nebelrest geht parallel weg.
	if fog_veil:
		fog_veil.tween_reveal(1.0, 3.0)
	await _walk(walk_to_center_distance, 0.0)

	# --- Beat 4: kurzer Stop ----------------------------------------
	await _wait(0.8)

	# --- Beat 5: Player läuft Richtung Greif, Kamera folgt -----------
	await _walk(walk_to_griffin_distance)

	# --- Beat 6: Player steht, Dialog (automatisch, geführt) ---------
	await _wait(0.8)
	await _show_dialog_line(dialog_line)
	await _wait(0.4)

	# --- Beat 7: noch zwei Schritte nach vorne ----------------------
	await _walk(walk_after_dialog_distance)

	# --- Beat 8: Omnilight am Greif baut sich auf -------------------
	await _charge()

	# --- Beat 9: Fade to White (verdeckt alles, auch Player-Fallen) -
	await _fade_to_white()

	# --- Beat 10: Szenenwechsel -------------------------------------
	await _finish()


func _charge() -> void:
	if charge_sfx:
		charge_sfx.volume_db = silence_db
		charge_sfx.pitch_scale = 0.8
		charge_sfx.play()
		var st := create_tween().set_parallel(true)
		st.tween_property(charge_sfx, "volume_db", -4.0, charge_time)
		st.tween_property(charge_sfx, "pitch_scale", 1.5, charge_time)  # steigt an
	if griffin_light:
		var lt := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		lt.tween_property(griffin_light, "light_energy", charge_light_energy, charge_time)
	if post and post.has_method("set_vignette"):
		post.set_vignette(charge_vignette, charge_time)   # Tunnel enger -> Druck
	await _wait(charge_time)


func _fade_to_white() -> void:
	# Licht peakt parallel zum Fade -> wirkt wie ueberbelichtet
	if griffin_light:
		var pk := create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
		pk.tween_property(griffin_light, "light_energy", flash_light_energy, fade_to_white_duration * 0.6)

	# Bildschirm langsam weiss werden lassen
	if flash_overlay:
		var fl := create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
		fl.tween_property(flash_overlay, "color:a", 1.0, fade_to_white_duration)
		await fl.finished
	else:
		await _wait(fade_to_white_duration)

	if charge_sfx:
		charge_sfx.stop()

	# Weiss halten, bevor der Szenenwechsel kommt – verdeckt alles,
	# auch den Player, der durch den Boden faellt.
	await _wait(white_hold_duration)


func _finish() -> void:
	if bars:
		bars.hide_bars(0.8)
	if music:
		_tween_db(music, silence_db, 1.5)
	if wind:
		_tween_db(wind, silence_db, 1.5)

	# Player aus dem Cinematic-Modus holen, BEVOR wir die Szene wechseln –
	# der PlayerManager re-parented ihn sonst eingefroren in die naechste
	# Szene und der Spieler kann sich nicht bewegen.
	_exit_cinematic()

	# Szenenwechsel: bevorzugt euer SceneTransition (Fade etc. uebernimmt es),
	# sonst harter Wechsel. Bildschirm ist hier weiss – verdeckt den Wechsel.
	WhiteBridge.cover_instant()
	var st := get_node_or_null("/root/SceneTransition")
	if st and st.has_method("transition_to_game"):
		st.transition_to_game(game_scene_path)
	else:
		get_tree().change_scene_to_file(game_scene_path)


# ---------------------------------------------------------------------
#  Bewegung
# ---------------------------------------------------------------------

func _walk(distance: float, follow_ratio: float = -1.0) -> void:
	if not _player:
		return
	var dir := Vector3.FORWARD
	if griffin:
		dir = griffin.global_position - _player.global_position
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var target := _player.global_position + dir * distance
	var dur := distance / maxf(walk_speed, 0.01)

	# Kamera-Follow: pro Walk überschreibbar (-1 = Default aus Inspector)
	var fr: float = follow_ratio if follow_ratio >= 0.0 else camera_follow_ratio
	if camera and fr > 0.0:
		var ct := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		ct.tween_property(camera, "global_position",
			camera.global_position + dir * distance * fr, dur)

	if _player.has_method("cinematic_walk_to"):
		await _player.cinematic_walk_to(target, walk_speed, anim_speed_scale)
	else:
		var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(_player, "global_position", target, dur)
		await t.finished


# ---------------------------------------------------------------------
#  Helfer
# ---------------------------------------------------------------------

## Erzeugt ein flash_overlay zur Laufzeit, falls keins in der Szene
## zugewiesen wurde. Liegt auf einem hohen CanvasLayer, damit es ueber
## allem anderen ist (auch ueber dem fog_veil und den Bars).
func _create_fallback_flash_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 64
	layer.name = "AutoFlashLayer"
	add_child(layer)
	var rect := ColorRect.new()
	rect.name = "AutoFlashOverlay"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(1, 1, 1, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	flash_overlay = rect
	print("[CutsceneDirector3D] flash_overlay nicht zugewiesen – Fallback erstellt.")


func _tween_db(p: AudioStreamPlayer, to_db: float, dur: float) -> void:
	var t := create_tween()
	t.tween_property(p, "volume_db", to_db, dur)


func _wait(seconds: float) -> void:
	if _skip:
		return
	await get_tree().create_timer(seconds).timeout


# ---------------------------------------------------------------------
#  Dialog
# ---------------------------------------------------------------------

## Cinematic-Wrapper um den vorhandenen DialogueManager-Autoload.
##
## Warum nicht DialogueManager.start_dialogue(...)?
##  - das braucht einen NPC + DialogueData-Resource
##  - es ruft get_tree().paused = true auf -> der Director-Timer haelt an
##    -> Intro friert ein
##
## Stattdessen poken wir die intern bereits aufgebaute UI direkt an:
##  - Panel anzeigen, Text einsetzen, Typewriter selbst treiben
##  - kein pause, kein NPC, kein Choice-Container, kein Continue-Hinweis
##  - Input-Handler vom Manager bleibt inaktiv (_is_active = false)
func _show_dialog_line(text: String) -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	if dm == null:
		push_warning("CutsceneDirector3D: DialogueManager-Autoload nicht gefunden.")
		await _wait(dialog_hold_after)
		return

	# Auf das vom Manager erzeugte UI warten (call_deferred in seinem _ready)
	var tries := 0
	while dm._panel == null and tries < 60:
		await get_tree().process_frame
		tries += 1
	if dm._panel == null:
		push_warning("CutsceneDirector3D: DialogueManager UI nicht bereit.")
		return

	# UI vorbereiten – kein Speaker, kein Hint, keine Choices.
	dm._speaker_label.text = ""
	dm._hint_label.visible = false
	for child in dm._choices_container.get_children():
		child.queue_free()

	dm._text_label.text = text
	dm._text_label.visible_characters = 0

	# --- Fade-In ----------------------------------------------------
	# Panel als Control hat modulate; setzen wir auf 0 -> sichtbar machen
	# -> auf 1 hochtweenen. So sieht kein Frame mit voller Deckkraft auf.
	dm._panel.modulate.a = 0.0
	dm._panel.visible = true
	var fade_in := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_in.tween_property(dm._panel, "modulate:a", 1.0, dialog_fade_duration)
	await fade_in.finished

	# --- Typewriter -------------------------------------------------
	var total := text.length()
	var per_char := maxf(dm.type_speed, 0.005)
	for i in total:
		dm._text_label.visible_characters = i + 1
		await get_tree().create_timer(per_char).timeout
	dm._text_label.visible_characters = -1

	await _wait(dialog_hold_after)

	# --- Fade-Out ---------------------------------------------------
	var fade_out := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade_out.tween_property(dm._panel, "modulate:a", 0.0, dialog_fade_duration)
	await fade_out.finished
	dm._panel.visible = false
	dm._panel.modulate.a = 1.0   # Zustand fuer normalen Dialog wiederherstellen

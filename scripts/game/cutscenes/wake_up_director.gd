extends Node3D
## Title-Sequence + Aufwach-Cutscene am Anfang von demo.tscn.
##
## Ablauf (alle Zeiten im Inspector tunebar):
##   1. Weiss (WhiteBridge-Autoload) blendet aus. Kamera steht UNTEN, statisch.
##   2. Halt: Voegel fliegen durchs Bild, Gezwitscher setzt ein.
##   3. Kurz danach: Musik startet.
##   4. Studio-Card "Pathlight Studios presents" — ein/halten/aus.
##   5. Kamera faehrt langsam HOCH zum Charakter.
##   6. Charakter oeffnet die Augen (Frame 95 -> 94).
##   7. Griffinblade-Logo (PNG) erscheint und bleibt/faded.
##   8. Dialog "This strange dream again..." (playergesteuert, Sprecher Daryn).
##   9. Sitzen -> Idle -> Tween Szenenkamera -> echte GameCamera -> Kontrolle frei.
##
## Als Node3D in demo.tscn. Eine Camera3D auf der UNTEREN Start-Position
## referenzieren; der Director tweent sie hoch und zuletzt in die echte
## Player-SpringArm-Kamera.

# =====================================================================
#  REFERENZEN
# =====================================================================
@export_group("Referenzen")
## Cinematic-Kamera fuer die Sequenz. Startet auf der unteren Start-Position.
@export var camera: Camera3D
## Optionaler Marker fuer die END-Position der Hochfahrt (oben, am Charakter).
## Wenn gesetzt, faehrt die Kamera dorthin; sonst Player-Position + Offset.
@export var camera_end_marker: Node3D

# =====================================================================
#  PHASE 1-2: WEISS + HALT UNTEN
# =====================================================================
@export_group("Phase: Weiss & Halt")
@export var white_fade_duration: float = 2.0
## Wie lange die Kamera unten stehenbleibt, bevor irgendwas passiert.
@export var hold_before_birds: float = 1.0
## Halt unten NACH den Voegeln/Card, bevor die Kamera hochfaehrt.
@export var hold_before_pan: float = 1.0

# =====================================================================
#  PHASE 3: MUSIK
# =====================================================================
@export_group("Phase: Musik")
@export var music_track: AudioStream
@export var music_volume_db: float = -3.0
@export var music_fade_in: float = 3.0
## Verzoegerung nach Sequenz-Start, bis die Musik einsetzt.
@export var music_start_delay: float = 1.5

# =====================================================================
#  PHASE 4: STUDIO-CARD
# =====================================================================
@export_group("Phase: Studio-Card")
@export var studio_text: String = "Pathlight Studios presents"
## Verzoegerung, bis die Card erscheint (ab Sequenz-Start gerechnet).
@export var studio_delay: float = 2.0
@export var studio_fade_in: float = 1.6
@export var studio_hold: float = 2.2
@export var studio_fade_out: float = 1.6
@export_subgroup("Studio-Card Stil")
## Eigene Schrift fuer die Card. Leer -> Merriweather-Regular -> Default.
@export var studio_font: Font
@export var studio_font_size: int = 30
## Sperrung (letter spacing) in Pixeln — Studio-Cards wirken weit gesperrt edel.
@export var studio_letter_spacing: int = 6
## Deckkraft des Texts (Studio-Cards oft nur halb deckend = leiser).
@export var studio_color: Color = Color(1, 1, 1, 0.85)
## Vertikale Bildposition 0..1 (0.5 = exakt mittig).
@export_range(0.0, 1.0, 0.01) var studio_v_position: float = 0.5

# =====================================================================
#  PHASE 5: KAMERAFAHRT HOCH
# =====================================================================
@export_group("Phase: Kamerafahrt")
@export var pan_duration: float = 6.0
## Falls kein End-Marker: Ziel = Player-Position + dieser Offset.
@export var camera_end_offset: Vector3 = Vector3(0, 6, 6)

# =====================================================================
#  PHASE 6: AUFWACHEN
# =====================================================================
@export_group("Phase: Aufwachen")
@export var sleep_frame: int = 95          ## Kopf gesenkt
@export var awake_frame: int = 94          ## Kopf erhoben
## Pause nach Kamera-Stopp, bevor die Augen aufgehen.
@export var pause_before_wake: float = 1.5

# =====================================================================
#  PHASE 7: GAME-LOGO
# =====================================================================
@export_group("Phase: Game-Logo")
@export var logo_texture: Texture2D
## Verzoegerung nach dem Aufwachen, bis das Logo erscheint.
@export var logo_delay: float = 2.0
@export var logo_fade_in: float = 1.8
@export var logo_hold: float = 2.5
@export var logo_fade_out: float = 1.5
## Logo bleibt sichtbar bis nach dem Dialog (statt vorher auszublenden)?
@export var logo_persist_until_dialog: bool = false
@export_subgroup("Logo Platzierung")
@export var logo_scale: float = 1.0
## Vertikale Bildposition 0..1.
@export_range(0.0, 1.0, 0.01) var logo_v_position: float = 0.42
@export var logo_max_width_ratio: float = 0.5   ## max. Breite relativ zum Screen

# =====================================================================
#  PHASE 8: DIALOG
# =====================================================================
@export_group("Phase: Dialog")
@export var speaker_name: String = "Daryn"
@export var dialog_line: String = "This strange dream again..."
@export var dialog_fade_duration: float = 0.6
## Verzoegerung nach Logo, bis der Dialog startet.
@export var pause_before_dialog: float = 0.8

# =====================================================================
#  PHASE 9: ABSCHLUSS + KAMERA-UEBERGABE
# =====================================================================
@export_group("Phase: Abschluss")
@export var sit_after_dialog: float = 1.5
@export var idle_before_handover: float = 0.8
## Dauer des Tweens von Szenenkamera zur echten GameCamera.
@export var handover_duration: float = 1.8

# =====================================================================
#  AUDIO (Voegel)
# =====================================================================
@export_group("Audio: Voegel")
@export var birds_sfx: AudioStream
@export var birds_volume_db: float = -6.0
@export var birds_fade_in: float = 2.5

# =====================================================================
#  VOEGEL (3D-Schwarm)
# =====================================================================
@export_group("Voegel: Schwarm")
## Spritesheet der Voegel (320x64, hframes=10/vframes=2, Frames 0,1,2 gezeichnet).
@export var bird_texture: Texture2D
## Spawn-Punkt, durch dessen Umgebung die Voegel ziehen. Leer -> dieser Node.
@export var bird_spawn_point: Node3D
@export var bird_count: int = 3
@export var bird_stagger: float = 0.9
@export var bird_base_height: float = 4.0
@export var bird_base_speed: float = 4.0
@export var bird_scale: float = 0.5
## Verzoegerung nach Sequenz-Start, bis der erste Vogel startet.
@export var birds_start_delay: float = 0.5

# =====================================================================
#  INTERN
# =====================================================================
@export_group("Einmaligkeit")
## GameManager-Flag, das markiert, dass das Intro schon lief. Wird nach dem
## Abspielen gesetzt und im Save persistiert. Fehlt es (= neues Spiel), laeuft
## das Intro; ist es gesetzt (geladener Stand / Hoehlen-Ausgang), wird es
## uebersprungen.
@export var intro_played_flag: String = "wakeup_intro_played"

@export_group("HUD & Occlusion")
## Autoload-Name des HUD (CanvasLayer). Wird waehrend des Intros versteckt
## und am Ende sanft eingeblendet.
@export var hud_autoload_name: String = "Hud"
## Autoload-Name des TreeOcclusionManager. Occlusion wird waehrend des Intros
## eingefroren (set_suppressed) und am Ende wieder freigegeben.
@export var occlusion_autoload_name: String = "TreeOcclusionManager"
@export var hud_fade_in_duration: float = 0.8

var _player: Node = null
var _birds_player: AudioStreamPlayer = null
var _music_player: AudioStreamPlayer = null
var _overlay_layer: CanvasLayer = null
var _studio_label: Label = null
var _logo_rect: TextureRect = null

const FALLBACK_FONT_PATH := "res://menu/assets/fonts/Merriweather-Regular.ttf"


func _ready() -> void:
	# Nur bei einem NEUEN Spiel abspielen. Ist das Flag gesetzt (geladener
	# Spielstand oder Rueckkehr aus einer Hoehle), Director sofort entfernen —
	# OHNE das Weiss zu setzen, sonst bliebe der Bildschirm weiss haengen.
	if _intro_already_played():
		queue_free()
		return

	# Direkt decken, falls die Szene mal ohne Intro startet (z.B. F6 im Editor).
	if has_node("/root/WhiteBridge"):
		WhiteBridge.cover_instant()
	_build_overlay_layer()
	_play()


func _intro_already_played() -> bool:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("get_flag"):
		return false   # kein GameManager -> im Zweifel abspielen
	return gm.get_flag(intro_played_flag)


func _mark_intro_played() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("set_flag"):
		gm.set_flag(intro_played_flag, true)


func _play() -> void:
	# Sofort als gesehen markieren: Schliesst der Spieler mitten im Intro und
	# laedt dann, soll es nicht erneut kommen. Das Flag wird mit dem naechsten
	# Save persistiert.
	_mark_intro_played()

	# HUD verstecken + Occlusion einfrieren, BEVOR das Weiss ausgeht.
	# Auf das HUD kurz warten: dessen _ready() (add_to_group "hud") kann nach
	# diesem Director laufen — sonst ginge das Verstecken ins Leere.
	await _hide_hud_when_ready()
	_set_occlusion_suppressed(true)

	_player = await _await_player()
	if _player == null:
		push_warning("WakeUpDirector: Kein Player gefunden – Cutscene wird uebersprungen.")
		_finish_immediately()
		return

	# Player einfrieren + schlafende Pose, BEVOR das Weiss ausgeht.
	if _player.has_method("set_cinematic_mode"):
		_player.set_cinematic_mode(true)
	_show_player_frame(sleep_frame)

	# Cinematic-Kamera erzwingen.
	if camera:
		_disable_player_cameras()
		camera.make_current()
		await get_tree().process_frame
		_kick_world_environment()

	# --- PHASE 1: Weiss ausblenden ---
	if has_node("/root/WhiteBridge"):
		WhiteBridge.fade_out(white_fade_duration)

	# Musik + Voegel als unabhaengige, zeitgesteuerte Spuren starten
	# (blockieren die Haupt-Timeline nicht).
	_schedule_birds()
	_schedule_music()
	_schedule_bird_flock()

	# --- PHASE 2: Halt unten ---
	await _wait(hold_before_birds)

	# --- PHASE 4: Studio-Card (Kamera steht noch unten) ---
	# studio_delay wird ab JETZT (nach Halt) gewertet, minus bereits Gewartetes.
	var remaining_studio_delay := maxf(studio_delay - hold_before_birds, 0.0)
	await _wait(remaining_studio_delay)
	await _show_studio_card()

	# Kurzer Atemzug, bevor die Kamera sich in Bewegung setzt.
	await _wait(hold_before_pan)

	# --- PHASE 5: Kamera faehrt hoch ---
	await _pan_camera()

	# --- PHASE 6: Aufwachen ---
	await _wait(pause_before_wake)
	_show_player_frame(awake_frame)

	# --- PHASE 7: Game-Logo ---
	await _wait(logo_delay)
	if logo_persist_until_dialog:
		await _show_logo(false)   # einblenden, NICHT ausblenden
	else:
		await _show_logo(true)    # ein + halten + aus

	# --- PHASE 8: Dialog ---
	await _wait(pause_before_dialog)
	await _run_dialog()

	# Logo jetzt ausblenden, falls es bis zum Dialog stehen bleiben sollte.
	if logo_persist_until_dialog:
		await _fade_out_logo()

	# --- PHASE 9: Abschluss ---
	await _wait(sit_after_dialog)
	if _player.has_method("_show_idle"):
		_player._show_idle()
	await _wait(idle_before_handover)

	await _handover_to_game_camera()
	_release_control()


# ---------------------------------------------------------------------
#  Overlay-Layer (Studio-Card + Logo liegen hier, UNTER dem Weiss-Bridge)
# ---------------------------------------------------------------------

func _build_overlay_layer() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 90   # ueber dem Spiel, unter WhiteBridge (128)
	add_child(_overlay_layer)


func _resolve_studio_font() -> Font:
	if studio_font != null:
		return studio_font
	if ResourceLoader.exists(FALLBACK_FONT_PATH):
		return load(FALLBACK_FONT_PATH)
	return null


# ---------------------------------------------------------------------
#  PHASE 4: Studio-Card
# ---------------------------------------------------------------------

func _show_studio_card() -> void:
	_studio_label = Label.new()
	_studio_label.text = studio_text
	_studio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_studio_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_studio_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_studio_label.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Stil ueber LabelSettings (sauberer als Theme-Overrides; keine Doppelung).
	var ls := LabelSettings.new()
	var f := _resolve_studio_font()
	if f != null:
		ls.font = f
	ls.font_size = studio_font_size
	ls.font_color = studio_color
	_studio_label.label_settings = ls

	# Sperrung (letter spacing): nicht ueber Theme-Konstanten moeglich.
	# Wir setzen sie ueber den Font selbst, indem wir extra_spacing am
	# FontVariation anlegen — funktioniert mit jeder Basis-Font.
	if f != null and studio_letter_spacing != 0:
		var fv := FontVariation.new()
		fv.base_font = f
		fv.spacing_glyph = studio_letter_spacing
		ls.font = fv

	# Vertikale Position ueber Anchor steuern.
	_studio_label.anchor_top = studio_v_position
	_studio_label.anchor_bottom = studio_v_position
	_studio_label.offset_top = -40.0
	_studio_label.offset_bottom = 40.0

	_studio_label.modulate = Color(1, 1, 1, 0.0)
	_overlay_layer.add_child(_studio_label)

	# Ein
	var t_in := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t_in.tween_property(_studio_label, "modulate:a", 1.0, studio_fade_in)
	await t_in.finished

	await _wait(studio_hold)

	# Aus
	var t_out := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t_out.tween_property(_studio_label, "modulate:a", 0.0, studio_fade_out)
	await t_out.finished

	if is_instance_valid(_studio_label):
		_studio_label.queue_free()
	_studio_label = null


# ---------------------------------------------------------------------
#  PHASE 7: Game-Logo
# ---------------------------------------------------------------------

func _show_logo(auto_fade_out: bool) -> void:
	if logo_texture == null:
		push_warning("WakeUpDirector: logo_texture nicht zugewiesen.")
		return

	_logo_rect = TextureRect.new()
	_logo_rect.texture = logo_texture
	_logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Groesse aus Texturgroesse * scale, gedeckelt auf max. Bildbreite.
	var screen := get_viewport().get_visible_rect().size
	var tex_size := logo_texture.get_size() * logo_scale
	var max_w := screen.x * logo_max_width_ratio
	if tex_size.x > max_w and tex_size.x > 0.0:
		var k := max_w / tex_size.x
		tex_size *= k

	_logo_rect.custom_minimum_size = tex_size
	_logo_rect.size = tex_size
	# Mittig horizontal, vertikal ueber logo_v_position.
	_logo_rect.position = Vector2(
		(screen.x - tex_size.x) * 0.5,
		screen.y * logo_v_position - tex_size.y * 0.5
	)

	_logo_rect.modulate = Color(1, 1, 1, 0.0)
	_overlay_layer.add_child(_logo_rect)

	var t_in := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t_in.tween_property(_logo_rect, "modulate:a", 1.0, logo_fade_in)
	await t_in.finished

	if not auto_fade_out:
		return

	await _wait(logo_hold)
	await _fade_out_logo()


func _fade_out_logo() -> void:
	if _logo_rect == null or not is_instance_valid(_logo_rect):
		return
	var t_out := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t_out.tween_property(_logo_rect, "modulate:a", 0.0, logo_fade_out)
	await t_out.finished
	if is_instance_valid(_logo_rect):
		_logo_rect.queue_free()
	_logo_rect = null


# ---------------------------------------------------------------------
#  PHASE 5: Kamerafahrt hoch
# ---------------------------------------------------------------------

func _pan_camera() -> void:
	if camera == null:
		return
	var target_pos: Vector3
	if camera_end_marker:
		target_pos = camera_end_marker.global_position
	elif _player is Node3D:
		target_pos = (_player as Node3D).global_position + camera_end_offset
	else:
		return

	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(camera, "global_position", target_pos, pan_duration)
	await t.finished


# ---------------------------------------------------------------------
#  PHASE 9: Kamera-Uebergabe an die echte GameCamera
# ---------------------------------------------------------------------

func _handover_to_game_camera() -> void:
	if camera == null:
		return
	var game_cam := _find_player_camera()
	if game_cam == null:
		# Keine Spielkamera gefunden -> hart umschalten reicht.
		return

	# Tween Position + Rotation + FOV der Cinematic-Kamera exakt auf die
	# Spielkamera. Da SpringArm/Player evtl. minimal nachlaufen, lesen wir
	# die Zielwerte zu Beginn des Tweens. Bei statischem Player passt das.
	var t := create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(camera, "global_position", game_cam.global_position, handover_duration)
	t.tween_property(camera, "global_rotation", game_cam.global_rotation, handover_duration)
	t.tween_property(camera, "fov", game_cam.fov, handover_duration)
	await t.finished


func _find_player_camera() -> Camera3D:
	if _player == null:
		return null
	for cam in _player.find_children("*", "Camera3D", true, false):
		return cam as Camera3D
	return null


# ---------------------------------------------------------------------
#  PHASE 8: Dialog (playergesteuert, UI direkt angesteuert)
# ---------------------------------------------------------------------

func _run_dialog() -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	if dm == null:
		push_warning("WakeUpDirector: Kein DialogueManager – Dialog wird uebersprungen.")
		return

	# NICHT dm.start_dialogue() — das verlangt NPC + DialogueData und ruft
	# get_tree().paused = true auf. Wir pokern die UI direkt, playergesteuert.
	if not ("_panel" in dm) or dm._panel == null:
		push_warning("WakeUpDirector: DialogueManager._panel nicht verfuegbar.")
		return

	if "_speaker_label" in dm and dm._speaker_label:
		dm._speaker_label.text = speaker_name
	if "_hint_label" in dm and dm._hint_label:
		dm._hint_label.visible = false
	if "_choices_container" in dm and dm._choices_container:
		for child in dm._choices_container.get_children():
			child.queue_free()

	if "_text_label" in dm and dm._text_label:
		dm._text_label.text = dialog_line
		dm._text_label.visible_characters = 0

	dm._panel.modulate.a = 0.0
	dm._panel.visible = true
	var fade_in := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_in.tween_property(dm._panel, "modulate:a", 1.0, dialog_fade_duration)
	await fade_in.finished

	# Typewriter
	var total := dialog_line.length()
	var per_char := 0.04
	if "type_speed" in dm:
		per_char = maxf(dm.type_speed, 0.005)
	if "_text_label" in dm and dm._text_label:
		for i in total:
			dm._text_label.visible_characters = i + 1
			await get_tree().create_timer(per_char).timeout
		dm._text_label.visible_characters = -1

	if "_hint_label" in dm and dm._hint_label:
		dm._hint_label.visible = true

	await _wait(0.25)
	await _await_advance_input()

	if "_hint_label" in dm and dm._hint_label:
		dm._hint_label.visible = false
	var fade_out := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade_out.tween_property(dm._panel, "modulate:a", 0.0, dialog_fade_duration)
	await fade_out.finished
	dm._panel.visible = false
	dm._panel.modulate.a = 1.0


func _await_advance_input() -> void:
	while true:
		if Input.is_action_just_pressed("ui_accept") \
		or Input.is_action_just_pressed("interact") \
		or Input.is_action_just_pressed("hotbar_w") \
		or Input.is_action_just_pressed("ui_select"):
			return
		await get_tree().process_frame


# ---------------------------------------------------------------------
#  Audio
# ---------------------------------------------------------------------

func _schedule_birds() -> void:
	if birds_sfx == null:
		return
	_birds_player = AudioStreamPlayer.new()
	_birds_player.stream = birds_sfx
	_birds_player.bus = "SFX"
	_birds_player.volume_db = -40.0
	add_child(_birds_player)
	_birds_player.play()
	var t := create_tween()
	t.tween_property(_birds_player, "volume_db", birds_volume_db, birds_fade_in)


func _schedule_music() -> void:
	if music_track == null:
		return
	# Verzoegert starten, ohne die Haupt-Timeline zu blockieren.
	var timer := get_tree().create_timer(music_start_delay)
	timer.timeout.connect(_start_music)


func _start_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = music_track
	_music_player.bus = "Music"
	_music_player.volume_db = -40.0
	add_child(_music_player)
	_music_player.play()
	var t := create_tween()
	t.tween_property(_music_player, "volume_db", music_volume_db, music_fade_in)


func _schedule_bird_flock() -> void:
	if bird_texture == null:
		return
	var timer := get_tree().create_timer(birds_start_delay)
	timer.timeout.connect(_spawn_bird_flock)


func _spawn_bird_flock() -> void:
	var flock_script := load("res://assets/base_tiles/wilds/birds/bird_flock.gd")
	if flock_script == null:
		push_warning("WakeUpDirector: bird_flock.gd nicht gefunden (Pfad pruefen).")
		return
	var flock: Node3D = flock_script.new()
	# An Spawn-Punkt haengen, sonst an diesen Node.
	if bird_spawn_point and is_instance_valid(bird_spawn_point):
		bird_spawn_point.add_child(flock)
		flock.global_position = bird_spawn_point.global_position
	else:
		add_child(flock)
		flock.global_position = global_position
	# Parameter durchreichen.
	flock.bird_texture = bird_texture
	flock.bird_count = bird_count
	flock.stagger = bird_stagger
	flock.base_height = bird_base_height
	flock.base_speed = bird_base_speed
	flock.bird_scale = bird_scale
	flock.launch()


# ---------------------------------------------------------------------
#  Helfer
# ---------------------------------------------------------------------

func _await_player() -> Node:
	var tries := 0
	while tries < 120:
		var p := get_tree().get_first_node_in_group("player")
		if p != null:
			return p
		await get_tree().process_frame
		tries += 1
	return null


func _show_player_frame(frame: int) -> void:
	if _player == null:
		return
	if _player.has_method("cinematic_show_frame"):
		_player.cinematic_show_frame(frame, false)
	elif "character" in _player and _player.character:
		_player.character.frame = frame


func _disable_player_cameras() -> void:
	if _player == null:
		return
	for cam in _player.find_children("*", "Camera3D", true, false):
		cam.current = false


func _kick_world_environment() -> void:
	for env in get_tree().get_root().find_children("*", "Node3D", true, false):
		if env.get_script() != null and env.has_method("_check_refs"):
			env._check_refs()


func _release_control() -> void:
	# Occlusion wieder freigeben — ab jetzt sollen Baeume normal occluden.
	_set_occlusion_suppressed(false)
	# HUD sanft einblenden (erstes Erscheinen ueberhaupt).
	_set_hud_visible(true, true)

	if _player and _player.has_method("set_cinematic_mode"):
		_player.set_cinematic_mode(false)
	var game_cam := _find_player_camera()
	if game_cam:
		game_cam.make_current()
	queue_free()


func _finish_immediately() -> void:
	_set_occlusion_suppressed(false)
	_set_hud_visible(true, false)
	if has_node("/root/WhiteBridge"):
		WhiteBridge.fade_out(0.3)
	queue_free()


# ---------------------------------------------------------------------
#  HUD & Occlusion
# ---------------------------------------------------------------------

func _set_hud_visible(value: bool, fade: bool = false) -> void:
	var hud := _find_hud()
	if hud == null:
		return

	# Bevorzugt die HUD-eigenen Methoden — die faden den korrekten, lebenden
	# _hud_root und sind robust gegen die _ready()-Reihenfolge.
	if not value and hud.has_method("hide_for_intro"):
		hud.hide_for_intro()
		return
	if value and fade and hud.has_method("reveal_after_intro"):
		hud.reveal_after_intro(hud_fade_in_duration)
		return
	if value and not fade and hud.has_method("reveal_after_intro"):
		hud.reveal_after_intro(0.0)
		return

	# --- Fallback, falls die HUD-Methoden fehlen ---
	if not fade:
		if "visible" in hud:
			hud.visible = value
		return
	if "visible" in hud:
		hud.visible = value
	var fade_root: CanvasItem = _find_fade_target(hud)
	if fade_root:
		fade_root.modulate.a = 0.0
		var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(fade_root, "modulate:a", 1.0, hud_fade_in_duration)


## Mehrstufige HUD-Suche: Autoload -> Gruppe "hud" -> Name -> Typ.
func _find_hud() -> Node:
	# 1. Autoload unter /root/<Name>
	var by_autoload := get_node_or_null("/root/" + hud_autoload_name)
	if by_autoload:
		return by_autoload
	# 2. Node-Gruppe "hud"
	var by_group := get_tree().get_first_node_in_group("hud")
	if by_group:
		return by_group
	# 3. Namenssuche im aktuellen Szenenbaum (Hud / HUD)
	var scene := get_tree().current_scene
	if scene:
		for name_try in [hud_autoload_name, "Hud", "HUD"]:
			var found := scene.find_child(name_try, true, false)
			if found:
				return found
	return null


## Findet das Control/CanvasItem, das wir faden koennen. Bevorzugt das HUD
## selbst (falls es ein CanvasItem ist), sonst das erste CanvasItem-Kind.
func _find_fade_target(hud: Node) -> CanvasItem:
	if hud is CanvasItem:
		return hud
	for child in hud.get_children():
		if child is CanvasItem:
			return child
	return null


func _set_occlusion_suppressed(value: bool) -> void:
	var occ := get_node_or_null("/root/" + occlusion_autoload_name)
	if occ == null:
		return
	if occ.has_method("set_suppressed"):
		occ.set_suppressed(value)


## Wartet ein paar Frames, bis das HUD im Baum ist (sein _ready ruft
## add_to_group "hud"), und versteckt es dann. Loest die Race-Condition,
## dass der Director vor dem HUD startet.
func _hide_hud_when_ready() -> void:
	var tries := 0
	while tries < 30:
		var hud := _find_hud()
		if hud != null:
			_set_hud_visible(false)
			return
		await get_tree().process_frame
		tries += 1
	# Kein HUD gefunden — kein Drama, dann gibt es eben nichts zu verstecken.


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout

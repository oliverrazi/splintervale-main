extends Node
class_name BoulderChaseDirector

## Orchestriert die komplette Indiana-Jones-Boulder-Chase-Sequenz als
## eigenständige State-Machine — bespoke Intro-Cutscene, on-rails-Boulder über
## PathFollow3D mit Beschleunigung, präzises Musik-Timing über einen eigenen
## AudioStreamPlayer, Fail-Retry ohne Szenenreload, Erfolg persistiert per Flag.
##
## Ablauf:
##   ARMED  → Player betritt trigger_area
##   INTRO  → Player gesperrt, schaut zur Kugel; Steinchen+Staub-Telegraph,
##            dann stürzt die Kugel herab; Intro-Musik läuft, Cave eingefroren.
##            Kurz vor Intro-Ende beginnt die Kugel (aus dem Stand) anzurollen.
##   CHASE  → Chase-Loop, Player frei, Kugel beschleunigt auf boulder_speed,
##            durchgängiges leichtes Kamera-Rumble (skaliert mit Nähe).
##   SUCCESS→ Player launcht auf den Klippen-Anchor: Fanfare + Flag + Save;
##            Kugel rollt bis zum Pfad-Ende (Lücke) und zerspringt dort in
##            Brocken + Fog. Danach Stille (Cave bleibt gepaused).
##   FAIL   → Boulder-Treffer ODER Sturz in eine fail_zone: Musik SOFORT aus,
##            Freeze → Fade schwarz → Respawn vor dem Trigger → Cave weiter → ARMED

enum State { DORMANT, ARMED, INTRO, CHASE, SUCCESS, CLEARED, FAIL }

@export_group("Identity")
@export var chase_id: String = "cave_01"           ## Flag = "boulder_chase_cleared_" + chase_id
@export var autosave_on_clear: bool = true

@export_group("Scene Refs")
@export var trigger_area: Area3D
@export var boulder: ChaseBoulder
@export var boulder_path_follow: PathFollow3D
@export var respawn_marker: Node3D                 ## KLAR außerhalb der trigger_area platzieren!
@export var cliff_anchor: Node3D                   ## VectorAnchorTargetable3D der Klippe

@export_group("Music")
@export var intro_music: AudioStream               ## one-shot (NICHT loopen)
@export var chase_music: AudioStream               ## loopend (Loop im Import-Dock)
@export var victory_music: AudioStream             ## one-shot
@export var music_bus: String = "Music"

@export_group("Boulder Motion")
@export var boulder_speed: float = 45.0            ## Ziel-Speed (Welt-Einh./Sek) — knapp unter Player.SPEED (=50)
@export var boulder_accel_time: float = 1.2        ## Sekunden von 0 auf boulder_speed
@export var boulder_drop_height: float = 6.0
@export var boulder_drop_time: float = 0.7

@export_group("Rubber Band")                       ## Boulder-Speed variiert subtil mit dem Abstand zum Player
@export var rubber_band_enabled: bool = true
@export var rubber_band_near: float = 6.0          ## unter diesem Abstand: langsamster Faktor
@export var rubber_band_far: float = 15.0          ## über diesem Abstand: schnellster Faktor
@export var rubber_band_slow_mult: float = 0.9     ## nah dran → etwas langsamer
@export var rubber_band_fast_mult: float = 1.15    ## weit weg → etwas schneller (holt auf)

@export_group("Boulder Landing FX")
@export var landing_hitstop: float = 0.05
@export var landing_shake_strength: float = 0.15   ## SpringArm-Shake beim Aufprall (Welt-Einheiten)
@export var landing_shake_duration: float = 0.35

@export_group("Roll Camera Shake")                 ## durchgängiges leichtes Rumble während der Jagd
@export var roll_shake_min: float = 0.01           ## weit weg
@export var roll_shake_max: float = 0.06           ## Kugel dicht am Player
@export var roll_shake_range: float = 15.0         ## Distanz, über die es hochskaliert
@export var roll_shake_refresh: float = 0.15

@export_group("Intro Telegraph")                   ## Steinchen + Staub kündigen den Boulder an
@export var boulder_drop_delay: float = 0.7        ## Pause nach dem Telegraph, ehe der Boulder kracht
@export var debris_scene: PackedScene              ## darf ein reines MeshInstance3D sein — wird auto-gewrappt
@export var debris_count: int = 5
@export var debris_drop_height: float = 4.0
@export var debris_scatter: float = 1.5            ## horizontaler Streuradius der Steinchen — größer = weiter verteilt (im Inspector setzen!)
@export var debris_settle_time: float = 2.0        ## danach einfrieren + Kollision aus (billig)
@export var debris_collision_mask: int = 1         ## Boden-Layer, damit sie liegen bleiben

@export_group("Dust")
@export var dust_shader: Shader                     ## resonance_dust_volume.gdshader zuweisen
@export var dust_opacity: float = 0.9
@export var dust_billboard_count: int = 4
@export var dust_rise_height: float = 0.5
@export var telegraph_dust_size: float = 0.8
@export var telegraph_dust_duration: float = 1.2
@export var landing_dust_size: float = 1.8
@export var landing_dust_duration: float = 1.8

@export_group("Sounds")
@export var predrop_sound: AudioStream             ## kurz vor dem Sturz (beim Telegraph)
@export var impact_sound: AudioStream              ## beim Aufprall
@export var predrop_volume_db: float = -4.0
@export var impact_volume_db: float = 0.0

@export_group("Fail Zones")                        ## Löcher / Absturzkanten — nur im Chase aktiv
@export var fail_zones: Array[Area3D] = []         ## Area3D(s) knapp ÜBER dem Wasser als Fangschicht
@export var fail_below_y: float = -1000.0          ## Backup: Player unter dieser Y-Höhe = Fail (im Chase)

@export_group("Fail")
@export var fail_damage: int = 5                   ## Nur fürs Feeling — wird nie tödlich
@export var fail_freeze_hold: float = 0.35
@export var fail_fade_duration: float = 0.5
@export var fail_music_fade: float = 0.6           ## Musik beim Fail sanft ausblenden (statt hart stoppen)

@export_group("Success Shatter")                   ## Boulder zerspringt am Pfad-Ende (Lücke)
@export var shatter_debris_scene: PackedScene      ## eigene Steine für den Boulder-Zerfall (andere als Telegraph!)
@export var shatter_count: int = 15
@export var shatter_impulse: float = 3.0
@export var shatter_up_kick: float = 2.0
@export var shatter_scatter: float = 1.5
@export var shatter_lifetime: float = 3.0
@export var shatter_sound: AudioStream
@export var shatter_dust_size: float = 1.6
@export var shatter_dust_duration: float = 1.8

@export_group("Stalagmites")
@export var stalagmite_hit_radius: float = 0.6     ## horizontaler Trefferradius Boulder↔Stalagmit (layer-unabhängig)
@export var debug_stalagmites: bool = false        ## Konsolen-Ausgabe bei Treffer (Diagnose)

@export_group("Intro")
@export var face_boulder_on_intro: bool = true
@export var trigger_forward_distance: float = 0.0   ## beim Betreten X Einheiten auf der Z-Achse nach oben/vorne (-Z); 0 = aus, negativ = andersrum
@export var trigger_forward_time: float = 0.3

@export_group("Intro Recoil")                      ## kleine Schreck-Cutscene nach dem Boulder-Sturz
@export var recoil_flip: bool = true               ## Frames gespiegelt (Default-Sprite schaut nach links)
@export var recoil_sword_hidden: bool = true       ## Schwert-Layer während der Recoil-Frames ausblenden
@export_subgroup("Phase 1 — großer Schreck-Schritt")
@export var recoil_frame_1: int = 51
@export var recoil_first_step_distance: float = 2.5
@export var recoil_first_step_time: float = 0.25
@export var recoil_first_pause: float = 0.5
@export_subgroup("Phase 2 — kleine Rückwärts-Schritte (52-53 im Wechsel)")
@export var recoil_walk_frame_a: int = 52
@export var recoil_walk_frame_b: int = 53
@export var recoil_walk_frame_extra: int = 54       ## Extra-Frame nach jedem Schritt (52-54, 53-54)
@export var recoil_walk_steps: int = 4
@export var recoil_walk_step_distance: float = 0.8
@export var recoil_walk_frame_time: float = 0.18
@export_subgroup("Phase 3 — nach links drehen")
@export var recoil_turn_pause: float = 0.2

var _state: int = State.ARMED
var _player: Node3D = null
var _vector_anchor: Node = null
var _music_player: AudioStreamPlayer = null
var _cave_paused: bool = false
var _launch_connected: bool = false
var _telegraph_debris: Array[Node] = []   ## liegen gebliebene Steinchen des aktuellen Versuchs
var _boulder_rolling: bool = false
var _boulder_speed_current: float = 0.0
var _convex_cache: Dictionary = {}        ## Mesh → Shape3D, damit Hulls nur einmal berechnet werden


func _ready() -> void:
	# Eigener Musik-Player nur für die Sequenz (Intro/Chase/Fanfare).
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = music_bus
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS   # läuft durch jeden Hitstop durch → kein Stottern
	add_child(_music_player)

	if trigger_area:
		trigger_area.body_entered.connect(_on_trigger_body_entered)
	if boulder:
		boulder.body_entered.connect(_on_boulder_body_entered)
		boulder.hide_boulder()
	if boulder_path_follow:
		boulder_path_follow.loop = false           # Kugel darf am Kurvenende nicht zurückspringen

	for zone in fail_zones:
		if zone:
			zone.body_entered.connect(_on_fail_zone_entered)

	# Schon geschafft? → schlafen legen, Trigger tot.
	if _flag_cleared():
		_enter_dormant()
	else:
		_state = State.ARMED

	_prewarm_debris()   # Convex-Hulls der Debris-Meshes vorab berechnen → kein Shatter-Ruckler


func _physics_process(delta: float) -> void:
	# Boulder-Bewegung mit Beschleunigung (unabhängig vom State, sobald rollend).
	if _boulder_rolling and boulder_path_follow:
		var target_speed: float = boulder_speed * _rubber_band_factor()
		var accel: float = boulder_speed / maxf(boulder_accel_time, 0.01)
		_boulder_speed_current = move_toward(_boulder_speed_current, target_speed, accel * delta)
		boulder_path_follow.progress += _boulder_speed_current * delta
		if boulder_path_follow.progress_ratio >= 1.0:
			boulder_path_follow.progress_ratio = 1.0
			_on_boulder_reached_end()

	# Durchgängiges Roll-Rumble nur während der Jagd.
	if _state == State.CHASE:
		_apply_roll_shake()
		_check_stalagmite_hits()
		if _player and _player.global_position.y < fail_below_y:
			_on_fail()


func _exit_tree() -> void:
	# Nie mit stummgeschaltetem MusicManager aus der Szene gehen
	# (nach SUCCESS bleibt die Cave absichtlich gepaused → hier auflösen).
	if _cave_paused:
		MusicManager.resume_music()
		_cave_paused = false
	_disconnect_launch()


# ─── Trigger ───────────────────────────────────────────────────────

func _on_trigger_body_entered(body: Node) -> void:
	if _state != State.ARMED:
		return
	if not body.is_in_group("player"):
		return
	_start_intro()


# ─── INTRO ─────────────────────────────────────────────────────────

func _start_intro() -> void:
	if _state != State.ARMED:
		return
	_state = State.INTRO

	_resolve_player()
	if _player == null:
		push_warning("BoulderChaseDirector: kein Player gefunden — Intro abgebrochen.")
		_state = State.ARMED
		return

	# Cave-Theme einfrieren (läuft bei Fail exakt an gleicher Stelle weiter).
	_pause_cave()

	# Kugel ZUERST an den Kurvenstart zurück — auch wenn im Editor der
	# progress_ratio zum Vorschauen verstellt wurde. Sonst zeigt der Blick
	# aufs falsche Ziel (Ursache für "Player schaut andersrum").
	if boulder and boulder_path_follow:
		boulder_path_follow.progress = 0.0
		_boulder_speed_current = 0.0
		boulder.hide_boulder()

	# Player sperren.
	if _player.has_method("set_cinematic_mode"):
		_player.set_cinematic_mode(true)

	# Erst ein Stück auf der Z-Achse nach vorne laufen (Run-Frames), dann blicken.
	await _move_player_forward()
	if _state != State.INTRO:
		return
	if face_boulder_on_intro:
		_face_player_at_boulder()

	# Intro-Stinger starten.
	_play_music(intro_music)

	# Ablauf: Telegraph + Boulder-Sturz → Recoil-Cutscene → Chase.
	await _run_intro_sequence()
	if _state != State.INTRO:
		return

	# Kleine Cutscene: zweimal Schritt zurück mit Schreck-Frames.
	await _play_intro_recoil()
	if _state != State.INTRO:
		return

	# Jetzt läuft der Player los (Kontrolle frei) und der Boulder rollt an.
	_begin_chase()


func _run_intro_sequence() -> void:
	# Landepunkt = Ruheposition der Kugel am Kurvenstart (progress = 0).
	var landing_pos: Vector3 = _boulder_landing_point()

	# 1) Telegraph: Steinchen + etwas Staub + Vorwarn-Sound.
	_spawn_debris_telegraph(landing_pos)
	_play_sfx(predrop_sound, landing_pos, predrop_volume_db)

	# 2) Bewusste Pause — der Boulder kommt etwas später, nicht sofort.
	await get_tree().create_timer(boulder_drop_delay).timeout
	if _state != State.INTRO:
		return

	# 3) Boulder einblenden, anheben, herabstürzen.
	if boulder:
		boulder.prepare_drop(boulder_drop_height)
		await boulder.drop_to_rest(boulder_drop_time)
	if _state != State.INTRO:
		return

	# 4) Aufprall: Kamera-Shake + Hitstop + Staub + Impact-Sound.
	_boulder_landing_fx(landing_pos)


func _play_intro_recoil() -> void:
	if _player == null:
		return

	# Boulder fängt schon während des Zurückweichens langsam an zu rollen
	# (Trefferabfrage bleibt bis zum Chase aus, Fail nur im CHASE-State).
	_start_boulder_motion()

	# Schwert für die Recoil-Frames ausblenden.
	_set_player_sword_visible(false)

	# Phase 1: großer Schreck-Schritt zurück mit Frame 1 (gespiegelt), halten.
	_show_recoil_frame(recoil_frame_1)
	await _step_back(recoil_first_step_distance, recoil_first_step_time)
	_show_recoil_frame(recoil_frame_1)
	await _hold(recoil_first_pause)
	if _state != State.INTRO:
		return

	# Phase 2: kleine Rückwärts-Schritte, pro Schritt ZWEI Frames — primär (52/53
	# im Wechsel) + Extra-Frame (54). Ergibt 52-54, 53-54, ...
	for i in range(recoil_walk_steps):
		var primary: int = recoil_walk_frame_a if (i % 2 == 0) else recoil_walk_frame_b
		# Primär-Frame + halber Schritt.
		_show_recoil_frame(primary)
		await _step_back(recoil_walk_step_distance * 0.5, recoil_walk_frame_time * 0.5)
		if _state != State.INTRO:
			return
		# Extra-Frame + zweiter halber Schritt.
		_show_recoil_frame(recoil_walk_frame_extra)
		await _step_back(recoil_walk_step_distance * 0.5, recoil_walk_frame_time * 0.5)
		if _state != State.INTRO:
			return

	# Phase 3: Schwert zurück, nach links drehen (Fluchtrichtung), bereit loszurennen.
	_set_player_sword_visible(true)
	if _player.has_method("cinematic_face"):
		_player.cinematic_face(_flee_direction())
	await _hold(recoil_turn_pause)


func _show_recoil_frame(frame: int) -> void:
	if _player != null and _player.has_method("cinematic_show_frame"):
		_player.cinematic_show_frame(frame, recoil_flip)


func _step_back(distance: float, time: float) -> void:
	if _player == null:
		return
	var back: Vector3 = _flee_direction()
	var target: Vector3 = _player.global_position + back * distance
	if _player.has_method("cinematic_tween_to"):
		var t: Tween = _player.cinematic_tween_to(target, time)
		if t != null:
			await t.finished
	else:
		_player.global_position = target


func _set_player_sword_visible(vis: bool) -> void:
	# Schwert liegt als "weapon"-Layer auf dem charactersprite (LayeredPixelSprite3D).
	if not recoil_sword_hidden or _player == null:
		return
	var sprite := _player.get_node_or_null("charactersprite")
	if sprite != null and sprite.has_method("has_layer") and sprite.has_method("set_layer_visible"):
		if sprite.has_layer("weapon"):
			sprite.set_layer_visible("weapon", vis)


func _flee_direction() -> Vector3:
	# "Geradeaus nach links" relativ zur Kamera (Screen-Left). NICHT die
	# Boulder→Player-Richtung nehmen — die zeigt oft leicht diagonal, wodurch
	# der Schritt nach links-unten driftet statt gerade nach links.
	if _player != null:
		var arm := _player.get_node_or_null("SpringArm3D")
		if arm != null:
			var yaw: float = arm.rotation.y
			var right := Vector3(cos(yaw), 0.0, -sin(yaw))
			return (-right).normalized()
	return Vector3.LEFT


func _move_player_forward() -> void:
	# Reine Welt-Z-Bewegung. Positiver Wert = nach oben/vorne (-Z auf dem Screen),
	# negativer = andersrum. Läuft animiert (Run-Frames), fällt sonst auf Walk/Tween zurück.
	if _player == null or trigger_forward_distance == 0.0:
		return
	var target: Vector3 = _player.global_position + Vector3(0.0, 0.0, -trigger_forward_distance)
	var speed: float = absf(trigger_forward_distance) / maxf(trigger_forward_time, 0.01)
	if _player.has_method("cinematic_run_to"):
		await _player.cinematic_run_to(target, speed)
	elif _player.has_method("cinematic_walk_to"):
		await _player.cinematic_walk_to(target, speed)
	elif _player.has_method("cinematic_tween_to"):
		var t: Tween = _player.cinematic_tween_to(target, trigger_forward_time)
		if t != null:
			await t.finished
	else:
		_player.global_position = target


func _hold(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _start_boulder_motion() -> void:
	if _boulder_rolling:
		return
	_boulder_rolling = true
	_boulder_speed_current = 0.0
	if boulder:
		boulder.start_roll_sound()


# ─── CHASE ─────────────────────────────────────────────────────────

func _begin_chase() -> void:
	_state = State.CHASE
	_play_music(chase_music)
	_set_player_sword_visible(true)                # Schwert wieder normal (Sicherheitsnetz)
	if _player and _player.has_method("set_cinematic_mode"):
		_player.set_cinematic_mode(false)          # Player freigeben
	if boulder:
		boulder.set_hit_detection(true)
	_start_boulder_motion()                        # Boulder rollt jetzt an (beschleunigt aus dem Stand)
	_connect_launch()


func _apply_roll_shake() -> void:
	if _player == null or boulder == null:
		return
	var d: float = boulder.global_position.distance_to(_player.global_position)
	var prox: float = clampf(1.0 - d / maxf(roll_shake_range, 0.01), 0.0, 1.0)
	var amp: float = roll_shake_min + (roll_shake_max - roll_shake_min) * prox
	# GameEffects jeden Frame frisch antriggern → sauberes Dauer-Rumble, klingt bei Chase-Ende aus.
	if GameEffects:
		GameEffects.shake(amp, roll_shake_refresh)


func _check_stalagmite_hits() -> void:
	# Layer-unabhängig: zerschlägt jeden Stalagmit auf der Route, sobald der
	# Boulder horizontal nah genug ist (kein Verlass auf Collision-Masken).
	if boulder == null:
		return
	var bpos: Vector3 = boulder.global_position
	var r2: float = stalagmite_hit_radius * stalagmite_hit_radius
	for s in get_tree().get_nodes_in_group("chase_stalagmite"):
		if not (s is Node3D):
			continue
		if s.has_method("is_shattered") and s.is_shattered():
			continue
		var spos: Vector3 = (s as Node3D).global_position
		var dx: float = bpos.x - spos.x
		var dz: float = bpos.z - spos.z
		if dx * dx + dz * dz <= r2 and s.has_method("shatter"):
			if debug_stalagmites:
				print("[Chase] Stalagmit '%s' getroffen (dist=%.2f)" % [s.name, sqrt(dx * dx + dz * dz)])
			s.shatter()


func _rubber_band_factor() -> float:
	# Weit weg vom Player → etwas schneller (holt auf), nah dran → etwas langsamer.
	# Subtil, damit man es kaum bemerkt, aber der Boulder nie ganz aus dem Bild fällt.
	if not rubber_band_enabled or _player == null:
		return 1.0
	var boulder_pos: Vector3 = boulder.global_position if boulder else boulder_path_follow.global_position
	var to_player: Vector3 = _player.global_position - boulder_pos
	to_player.y = 0.0
	var dist: float = to_player.length()
	var t: float = clampf((dist - rubber_band_near) / maxf(rubber_band_far - rubber_band_near, 0.01), 0.0, 1.0)
	return lerpf(rubber_band_slow_mult, rubber_band_fast_mult, t)


func _on_boulder_reached_end() -> void:
	_boulder_rolling = false
	if _state == State.SUCCESS:
		_shatter_boulder()
	# Bei CHASE bleibt die Kugel am Ende stehen (degenerierter Fall — Player launcht normal).


# ─── SUCCESS ───────────────────────────────────────────────────────

func _on_player_launch_started() -> void:
	if _state != State.CHASE or _vector_anchor == null or cliff_anchor == null:
		return
	if _vector_anchor.get_current_target() == cliff_anchor:
		_on_success()


func _on_success() -> void:
	_state = State.SUCCESS
	_disconnect_launch()
	if boulder:
		boulder.set_hit_detection(false)

	# Fanfare. Cave bleibt gepaused → danach mysteriöse Stille.
	_play_music(victory_music)

	# Fortschritt sichern.
	if GameManager:
		GameManager.set_flag(_flag_name(), true)
		if autosave_on_clear and GameManager.has_method("save_game"):
			GameManager.save_game()

	if trigger_area:
		trigger_area.monitoring = false

	# Kugel rollt bis ans Pfad-Ende (Lücke) weiter und zerspringt DORT.
	_boulder_rolling = true
	if boulder_path_follow and boulder_path_follow.progress_ratio >= 1.0:
		_shatter_boulder()                         # schon am Ende → sofort


func _shatter_boulder() -> void:
	_boulder_rolling = false
	var pos: Vector3 = boulder.global_position if boulder else _boulder_landing_point()

	# 15 Brocken prozedural spawnen (oder debris_scene-Mesh), nach außen/oben schleudern.
	for i in range(shatter_count):
		var chunk := _make_pebble_instance(shatter_debris_scene, 0.1, 0.25)
		add_child(chunk)
		if chunk is Node3D:
			(chunk as Node3D).global_position = pos + Vector3(
				randf_range(-shatter_scatter, shatter_scatter) * 0.3,
				randf_range(0.0, shatter_scatter) * 0.3,
				randf_range(-shatter_scatter, shatter_scatter) * 0.3
			)
		if chunk is RigidBody3D:
			var rb := chunk as RigidBody3D
			rb.freeze = false
			rb.sleeping = false
			var scatter := Vector3(randf_range(-1.0, 1.0), randf_range(0.0, 1.0), randf_range(-1.0, 1.0))
			if scatter.length_squared() < 0.01:
				scatter = Vector3.UP
			var impulse := scatter.normalized() * shatter_impulse + Vector3.UP * shatter_up_kick
			rb.apply_central_impulse(impulse * rb.mass)
			rb.apply_torque_impulse(Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1)))
		_free_after(chunk, shatter_lifetime)

	# Fog + Sound.
	_spawn_dust(pos, shatter_dust_size, shatter_dust_size, dust_opacity, shatter_dust_duration)
	_play_sfx(shatter_sound, pos, 0.0)

	# Kugel weg.
	if boulder:
		boulder.stop_roll_sound()
		boulder.hide_boulder()

	_state = State.CLEARED


# ─── FAIL ──────────────────────────────────────────────────────────

func _on_boulder_body_entered(body: Node) -> void:
	if _state != State.CHASE:
		return
	# Stalagmit auf der Route? → zerschlagen, kein Fail, Kugel rollt weiter.
	if body.is_in_group("chase_stalagmite") and body.has_method("shatter"):
		body.shatter()
		return
	if not body.is_in_group("player"):
		return
	_on_fail()


func _on_fail_zone_entered(body: Node) -> void:
	if _state != State.CHASE:
		return
	if not body.is_in_group("player"):
		return
	_on_fail()


func _on_fail() -> void:
	if _state != State.CHASE:
		return
	_state = State.FAIL

	# Musik sanft ausblenden statt hart stoppen (klingt besser).
	# _music_player läuft dank PROCESS_MODE_ALWAYS durch den Hitstop → kein Stottern.
	_fade_out_music(fail_music_fade)
	if boulder:
		boulder.stop_roll_sound()
	_boulder_rolling = false

	_disconnect_launch()
	if boulder:
		boulder.set_hit_detection(false)

	_resolve_player()

	# "Es tut weh" — Schaden fürs Feeling, aber garantiert nie tödlich.
	# (Der Kamera-Shake kommt aus deinem take_damage/_play_hurt_feedback selbst.)
	if _player and _player.has_method("take_damage"):
		var dmg := fail_damage
		if GameManager and GameManager.player_data:
			var hp: int = GameManager.player_data.current_hp
			if hp - dmg <= 0:
				dmg = max(0, hp - 1)
		var hit_from: Vector3 = boulder.global_position if boulder else _player.global_position
		_player.take_damage(dmg, hit_from)

	# Player sofort einfrieren (stoppt Fall/Bewegung, bricht Knockback ab).
	if _player and _player.has_method("set_cinematic_mode"):
		_player.set_cinematic_mode(true)

	# Dramatischer Ganz-Szene-Freeze.
	if GameEffects:
		GameEffects.hitstop(fail_freeze_hold)
	await get_tree().create_timer(fail_freeze_hold).timeout
	get_tree().paused = false

	# Fade zu Schwarz.
	await SceneTransition.fade_out(fail_fade_duration)

	# --- Im Schwarzbild alles zurücksetzen ---
	_reset_for_retry()
	_resume_cave()                                 # Cave läuft exakt weiter

	# Zurück ins Bild.
	SceneTransition.fade_in(fail_fade_duration)
	await get_tree().create_timer(fail_fade_duration).timeout

	if _player and _player.has_method("set_cinematic_mode"):
		_player.set_cinematic_mode(false)
	_state = State.ARMED


func _reset_for_retry() -> void:
	_music_player.stop()
	if boulder:
		boulder.stop_roll_sound()
	_boulder_rolling = false
	_boulder_speed_current = 0.0

	# Steinchen des Fehlversuchs entfernen (nach SUCCESS bleiben sie dagegen liegen).
	for d in _telegraph_debris:
		if is_instance_valid(d):
			d.queue_free()
	_telegraph_debris.clear()

	# Zerschlagene Stalagmiten wieder aufbauen.
	for s in get_tree().get_nodes_in_group("chase_stalagmite"):
		if s.has_method("reset"):
			s.reset()

	if boulder_path_follow:
		boulder_path_follow.progress = 0.0
	if boulder:
		boulder.reset_roll()
		boulder.hide_boulder()

	# Player vor den Trigger setzen, Richtung Trigger blicken lassen.
	if _player and respawn_marker:
		_player.global_position = respawn_marker.global_position
		if "velocity" in _player:
			_player.velocity = Vector3.ZERO
		if _player.has_method("cinematic_face") and trigger_area:
			var face_dir: Vector3 = trigger_area.global_position - respawn_marker.global_position
			face_dir.y = 0.0
			if face_dir.length_squared() > 0.0001:
				_player.cinematic_face(face_dir.normalized())


# ─── Launch-Signal ─────────────────────────────────────────────────

func _connect_launch() -> void:
	if _launch_connected:
		return
	_resolve_player()
	if _vector_anchor and _vector_anchor.has_signal("launch_started"):
		_vector_anchor.launch_started.connect(_on_player_launch_started)
		_launch_connected = true


func _disconnect_launch() -> void:
	if _launch_connected and _vector_anchor \
	and _vector_anchor.launch_started.is_connected(_on_player_launch_started):
		_vector_anchor.launch_started.disconnect(_on_player_launch_started)
	_launch_connected = false


# ─── Musik / Cave / SFX ────────────────────────────────────────────

func _play_music(stream: AudioStream) -> void:
	if _music_player == null:
		return
	if stream == null:
		_music_player.stop()
		return
	_music_player.stream = stream
	_music_player.volume_db = 0.0                  # evtl. vorheriges Fade-out zurücksetzen
	_music_player.play()


func _fade_out_music(duration: float) -> void:
	if _music_player == null or not _music_player.playing:
		return
	if duration <= 0.0:
		_music_player.stop()
		return
	# _music_player ist ALWAYS → das Tween läuft auch während des Hitstops sauber.
	var t := _music_player.create_tween()
	t.tween_property(_music_player, "volume_db", -40.0, duration)
	t.tween_callback(_music_player.stop)


func _play_sfx(stream: AudioStream, pos: Vector3, volume_db: float) -> void:
	if stream == null:
		return
	AudioPool.play_3d(stream, pos, volume_db, 1.0)


func _pause_cave() -> void:
	if _cave_paused:
		return
	MusicManager.pause_music()
	_cave_paused = true


func _resume_cave() -> void:
	if not _cave_paused:
		return
	MusicManager.resume_music()
	_cave_paused = false


# ─── Telegraph / Debris ────────────────────────────────────────────

func _spawn_debris_telegraph(landing_pos: Vector3) -> void:
	# Steinchen NICHT alle gleichzeitig — über das Zeitfenster bis zur
	# Boulder-Landung zufällig verteilt einstreuen.
	var window: float = maxf(0.05, boulder_drop_delay + boulder_drop_time)
	for i in range(debris_count):
		_spawn_one_debris_delayed(landing_pos, randf() * window)

	# Etwas Staub schon beim Telegraph.
	_spawn_dust(landing_pos, telegraph_dust_size, telegraph_dust_size,
		dust_opacity * 0.7, telegraph_dust_duration)


func _spawn_one_debris_delayed(landing_pos: Vector3, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if _state != State.INTRO:
		return

	var pebble := _make_pebble_instance(debris_scene, 0.06, 0.14)
	add_child(pebble)
	_telegraph_debris.append(pebble)

	if pebble is Node3D:
		var off := Vector3(
			randf_range(-debris_scatter, debris_scatter),
			debris_drop_height + randf_range(0.0, debris_drop_height * 0.4),
			randf_range(-debris_scatter, debris_scatter)
		)
		(pebble as Node3D).global_position = landing_pos + off
		# Zufällige Startrotation, damit nicht alle gleich aussehen (v.a. bei debris_scene).
		(pebble as Node3D).rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

	if pebble is RigidBody3D:
		var rb := pebble as RigidBody3D
		rb.freeze = false
		rb.sleeping = false
		rb.apply_torque_impulse(Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)))
		rb.apply_central_impulse(Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2)))
		_settle_pebble(rb)


## Liefert einen fallfähigen RigidBody3D — aus debris_scene (auto-gewrappt,
## falls der Root nur ein Mesh ist) oder prozedural als Fallback.
func _make_pebble_instance(scene: PackedScene, size_min: float, size_max: float) -> Node:
	if scene != null:
		var inst := scene.instantiate()
		if inst is RigidBody3D:
			var rb := inst as RigidBody3D
			rb.freeze = false
			rb.sleeping = false
			if rb.collision_mask == 0:
				rb.collision_mask = debris_collision_mask
			return rb
		return _wrap_mesh_in_rigidbody(inst)
	return _make_procedural_pebble(size_min, size_max)


func _wrap_mesh_in_rigidbody(visual: Node) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 0                       # blockiert nichts (auch die Jagd nicht)
	body.collision_mask = debris_collision_mask    # fällt aber auf den Boden
	body.continuous_cd = true
	body.add_child(visual)
	if visual is Node3D:
		(visual as Node3D).transform = Transform3D.IDENTITY

	var mesh_inst := visual as MeshInstance3D
	if mesh_inst == null:
		mesh_inst = _find_first_mesh(visual)

	var col := CollisionShape3D.new()
	if mesh_inst != null and mesh_inst.mesh != null:
		col.shape = _convex_for(mesh_inst.mesh)
	else:
		var s := SphereShape3D.new()
		s.radius = 0.1
		col.shape = s
	body.add_child(col)
	return body


## Convex-Shape eines Meshes — einmal berechnet (ohne Simplify), dann gecacht
## und über alle Steine geteilt. Verhindert den Hull-Rechen-Ruckler beim Shatter.
func _convex_for(mesh: Mesh) -> Shape3D:
	if mesh == null:
		var s := SphereShape3D.new()
		s.radius = 0.1
		return s
	if _convex_cache.has(mesh):
		return _convex_cache[mesh]
	var shape: Shape3D = mesh.create_convex_shape()   # simplify=false → schnell
	_convex_cache[mesh] = shape
	return shape


func _prewarm_debris() -> void:
	# Convex-Hulls der Debris-Meshes zur Ladezeit berechnen (statt im Gameplay),
	# damit schon der erste Shatter absolut ruckelfrei ist.
	for scene in [debris_scene, shatter_debris_scene]:
		if scene == null:
			continue
		var inst :Variant= scene.instantiate()
		var mesh_inst := inst as MeshInstance3D
		if mesh_inst == null:
			mesh_inst = _find_first_mesh(inst)
		if mesh_inst != null and mesh_inst.mesh != null:
			_convex_for(mesh_inst.mesh)
		inst.free()


func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


func _make_procedural_pebble(size_min: float, size_max: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = debris_collision_mask
	body.continuous_cd = true

	var size: float = randf_range(size_min, size_max)
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.48, 0.46, 0.43)
	mat.roughness = 1.0
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3.ONE * size
	col.shape = box_shape
	body.add_child(col)

	body.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	return body


func _settle_pebble(body: RigidBody3D) -> void:
	await get_tree().create_timer(debris_settle_time).timeout
	if not is_instance_valid(body):
		return
	# Nach dem Setzen: einfrieren + Kollision aus → reine Deko, billig, keine Jagd-Störung.
	body.freeze = true
	for c in body.get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)


func _free_after(node: Node, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(node):
		node.queue_free()


# ─── Dust ──────────────────────────────────────────────────────────

func _spawn_dust(world_pos: Vector3, span: float, height: float, opacity: float, duration: float) -> void:
	# Adaptiert aus CrumbleWall._emit_dust — Quads + Volume-Shader.
	if dust_shader == null:
		push_warning("BoulderChaseDirector: dust_shader nicht gesetzt — Staub übersprungen.")
		return

	var root := Node3D.new()
	root.name = "BoulderDust"
	add_child(root)
	root.global_position = world_pos

	var materials: Array[ShaderMaterial] = []
	for i in range(dust_billboard_count):
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(span, height)
		quad.mesh = mesh
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat := ShaderMaterial.new()
		mat.shader = dust_shader
		mat.set_shader_parameter("opacity", opacity)
		mat.set_shader_parameter("noise_offset", Vector2(randf() * 10.0, randf() * 10.0))
		quad.material_override = mat
		materials.append(mat)

		quad.position = Vector3(
			randf_range(-span, span) * 0.15,
			randf_range(-height, height) * 0.1,
			randf_range(-span, span) * 0.15
		)
		root.add_child(quad)

	var tween := create_tween()
	tween.set_parallel(true)
	for mat in materials:
		tween.tween_method(
			func(v: float): mat.set_shader_parameter("progress", v),
			0.0, 1.0, duration
		)
	tween.tween_property(root, "global_position",
		world_pos + Vector3(0.0, dust_rise_height, 0.0), duration)
	tween.chain().tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
	)


# ─── FX-Helfer ─────────────────────────────────────────────────────

func _boulder_landing_fx(landing_pos: Vector3) -> void:
	if GameEffects and landing_hitstop > 0.0:
		GameEffects.hitstop(landing_hitstop)
	_camera_shake(landing_shake_strength, landing_shake_duration)
	_spawn_dust(landing_pos, landing_dust_size, landing_dust_size, dust_opacity, landing_dust_duration)
	_play_sfx(impact_sound, landing_pos, impact_volume_db)


func _camera_shake(strength: float, duration: float) -> void:
	# Bevorzugt den vorhandenen SpringArm-Shake des Players; sonst GameEffects.
	_resolve_player()
	var arm: Node = _player.get_node_or_null("SpringArm3D") if _player else null
	if arm and arm.has_method("shake"):
		arm.shake(strength, duration)
	elif GameEffects:
		GameEffects.shake(strength, duration)


# ─── Helpers ───────────────────────────────────────────────────────

func _boulder_landing_point() -> Vector3:
	if boulder:
		return boulder.global_position
	if boulder_path_follow:
		return boulder_path_follow.global_position
	return Vector3.ZERO


func _flag_name() -> String:
	return "boulder_chase_cleared_" + chase_id


func _flag_cleared() -> bool:
	return GameManager != null and GameManager.get_flag(_flag_name())


func _enter_dormant() -> void:
	_state = State.DORMANT
	if trigger_area:
		trigger_area.monitoring = false
	if boulder:
		boulder.hide_boulder()


func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var pm := get_node_or_null("/root/PlayerManager")
	if pm != null:
		_player = pm.player_instance
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		_vector_anchor = _player.get_node_or_null("VectorAnchorComponent")


func _face_player_at_boulder() -> void:
	if _player == null or boulder == null or not _player.has_method("cinematic_face"):
		return
	var dir: Vector3 = boulder.global_position - _player.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.RIGHT
	_player.cinematic_face(dir.normalized())

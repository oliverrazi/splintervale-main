extends Node
class_name FinisherDirector

signal finisher_complete

@export_group("Roar (Phase 0)")
@export var roar_anim: String = "NormalRoar"
@export var roar_delay: float = 0.5       # wartet VOR allem
@export var roar_duration: float = 1.5    # gesamte Phase NACH Delay
@export var roar_sfx: AudioStream
@export var roar_sfx_volume_db: float = 1.0
@export var roar_shake_strength: float = 0.1
@export var roar_shake_duration: float = 0.3

@export_group("Player Setup (Phase 0)")
@export var setup_offset: Vector3 = Vector3(-1.0, 0.0, 0.0)  # relativ zum Oger, -X = links
@export var setup_jump_time: float = 0.7
@export var setup_jump_arc_height: float = 0.2
@export var setup_jump_held_frame: int = 93


@export_group("Slams (Phase 1-3)")
@export var slam_dodge_distance: float = 1.0
@export var slam_step_back_distance: float = 0.5
@export var slam_impact_time: float = 0.55     # Anim-Sekunde, an der die Keule aufprallt

@export var slam_anim_speed: float = 2.25      # Oger-Slam schneller abspielen
@export var slam_dodge_delay: float = 0.4     # Player reagiert leicht verzögert
@export var slam_dodge_move_time: float = 0.25 # Dauer der Dodge-Bewegung

@export var slam_max_wait: float = 2.5
@export var slam_impact_forward: float = 1.2   # Wo vor dem Oger die VFX spawnt
@export var slam1_boss_step: float = 0.4       # Oger-Bewegung in Schritt-Distanz
@export var slam2_boss_step: float = 0.4
@export var slam3_boss_step: float = 0.5
@export var slam_end_sfx: AudioStream
@export var slam_end_sfx_volume_db: float = 0.0

@export_group("Player Attacks (Phase 5-7)")
@export var attack_setup_delay: float = 0.1
@export var attack_first_impact_delay: float = 0.18  # Hit 1 visuell → Stagger 1
@export var attack_second_impact_delay: float = 0.18
@export var attack_third_impact_delay: float = 0.22 
@export var attack_combo_chain_delay: float = 0.08   # nach Stagger 1 → Hit 2 buffern
@export var stagger_distance: float = 0.5
@export var stagger_tween_time: float = 0.35
@export var stagger_max_wait: float = 2.0
@export var attack_third_step_distance: float = 0.6   # größerer Schritt
@export var attack_third_stagger_distance: float = 0.9 

@export_group("Finisher Strike (Phase 8-9)")
@export var dive_apex_wait: float = 0.3
@export var dive_complete_wait: float = 2.2
@export var dive_sfx_delay: float = 0.9
@export var dive_freeze_frame: int = 91


@export var jump_back_distance: float = 1.5
@export var jump_back_h_force: float = 3.0
@export var jump_back_up_force: float = 3.0
@export var jump_back_held_frame: int = 93
@export var jump_back_duration: float = 0.9


@export_group("Finisher Anchor")
@export var finisher_anchor_offset: Vector3 = Vector3.ZERO  # optionaler Versatz vom Boss-Spawn
@export var boss_walk_anim: String = "Run"
@export var boss_walk_anim_speed: float = 3.0
@export var boss_walk_speed: float = 3.0  # m/s
@export var boss_walk_min_distance: float = 0.15


@export_group("Outro")
@export var outro_song: AudioStream
@export var outro_volume_db: float = 0.0

@export_group("Camera")
@export var cam_fov: float = 18.0
@export var cam_blend_time: float = 2.0
@export var cam_pitch_up_degrees: float = 2.0

@export var cam_follow_player: bool = true
@export var cam_follow_lerp_speed: float = 5.0
@export var cam_follow_offset: Vector3 = Vector3.ZERO
@export var cam_follow_lock_y: bool = true

@export var cinematic_player_y_offset: float = 0.05

@export_group("Finisher Strike Sounds")
@export var dive_sfx_a: AudioStream
@export var dive_sfx_b: AudioStream
@export var dive_sfx_a_volume_db: float = 0.0
@export var dive_sfx_b_volume_db: float = 0.0

var _boss: Node3D
var _player: Node3D
var _cs_mount: Node3D = null
var _cs_cam: Camera3D = null
var _prev_cam: Camera3D = null

var _finisher_anchor: Vector3 = Vector3.ZERO


var _boss_face_player_active: bool = false
var _camera_follow_active: bool = false
var _camera_follow_base_offset: Vector3 = Vector3.ZERO
var _camera_fixed_y: float = 0.0

@export var attack_step_forward_distance: float = 0.4
@export var attack_step_forward_time: float = 0.15

func _process(_delta: float) -> void:
	_update_cinematic_camera_pan(_delta)
	
	if not _boss_face_player_active: return
	if _boss == null or not is_instance_valid(_boss): return
	if _player == null or not is_instance_valid(_player): return
	if not _boss.has_method("_face_direction"): return
	
	var d := _player.global_position - _boss.global_position
	d.y = 0.0
	if d.length() > 0.001:
		_boss._face_direction(d.normalized())


var _scene_floor_y: float = 0.0

func start_finisher(boss: Node3D, player: Node3D) -> void:
	_boss = boss
	_player = player
	if _boss == null or _player == null:
		finisher_complete.emit()
		return
		
	_scene_floor_y = _player.global_position.y
	
	if "_spawn_position" in _boss:
		_finisher_anchor = _boss._spawn_position + finisher_anchor_offset
	else:
		_finisher_anchor = _boss.global_position + finisher_anchor_offset
	_finisher_anchor.y = _scene_floor_y
	
		
	_player.set_cinematic_mode(true)
	_setup_camera()
	_boss_face_player_active = true
	await _phase_roar()
	await _phase_boss_walk_to_anchor() 
	_play_outro()
	await _phase_slam("FinisherSlam1", slam1_boss_step, 1)
	await _phase_slam("FinisherSlam2", slam2_boss_step, 1)
	await _phase_slam("FinisherSlam1", slam2_boss_step, 1)
	await _phase_slam("FinisherSlam2", slam2_boss_step, -1)
	await _phase_slam("FinisherSlam1", slam3_boss_step, 1)   # Player taumelt rückwärts statt seitlich
	await _phase_exhausted()
	#await _phase_player_attack(1)
	await _phase_player_combo()
	await _phase_fall_on_back()
	await _phase_vector_dive()
	await _phase_player_jumpback()
	await _phase_oger_death()
	_teardown_camera()
	
	if _player and is_instance_valid(_player):
		_player.set_cinematic_mode(false)
		
	finisher_complete.emit()

# --- Phasen ---

func _play_boss_anim_force(anim_name: StringName, speed: float = 1.0) -> float:
	if _boss == null:
		push_warning("FinisherDirector: Kein Boss gesetzt.")
		return 0.0

	if _boss.anim_player == null:
		push_warning("FinisherDirector: Boss hat keinen anim_player.")
		return 0.0

	var ap: AnimationPlayer = _boss.anim_player

	if not ap.has_animation(anim_name):
		push_warning("FinisherDirector: Boss-Animation fehlt: %s" % String(anim_name))
		return 0.0

	var anim: Animation = ap.get_animation(anim_name)
	var anim_length := anim.length

	print(
		"Roar anim found: ",
		String(anim_name),
		" | length: ",
		anim_length,
		" | tracks: ",
		anim.get_track_count()
	)

	ap.stop()
	ap.play(anim_name, 0.0, speed, false)
	ap.advance(0.0)

	await get_tree().process_frame

	print(
		"After play | current: ",
		ap.current_animation,
		" | playing: ",
		ap.is_playing(),
		" | pos: ",
		ap.current_animation_position
	)

	return anim_length / abs(speed)

func _phase_roar() -> void:
	_boss_face_player_active = false
	
	# Player-Ziel: anchor + setup_offset (FEST, nicht boss-relativ).
	# Damit ist die Player-Endposition unabhängig davon wo der Boss
	# beim Trigger gerade stand.
	var setup_target := _finisher_anchor + setup_offset
	setup_target.y = _scene_floor_y + cinematic_player_y_offset
	var setup_start := _player.global_position
	
	# Player schaut zum Anchor (= wo der Boss nach dem Walk sein wird)
	var to_anchor := _finisher_anchor - setup_target
	to_anchor.y = 0.0
	var flip := to_anchor.x < 0.0
	if to_anchor.length() > 0.001:
		_player.cinematic_face(to_anchor.normalized())
	
	var jump_tween := create_tween()
	jump_tween.tween_method(func(t: float):
		if not is_instance_valid(_player) or not is_instance_valid(_boss): return
		var horiz: Vector3 = setup_start.lerp(setup_target, t)
		var arc := 4.0 * setup_jump_arc_height * t * (1.0 - t)
		_player.global_position = horiz + Vector3(0, arc, 0)
		if "velocity" in _player:
			_player.velocity = Vector3.ZERO
		_player.cinematic_show_frame(setup_jump_held_frame, flip)
	, 0.0, 1.0, setup_jump_time)
	
	if roar_delay > 0.0:
		await get_tree().create_timer(roar_delay).timeout
	
	if not String(roar_anim).is_empty():
		_play_boss_anim_force(roar_anim)
	if roar_sfx != null:
		_play_sfx_at_boss(roar_sfx, roar_sfx_volume_db)
	if _boss.has_method("_shake_camera"):
		_boss._shake_camera(roar_shake_strength, roar_shake_duration)
	
	await get_tree().create_timer(roar_duration).timeout
	
	if jump_tween.is_running():
		await jump_tween.finished
	
	# Final-Snap auf den festen Anchor-Punkt
	_player.global_position = setup_target
	if "velocity" in _player:
		_player.velocity = Vector3.ZERO
	
	# Player schaut Richtung Anchor (Boss wird gleich dorthin laufen)
	var face_dir := _finisher_anchor - _player.global_position
	face_dir.y = 0.0
	if face_dir.length() > 0.001:
		_player.cinematic_face(face_dir.normalized())
		

func _phase_boss_walk_to_anchor() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	
	var walk_target: Vector3 = _finisher_anchor
	walk_target.y = _boss.global_position.y
	
	var to_anchor := walk_target - _boss.global_position
	to_anchor.y = 0.0
	var dist := to_anchor.length()
	
	if dist < boss_walk_min_distance:
		_boss_face_player_active = true
		return
	
	# Boss einfrieren: stoppt _physics_process und Collision, damit der Tween
	# nicht mit move_and_slide() um die Position kämpft. Sonst bleibt der
	# Boss bei großer Distanz nach einem Schritt hängen.
	if _boss.has_method("set_cinematic_freeze"):
		_boss.set_cinematic_freeze(true)
	
	_boss_face_player_active = false
	if _boss.has_method("_face_direction"):
		_boss._face_direction(to_anchor.normalized())
	
	if _boss.has_method("cinematic_play_anim"):
		_boss.cinematic_play_anim(boss_walk_anim, boss_walk_anim_speed)
	
	var walk_time: float = dist / max(boss_walk_speed, 0.1)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(_boss, "global_position", walk_target, walk_time)
	await tween.finished
	
	# Sauberer Endpunkt
	_boss.global_position = walk_target
	
	# Boss wieder freigeben - die Slam-Phasen brauchen physics_process zurück
	if _boss.has_method("set_cinematic_freeze"):
		_boss.set_cinematic_freeze(false)
	
	if _boss.has_method("_face_direction"):
		var to_player := _player.global_position - _boss.global_position
		to_player.y = 0.0
		if to_player.length() > 0.001:
			_boss._face_direction(to_player.normalized())
	
	_boss_face_player_active = true


func _phase_slam(anim_name: String, boss_step: float, dodge_side: int) -> void:
	# Boss-Tracking erst aus, NACHDEM wir das Target nochmal aktiv gesetzt
	# haben. _face_direction respektiert die Boss-eigene Facing-Konvention,
	# look_at nicht.
	var aim_dir: Vector3 = _to_player_dir()
	if aim_dir.length() > 0.001 and _boss.has_method("_face_direction"):
		_boss._face_direction(aim_dir)
	_boss_face_player_active = false
	
	var anim_speed: float = max(slam_anim_speed, 0.01)
	var impact_wait: float = slam_impact_time / anim_speed
	_boss.cinematic_play_anim(anim_name, anim_speed)
	
	# Player-Dodge
	var dodge_dir: Vector3
	var dodge_dist: float
	if dodge_side != 0:
		dodge_dir = _side_dir(dodge_side)
		dodge_dist = slam_dodge_distance
	else:
		dodge_dir = -aim_dir
		dodge_dist = slam_step_back_distance
	
	var safe_dodge_delay: float = clamp(slam_dodge_delay, 0.0, max(impact_wait - 0.05, 0.0))
	_trigger_cinematic_dodge_delayed(dodge_dir, dodge_dist, safe_dodge_delay)
	
	# Boss vorwärts in die fixierte aim_dir - nicht live _to_player_dir(),
	# sonst läuft er dem schon dodgenden Player hinterher.
	if boss_step > 0.0:
		var boss_target := _boss.global_position + aim_dir * boss_step
		create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
			.tween_property(_boss, "global_position", boss_target, impact_wait)
	
	await get_tree().create_timer(impact_wait).timeout
	await _wait_for_anim(anim_name, slam_max_wait / anim_speed)
	
	if slam_end_sfx != null:
		_play_sfx_at_boss(slam_end_sfx, slam_end_sfx_volume_db)
	
	if _boss.has_method("_shake_camera"):
		_boss._shake_camera(roar_shake_strength, roar_shake_duration)
	
	# Tracking wieder an für die Pose zwischen den Slams
	_boss_face_player_active = true
		
func _trigger_cinematic_dodge_delayed(world_dir: Vector3, distance: float, delay: float) -> void:
	if delay <= 0.0:
		_trigger_cinematic_dodge(world_dir, distance)
		return

	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func():
		if _player == null or not is_instance_valid(_player):
			return
		_trigger_cinematic_dodge(world_dir, distance)
	)

func _phase_exhausted() -> void:
	_boss.cinematic_play_anim("Exhausted", 0.7)
	_player.cinematic_face(_to_boss_dir())
	await _wait_for_anim("Exhausted", 3.0)


func _phase_player_combo() -> void:
	_player.cinematic_face(_to_boss_dir())
	await get_tree().create_timer(attack_setup_delay).timeout

	var sword: SwordComponent = _player.get_node_or_null("SwordComponent") as SwordComponent
	
	var impact_delays := [
		attack_first_impact_delay,
		attack_second_impact_delay,
		attack_third_impact_delay,
	]

	for i in range(3):
		var idx := i + 1


		if i > 0 and sword != null:
			await _wait_for_chain_window_at_step(sword, idx - 1)
		elif i > 0:
			await get_tree().create_timer(attack_combo_chain_delay).timeout

		var step_dist := attack_step_forward_distance
		if i == 2:
			step_dist = attack_third_step_distance

		var step_target := _player.global_position + _to_boss_dir() * step_dist
		create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
			.tween_property(_player, "global_position", step_target, attack_step_forward_time)

		_player.cinematic_sword_attack(idx)
		
		if i > 0 and sword != null:
			await _wait_for_step(sword, idx)

		await get_tree().create_timer(impact_delays[i]).timeout
		_trigger_boss_stagger("StaggerBack%d" % idx)

	await _wait_for_anim("StaggerBack3", stagger_max_wait)

func _wait_for_chain_window_at_step(sword: SwordComponent, expected_step: int, timeout: float = 2.0) -> void:
	var elapsed := 0.0
	while elapsed < timeout:
		if not sword.is_attacking():
			return
		if sword.get_current_step() == expected_step and sword.can_chain():
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		
func _wait_for_step(sword: SwordComponent, expected_step: int, timeout: float = 1.5) -> void:
	var elapsed := 0.0
	while elapsed < timeout:
		if not sword.is_attacking():
			return
		if sword.get_current_step() >= expected_step:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()

func _wait_for_chain_window(sword: SwordComponent, timeout: float = 1.5) -> void:
	var elapsed := 0.0
	while elapsed < timeout:
		if not sword.is_attacking():
			return  # Kein Attack läuft mehr - chain ist verpasst, weitermachen
		if sword.can_chain():
			return  # Window offen, jetzt kann gebuffert werden
		await get_tree().process_frame
		elapsed += get_process_delta_time()

func _trigger_boss_stagger(anim_name: String) -> void:
	_boss.cinematic_play_anim(anim_name, 1.0)
	var back_pos := _boss.global_position + _to_boss_dir() * stagger_distance
	create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
		.tween_property(_boss, "global_position", back_pos, stagger_tween_time)

func _phase_fall_on_back() -> void:
	_boss_face_player_active = false  

	_boss.cinematic_play_anim("FallOnBack", 1.0)
	await _wait_for_anim("FallOnBack", 3.0)
	_boss._shake_camera(roar_shake_strength, roar_shake_duration)


func _phase_vector_dive() -> void:
	_player.cinematic_face(_to_boss_dir())
	
	# Approach-Direction merken, solange Player und Boss klar getrennt sind.
	# JumpBack nutzt diese, weil _to_boss_dir() nach dem Mount unzuverlässig wird
	# (Player exakt über Boss -> XZ-Distanz 0 -> Rückfall auf Vector3.FORWARD).
	_finisher_approach_dir = -_to_boss_dir()
	
	var dive_strike: DiveStrikeComponent = _get_dive_strike()
	if dive_strike != null:
		dive_strike.cinematic_mode = true
	
	# Launch + Strike - Player braucht hier seine Physik
	if _player.vector_anchor and _player.vector_anchor.has_method("cinematic_launch_at"):
		_player.vector_anchor.cinematic_launch_at(_boss)
	await get_tree().create_timer(dive_apex_wait).timeout
	if _player.vector_anchor and _player.vector_anchor.has_method("try_dive_strike"):
		_player.vector_anchor.try_dive_strike()
	
	_schedule_dive_sfx()
	
	# Auf Impact warten
	if dive_strike != null:
		await dive_strike.dive_completed
	else:
		await get_tree().create_timer(dive_complete_wait).timeout
	
	# Übergabe: Boss + Player einfrieren, Player auf Mount-Position
	_boss.set_cinematic_freeze(true)
	
	var mount_pos: Vector3 = _get_mount_position()
	var freeze_flip: bool = _to_boss_dir().x < 0.0
	_player.global_position = mount_pos
	_player.cinematic_show_frame(dive_freeze_frame, freeze_flip)
	
	# Hold-Phase
	var elapsed := 0.0
	while elapsed < dive_complete_wait:
		if is_instance_valid(_player):
			_player.global_position = mount_pos
			if "velocity" in _player:
				_player.velocity = Vector3.ZERO
			_player.cinematic_show_frame(dive_freeze_frame, freeze_flip)
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	
	# Player wieder beweglich machen - aber Boss bleibt eingefroren,
	# er liegt ja und soll während der Death-Phase auch liegen bleiben.
	if dive_strike != null:
		dive_strike.cinematic_mode = false



var _finisher_approach_dir: Vector3 = Vector3.FORWARD


func _phase_player_jumpback() -> void:
	# Gespeicherte Approach-Direction nutzen. _to_boss_dir() wäre hier
	# unzuverlässig, weil Player und Boss noch auf der gleichen XZ stehen.
	var back_dir: Vector3 = _finisher_approach_dir
	if back_dir.length() < 0.001:
		back_dir = Vector3.FORWARD
	
	_player.cinematic_jump_back(back_dir, jump_back_h_force, jump_back_up_force)
	var elapsed := 0.0
	while elapsed < jump_back_duration:
		_player.cinematic_show_frame(jump_back_held_frame, back_dir.x < 0.0)
		await get_tree().process_frame
		elapsed += get_process_delta_time()

func _schedule_dive_sfx() -> void:
	# Feuer-und-vergiss SFX-Timing, blockiert die Phase nicht
	var t := get_tree().create_timer(dive_sfx_delay)
	t.timeout.connect(func():
		if dive_sfx_a != null:
			_play_sfx_at_boss(dive_sfx_a, dive_sfx_a_volume_db)
		if dive_sfx_b != null:
			_play_sfx_at_boss(dive_sfx_b, dive_sfx_b_volume_db)
	)


@export var dive_mount_height: float = 0.5


func _get_mount_position() -> Vector3:
	return Vector3(
		_boss.global_position.x,
		_scene_floor_y + dive_mount_height,
		_boss.global_position.z
	)

func _get_dive_strike() -> DiveStrikeComponent:
	if _player == null:
		return null
	if "dive_strike" in _player and _player.dive_strike != null:
		return _player.dive_strike as DiveStrikeComponent
	return _player.get_node_or_null("DiveStrikeComponent") as DiveStrikeComponent
		


func _phase_oger_death() -> void:
	_boss.cinematic_play_anim("FinisherDeath", 1.0)
	await _wait_for_anim("FinisherDeath", 4.0)

# --- Helpers ---

func _play_boss_anim_checked(anim_name: StringName, speed: float = 1.0) -> bool:
	if _boss == null:
		push_warning("FinisherDirector: Kein Boss gesetzt.")
		return false

	if _boss.anim_player == null:
		push_warning("FinisherDirector: Boss hat keinen anim_player.")
		return false

	if not _boss.anim_player.has_animation(anim_name):
		push_warning("FinisherDirector: Boss-Animation fehlt: %s" % String(anim_name))
		return false

	if not _boss.has_method("cinematic_play_anim"):
		push_warning("FinisherDirector: Boss hat keine Methode cinematic_play_anim().")
		return false

	_boss.cinematic_play_anim(String(anim_name), speed)

	await get_tree().process_frame

	if not _boss.anim_player.is_playing():
		push_warning("FinisherDirector: Animation wurde nicht gestartet: %s" % String(anim_name))
		return false

	if StringName(_boss.anim_player.current_animation) != anim_name:
		push_warning(
			"FinisherDirector: Falsche Animation läuft. Erwartet: %s | Läuft: %s" %
			[String(anim_name), String(_boss.anim_player.current_animation)]
		)
		return false

	return true

func _play_sfx_at_boss(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null or _boss == null:
		return

	var audio := AudioStreamPlayer3D.new()
	audio.stream = stream
	audio.volume_db = volume_db
	_boss.add_child(audio)
	audio.global_position = _boss.global_position
	audio.play()
	audio.finished.connect(audio.queue_free)

func _trigger_cinematic_dodge(world_dir: Vector3, distance: float) -> void:
	if _player.dodge_component and _player.dodge_component.has_method("cinematic_dodge"):
		_player.dodge_component.cinematic_dodge(world_dir)

	var dodge_target: Vector3 = _player.global_position + world_dir.normalized() * distance

	create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
		.tween_property(_player, "global_position", dodge_target, slam_dodge_move_time)

func _wait_for_anim(anim_name: String, fallback_time: float = 2.0) -> void:
	if _boss.anim_player == null:
		await get_tree().create_timer(fallback_time).timeout
		return
	if not _boss.anim_player.is_playing() or _boss.anim_player.current_animation != anim_name:
		await get_tree().create_timer(fallback_time).timeout
		return
	var elapsed := 0.0
	while _boss.anim_player.is_playing() and _boss.anim_player.current_animation == anim_name:
		if elapsed >= fallback_time: return
		await get_tree().process_frame
		elapsed += get_process_delta_time()

func _play_outro() -> void:
	if outro_song == null:
		return
	if _boss and _boss.has_method("play_outro_music"):
		_boss.play_outro_music(outro_song)

func _to_boss_dir() -> Vector3:
	var d := _boss.global_position - _player.global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD

func _to_player_dir() -> Vector3:
	return -_to_boss_dir()

func _side_dir(sign_value: int) -> Vector3:
	var fwd := _to_boss_dir()
	return Vector3(fwd.z, 0.0, -fwd.x) * sign(sign_value)

func _setup_camera() -> void:
	_prev_cam = _boss.get_viewport().get_camera_3d()

	if _prev_cam == null or not is_instance_valid(_prev_cam):
		return

	_cs_mount = Node3D.new()
	_boss.get_tree().current_scene.add_child(_cs_mount)

	_cs_cam = Camera3D.new()
	_cs_mount.add_child(_cs_cam)

	# Exakt die aktuelle Spielkamera übernehmen.
	_cs_cam.global_transform = _prev_cam.global_transform
	_cs_cam.fov = _prev_cam.fov
	_cs_cam.near = _prev_cam.near
	_cs_cam.far = _prev_cam.far
	_cs_cam.current = true

	if abs(cam_pitch_up_degrees) > 0.001:
		var rot := _cs_cam.rotation_degrees
		rot.x += cam_pitch_up_degrees
		_cs_cam.rotation_degrees = rot

	_camera_follow_active = cam_follow_player
	_camera_follow_base_offset = _cs_cam.global_position - _player.global_position
	_camera_fixed_y = _cs_cam.global_position.y

	var t := create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_IN_OUT)

	t.tween_property(_cs_cam, "fov", cam_fov, cam_blend_time)
	
func _teardown_camera() -> void:
	_camera_follow_active = false

	if _cs_cam == null or not is_instance_valid(_cs_cam):
		return

	if _prev_cam and is_instance_valid(_prev_cam):
		var t := create_tween()
		t.set_parallel(true)
		t.set_trans(Tween.TRANS_SINE)
		t.set_ease(Tween.EASE_IN_OUT)

		t.tween_property(_cs_cam, "global_transform", _prev_cam.global_transform, 0.8)
		t.tween_property(_cs_cam, "fov", _prev_cam.fov, 0.8)

		await t.finished
		_prev_cam.make_current()

	if _cs_mount and is_instance_valid(_cs_mount):
		_cs_mount.queue_free()

	_cs_mount = null
	_cs_cam = null
	
	
	

func _update_cinematic_camera_pan(delta: float) -> void:
	if not _camera_follow_active:
		return
	if _cs_cam == null or not is_instance_valid(_cs_cam):
		return
	if _player == null or not is_instance_valid(_player):
		return

	var target_pos := _player.global_position + _camera_follow_base_offset + cam_follow_offset

	if cam_follow_lock_y:
		target_pos.y = _camera_fixed_y

	var weight := 1.0 - exp(-cam_follow_lerp_speed * delta)
	_cs_cam.global_position = _cs_cam.global_position.lerp(target_pos, weight)

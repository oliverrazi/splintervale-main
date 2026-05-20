extends CharacterBody3D
class_name OgerBoss

## Oger-Miniboss — 3D-Modell im SubViewport, AnimationPlayer-basiert.
## Übernimmt Infrastruktur-Pattern aus Enemy (Freeze, Terrain-Await, Gravity,
## Audio, Health), aber eigene State-Machine wegen SubViewport-Architektur.

# === REFERENCES ===
@onready var rotator: Node3D = $RenderViewport/BossRotator
var anim_player: AnimationPlayer

@onready var boss_sprite: SmoothPixelSprite3D = $BossSprite
@onready var render_viewport: SubViewport = $RenderViewport

# === HEALTH ===
@export_group("Health")
@export var max_health: int = 200

@export var max_armor: int = 50      # nur per Dive Strike abbaubar
var _armor: int

@export var body_hit_radius: float = 0.5

# === ANIMATION ===
@export_group("Animation")
@export var idle_anim: String = "Idle"
@export var walk_anim: String = "Walk"
@export var slam_anim: String = "Groundslam"
@export var idle_anim_speed: float = 1.0
@export var walk_anim_speed: float = 2.5
@export var slam_anim_speed: float = 1.0

@export_group("Armor Break Sequence")
@export var armor_break_sit_anim: String = "ArmorBreakSit"
@export var armor_break_standup_anim: String = "ArmorBreakStandup"
@export var armor_break_roar_anim: String = "ArmorBreakRoar"
@export var armor_break_sit_time: float = 2.0
@export var armor_break_standup_time: float = 1.2
@export var armor_break_roar_time: float = 1.2
@export var armor_break_roar_vfx_time: float = 0.25   # ab Roar-Start bis Cone-VFX
@export var roar_vfx_scene: PackedScene              # Cone Richtung Kamera (baust du)
@export var roar_vfx_height: float = 1.0
@export var roar_sound: AudioStream
var _roar_vfx_done: bool = false

@export_group("Armor Break Cutscene")
@export var phase2_boss_music: AudioStream
@export var roar_shake_strength: float = 0.22
@export var roar_shake_duration: float = 0.7
@export var cutscene_zoom: float = 0.9    
var _phase2_zone = null



@export_group("Armor Break Cutscene Camera")
@export var cutscene_cam_distance: float = 6.6     # Abstand zum Oger
@export var cutscene_cam_focus_height: float = 1.1 # Blickpunkt am Oger (Brust)
@export var cutscene_cam_move_time: float = 0.7


@export var armor_break_player_up: float = 3.0
@export var armor_break_player_knockback: float = 4.0   # großer Abprall, raus aus dem Bild
@export var armor_break_land_confirm: float = 0.12       # Boden muss kurz bestätigt sein
@export var armor_break_wait_max: float = 3.0            # Safety, falls er nie landet
var _player_locked: bool = false
var _land_confirm: float = 0.0
var _armor_break_wait_clock: float = 0.0

var _cs_mount: Node3D = null
var _cs_cam: Camera3D = null
var _prev_cam: Camera3D = null
var _roar_shake_time: float = 0.0

@export_group("Facing Style")
@export var angled_sideview: bool = true
@export_range(0.0, 60.0, 1.0) var sideview_pull_deg: float = 25.0
@export var facing_yaw_offset_deg: float = 0.0

@export var hit_hitstop_duration: float = 0.15

# === MOVEMENT ===
@export_group("Movement")
@export var move_speed: float = 1.0            # langsam — schwer wegen Rüstung
@export var detection_range: float = 9.0
@export var lose_interest_range: float = 12.0
@export var attack_range: float = 1.8          # ab hier Ground Slam
@export var snap_8_directions: bool = true

# === FOOTSTEPS ===
@export_group("Footsteps")
@export var footstep_sound: AudioStream
@export var step_interval: float = 0.55        # Sekunden zwischen Schritten
@export var step_shake_strength: float = 0.05
@export var step_shake_duration: float = 0.08

# === GROUND SLAM ===
@export_group("Ground Slam")
@export var slam_damage: int = 20
@export var slam_radius: float = 2.5
@export var slam_windup_time: float = 1.5      # Gesamtdauer Ausholen (Keule hoch + hinter Kopf)
@export var slam_impact_time: float = 1.35     # Zeitpunkt, an dem die Keule auftrifft
@export var slam_recovery_time: float = 1.2    # Erholung nach dem Schlag
@export var slam_shake_strength: float = 0.6
@export var slam_shake_duration: float = 0.35
@export var slam_sound: AudioStream
@export var slam_vfx_scene: PackedScene        # optional; sonst prozedural
@export var slam_impact_forward_offset: float = 1.2

@export var slam_vfx_lifetime: float = 2.0

@export_group("Armored Charge")
@export var charge_telegraph_anim: String = "ArmoredTelegraph"
@export var charge_dash_anim: String = "ArmoredDash_001"                   
@export var charge_telegraph_anim_speed: float = 1.0
@export var charge_dash_anim_speed: float = 2.5
@export var charge_chance: float = 0.4
@export var charge_min_distance: float = 1.5
@export var charge_max_distance: float = 8.0
@export var charge_decision_interval: float = 1.0
@export var charge_cooldown_time: float = 6.0
@export var charge_telegraph_time: float = 1.4    # Dauer 3 Klopfer — an Anim messen
@export var charge_speed: float = 6.0
@export var charge_max_duration: float = 1.1
@export var charge_hit_range: float = 1.4
@export var charge_damage: int = 28
@export var charge_player_knockback: float = 9.0
@export var charge_recovery_time: float = 2.2 

@export var fx_local_height: float = 1.0      # Brusthöhe im Modell-Maßstab
@export var hit_refractory: float = 0.15
var _hit_gate_until: float = 0.0

@export_group("Charge SFX")
@export var charge_knock_sound: AudioStream
@export var charge_knock_times: Array[float] = [0.15, 0.6, 1.05]  # rel. Telegraph-Start
@export var charge_step_sound: AudioStream      # leer → footstep_sound
@export var charge_step_interval: float = 0.18  # schneller als normaler Schritt

@export_group("Impact VFX Placement")
@export var impact_vfx_scale: float = 1.0
@export var impact_vfx_lifetime: float = 0.5
@export var impact_vfx_delay := 0.0

var _knock_index: int = 0
var _charge_step_timer: float = 0.0

var _charge_dir: Vector3 = Vector3.ZERO
var _charge_hit_done: bool = false
var _charge_cooldown: float = 0.0
var _charge_decision_timer: float = 0.0
var _charge_time: float = 0.0

var _charge_thrust: Node3D = null

@export_group("Charge Thrust VFX")
@export var charge_thrust_scene: PackedScene
@export var charge_thrust_forward: float = 1.0
@export var charge_thrust_height: float = 0.4

# === FREEZE (Terrain3D Collision Optimization) ===
@export_group("Freeze")
@export var freeze_distance: float = 22.0
@export var unfreeze_distance: float = 20.0

@export_group("Armor Phase")
@export var is_armored: bool = true
@export var impact_vfx_scene: PackedScene        # dein impact3.tscn
@export var impact_vfx_height: float = 0.5       # Trefferhöhe (Brust/Rüstung)
@export var armor_hit_sound: AudioStream
@export var player_bounce_strength: float = 3.0

@export_group("Armor Break")
@export var armor_mesh_names: Array[String] = ["Armor"]
@export var armor_break_sound: AudioStream
@export var armor_break_vfx_scene: PackedScene

@export_group("Armor Break Pieces")
@export var armor_break_scene: PackedScene
@export var armor_break_impulse: float = 3.5
@export var armor_break_up: float = 2.5
@export var armor_break_lifetime: float = 1.0

@export_group("Arena")
@export var arena_radius: float = 12.0
@export var return_speed: float = 0.9 

@export_group("Phase 2")
@export var p2_run_anim: String = "Run"
@export var p2_run_anim_speed: float = 3.0
@export var p2_chase_speed_mult: float = 1.9
@export var p2_slam_speed_mult: float = 1.6

var _slam_windup_t: float
var _slam_impact_t: float
var _slam_recovery_t: float

@export_group("Vector Anchor Block")
@export var vector_block_anim: String = "VectorBlock"
@export var vector_block_anim_speed: float = 1.0
@export var vector_block_time: float = 0.7
@export var vector_block_damage: int = 6
@export var vector_block_sound: AudioStream



@export_group("Boss Presentation")
@export var boss_display_name: String = "Tharok"
@export var boss_bar_scene: PackedScene

@export_group("Boss Music")
@export var boss_music: AudioStream
@export var boss_music_priority: int = 100      # MUSS höher sein als deine Overworld-Zonen
@export var boss_music_crossfade: float = 1.5

var _phase: int = 1

# === STATE ===
enum State { IDLE, CHASE, SLAM_WINDUP, SLAM_RECOVERY, HIT, RETURN,
CHARGE_TELEGRAPH, CHARGE_DASH, CHARGE_RECOVERY,
ARMOR_BREAK_SIT, ARMOR_BREAK_STANDUP, ARMOR_BREAK_ROAR, DEAD }
var _state: State = State.IDLE
var _state_timer: float = 0.0

var _arena_active: bool = false
@onready var _boss_bar: Node = $BossHealthBar 
var _boss_zone = null

var _health: int
var _target: Node3D = null
var _player_ref: Node3D = null
var _spawn_position: Vector3
var _is_frozen: bool = false
var _is_dead: bool = false
var _current_facing_index: int = -1
var _step_timer: float = 0.0
var _slam_time: float = 0.0
var _slam_impact_done: bool = false
var _locked_facing: Vector3 = Vector3.ZERO

var _audio_step: AudioStreamPlayer3D
var _audio_action: AudioStreamPlayer3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


# === LIFECYCLE ===

func _ready() -> void:
	boss_sprite.hframes = 1
	boss_sprite.vframes = 1
	boss_sprite.texture = render_viewport.get_texture()
	
	_health = max_health
	_armor = max_armor
	_spawn_position = global_position
	_player_ref = get_tree().get_first_node_in_group("player")

	add_to_group("enemies")
	_setup_audio()
	_setup_animation()

	# Terrain-Await: Physics erst nach einem Frame, damit Terrain3D-Collision steht
	set_physics_process(false)
	_is_frozen = true
	velocity = Vector3.ZERO
	await get_tree().process_frame
	set_physics_process(true)
	_is_frozen = false
	_enter_idle()


func _setup_animation() -> void:
	if rotator == null:
		push_warning("OgerBoss: BossRotator nicht gefunden")
		return
	anim_player = rotator.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player == null:
		push_warning("OgerBoss: AnimationPlayer nicht gefunden")
		return
	if anim_player.has_animation(idle_anim):
		anim_player.get_animation(idle_anim).loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation(walk_anim):
		anim_player.get_animation(walk_anim).loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation(slam_anim):
		anim_player.get_animation(slam_anim).loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation(charge_telegraph_anim):
		anim_player.get_animation(charge_telegraph_anim).loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation(charge_dash_anim):
		anim_player.get_animation(charge_dash_anim).loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation(p2_run_anim):
		anim_player.get_animation(p2_run_anim).loop_mode = Animation.LOOP_LINEAR
		
	for a in [armor_break_sit_anim, armor_break_standup_anim, armor_break_roar_anim]:
		if anim_player.has_animation(a):
			anim_player.get_animation(a).loop_mode = Animation.LOOP_NONE


func _setup_audio() -> void:
	_audio_step = AudioStreamPlayer3D.new()
	_audio_step.name = "AudioStep"
	_audio_step.max_distance = 25.0
	_audio_step.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_audio_step)

	_audio_action = AudioStreamPlayer3D.new()
	_audio_action.name = "AudioAction"
	_audio_action.max_distance = 30.0
	_audio_action.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_audio_action)


# === PROCESS ===

func _process(_delta: float) -> void:
	_check_freeze_state()
	_update_arena_presentation()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if _is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	
	_charge_cooldown = maxf(_charge_cooldown - delta, 0.0)

	match _state:
		State.IDLE:
			_process_idle(delta)
		State.CHASE:
			_process_chase(delta)
		State.SLAM_WINDUP:
			_process_slam_windup(delta)
		State.SLAM_RECOVERY:
			_process_slam_recovery(delta)
		State.HIT:
			_process_hit(delta)
		State.RETURN:                
			_process_return(delta)
		State.CHARGE_TELEGRAPH:
			_process_charge_telegraph(delta)
		State.CHARGE_DASH:
			_process_charge_dash(delta)
		State.CHARGE_RECOVERY:
			_process_charge_recovery(delta)
		State.ARMOR_BREAK_SIT:
			_process_armor_break_sit(delta)
		State.ARMOR_BREAK_STANDUP:
			_process_armor_break_standup(delta)
		State.ARMOR_BREAK_ROAR:
			_process_armor_break_roar(delta)

	move_and_slide()


# === STATE: IDLE ===

func _enter_idle() -> void:
	_state = State.IDLE
	velocity.x = 0.0
	velocity.z = 0.0
	_play_anim(idle_anim, idle_anim_speed)


func _process_idle(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var p := _get_player()
	if _player_inside_arena(p):
		_target = p
		_enter_chase()


# === STATE: CHASE ===

func _enter_chase() -> void:
	_state = State.CHASE
	_step_timer = 0.0
	if _is_phase2():
		_play_anim(p2_run_anim, p2_run_anim_speed)
	else:
		_play_anim(walk_anim, walk_anim_speed)


func _process_chase(delta: float) -> void:
	var p := _get_player()
	if not _player_inside_arena(p):
		_enter_return()
		return

	var to_player := p.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if dist <= attack_range:
		_enter_slam()
		return

	_charge_decision_timer -= delta
	if _charge_decision_timer <= 0.0:
		_charge_decision_timer = charge_decision_interval
		if _charge_cooldown <= 0.0 \
		and dist >= charge_min_distance and dist <= charge_max_distance:
			if randf() < charge_chance:
				_enter_charge_telegraph()
				return

	var dir := to_player.normalized()
	_face_direction(dir)
	var spd := move_speed * (p2_chase_speed_mult if _is_phase2() else 1.0)
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd

	_step_timer += delta
	if _step_timer >= step_interval:
		_step_timer = 0.0
		_play_sound(_audio_step, footstep_sound, 0.08)
		_shake_camera(step_shake_strength, step_shake_duration)


func _process_return(delta: float) -> void:
	# Player wieder in Arena → sofort weiterjagen
	var p := _get_player()
	if _player_inside_arena(p):
		_target = p
		_enter_chase()
		return

	var to_spawn := _spawn_position - global_position
	to_spawn.y = 0.0
	if to_spawn.length() < 0.3:
		_enter_idle()
		return

	var dir := to_spawn.normalized()
	_face_direction(dir)
	velocity.x = dir.x * return_speed
	velocity.z = dir.z * return_speed

func _enter_return() -> void:
	_state = State.RETURN
	velocity.x = 0.0
	velocity.z = 0.0
	_play_anim(walk_anim, walk_anim_speed)
	
func _apply_hit_juice() -> void:
	if GameEffects:
		GameEffects.hitstop(hit_hitstop_duration)

# === STATE: GROUND SLAM ===

func _enter_slam() -> void:
	_state = State.SLAM_WINDUP
	_slam_time = 0.0
	_slam_impact_done = false
	velocity.x = 0.0
	velocity.z = 0.0
	var m := (p2_slam_speed_mult if _is_phase2() else 1.0)   # >1 = schneller
	_slam_windup_t = slam_windup_time / m
	_slam_impact_t = slam_impact_time / m
	_slam_recovery_t = slam_recovery_time / m
	if _target and is_instance_valid(_target):
		var d := _target.global_position - global_position
		d.y = 0.0
		_locked_facing = d.normalized()
		_face_direction(_locked_facing)
	_play_anim(slam_anim, slam_anim_speed * m)


func _process_slam_windup(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_slam_time += delta
	if not _slam_impact_done and _slam_time >= _slam_impact_t:
		_slam_impact_done = true
		_do_slam_impact()
	if _slam_time >= _slam_windup_t:
		_state = State.SLAM_RECOVERY
		_state_timer = _slam_recovery_t



func _slam_impact_point() -> Vector3:
	var fwd := _locked_facing if _locked_facing.length() > 0.01 else -global_transform.basis.z
	return global_position + fwd * slam_impact_forward_offset

func _do_slam_impact() -> void:
	_spawn_slam_debug_ring(_slam_impact_point())
	_play_sound(_audio_action, slam_sound, 0.05)
	_shake_camera(slam_shake_strength, slam_shake_duration)
	_spawn_slam_vfx()

	# AoE-Schaden: Spieler in Reichweite?
	var p := _get_player()
	if p and is_instance_valid(p):
		var d := p.global_position - _slam_impact_point()
		d.y = 0.0
		if d.length() <= slam_radius and p.has_method("take_damage"):
			p.take_damage(slam_damage, global_position)


func _process_slam_recovery(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_state_timer -= delta
	if _state_timer <= 0.0:
		# Entscheidung: nochmal nah genug → erneut Slam, sonst Chase/Idle
		var p := _get_player()
		if p and is_instance_valid(p):
			var dist := global_position.distance_to(p.global_position)
			if dist <= lose_interest_range:
				_target = p
				_enter_chase()
				return
		_enter_idle()


func _enter_charge_telegraph() -> void:
	_knock_index = 0
	_state = State.CHARGE_TELEGRAPH
	_charge_time = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_play_anim(charge_telegraph_anim, charge_telegraph_anim_speed)

func _process_charge_telegraph(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_charge_time += delta
	# Während der Klopfer den Spieler weiter anvisieren
	var p := _get_player()
	if p and is_instance_valid(p):
		var d := p.global_position - global_position
		d.y = 0.0
		if d.length() > 0.01:
			d = d.normalized()
			_face_direction(d)
			_charge_dir = d
	while _knock_index < charge_knock_times.size() \
	and _charge_time >= charge_knock_times[_knock_index]:
		_play_sound(_audio_action, charge_knock_sound, 0.05)
		#_shake_camera(charge_telegraph_shake, 0.12)
		_knock_index += 1
	if _charge_time >= charge_telegraph_time:
		_enter_charge_dash()

func _enter_charge_dash() -> void:
	_charge_step_timer = 0.0
	_state = State.CHARGE_DASH
	_charge_time = 0.0
	_charge_hit_done = false
	# Richtung JETZT festnageln — committed, dreht nicht mehr nach
	var p := _get_player()
	if p and is_instance_valid(p):
		var d := p.global_position - global_position
		d.y = 0.0
		if d.length() > 0.01:
			_charge_dir = d.normalized()
	_face_direction(_charge_dir)
	_play_anim(charge_dash_anim, charge_dash_anim_speed)
	_spawn_charge_thrust()

func _process_charge_dash(delta: float) -> void:
	_update_charge_thrust()
	_charge_time += delta
	_charge_step_timer += delta
	if _charge_step_timer >= charge_step_interval:
		_charge_step_timer = 0.0
		var s := charge_step_sound if charge_step_sound else footstep_sound
		_play_sound(_audio_step, s, 0.08)
		_shake_camera(step_shake_strength, step_shake_duration)
	
	velocity.x = _charge_dir.x * charge_speed
	velocity.z = _charge_dir.z * charge_speed

	if not _charge_hit_done:
		var p := _get_player()
		if p and is_instance_valid(p):
			var to_p := p.global_position - global_position
			to_p.y = 0.0
			if to_p.length() <= charge_hit_range \
			and _charge_dir.dot(to_p.normalized()) > 0.3:
				_charge_hit_done = true
				if p.has_method("take_damage"):
					p.take_damage(charge_damage, global_position)
				if p.has_method("apply_knockback"):
					p.apply_knockback(global_position, charge_player_knockback)

	if _charge_time >= charge_max_duration or is_on_wall():
		_enter_charge_recovery()

func _enter_charge_recovery() -> void:
	_cleanup_charge_thrust()
	_state = State.CHARGE_RECOVERY
	_state_timer = charge_recovery_time
	_charge_cooldown = charge_cooldown_time
	velocity.x = 0.0
	velocity.z = 0.0
	_play_anim(idle_anim, idle_anim_speed)

func _process_charge_recovery(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_state_timer -= delta
	if _state_timer <= 0.0:
		var p := _get_player()
		if _player_inside_arena(p):
			_target = p
			_enter_chase()
		else:
			_enter_return()
			

func _spawn_charge_thrust() -> void:
	_cleanup_charge_thrust()
	if charge_thrust_scene == null:
		return
	_charge_thrust = charge_thrust_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(_charge_thrust)
	_update_charge_thrust()

func _update_charge_thrust() -> void:
	if _charge_thrust == null or not is_instance_valid(_charge_thrust):
		return
	_charge_thrust.global_position = global_position \
		+ _charge_dir * charge_thrust_forward + Vector3.UP * charge_thrust_height
	_charge_thrust.global_rotation = Vector3(0.0, atan2(_charge_dir.x, _charge_dir.z), 0.0)

func _cleanup_charge_thrust() -> void:
	if _charge_thrust and is_instance_valid(_charge_thrust):
		_charge_thrust.queue_free()
	_charge_thrust = null

# === STATE: HIT (minimal — Oger ist schwer, kaum Reaktion) ===

func _enter_hit() -> void:
	_state = State.HIT
	_state_timer = 0.2


func _process_hit(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_state_timer -= delta
	if _state_timer <= 0.0:
		var p := _get_player()
		if p and is_instance_valid(p):
			_target = p
			_enter_chase()
		else:
			_enter_idle()


# === SLAM VFX (prozedural; Shader inline) ===

func _spawn_slam_vfx() -> void:
	if slam_vfx_scene == null:
		return
	var p := _slam_impact_point()
	_spawn_self_playing_vfx(slam_vfx_scene, Vector3(p.x, p.y + 0.02, p.z), slam_vfx_lifetime)

func _spawn_self_playing_vfx(scene: PackedScene, world_pos: Vector3, lifetime: float, scale: float = 1.0, look_at_pos = null) -> Node3D:
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	get_tree().current_scene.add_child(inst)
	inst.global_position = world_pos
	if scale != 1.0:
		inst.scale = Vector3(scale, scale, scale)
	if look_at_pos != null and inst.global_position.distance_to(look_at_pos) > 0.01:
		inst.look_at(look_at_pos, Vector3.UP)
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		var clip: String = ap.autoplay if ap.autoplay != "" else "impact"
		if ap.has_animation(clip):
			ap.play(clip)
	for ps in inst.find_children("*", "GPUParticles3D", true, false):
		ps.emitting = true
	for ps in inst.find_children("*", "CPUParticles3D", true, false):
		ps.emitting = true
	get_tree().create_timer(lifetime).timeout.connect(func():
		if is_instance_valid(inst): inst.queue_free())
	return inst

func _spawn_roar_vfx() -> void:
	if roar_vfx_scene == null:
		push_warning("OgerBoss: roar_vfx_scene nicht zugewiesen → kein Cone")
		return
	var cam := get_viewport().get_camera_3d()
	var look = cam.global_position if cam else null
	_spawn_self_playing_vfx(roar_vfx_scene,
		global_position + Vector3(0, roar_vfx_height, 0),
		armor_break_roar_time, 1.0, look)

func _on_armored_hit(from_position: Vector3, skip_hitstop: bool = false) -> void:
	_spawn_impact(impact_vfx_scene)
	_play_sound(_audio_action, armor_hit_sound, 0.05)
	if not skip_hitstop: _apply_hit_juice()
	var p := _get_player()
	if p and is_instance_valid(p) and p.has_method("apply_knockback"):
		p.apply_knockback(global_position, player_bounce_strength)


func _player_inside_arena(p: Node3D) -> bool:
	return p != null and is_instance_valid(p) \
		and _spawn_position.distance_to(p.global_position) <= arena_radius

# === FACING ===

func _face_direction(dir: Vector3) -> void:
	if rotator == null or dir.length() < 0.001:
		return
	var angle := atan2(dir.x, dir.z)
	if snap_8_directions:
		var target_index := wrapi(int(round(angle / (PI / 4.0))), 0, 8)
		if target_index != _current_facing_index:
			_current_facing_index = target_index
			rotator.rotation.y = _styled_yaw(target_index * PI / 4.0)
			rotator.reset_physics_interpolation()
	else:
		rotator.rotation.y = _styled_yaw(angle)

func _styled_yaw(raw: float) -> float:
	if not angled_sideview:
		return raw
	var ref := deg_to_rad(facing_yaw_offset_deg)
	var rel := wrapf(raw - ref, -PI, PI)
	rel -= deg_to_rad(sideview_pull_deg) * sin(rel)
	return ref + rel


# === FREEZE SYSTEM (Terrain3D-Collision-Optimierung) ===

func _check_freeze_state() -> void:
	if _in_armor_break():
		return
	if not _player_ref or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player")
		return
	var dist := global_position.distance_to(_player_ref.global_position)
	if _is_frozen:
		if dist < unfreeze_distance:
			_is_frozen = false
			velocity = Vector3.ZERO
			set_physics_process(true)
	else:
		if dist > freeze_distance:
			_is_frozen = true
			velocity = Vector3.ZERO
			set_physics_process(false)


# === HEALTH ===

func take_damage(amount: int, from_position: Vector3, skip_hitstop: bool = false) -> void:
	if _is_dead: return
	if _in_armor_break(): return
	if not _consume_hit(): return
	if is_armored:
		_on_armored_hit(from_position, skip_hitstop)
		return
	_health -= amount
	if not skip_hitstop: _apply_hit_juice()
	if _health <= 0: _die()
	elif _state in [State.IDLE, State.CHASE]: _enter_hit()
	_update_boss_bar()
	
	
func _update_arena_presentation() -> void:
	var p := _get_player()
	var inside := _player_inside_arena(p)
	if inside and not _arena_active:
		_arena_active = true
		_on_arena_enter()
	elif not inside and _arena_active:
		_arena_active = false
		_on_arena_exit()

func _on_arena_enter() -> void:
	_start_boss_music()
	if _boss_bar and _boss_bar.has_method("bind"):
		_boss_bar.bind(boss_display_name)
		_boss_bar.set_health(_health, max_health)
		_boss_bar.set_armor(_armor, max_armor)
		_boss_bar.appear()

func _on_arena_exit() -> void:
	_stop_boss_music()
	if _boss_bar and _boss_bar.has_method("vanish"):
		_boss_bar.vanish()
		
func _start_boss_music() -> void:
	if boss_music == null or MusicManager == null:
		return
	if _boss_zone == null:
		_boss_zone = MusicZone.new()
		_boss_zone.music_track = boss_music
		_boss_zone.zone_priority = boss_music_priority
		_boss_zone.crossfade_duration = boss_music_crossfade
	MusicManager.enter_zone(_boss_zone)

func _stop_boss_music() -> void:
	if _boss_zone and MusicManager:
		MusicManager.exit_zone(_boss_zone)
	if _phase2_zone and MusicManager: 
		MusicManager.exit_zone(_phase2_zone)

func _update_boss_bar() -> void:
	if _boss_bar and _boss_bar.has_method("set_health"):
		_boss_bar.set_health(_health, max_health)
	if _boss_bar and _boss_bar.has_method("set_armor"):
		_boss_bar.set_armor(_armor, max_armor)

func _spawn_armor_impact() -> void:
	CombatVFXUtils.spawn_impact(self, impact_vfx_scene,
		global_position + Vector3(0, impact_vfx_height, 0),
		impact_vfx_scale, impact_vfx_delay, impact_vfx_lifetime)

func take_dive_strike(amount: int, from_position: Vector3) -> bool:
	if _is_dead: return false
	if _in_armor_break(): return true            # Cinematic läuft – Treffer ohne Wirkung
	if not _consume_hit(): return true
	if is_armored:
		_armor = max(_armor - amount, 0)
		if _armor <= 0:
			_break_armor()
		else:
			_spawn_impact(impact_vfx_scene)
			_play_sound(_audio_action, armor_hit_sound, 0.05)
			_shake_camera(slam_shake_strength * 0.5, 0.15)
			_update_boss_bar()
		return true
	_health -= amount
	if _health <= 0: _die()
	elif _state in [State.IDLE, State.CHASE]: _enter_hit()
	_update_boss_bar()
	return true
	
func _knockback_player_away(strength: float) -> void:
	var p := _get_player()
	if p == null or not is_instance_valid(p):
		return
	var d := p.global_position - global_position
	d.y = 0.0
	if d.length() < 0.5:
		d = _locked_facing if _locked_facing.length() > 0.01 else Vector3.FORWARD
		d.y = 0.0
	d = d.normalized()
	if p.has_method("launch_airborne"):
		p.launch_airborne(d, strength, armor_break_player_up)
	elif p.has_method("apply_knockback"):
		p.apply_knockback(p.global_position - d, strength)

func _break_armor() -> void:
	is_armored = false
	for mesh_name in armor_mesh_names:
		var m = rotator.find_child(mesh_name, true, false)
		if m: m.visible = false
	_spawn_armor_pieces()
	if armor_break_sound: _play_sound(_audio_action, armor_break_sound, 0.0)
	_spawn_self_playing_vfx(armor_break_vfx_scene,
		global_position + Vector3(0, impact_vfx_height, 0),
		armor_break_lifetime, impact_vfx_scale)
	_shake_camera(slam_shake_strength, slam_shake_duration)   # Rückstoß-Wumms
	_update_boss_bar()
	_knockback_player_away(armor_break_player_knockback)
	_set_player_frozen(true)
	_enter_armor_break_sit()


func _spawn_armor_pieces() -> void:
	if armor_break_scene == null:
		return
	var pieces := armor_break_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(pieces)
	pieces.global_position = global_position + Vector3.UP * impact_vfx_height
	var i := 0
	for child in pieces.get_children():
		if child is RigidBody3D:
			var side := 1.0 if i % 2 == 0 else -1.0
			var impulse := global_transform.basis.x * side * armor_break_impulse \
				+ Vector3.UP * armor_break_up
			child.apply_impulse(impulse)
			child.angular_velocity = Vector3(
				randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
			i += 1
	get_tree().create_timer(armor_break_lifetime).timeout.connect(pieces.queue_free)

func _in_armor_break() -> bool:
	return _state in [State.ARMOR_BREAK_SIT, State.ARMOR_BREAK_STANDUP, State.ARMOR_BREAK_ROAR]

func _enter_armor_break_sit() -> void:
	_state = State.ARMOR_BREAK_SIT
	_state_timer = armor_break_sit_time
	_player_locked = false
	_land_confirm = 0.0
	_armor_break_wait_clock = 0.0
	velocity = Vector3.ZERO
	_face_camera()
	_play_anim(armor_break_sit_anim, 1.0)
	_stop_boss_music()
	_camera_focus(true)     # Kamera gleitet schon zum Oger – ohne Freeze

func _process_armor_break_sit(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not _player_locked:
		_armor_break_wait_clock += delta
		var p := _get_player()
		var grounded : bool= p != null and is_instance_valid(p) \
			and p.has_method("is_on_floor") and p.is_on_floor()
		_land_confirm = _land_confirm + delta if grounded else 0.0
		if _land_confirm >= armor_break_land_confirm \
		or _armor_break_wait_clock >= armor_break_wait_max:
			_player_locked = true
			_set_player_frozen(true)
			_state_timer = armor_break_sit_time   # Hold beginnt erst NACH dem Lock
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_armor_break_standup()

func _enter_armor_break_standup() -> void:
	_state = State.ARMOR_BREAK_STANDUP
	_state_timer = armor_break_standup_time
	_face_camera()
	_play_anim(armor_break_standup_anim, 1.0)

func _process_armor_break_standup(delta: float) -> void:
	velocity.x = 0.0; velocity.z = 0.0
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_armor_break_roar()

func _enter_armor_break_roar() -> void:
	_state = State.ARMOR_BREAK_ROAR
	_state_timer = armor_break_roar_time
	_roar_vfx_done = false
	_face_camera()
	_play_anim(armor_break_roar_anim, 1.0)
	_start_phase2_music()
	_play_sound(_audio_action, roar_sound, 0.03)

func _process_armor_break_roar(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_face_camera()
	_state_timer -= delta
	if not _roar_vfx_done \
	and (armor_break_roar_time - _state_timer) >= armor_break_roar_vfx_time:
		_roar_vfx_done = true
		_spawn_roar_vfx()
		_roar_shake_time = roar_shake_duration
	if _cs_cam and is_instance_valid(_cs_cam):
		if _roar_shake_time > 0.0:
			_roar_shake_time -= delta
			var k := clampf(_roar_shake_time / maxf(roar_shake_duration, 0.001), 0.0, 1.0)
			_cs_cam.position = Vector3(
				randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)) * roar_shake_strength * k
		else:
			_cs_cam.position = Vector3.ZERO
	if _state_timer <= 0.0:
		var p := _get_player()
		_exit_cutscene()
		_phase = 2
		if _player_inside_arena(p):
			_target = p
			_enter_chase()
		else:
			_enter_return()

func _face_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or rotator == null:
		return
	var d := cam.global_position - global_position
	d.y = 0.0
	if d.length() < 0.001:
		return
	rotator.rotation.y = _styled_yaw(atan2(d.x, d.z))
	rotator.reset_physics_interpolation()
	_current_facing_index = -1
	


func _exit_cutscene() -> void:
	_camera_focus(false)
	_set_player_frozen(false)
		
func _set_player_frozen(frozen: bool) -> void:
	var p := _get_player()
	if p and is_instance_valid(p) and p.has_method("set_frozen"):
		p.set_frozen(frozen)   # exakt der Lock, den der DialogueManager beim Pickup nutzt


func _camera_focus(on: bool) -> void:
	if on:
		_prev_cam = get_viewport().get_camera_3d()
		_cs_mount = Node3D.new()
		get_tree().current_scene.add_child(_cs_mount)
		_cs_cam = Camera3D.new()
		_cs_mount.add_child(_cs_cam)
		if _prev_cam and is_instance_valid(_prev_cam):
			_cs_mount.global_transform = _prev_cam.global_transform   # exakt gleicher Winkel
			_cs_cam.fov = _prev_cam.fov
		_cs_cam.make_current()
		var fwd := -_cs_mount.global_transform.basis.z.normalized()
		var focus := global_position + Vector3(0, cutscene_cam_focus_height, 0)
		var target_pos := focus - fwd * cutscene_cam_distance
		var t := create_tween()
		t.set_parallel(true)
		t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(_cs_mount, "global_position", target_pos, cutscene_cam_move_time)
		t.tween_property(_cs_cam, "fov", _cs_cam.fov * cutscene_zoom, cutscene_cam_move_time)
	else:
		if _cs_mount == null or not is_instance_valid(_cs_mount):
			return
		if not (_prev_cam and is_instance_valid(_prev_cam) \
		and _cs_cam and is_instance_valid(_cs_cam)):
			if _cs_mount: _cs_mount.queue_free()
			_cs_mount = null
			_cs_cam = null
			return
		var t := create_tween()
		t.set_parallel(true)
		t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(_cs_mount, "global_position", _prev_cam.global_position, 0.7)
		t.tween_property(_cs_cam, "fov", _prev_cam.fov, 0.7)        # der fehlende Zoom-Rücktween
		t.tween_property(_cs_cam, "position", Vector3.ZERO, 0.25)   # Shake weich ausfahren
		t.chain().tween_callback(func():
			if _prev_cam and is_instance_valid(_prev_cam):
				_prev_cam.make_current()
			if _cs_mount and is_instance_valid(_cs_mount):
				_cs_mount.queue_free()
			_cs_mount = null
			_cs_cam = null)

func _start_phase2_music() -> void:
	if phase2_boss_music == null or MusicManager == null:
		return
	if _phase2_zone == null:
		_phase2_zone = MusicZone.new()
		_phase2_zone.music_track = phase2_boss_music
		_phase2_zone.zone_priority = boss_music_priority + 10   # schlägt Boss-Zone
		_phase2_zone.crossfade_duration = boss_music_crossfade
	MusicManager.enter_zone(_phase2_zone)


func _die() -> void:
	_cleanup_charge_thrust()
	if _is_dead:
		return
	_is_dead = true
	_state = State.DEAD
	velocity = Vector3.ZERO
	# Death-Anim / VFX / Rewards kommen später


# === HELPERS ===

func _spawn_impact(scene: PackedScene) -> void:   # einzige VFX-Hilfe, die übrig bleibt
	CombatVFXUtils.spawn_impact(self, scene,
		global_position + Vector3(0, impact_vfx_height, 0),
		impact_vfx_scale, 0.0, impact_vfx_lifetime)

func _consume_hit() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _hit_gate_until:
		return false
	_hit_gate_until = now + hit_refractory
	return true
	
func _is_phase2() -> bool:
	return _phase >= 2

func get_hit_radius() -> float:
	return body_hit_radius

func _get_player() -> Node3D:
	if _player_ref and is_instance_valid(_player_ref):
		return _player_ref
	_player_ref = get_tree().get_first_node_in_group("player")
	return _player_ref


func _play_anim(anim_name: String, speed: float) -> void:
	if anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name, -1, speed)


func _play_sound(player: AudioStreamPlayer3D, stream: AudioStream, pitch_var: float) -> void:
	if stream == null or player == null:
		return
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	player.play()


func _shake_camera(strength: float, duration: float) -> void:
	if GameEffects:
		GameEffects.shake(strength, duration)
		
		
		
@export var debug_slam_radius: bool = false

func _spawn_slam_debug_ring(center: Vector3) -> void:
	if not debug_slam_radius:
		return
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = max(slam_radius - 0.05, 0.01)
	torus.outer_radius = slam_radius
	ring.mesh = torus  # Godot-Torus liegt by default flach in XZ
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 0, 0, 0.85)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = m
	get_tree().current_scene.add_child(ring)
	ring.global_position = Vector3(center.x, center.y + 0.03, center.z)
	get_tree().create_timer(slam_vfx_lifetime).timeout.connect(
		func(): if is_instance_valid(ring): ring.queue_free())
		

extends CharacterBody3D
class_name OgerBoss

## Oger-Miniboss — 3D-Modell im SubViewport, AnimationPlayer-basiert.
## Übernimmt Infrastruktur-Pattern aus Enemy (Freeze, Terrain-Await, Gravity,
## Audio, Health), aber eigene State-Machine wegen SubViewport-Architektur.

# === REFERENCES ===
@onready var rotator: Node3D = $RenderViewport/BossRotator
var anim_player: AnimationPlayer

var _in_finisher: bool = false
@onready var _finisher_director: Node = $FinisherDirector

@onready var boss_sprite: SmoothPixelSprite3D = $BossSprite
@onready var render_viewport: SubViewport = $RenderViewport

@export_group("Save Flags")

@export var boss_id: String = "ogre_boss"


# === HEALTH ===
@export_group("Health")
@export var max_health: int = 100

@export var max_armor: int = 50      # nur per Dive Strike abbaubar
var _armor: int

@export var body_hit_radius: float = 0.5

# === ANIMATION ===
@export_group("Animation")
@export var idle_anim: String = "Idle"
@export var walk_anim: String = "Walk"
@export var slam_anim: String = "GroundSlam"
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
@export var armor_break_music_fade: float = 0.8
var _roar_vfx_done: bool = false

@export_group("Armor Break Cutscene")
@export var phase2_boss_music: AudioStream
@export var roar_shake_strength: float = 0.22
@export var roar_shake_duration: float = 0.7
@export var cutscene_zoom: float = 0.9    



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

const BOSS_MUSIC_OWNER := "boss"

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
@export var slam_windup_time: float = 1.5      # Gesamtdauer Ausholen (Keule hoch + hinter Kopf)
@export var slam_impact_time: float = 1.35     # Zeitpunkt, an dem die Keule auftrifft
@export var slam_recovery_time: float = 1.2    # Erholung nach dem Schlag
@export var slam_shake_strength: float = 0.6
@export var slam_shake_duration: float = 0.35
@export var slam_sound: AudioStream
@export var slam_vfx_scene: PackedScene        # optional; sonst prozedural
@export var slam_impact_forward_offset: float = 1.2

@export var slam_vfx_lifetime: float = 2.0


@export_group("Attack Selection")
@export var slam_weight: float = 0.5
@export var charge_weight: float = 0.25
@export var butt_weight: float = 0.25

@export_group("Armored Charge")
@export var charge_telegraph_anim: String = "ArmoredTelegraph"
@export var charge_dash_anim: String = "ArmoredDash_001"                   
@export var charge_telegraph_anim_speed: float = 1.0
@export var charge_dash_anim_speed: float = 2.5
@export var charge_chance: float = 0.4
@export var charge_min_distance: float = 0.0
@export var charge_max_distance: float = 6.0
@export var charge_decision_interval: float = 1.0
@export var charge_cooldown_time: float = 6.0
@export var charge_telegraph_time: float = 1.4    # Dauer 3 Klopfer — an Anim messen
@export var charge_speed: float = 6.0
@export var charge_max_duration: float = 1.1
@export var charge_damage: int = 28
@export var charge_player_knockback: float = 9.0
@export var charge_recovery_time: float = 1.2 

@export var fx_local_height: float = 1.0      # Brusthöhe im Modell-Maßstab
@export var hit_refractory: float = 0.15
var _hit_gate_until: float = 0.0

@export_group("Charge SFX")
@export var charge_knock_sound: AudioStream
@export var charge_knock_times: Array[float] = [0.15, 0.6, 1.05]  # rel. Telegraph-Start
@export var charge_step_sound: AudioStream      # leer → footstep_sound
@export var charge_step_interval: float = 0.18  # schneller als normaler Schritt

@export_group("Charge Wall Impact")
@export var charge_wall_sfx: AudioStream
@export var charge_wall_shake_strength: float = 0.35
@export var charge_wall_shake_duration: float = 0.25
@export var charge_wall_bounce_strength: float = 3.0
@export var charge_wall_stun_time: float = 1.0
@export var charge_wall_stun_anim: String = "ArmorBreakSit"
@export var charge_wall_stun_anim_speed: float = 1.0


@export_group("Impact VFX Placement")
@export var impact_vfx_scale: float = 1.0
@export var impact_vfx_lifetime: float = 0.5
@export var impact_vfx_delay := 0.0

var _knock_index: int = 0
var _charge_step_timer: float = 0.0

var _charge_dir: Vector3 = Vector3.ZERO
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
@export var arena_bounds_path: NodePath 

@export_group("Phase 2")
@export var p2_run_anim: String = "Run"
@export var p2_run_anim_speed: float = 3.0
@export var p2_chase_speed_mult: float = 1.9
@export var p2_slam_speed_mult: float = 1.6
@export var p2_step_interval: float = 0.30          # Walk hat z.B. 0.55 — Run schneller
@export var p2_step_shake_strength: float = 0.18    # schwereres Stampfen
@export var p2_step_shake_duration: float = 0.10
@export var p2_footstep_sound: AudioStream 


@export_group("Phase 2 Hit Feedback")
@export var hit_flash_duration: float = 0.12
@export var hit_flash_color: Color = Color(1.6, 0.5, 0.5)
@export var hit_bounce_strength: float = 1.5
@export var hit_bounce_damping: float = 12.0

var _hit_flash_timer: float = 0.0
var _hit_knockback: Vector3 = Vector3.ZERO


var _slam_windup_t: float
var _slam_impact_t: float
var _slam_recovery_t: float

@export_group("Vector Anchor Block")
@export var vector_block_anim: String = "VectorBlock"
@export var vector_block_anim_speed: float = 8.0
@export var vector_block_time: float = 0.7
@export var vector_block_damage: int = 6
@export var vector_block_sound: AudioStream
@export var vector_block_vfx_scene: PackedScene
@export var vector_block_vfx_lifetime: float = 0.6

@export_group("Butt Slam")
@export var butt_chance: float = 0.5
@export var butt_min_distance: float = 0.0
@export var butt_max_distance: float = 6.0
@export var butt_cooldown_after_attack: float = 5.0

@export var butt_crouch_anim: String = "ButtCrouch"
@export var butt_crouch_anim_speed: float = 0.5
@export var butt_crouch_time: float = 1.5           # in die Knie + kurzes Halten

@export var butt_jump_anim: String = "ButtJump"
@export var butt_jump_anim_speed: float = 1.0
@export var butt_jump_time: float = 1.0             # Gesamtdauer der Flugbahn
@export var butt_jump_arc_height: float = 2.2

@export var butt_land_anim: String = "ButtLand"
@export var butt_land_anim_speed: float = 1.0
@export var butt_recovery_time: float = 2.0

@export var butt_damage: int = 25
@export var butt_shake_strength: float = 0.7
@export var butt_shake_duration: float = 0.4
@export var butt_vfx_scene: PackedScene        # optional; sonst prozedural
@export var butt_sound: AudioStream


@export_group("Boss Presentation")
@export var boss_display_name: String = "Tharok"
@export var boss_bar_scene: PackedScene

@export_group("Boss Music")
@export var boss_music: AudioStream
@export var boss_music_priority: int = 100      # MUSS höher sein als deine Overworld-Zonen
@export var boss_music_crossfade: float = 1.5

@export_group("Boss Intro")
@export var play_intro_on_first_enter: bool = true

@export var intro_roar_delay_min: float = 2.0
@export var intro_roar_delay_max: float = 2.0

@export var intro_title_fade_in: float = 0.6
@export var intro_title_hold: float = 0.1
@export var intro_title_fade_out: float = 0.6

@export_group("Boss Intro Camera")
@export var intro_camera_marker_path: NodePath = NodePath("IntroCameraMarker")
@export var intro_camera_pan_from_current: bool = true
@export var intro_camera_pan_time: float = 0.75
@export var intro_camera_zoom: float = 0.85
@export var intro_camera_return_time: float = 0.7

@export_group("Boss Intro Sequence")
@export var intro_slam_1_anim: String = "FinisherSlam1"
@export var intro_slam_2_anim: String = "FinisherSlam2"
@export var intro_slam_anim_speed: float = 2.5
@export var intro_slam_pause: float = 1.0
@export var intro_slam_1_wait: float = 1.25
@export var intro_slam_2_wait: float = 3.35
@export var intro_slam_impact_time: float = 0.55

@export var intro_pause_before_roar: float = 0.25
@export var intro_roar_anim: String = "ArmorBreakRoar"
@export var intro_roar_anim_speed: float = 1.0
@export var intro_roar_time: float = 1.2
@export var intro_roar_vfx_time: float = 0.25


@export var intro_slam_shake_strength: float = 0.2
@export var intro_slam_shake_duration: float = 0.2


@export_group("Boss Intro Music")
@export var intro_music: AudioStream
@export var intro_music_priority: int = 110
@export var intro_music_crossfade: float = 0.0
@export var intro_to_boss_music_crossfade: float = 1.0

@export_group("Death VFX")
@export var boss_ash_death_scene: PackedScene

@export_group("Death Loot")
@export var chest_reveal_scene: PackedScene  # -> ChestReveal.tscn
@export var linked_chest_path: NodePath
@export var chest_reveal_delay: float = 4.5



var _phase: int = 1

# === STATE ===
enum State { IDLE, CHASE, SLAM_WINDUP, SLAM_RECOVERY, HIT, RETURN,
CHARGE_TELEGRAPH, CHARGE_DASH, CHARGE_RECOVERY, CHARGE_WALL_STUN,
ARMOR_BREAK_SIT, ARMOR_BREAK_STANDUP, ARMOR_BREAK_ROAR, VECTOR_BLOCK,
BUTT_CROUCH, BUTT_JUMP, BUTT_RECOVERY, DEAD }

var _state: State = State.IDLE
var _state_timer: float = 0.0


var _arena_active: bool = false
@onready var _boss_bar: Node = $BossHealthBar 


var _intro_done: bool = false
var _intro_running: bool = false
var _intro_title_layer: CanvasLayer = null

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


var _butt_cooldown: float = 0.0
var _butt_time: float = 0.0
var _butt_start_pos: Vector3
var _butt_land_pos: Vector3
var _butt_impact_done: bool = false

@onready var _finisher_mount_point: Marker3D = $FinisherMountPoint


var _arena_bounds: Node3D = null

# === LIFECYCLE ===

func _ready() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_flag"):
		# Boss schon besiegt? Komplett entfernen.
		if gm.get_flag("boss_defeated_" + boss_id):
			queue_free()
			return
		# Intro schon gesehen? Nicht mehr abspielen.
		if gm.get_flag("boss_intro_played_" + boss_id):
			_intro_done = true

	
	
	boss_sprite.hframes = 1
	boss_sprite.vframes = 1
	boss_sprite.texture = render_viewport.get_texture()
	
	_health = max_health
	_armor = max_armor
	_spawn_position = global_position
	_player_ref = get_tree().get_first_node_in_group("player")

	add_to_group("enemies")
	
	if not arena_bounds_path.is_empty():
		_arena_bounds = get_node_or_null(arena_bounds_path) as Node3D
	if _arena_bounds == null:
		push_warning("OgerBoss: arena_bounds_path zeigt nicht auf ein Node3D")
	
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
	if anim_player.has_animation(vector_block_anim): 
		anim_player.get_animation(vector_block_anim).loop_mode = Animation.LOOP_NONE
	
	for a in [butt_crouch_anim, butt_jump_anim, butt_land_anim]:
		if anim_player.has_animation(a):
			anim_player.get_animation(a).loop_mode = Animation.LOOP_NONE
		
	for a in [armor_break_sit_anim, armor_break_standup_anim, armor_break_roar_anim, intro_roar_anim]:
		if anim_player.has_animation(a):
			anim_player.get_animation(a).loop_mode = Animation.LOOP_NONE
			
	for a in ["FinisherSlam1", "FinisherSlam2", "FinisherSlam3", "Exhausted",
			"StaggerBack1", "StaggerBack2", "FallOnBack", "FinisherDeath"]:
		if anim_player.has_animation(a):
			anim_player.get_animation(a).loop_mode = Animation.LOOP_NONE
			
	for a in [
		armor_break_sit_anim,
		armor_break_standup_anim,
		armor_break_roar_anim,
		intro_slam_1_anim,
		intro_slam_2_anim,
		intro_roar_anim
	]:
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
	if _in_finisher: return
	_check_freeze_state()
	_update_arena_presentation()
	_update_hit_flash(_delta)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if _intro_running:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	if _is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
		
	if _in_finisher:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	
	_charge_cooldown = maxf(_charge_cooldown - delta, 0.0)
	
	if _in_finisher:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

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
		State.CHARGE_WALL_STUN:
			_process_charge_wall_stun(delta)
		State.ARMOR_BREAK_SIT:
			_process_armor_break_sit(delta)
		State.ARMOR_BREAK_STANDUP:
			_process_armor_break_standup(delta)
		State.ARMOR_BREAK_ROAR:
			_process_armor_break_roar(delta)
		State.VECTOR_BLOCK: 
			_process_vector_block(delta)
		State.BUTT_CROUCH:
			_process_butt_crouch(delta)
		State.BUTT_JUMP:
			_process_butt_jump(delta)
		State.BUTT_RECOVERY:
			_process_butt_recovery(delta)
			
	if _hit_knockback.length_squared() > 0.0001:
		velocity.x += _hit_knockback.x
		velocity.z += _hit_knockback.z
		_hit_knockback = _hit_knockback.lerp(Vector3.ZERO, clampf(delta * hit_bounce_damping, 0.0, 1.0))

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
	_charge_decision_timer = 0.0 
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
	
	_butt_cooldown = maxf(_butt_cooldown - delta, 0.0)
	_charge_decision_timer -= delta
	
	# Attack-Auswahl: alle verfügbaren Attacken gewichtet würfeln,
	# nicht mehr "Slam wenn nah, sonst Rest" hartkodiert.
	if _charge_decision_timer <= 0.0:
		_charge_decision_timer = charge_decision_interval
		var chosen := _pick_attack(dist)
		match chosen:
			"slam":
				_enter_slam()
				return
			"charge":
				_enter_charge_telegraph()
				return
			"butt":
				_enter_butt_crouch()
				return
	
	# Keine Attack gewählt (alle auf Cooldown / außer Range) → weiter chasen
	var dir := to_player.normalized()
	_face_direction(dir)
	var spd := move_speed * (p2_chase_speed_mult if _is_phase2() else 1.0)
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	
	_step_timer += delta
	var stride := p2_step_interval if _is_phase2() else step_interval
	if _step_timer >= stride:
		_step_timer = 0.0
		var snd: AudioStream = (p2_footstep_sound if (_is_phase2() and p2_footstep_sound != null) else footstep_sound)
		_play_sound(_audio_step, snd, 0.08)
		if _is_phase2():
			_shake_camera(p2_step_shake_strength, p2_step_shake_duration)
		else:
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
	var p := _slam_impact_point()
	_spawn_self_playing_vfx(slam_vfx_scene,
		Vector3(p.x, p.y + 0.02, p.z),
		slam_vfx_lifetime, 1.0, null, slam_damage)
	if slam_sound:
		_play_sound(_audio_action, slam_sound, 0.0)
	_shake_camera(slam_shake_strength, slam_shake_duration)


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
	
	# Wand-Treffer: eigener Stun-State mit Feedback.
	# Zeit-Ende: normale Recovery wie bisher.
	if is_on_wall():
		_enter_charge_wall_stun()
		return
	if _charge_time >= charge_max_duration:
		_enter_charge_recovery()
		
func _on_charge_hit_player(body: Node) -> void:
	if body and is_instance_valid(body) and body.has_method("apply_knockback"):
		body.apply_knockback(global_position, charge_player_knockback)
		
func _enter_charge_wall_stun() -> void:
	_cleanup_charge_thrust()
	_state = State.CHARGE_WALL_STUN
	_state_timer = charge_wall_stun_time
	_charge_cooldown = charge_cooldown_time
	velocity = Vector3.ZERO
	
	# Feedback: Sound + Shake
	if charge_wall_sfx:
		_play_sound(_audio_action, charge_wall_sfx, 0.0)
	_shake_camera(charge_wall_shake_strength, charge_wall_shake_duration)
	
	_hit_knockback = -_charge_dir * charge_wall_bounce_strength
	

	_play_anim(charge_wall_stun_anim, charge_wall_stun_anim_speed)


func _process_charge_wall_stun(delta: float) -> void:
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
	# Damage in alle VFXHitArea(s) der Szene injizieren
	for area in _charge_thrust.find_children("*", "Area3D", true, false):
		if "damage" in area:
			area.damage = charge_damage
		if area.has_signal("hit_landed"):           # optional: für Bonus-Knockback
			area.hit_landed.connect(_on_charge_hit_player)
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
	
func _enter_butt_crouch() -> void:
	_state = State.BUTT_CROUCH
	_state_timer = butt_crouch_time
	velocity.x = 0.0
	velocity.z = 0.0
	var p := _get_player()
	if p and is_instance_valid(p):
		var d := p.global_position - global_position
		d.y = 0.0
		if d.length() > 0.01:
			_locked_facing = d.normalized()
			_face_direction(_locked_facing)
	_play_anim(butt_crouch_anim, butt_crouch_anim_speed)

func _process_butt_crouch(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_butt_jump()

func _enter_butt_jump() -> void:
	_state = State.BUTT_JUMP
	_butt_time = 0.0
	_butt_impact_done = false
	_butt_start_pos = global_position
	var p := _get_player()
	if p and is_instance_valid(p):
		_butt_land_pos = Vector3(p.global_position.x, _butt_start_pos.y, p.global_position.z)
	else:
		_butt_land_pos = _butt_start_pos + _locked_facing * 4.0
	_play_anim(butt_jump_anim, butt_jump_anim_speed)

func _process_butt_jump(delta: float) -> void:
	_butt_time += delta
	var t := clampf(_butt_time / butt_jump_time, 0.0, 1.0)
	var horiz := _butt_start_pos.lerp(_butt_land_pos, t)
	var arc := 4.0 * butt_jump_arc_height * t * (1.0 - t)
	# direkte Position statt move_and_slide — saubere Parabel, keine Schwerkraft-Konflikte
	global_position = Vector3(horiz.x, _butt_start_pos.y + arc, horiz.z)
	velocity = Vector3.ZERO
	if not _butt_impact_done and t >= 1.0:
		_butt_impact_done = true
		_do_butt_impact()
		_enter_butt_recovery()

func _do_butt_impact() -> void:
	global_position = _butt_land_pos
	_spawn_self_playing_vfx(butt_vfx_scene,
		global_position + Vector3(0, 0.02, 0),
		slam_vfx_lifetime, 1.0, null, butt_damage)
	if butt_sound:
		_play_sound(_audio_action, butt_sound, 0.0)
	_shake_camera(butt_shake_strength, butt_shake_duration)

func _enter_butt_recovery() -> void:
	_state = State.BUTT_RECOVERY
	_state_timer = butt_recovery_time
	velocity = Vector3.ZERO
	_butt_cooldown = butt_cooldown_after_attack
	_play_anim(butt_land_anim, butt_land_anim_speed)

func _process_butt_recovery(delta: float) -> void:
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

func _spawn_self_playing_vfx(
		scene: PackedScene, world_pos: Vector3, lifetime: float,
		scale: float = 1.0, look_at_pos = null,
		damage: int = 0
) -> Node3D:
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	get_tree().current_scene.add_child(inst)
	inst.global_position = world_pos
	if scale != 1.0:
		inst.scale = Vector3(scale, scale, scale)
	if look_at_pos != null and inst.global_position.distance_to(look_at_pos) > 0.01:
		inst.look_at(look_at_pos, Vector3.UP)
	# Schaden in alle VFXHitArea(s) der Szene injizieren
	if damage > 0:
		for area in inst.find_children("*", "Area3D", true, false):
			if "damage" in area:
				area.damage = damage
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
	if p == null or not is_instance_valid(p):
		return false
	if _arena_bounds and is_instance_valid(_arena_bounds):
		if _arena_bounds.has_method("contains_point"):
			return _arena_bounds.contains_point(p.global_position)
		if _arena_bounds is Area3D:
			return _arena_bounds.overlaps_body(p)
	return _spawn_position.distance_to(p.global_position) <= arena_radius

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
	if _intro_running: return
	if _is_dead: return
	if _in_finisher: return
	if _in_armor_break(): return
	if not _consume_hit(): return
	if is_armored:
		_on_armored_hit(from_position, skip_hitstop)
		return
		
	_trigger_phase2_hit_feedback(from_position)
	
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
	if has_node("/root/CombatManager"):
		CombatManager.engage_enemy(self)
	if play_intro_on_first_enter and not _intro_done:
		_start_boss_intro()
		return

	_start_boss_encounter_ui()

func _start_boss_encounter_ui(start_music: bool = true) -> void:
	if start_music:
		_start_boss_music()

	if _boss_bar and _boss_bar.has_method("bind"):
		_boss_bar.bind(boss_display_name)
		_boss_bar.set_health(_health, max_health)
		_boss_bar.set_armor(_armor, max_armor)
		_boss_bar.appear()

func _on_arena_exit() -> void:
	if _intro_running or _in_armor_break() or _in_finisher:
		return
		
	if has_node("/root/CombatManager"):
		CombatManager.disengage_enemy(self)
	_health = max_health
	_update_boss_bar()
	
	_stop_intro_music()
	_stop_boss_music()
	if _boss_bar and _boss_bar.has_method("vanish"):
		_boss_bar.vanish()
		
func _start_intro_music() -> void:
	if intro_music == null:
		return
	MusicManager.push_music(BOSS_MUSIC_OWNER, intro_music,
		intro_music_priority, intro_music_crossfade)


func _stop_intro_music() -> void:
	pass


func _transition_intro_music_to_boss_music() -> void:
	# Track-Wechsel innerhalb desselben Owners → fällt NIE auf die
	# Overworld-Zone zurück, auch nicht in einer Timing-Lücke.
	if boss_music == null:
		return
	MusicManager.push_music(BOSS_MUSIC_OWNER, boss_music,
		boss_music_priority, intro_to_boss_music_crossfade)


func _start_boss_music() -> void:
	if boss_music == null:
		return
	MusicManager.push_music(BOSS_MUSIC_OWNER, boss_music,
		boss_music_priority, boss_music_crossfade)


func _stop_boss_music() -> void:
	MusicManager.pop_music(BOSS_MUSIC_OWNER)




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
	if _intro_running: return false
	if _in_finisher: return false 
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
	
	
func _start_boss_intro() -> void:
	if _intro_running or _intro_done:
		return
	_run_boss_intro()
	
func _run_boss_intro() -> void:
	_intro_running = true
	_intro_done = true
	
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("set_flag"):
		gm.set_flag("boss_intro_played_" + boss_id, true)


	velocity = Vector3.ZERO
	_target = null
	_set_player_frozen(true)

	_start_intro_music()

	_intro_camera_focus(true)

	# Kamera erst ankommen lassen.
	await get_tree().create_timer(intro_camera_pan_time).timeout

	# Oger zur festen Intro-Kamera ausrichten.
	_face_camera()

	await _play_intro_slam_fixed(
		intro_slam_1_anim,
		intro_slam_anim_speed,
		intro_slam_1_wait,
		intro_slam_impact_time
	)

	if intro_slam_pause > 0.0:
		await get_tree().create_timer(intro_slam_pause).timeout

	await _play_intro_slam_fixed(
		intro_slam_2_anim,
		intro_slam_anim_speed,
		intro_slam_2_wait,
		intro_slam_impact_time
	)

	if intro_pause_before_roar > 0.0:
		await get_tree().create_timer(intro_pause_before_roar).timeout

	# Roar.
	_face_camera()
	_play_anim(intro_roar_anim, intro_roar_anim_speed)

	if roar_sound:
		_play_sound(_audio_action, roar_sound, 0.03)

	_show_boss_intro_title(boss_display_name)

	var roar_elapsed := 0.0
	var vfx_done := false

	while roar_elapsed < intro_roar_time:
		var delta := get_process_delta_time()
		roar_elapsed += delta

		_face_camera()

		if not vfx_done and roar_elapsed >= intro_roar_vfx_time:
			vfx_done = true
			_spawn_intro_roar_vfx()
			_shake_camera(roar_shake_strength, roar_shake_duration)

		await get_tree().process_frame
	
	
	_hide_boss_intro_title()      # nicht awaiten
	_intro_camera_focus(false)    # nicht awaiten

	_transition_intro_music_to_boss_music()
	_start_boss_encounter_ui(false)

	# Optional: ganz kurzer Idle-Settle, wirklich nur ein paar Frames.
	_face_camera()
	_play_anim(idle_anim, idle_anim_speed)

	await get_tree().create_timer(0.08).timeout

	_set_player_frozen(false)
	_intro_running = false

	var p := _get_player()
	if _player_inside_arena(p):
		_target = p
		_enter_chase()
	else:
		_enter_return()
		
		
		
func _intro_camera_focus(on: bool) -> void:
	if on:
		_prev_cam = get_viewport().get_camera_3d()

		if _cs_mount and is_instance_valid(_cs_mount):
			_cs_mount.queue_free()
			_cs_mount = null
			_cs_cam = null

		var marker := get_node_or_null(intro_camera_marker_path) as Node3D
		if marker == null:
			push_warning("OgerBoss: IntroCameraMarker fehlt oder intro_camera_marker_path ist falsch.")
			return

		_cs_mount = Node3D.new()
		get_tree().current_scene.add_child(_cs_mount)

		_cs_cam = Camera3D.new()
		_cs_mount.add_child(_cs_cam)

		var target_transform := marker.global_transform

		if intro_camera_pan_from_current and _prev_cam and is_instance_valid(_prev_cam):
			# Start bei aktueller Kamera-Position, aber sofort mit festem Intro-Winkel.
			# Dadurch kein rotierender Kameraschwenk.
			_cs_mount.global_transform = Transform3D(
				target_transform.basis,
				_prev_cam.global_position
			)
			_cs_cam.fov = _prev_cam.fov
			_cs_cam.near = _prev_cam.near
			_cs_cam.far = _prev_cam.far
		else:
			# Komplett fester Shot.
			_cs_mount.global_transform = target_transform
			if _prev_cam and is_instance_valid(_prev_cam):
				_cs_cam.fov = _prev_cam.fov
				_cs_cam.near = _prev_cam.near
				_cs_cam.far = _prev_cam.far

		_cs_cam.position = Vector3.ZERO
		_cs_cam.rotation = Vector3.ZERO
		_cs_cam.make_current()

		var target_fov := _cs_cam.fov * intro_camera_zoom

		var t := create_tween()
		t.set_parallel(true)
		t.set_trans(Tween.TRANS_SINE)
		t.set_ease(Tween.EASE_OUT)

		t.tween_property(_cs_mount, "global_position", target_transform.origin, intro_camera_pan_time)
		t.tween_property(_cs_cam, "fov", target_fov, intro_camera_pan_time)

	else:
		if _cs_mount == null or not is_instance_valid(_cs_mount):
			return

		if not (_prev_cam and is_instance_valid(_prev_cam) and _cs_cam and is_instance_valid(_cs_cam)):
			if _cs_mount:
				_cs_mount.queue_free()
			_cs_mount = null
			_cs_cam = null
			return

		var t := create_tween()
		t.set_parallel(true)
		t.set_trans(Tween.TRANS_SINE)
		t.set_ease(Tween.EASE_IN_OUT)

		# Keine Rotation zurücktweenen. Nur Position + FOV.
		t.tween_property(_cs_mount, "global_position", _prev_cam.global_position, intro_camera_return_time)
		t.tween_property(_cs_cam, "fov", _prev_cam.fov, intro_camera_return_time)

		t.chain().tween_callback(func():
			if _prev_cam and is_instance_valid(_prev_cam):
				_prev_cam.make_current()
			if _cs_mount and is_instance_valid(_cs_mount):
				_cs_mount.queue_free()
			_cs_mount = null
			_cs_cam = null
		)
		
func _play_intro_boss_anim(anim_name: String, speed: float, fallback_time: float = 1.5) -> void:
	if String(anim_name).is_empty():
		return

	_face_camera()

	if anim_player == null:
		await get_tree().create_timer(fallback_time).timeout
		return

	if not anim_player.has_animation(anim_name):
		push_warning("OgerBoss: Intro-Animation fehlt: %s" % anim_name)
		await get_tree().create_timer(fallback_time).timeout
		return

	var real_speed := maxf(absf(speed), 0.01)
	var anim := anim_player.get_animation(anim_name)
	var wait_time := (anim.length / real_speed) + 0.05

	# Wichtig: alte Animation hart stoppen, dann neue Animation sauber starten.
	anim_player.stop()
	anim_player.play(anim_name, -1.0, speed)
	anim_player.advance(0.0)

	# Wichtig: einen Frame geben, damit AnimationPlayer seinen State sauber setzt.
	await get_tree().process_frame

	var elapsed := 0.0

	while elapsed < wait_time:
		_face_camera()

		# Nur abbrechen, wenn wirklich eine ANDERE Animation läuft.
		# Nicht abbrechen, nur weil is_playing() kurz false ist.
		if anim_player.current_animation != anim_name:
			return

		await get_tree().process_frame
		elapsed += get_process_delta_time()
		
func _play_intro_slam_fixed(
	anim_name: String,
	speed: float,
	wait_time: float,
	impact_time: float
) -> void:
	if String(anim_name).is_empty():
		return

	_face_camera()

	var real_speed := maxf(absf(speed), 0.01)
	var total_wait := maxf(wait_time / real_speed, 0.05)
	var impact_wait := clampf(impact_time / real_speed, 0.0, total_wait)

	if anim_player == null:
		await get_tree().create_timer(total_wait).timeout
		return

	if not anim_player.has_animation(anim_name):
		push_warning("OgerBoss: Intro-Slam-Animation fehlt: %s" % anim_name)
		await get_tree().create_timer(total_wait).timeout
		return

	# Alte Animation wirklich beenden, dann Slam sauber von Frame 0 starten.
	anim_player.stop(false)
	anim_player.play(anim_name, 0.0, speed, false)
	anim_player.seek(0.0, true)
	anim_player.advance(0.0)

	var elapsed := 0.0
	var impact_done := false

	while elapsed < total_wait:
		if not impact_done and elapsed >= impact_wait:
			impact_done = true

			if slam_sound:
				_play_sound(_audio_action, slam_sound, 0.03)

			_shake_camera(intro_slam_shake_strength, intro_slam_shake_duration)

		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _spawn_intro_roar_vfx() -> void:
	if roar_vfx_scene == null:
		push_warning("OgerBoss: roar_vfx_scene nicht zugewiesen → kein Intro-Roar-Cone")
		return

	var cam := get_viewport().get_camera_3d()
	var look = cam.global_position if cam else null

	_spawn_self_playing_vfx(
		roar_vfx_scene,
		global_position + Vector3(0, roar_vfx_height, 0),
		intro_roar_time,
		1.0,
		look
	)

func _clear_boss_intro_title() -> void:
	if _intro_title_layer and is_instance_valid(_intro_title_layer):
		_intro_title_layer.queue_free()
	_intro_title_layer = null
func _show_boss_intro_title(title_text: String) -> void:
	_clear_boss_intro_title()

	_intro_title_layer = CanvasLayer.new()
	_intro_title_layer.layer = 80
	get_tree().current_scene.add_child(_intro_title_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_title_layer.add_child(root)

	var label := Label.new()
	label.name = "BossIntroTitle"
	label.text = title_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vp := get_viewport().get_visible_rect().size
	label.position = Vector2(0.0, vp.y * 0.65)
	label.size = Vector2(vp.x, 90.0)

	label.modulate = Color.BLACK
	label.scale = Vector2(0.92, 0.92)
	label.pivot_offset = label.size * 0.5

	label.add_theme_font_size_override("font_size", 58)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.0, 1.0))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)

	var title_font_path := "res://menu/assets/fonts/Cinzel-Bold.ttf"
	var main_font_path := "res://menu/assets/fonts/Merriweather-Regular.ttf"

	if ResourceLoader.exists(title_font_path):
		label.add_theme_font_override("font", load(title_font_path))
	elif ResourceLoader.exists(main_font_path):
		label.add_theme_font_override("font", load(main_font_path))

	root.add_child(label)

	var t := create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate", Color.WHITE, intro_title_fade_in)
	t.tween_property(label, "scale", Vector2.ONE, intro_title_fade_in)
	
func _hide_boss_intro_title() -> void:
	if _intro_title_layer == null or not is_instance_valid(_intro_title_layer):
		return

	var label := _intro_title_layer.find_child("BossIntroTitle", true, false) as Label
	if label == null:
		_clear_boss_intro_title()
		return

	var t := create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_IN)
	t.tween_property(label, "modulate:a", 0.0, intro_title_fade_out)
	t.tween_property(label, "scale", Vector2(1.06, 1.06), intro_title_fade_out)

	await t.finished
	_clear_boss_intro_title()

func _enter_armor_break_sit() -> void:
	_state = State.ARMOR_BREAK_SIT
	_state_timer = armor_break_sit_time
	_player_locked = false
	_land_confirm = 0.0
	_armor_break_wait_clock = 0.0
	velocity = Vector3.ZERO
	_face_camera()
	_play_anim(armor_break_sit_anim, 1.0)
	# Dramatische Pause: Boss-Owner hält Stille, Overworld blitzt nicht durch.
	MusicManager.push_silence(BOSS_MUSIC_OWNER, boss_music_priority, armor_break_music_fade)
	_camera_focus(true)

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

		if _cs_mount and is_instance_valid(_cs_mount):
			_cs_mount.queue_free()
			_cs_mount = null
			_cs_cam = null

		_cs_mount = Node3D.new()
		get_tree().current_scene.add_child(_cs_mount)

		_cs_cam = Camera3D.new()
		_cs_mount.add_child(_cs_cam)

		if _prev_cam and is_instance_valid(_prev_cam):
			# ArmorBreak übernimmt bewusst den aktuellen Spielkamera-Winkel.
			_cs_mount.global_transform = _prev_cam.global_transform
			_cs_cam.fov = _prev_cam.fov
			_cs_cam.near = _prev_cam.near
			_cs_cam.far = _prev_cam.far

		_cs_cam.position = Vector3.ZERO
		_cs_cam.rotation = Vector3.ZERO
		_cs_cam.make_current()

		var fwd := -_cs_mount.global_transform.basis.z.normalized()
		var focus := global_position + Vector3(0.0, cutscene_cam_focus_height, 0.0)
		var target_pos := focus - fwd * cutscene_cam_distance

		var t := create_tween()
		t.set_parallel(true)
		t.set_trans(Tween.TRANS_SINE)
		t.set_ease(Tween.EASE_OUT)
		t.tween_property(_cs_mount, "global_position", target_pos, cutscene_cam_move_time)
		t.tween_property(_cs_cam, "fov", _cs_cam.fov * cutscene_zoom, cutscene_cam_move_time)

	else:
		if _cs_mount == null or not is_instance_valid(_cs_mount):
			return

		if not (_prev_cam and is_instance_valid(_prev_cam) and _cs_cam and is_instance_valid(_cs_cam)):
			if _cs_mount and is_instance_valid(_cs_mount):
				_cs_mount.queue_free()
			_cs_mount = null
			_cs_cam = null
			return

		var t := create_tween()
		t.set_parallel(true)
		t.set_trans(Tween.TRANS_SINE)
		t.set_ease(Tween.EASE_IN_OUT)
		t.tween_property(_cs_mount, "global_position", _prev_cam.global_position, 0.7)
		t.tween_property(_cs_cam, "fov", _prev_cam.fov, 0.7)
		t.tween_property(_cs_cam, "position", Vector3.ZERO, 0.25)

		t.chain().tween_callback(func():
			if _prev_cam and is_instance_valid(_prev_cam):
				_prev_cam.make_current()
			if _cs_mount and is_instance_valid(_cs_mount):
				_cs_mount.queue_free()
			_cs_mount = null
			_cs_cam = null
		)

func _get_camera_pan_position_for_focus(focus: Vector3) -> Vector3:
	if _cs_mount == null or not is_instance_valid(_cs_mount):
		return focus

	var cam_pos := _cs_mount.global_position

	# Aktuelle Blickrichtung der Kamera.
	# Diese wird NICHT verändert.
	var fwd := -_cs_mount.global_transform.basis.z.normalized()

	var to_focus := focus - cam_pos
	var depth := to_focus.dot(fwd)

	# Falls der Fokuspunkt aus irgendeinem Grund nicht sinnvoll vor der Kamera liegt,
	# Fallback auf alte Distanzlogik — aber weiterhin ohne Rotation.
	if depth <= 0.1:
		return focus - fwd * cutscene_cam_distance

	# Punkt, der aktuell in der Bildmitte liegt, auf derselben Tiefe wie der Oger.
	var center_point_at_focus_depth := cam_pos + fwd * depth

	# Das ist die reine Pan-Verschiebung:
	# Kamera wird so verschoben, dass der Oger auf der Bildmitten-Achse liegt.
	var pan_delta := focus - center_point_at_focus_depth

	return cam_pos + pan_delta

func _start_phase2_music() -> void:
	if phase2_boss_music == null:
		return
	MusicManager.push_music(BOSS_MUSIC_OWNER, phase2_boss_music,
		boss_music_priority, 0.0) 
	
func vector_anchor_blocks() -> bool:
	return _is_phase2() and not _is_dead and not _in_armor_break() and not _in_finisher

func on_vector_anchor_blocked(player_node: Node) -> void:
	_enter_vector_block()
	if player_node and is_instance_valid(player_node) and player_node.has_method("take_damage"):
		player_node.take_damage(vector_block_damage, global_position)
	if vector_block_sound:
		_play_sound(_audio_action, vector_block_sound, 0.0)
	# ImpactVFX am Treffer-Punkt (= Spielerposition), damage=0 weil take_damage schon HP gezogen hat
	if vector_block_vfx_scene and player_node and is_instance_valid(player_node):
		_spawn_self_playing_vfx(vector_block_vfx_scene,
			player_node.global_position, vector_block_vfx_lifetime,
			1.0, null, 0)
			
func _enter_vector_block() -> void:
	_state = State.VECTOR_BLOCK
	_state_timer = vector_block_time
	velocity.x = 0.0
	velocity.z = 0.0
	var p := _get_player()
	if p and is_instance_valid(p):
		var d := p.global_position - global_position
		d.y = 0.0
		if d.length() > 0.01:
			_face_direction(d.normalized())
	_play_anim(vector_block_anim, vector_block_anim_speed)

func _process_vector_block(delta: float) -> void:
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


func _die() -> void:
	_cleanup_charge_thrust()
	if _is_dead or _in_finisher:
		return
	if _finisher_director and _finisher_director.has_method("start_finisher"):
		_in_finisher = true
		# _stop_boss_music() hier ENTFERNT — Boss-Owner bleibt aktiv,
		# damit der Finisher/das Outro nahtlos übernehmen kann.
		_finisher_director.start_finisher(self, _get_player())
		await _finisher_director.finisher_complete
		_in_finisher = false
	_die_for_real()

func _die_for_real() -> void:
	if _is_dead: return
	_is_dead = true
	_state = State.DEAD
	
	if has_node("/root/CombatManager"):
		CombatManager.disengage_enemy(self)
	
	velocity = Vector3.ZERO
	
	# Defeated-Flag persistieren (BEVOR queue_free, damit Truhe es lesen kann)
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("set_flag"):
		gm.set_flag("boss_defeated_" + boss_id, true)
	
	# Boss-Ash-Death
	if boss_ash_death_scene and boss_sprite:
		var ash := boss_ash_death_scene.instantiate()
		get_tree().current_scene.add_child(ash)
		if ash.has_method("play"):
			ash.play(boss_sprite)
	
	if _boss_bar and _boss_bar.has_method("vanish"):
		_boss_bar.vanish()
	_stop_boss_music()
	
	# Chest-Reveal mit Delay
	_schedule_chest_reveal()
	
	get_tree().create_timer(5.0).timeout.connect(queue_free)

 
func _schedule_chest_reveal() -> void:
	if chest_reveal_scene == null or linked_chest_path.is_empty():
		return
	
	var chest := get_node_or_null(linked_chest_path) as Node3D
	if chest == null:
		push_warning("OgerBoss: linked_chest_path zeigt nicht auf eine gueltige Truhe.")
		return
	
	# Position JETZT abgreifen - Boss queue_freet sich gleich,
	# aber Truhe steht eigenstaendig in der Welt und bleibt erreichbar.
	var chest_pos := chest.global_position
	
	get_tree().create_timer(chest_reveal_delay).timeout.connect(
		_spawn_chest_reveal.bind(chest_pos, chest)
	)
 
 
func _spawn_chest_reveal(spawn_pos: Vector3, chest: Node3D) -> void:
	if not is_instance_valid(chest):
		return
	
	var reveal := chest_reveal_scene.instantiate()
	get_tree().current_scene.add_child(reveal)
	reveal.global_position = spawn_pos
	
	if reveal.has_method("set_target_chest"):
		reveal.set_target_chest(chest)
	if reveal.has_method("play"):
		reveal.play()


	


# === HELPERS ===
func _spawn_death_scene(scene: PackedScene) -> Node3D:
	if scene == null:
		return null

	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null

	get_tree().current_scene.add_child(inst)

	# AshDeath-Sonderfall:
	# Diese Szene braucht boss_sprite und startet NICHT automatisch.
	if inst.has_method("play"):
		var sprite_mesh := boss_sprite as MeshInstance3D
		if sprite_mesh:
			inst.play(sprite_mesh)
		else:
			push_warning("OgerBoss: death_scene hat play(), aber boss_sprite ist kein MeshInstance3D.")
			inst.global_position = global_position
	else:
		# Normale zweite Death-Szene: einfach an Oger-Position spawnen.
		inst.global_position = global_position
		_start_generic_death_vfx(inst)

	return inst

func play_outro_music(track: AudioStream) -> void:
	MusicManager.push_music(BOSS_MUSIC_OWNER, track, boss_music_priority, 1.0)

func _start_generic_death_vfx(inst: Node3D) -> void:
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		var clip: String = ap.autoplay if ap.autoplay != "" else "impact"
		if ap.has_animation(clip):
			ap.play(clip)

	for ps in inst.find_children("*", "GPUParticles3D", true, false):
		ps.emitting = true

	for ps in inst.find_children("*", "CPUParticles3D", true, false):
		ps.emitting = true


func _disable_death_interaction() -> void:
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO

	for n in find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if cs:
			cs.disabled = true

	for n in find_children("*", "Area3D", true, false):
		var area := n as Area3D
		if area:
			area.monitoring = false
			area.monitorable = false
			area.collision_layer = 0
			area.collision_mask = 0



func _trigger_phase2_hit_feedback(from_position: Vector3) -> void:
	_hit_flash_timer = hit_flash_duration
	
	var dir := global_position - from_position
	dir.y = 0.0
	if dir.length() > 0.001:
		_hit_knockback = dir.normalized() * hit_bounce_strength

func _update_hit_flash(delta: float) -> void:
	if boss_sprite == null:
		return
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0:
			boss_sprite.modulate = Color.WHITE
		else:
			boss_sprite.modulate = hit_flash_color


func _pick_attack(dist: float) -> String:
	var candidates: Array[Dictionary] = []
	
	# Slam: nur in Schlagdistanz
	if dist <= attack_range:
		candidates.append({"name": "slam", "weight": slam_weight})
	
	# Charge: Cooldown frei und in Charge-Range
	if _charge_cooldown <= 0.0 \
	and dist >= charge_min_distance and dist <= charge_max_distance:
		candidates.append({"name": "charge", "weight": charge_weight})
	
	# Butt: nur Phase 2, Cooldown frei, in Butt-Range
	if _is_phase2() and _butt_cooldown <= 0.0 \
	and dist >= butt_min_distance and dist <= butt_max_distance:
		candidates.append({"name": "butt", "weight": butt_weight})
	
	if candidates.is_empty():
		return ""
	
	var total_weight: float = 0.0
	for c in candidates:
		total_weight += c["weight"]
	
	var roll: float = randf() * total_weight
	var accum: float = 0.0
	for c in candidates:
		accum += c["weight"]
		if roll <= accum:
			return c["name"]
	
	return candidates[-1]["name"]

func get_finisher_mount_position() -> Vector3:
	if _finisher_mount_point != null:
		return _finisher_mount_point.global_position
	return global_position + Vector3(0, 1.0, 0) 

func cinematic_play_anim(anim_name: String, speed: float = 1.0) -> void:
	_play_anim(anim_name, speed)

func cinematic_slam_impact(world_pos: Vector3) -> void:
	if slam_vfx_scene:
		_spawn_self_playing_vfx(slam_vfx_scene,
			world_pos + Vector3(0, 0.02, 0),
			slam_vfx_lifetime, 1.0, null, 0)
	if slam_sound:
		_play_sound(_audio_action, slam_sound, 0.0)
	_shake_camera(slam_shake_strength, slam_shake_duration)

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
		
var _cf_active: bool = false
var _cf_saved_collision_layer: int = 0
var _cf_saved_collision_mask: int = 0
var _cf_saved_physics_process: bool = true
var _cf_saved_velocity: Vector3 = Vector3.ZERO
var _cf_saved_top_level: bool = false

func set_cinematic_freeze(freeze: bool) -> void:
	if freeze == _cf_active:
		return
	_cf_active = freeze

	if freeze:
		_cf_saved_collision_layer = collision_layer
		_cf_saved_collision_mask = collision_mask
		_cf_saved_physics_process = is_physics_processing()
		_cf_saved_velocity = velocity
		_cf_saved_top_level = top_level

		collision_layer = 0
		collision_mask = 0
		velocity = Vector3.ZERO
		set_physics_process(false)
		
		# top_level entkoppelt den Transform von Parent-Bewegungen UND
		# — wichtig — verhindert dass AnimationPlayer-Tracks auf dem Wurzelknoten
		# die globale Position schreiben, falls die Animation Root-Motion hat.
		# Setze das NUR wenn der Boss tatsächlich ein Top-Level-Node ist.
		# Bei Animation-Root-Motion brauchst du zusätzlich Transform-Keys
		# in der Animation deaktivieren oder lokale Transform-Tracks nutzen.
	else:
		collision_layer = _cf_saved_collision_layer
		collision_mask = _cf_saved_collision_mask
		velocity = Vector3.ZERO  # niemals alte Velocity reaktivieren
		set_physics_process(_cf_saved_physics_process)

func is_cinematic_frozen() -> bool:
	return _cf_active
		

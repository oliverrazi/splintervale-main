extends CharacterBody3D
class_name Goblin

# --- Sprite Setup ---
@export_group("Sprite")
@export var HFRAMES: int = 10
@export var VFRAMES: int = 10

# --- Movement ---
@export_group("Movement")
@export var WALK_SPEED: float = 1.0
@export var RUN_SPEED: float = 2.0
@export var CHARGE_SPEED: float = 10.0
@export var CHARGE_DECELERATION: float = 60.0
@export var STRAFE_SPEED: float = 1.0

# --- Patrol ---
@export_group("Patrol")
@export var patrol_radius: float = 3.0
@export var patrol_wait_time_min: float = 1.0
@export var patrol_wait_time_max: float = 1.0

# --- Combat ---
@export_group("Combat")
@export var max_health: int = 30
@export var damage: int = 5
@export var circle_time_min: float = 0.3
@export var circle_time_max: float = 0.8
@export var circle_steps_min: int = 1
@export var circle_steps_max: int = 2
@export var circle_pause_min: float = 0.3
@export var circle_pause_max: float = 0.8
@export var attack_chance_per_pause: float = 0.3
@export var charge_duration: float = 0.4
@export var attack_recovery: float = 0.8
@export var knockback_strength: float = 0.5

# --- Detection ---
@export_group("Detection")
@export var detection_range: float = 0.1
@export var lose_interest_range: float = 12.0
@export var preferred_distance: float = 1
@export var preferred_distance_tolerance: float = 0.3

@export_group("Obstacle Avoidance")
@export var stuck_detection_time: float = 0.4
@export var stuck_min_movement: float = 0.05
@export var strafe_raycast_length: float = 1.5
@export var strafe_escape_duration: float = 0.6

# --- Neue Variablen bei den internen Vars ---
var _last_position_check: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0
var _stuck_check_initialized: bool = false  # NEU
var _is_strafe_escaping: bool = false
var _strafe_escape_timer: float = 0.0
var _strafe_escape_dir: Vector3 = Vector3.ZERO

# --- Animation ---
@export_group("Animation")
@export var WALK_FPS: float = 6.0
@export var RUN_FPS: float = 10.0
@export var HIT_FPS: float = 5.0
@export var hit_flash_duration: float = 0.15

@export_group("Loot")
@export var exp_reward: int = 25
@export var gold_reward_min: int = 5
@export var gold_reward_max: int = 15

# --- Thrust VFX ---
@export_group("Thrust VFX")
@export var thrust_scene: PackedScene
@export var thrust_offset: float = 0.4
@export var thrust_height: float = 0.15
@export var thrust_scale: Vector3 = Vector3(0.4, 0.4, 0.4)

@export_subgroup("Offsets per Direction")
@export var thrust_offset_up: Vector3 = Vector3(0.0, 0.0, -0.4)
@export var thrust_offset_up_right: Vector3 = Vector3(0.28, 0.0, -0.28)
@export var thrust_offset_right: Vector3 = Vector3(0.4, 0.0, 0.0)
@export var thrust_offset_down_right: Vector3 = Vector3(0.28, 0.0, 0.28)
@export var thrust_offset_down: Vector3 = Vector3(0.0, 0.0, 0.4)
@export var thrust_offset_down_left: Vector3 = Vector3(-0.28, 0.0, 0.28)
@export var thrust_offset_left: Vector3 = Vector3(-0.4, 0.0, 0.0)
@export var thrust_offset_up_left: Vector3 = Vector3(-0.28, 0.0, -0.28)


@export_group("Alert")
@export var alert_popup_scene: PackedScene
@export var alert_duration: float = 1
@export var alert_offset: Vector3 = Vector3(0, 0.2, 0)

@export_group("HP Bar")
@export var hp_bar_scene: PackedScene
@export var hp_bar_offset: Vector3 = Vector3(0, 0.45, 0)

var _hp_bar: EnemyHPBar = null

# --- Frame Definitions ---
# Idle (1 Frame each)
const IDLE_RIGHT: Array[int] = [0, 0]
const IDLE_RIGHT_BOTTOM: Array[int] = [2, 2]
const IDLE_BOTTOM: Array[int] = [4, 4]
const IDLE_LEFT_TOP: Array[int] = [6, 6]
const IDLE_TOP: Array[int] = [8, 8]

# Walk (7 Frames each)
const WALK_DOWN: Array[int] = [11, 15, 12, 15]
const WALK_UP: Array[int] = [21, 25, 22, 25]

# Run (7 Frames each)
const RUN_DOWN_START: int = 10
const RUN_DOWN_END: int = 16
const RUN_UP_START: int = 20
const RUN_UP_END: int = 26

# Attack Frames (separate frames for windup and attack)
# [0] = Windup/Charge frame, [1] = Attack/Strike frame
const ATTACK_RIGHT: Array[int] = [30, 31]
const ATTACK_RIGHT_BOTTOM: Array[int] = [32, 33]
const ATTACK_BOTTOM: Array[int] = [34, 35]
const ATTACK_LEFT_TOP: Array[int] = [36, 37]
const ATTACK_TOP: Array[int] = [38, 39]

# Hurt Frames
const HURT_DOWN_RIGHT: int = 40
const HURT_UP_RIGHT: int = 41

# Death Animation
const DEATH_FRAMES: Array[int] = [50, 51, 52]
const DEATH_FPS: float = 8.0

@export_group("Death VFX")
@export var death_vfx_scene: PackedScene
@export var death_vfx_lifetime: float = 1.0
@export var death_vfx_scale: float = 1.0
@export var death_hold_time: float = 0.5  # Wie lange Frame 52 gehalten wird
@export var death_dissolve_time: float = 0.5  # Wie lange das Auflösen dauert


@export var freeze_distance: float = 25.0
@export var unfreeze_distance: float = 25.0 


var _is_frozen: bool = false
var _player_ref: Node3D = null


# --- Thrust VFX Rotation für 8 Richtungen ---
const THRUST_YAW_DEG := {
	DirMode.LEFT: 270.0,
	DirMode.UP_LEFT: 225.0,
	DirMode.UP: 180.0,
	DirMode.UP_RIGHT: 135.0,
	DirMode.RIGHT: 90.0,
	DirMode.DOWN_RIGHT: 45.0,
	DirMode.DOWN: 0.0,
	DirMode.DOWN_LEFT: 315.0,
}

# --- State Machine ---
enum State { 
	PATROL_IDLE,
	PATROL_WALK,
	ALERT,
	CHASE,
	CIRCLE_IDLE,
	CIRCLE_STRAFE,
	ATTACK_WINDUP,
	ATTACK_CHARGE,
	ATTACK_RECOVERY,
	HIT,
	DEAD 
}
var current_state: State = State.PATROL_IDLE

# --- Direction (8 directions) ---
enum DirMode { 
	DOWN, UP, LEFT, RIGHT, 
	DOWN_LEFT, DOWN_RIGHT, UP_LEFT, UP_RIGHT 
}
var _facing_dir: int = DirMode.DOWN

# --- Internal ---
var _health: int
var _target: Node3D = null
var _anim_time: float = 0.0
var _state_timer: float = 0.0
var _hit_timer: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO

# Patrol
var _spawn_position: Vector3
var _patrol_target: Vector3

# Circle/Strafe
var _strafe_direction: int = 1
var _strafe_steps_remaining: int = 0

# Attack
var _charge_direction: Vector3 = Vector3.ZERO
var _charge_speed_current: float = 0.0
var _has_hit_player: bool = false



var _active_thrust_vfx: Node3D = null
var _thrust_material: ShaderMaterial = null
var _flicker_tween: Tween = null

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _group: EnemyGroup = null

@onready var sprite: Sprite3D = $Sprite3D
@onready var detection_area: Area3D = $DetectionArea
@onready var attack_area: Area3D = $AttackArea

var _death_phase: int = 0  # 0 = Animation, 1 = Hold, 2 = Dissolve
var _death_timer: float = 0.0




func _ready() -> void:
	_health = max_health
	_spawn_position = global_position
	_last_position_check = global_position
	
	_player_ref = get_tree().get_first_node_in_group("player")
	
	if sprite:
		sprite.hframes = HFRAMES
		sprite.vframes = VFRAMES
	
	_setup_hp_bar()
	
	call_deferred("_setup_detection")
	
	# Zufälliger Start-Offset für Desync
	_state_timer = randf_range(0.0, patrol_wait_time_max)
	current_state = State.PATROL_IDLE
	
	
func _setup_hp_bar() -> void:
	if hp_bar_scene == null:
		return
	
	_hp_bar = hp_bar_scene.instantiate() as EnemyHPBar
	add_child(_hp_bar)
	_hp_bar.position = hp_bar_offset
	
func _spawn_alert_popup() -> void:
	if alert_popup_scene == null:
		return
	
	var popup := alert_popup_scene.instantiate() as AlertPopup
	add_child(popup)
	popup.position = alert_offset

func _setup_detection() -> void:
	# Warte einen Frame damit _group gesetzt werden kann
	if detection_area:
		if _group != null:
			# In Gruppe - eigene Detection deaktivieren
			detection_area.monitoring = false
			detection_area.monitorable = false
		else:
			# Keine Gruppe - individuelle Detection
			var detection_shape := detection_area.get_node_or_null("CollisionShape3D")
			if detection_shape and detection_shape.shape is SphereShape3D:
				detection_shape.shape.radius = detection_range
			detection_area.body_entered.connect(_on_detection_body_entered)
			detection_area.body_exited.connect(_on_detection_body_exited)
			print(name, ": Using individual detection with range ", detection_range)

func _check_freeze_state() -> void:
	if not _player_ref or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player")
		return
	
	var dist := global_position.distance_to(_player_ref.global_position)
	
	if _is_frozen:
		if dist < unfreeze_distance:
			_unfreeze()
	else:
		if dist > freeze_distance:
			_freeze()


func _freeze() -> void:
	if _is_frozen:
		return
	
	_is_frozen = true
	velocity = Vector3.ZERO
	
	# Speichere die XZ-Position, Y wird beim Unfreeze neu berechnet
	_spawn_position.x = global_position.x
	_spawn_position.z = global_position.z
	
	set_physics_process(false)


func _unfreeze() -> void:
	if not _is_frozen:
		return
	
	_is_frozen = false
	
	# Einfach leicht anheben - Gravity erledigt den Rest
	global_position.y = _spawn_position.y + 1.0
	velocity = Vector3.ZERO
	
	set_physics_process(true)

func _process(delta: float) -> void:
	# Freeze-Check läuft immer (in _process, nicht _physics_process)
	_check_freeze_state()
	

func _physics_process(delta: float) -> void:

	if not is_on_floor():
		velocity.y -= gravity * delta
	
	if global_position.y < _spawn_position.y - 5.0:
		global_position = _spawn_position
		global_position.y += 1.5
		velocity = Vector3.ZERO
		return
	
	if current_state not in [State.DEAD, State.HIT, State.ATTACK_CHARGE, State.ATTACK_WINDUP, State.ALERT]:
		_check_player_detection()
	
	match current_state:
		State.PATROL_IDLE:
			_process_patrol_idle(delta)
		State.PATROL_WALK:
			_process_patrol_walk(delta)
		State.ALERT: 
			_process_alert(delta)
		State.CHASE:
			_process_chase(delta)
		State.CIRCLE_IDLE:
			_process_circle_idle(delta)
		State.CIRCLE_STRAFE:
			_process_circle_strafe(delta)
		State.ATTACK_WINDUP:
			_process_attack_windup(delta)
		State.ATTACK_CHARGE:
			_process_attack_charge(delta)
		State.ATTACK_RECOVERY:
			_process_attack_recovery(delta)
		State.HIT:
			_process_hit(delta)
		State.DEAD:
			_process_dead(delta)
	
	# ENTFERNT: if _state_timer > 0.0: _state_timer -= delta
	
	_update_thrust_vfx_position()
	move_and_slide()


func _check_player_detection() -> void:
	# Wenn in Gruppe, überlässt die Gruppe die Detection
	# ABER: Reagiere trotzdem wenn kürzlich Schaden erhalten
	if _group != null and not _was_recently_damaged():
		return
	
	# Target finden falls nicht vorhanden
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player")
	
	if _target == null:
		return
	
	var distance := global_position.distance_to(_target.global_position)
	
	# Re-Aggro Bedingungen:
	# 1. Spieler in Detection Range
	# 2. ODER kürzlich Schaden erhalten (dann größere Range)
	var effective_range := detection_range
	if _was_recently_damaged():
		effective_range = lose_interest_range  # Größere Range wenn beschädigt
	
	
	if distance <= effective_range:
		# Nur State wechseln wenn nicht bereits im Kampf
		if current_state in [State.PATROL_IDLE, State.PATROL_WALK]:
			_enter_state(State.ALERT)
		# Auch während ATTACK_RECOVERY wieder Chase aufnehmen
		elif current_state == State.ATTACK_RECOVERY and distance > preferred_distance + preferred_distance_tolerance:
			_enter_state(State.CHASE)
			
var _last_damage_time: float = -5.0
			
func _was_recently_damaged() -> bool:
	var current_time := Time.get_ticks_msec() / 1000.0
	return (current_time - _last_damage_time) < 5.0  # 5 Sekunden "wütend"
	

# ============ STATE MANAGEMENT ============

func _enter_state(new_state: State) -> void:
	current_state = new_state
	_anim_time = 0.0
	
	match new_state:
		State.PATROL_IDLE:
			_state_timer = randf_range(patrol_wait_time_min, patrol_wait_time_max)
			velocity.x = 0.0
			velocity.z = 0.0
			_reset_stuck_detection()
		
		State.PATROL_WALK:
			_patrol_target = _get_random_patrol_point()
			_reset_stuck_detection()
			
		State.ALERT:
			_state_timer = alert_duration
			velocity.x = 0.0
			velocity.z = 0.0
			_reset_stuck_detection()
			_spawn_alert_popup()
			if _target and is_instance_valid(_target):
				var dir := (_target.global_position - global_position)
				dir.y = 0
				_update_facing_direction(dir.normalized())
		
		State.CHASE:
			_reset_stuck_detection()
		
		State.CIRCLE_IDLE:
			_state_timer = randf_range(circle_pause_min, circle_pause_max)
			velocity.x = 0.0
			velocity.z = 0.0
			_reset_stuck_detection()
			if _target and is_instance_valid(_target):
				var dir := (_target.global_position - global_position)
				dir.y = 0
				_update_facing_direction(dir.normalized())
		
		State.CIRCLE_STRAFE:
			_reset_stuck_detection()
			if _group:
				_strafe_direction = _group.get_optimal_strafe_direction(self, _target.global_position)
			elif randf() > 0.7:
				_strafe_direction *= -1
			
			_strafe_steps_remaining = randi_range(circle_steps_min, circle_steps_max)
			_state_timer = randf_range(0.3, 0.6)
		
		State.ATTACK_WINDUP:
			_state_timer = 0.4
			velocity.x = 0.0
			velocity.z = 0.0
			_reset_stuck_detection()
			if _target and is_instance_valid(_target):
				var dir := (_target.global_position - global_position)
				dir.y = 0
				_charge_direction = dir.normalized()
				_update_facing_direction(_charge_direction)
		
		State.ATTACK_CHARGE:
			_charge_speed_current = CHARGE_SPEED
			_has_hit_player = false
			_state_timer = charge_duration
			_reset_stuck_detection()
			if _target and is_instance_valid(_target):
				var dir := (_target.global_position - global_position)
				dir.y = 0
				_charge_direction = dir.normalized()
			_spawn_thrust_vfx()
		
		State.ATTACK_RECOVERY:
			_state_timer = attack_recovery
			velocity.x = 0.0
			velocity.z = 0.0
			_reset_stuck_detection()
			_cleanup_thrust_vfx_immediate()
		
		State.HIT:
			_hit_timer = 0.3
			_reset_stuck_detection()
			_cleanup_thrust_vfx_immediate()
		
		State.DEAD:
			velocity.x = 0.0
			velocity.z = 0.0
			_reset_stuck_detection()
			_cleanup_thrust_vfx_immediate()
			_death_phase = 0
			_death_timer = 0.0
			_anim_time = 0.0


func _process_alert(delta: float) -> void:
	# Idle Animation während Alert
	_animate_idle()
	
	# Zum Ziel schauen
	if _target and is_instance_valid(_target):
		var dir := (_target.global_position - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			_update_facing_direction(dir.normalized())
	
	_state_timer -= delta
	
	if _state_timer <= 0:
		_enter_state(State.CHASE)

func _spawn_thrust_vfx() -> void:
	if thrust_scene == null:
		return

	_cleanup_thrust_vfx_immediate()

	_active_thrust_vfx = thrust_scene.instantiate() as Node3D
	add_child(_active_thrust_vfx)

	var offset := _get_thrust_offset()
	_active_thrust_vfx.position = offset
	_active_thrust_vfx.position.y = thrust_height

	_active_thrust_vfx.scale = thrust_scale

	var yaw: float = THRUST_YAW_DEG.get(_facing_dir, 180.0)
	_active_thrust_vfx.rotation_degrees.y = yaw

	var mesh: MeshInstance3D = _active_thrust_vfx.get_node_or_null("MeshInstance3D")

	if mesh == null:
		_cleanup_thrust_vfx_immediate()
		return

	_thrust_material = mesh.material_override as ShaderMaterial

	if _thrust_material == null:
		_cleanup_thrust_vfx_immediate()
		return

	_thrust_material = _thrust_material.duplicate() as ShaderMaterial
	mesh.material_override = _thrust_material

	_thrust_material.set_shader_parameter("time_offset", randf() * 100.0)
	_thrust_material.set_shader_parameter("flicker", 1.0)
	
	# Hitbox Setup
	var hit_area: Area3D = _active_thrust_vfx.get_node_or_null("HitArea")
	if hit_area:
		hit_area.body_entered.connect(_on_thrust_hit)
	
	_start_flicker_loop()

func _get_hurt_frame() -> Dictionary:
	# Basierend auf Blickrichtung den richtigen Hurt-Frame wählen
	match _facing_dir:
		DirMode.DOWN, DirMode.DOWN_RIGHT, DirMode.RIGHT:
			return {frame = HURT_DOWN_RIGHT, flip = false}
		DirMode.DOWN_LEFT, DirMode.LEFT:
			return {frame = HURT_DOWN_RIGHT, flip = true}
		DirMode.UP, DirMode.UP_RIGHT:
			return {frame = HURT_UP_RIGHT, flip = false}
		DirMode.UP_LEFT:
			return {frame = HURT_UP_RIGHT, flip = true}
		_:
			return {frame = HURT_DOWN_RIGHT, flip = false}
			


func _on_thrust_hit(body: Node3D) -> void:
	# Nicht sich selbst treffen
	if body == self:
		return
	
	# Nur während ATTACK_CHARGE Schaden machen
	if current_state != State.ATTACK_CHARGE:
		return
	
	# Bereits getroffen?
	if _has_hit_player:
		return
	
	# Nur Player treffen
	if body.has_method("take_damage"):
		_has_hit_player = true
		body.take_damage(damage, global_position)
		
		


func _start_flicker_loop() -> void:
	if _thrust_material == null:
		return

	if _flicker_tween and _flicker_tween.is_valid():
		_flicker_tween.kill()

	_flicker_tween = create_tween()
	_flicker_tween.set_loops(0)

	# Subtiles Flackern der gesamten Kuppel
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 0.8, 0.05)
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 1.1, 0.04)
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 0.9, 0.06)
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 1.15, 0.03)
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 0.95, 0.05)
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 1.0, 0.04)
	
	

func _update_thrust_vfx_position() -> void:
	if _active_thrust_vfx == null or not is_instance_valid(_active_thrust_vfx):
		return
	
	var offset := _get_thrust_offset()
	_active_thrust_vfx.global_position = global_position + offset
	_active_thrust_vfx.global_position.y = global_position.y + thrust_height


func _get_thrust_offset() -> Vector3:
	match _facing_dir:
		DirMode.UP:
			return thrust_offset_up
		DirMode.UP_RIGHT:
			return thrust_offset_up_right
		DirMode.RIGHT:
			return thrust_offset_right
		DirMode.DOWN_RIGHT:
			return thrust_offset_down_right
		DirMode.DOWN:
			return thrust_offset_down
		DirMode.DOWN_LEFT:
			return thrust_offset_down_left
		DirMode.LEFT:
			return thrust_offset_left
		DirMode.UP_LEFT:
			return thrust_offset_up_left
		_:
			return thrust_offset_down


func _cleanup_thrust_vfx_immediate() -> void:
	
	if _flicker_tween and _flicker_tween.is_valid():
		_flicker_tween.kill()
	_flicker_tween = null
	
	_thrust_material = null
	
	if _active_thrust_vfx and is_instance_valid(_active_thrust_vfx):
		_active_thrust_vfx.queue_free()
	_active_thrust_vfx = null


# ============ STATE PROCESSING ============

func _process_patrol_idle(delta: float) -> void:
	_animate_idle()
	
	if _check_for_target():
		_enter_state(State.CHASE)
		return
	
	_state_timer -= delta  # HIER
	
	if _state_timer <= 0.0:
		_enter_state(State.PATROL_WALK)


func _process_patrol_walk(delta: float) -> void:
	if _check_for_target():
		_reset_stuck_detection()
		_enter_state(State.CHASE)
		return
		

	
	var dir := (_patrol_target - global_position)
	dir.y = 0
	var dist := dir.length()
	
	if dist < 0.2:
		_reset_stuck_detection()
		_enter_state(State.PATROL_IDLE)
		return
		
	var dist_from_spawn := (_patrol_target - _spawn_position).length()
	if dist_from_spawn > patrol_radius * 2:
		# Zurück zum Spawn gehen
		_patrol_target = _spawn_position
	
	dir = dir.normalized()
	_update_facing_direction(dir)
	
	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED
	
	_animate_walk(delta)
	
	if _check_if_stuck(delta):
		_abort_patrol()


func _process_chase(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_reset_stuck_detection()
		_enter_state(State.PATROL_IDLE)
		return
	
	var to_target := _target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()
	
	if dist > lose_interest_range:
		_reset_stuck_detection()
		_target = null
		_enter_state(State.PATROL_IDLE)
		return
	
	if dist <= preferred_distance + preferred_distance_tolerance:
		_reset_stuck_detection()
		_enter_state(State.CIRCLE_IDLE)
		return
	
	var dir := to_target.normalized()
	
	# Strafe-Escape aktiv?
	if _is_strafe_escaping:
		_strafe_escape_timer -= delta
		
		if _strafe_escape_timer <= 0.0:
			_is_strafe_escaping = false
			_reset_stuck_detection()
		else:
			# Seitlich + leicht vorwärts bewegen
			var escape_move := (_strafe_escape_dir * 0.7 + dir * 0.3).normalized()
			velocity.x = escape_move.x * RUN_SPEED
			velocity.z = escape_move.z * RUN_SPEED
			_update_facing_direction(escape_move)
			_animate_run(delta)
			return
	
	# Normale Chase-Bewegung ZUERST, dann Stuck-Check
	var separation := Vector3.ZERO
	if _group:
		separation = _group.get_separation_vector(self) * 0.5
	
	var move_dir := (dir + separation).normalized()
	_update_facing_direction(move_dir)
	
	velocity.x = move_dir.x * RUN_SPEED
	velocity.z = move_dir.z * RUN_SPEED
	
	_animate_run(delta)
	
	# Stuck-Check NACH der Bewegung (nur einmal!)
	if _check_if_stuck(delta):
		_is_strafe_escaping = true
		_strafe_escape_timer = strafe_escape_duration
		_strafe_escape_dir = _find_strafe_escape_direction(dir)
		

func _process_circle_idle(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state(State.PATROL_IDLE)
		return
	
	var to_target := _target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()
	
	if dist > lose_interest_range:
		_target = null
		_enter_state(State.PATROL_IDLE)
		return
	
	if dist > preferred_distance + preferred_distance_tolerance * 2:
		_enter_state(State.CHASE)
		return
	
	_update_facing_direction(to_target.normalized())
	_animate_idle()
	
	_state_timer -= delta  # HIER
	
	if _state_timer <= 0.0:
		if randf() < attack_chance_per_pause:
			_enter_state(State.ATTACK_WINDUP)
		else:
			_enter_state(State.CIRCLE_STRAFE)

func _process_circle_strafe(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_reset_stuck_detection()
		_enter_state(State.PATROL_IDLE)
		return
	
	var to_target := _target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()
	
	if dist > lose_interest_range:
		_reset_stuck_detection()
		_target = null
		_enter_state(State.PATROL_IDLE)
		return
	
	if dist > preferred_distance + preferred_distance_tolerance * 3:
		_reset_stuck_detection()
		_enter_state(State.CHASE)
		return
		
	if _check_if_stuck(delta):
		_strafe_direction *= -1
		_stuck_timer = 0.0
	
	var dir_to_target := to_target.normalized()
	_update_facing_direction(dir_to_target)
	
	# Seitwärts-Bewegung
	var strafe_dir := Vector3(-dir_to_target.z, 0, dir_to_target.x) * _strafe_direction
	
	# Distanz-Korrektur
	var distance_diff := dist - preferred_distance
	var distance_correction := Vector3.ZERO
	
	if abs(distance_diff) > preferred_distance_tolerance:
		var correction_strength: float = clamp(distance_diff * 0.5, -1.0, 1.0)
		distance_correction = dir_to_target * correction_strength
	
	# Separation von anderen Goblins
	var separation := Vector3.ZERO
	if _group:
		separation = _group.get_separation_vector(self)
	
	# Kombinierte Bewegungsrichtung
	var move_dir := (strafe_dir + distance_correction + separation).normalized()
	
	velocity.x = move_dir.x * STRAFE_SPEED
	velocity.z = move_dir.z * STRAFE_SPEED
	
	_animate_walk(delta)
	
	_state_timer -= delta
	
	if _state_timer <= 0.0:
		_strafe_steps_remaining -= 1
		
		if _strafe_steps_remaining <= 0:
			_enter_state(State.CIRCLE_IDLE)
		else:
			_state_timer = randf_range(0.3, 0.6)

func _process_attack_windup(delta: float) -> void:
	if _target and is_instance_valid(_target):
		var dir := (_target.global_position - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			_charge_direction = dir.normalized()
			_update_facing_direction(_charge_direction)
	
	_show_attack_windup_frame()
	
	_state_timer -= delta  # HIER
	
	if _state_timer <= 0.0:
		_enter_state(State.ATTACK_CHARGE)


func _process_attack_charge(delta: float) -> void:
	# Strafe-Escape aktiv?
	if _is_strafe_escaping:
		var strafe_move := _strafe_escape_dir * STRAFE_SPEED * 2.0
		velocity.x = strafe_move.x + _charge_direction.x * _charge_speed_current * 0.3
		velocity.z = strafe_move.z + _charge_direction.z * _charge_speed_current * 0.3
		
		# Prüfen ob wieder frei
		var horizontal_movement := Vector3(
			global_position.x - _last_position_check.x,
			0,
			global_position.z - _last_position_check.z
		).length()
		
		if horizontal_movement > stuck_min_movement * 3.0:
			_is_strafe_escaping = false
			_stuck_timer = 0.0
	else:
		# Stuck-Check nur wenn nicht am Escapen
		if _check_if_stuck(delta):
			_is_strafe_escaping = true
			_strafe_escape_dir = _find_strafe_escape_direction(_charge_direction)
		
		# Normale Charge-Bewegung
		_charge_speed_current = move_toward(_charge_speed_current, CHARGE_SPEED * 0.3, CHARGE_DECELERATION * delta)
		velocity.x = _charge_direction.x * _charge_speed_current
		velocity.z = _charge_direction.z * _charge_speed_current
	
	if not _has_hit_player:
		_check_charge_hit()
	
	_show_attack_strike_frame()
	
	_state_timer -= delta
	
	if _state_timer <= 0.0:
		_reset_stuck_detection()
		_enter_state(State.ATTACK_RECOVERY)



func _process_attack_recovery(delta: float) -> void:
	if _target and is_instance_valid(_target):
		var dir := (_target.global_position - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			_update_facing_direction(dir.normalized())
	
	_animate_idle()
	
	_state_timer -= delta  # HIER
	
	if _state_timer <= 0.0:
		if _target and is_instance_valid(_target):
			var dist := global_position.distance_to(_target.global_position)
			if dist <= lose_interest_range:
				if dist > preferred_distance + preferred_distance_tolerance:
					_enter_state(State.CHASE)
				else:
					_enter_state(State.CIRCLE_IDLE)
				return
		_enter_state(State.PATROL_IDLE)


func _process_hit(delta: float) -> void:
	_hit_timer -= delta
	
	velocity.x = _knockback_velocity.x
	velocity.z = _knockback_velocity.z
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, knockback_strength * 3.0 * delta)
	
	_animate_hit_damaged(delta)
	
	if _hit_timer <= 0.0:
		if _health <= 0:
			_enter_state(State.DEAD)
		elif _target and is_instance_valid(_target):
			_enter_state(State.CHASE)
		else:
			_enter_state(State.PATROL_IDLE)


func _process_dead(delta: float) -> void:
	match _death_phase:
		0:  # Death Animation
			_anim_time += delta
			var frame_duration: float = 1.0 / DEATH_FPS
			var frame_idx: int = int(_anim_time / frame_duration)
			
			if frame_idx >= DEATH_FRAMES.size():
				_death_phase = 1
				_death_timer = death_hold_time
				sprite.frame = DEATH_FRAMES[DEATH_FRAMES.size() - 1]
				_give_rewards()
			else:
				sprite.frame = DEATH_FRAMES[frame_idx]
			
			var data := _get_hurt_frame()
			sprite.flip_h = data.flip
			sprite.modulate = Color.WHITE
		
		1:  # Hold
			_death_timer -= delta
			if _death_timer <= 0.0:
				_spawn_death_vfx()
				_death_phase = 2
				_death_timer = death_dissolve_time
		
		2:  # Dissolve
			_death_timer -= delta
			var progress: float = 1.5 - (_death_timer / death_dissolve_time)
			sprite.modulate.a = 1.0 - progress
			
			if _death_timer <= 0.0:
				# Aus Gruppe entfernen
				if _group:
					_group.remove_goblin(self)
				queue_free()
				
func _give_rewards() -> void:
	# EXP vergeben
	GameManager.player_data.add_exp(exp_reward)
	
	# Gold vergeben (zufällig im Bereich)
	var gold_amount := randi_range(gold_reward_min, gold_reward_max)
	GameManager.player_data.add_gold(gold_amount)
	
	print("Rewards: +", exp_reward, " EXP, +", gold_amount, " Gold")



func _spawn_death_vfx() -> void:
	if death_vfx_scene == null:
		return
	
	var vfx := death_vfx_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = global_position + Vector3(0.0, -0.1, 0.4)
	vfx.scale = Vector3(death_vfx_scale, death_vfx_scale, death_vfx_scale)
	
	# Partikel starten
	for child in vfx.get_children():
		if child is GPUParticles3D:
			child.emitting = true
	
	# Aufräumen
	get_tree().create_timer(death_vfx_lifetime).timeout.connect(vfx.queue_free)


# ============ ATTACK HIT DETECTION ============

func _check_charge_hit() -> void:
	if not _target or not is_instance_valid(_target):
		return
	
	var to_target := _target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()
	
	if dist > 0.5:
		return
	
	var dir_to_target := to_target.normalized()
	var dot := _charge_direction.dot(dir_to_target)
	
	if dot > 0.5:
		_has_hit_player = true
		if _target.has_method("take_damage"):
			_target.take_damage(damage, global_position)
			
			# Hit Sound abspielen
			#_play_hit_sound(_target.global_position)



# ============ HELPER FUNCTIONS ============

func _check_for_target() -> bool:
	if _target and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		return dist <= detection_range
	return false


func _get_random_patrol_point() -> Vector3:
	var angle := randf() * TAU
	var dist := randf_range(patrol_radius * 0.3, patrol_radius)
	var offset := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	return _spawn_position + offset


# ============ DIRECTION HANDLING ============

func _update_facing_direction(dir: Vector3) -> void:
	if dir == Vector3.ZERO:
		return
	
	var dir2d := Vector2(dir.x, dir.z)
	var angle := rad_to_deg(dir2d.angle())
	if angle < 0:
		angle += 360.0
	
	if angle >= 337.5 or angle < 22.5:
		_facing_dir = DirMode.RIGHT
	elif angle >= 22.5 and angle < 67.5:
		_facing_dir = DirMode.DOWN_RIGHT
	elif angle >= 67.5 and angle < 112.5:
		_facing_dir = DirMode.DOWN
	elif angle >= 112.5 and angle < 157.5:
		_facing_dir = DirMode.DOWN_LEFT
	elif angle >= 157.5 and angle < 202.5:
		_facing_dir = DirMode.LEFT
	elif angle >= 202.5 and angle < 247.5:
		_facing_dir = DirMode.UP_LEFT
	elif angle >= 247.5 and angle < 292.5:
		_facing_dir = DirMode.UP
	else:
		_facing_dir = DirMode.UP_RIGHT


func _get_flip_and_frames_idle() -> Dictionary:
	match _facing_dir:
		DirMode.RIGHT:
			return {flip = false, frames = IDLE_RIGHT}
		DirMode.LEFT:
			return {flip = true, frames = IDLE_RIGHT}
		DirMode.DOWN_RIGHT:
			return {flip = false, frames = IDLE_RIGHT_BOTTOM}
		DirMode.DOWN_LEFT:
			return {flip = true, frames = IDLE_RIGHT_BOTTOM}
		DirMode.DOWN:
			return {flip = false, frames = IDLE_BOTTOM}
		DirMode.UP_RIGHT:
			return {flip = true, frames = IDLE_LEFT_TOP}
		DirMode.UP_LEFT:
			return {flip = false, frames = IDLE_LEFT_TOP}
		DirMode.UP:
			return {flip = false, frames = IDLE_TOP}
		_:
			return {flip = false, frames = IDLE_BOTTOM}


func _get_flip_and_attack_frames() -> Dictionary:
	match _facing_dir:
		DirMode.RIGHT:
			return {flip = false, frames = ATTACK_RIGHT}
		DirMode.LEFT:
			return {flip = true, frames = ATTACK_RIGHT}
		DirMode.DOWN_RIGHT:
			return {flip = false, frames = ATTACK_RIGHT_BOTTOM}
		DirMode.DOWN_LEFT:
			return {flip = true, frames = ATTACK_RIGHT_BOTTOM}
		DirMode.DOWN:
			return {flip = false, frames = ATTACK_BOTTOM}
		DirMode.UP_RIGHT:
			return {flip = true, frames = ATTACK_LEFT_TOP}
		DirMode.UP_LEFT:
			return {flip = false, frames = ATTACK_LEFT_TOP}
		DirMode.UP:
			return {flip = false, frames = ATTACK_TOP}
		_:
			return {flip = false, frames = ATTACK_BOTTOM}


func _get_flip_and_walk_frames() -> Dictionary:
	var is_moving_up := _facing_dir in [DirMode.UP, DirMode.UP_LEFT, DirMode.UP_RIGHT]
	var flip := _facing_dir in [DirMode.LEFT, DirMode.DOWN_LEFT, DirMode.UP_LEFT]
	
	if is_moving_up:
		return {flip = flip, frames = WALK_UP}
	else:
		return {flip = flip, frames = WALK_DOWN}


func _get_flip_and_run_range() -> Dictionary:
	var is_moving_up := _facing_dir in [DirMode.UP, DirMode.UP_LEFT, DirMode.UP_RIGHT]
	var flip := _facing_dir in [DirMode.LEFT, DirMode.DOWN_LEFT, DirMode.UP_LEFT]
	
	if is_moving_up:
		return {flip = flip, start = RUN_UP_START, end = RUN_UP_END}
	else:
		return {flip = flip, start = RUN_DOWN_START, end = RUN_DOWN_END}


# ============ ANIMATION ============

func _animate_idle() -> void:
	var data := _get_flip_and_frames_idle()
	sprite.frame = data.frames[0]
	sprite.flip_h = data.flip
	sprite.modulate = Color.WHITE


func _animate_walk(delta: float) -> void:
	_anim_time += delta
	
	var data := _get_flip_and_walk_frames()
	var frames: Array = data.frames
	var idx: int = int(_anim_time * WALK_FPS) % frames.size()
	
	sprite.frame = frames[idx]
	sprite.flip_h = data.flip
	sprite.modulate = Color.WHITE


func _animate_run(delta: float) -> void:
	_anim_time += delta
	
	var data := _get_flip_and_run_range()
	var frame_count: int = data.end - data.start + 1
	var idx: int = int(_anim_time * RUN_FPS) % frame_count
	
	sprite.frame = data.start + idx
	sprite.flip_h = data.flip
	sprite.modulate = Color.WHITE


func _show_attack_windup_frame() -> void:
	var data := _get_flip_and_attack_frames()
	sprite.frame = data.frames[0]  # Windup = erster Frame
	sprite.flip_h = data.flip
	sprite.modulate = Color.WHITE


func _show_attack_strike_frame() -> void:
	var data := _get_flip_and_attack_frames()
	sprite.frame = data.frames[1]  # Strike = zweiter Frame
	sprite.flip_h = data.flip
	sprite.modulate = Color.WHITE


func _animate_hit_damaged(delta: float) -> void:
	_anim_time += delta
	
	var data := _get_hurt_frame()
	sprite.frame = data.frame
	sprite.flip_h = data.flip
	
	# Rot blinken
	var flash := fmod(_anim_time, hit_flash_duration * 2.0) < hit_flash_duration
	sprite.modulate = Color(1.5, 0.5, 0.5) if flash else Color.WHITE


# ============ COMBAT ============

func take_damage(amount: int, from_position: Vector3) -> void:
	if current_state == State.DEAD:
		return
	
	print("GOBLIN HIT")
	GameEffects.hit_effect()
	_health -= amount
	_anim_time = 0.0
	
	_last_damage_time = Time.get_ticks_msec() / 1000.0
	
	if _hp_bar:
		_hp_bar.set_health(_health, max_health)
	
	var attacker := get_tree().get_first_node_in_group("player")
	if attacker:
		_target = attacker
	
	var knockback_dir := (global_position - from_position).normalized()
	knockback_dir.y = 0
	_knockback_velocity = knockback_dir * knockback_strength
	
	_update_facing_direction(-knockback_dir)
	
	_enter_state(State.HIT)
	
	if _group:
		_group.alert_group(_target)

func get_health() -> int:
	return _health


func is_alive() -> bool:
	return current_state != State.DEAD


# ============ SIGNALS ============

func _on_detection_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_target = body


func _on_detection_body_exited(body: Node3D) -> void:
	pass
	
func set_group(group: EnemyGroup) -> void:
	print(group)
	_group = group


func set_target(target: Node3D) -> void:
	_target = target
	if _target and current_state in [State.PATROL_IDLE, State.PATROL_WALK]:
		_enter_state(State.ALERT)


func clear_target() -> void:
	
	if _was_recently_damaged():
		# Wütend bleiben, weiter verfolgen
		if _target and is_instance_valid(_target):
			_enter_state(State.CHASE)
		return
	
	_target = null
	if current_state not in [State.HIT, State.DEAD]:
		_enter_state(State.PATROL_IDLE)
		
		
# ============ STUCK DETECTION ============

func _check_if_stuck(delta: float) -> bool:
	# Nur prüfen wenn wir uns bewegen wollen
	var intended_speed := Vector2(velocity.x, velocity.z).length()
	if intended_speed < 0.1:
		_stuck_timer = 0.0
		return false
	
	# Tatsächliche Bewegung messen
	var actual_movement := Vector2(
		global_position.x - _last_position_check.x,
		global_position.z - _last_position_check.z
	).length()
	
	_last_position_check = global_position
	
	# Verhältnis: Wie viel von der gewünschten Bewegung haben wir geschafft?
	var expected := intended_speed * delta
	var ratio := actual_movement / maxf(expected, 0.001)
	
	# Unter 30% der erwarteten Bewegung = stuck
	if ratio < 0.3:
		_stuck_timer += delta
		if _stuck_timer >= stuck_detection_time:
			return true
	else:
		_stuck_timer = 0.0
	
	return false


func _reset_stuck_detection() -> void:
	_stuck_timer = 0.0
	_last_position_check = global_position
	_is_strafe_escaping = false
	_strafe_escape_timer = 0.0


func _find_strafe_escape_direction(blocked_direction: Vector3) -> Vector3:
	# Prüfe links und rechts vom blockierten Pfad
	var right: Vector3 = blocked_direction.cross(Vector3.UP).normalized()
	
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	
	# Rechts prüfen
	var query_right := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.3, 0),
		global_position + Vector3(0, 0.3, 0) + right * strafe_raycast_length
	)
	query_right.exclude = [self]
	
	# Links prüfen
	var query_left := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.3, 0),
		global_position + Vector3(0, 0.3, 0) - right * strafe_raycast_length
	)
	query_left.exclude = [self]
	
	var result_right: Dictionary = space_state.intersect_ray(query_right)
	var result_left: Dictionary = space_state.intersect_ray(query_left)
	
	var right_free: bool = result_right.is_empty()
	var left_free: bool = result_left.is_empty()
	
	if right_free and not left_free:
		return right
	elif left_free and not right_free:
		return -right
	elif right_free and left_free:
		# Beide frei - zufällig, aber konsistent für diesen Escape
		return right if randf() > 0.5 else -right
	else:
		# Beide blockiert - versuche diagonal zurück
		return (-blocked_direction + right * (1.0 if randf() > 0.5 else -1.0)).normalized()


func _abort_patrol() -> void:
	_reset_stuck_detection()
	velocity.x = 0.0
	velocity.z = 0.0
	_enter_state(State.PATROL_IDLE)

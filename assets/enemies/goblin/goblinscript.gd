extends CharacterBody3D
class_name Goblin

# --- Sprite Setup ---
@export_group("Sprite")
@export var HFRAMES: int = 10
@export var VFRAMES: int = 5

# --- Movement ---
@export_group("Movement")
@export var WALK_SPEED: float = 10.0
@export var RUN_SPEED: float = 20.0
@export var CHARGE_SPEED: float = 45.0
@export var CHARGE_DECELERATION: float = 60.0
@export var CIRCLE_SPEED: float = 15.0

# --- Patrol ---
@export_group("Patrol")
@export var patrol_radius: float = 30.0
@export var patrol_wait_time_min: float = 1.0
@export var patrol_wait_time_max: float = 3.0

# --- Combat ---
@export_group("Combat")
@export var max_health: int = 30
@export var damage: int = 5
@export var attack_windup_min: float = 1.0
@export var attack_windup_max: float = 3.0
@export var charge_duration: float = 0.4
@export var attack_recovery: float = 0.8
@export var knockback_strength: float = 10.0

# --- Detection ---
@export_group("Detection")
@export var detection_range: float = 80.0
@export var lose_interest_range: float = 120.0
@export var preferred_distance: float = 15.0
@export var circle_distance_tolerance: float = 5.0

# --- Animation ---
@export_group("Animation")
@export var IDLE_FPS: float = 3.0
@export var WALK_FPS: float = 6.0
@export var RUN_FPS: float = 10.0
@export var HIT_FPS: float = 8.0
@export var hit_flash_duration: float = 0.15

# --- Frame Definitions ---
# Idle (2 Frames each) - 0-indexed
const IDLE_RIGHT: Array[int] = [0, 0]
const IDLE_RIGHT_BOTTOM: Array[int] = [2, 2]
const IDLE_BOTTOM: Array[int] = [4, 4]
const IDLE_LEFT_TOP: Array[int] = [6, 6]
const IDLE_TOP: Array[int] = [8, 8]

# Walk (3 Frames each)
const WALK_DOWN: Array[int] = [11, 12, 15]
const WALK_UP: Array[int] = [21, 22, 25]

# Run (7 Frames each)
const RUN_DOWN_START: int = 10
const RUN_DOWN_END: int = 16
const RUN_UP_START: int = 20
const RUN_UP_END: int = 26

# Hit/Attack (2 Frames each)
const HIT_RIGHT: Array[int] = [30, 31]
const HIT_RIGHT_BOTTOM: Array[int] = [32, 33]
const HIT_BOTTOM: Array[int] = [34, 35]
const HIT_LEFT_TOP: Array[int] = [36, 37]
const HIT_TOP: Array[int] = [38, 39]

# --- State Machine ---
enum State { 
	PATROL_IDLE,
	PATROL_WALK,
	CHASE,
	CIRCLE,
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
var _circle_direction: int = 1

# Attack
var _charge_direction: Vector3 = Vector3.ZERO
var _charge_speed_current: float = 0.0
var _has_hit_player: bool = false

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var sprite: Sprite3D = $Sprite3D
@onready var detection_area: Area3D = $DetectionArea
@onready var attack_area: Area3D = $AttackArea


func _ready() -> void:
	_health = max_health
	_spawn_position = global_position
	
	if sprite:
		sprite.hframes = HFRAMES
		sprite.vframes = VFRAMES
	
	if detection_area:
		var detection_shape := detection_area.get_node_or_null("CollisionShape3D")
		if detection_shape and detection_shape.shape is SphereShape3D:
			detection_shape.shape.radius = detection_range
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)
	
	_enter_state(State.PATROL_IDLE)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	if _state_timer > 0.0:
		_state_timer -= delta
	
	match current_state:
		State.PATROL_IDLE:
			_process_patrol_idle(delta)
		State.PATROL_WALK:
			_process_patrol_walk(delta)
		State.CHASE:
			_process_chase(delta)
		State.CIRCLE:
			_process_circle(delta)
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
	
	move_and_slide()


# ============ STATE MANAGEMENT ============

func _enter_state(new_state: State) -> void:
	current_state = new_state
	_anim_time = 0.0
	
	match new_state:
		State.PATROL_IDLE:
			_state_timer = randf_range(patrol_wait_time_min, patrol_wait_time_max)
			velocity.x = 0.0
			velocity.z = 0.0
		
		State.PATROL_WALK:
			_patrol_target = _get_random_patrol_point()
		
		State.CHASE:
			pass
		
		State.CIRCLE:
			_state_timer = randf_range(attack_windup_min, attack_windup_max)
			_circle_direction = 1 if randf() > 0.5 else -1
		
		State.ATTACK_WINDUP:
			_state_timer = 0.3
			velocity.x = 0.0
			velocity.z = 0.0
			if _target and is_instance_valid(_target):
				var dir := (_target.global_position - global_position)
				dir.y = 0
				_charge_direction = dir.normalized()
				_update_facing_direction(_charge_direction)
		
		State.ATTACK_CHARGE:
			_charge_speed_current = CHARGE_SPEED
			_has_hit_player = false
			_state_timer = charge_duration
		
		State.ATTACK_RECOVERY:
			_state_timer = attack_recovery
			velocity.x = 0.0
			velocity.z = 0.0
		
		State.HIT:
			_hit_timer = 0.3
		
		State.DEAD:
			velocity.x = 0.0
			velocity.z = 0.0


# ============ STATE PROCESSING ============

func _process_patrol_idle(delta: float) -> void:
	_animate_idle(delta)
	
	if _check_for_target():
		_enter_state(State.CHASE)
		return
	
	if _state_timer <= 0.0:
		_enter_state(State.PATROL_WALK)


func _process_patrol_walk(delta: float) -> void:
	if _check_for_target():
		_enter_state(State.CHASE)
		return
	
	var dir := (_patrol_target - global_position)
	dir.y = 0
	var dist := dir.length()
	
	if dist < 2.0:
		_enter_state(State.PATROL_IDLE)
		return
	
	dir = dir.normalized()
	_update_facing_direction(dir)
	
	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED
	
	_animate_walk(delta)


func _process_chase(delta: float) -> void:
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
	
	if dist <= preferred_distance + circle_distance_tolerance:
		_enter_state(State.CIRCLE)
		return
	
	var dir := to_target.normalized()
	_update_facing_direction(dir)
	
	velocity.x = dir.x * RUN_SPEED
	velocity.z = dir.z * RUN_SPEED
	
	_animate_run(delta)


func _process_circle(delta: float) -> void:
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
	
	if _state_timer <= 0.0:
		_enter_state(State.ATTACK_WINDUP)
		return
	
	var dir_to_target := to_target.normalized()
	var circle_dir := Vector3(-dir_to_target.z, 0, dir_to_target.x) * _circle_direction
	
	var distance_adjustment := Vector3.ZERO
	if dist < preferred_distance - circle_distance_tolerance:
		distance_adjustment = -dir_to_target * 0.5
	elif dist > preferred_distance + circle_distance_tolerance:
		distance_adjustment = dir_to_target * 0.5
	
	var move_dir := (circle_dir + distance_adjustment).normalized()
	
	_update_facing_direction(dir_to_target)
	
	velocity.x = move_dir.x * CIRCLE_SPEED
	velocity.z = move_dir.z * CIRCLE_SPEED
	
	if randf() < 0.01:
		_circle_direction *= -1
	
	_animate_walk(delta)


func _process_attack_windup(delta: float) -> void:
	_animate_attack_windup()
	
	if _state_timer <= 0.0:
		_enter_state(State.ATTACK_CHARGE)


func _process_attack_charge(delta: float) -> void:
	_charge_speed_current = move_toward(_charge_speed_current, CHARGE_SPEED * 0.3, CHARGE_DECELERATION * delta)
	
	velocity.x = _charge_direction.x * _charge_speed_current
	velocity.z = _charge_direction.z * _charge_speed_current
	
	if not _has_hit_player:
		_check_charge_hit()
	
	_animate_hit(delta)
	
	if _state_timer <= 0.0:
		_enter_state(State.ATTACK_RECOVERY)


func _process_attack_recovery(delta: float) -> void:
	_animate_idle(delta)
	
	if _state_timer <= 0.0:
		if _target and is_instance_valid(_target):
			var dist := global_position.distance_to(_target.global_position)
			if dist <= lose_interest_range:
				if randf() > 0.3:
					_enter_state(State.CIRCLE)
				else:
					_state_timer = randf_range(0.5, 1.5)
					if _state_timer <= 0.0:
						_enter_state(State.CIRCLE)
				return
		_enter_state(State.PATROL_IDLE)


func _process_hit(delta: float) -> void:
	_hit_timer -= delta
	
	velocity.x = _knockback_velocity.x
	velocity.z = _knockback_velocity.z
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, 80.0 * delta)
	
	_animate_hit_damaged(delta)
	
	if _hit_timer <= 0.0:
		if _health <= 0:
			_enter_state(State.DEAD)
		elif _target and is_instance_valid(_target):
			_enter_state(State.CHASE)
		else:
			_enter_state(State.PATROL_IDLE)


func _process_dead(delta: float) -> void:
	if sprite:
		sprite.modulate.a -= delta * 2.0
		if sprite.modulate.a <= 0.0:
			queue_free()


# ============ ATTACK HIT DETECTION ============

func _check_charge_hit() -> void:
	if not _target or not is_instance_valid(_target):
		return
	
	var to_target := _target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()
	
	if dist > 3.0:
		return
	
	var dir_to_target := to_target.normalized()
	var dot := _charge_direction.dot(dir_to_target)
	
	if dot > 0.5:
		_has_hit_player = true
		if _target.has_method("take_damage"):
			_target.take_damage(damage, global_position)


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


func _get_flip_and_frames_hit() -> Dictionary:
	match _facing_dir:
		DirMode.RIGHT:
			return {flip = false, frames = HIT_RIGHT}
		DirMode.LEFT:
			return {flip = true, frames = HIT_RIGHT}
		DirMode.DOWN_RIGHT:
			return {flip = false, frames = HIT_RIGHT_BOTTOM}
		DirMode.DOWN_LEFT:
			return {flip = true, frames = HIT_RIGHT_BOTTOM}
		DirMode.DOWN:
			return {flip = false, frames = HIT_BOTTOM}
		DirMode.UP_RIGHT:
			return {flip = true, frames = HIT_LEFT_TOP}
		DirMode.UP_LEFT:
			return {flip = false, frames = HIT_LEFT_TOP}
		DirMode.UP:
			return {flip = false, frames = HIT_TOP}
		_:
			return {flip = false, frames = HIT_BOTTOM}


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

func _animate_idle(delta: float) -> void:
	_anim_time += delta
	
	var data := _get_flip_and_frames_idle()
	var frames: Array = data.frames
	var idx: int = int(_anim_time * IDLE_FPS) % frames.size()
	
	sprite.frame = frames[idx]
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


func _animate_attack_windup() -> void:
	var data := _get_flip_and_frames_hit()
	sprite.frame = data.frames[0]
	sprite.flip_h = data.flip
	sprite.modulate = Color.WHITE


func _animate_hit(delta: float) -> void:
	_anim_time += delta
	
	var data := _get_flip_and_frames_hit()
	var frames: Array = data.frames
	var idx: int = int(_anim_time * HIT_FPS) % frames.size()
	
	sprite.frame = frames[idx]
	sprite.flip_h = data.flip
	sprite.modulate = Color.WHITE


func _animate_hit_damaged(delta: float) -> void:
	_anim_time += delta
	
	var data := _get_flip_and_frames_hit()
	var frames: Array = data.frames
	var idx: int = int(_anim_time * HIT_FPS) % frames.size()
	
	sprite.frame = frames[idx]
	sprite.flip_h = data.flip
	
	var flash := fmod(_anim_time, hit_flash_duration * 2.0) < hit_flash_duration
	sprite.modulate = Color.WHITE if flash else Color(1.5, 0.5, 0.5)


# ============ COMBAT ============

func take_damage(amount: int, from_position: Vector3) -> void:
	if current_state == State.DEAD:
		return
	
	_health -= amount
	_anim_time = 0.0
	
	var knockback_dir := (global_position - from_position).normalized()
	knockback_dir.y = 0
	_knockback_velocity = knockback_dir * knockback_strength
	
	_update_facing_direction(-knockback_dir)
	
	_enter_state(State.HIT)


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

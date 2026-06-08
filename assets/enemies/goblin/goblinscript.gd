extends Enemy
class_name Goblin

## Goblin-Gegner mit Patrol, Circle-Strafe Kampf und Thrust-Attacke

# === MOVEMENT ===
@export_group("Movement")
@export var WALK_SPEED: float = 1.0
@export var RUN_SPEED: float = 2.0
@export var CHARGE_SPEED: float = 10.0
@export var CHARGE_DECELERATION: float = 60.0
@export var STRAFE_SPEED: float = 1.0

# === COMBAT ===
@export_group("Combat")
@export var damage: int = 5
@export var circle_time_min: float = 0.3
@export var circle_time_max: float = 0.8
@export var circle_steps_min: int = 1
@export var circle_steps_max: int = 2
@export var circle_pause_min: float = 0.3
@export var circle_pause_max: float = 0.8
@export var attack_chance_per_pause: float = 0.7
@export var charge_duration: float = 0.4
@export var attack_recovery: float = 0.8
@export var preferred_distance: float = 1.0
@export var preferred_distance_tolerance: float = 0.3

# === OBSTACLE AVOIDANCE ===
@export_group("Obstacle Avoidance")
@export var strafe_raycast_length: float = 1.5
@export var strafe_escape_duration: float = 0.6

# === ANIMATION ===
@export_group("Animation")
@export var WALK_FPS: float = 6.0
@export var RUN_FPS: float = 10.0
@export var HIT_FPS: float = 5.0

# === THRUST VFX ===
@export_group("Thrust VFX")
@export var thrust_scene: PackedScene
@export var thrust_offset: float = 0.4
@export var thrust_height: float = 0.15
@export var thrust_scale: Vector3 = Vector3(1.0, 1.0, 1.0)

@export_subgroup("Offsets per Direction")
@export var thrust_offset_up: Vector3 = Vector3(0.0, 0.0, -0.2)
@export var thrust_offset_up_right: Vector3 = Vector3(0.1, 0.0, 0.3)
@export var thrust_offset_right: Vector3 = Vector3(0.2, 0.0, 0.5)
@export var thrust_offset_down_right: Vector3 = Vector3(0.05, 0.0, 0.7)
@export var thrust_offset_down: Vector3 = Vector3(0.0, 0.0, 0.4)
@export var thrust_offset_down_left: Vector3 = Vector3(-0.05, 0.0, 0.7)
@export var thrust_offset_left: Vector3 = Vector3(-0.2, 0.0, 0.5)
@export var thrust_offset_up_left: Vector3 = Vector3(-0.1, 0.0, 0.3)

# === VISUAL VARIANT ===
@export_group("Visual Variant")
@export var sprite_texture_override: Texture2D
@export var sprite_modulate_override: Color = Color.WHITE


# === FRAME DEFINITIONS ===
const IDLE_RIGHT: Array[int] = [0, 0]
const IDLE_RIGHT_BOTTOM: Array[int] = [2, 2]
const IDLE_BOTTOM: Array[int] = [4, 4]
const IDLE_LEFT_TOP: Array[int] = [6, 6]
const IDLE_TOP: Array[int] = [8, 8]

const WALK_DOWN: Array[int] = [11, 15, 12, 15]
const WALK_UP: Array[int] = [21, 25, 22, 25]

const WALK_TOP: Array[int] = [71, 75, 72, 75]
const WALK_BOTTOM: Array[int] = [61, 65, 62, 65]

const RUN_DOWN_START: int = 10
const RUN_DOWN_END: int = 16
const RUN_UP_START: int = 20
const RUN_UP_END: int = 26

const RUN_TOP_START: int = 70
const RUN_TOP_END: int = 76

const RUN_BOTTOM_START: int = 60
const RUN_BOTTOM_END: int = 66

const ATTACK_RIGHT: Array[int] = [30, 31]
const ATTACK_RIGHT_BOTTOM: Array[int] = [32, 33]
const ATTACK_BOTTOM: Array[int] = [34, 35]
const ATTACK_LEFT_TOP: Array[int] = [36, 37]
const ATTACK_TOP: Array[int] = [38, 39]

const HURT_DOWN_RIGHT: int = 40
const HURT_UP_RIGHT: int = 41

const DROWN_FRAME: int = 53

const DEATH_FRAME_LIST: Array[int] = [50, 51, 52]

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

# === STATE MACHINE ===
enum State {
	PATROL_IDLE, PATROL_WALK,
	ALERT, CHASE,
	CIRCLE_IDLE, CIRCLE_STRAFE,
	ATTACK_WINDUP, ATTACK_CHARGE, ATTACK_RECOVERY,
	HIT, DEAD,
	CONFUSED
}
var _state: State = State.PATROL_IDLE
var _state_timer: float = 0.0

# === DIRECTION ===
enum DirMode {
	DOWN, UP, LEFT, RIGHT,
	DOWN_LEFT, DOWN_RIGHT, UP_LEFT, UP_RIGHT
}
var _facing_dir: int = DirMode.DOWN

# === PATROL ===
var _patrol_target: Vector3

# === COMBAT ===
var _strafe_direction: int = 1
var _strafe_steps_remaining: int = 0
var _charge_direction: Vector3 = Vector3.ZERO
var _charge_speed_current: float = 0.0
var _has_hit_player: bool = false
var _last_damage_time: float = -5.0

# === STRAFE ESCAPE ===
var _is_strafe_escaping: bool = false
var _strafe_escape_timer: float = 0.0
var _strafe_escape_dir: Vector3 = Vector3.ZERO

# === VFX ===
var _active_thrust_vfx: Node3D = null
var _thrust_material: ShaderMaterial = null
var _flicker_tween: Tween = null

# === GROUP ===
var _group: Node = null

# === DETECTION ===
@onready var detection_area: Area3D = $DetectionArea
@onready var attack_area: Area3D = $AttackArea


# === ENEMY OVERRIDES ===

func _on_ready_after_terrain() -> void:
	_apply_visual_variant()
	
	_last_position_check = global_position
	call_deferred("_setup_detection")
	_state_timer = randf_range(0.0, patrol_wait_time_max)

	if _target == null:
		_state = State.PATROL_IDLE
		
func _apply_visual_variant() -> void:
	if sprite == null:
		return

	if sprite_texture_override != null:
		sprite.texture = sprite_texture_override

	sprite.modulate = sprite_modulate_override


func _process_ai(delta: float) -> void:
	# Während Verwirrung: Nur Idle-Animation
	if is_confused():
		_animate_idle()
		return
	
	if _state not in [State.DEAD, State.HIT, State.ATTACK_CHARGE, State.ATTACK_WINDUP, State.ALERT, State.CONFUSED]:
		_check_player_detection()

	match _state:
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
		State.CONFUSED:
			_process_confused(delta)

	_update_thrust_vfx_position()


func _on_damage_received(amount: int, from_position: Vector3) -> void:
	_last_damage_time = Time.get_ticks_msec() / 1000.0

	var attacker := get_tree().get_first_node_in_group("player")
	if attacker:
		_target = attacker

	var knockback_dir := (global_position - from_position).normalized()
	_update_facing_direction(-knockback_dir)

	_enter_state(State.HIT)

	if _group and _group.has_method("alert_group"):
		_group.alert_group(_target)


func _on_death() -> void:
	_cleanup_thrust_vfx_immediate()
	_state = State.DEAD


func _on_death_finished() -> void:
	if _group and _group.has_method("remove_goblin"):
		_group.remove_goblin(self)


func _on_confusion_started() -> void:
	_enter_state(State.CONFUSED)


func _on_confusion_ended() -> void:
	if _target and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		if dist <= lose_interest_range:
			_enter_state(State.ALERT)
		else:
			_enter_state(State.PATROL_IDLE)
	else:
		_enter_state(State.PATROL_IDLE)


func _get_hurt_frame() -> Dictionary:
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


func _get_drown_frame() -> int:
	return DROWN_FRAME

func _get_death_frames() -> Array[int]:
	return DEATH_FRAME_LIST


func _reset_stuck_detection() -> void:
	super()
	_is_strafe_escaping = false
	_strafe_escape_timer = 0.0


# === DETECTION ===

func _setup_detection() -> void:
	if detection_area:
		if _group != null:
			detection_area.monitoring = false
			detection_area.monitorable = false
		else:
			var detection_shape := detection_area.get_node_or_null("CollisionShape3D")
			if detection_shape and detection_shape.shape is SphereShape3D:
				detection_shape.shape.radius = detection_range
			detection_area.body_entered.connect(_on_detection_body_entered)
			detection_area.body_exited.connect(_on_detection_body_exited)


func _check_player_detection() -> void:
	
	
	
	if _group != null and not _was_recently_damaged():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var distance := global_position.distance_to(player.global_position)
	var effective_range := lose_interest_range if _was_recently_damaged() else detection_range
	if distance <= effective_range:
		if _state in [State.PATROL_IDLE, State.PATROL_WALK]:
			_target = player
			_enter_state(State.ALERT)
		elif _state == State.ATTACK_RECOVERY and distance > preferred_distance + preferred_distance_tolerance:
			_enter_state(State.CHASE)


func _was_recently_damaged() -> bool:
	var current_time := Time.get_ticks_msec() / 1000.0
	return (current_time - _last_damage_time) < 5.0


func _on_detection_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_target = body


func _on_detection_body_exited(_body: Node3D) -> void:
	pass


# === STATE MANAGEMENT ===

func _enter_state(new_state: State) -> void:
	_state = new_state
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
			spawn_alert_popup()
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
			if _group and _group.has_method("get_optimal_strafe_direction"):
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

		State.CONFUSED:
			velocity.x = 0.0
			velocity.z = 0.0
			_reset_stuck_detection()
			_cleanup_thrust_vfx_immediate()


# === STATE PROCESSING ===

func _process_patrol_idle(delta: float) -> void:
	_animate_idle()

	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.PATROL_WALK)


func _process_patrol_walk(delta: float) -> void:
	var dir := (_patrol_target - global_position)
	dir.y = 0
	var dist := dir.length()

	if dist < 0.2:
		_reset_stuck_detection()
		_enter_state(State.PATROL_IDLE)
		return

	var dist_from_spawn := (_patrol_target - _spawn_position).length()
	if dist_from_spawn > patrol_radius * 2:
		_patrol_target = _spawn_position

	dir = dir.normalized()
	if avoid_cliffs and _is_cliff_ahead(dir):
		_abort_patrol()
		return
	
	_update_facing_direction(dir)

	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED

	_animate_walk(delta)

	if _check_if_stuck(delta):
		_abort_patrol()


func _process_alert(delta: float) -> void:
	_animate_idle()

	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player")

	if _target and is_instance_valid(_target):
		var dir := (_target.global_position - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			_update_facing_direction(dir.normalized())

	_state_timer -= delta
	if _state_timer <= 0:
		if _target == null or not is_instance_valid(_target):
			_target = get_tree().get_first_node_in_group("player")

		if _target and is_instance_valid(_target):
			_enter_state(State.CHASE)
		else:
			_enter_state(State.PATROL_IDLE)


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

	if _is_strafe_escaping:
		_strafe_escape_timer -= delta
		if _strafe_escape_timer <= 0.0:
			_is_strafe_escaping = false
			_reset_stuck_detection()
		else:
			var escape_move := (_strafe_escape_dir * 0.7 + dir * 0.3).normalized()
			velocity.x = escape_move.x * RUN_SPEED
			velocity.z = escape_move.z * RUN_SPEED
			_update_facing_direction(escape_move)
			_animate_run(delta)
			return

	var separation := Vector3.ZERO
	if _group and _group.has_method("get_separation_vector"):
		separation = _group.get_separation_vector(self) * 0.5

	var move_dir := (dir + separation).normalized()

	# Cliff Check
	if avoid_cliffs:
		var safe_dir := _find_safe_direction(move_dir)
		if safe_dir == Vector3.ZERO:
			# Kein Weg zum Spieler — anhalten und aufgeben
			velocity.x = 0.0
			velocity.z = 0.0
			_update_facing_direction(dir)
			_animate_idle()
			_reset_stuck_detection()
			# Wenn nah genug: in Circle gehen, sonst Patrol
			if dist <= preferred_distance + preferred_distance_tolerance * 2:
				_enter_state(State.CIRCLE_IDLE)
			else:
				_target = null
				_enter_state(State.PATROL_IDLE)
			return
		move_dir = safe_dir

	_update_facing_direction(move_dir)

	velocity.x = move_dir.x * RUN_SPEED
	velocity.z = move_dir.z * RUN_SPEED

	_animate_run(delta)

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

	_state_timer -= delta
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

	var strafe_dir := Vector3(-dir_to_target.z, 0, dir_to_target.x) * _strafe_direction

	if avoid_cliffs and _is_cliff_ahead(strafe_dir):
		_strafe_direction *= -1
		strafe_dir = -strafe_dir
		# Wenn auch die andere Seite ein Abgrund ist: nur stehen bleiben
		if _is_cliff_ahead(strafe_dir):
			velocity.x = 0.0
			velocity.z = 0.0
			_animate_idle()
			_state_timer = 0.0  # sofort weiter zur Entscheidung
			return

	var distance_diff := dist - preferred_distance
	var distance_correction := Vector3.ZERO
	if abs(distance_diff) > preferred_distance_tolerance:
		var correction_strength: float = clamp(distance_diff * 0.5, -1.0, 1.0)
		distance_correction = dir_to_target * correction_strength

	var separation := Vector3.ZERO
	if _group and _group.has_method("get_separation_vector"):
		separation = _group.get_separation_vector(self)

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

	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.ATTACK_CHARGE)


func _process_attack_charge(delta: float) -> void:
	if _is_strafe_escaping:
		var strafe_move := _strafe_escape_dir * STRAFE_SPEED * 2.0
		velocity.x = strafe_move.x + _charge_direction.x * _charge_speed_current * 0.3
		velocity.z = strafe_move.z + _charge_direction.z * _charge_speed_current * 0.3

		var horizontal_movement := Vector3(
			global_position.x - _last_position_check.x, 0,
			global_position.z - _last_position_check.z
		).length()

		if horizontal_movement > stuck_min_movement * 3.0:
			_is_strafe_escaping = false
			_stuck_timer = 0.0
	else:
		if _check_if_stuck(delta):
			_is_strafe_escaping = true
			_strafe_escape_dir = _find_strafe_escape_direction(_charge_direction)

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

	_state_timer -= delta
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
			_die()
		elif _target and is_instance_valid(_target):
			_enter_state(State.CHASE)
		else:
			_enter_state(State.PATROL_IDLE)


func _process_confused(_delta: float) -> void:
	# Während Verwirrung: Nur Idle-Animation, keine Bewegung, keine Richtungsänderung
	_animate_idle()


# === ATTACK HIT DETECTION ===

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


# === HELPER FUNCTIONS ===

func _abort_patrol() -> void:
	_reset_stuck_detection()
	velocity.x = 0.0
	velocity.z = 0.0
	_enter_state(State.PATROL_IDLE)


func _find_strafe_escape_direction(blocked_direction: Vector3) -> Vector3:
	var right: Vector3 = blocked_direction.cross(Vector3.UP).normalized()
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 0.3, 0)

	var query_right := PhysicsRayQueryParameters3D.create(
		origin, origin + right * strafe_raycast_length
	)
	query_right.exclude = [self]

	var query_left := PhysicsRayQueryParameters3D.create(
		origin, origin - right * strafe_raycast_length
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
		return right if randf() > 0.5 else -right
	else:
		return (-blocked_direction + right * (1.0 if randf() > 0.5 else -1.0)).normalized()


# === DIRECTION HANDLING ===

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
	match _facing_dir:
		DirMode.UP:
			return {flip = false, frames = WALK_TOP}
		DirMode.DOWN:
			return {flip = false, frames = WALK_BOTTOM}
		DirMode.UP_LEFT:
			return {flip = true, frames = WALK_UP}
		DirMode.UP_RIGHT:
			return {flip = false, frames = WALK_UP}
		DirMode.LEFT, DirMode.DOWN_LEFT:
			return {flip = true, frames = WALK_DOWN}
		DirMode.RIGHT, DirMode.DOWN_RIGHT:
			return {flip = false, frames = WALK_DOWN}
		_:
			return {flip = false, frames = WALK_BOTTOM}


func _get_flip_and_run_range() -> Dictionary:
	match _facing_dir:
		DirMode.UP:
			return {flip = false, start = RUN_TOP_START, end = RUN_TOP_END}
		DirMode.DOWN:
			return {flip = false, start = RUN_BOTTOM_START, end = RUN_BOTTOM_END}
		DirMode.UP_LEFT:
			return {flip = true, start = RUN_UP_START, end = RUN_UP_END}
		DirMode.UP_RIGHT:
			return {flip = false, start = RUN_UP_START, end = RUN_UP_END}
		DirMode.LEFT, DirMode.DOWN_LEFT:
			return {flip = true, start = RUN_DOWN_START, end = RUN_DOWN_END}
		DirMode.RIGHT, DirMode.DOWN_RIGHT:
			return {flip = false, start = RUN_DOWN_START, end = RUN_DOWN_END}
		_:
			return {flip = false, start = RUN_BOTTOM_START, end = RUN_BOTTOM_END}


# === ANIMATION ===

func _animate_idle() -> void:
	var data := _get_flip_and_frames_idle()
	sprite.frame = data.frames[0]
	sprite.flip_h = data.flip
	sprite.modulate = sprite_modulate_override


func _animate_walk(delta: float) -> void:
	_anim_time += delta
	var data := _get_flip_and_walk_frames()
	var frames: Array = data.frames
	var idx: int = int(_anim_time * WALK_FPS) % frames.size()
	sprite.frame = frames[idx]
	sprite.flip_h = data.flip
	sprite.modulate = sprite_modulate_override


func _animate_run(delta: float) -> void:
	_anim_time += delta
	var data := _get_flip_and_run_range()
	var frame_count: int = data.end - data.start + 1
	var idx: int = int(_anim_time * RUN_FPS) % frame_count
	sprite.frame = data.start + idx
	sprite.flip_h = data.flip
	sprite.modulate = sprite_modulate_override


func _show_attack_windup_frame() -> void:
	var data := _get_flip_and_attack_frames()
	sprite.frame = data.frames[0]
	sprite.flip_h = data.flip
	sprite.modulate = sprite_modulate_override


func _show_attack_strike_frame() -> void:
	var data := _get_flip_and_attack_frames()
	sprite.frame = data.frames[1]
	sprite.flip_h = data.flip
	sprite.modulate = sprite_modulate_override


func _animate_hit_damaged(delta: float) -> void:
	_anim_time += delta
	var data := _get_hurt_frame()
	sprite.frame = data.frame
	sprite.flip_h = data.flip
	var flash := fmod(_anim_time, hit_flash_duration * 2.0) < hit_flash_duration
	sprite.modulate = Color(1.5, 0.5, 0.5) if flash else sprite_modulate_override


# === THRUST VFX ===

func _spawn_thrust_vfx() -> void:
	if thrust_scene == null:
		return

	_cleanup_thrust_vfx_immediate()

	_active_thrust_vfx = thrust_scene.instantiate() as Node3D
	add_child(_active_thrust_vfx)
	_active_thrust_vfx.scale = thrust_scale

	# Position + Rotation gleich korrekt setzen
	_update_thrust_vfx_position()

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

	var hit_area: Area3D = _active_thrust_vfx.get_node_or_null("HitArea")
	if hit_area:
		hit_area.body_entered.connect(_on_thrust_hit)

	_start_flicker_loop()


func _on_thrust_hit(body: Node3D) -> void:
	if body == self:
		return
	if _state != State.ATTACK_CHARGE:
		return
	if _has_hit_player:
		return

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
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 0.8, 0.05)
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 1.1, 0.04)
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 0.9, 0.06)
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 1.15, 0.03)
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 0.95, 0.05)
	_flicker_tween.tween_property(_thrust_material, "shader_parameter/flicker", 1.0, 0.04)


func _update_thrust_vfx_position() -> void:
	if _active_thrust_vfx == null or not is_instance_valid(_active_thrust_vfx):
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var offset := _get_thrust_offset()
	var cam_basis := camera.global_transform.basis

	# Anker im Camera-Space: klebt am Sprite, egal wie die Kamera steht
	var anchor := global_position
	anchor += cam_basis.x * offset.x   # X = rechts auf dem Bildschirm
	anchor += cam_basis.y * offset.y   # Y = hoch auf dem Bildschirm
	anchor += -cam_basis.z * offset.z  # Z = von der Kamera weg (optional, meist 0)

	_active_thrust_vfx.global_position = anchor

	# Rotation in Welt-Space, damit der Zylinder in die echte Schwungrichtung zeigt
	var yaw: float = THRUST_YAW_DEG.get(_facing_dir, 180.0)
	_active_thrust_vfx.global_rotation = Vector3(0.0, deg_to_rad(yaw), 0.0)


func _get_thrust_offset() -> Vector3:
	match _facing_dir:
		DirMode.UP: return thrust_offset_up
		DirMode.UP_RIGHT: return thrust_offset_up_right
		DirMode.RIGHT: return thrust_offset_right
		DirMode.DOWN_RIGHT: return thrust_offset_down_right
		DirMode.DOWN: return thrust_offset_down
		DirMode.DOWN_LEFT: return thrust_offset_down_left
		DirMode.LEFT: return thrust_offset_left
		DirMode.UP_LEFT: return thrust_offset_up_left
		_: return thrust_offset_down


func _cleanup_thrust_vfx_immediate() -> void:
	if _flicker_tween and _flicker_tween.is_valid():
		_flicker_tween.kill()
	_flicker_tween = null
	_thrust_material = null

	if _active_thrust_vfx and is_instance_valid(_active_thrust_vfx):
		_active_thrust_vfx.queue_free()
	_active_thrust_vfx = null


# === GROUP ===

func set_group(group: Node) -> void:
	_group = group


func set_target_from_group(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return

	_target = target

	if _state in [State.PATROL_IDLE, State.PATROL_WALK]:
		_enter_state(State.ALERT)


func clear_target() -> void:
	if _was_recently_damaged():
		if _target and is_instance_valid(_target):
			_enter_state(State.CHASE)
		return

	_target = null
	if _state not in [State.HIT, State.DEAD, State.CONFUSED]:
		_enter_state(State.PATROL_IDLE)
		
func _on_drown_started() -> void:
	_cleanup_thrust_vfx_immediate()

extends Enemy
class_name CaveBat

## Fliegende Höhlenfledermaus – hängt an der Wand, verfolgt per Flug,
## greift mit Sturzflug oder seitlichem Vorbeihieb an.

# === MOVEMENT ===
@export_group("Movement")
@export var FLY_SPEED: float = 2.5
@export var FLY_ACCEL: float = 6.0
@export var TURN_SPEED: float = 4.0          ## Wie schnell die Fledermaus ihre Richtung ändert
@export var DRIFT_AMPLITUDE: float = 0.6     ## Seitliche Drift-Stärke beim Fliegen
@export var DRIFT_FREQUENCY: float = 1.8     ## Drift-Geschwindigkeit
@export var BOB_AMPLITUDE: float = 0.08      ## Vertikales Wippen
@export var BOB_FREQUENCY: float = 2.5
@export var FLY_HEIGHT: float = 0.6          ## Flughöhe über Spawn-Y (niedrig genug für Player-Hitbox)
@export var RISE_SPEED: float = 2.0          ## Aufstiegsgeschwindigkeit nach Spawn / Sturzflug

# === COMBAT ===
@export_group("Combat")
@export var damage: int = 4
@export var attack_cooldown_min: float = 2.0
@export var attack_cooldown_max: float = 4.0
@export var dive_chance: float = 0.55        ## Wahrscheinlichkeit für Sturzflug vs. Vorbeihieb
@export var preferred_distance: float = 2.5  ## Abstand zum Spieler beim Umkreisen

# Sturzflug
@export_subgroup("Dive Attack")
@export var dive_windup_time: float = 0.5
@export var dive_speed: float = 9.0
@export var dive_duration: float = 0.45
@export var dive_curve_strength: float = 0.3 ## 0 = gerade Linie, 1 = stark gebogen
@export var dive_recovery_time: float = 0.9

# Vorbeihieb
@export_subgroup("Swipe Attack")
@export var swipe_approach_speed: float = 3.5
@export var swipe_speed: float = 7.0
@export var swipe_duration: float = 0.35
@export var swipe_lateral_offset: float = 1.8  ## Seitlicher Versatz beim Anflug
@export var swipe_recovery_time: float = 0.7

# === WALL STUN ===
@export_group("Wall Stun")
@export var wall_stun_duration: float = 0.5
@export var wall_bounce_strength: float = 2.0  ## Abprall-Geschwindigkeit
@export var wall_check_raycast_len: float = 0.4 ## Kurzer Raycast vor der Nase

# === DEATH LAUNCH ===
@export_group("Death Launch")
@export var death_launch_strength: float = 4.0   ## Horizontale Wegschleuder-Stärke
@export var death_launch_height: float = 3.5     ## Vertikaler Aufwärts-Kick

# === WAKE UP ===
@export_group("Wake Up")
@export var wake_duration: float = 0.6

# === ANIMATION ===
@export_group("Animation")
@export var FLY_FPS: float = 8.0
@export var CHARGE_FPS: float = 10.0
@export var WAKE_FPS: float = 4.0
@export var HIT_FPS: float = 5.0

# === WALL IDLE ===
@export_group("Wall Idle")
@export var wall_raycast_distance: float = 1.5   ## Wie weit nach Wänden gesucht wird
@export var wall_raycast_directions: int = 8      ## Anzahl Richtungen zum Scannen


# ╔══════════════════════════════════════════════════════╗
# ║                   FRAME DEFINITIONS                  ║
# ╚══════════════════════════════════════════════════════╝

# Idle (an der Wand hängend)
const IDLE_WALL_FRAME: int = 0

# Wake-Up
const WAKE_FRAMES: Array[int] = [1, 2]

# Flug – 3 Frames pro Richtung (5 unique, 3 gespiegelt)
const FLY_RIGHT: Array[int]        = [10, 11, 12]
const FLY_BOTTOM_RIGHT: Array[int] = [13, 14, 15]
const FLY_BOTTOM: Array[int]       = [16, 17, 18]
const FLY_TOP_RIGHT: Array[int]    = [20, 21, 22]
const FLY_TOP: Array[int]          = [23, 24, 25]

# Charge (Sturzflug / Vorbeihieb) – 1 Frame pro Richtung, gespiegelt
const CHARGE_RIGHT: int        = 11
const CHARGE_BOTTOM_RIGHT: int = 13
const CHARGE_BOTTOM: int       = 16
const CHARGE_TOP_RIGHT: int    = 21
const CHARGE_TOP: int          = 24

# Attack-Einleitung (Windup) – statischer Frame pro Richtung
const ATTACK_RIGHT: int        = 30
const ATTACK_BOTTOM_RIGHT: int = 32
const ATTACK_BOTTOM: int       = 34
const ATTACK_TOP_RIGHT: int    = 36
const ATTACK_TOP: int          = 38

# Hurt / Death
const HURT_FRAME: int = 40
const DEATH_FRAME_LIST: Array[int] = [40, 42, 41]


# ╔══════════════════════════════════════════════════════╗
# ║                     STATE MACHINE                    ║
# ╚══════════════════════════════════════════════════════╝

enum State {
	WALL_IDLE,
	WAKE_UP,
	PURSUE,
	DIVE_WINDUP,
	DIVE_ATTACK,
	DIVE_RECOVERY,
	SWIPE_APPROACH,
	SWIPE_ATTACK,
	SWIPE_RECOVERY,
	WALL_STUN,
	HIT,
	DEAD
}
var _state: State = State.WALL_IDLE
var _state_timer: float = 0.0

# === DIRECTION ===
enum DirMode {
	DOWN, UP, LEFT, RIGHT,
	DOWN_LEFT, DOWN_RIGHT, UP_LEFT, UP_RIGHT
}
var _facing_dir: int = DirMode.DOWN

# === FLIGHT ===
var _fly_target_y: float = 0.0
var _current_fly_dir: Vector3 = Vector3.ZERO
var _flight_time: float = 0.0
var _attack_timer: float = 0.0

# === WALL ===
var _wall_normal: Vector3 = Vector3.ZERO
var _is_airborne: bool = false

# === DIVE ===
var _dive_direction: Vector3 = Vector3.ZERO
var _dive_start_pos: Vector3 = Vector3.ZERO
var _dive_target_pos: Vector3 = Vector3.ZERO
var _dive_curve_perp: Vector3 = Vector3.ZERO
var _dive_progress: float = 0.0
var _has_hit_player: bool = false

# === SWIPE ===
var _swipe_direction: Vector3 = Vector3.ZERO
var _swipe_side: int = 1
var _swipe_target_pos: Vector3 = Vector3.ZERO

# === WALL STUN ===
var _stun_bounce_vel: Vector3 = Vector3.ZERO

# === DEATH MOMENTUM ===
var _death_momentum: Vector3 = Vector3.ZERO

# === DETECTION ===
@onready var detection_area: Area3D = $DetectionArea


# ╔══════════════════════════════════════════════════════╗
# ║                   ENEMY OVERRIDES                    ║
# ╚══════════════════════════════════════════════════════╝

func _on_ready_after_terrain() -> void:
	_fly_target_y = _spawn_position.y + FLY_HEIGHT
	_last_position_check = global_position
	_detect_wall_at_spawn()
	call_deferred("_setup_detection")
	_sync_collision_layers()
 
	if _wall_normal != Vector3.ZERO:
		_update_facing_direction(-_wall_normal)
	_state = State.WALL_IDLE
 
 
## Kopiert Collision-Layer/Mask vom ersten anderen Enemy in der Szene (z.B. Goblin).
## Damit funktioniert die Player-AttackArea auch wenn die Bat-Szene
## noch Default-Layers hat.
func _sync_collision_layers() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node != self and node is CharacterBody3D:
			if node.collision_layer != collision_layer or node.collision_mask != collision_mask:
				collision_layer = node.collision_layer
				collision_mask = node.collision_mask
				push_warning("CaveBat: Collision Layers von '%s' übernommen (Layer=%d, Mask=%d)" % [node.name, collision_layer, collision_mask])
			return
 
 
## Überschreibe _physics_process – Fledermaus fliegt, keine Gravitation.
func _physics_process(delta: float) -> void:
	if _is_dead:
		# Tod mit Schwung: behält horizontale Velocity + Gravitation
		_death_momentum.y -= gravity * delta
		velocity = _death_momentum
		_process_death(delta)
		move_and_slide()
		# Reibung auf XZ wenn am Boden
		if is_on_floor():
			_death_momentum.x = move_toward(_death_momentum.x, 0.0, 8.0 * delta)
			_death_momentum.z = move_toward(_death_momentum.z, 0.0, 8.0 * delta)
			_death_momentum.y = 0.0
		return
 
	if not is_inside_tree() or get_world_3d() == null:
		return
 
	if global_position.y < _spawn_position.y - 8.0:
		global_position = _spawn_position
		velocity = Vector3.ZERO
		return
 
	if _is_invincible:
		_invincibility_timer -= delta
		if _invincibility_timer <= 0.0:
			_is_invincible = false
 
	_process_ai(delta)
 
	if _is_airborne:
		_manage_altitude(delta)
 
	move_and_slide()
 
	# Wand-Kollisionsprüfung nur wenn Spieler NICHT getroffen (sonst → Recovery)
	if _state in [State.DIVE_ATTACK, State.SWIPE_ATTACK] and not _has_hit_player:
		_check_wall_collision()
 
 
func _process_ai(delta: float) -> void:
	if _state not in [State.DEAD, State.HIT, State.WALL_IDLE, State.WALL_STUN]:
		_check_player_detection()
 
	match _state:
		State.WALL_IDLE:
			_process_wall_idle(delta)
		State.WAKE_UP:
			_process_wake_up(delta)
		State.PURSUE:
			_process_pursue(delta)
		State.DIVE_WINDUP:
			_process_dive_windup(delta)
		State.DIVE_ATTACK:
			_process_dive_attack(delta)
		State.DIVE_RECOVERY:
			_process_dive_recovery(delta)
		State.SWIPE_APPROACH:
			_process_swipe_approach(delta)
		State.SWIPE_ATTACK:
			_process_swipe_attack(delta)
		State.SWIPE_RECOVERY:
			_process_swipe_recovery(delta)
		State.WALL_STUN:
			_process_wall_stun(delta)
		State.HIT:
			_process_hit(delta)
 
 
func _on_damage_received(amount: int, from_position: Vector3) -> void:
	var attacker := get_tree().get_first_node_in_group("player")
	if attacker:
		_target = attacker

	var knockback_dir := (global_position - from_position).normalized()
	_update_facing_direction(-knockback_dir)
	_enter_state(State.HIT)
 
 
func _on_death() -> void:
	_state = State.DEAD
	_is_airborne = false
	# Knockback-Richtung vom letzten Treffer → kräftiger Wegschleudern
	var launch_dir := _knockback_velocity.normalized() if _knockback_velocity.length() > 0.01 else Vector3.BACK
	_death_momentum = launch_dir * death_launch_strength
	_death_momentum.y = death_launch_height
 
 
func _on_death_finished() -> void:
	pass
 
 
func _get_hurt_frame() -> Dictionary:
	return {frame = HURT_FRAME, flip = false}
 
 
func _get_death_frames() -> Array[int]:
	return DEATH_FRAME_LIST
 
 
func _reset_stuck_detection() -> void:
	super()
 
 
# ╔══════════════════════════════════════════════════════╗
# ║                     DETECTION                        ║
# ╚══════════════════════════════════════════════════════╝
 
func _setup_detection() -> void:
	if detection_area == null:
		return
	var detection_shape := detection_area.get_node_or_null("CollisionShape3D")
	if detection_shape and detection_shape.shape is SphereShape3D:
		detection_shape.shape.radius = detection_range
	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)
 
 
func _check_player_detection() -> void:
	var player := get_player()
	if player == null:
		return
	var distance := global_position.distance_to(player.global_position)
	if distance > lose_interest_range and _state not in [State.DIVE_ATTACK, State.SWIPE_ATTACK]:
		_target = null
		_enter_state_return_to_wall()
 
 
func _on_detection_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_target = body
		if _state == State.WALL_IDLE:
			_enter_state(State.WAKE_UP)
 
 
func _on_detection_body_exited(_body: Node3D) -> void:
	pass
 
 
# ╔══════════════════════════════════════════════════════╗
# ║                  WALL DETECTION                      ║
# ╚══════════════════════════════════════════════════════╝
 
func _detect_wall_at_spawn() -> void:
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return
 
	var origin := global_position + Vector3(0, 0.2, 0)
	var best_dist := wall_raycast_distance + 1.0
 
	for i in wall_raycast_directions:
		var angle := float(i) / float(wall_raycast_directions) * TAU
		var dir := Vector3(cos(angle), 0, sin(angle))
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin + dir * wall_raycast_distance
		)
		query.exclude = [get_rid()]
		query.collision_mask = 1
 
		var result := space_state.intersect_ray(query)
		if not result.is_empty():
			var dist: float = origin.distance_to(result.position)
			if dist < best_dist:
				best_dist = dist
				_wall_normal = result.normal
 
 
# ╔══════════════════════════════════════════════════════╗
# ║              WALL COLLISION (ABPRALL)                ║
# ╚══════════════════════════════════════════════════════╝
 
## Prüft per slide-Kollision und Backup-Raycast ob eine Wand getroffen wurde.
func _check_wall_collision() -> void:
	# Methode 1: move_and_slide Kollisionsdaten
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider and not collider.is_in_group("player") and collider is StaticBody3D:
			_trigger_wall_stun(col.get_normal())
			return
 
	# Methode 2: Kurzer Vorwärts-Raycast als Backup
	var move_dir := Vector3(velocity.x, 0, velocity.z).normalized()
	if move_dir.length() < 0.1:
		return
 
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return
 
	var origin := global_position + Vector3(0, 0.2, 0)
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + move_dir * wall_check_raycast_len
	)
	query.exclude = [get_rid()]
	query.collision_mask = 1
 
	var result := space_state.intersect_ray(query)
	if not result.is_empty():
		_trigger_wall_stun(result.normal)
 
 
func _trigger_wall_stun(wall_normal: Vector3) -> void:
	var fly_dir := Vector3(velocity.x, 0, velocity.z).normalized()
	var reflected := fly_dir.bounce(wall_normal)
	_stun_bounce_vel = reflected * wall_bounce_strength
	_enter_state(State.WALL_STUN)
 
 
# ╔══════════════════════════════════════════════════════╗
# ║                  STATE MANAGEMENT                    ║
# ╚══════════════════════════════════════════════════════╝
 
func _enter_state(new_state: State) -> void:
	_state = new_state
	_anim_time = 0.0
 
	match new_state:
		State.WALL_IDLE:
			velocity = Vector3.ZERO
			_is_airborne = false
			_reset_stuck_detection()
 
		State.WAKE_UP:
			_state_timer = wake_duration
			velocity = Vector3.ZERO
			_is_airborne = false
			_reset_stuck_detection()
			spawn_alert_popup()
			if _target and is_instance_valid(_target):
				var dir := (_target.global_position - global_position)
				dir.y = 0
				if dir.length() > 0.01:
					_update_facing_direction(dir.normalized())
 
		State.PURSUE:
			_is_airborne = true
			_attack_timer = randf_range(attack_cooldown_min, attack_cooldown_max)
			_flight_time = randf() * TAU
			_reset_stuck_detection()
			if _current_fly_dir == Vector3.ZERO and _target and is_instance_valid(_target):
				var dir := (_target.global_position - global_position)
				dir.y = 0
				_current_fly_dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
 
		State.DIVE_WINDUP:
			_state_timer = dive_windup_time
			_is_airborne = true
			velocity.x = 0.0
			velocity.z = 0.0
			_has_hit_player = false
			_reset_stuck_detection()
			if _target and is_instance_valid(_target):
				var dir := (_target.global_position - global_position)
				dir.y = 0
				if dir.length() > 0.01:
					_update_facing_direction(dir.normalized())
 
		State.DIVE_ATTACK:
			_is_airborne = false  # Keine auto-Höhe während Dive
			_state_timer = dive_duration
			_has_hit_player = false
			_reset_stuck_detection()
			_dive_start_pos = global_position
			if _target and is_instance_valid(_target):
				_dive_target_pos = _target.global_position
				var full_dir := (_dive_target_pos - _dive_start_pos)
				_dive_direction = full_dir.normalized()
				var xz_dir := Vector3(full_dir.x, 0, full_dir.z).normalized()
				_dive_curve_perp = xz_dir.cross(Vector3.UP).normalized()
				if randf() > 0.5:
					_dive_curve_perp *= -1.0
				# Richtung EINMAL fixieren – bleibt während Dive konstant
				if xz_dir.length() > 0.01:
					_update_facing_direction(xz_dir)
			_dive_progress = 0.0
 
		State.DIVE_RECOVERY:
			_state_timer = dive_recovery_time
			_is_airborne = true
			_reset_stuck_detection()
			var carry_dir := _dive_direction
			carry_dir.y = 0
			if carry_dir.length() > 0.01:
				_current_fly_dir = carry_dir.normalized()
 
		State.SWIPE_APPROACH:
			_is_airborne = true
			_has_hit_player = false
			_swipe_side = 1 if randf() > 0.5 else -1
			_reset_stuck_detection()
			_state_timer = 0.0
			_compute_swipe_target()
 
		State.SWIPE_ATTACK:
			_is_airborne = false  # Keine auto-Höhe → fliegt auf Spieler-Y
			_state_timer = swipe_duration
			_has_hit_player = false
			_reset_stuck_detection()
			if _target and is_instance_valid(_target):
				_swipe_direction = (_target.global_position - global_position).normalized()
				_update_facing_direction(Vector3(_swipe_direction.x, 0, _swipe_direction.z))
 
		State.SWIPE_RECOVERY:
			_state_timer = swipe_recovery_time
			_is_airborne = true
			_reset_stuck_detection()
			var carry := Vector3(_swipe_direction.x, 0, _swipe_direction.z)
			if carry.length() > 0.01:
				_current_fly_dir = carry.normalized()
 
		State.WALL_STUN:
			_state_timer = wall_stun_duration
			_is_airborne = false  # Fällt zu Boden → Spieler kann sie treffen
			_has_hit_player = false
			velocity.x = _stun_bounce_vel.x
			velocity.z = _stun_bounce_vel.z
			velocity.y = 0.5
			_reset_stuck_detection()
 
		State.HIT:
			_hit_timer = 0.3
			_is_airborne = true
			_reset_stuck_detection()
 
		State.DEAD:
			pass
 
 
func _enter_state_return_to_wall() -> void:
	_target = null
	var dist_to_spawn := global_position.distance_to(_spawn_position)
	if dist_to_spawn < 1.0:
		global_position = _spawn_position
		_enter_state(State.WALL_IDLE)
	else:
		global_position = _spawn_position
		velocity = Vector3.ZERO
		_enter_state(State.WALL_IDLE)
 
 
# ╔══════════════════════════════════════════════════════╗
# ║                  STATE PROCESSING                    ║
# ╚══════════════════════════════════════════════════════╝
 
func _process_wall_idle(_delta: float) -> void:
	velocity = Vector3.ZERO
	sprite.frame = IDLE_WALL_FRAME
	sprite.flip_h = false
	sprite.modulate = Color.WHITE
 
	if _target and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		if dist <= detection_range:
			_enter_state(State.WAKE_UP)
 
 
func _process_wake_up(delta: float) -> void:
	_anim_time += delta
	var frame_idx := int(_anim_time * WAKE_FPS) % WAKE_FRAMES.size()
	sprite.frame = WAKE_FRAMES[frame_idx]
	sprite.flip_h = false
	sprite.modulate = Color.WHITE
 
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = RISE_SPEED * 0.5
 
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.PURSUE)
 
 
func _process_pursue(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state_return_to_wall()
		return
 
	var to_target := _target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()
 
	if dist > lose_interest_range:
		_enter_state_return_to_wall()
		return
 
	_flight_time += delta
	var desired_dir := to_target.normalized() if dist > 0.1 else _current_fly_dir
 
	var perp := Vector3(-_current_fly_dir.z, 0, _current_fly_dir.x)
	var drift := perp * sin(_flight_time * DRIFT_FREQUENCY * TAU) * DRIFT_AMPLITUDE
 
	var speed_factor := clampf(dist / preferred_distance, 0.3, 1.2)
	var target_dir := (desired_dir + drift * 0.3).normalized()
 
	_current_fly_dir = _current_fly_dir.lerp(target_dir, TURN_SPEED * delta).normalized()
	_update_facing_direction(_current_fly_dir)
 
	var target_vel := _current_fly_dir * FLY_SPEED * speed_factor
	velocity.x = move_toward(velocity.x, target_vel.x, FLY_ACCEL * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, FLY_ACCEL * delta)
 
	_animate_fly(delta)
 
	_attack_timer -= delta
	if _attack_timer <= 0.0 and dist < preferred_distance * 1.8:
		if randf() < dive_chance:
			_enter_state(State.DIVE_WINDUP)
		else:
			_enter_state(State.SWIPE_APPROACH)
 
 
func _process_dive_windup(delta: float) -> void:
	if _target and is_instance_valid(_target):
		var dir := (_target.global_position - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			_update_facing_direction(dir.normalized())
 
	var pull_back := -_current_fly_dir * 0.5
	velocity.x = pull_back.x
	velocity.z = pull_back.z
 
	_show_attack_frame()
 
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.DIVE_ATTACK)
 
 
func _process_dive_attack(delta: float) -> void:
	_dive_progress += delta / maxf(dive_duration, 0.01)
	_dive_progress = clampf(_dive_progress, 0.0, 1.0)
 
	# Leicht gebogener Pfad
	var curve_offset := _dive_curve_perp * sin(_dive_progress * PI) * dive_curve_strength
 
	# Interpoliere Position: Start → Spieler-Position (inkl. Y!)
	# So fliegt die Fledermaus tatsächlich runter auf Spieler-Höhe
	var ideal_pos := _dive_start_pos.lerp(_dive_target_pos, _dive_progress)
	ideal_pos += curve_offset
 
	var to_ideal := ideal_pos - global_position
	var dist_to_ideal := to_ideal.length()
	if dist_to_ideal > 0.01:
		velocity = to_ideal.normalized() * dive_speed
	else:
		velocity = _dive_direction * dive_speed
 
	# Richtung NICHT mehr aktualisieren – beim DIVE_ATTACK-Start fixiert.
	# Das verhindert Flicker wenn Spieler direkt unter/über der Bat ist.
	_show_charge_frame()
 
	if not _has_hit_player:
		_check_attack_hit(0.7)
 
	# Treffer gelandet → sofort in Recovery (kein weiterer Flug = kein Wand-Stun)
	if _has_hit_player:
		_enter_state(State.DIVE_RECOVERY)
		return
 
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.DIVE_RECOVERY)
 
 
func _process_dive_recovery(delta: float) -> void:
	var slow_factor := _state_timer / maxf(dive_recovery_time, 0.01)
	velocity.x = _current_fly_dir.x * FLY_SPEED * slow_factor * 0.6
	velocity.z = _current_fly_dir.z * FLY_SPEED * slow_factor * 0.6
	# _is_airborne = true → _manage_altitude zieht die Bat automatisch hoch
 
	_update_facing_direction(_current_fly_dir)
	_animate_fly(delta)
 
	_state_timer -= delta
	if _state_timer <= 0.0:
		if _target and is_instance_valid(_target):
			_enter_state(State.PURSUE)
		else:
			_enter_state_return_to_wall()
 
 
func _process_swipe_approach(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state(State.PURSUE)
		return
 
	_compute_swipe_target()
	var to_swipe_pos := _swipe_target_pos - global_position
	to_swipe_pos.y = 0
	var dist := to_swipe_pos.length()
 
	if dist < 0.5:
		_enter_state(State.SWIPE_ATTACK)
		return
 
	var dir := to_swipe_pos.normalized()
	_current_fly_dir = _current_fly_dir.lerp(dir, TURN_SPEED * 1.5 * delta).normalized()
	_update_facing_direction(_current_fly_dir)
 
	velocity.x = _current_fly_dir.x * swipe_approach_speed
	velocity.z = _current_fly_dir.z * swipe_approach_speed
 
	_animate_fly(delta)
 
	_state_timer += delta
	if _state_timer > 2.0:
		_enter_state(State.SWIPE_ATTACK)
 
 
func _process_swipe_attack(delta: float) -> void:
	# Fliegt mit voller 3D-Richtung (inkl. Y) zum Spieler durch
	velocity = _swipe_direction * swipe_speed
 
	_show_charge_frame()
 
	if not _has_hit_player:
		_check_attack_hit(0.8)
 
	# Treffer gelandet → sofort in Recovery (kein Wand-Stun nach erfolgreichem Hit)
	if _has_hit_player:
		_enter_state(State.SWIPE_RECOVERY)
		return
 
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.SWIPE_RECOVERY)
 
 
func _process_swipe_recovery(delta: float) -> void:
	var slow := _state_timer / maxf(swipe_recovery_time, 0.01)
	velocity.x = _current_fly_dir.x * FLY_SPEED * slow * 0.4
	velocity.z = _current_fly_dir.z * FLY_SPEED * slow * 0.4
 
	_update_facing_direction(_current_fly_dir)
	_animate_fly(delta)
 
	_state_timer -= delta
	if _state_timer <= 0.0:
		if _target and is_instance_valid(_target):
			_enter_state(State.PURSUE)
		else:
			_enter_state_return_to_wall()
 
 
func _process_wall_stun(delta: float) -> void:
	# Abprall abbremsen
	_stun_bounce_vel = _stun_bounce_vel.move_toward(Vector3.ZERO, wall_bounce_strength * 2.0 * delta)
	velocity.x = _stun_bounce_vel.x
	velocity.z = _stun_bounce_vel.z
 
	# Gravitation → Fledermaus fällt zu Boden
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
 
	# Benommen-Animation: Hurt-Frame + gelbliches Flackern
	_anim_time += delta
	sprite.frame = HURT_FRAME
	sprite.flip_h = false
	var flash := fmod(_anim_time, 0.12) < 0.06
	sprite.modulate = Color(1.0, 1.0, 0.6) if flash else Color(0.8, 0.8, 1.0)
 
	_state_timer -= delta
	if _state_timer <= 0.0:
		sprite.modulate = Color.WHITE
		if _target and is_instance_valid(_target):
			_enter_state(State.PURSUE)
		else:
			_enter_state_return_to_wall()
 
 
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
			_enter_state(State.PURSUE)
		else:
			_enter_state_return_to_wall()
 
 
# ╔══════════════════════════════════════════════════════╗
# ║                  ALTITUDE MANAGEMENT                 ║
# ╚══════════════════════════════════════════════════════╝
 
func _manage_altitude(delta: float) -> void:
	var bob := sin(_flight_time * BOB_FREQUENCY * TAU) * BOB_AMPLITUDE
	var target_y := _fly_target_y + bob
	var diff := target_y - global_position.y
 
	if abs(diff) > 0.05:
		velocity.y = diff * RISE_SPEED
	else:
		velocity.y = move_toward(velocity.y, 0.0, RISE_SPEED * delta)
 
 
# ╔══════════════════════════════════════════════════════╗
# ║                  ATTACK HIT DETECTION                ║
# ╚══════════════════════════════════════════════════════╝
 
func _check_attack_hit(hit_radius: float) -> void:
	if not _target or not is_instance_valid(_target):
		return
 
	var to_target := _target.global_position - global_position
	var dist := to_target.length()  # Volle 3D-Distanz
 
	if dist <= hit_radius:
		_has_hit_player = true
		if _target.has_method("take_damage"):
			_target.take_damage(damage, global_position)
 
 
func _compute_swipe_target() -> void:
	if not _target or not is_instance_valid(_target):
		return
 
	var to_player := _target.global_position - global_position
	to_player.y = 0
	var dir := to_player.normalized()
	var perp := Vector3(-dir.z, 0, dir.x) * float(_swipe_side)
 
	_swipe_target_pos = _target.global_position + perp * swipe_lateral_offset - dir * 1.0
	_swipe_target_pos.y = _fly_target_y
 
 
# ╔══════════════════════════════════════════════════════╗
# ║                  DIRECTION HANDLING                  ║
# ╚══════════════════════════════════════════════════════╝
 
## Sektor-Mittelpunkt für jede Richtung (in Grad, 0° = RIGHT, läuft im Uhrzeigersinn da Z = Down)
const _DIR_ANGLES := {
	DirMode.RIGHT: 0.0,
	DirMode.DOWN_RIGHT: 45.0,
	DirMode.DOWN: 90.0,
	DirMode.DOWN_LEFT: 135.0,
	DirMode.LEFT: 180.0,
	DirMode.UP_LEFT: 225.0,
	DirMode.UP: 270.0,
	DirMode.UP_RIGHT: 315.0,
}
 
## Hysterese-Schwelle: aktuelle Richtung wird nur gewechselt, wenn der Winkel
## mehr als (22.5° + HYSTERESIS) von der Sektor-Mitte abweicht.
## 22.5° = halber Sektor (8 Richtungen á 45°). +7° = 29.5° Toleranz.
const _DIR_HYSTERESIS_DEG: float = 7.0
 
 
func _update_facing_direction(dir: Vector3) -> void:
	if dir == Vector3.ZERO:
		return
 
	var dir2d := Vector2(dir.x, dir.z)
	var angle := rad_to_deg(dir2d.angle())
	if angle < 0:
		angle += 360.0
 
	# Aktueller Sektor-Mittelpunkt
	var current_center: float = _DIR_ANGLES.get(_facing_dir, 0.0)
	var diff: float = abs(_angle_delta(angle, current_center))
 
	# Innerhalb der Hysterese-Zone? Dann Richtung beibehalten.
	if diff < 22.5 + _DIR_HYSTERESIS_DEG:
		return
 
	# Sonst: nächste Richtung über Standard-Sektor-Schwellen bestimmen
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
 
 
## Kürzeste Winkeldifferenz zwischen zwei Winkeln (handled 360°-Wrap)
func _angle_delta(a: float, b: float) -> float:
	var d: float = fmod(a - b + 540.0, 360.0) - 180.0
	return d
 
 
# ╔══════════════════════════════════════════════════════╗
# ║                     ANIMATION                        ║
# ╚══════════════════════════════════════════════════════╝
 
func _get_fly_frames_and_flip() -> Dictionary:
	match _facing_dir:
		DirMode.RIGHT:
			return {flip = false, frames = FLY_RIGHT}
		DirMode.LEFT:
			return {flip = true, frames = FLY_RIGHT}
		DirMode.DOWN_RIGHT:
			return {flip = false, frames = FLY_BOTTOM_RIGHT}
		DirMode.DOWN_LEFT:
			return {flip = true, frames = FLY_BOTTOM_RIGHT}
		DirMode.DOWN:
			return {flip = false, frames = FLY_BOTTOM}
		DirMode.UP_RIGHT:
			return {flip = false, frames = FLY_TOP_RIGHT}
		DirMode.UP_LEFT:
			return {flip = true, frames = FLY_TOP_RIGHT}
		DirMode.UP:
			return {flip = false, frames = FLY_TOP}
		_:
			return {flip = false, frames = FLY_BOTTOM}
 
 
func _get_attack_frame_and_flip() -> Dictionary:
	match _facing_dir:
		DirMode.RIGHT:
			return {flip = false, frame = ATTACK_RIGHT}
		DirMode.LEFT:
			return {flip = true, frame = ATTACK_RIGHT}
		DirMode.DOWN_RIGHT:
			return {flip = false, frame = ATTACK_BOTTOM_RIGHT}
		DirMode.DOWN_LEFT:
			return {flip = true, frame = ATTACK_BOTTOM_RIGHT}
		DirMode.DOWN:
			return {flip = false, frame = ATTACK_BOTTOM}
		DirMode.UP_RIGHT:
			return {flip = false, frame = ATTACK_TOP_RIGHT}
		DirMode.UP_LEFT:
			return {flip = true, frame = ATTACK_TOP_RIGHT}
		DirMode.UP:
			return {flip = false, frame = ATTACK_TOP}
		_:
			return {flip = false, frame = ATTACK_BOTTOM}
 
 
func _get_charge_frame_and_flip() -> Dictionary:
	match _facing_dir:
		DirMode.RIGHT:
			return {flip = false, frame = CHARGE_RIGHT}
		DirMode.LEFT:
			return {flip = true, frame = CHARGE_RIGHT}
		DirMode.DOWN_RIGHT:
			return {flip = false, frame = CHARGE_BOTTOM_RIGHT}
		DirMode.DOWN_LEFT:
			return {flip = true, frame = CHARGE_BOTTOM_RIGHT}
		DirMode.DOWN:
			return {flip = false, frame = CHARGE_BOTTOM}
		DirMode.UP_RIGHT:
			return {flip = false, frame = CHARGE_TOP_RIGHT}
		DirMode.UP_LEFT:
			return {flip = true, frame = CHARGE_TOP_RIGHT}
		DirMode.UP:
			return {flip = false, frame = CHARGE_TOP}
		_:
			return {flip = false, frame = CHARGE_BOTTOM}
 
 
func _animate_fly(delta: float) -> void:
	_anim_time += delta
	var data := _get_fly_frames_and_flip()
	var frames: Array = data.frames
	var idx: int = int(_anim_time * FLY_FPS) % frames.size()
	sprite.frame = frames[idx]
	sprite.flip_h = data.flip
	sprite.modulate = Color.WHITE
 
 
func _show_attack_frame() -> void:
	var data := _get_attack_frame_and_flip()
	sprite.frame = data.frame
	sprite.flip_h = data.flip
	sprite.modulate = Color.WHITE
 
 
func _show_charge_frame() -> void:
	var data := _get_charge_frame_and_flip()
	sprite.frame = data.frame
	sprite.flip_h = data.flip
	sprite.modulate = Color.WHITE
 
 
func _animate_hit_damaged(delta: float) -> void:
	_anim_time += delta
	sprite.frame = HURT_FRAME
	sprite.flip_h = false
	var flash := fmod(_anim_time, hit_flash_duration * 2.0) < hit_flash_duration
	sprite.modulate = Color(1.5, 0.5, 0.5) if flash else Color.WHITE

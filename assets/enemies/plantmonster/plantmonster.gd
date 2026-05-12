extends Enemy
class_name PlantMonster

## Pflanzenmonster mit 8-Richtungs-Animation und Ranken-Zungenangriff
## Die Zunge besteht aus einer Kette von Segmenten + Tip

# === MOVEMENT ===
@export_group("Movement")
@export var WALK_SPEED: float = 0.8

# === COMBAT ===
@export_group("Combat")
@export var damage: int = 8
@export var attack_range: float = 4.0
@export var attack_cooldown: float = 3.0
@export var tongue_speed: float = 8.0
@export var tongue_retract_speed: float = 6.0
@export var tongue_hold_time: float = 0.15
@export var tongue_max_length: float = 3.5
@export var windup_duration: float = 0.4

# === TONGUE SPRITES ===
@export_group("Tongue Sprites")
@export var tongue_segment_texture: Texture2D
@export var tongue_tip_texture: Texture2D
@export var tongue_pixel_size: float = 0.01
@export var segment_spacing: float = 0.25

@export var tongue_behind_distance: float = 0.4

# === TONGUE OFFSETS (2D Pixel-Offset auf dem Sprite, wird zur Laufzeit umgerechnet) ===
@export_group("Tongue Offsets")
@export var tongue_sprite_offset_up: Vector2 = Vector2(0, 8)
@export var tongue_sprite_offset_up_right: Vector2 = Vector2(6, 6)
@export var tongue_sprite_offset_right: Vector2 = Vector2(14, -5)
@export var tongue_sprite_offset_down_right: Vector2 = Vector2(6, -4)
@export var tongue_sprite_offset_down: Vector2 = Vector2(0, -6)
@export var tongue_height: float = 0.1

# Mindestabstand bevor Segment sichtbar wird (versteckt Spawn im Mund)
@export var tongue_visible_threshold: float = 0.08

# === OBSTACLE AVOIDANCE ===
@export_group("Obstacle Avoidance")
@export var separation_radius: float = 1.2
@export var separation_strength: float = 0.8
@export var obstacle_raycast_length: float = 1.0

# === ANIMATION ===
@export_group("Animation")
@export var WALK_FPS: float = 6.0
@export var HURT_FPS: float = 8.0

@export var tongue_mouth_overlap: float = 0.18

# === TONGUE VFX ===
@export_group("Tongue VFX")
@export var tongue_vfx_scene: PackedScene
@export var vfx_bubble_color: Color = Color(0.25, 0.9, 0.2, 0.6)
@export var vfx_bubble_highlight: Color = Color(0.5, 1.0, 0.4, 0.8)
@export var vfx_glow_color: Color = Color(0.3, 1.0, 0.2, 1.0)

var _tongue_vfx: TongueVFX = null

const DIRECTION_HYSTERESIS: float = 20.0

# === FRAME DEFINITIONS ===
const IDLE_FRAMES := {
	DirMode.RIGHT: 0,
	DirMode.DOWN_RIGHT: 2,
	DirMode.DOWN: 4,
	DirMode.DOWN_LEFT: 2,
	DirMode.LEFT: 0,
	DirMode.UP_LEFT: 6,
	DirMode.UP: 8,
	DirMode.UP_RIGHT: 6,
}

const WALK_FRAMES := {
	DirMode.RIGHT: [0, 10, 0, 11],
	DirMode.DOWN_RIGHT: [2, 12, 2, 13],
	DirMode.DOWN: [4, 14, 4, 15],
	DirMode.DOWN_LEFT: [2, 12, 2, 13],
	DirMode.LEFT: [0, 10, 0, 11],
	DirMode.UP_LEFT: [6, 16, 6, 17],
	DirMode.UP: [8, 18, 8, 19],
	DirMode.UP_RIGHT: [6, 16, 6, 17],
}

const ATTACK_FRAMES := {
	DirMode.RIGHT: 1,
	DirMode.DOWN_RIGHT: 3,
	DirMode.DOWN: 5,
	DirMode.DOWN_LEFT: 3,
	DirMode.LEFT: 1,
	DirMode.UP_LEFT: 7,
	DirMode.UP: 9,
	DirMode.UP_RIGHT: 7,
}

const HURT_FRAMES := {
	DirMode.RIGHT: 20,
	DirMode.DOWN_RIGHT: 20,
	DirMode.DOWN: 21,
	DirMode.DOWN_LEFT: 20,
	DirMode.LEFT: 20,
	DirMode.UP_LEFT: 20,
	DirMode.UP: 22,
	DirMode.UP_RIGHT: 20,
}

const DEATH_FRAME_LIST: Array[int] = [30, 31, 32]

const FLIPPED_DIRS := [DirMode.DOWN_LEFT, DirMode.LEFT, DirMode.UP_LEFT]
const TONGUE_BEHIND_DIRS := [DirMode.UP, DirMode.UP_LEFT, DirMode.UP_RIGHT]

const TONGUE_FRAME_MAP := {
	DirMode.RIGHT: 0,
	DirMode.LEFT: 0,
	DirMode.DOWN_RIGHT: 1,
	DirMode.DOWN_LEFT: 1,
	DirMode.DOWN: 2,
	DirMode.UP_RIGHT: 3,
	DirMode.UP_LEFT: 3,
	DirMode.UP: 4,
}

# === STATE MACHINE ===
enum State {
	PATROL_IDLE,
	PATROL_WALK,
	ALERT,
	CHASE,
	COMBAT_IDLE,
	ATTACK_WINDUP,
	ATTACK_TONGUE_OUT,
	ATTACK_TONGUE_HOLD,
	ATTACK_TONGUE_RETRACT,
	ATTACK_COOLDOWN,
	HIT,
	DEAD
}
var _state: State = State.PATROL_IDLE
var _state_timer: float = 0.0

# === DIRECTION ===
enum DirMode {
	RIGHT, DOWN_RIGHT, DOWN, DOWN_LEFT,
	LEFT, UP_LEFT, UP, UP_RIGHT
}
var _facing_dir: DirMode = DirMode.DOWN

# === PATROL ===
var _patrol_target: Vector3

# === COMBAT ===
var _attack_cooldown_timer: float = 0.0
var _has_hit_player: bool = false

# === TONGUE ===
var _tongue_segments: Array[Sprite3D] = []
var _tongue_tip: Sprite3D = null
var _tongue_hitbox: Area3D = null
var _tongue_current_length: float = 0.0
var _tongue_target_length: float = 0.0
var _tongue_direction: Vector3 = Vector3.ZERO
var _tongue_container: Node3D = null


# === LIFECYCLE ===

func _on_ready_after_terrain() -> void:
	_last_position_check = global_position
	_state = State.PATROL_IDLE
	_state_timer = randf_range(patrol_wait_time_min, patrol_wait_time_max)
	_setup_tongue()


func _setup_tongue() -> void:
	_tongue_container = Node3D.new()
	_tongue_container.name = "TongueContainer"
	add_child(_tongue_container)

	_tongue_tip = _create_tongue_sprite("TongueTip", tongue_tip_texture)
	_tongue_container.add_child(_tongue_tip)

	# === VFX SETUP ===
	if tongue_vfx_scene:
		_tongue_vfx = tongue_vfx_scene.instantiate() as TongueVFX
	else:
		_tongue_vfx = TongueVFX.new()

	_tongue_vfx.set_colors(vfx_bubble_color, vfx_bubble_highlight, vfx_glow_color)
	_tongue_container.add_child(_tongue_vfx)

	# === HITBOX ===
	_tongue_hitbox = Area3D.new()
	_tongue_hitbox.name = "TongueHitbox"
	_tongue_hitbox.collision_layer = 0
	_tongue_hitbox.collision_mask = 1
	_tongue_hitbox.monitoring = false

	var hitbox_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	hitbox_shape.shape = sphere
	_tongue_hitbox.add_child(hitbox_shape)
	_tongue_hitbox.body_entered.connect(_on_tongue_hit)
	_tongue_container.add_child(_tongue_hitbox)


func _create_tongue_sprite(sprite_name: String, texture: Texture2D) -> Sprite3D:
	var s := Sprite3D.new()
	s.name = sprite_name
	s.texture = texture
	s.hframes = 5
	s.vframes = 1
	s.frame = 0
	s.pixel_size = tongue_pixel_size
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.shaded = false
	s.double_sided = true
	s.transparent = true
	s.visible = false
	s.centered = true
	s.offset = Vector2.ZERO
	return s


# === MAIN AI LOOP ===

func _process_ai(delta: float) -> void:
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta

	if _state not in [State.DEAD, State.HIT, State.ATTACK_TONGUE_OUT, State.ATTACK_TONGUE_HOLD, State.ATTACK_TONGUE_RETRACT]:
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
		State.COMBAT_IDLE:
			_process_combat_idle(delta)
		State.ATTACK_WINDUP:
			_process_attack_windup(delta)
		State.ATTACK_TONGUE_OUT:
			_process_attack_tongue_out(delta)
		State.ATTACK_TONGUE_HOLD:
			_process_attack_tongue_hold(delta)
		State.ATTACK_TONGUE_RETRACT:
			_process_attack_tongue_retract(delta)
		State.ATTACK_COOLDOWN:
			_process_attack_cooldown(delta)
		State.HIT:
			_process_hit(delta)


# === PLAYER DETECTION ===

func _check_player_detection() -> void:
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player")

	if _target == null:
		return

	var distance := global_position.distance_to(_target.global_position)

	if distance <= detection_range:
		if _state in [State.PATROL_IDLE, State.PATROL_WALK]:
			_enter_state(State.ALERT)
	elif distance > lose_interest_range:
		if _state in [State.CHASE, State.COMBAT_IDLE, State.ATTACK_COOLDOWN]:
			_target = null
			_enter_state(State.PATROL_IDLE)


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
			spawn_alert_popup()
			_face_target()

		State.CHASE:
			_reset_stuck_detection()

		State.COMBAT_IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			_state_timer = randf_range(0.3, 0.8)

		State.ATTACK_WINDUP:
			velocity.x = 0.0
			velocity.z = 0.0
			_state_timer = windup_duration
			_has_hit_player = false
			_prepare_tongue_attack()

		State.ATTACK_TONGUE_OUT:
			_tongue_current_length = 0.0
			_show_tongue()
			_update_tongue_frame()
			_update_tongue_chain()

		State.ATTACK_TONGUE_HOLD:
			_state_timer = tongue_hold_time

		State.ATTACK_TONGUE_RETRACT:
			_tongue_hitbox.monitoring = false

		State.ATTACK_COOLDOWN:
			_hide_tongue()
			_attack_cooldown_timer = attack_cooldown
			_state_timer = 0.5

		State.HIT:
			_hit_timer = 0.3
			_hide_tongue()
			_reset_stuck_detection()


# === STATE PROCESSORS ===

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
		_enter_state(State.PATROL_IDLE)
		return

	dir = dir.normalized()

	var separation := _get_separation_vector()
	var move_dir := (dir + separation).normalized()

	if _is_path_blocked(move_dir):
		move_dir = _find_alternate_direction(move_dir)

	_update_facing_direction(move_dir)
	velocity.x = move_dir.x * WALK_SPEED
	velocity.z = move_dir.z * WALK_SPEED

	_animate_walk(delta)

	if _check_if_stuck(delta):
		_enter_state(State.PATROL_IDLE)


func _process_alert(delta: float) -> void:
	_animate_idle()
	_face_target()

	_state_timer -= delta
	if _state_timer <= 0.0:
		if _target and is_instance_valid(_target):
			_enter_state(State.CHASE)
		else:
			_enter_state(State.PATROL_IDLE)


func _process_chase(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state(State.PATROL_IDLE)
		return

	var to_target := _target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()

	if dist <= attack_range:
		_enter_state(State.COMBAT_IDLE)
		return

	var dir := to_target.normalized()
	var separation := _get_separation_vector()
	var move_dir := (dir + separation).normalized()

	if _is_path_blocked(move_dir):
		move_dir = _find_alternate_direction(move_dir)

	_update_facing_direction(move_dir)
	velocity.x = move_dir.x * WALK_SPEED * 1.2
	velocity.z = move_dir.z * WALK_SPEED * 1.2

	_animate_walk(delta)

	if _check_if_stuck(delta):
		var alt_dir := _find_alternate_direction(dir)
		velocity.x = alt_dir.x * WALK_SPEED
		velocity.z = alt_dir.z * WALK_SPEED
		_reset_stuck_detection()


func _process_combat_idle(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state(State.PATROL_IDLE)
		return

	var to_target := _target.global_position - global_position
	to_target.y = 0
	var dist := to_target.length()

	if dist > attack_range * 1.2:
		_enter_state(State.CHASE)
		return

	_update_facing_direction(to_target.normalized())
	_animate_idle()

	_state_timer -= delta
	if _state_timer <= 0.0:
		if _attack_cooldown_timer <= 0.0:
			_enter_state(State.ATTACK_WINDUP)
		else:
			_state_timer = 0.3


func _process_attack_windup(delta: float) -> void:
	_prepare_tongue_attack()
	_animate_attack()

	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.ATTACK_TONGUE_OUT)


func _process_attack_tongue_out(delta: float) -> void:
	_tongue_current_length += tongue_speed * delta

	if _tongue_current_length >= _tongue_target_length:
		_tongue_current_length = _tongue_target_length

		if _tongue_vfx:
			var tip_pos := _get_tongue_offset() + _tongue_direction.normalized() * _tongue_current_length
			tip_pos.y = tongue_height
			_tongue_vfx.spawn_impact(tip_pos)

		_enter_state(State.ATTACK_TONGUE_HOLD)

	_update_tongue_chain()
	_animate_attack()


func _process_attack_tongue_hold(delta: float) -> void:
	_update_tongue_chain()
	_animate_attack()

	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.ATTACK_TONGUE_RETRACT)


func _process_attack_tongue_retract(delta: float) -> void:
	_tongue_current_length -= tongue_retract_speed * delta

	if _tongue_current_length <= 0.0:
		_tongue_current_length = 0.0
		_enter_state(State.ATTACK_COOLDOWN)

	_update_tongue_chain()
	_animate_attack()


func _process_attack_cooldown(delta: float) -> void:
	_animate_idle()

	_state_timer -= delta
	if _state_timer <= 0.0:
		if _target and is_instance_valid(_target):
			var dist := global_position.distance_to(_target.global_position)
			if dist <= attack_range:
				_enter_state(State.COMBAT_IDLE)
			elif dist <= lose_interest_range:
				_enter_state(State.CHASE)
			else:
				_target = null
				_enter_state(State.PATROL_IDLE)
		else:
			_enter_state(State.PATROL_IDLE)


func _process_hit(delta: float) -> void:
	_hit_timer -= delta

	velocity.x = _knockback_velocity.x
	velocity.z = _knockback_velocity.z
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, knockback_strength * 3.0 * delta)

	_animate_hit(delta)

	if _hit_timer <= 0.0:
		if _health <= 0:
			_die()
		elif _target and is_instance_valid(_target):
			_enter_state(State.CHASE)
		else:
			_enter_state(State.PATROL_IDLE)


# === TONGUE CHAIN SYSTEM ===

func _prepare_tongue_attack() -> void:
	if _target and is_instance_valid(_target):
		var dir := (_target.global_position - global_position)
		dir.y = 0
		_tongue_direction = dir.normalized()
		# Richtung sofort snappen ohne Hysterese
		var angle := rad_to_deg(atan2(_tongue_direction.x, _tongue_direction.z))
		if angle < 0.0:
			angle += 360.0
		_facing_dir = _angle_to_direction(angle)
		_tongue_target_length = minf(dir.length(), tongue_max_length)


func _update_tongue_frame() -> void:
	var frame_idx: int = 2

	_tongue_tip.frame = frame_idx
	_tongue_tip.flip_h = false

	for segment in _tongue_segments:
		segment.frame = frame_idx
		segment.flip_h = false


func _update_tongue_chain() -> void:
	if not _tongue_tip.visible:
		return

	var base_offset := _get_tongue_offset()

	var dir := _tongue_direction
	dir.y = 0.0
	if dir.length() <= 0.0001:
		return
	dir = dir.normalized()

	var tongue_angle := atan2(dir.x, dir.z) + PI
	var len := _tongue_current_length

	# === TIP ===
	var tip_pos := base_offset + dir * len
	tip_pos.y = tongue_height
	_tongue_tip.position = tip_pos
	_tongue_tip.rotation.y = tongue_angle
	_tongue_tip.render_priority = 100

	# === SEGMENTE ===
	var tip_size := 0.15
	var segment_end := len - tip_size

	if segment_end <= 0:
		for s in _tongue_segments:
			s.visible = false
	else:
		var needed_segments := ceili(segment_end / segment_spacing)
		needed_segments = clampi(needed_segments, 0, 60)

		while _tongue_segments.size() < needed_segments:
			var new_segment := _create_tongue_sprite("TongueSegment_%d" % _tongue_segments.size(), tongue_segment_texture)
			_tongue_container.add_child(new_segment)
			_tongue_segments.append(new_segment)
			_update_tongue_frame()

		for i in range(_tongue_segments.size()):
			_tongue_segments[i].visible = false

		for i in range(needed_segments):
			var segment := _tongue_segments[i]
			var t := float(i + 0.5) / float(needed_segments)
			var dist := lerpf(-tongue_mouth_overlap, segment_end, t)

			var segment_pos := base_offset + dir * dist
			segment_pos.y = tongue_height

			if dist < tongue_behind_distance:
				segment.render_priority = -5 - i
			else:
				segment.render_priority = 5 + i

			segment.position = segment_pos
			segment.rotation.y = tongue_angle
			segment.visible = dist >= tongue_visible_threshold

	# === VFX UPDATE ===
	if _tongue_vfx:
		_tongue_vfx.update_position(tip_pos, dir)

	# === HITBOX ===
	_tongue_hitbox.position = tip_pos


func _show_tongue() -> void:
	_tongue_tip.visible = true
	_tongue_hitbox.monitoring = true

	if _tongue_vfx:
		_tongue_vfx.start(Vector3.ZERO)


func _hide_tongue() -> void:
	_tongue_tip.visible = false
	_tongue_tip.position = Vector3.ZERO
	_tongue_hitbox.monitoring = false
	_tongue_hitbox.position = Vector3.ZERO
	_tongue_current_length = 0.0

	if _tongue_vfx:
		_tongue_vfx.stop()

	# Segmente komplett freigeben statt nur verstecken
	for segment in _tongue_segments:
		segment.queue_free()
	_tongue_segments.clear()


func _on_tongue_hit(body: Node3D) -> void:
	if _has_hit_player:
		return

	if body.is_in_group("player") and body.has_method("take_damage"):
		_has_hit_player = true
		body.take_damage(damage, global_position)

		if _tongue_vfx:
			_tongue_vfx.spawn_impact(_tongue_tip.position)


func _get_tongue_offset() -> Vector3:
	var pixel_offset: Vector2 = _get_tongue_pixel_offset()

	var world_offset_x: float = pixel_offset.x * tongue_pixel_size
	var world_offset_z: float = -pixel_offset.y * tongue_pixel_size

	var camera := get_viewport().get_camera_3d()
	if camera:
		var cam_right := camera.global_transform.basis.x.normalized()
		cam_right.y = 0
		cam_right = cam_right.normalized()

		var cam_forward := -camera.global_transform.basis.z.normalized()
		cam_forward.y = 0
		cam_forward = cam_forward.normalized()

		var offset_3d := cam_right * world_offset_x + cam_forward * world_offset_z
		offset_3d.y = tongue_height
		return offset_3d

	return Vector3(world_offset_x, tongue_height, world_offset_z)


func _get_tongue_pixel_offset() -> Vector2:
	match _facing_dir:
		DirMode.UP:
			return tongue_sprite_offset_up
		DirMode.UP_RIGHT:
			return tongue_sprite_offset_up_right
		DirMode.UP_LEFT:
			return Vector2(-tongue_sprite_offset_up_right.x, tongue_sprite_offset_up_right.y)
		DirMode.RIGHT:
			return tongue_sprite_offset_right
		DirMode.LEFT:
			return Vector2(-tongue_sprite_offset_right.x, tongue_sprite_offset_right.y)
		DirMode.DOWN_RIGHT:
			return tongue_sprite_offset_down_right
		DirMode.DOWN_LEFT:
			return Vector2(-tongue_sprite_offset_down_right.x, tongue_sprite_offset_down_right.y)
		DirMode.DOWN:
			return tongue_sprite_offset_down
		_:
			return tongue_sprite_offset_down


# === OBSTACLE AVOIDANCE ===

func _get_separation_vector() -> Vector3:
	var separation := Vector3.ZERO
	var neighbors := 0

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self:
			continue

		var dist := global_position.distance_to(enemy.global_position)
		if dist < separation_radius and dist > 0.01:
			var away: Vector3 = (global_position - enemy.global_position).normalized()
			away.y = 0
			var strength := (separation_radius - dist) / separation_radius
			separation += away * strength
			neighbors += 1

	if neighbors > 0:
		separation = separation.normalized() * separation_strength

	return separation


func _is_path_blocked(direction: Vector3) -> bool:
	var space_state := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 0.3, 0)
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * obstacle_raycast_length
	)
	query.exclude = [self]
	query.collision_mask = 1

	var result := space_state.intersect_ray(query)
	return not result.is_empty()


func _find_alternate_direction(blocked_dir: Vector3) -> Vector3:
	var right := blocked_dir.cross(Vector3.UP).normalized()

	if not _is_path_blocked(right):
		return (blocked_dir * 0.3 + right * 0.7).normalized()

	if not _is_path_blocked(-right):
		return (blocked_dir * 0.3 - right * 0.7).normalized()

	return -blocked_dir


# === HELPER FUNCTIONS ===

func _face_target() -> void:
	if _target and is_instance_valid(_target):
		var dir := (_target.global_position - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			_update_facing_direction(dir.normalized())


# === DIRECTION ===


func _update_facing_direction(dir: Vector3) -> void:
	if dir.is_zero_approx():
		return

	var angle := atan2(dir.x, dir.z)
	angle = rad_to_deg(angle)
	if angle < 0:
		angle += 360.0

	var new_dir := _angle_to_direction(angle)

	if new_dir != _facing_dir:
		var current_center := _direction_to_center_angle(_facing_dir)
		var angle_diff := absf(_angle_difference(angle, current_center))

		if angle_diff > 22.5 + DIRECTION_HYSTERESIS:
			_facing_dir = new_dir


func _angle_to_direction(angle: float) -> DirMode:
	if angle >= 337.5 or angle < 22.5:
		return DirMode.DOWN
	elif angle >= 22.5 and angle < 67.5:
		return DirMode.DOWN_RIGHT
	elif angle >= 67.5 and angle < 112.5:
		return DirMode.RIGHT
	elif angle >= 112.5 and angle < 157.5:
		return DirMode.UP_RIGHT
	elif angle >= 157.5 and angle < 202.5:
		return DirMode.UP
	elif angle >= 202.5 and angle < 247.5:
		return DirMode.UP_LEFT
	elif angle >= 247.5 and angle < 292.5:
		return DirMode.LEFT
	else:
		return DirMode.DOWN_LEFT


func _direction_to_center_angle(dir: DirMode) -> float:
	match dir:
		DirMode.DOWN: return 0.0
		DirMode.DOWN_RIGHT: return 45.0
		DirMode.RIGHT: return 90.0
		DirMode.UP_RIGHT: return 135.0
		DirMode.UP: return 180.0
		DirMode.UP_LEFT: return 225.0
		DirMode.LEFT: return 270.0
		DirMode.DOWN_LEFT: return 315.0
		_: return 0.0


func _angle_difference(a: float, b: float) -> float:
	var diff := fmod(a - b + 180.0, 360.0) - 180.0
	return diff


# === ANIMATION ===

func _animate_idle() -> void:
	sprite.frame = IDLE_FRAMES[_facing_dir]
	sprite.flip_h = _facing_dir in FLIPPED_DIRS
	sprite.modulate = Color.WHITE


func _animate_walk(delta: float) -> void:
	_anim_time += delta
	var frames: Array = WALK_FRAMES[_facing_dir]
	var idx: int = int(_anim_time * WALK_FPS) % frames.size()
	sprite.frame = frames[idx]
	sprite.flip_h = _facing_dir in FLIPPED_DIRS
	sprite.modulate = Color.WHITE


func _animate_attack() -> void:
	if ATTACK_FRAMES.has(_facing_dir):
		sprite.frame = ATTACK_FRAMES[_facing_dir]
	else:
		sprite.frame = IDLE_FRAMES[_facing_dir]
	sprite.flip_h = _facing_dir in FLIPPED_DIRS
	sprite.modulate = Color.WHITE


func _animate_hit(delta: float) -> void:
	var data := _get_hurt_frame()
	sprite.frame = data.frame
	sprite.flip_h = data.flip
	var flash := fmod(_anim_time, hit_flash_duration * 2.0) < hit_flash_duration
	sprite.modulate = Color(1.5, 0.5, 0.5) if flash else Color.WHITE
	_anim_time += delta


# === ENEMY OVERRIDES ===

func _on_damage_received(amount: int, from_position: Vector3) -> void:
	var knockback_dir := (global_position - from_position).normalized()
	_update_facing_direction(-knockback_dir)
	_enter_state(State.HIT)


func _on_death() -> void:
	_hide_tongue()
	_state = State.DEAD


func _get_hurt_frame() -> Dictionary:
	var frame: int = HURT_FRAMES[_facing_dir]
	var flip: bool = _facing_dir in FLIPPED_DIRS
	return {frame = frame, flip = flip}


func _get_death_frames() -> Array[int]:
	return DEATH_FRAME_LIST

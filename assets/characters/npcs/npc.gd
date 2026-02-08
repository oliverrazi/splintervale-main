extends CharacterBody3D
class_name NPC

signal dialogue_started(npc: NPC)
signal dialogue_ended(npc: NPC)

enum MovementMode {
	STATIONARY,
	RANDOM_WANDER,
	PATROL_ROUTE,
	PATROL_LOOP,
	PATROL_PINGPONG
}

@export_group("NPC Info")
@export var npc_name: String = "Villager"
@export var npc_id: String = "npc_001"

@export_group("Sprite Setup")
@export var sprite_texture: Texture2D:
	set(value):
		sprite_texture = value
		if _sprite:
			_sprite.texture = value
@export var sprite_hframes: int = 4
@export var sprite_vframes: int = 4

@export_group("Animation Frames (4 Richtungen)")
@export var frames_down: Array[int] = [2, 3, 5, 6]
@export var frames_up: Array[int] = [11,12, 14, 15]
@export var frames_left: Array[int] = [16, 26, 17, 25]
@export var anim_fps: float = 4.0

@export_group("Idle Frames (je Richtung)")
@export var idle_frame_down: int = 0
@export var idle_frame_up: int = 9
@export var idle_frame_left: int = 18
@export var idle_frame_right: int = 18

@export_group("Movement")
@export var movement_mode: MovementMode = MovementMode.STATIONARY
@export var move_speed: float = 1.0
@export var gravity: float = 30.0
@export var wander_radius: float = 5.0
@export var wait_time_min: float = 2.0
@export var wait_time_max: float = 5.0
@export var patrol_points: Array[Marker3D] = []

@export_group("Wander Variation")
@export var wander_direction_changes_min: int = 0
@export var wander_direction_changes_max: int = 2
@export var wander_segment_length_min: float = 1.5
@export var wander_segment_length_max: float = 3.0

@export_group("Interaction")
@export var interaction_radius: float = 2.0
@export var dialogue_resource: DialogueData = null

@export_group("Collision Handling")
@export var stuck_detection_time: float = 0.5
@export var min_progress_distance: float = 0.1

@export_group("Freeze/Performance")
@export var freeze_distance: float = 25.0
@export var unfreeze_distance: float = 25.0

@export_group("Editor Visualization")
@export var show_wander_area: bool = true:
	set(value):
		show_wander_area = value
		_update_editor_visualization()

@onready var _sprite: Sprite3D = $Sprite3D
@onready var _interaction_area: Area3D = $InteractionArea
@onready var _dialogue_marker: Marker3D = $DialogueMarker

var _start_position: Vector3 = Vector3.ZERO
var _target_position: Vector3 = Vector3.ZERO
var _is_moving: bool = false
var _wait_timer: float = 0.0
var _current_patrol_index: int = 0
var _patrol_direction: int = 1
var _anim_time: float = 0.0

var _player_in_range: bool = false
var _is_in_dialogue: bool = false

var _wander_waypoints: Array[Vector3] = []
var _current_waypoint_index: int = 0

enum FacingDirection { DOWN, UP, LEFT, RIGHT }
var _current_facing: FacingDirection = FacingDirection.DOWN

var _wander_mesh: MeshInstance3D = null

# Stuck Detection
var _last_position: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0

# Freeze System
var _is_frozen: bool = false
var _player_ref: Node3D = null


func _ready() -> void:
	_start_position = global_position
	_last_position = global_position
	
	if Engine.is_editor_hint():
		_update_editor_visualization()
		return
	
	add_to_group("npc")
	
	_player_ref = get_tree().get_first_node_in_group("player")
	
	if _sprite and sprite_texture:
		_sprite.texture = sprite_texture
		_sprite.hframes = sprite_hframes
		_sprite.vframes = sprite_vframes
		_set_idle_frame()
	
	if _interaction_area:
		var collision: CollisionShape3D = _interaction_area.get_node_or_null("CollisionShape3D")
		if collision:
			# Immer eine neue SphereShape mit dem richtigen Radius erstellen
			var sphere := SphereShape3D.new()
			sphere.radius = interaction_radius
			collision.shape = sphere
		
		# Collision Settings
		_interaction_area.collision_layer = 0  # Area braucht keinen eigenen Layer
		_interaction_area.collision_mask = 1   # Player auf Layer 1 erkennen
		_interaction_area.monitoring = true
		_interaction_area.monitorable = false
		
		_interaction_area.body_entered.connect(_on_body_entered)
		_interaction_area.body_exited.connect(_on_body_exited)
	
	_wait_timer = randf_range(wait_time_min, wait_time_max)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_check_freeze_state()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if _is_in_dialogue:
		_face_player()
		return
	
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	
	# Fall-Reset
	if global_position.y < _start_position.y - 5.0:
		global_position = _start_position
		global_position.y += 1.5
		velocity = Vector3.ZERO
		return
	
	if _is_in_dialogue:
		_face_player()
		move_and_slide()
		return
	
	match movement_mode:
		MovementMode.STATIONARY:
			_process_stationary()
		MovementMode.RANDOM_WANDER:
			_process_wander(delta)
		MovementMode.PATROL_ROUTE, MovementMode.PATROL_LOOP, MovementMode.PATROL_PINGPONG:
			_process_patrol(delta)
	
	move_and_slide()


# ============ FREEZE SYSTEM ============

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
	set_physics_process(false)


func _unfreeze() -> void:
	if not _is_frozen:
		return
	
	_is_frozen = false
	
	# Leicht anheben, Gravity macht den Rest
	global_position.y = _start_position.y + 1.5
	velocity = Vector3.ZERO
	
	set_physics_process(true)


# ============ MOVEMENT PROCESSING ============

func _process_stationary() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_set_idle_frame()


func _process_wander(delta: float) -> void:
	if _is_moving:
		_move_along_waypoints(delta)
	else:
		_set_idle_frame()
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_generate_wander_path()


func _process_patrol(delta: float) -> void:
	if patrol_points.is_empty():
		return
	
	if _is_moving:
		_move_to_target(delta)
	else:
		_set_idle_frame()
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_pick_next_patrol_point()


func _generate_wander_path() -> void:
	_wander_waypoints.clear()
	_current_waypoint_index = 0
	
	var angle: float = randf() * TAU
	var distance: float = randf_range(wander_radius * 0.3, wander_radius)
	var final_target: Vector3 = _start_position + Vector3(
		cos(angle) * distance,
		0,
		sin(angle) * distance
	)
	
	var direction_changes: int = randi_range(wander_direction_changes_min, wander_direction_changes_max)
	
	if direction_changes == 0:
		_wander_waypoints.append(final_target)
	else:
		var current_pos: Vector3 = global_position
		
		for i in range(direction_changes):
			var to_target: Vector3 = (final_target - current_pos).normalized()
			var random_offset: float = randf_range(-PI * 0.6, PI * 0.6)
			var segment_angle: float = atan2(to_target.z, to_target.x) + random_offset
			
			var segment_length: float = randf_range(wander_segment_length_min, wander_segment_length_max)
			
			var waypoint: Vector3 = current_pos + Vector3(
				cos(segment_angle) * segment_length,
				0,
				sin(segment_angle) * segment_length
			)
			
			var from_start: Vector3 = waypoint - _start_position
			if from_start.length() > wander_radius:
				from_start = from_start.normalized() * wander_radius * 0.9
				waypoint = _start_position + from_start
			
			_wander_waypoints.append(waypoint)
			current_pos = waypoint
		
		_wander_waypoints.append(final_target)
	
	_is_moving = true
	_reset_stuck_detection()


func _move_along_waypoints(delta: float) -> void:
	if _current_waypoint_index >= _wander_waypoints.size():
		_is_moving = false
		_wait_timer = randf_range(wait_time_min, wait_time_max)
		velocity.x = 0.0
		velocity.z = 0.0
		return
	
	_target_position = _wander_waypoints[_current_waypoint_index]
	
	var direction: Vector3 = (_target_position - global_position)
	direction.y = 0
	var distance: float = direction.length()
	
	if distance < 0.15:
		_current_waypoint_index += 1
		return
	
	direction = direction.normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	
	_update_facing_from_direction(direction)
	_play_walk_animation(delta)
	
	if _check_if_stuck(delta):
		_abort_current_movement()


func _move_to_target(delta: float) -> void:
	var direction: Vector3 = (_target_position - global_position)
	direction.y = 0
	var distance: float = direction.length()
	
	if distance < 0.1:
		_is_moving = false
		_wait_timer = randf_range(wait_time_min, wait_time_max)
		velocity.x = 0.0
		velocity.z = 0.0
		return
	
	direction = direction.normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	
	_update_facing_from_direction(direction)
	_play_walk_animation(delta)
	
	if _check_if_stuck(delta):
		_abort_current_movement()


# ============ STUCK DETECTION ============

func _check_if_stuck(delta: float) -> bool:
	var intended_speed := Vector2(velocity.x, velocity.z).length()
	if intended_speed < 0.1:
		_stuck_timer = 0.0
		return false
	
	var actual_movement := Vector2(
		global_position.x - _last_position.x,
		global_position.z - _last_position.z
	).length()
	
	_last_position = global_position
	
	var expected := intended_speed * delta
	var ratio := actual_movement / maxf(expected, 0.001)
	
	if ratio < 0.3:
		_stuck_timer += delta
		if _stuck_timer >= stuck_detection_time:
			return true
	else:
		_stuck_timer = 0.0
	
	return false


func _reset_stuck_detection() -> void:
	_stuck_timer = 0.0
	_last_position = global_position


func _abort_current_movement() -> void:
	_is_moving = false
	_wander_waypoints.clear()
	_current_waypoint_index = 0
	velocity.x = 0.0
	velocity.z = 0.0
	_wait_timer = randf_range(wait_time_min, wait_time_max)
	_set_idle_frame()
	_reset_stuck_detection()


# ============ DIRECTION & ANIMATION ============

func _update_facing_from_direction(direction: Vector3) -> void:
	if abs(direction.x) > abs(direction.z):
		if direction.x > 0:
			_current_facing = FacingDirection.RIGHT
			_sprite.flip_h = true
		else:
			_current_facing = FacingDirection.LEFT
			_sprite.flip_h = false
	else:
		_sprite.flip_h = false
		if direction.z > 0:
			_current_facing = FacingDirection.DOWN
		else:
			_current_facing = FacingDirection.UP


func _get_frames_for_facing() -> Array[int]:
	match _current_facing:
		FacingDirection.DOWN:
			return frames_down
		FacingDirection.UP:
			return frames_up
		FacingDirection.LEFT, FacingDirection.RIGHT:
			return frames_left
	return frames_down


func _get_idle_frame_for_facing() -> int:
	match _current_facing:
		FacingDirection.DOWN:
			return idle_frame_down
		FacingDirection.UP:
			return idle_frame_up
		FacingDirection.LEFT:
			return idle_frame_left
		FacingDirection.RIGHT:
			return idle_frame_right
	return idle_frame_down


func _play_walk_animation(delta: float) -> void:
	if _sprite == null:
		return
	
	var frames: Array[int] = _get_frames_for_facing()
	if frames.is_empty():
		return
	
	_anim_time += delta
	var frame_count: int = frames.size()
	var frame_index: int = int(_anim_time * anim_fps) % frame_count
	_sprite.frame = frames[frame_index]


func _set_idle_frame() -> void:
	if _sprite == null:
		return
	
	_sprite.frame = _get_idle_frame_for_facing()
	
	if _current_facing == FacingDirection.RIGHT:
		_sprite.flip_h = true
	elif _current_facing == FacingDirection.LEFT:
		_sprite.flip_h = false
	
	_anim_time = 0.0


func _face_player() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if player and _sprite:
		var dir: Vector3 = player.global_position - global_position
		_update_facing_from_direction(dir)
		_set_idle_frame()


func _pick_next_patrol_point() -> void:
	if patrol_points.is_empty():
		return
	
	match movement_mode:
		MovementMode.PATROL_ROUTE:
			_current_patrol_index += 1
			if _current_patrol_index >= patrol_points.size():
				_current_patrol_index = 0
				_is_moving = false
				return
		
		MovementMode.PATROL_LOOP:
			_current_patrol_index = (_current_patrol_index + 1) % patrol_points.size()
		
		MovementMode.PATROL_PINGPONG:
			_current_patrol_index += _patrol_direction
			if _current_patrol_index >= patrol_points.size() - 1:
				_patrol_direction = -1
			elif _current_patrol_index <= 0:
				_patrol_direction = 1
	
	var target_marker: Marker3D = patrol_points[_current_patrol_index]
	if target_marker:
		_target_position = target_marker.global_position
		_is_moving = true
		_reset_stuck_detection()


# ============ INTERACTION ============

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		print("Player entered NPC range: ", npc_name)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		print("Player exited NPC range: ", npc_name)
		
func can_interact() -> bool:
	if not _player_in_range:
		return false
	
	if _is_in_dialogue:
		return false
	
	# DialogueManager Cooldown prüfen
	var dialogue_manager: Node = get_node_or_null("/root/DialogueManager")
	if dialogue_manager and dialogue_manager.is_on_cooldown():
		return false
	
	return true

func interact() -> bool:
	"""Wird vom Player aufgerufen. Gibt true zurück wenn Interaktion stattfand."""
	print("NPC.interact() called - can_interact: ", can_interact())
	if not can_interact():
		return false
	
	start_dialogue()
	return true



func start_dialogue() -> void:
	if _is_in_dialogue:
		return
	
	print("Starting dialogue with: ", npc_name)
	print("Dialogue resource: ", dialogue_resource)
	
	_is_in_dialogue = true
	_is_moving = false
	velocity = Vector3.ZERO
	
	dialogue_started.emit(self)
	
	var dialogue_manager: Node = get_node_or_null("/root/DialogueManager")
	if dialogue_manager:
		dialogue_manager.start_dialogue(self, dialogue_resource)
	else:
		push_error("DialogueManager not found!")
		end_dialogue()


func end_dialogue() -> void:
	_is_in_dialogue = false
	dialogue_ended.emit(self)
	print("Dialogue ended with: ", npc_name)
	
func get_dialogue_position() -> Vector3:
	if _dialogue_marker:
		return _dialogue_marker.global_position
	return global_position + Vector3(0, 1.5, 0)


# ============ EDITOR ============

func _update_editor_visualization() -> void:
	if not Engine.is_editor_hint():
		return
	
	if show_wander_area and movement_mode == MovementMode.RANDOM_WANDER:
		if _wander_mesh == null:
			_wander_mesh = MeshInstance3D.new()
			add_child(_wander_mesh)
		
		var cylinder: CylinderMesh = CylinderMesh.new()
		cylinder.top_radius = wander_radius
		cylinder.bottom_radius = wander_radius
		cylinder.height = 0.1
		_wander_mesh.mesh = cylinder
		
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.6, 1.0, 0.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wander_mesh.material_override = mat
	elif _wander_mesh:
		_wander_mesh.queue_free()
		_wander_mesh = null
		
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	
	if movement_mode in [MovementMode.PATROL_ROUTE, MovementMode.PATROL_LOOP, MovementMode.PATROL_PINGPONG]:
		if patrol_points.is_empty():
			warnings.append("Patrol mode benötigt mindestens einen Patrol Point!")
	
	if dialogue_resource == null:
		warnings.append("Kein Dialogue Resource zugewiesen!")
	
	return warnings

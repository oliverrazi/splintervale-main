extends CharacterBody3D
class_name Enemy

## Basisklasse für alle Gegner

# === HEALTH ===
@export_group("Health")
@export var max_health: int = 30
@export var knockback_strength: float = 0.5
@export var hit_flash_duration: float = 0.15
@export var invincibility_duration: float = 0.2

# === DETECTION & FREEZE ===
@export_group("Detection")
@export var detection_range: float = 5.0
@export var lose_interest_range: float = 12.0
@export var freeze_distance: float = 17.0
@export var unfreeze_distance: float = 17.0

# === PATROL ===
@export_group("Patrol")
@export var patrol_radius: float = 3.0
@export var patrol_wait_time_min: float = 1.0
@export var patrol_wait_time_max: float = 3.0

# === STUCK DETECTION ===
@export_group("Stuck Detection")
@export var stuck_detection_time: float = 0.4
@export var stuck_min_movement: float = 0.05

# === CLIFF AVOIDANCE ===
@export_group("Cliff Avoidance")
@export var avoid_cliffs: bool = false
@export var cliff_check_distance: float = 0.4   # wie weit vor den Füßen geprüft wird
@export var cliff_max_drop: float = 1.0         # maximal akzeptable Fallhöhe
@export var cliff_check_height: float = 0.3     # Ray-Start über den Füßen

# === REWARDS ===
@export_group("Rewards")
@export var exp_reward: int = 25
@export var gold_reward_min: int = 5
@export var gold_reward_max: int = 15
@export var reward_popup_scene: PackedScene
@export var reward_popup_offset: Vector3 = Vector3(0, 0.5, 0)

# === HP BAR ===
@export_group("HP Bar")
@export var hp_bar_scene: PackedScene
@export var hp_bar_offset: Vector3 = Vector3(0, 0.45, 0)
@export var hp_bar_show_duration: float = 3.0
@export var hp_bar_always_visible: bool = false

# === ALERT ===
@export_group("Alert")
@export var alert_popup_scene: PackedScene
@export var alert_offset: Vector3 = Vector3(0, 0.3, 0)
@export var alert_duration: float = 0.8
@export var alert_sound: AudioStream

# === CONFUSION ===
@export_group("Confusion")
@export var can_be_confused: bool = true
@export var confusion_popup_scene: PackedScene
@export var confusion_popup_offset: Vector3 = Vector3(0, 0.4, 0)

# === DEATH ===
@export_group("Death")
@export var death_frames: Array[int] = []
@export var death_fps: float = 8.0
@export var death_hold_time: float = 0.5
@export var death_dissolve_time: float = 0.5
@export var death_vfx_scene: PackedScene
@export var death_vfx_offset: Vector3 = Vector3(0, 0, 0)
@export var death_vfx_scale: float = 1.0
@export var death_vfx_lifetime: float = 2.0
@export var death_sound: AudioStream

@export_group("Drowning")
@export var drown_duration: float = 0.7
@export var drown_flip_interval: float = 0.1
@export var splash_vfx_scene: PackedScene

var _is_drowning: bool = false
var _drown_timer: float = 0.0
var _drown_flip_timer: float = 0.0
var _drown_flip_state: bool = false

@export_group("Instant Death")
@export var fall_death_y_offset: float = 8.0
@export var instant_death_vfx_scene: PackedScene  # optional, z. B. Splash
@export var instant_death_vfx_offset: Vector3 = Vector3.ZERO

# === HURT ===
@export_group("Hurt")
@export var hurt_sound: AudioStream
@export var hurt_pitch_variation: float = 0.1

# === SPRITE ===
@export_group("Sprite")
@export var HFRAMES: int = 10
@export var VFRAMES: int = 10

# === INTERNAL STATE ===
var _health: int
var _spawn_position: Vector3
var _target: Node3D = null
var _player_ref: Node3D = null
var _is_frozen: bool = false
var _is_dead: bool = false
var _is_invincible: bool = false
var _invincibility_timer: float = 0.0

# === CONFUSION STATE ===
var _is_confused: bool = false
var _confusion_timer: float = 0.0
var _confusion_popup: Node3D = null

# Knockback
var _knockback_velocity: Vector3 = Vector3.ZERO
var _hit_timer: float = 0.0

# Animation
var _anim_time: float = 0.0

# Components
var _hp_bar: Node = null
var _hp_bar_timer: float = 0.0
var _audio_player: AudioStreamPlayer3D = null
var sprite: SmoothPixelSprite3D  = null

# Death
var _death_phase: int = 0
var _death_timer: float = 0.0
var _rewards_given: bool = false

# Stuck Detection
var _last_position_check: Vector3 = Vector3.ZERO
var _stuck_timer: float = 0.0

# Physics
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


# === VIRTUAL METHODS (Override in Subclass) ===

func _on_ready_after_terrain() -> void:
	pass

func _process_ai(_delta: float) -> void:
	pass

func _on_damage_received(_amount: int, _from_position: Vector3) -> void:
	pass

func _on_death() -> void:
	pass
	
func _on_drown_started() -> void:
	pass

func _on_death_finished() -> void:
	pass

func _on_confusion_started() -> void:
	pass

func _on_confusion_ended() -> void:
	pass

func _get_hurt_frame() -> Dictionary:
	return {frame = 0, flip = false}

func _get_drown_frame() -> int:
	return _get_hurt_frame().frame

func _get_death_frames() -> Array[int]:
	return death_frames

func _get_death_fps() -> float:
	return death_fps

func _process_death_custom(_delta: float) -> bool:
	return false


# === LIFECYCLE ===

func _ready() -> void:
	_health = max_health
	_spawn_position = global_position
	
	_player_ref = get_tree().get_first_node_in_group("player")
	
	sprite = _find_sprite()
	if sprite:
		sprite.hframes = HFRAMES
		sprite.vframes = VFRAMES
	
	_setup_audio_player()
	_setup_hp_bar()
	
	add_to_group("enemies")
	
	_await_terrain_ready()


func _find_sprite() -> SmoothPixelSprite3D:
	var found := get_node_or_null("MeshInstance3D")
	if found is SmoothPixelSprite3D:
		return found
	
	for child in get_children():
		if child is SmoothPixelSprite3D:
			return child
	
	for child in get_children():
		if child is MeshInstance3D and child.has_method("_set_frame"):
			return child as SmoothPixelSprite3D
	
	push_warning("%s: Kein SmoothPixelSprite3D gefunden!" % name)
	return null


func _setup_audio_player() -> void:
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.name = "AudioPlayer"
	_audio_player.max_distance = 20.0
	_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_audio_player)


func _await_terrain_ready() -> void:
	set_physics_process(false)
	_is_frozen = true
	velocity = Vector3.ZERO
	
	await get_tree().process_frame
	_on_ready_after_terrain()


func _process(delta: float) -> void:
	_check_freeze_state()
	_update_hp_bar_timer(delta)
	_update_confusion(delta)


func _update_hp_bar_timer(delta: float) -> void:
	if _hp_bar == null or hp_bar_always_visible:
		return
	
	if _hp_bar_timer > 0.0:
		_hp_bar_timer -= delta
		if _hp_bar_timer <= 0.0:
			_hp_bar.visible = false


func _physics_process(delta: float) -> void:
	if _is_drowning:
		_process_drowning(delta)
		return
	
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	if not is_inside_tree() or get_world_3d() == null:
		return
	
	#if global_position.y < _spawn_position.y - 8.0:
	#	global_position = _spawn_position
	#	velocity = Vector3.ZERO
	#	return
	if global_position.y < _spawn_position.y - fall_death_y_offset:
		kill_instantly()
		return
	
	
	if _is_dead:
		_process_death(delta)
		return
	
	if _is_invincible:
		_invincibility_timer -= delta
		if _invincibility_timer <= 0.0:
			_is_invincible = false
	
	if _is_confused:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	
	_process_ai(delta)
	move_and_slide()


# === CONFUSION SYSTEM ===

func apply_confusion(duration: float) -> void:
	if not can_be_confused or _is_dead:
		return
	
	_is_confused = true
	_confusion_timer = duration
	
	_spawn_confusion_popup()
	_on_confusion_started()


func _update_confusion(delta: float) -> void:
	if not _is_confused:
		return
	
	_confusion_timer -= delta
	
	if _confusion_timer <= 0.0:
		_end_confusion()


func _end_confusion() -> void:
	_is_confused = false
	_confusion_timer = 0.0
	_remove_confusion_popup()
	_on_confusion_ended()


func _spawn_confusion_popup() -> void:
	_remove_confusion_popup()
	
	if confusion_popup_scene != null:
		_confusion_popup = confusion_popup_scene.instantiate() as Node3D
		add_child(_confusion_popup)
		_confusion_popup.position = confusion_popup_offset
	else:
		# Default: Einfaches Fragezeichen
		_confusion_popup = Node3D.new()
		_confusion_popup.name = "ConfusionPopup"
		
		var label := Label3D.new()
		label.text = "?"
		label.font_size = 48
		label.modulate = Color(1.0, 1.0, 0.3, 1.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.render_priority = 10
		
		_confusion_popup.add_child(label)
		add_child(_confusion_popup)
		_confusion_popup.position = confusion_popup_offset
		
		var tween := create_tween()
		tween.set_loops(0)
		tween.tween_property(_confusion_popup, "position:y", confusion_popup_offset.y + 0.1, 0.3)
		tween.tween_property(_confusion_popup, "position:y", confusion_popup_offset.y, 0.3)


func _remove_confusion_popup() -> void:
	if _confusion_popup and is_instance_valid(_confusion_popup):
		_confusion_popup.queue_free()
		_confusion_popup = null


func is_confused() -> bool:
	return _is_confused


# === FREEZE SYSTEM ===

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
	velocity = Vector3.ZERO
	set_physics_process(true)


# === HEALTH SYSTEM ===

func take_damage(amount: int, from_position: Vector3, skip_hitstop: bool = false) -> void:
	if _is_dead or _is_invincible:
		return
	
	if _is_confused:
		_end_confusion()
	
	_health -= amount
	_anim_time = 0.0
	
	_is_invincible = true
	_invincibility_timer = invincibility_duration
	
	_show_hp_bar()
	
	var knockback_dir := (global_position - from_position).normalized()
	knockback_dir.y = 0
	_knockback_velocity = knockback_dir * knockback_strength
	
	_play_sound(hurt_sound, hurt_pitch_variation)
	
	# Gemeinsame Effekte: Hitstop + Shake — kann pro Aufruf unterdrückt werden
	if not skip_hitstop and GameEffects:
		GameEffects.hit_effect()
	
	# Subclass-Hook: Facing, Target-Set, Group-Alert, State-Übergang etc.
	_on_damage_received(amount, from_position)
	
	if _health <= 0:
		_die()


func heal(amount: int) -> void:
	_health = mini(_health + amount, max_health)
	_show_hp_bar()


func _die() -> void:
	if _is_dead:
		return
	
	if _is_confused:
		_end_confusion()
	
	_is_dead = true
	velocity = Vector3.ZERO
	_anim_time = 0.0
	_death_phase = 0
	_death_timer = 0.0
	_rewards_given = false
	
	_hp_bar_visible(false)
	
	_play_sound(death_sound)
	
	_on_death()
	
func kill_instantly() -> void:
	if _is_dead:
		return

	_is_dead = true
	velocity = Vector3.ZERO
	_hp_bar_visible(false)

	if _is_confused:
		_end_confusion()

	# Subclass-Cleanup (VFX, Tongue, Thrust etc.)
	_on_death()

	# Rewards (EXP, Gold, Popup)
	_give_rewards()

	# Optional: Splash/Poof-VFX
	if instant_death_vfx_scene != null:
		var vfx := instant_death_vfx_scene.instantiate() as Node3D
		get_tree().current_scene.add_child(vfx)
		vfx.global_position = global_position + instant_death_vfx_offset
		for child in vfx.get_children():
			if child is GPUParticles3D:
				child.emitting = true
		get_tree().create_timer(death_vfx_lifetime).timeout.connect(vfx.queue_free)

	_on_death_finished()
	queue_free()


func _process_death(delta: float) -> void:
	if _process_death_custom(delta):
		return
	
	var frames := _get_death_frames()
	var fps := _get_death_fps()
	
	if frames.is_empty():
		_finish_death()
		return
	
	match _death_phase:
		0:
			_anim_time += delta
			var frame_duration := 1.0 / fps
			var frame_idx := int(_anim_time / frame_duration)
			
			if frame_idx >= frames.size():
				_death_phase = 1
				_death_timer = death_hold_time
				sprite.frame = frames[frames.size() - 1]
			else:
				sprite.frame = frames[frame_idx]
			
			var data := _get_hurt_frame()
			sprite.flip_h = data.flip
			sprite.modulate = Color.WHITE
		
		1:
			_death_timer -= delta
			if _death_timer <= 0.0:
				_give_rewards()
				_spawn_death_vfx()
				_death_phase = 2
				_death_timer = death_dissolve_time
		
		2:
			_death_timer -= delta
			var progress := 1.0 - (_death_timer / maxf(death_dissolve_time, 0.01))
			progress = clampf(progress, 0.0, 1.0)
			sprite.modulate.a = 1.0 - progress
			
			if _death_timer <= 0.0:
				_finish_death()


func _finish_death() -> void:
	if not _rewards_given:
		_give_rewards()
	_on_death_finished()
	queue_free()

func start_drowning() -> void:
	if _is_dead or _is_drowning:
		return

	_is_drowning = true
	_drown_timer = drown_duration
	_drown_flip_timer = 0.0
	_drown_flip_state = false
	velocity = Vector3.ZERO

	_hp_bar_visible(false)

	sprite.frame = _get_drown_frame()
	sprite.flip_h = false  # wird von _process_drowning gespiegelt
	sprite.modulate = Color.WHITE
	sprite.modulate.a = 1.0

	# Subclass-Cleanup (Goblin: Thrust-VFX entfernen)
	_on_drown_started()

	_spawn_splash_vfx()


func _process_drowning(delta: float) -> void:
	_drown_timer -= delta

	_drown_flip_timer -= delta
	if _drown_flip_timer <= 0.0:
		_drown_flip_state = not _drown_flip_state
		sprite.flip_h = _drown_flip_state
		_drown_flip_timer = drown_flip_interval

	if _drown_timer <= 0.0:
		_is_drowning = false
		kill_instantly()

func _spawn_splash_vfx() -> void:
	if splash_vfx_scene == null:
		return
	var splash := splash_vfx_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(splash)
	splash.global_position = global_position
	for child in splash.get_children():
		if child is GPUParticles3D:
			child.emitting = true
	get_tree().create_timer(2.0).timeout.connect(splash.queue_free)


func _give_rewards() -> void:
	if _rewards_given:
		return
	_rewards_given = true
	
	if GameManager and GameManager.player_data:
		GameManager.player_data.add_exp(exp_reward)
		var gold_amount := randi_range(gold_reward_min, gold_reward_max)
		GameManager.player_data.add_gold(gold_amount)
		_spawn_reward_popup(exp_reward, gold_amount)


func _spawn_reward_popup(exp_amount: int, _gold_amount: int) -> void:
	if reward_popup_scene == null:
		return
	
	var popup := reward_popup_scene.instantiate()
	get_tree().current_scene.add_child(popup)
	popup.global_position = global_position + reward_popup_offset
	
	if popup.has_method("setup_exp"):
		popup.setup_exp(exp_amount)


# === HP BAR ===

func _setup_hp_bar() -> void:
	if hp_bar_scene == null:
		return
	
	_hp_bar = hp_bar_scene.instantiate()
	add_child(_hp_bar)
	
	if _hp_bar is Node3D:
		_hp_bar.position = hp_bar_offset
	elif _hp_bar is Node2D or _hp_bar is Control:
		_hp_bar.position = Vector2(hp_bar_offset.x, hp_bar_offset.y)
	
	if _hp_bar.has_method("set_health"):
		_hp_bar.set_health(_health, max_health)
	
	_hp_bar.visible = hp_bar_always_visible
	_hp_bar_timer = 0.0


func _hp_bar_visible(visible: bool) -> void:
	if _hp_bar != null:
		_hp_bar.visible = visible


func _show_hp_bar() -> void:
	if _hp_bar == null:
		return
	
	if _hp_bar.has_method("set_health"):
		_hp_bar.set_health(_health, max_health)


# === ALERT POPUP ===

func spawn_alert_popup() -> void:
	if alert_popup_scene == null:
		return
	
	var popup := alert_popup_scene.instantiate()
	add_child(popup)
	
	if popup is Node3D:
		popup.position = alert_offset
	elif popup is Node2D or popup is Control:
		popup.position = Vector2(alert_offset.x, alert_offset.y)
	
	_play_sound(alert_sound)


# === DEATH VFX ===

func _spawn_death_vfx() -> void:
	if death_vfx_scene == null:
		return
	
	var vfx := death_vfx_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = global_position + death_vfx_offset
	vfx.scale = Vector3.ONE * death_vfx_scale
	
	for child in vfx.get_children():
		if child is GPUParticles3D:
			child.emitting = true
	
	get_tree().create_timer(death_vfx_lifetime).timeout.connect(vfx.queue_free)


# === STUCK DETECTION ===

func _check_if_stuck(delta: float) -> bool:
	var intended_speed := Vector2(velocity.x, velocity.z).length()
	if intended_speed < 0.1:
		_stuck_timer = 0.0
		return false
	
	var actual_movement := Vector2(
		global_position.x - _last_position_check.x,
		global_position.z - _last_position_check.z
	).length()
	
	_last_position_check = global_position
	
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
	_last_position_check = global_position


# === PATROL HELPERS ===

func _get_random_patrol_point() -> Vector3:
	var angle := randf() * TAU
	var dist := randf_range(patrol_radius * 0.3, patrol_radius)
	var offset := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	return _spawn_position + offset


# === CLIFF DETECTION ===

## Prüft, ob in der gegebenen Richtung ein Abgrund ist.
## Gibt false zurück wenn avoid_cliffs deaktiviert ist.
func _is_cliff_ahead(direction: Vector3, distance: float = -1.0) -> bool:
	if not avoid_cliffs:
		return false
	if direction.length_squared() < 0.0001:
		return false

	var check_dist: float = distance if distance > 0.0 else cliff_check_distance
	var dir_flat := Vector3(direction.x, 0, direction.z).normalized()

	var space_state := get_world_3d().direct_space_state
	var origin := global_position + dir_flat * check_dist + Vector3.UP * cliff_check_height
	var end := origin + Vector3.DOWN * (cliff_check_height + cliff_max_drop)

	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [self]

	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()  # kein Boden = Abgrund


## Sucht eine sichere Richtung in der Nähe der gewünschten.
## Gibt Vector3.ZERO zurück, wenn keine sichere Richtung gefunden wurde.
func _find_safe_direction(intended_dir: Vector3) -> Vector3:
	if not avoid_cliffs:
		return intended_dir

	var dir_flat := Vector3(intended_dir.x, 0, intended_dir.z).normalized()

	if not _is_cliff_ahead(dir_flat):
		return dir_flat

	# Probier zunehmend stärkere Abweichungen, jeweils nach links und rechts
	var angles: Array[float] = [25.0, -25.0, 50.0, -50.0, 80.0, -80.0]
	for angle_deg in angles:
		var rotated := dir_flat.rotated(Vector3.UP, deg_to_rad(angle_deg))
		if not _is_cliff_ahead(rotated):
			return rotated

	return Vector3.ZERO  # umzingelt von Abgründen

# === AUDIO ===

func _play_sound(sound: AudioStream, pitch_variation: float = 0.0) -> void:
	if sound == null or _audio_player == null:
		return
	
	_audio_player.stream = sound
	_audio_player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	_audio_player.play()


# === HIT FLASH ===

func apply_hit_flash() -> void:
	if sprite == null:
		return
	var flash := fmod(_anim_time, hit_flash_duration * 2.0) < hit_flash_duration
	sprite.modulate = Color(1.5, 0.5, 0.5) if flash else Color.WHITE


func clear_hit_flash() -> void:
	if sprite == null:
		return
	sprite.modulate = Color.WHITE


# === GETTERS ===

func get_health() -> int:
	return _health

func get_health_percent() -> float:
	return float(_health) / float(max_health)

func is_alive() -> bool:
	return not _is_dead

func is_frozen() -> bool:
	return _is_frozen

func is_invincible() -> bool:
	return _is_invincible

func get_target() -> Node3D:
	return _target

func set_target(new_target: Node3D) -> void:
	_target = new_target

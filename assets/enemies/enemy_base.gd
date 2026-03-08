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

func _on_death_finished() -> void:
	pass

func _get_hurt_frame() -> Dictionary:
	return {frame = 0, flip = false}

func _get_death_frames() -> Array[int]:
	return death_frames

func _get_death_fps() -> float:
	return death_fps

## Custom Death-Animation - überschreiben für eigene Animation
## Return true = Animation läuft noch, false = fertig (dann wird _finish_death aufgerufen)
func _process_death_custom(_delta: float) -> bool:
	return false


# === LIFECYCLE ===

func _ready() -> void:
	_health = max_health
	_spawn_position = global_position
	
	_player_ref = get_tree().get_first_node_in_group("player")
	
	sprite =  _find_sprite()
	if sprite:
		sprite.hframes = HFRAMES
		sprite.vframes = VFRAMES
	
	_setup_audio_player()
	_setup_hp_bar()
	
	add_to_group("enemies")
	
	_await_terrain_ready()

func _find_sprite() -> SmoothPixelSprite3D:
	# Direkt nach Name suchen
	var found := get_node_or_null("MeshInstance3D")
	if found is SmoothPixelSprite3D:
		return found
	
	# Fallback: Erstes SmoothPixelSprite3D-Kind finden
	for child in get_children():
		if child is SmoothPixelSprite3D:
			return child
	
	# Letzter Fallback: Erstes MeshInstance3D mit dem Script
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


func _update_hp_bar_timer(delta: float) -> void:
	if _hp_bar == null or hp_bar_always_visible:
		return
	
	if _hp_bar_timer > 0.0:
		_hp_bar_timer -= delta
		if _hp_bar_timer <= 0.0:
			_hp_bar.visible = false



func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# get_world_3d() Guard gegen null beim Laden
	if not is_inside_tree() or get_world_3d() == null:
		return
	
	if global_position.y < _spawn_position.y - 8.0:
		global_position = _spawn_position
		velocity = Vector3.ZERO
		return
	
	if _is_dead:
		_process_death(delta)
		return
	
	if _is_invincible:
		_invincibility_timer -= delta
		if _invincibility_timer <= 0.0:
			_is_invincible = false
	
	_process_ai(delta)
	move_and_slide()


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
	# Terrain3D hat hier garantiert Collision -> einfach fallen lassen
	set_physics_process(true)


# === HEALTH SYSTEM ===

func take_damage(amount: int, from_position: Vector3) -> void:
	if _is_dead or _is_invincible:
		return
	
	_health -= amount
	_anim_time = 0.0
	
	_is_invincible = true
	_invincibility_timer = invincibility_duration
	
	_show_hp_bar()
	
	var knockback_dir := (global_position - from_position).normalized()
	knockback_dir.y = 0
	_knockback_velocity = knockback_dir * knockback_strength
	
	_play_sound(hurt_sound, hurt_pitch_variation)
	
	_on_damage_received(amount, from_position)
	
	if _health <= 0:
		_die()


func heal(amount: int) -> void:
	_health = mini(_health + amount, max_health)
	_show_hp_bar()


func _die() -> void:
	if _is_dead:
		return
	
	_is_dead = true
	velocity = Vector3.ZERO
	_anim_time = 0.0
	_death_phase = 0
	_death_timer = 0.0
	_rewards_given = false
	
	_hp_bar_visible(false)
	
	_play_sound(death_sound)
	
	_on_death()


func _process_death(delta: float) -> void:
	# Custom animation hat Priorität
	if _process_death_custom(delta):
		return
	
	var frames := _get_death_frames()
	var fps := _get_death_fps()
	
	# Keine Death-Frames? Direkt zum Ende
	if frames.is_empty():
		_finish_death()
		return
	
	match _death_phase:
		0:  # Animation
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
		
		1:  # Hold
			_death_timer -= delta
			if _death_timer <= 0.0:
				_give_rewards()
				_spawn_death_vfx()
				_death_phase = 2
				_death_timer = death_dissolve_time
		
		2:  # Dissolve
			_death_timer -= delta
			var progress := 1.0 - (_death_timer / maxf(death_dissolve_time, 0.01))
			progress = clampf(progress, 0.0, 1.0)
			sprite.modulate.a = 1.0 - progress
			
			if _death_timer <= 0.0:
				_finish_death()


## Wird am Ende der Death-Animation aufgerufen
func _finish_death() -> void:
	if not _rewards_given:
		_give_rewards()
	_on_death_finished()
	queue_free()


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

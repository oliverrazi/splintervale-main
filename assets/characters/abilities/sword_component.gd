## SwordComponent
##
## Verwaltet die komplette Nahkampf-Logik:
## - Combo-System (3-Hit-Kombos, 8 Richtungen)
## - Slash VFX Spawning + Dissolve
## - Impact VFX + Partikel
## - Hit Detection + Damage Dealing
## - Swoosh + Hit Sounds
## - Waffen-Overlay auf dem LayeredPixelSprite3D
##
## Setup im Scene-Tree:
##   Player (CharacterBody3D)
##     └─ SwordComponent (Node + SwordComponent.gd)
##
## Der Player ruft auf:
##   sword.try_attack(dir_mode)    → startet Angriff
##   sword.buffer_combo()          → buffert nächsten Kombo-Hit
##   sword.process_attack(delta)   → Update pro Frame (nur wenn is_attacking)
##   sword.cancel()                → Angriff sofort abbrechen
##   sword.equip_weapon(item_id)   → Waffe wechseln + Overlay updaten

class_name SwordComponent
extends Node

# ─── Signals ───

## Gefeuert wenn ein Angriff startet (für Movement-Logik im Player)
signal attack_started()
## Gefeuert wenn ein Angriff endet
signal attack_ended()

# ─── Exports: VFX ───

@export_group("Slash VFX")
@export var slash_scene: PackedScene
@export var slash_lifetime: float = 0.3
@export var dissolve_duration: float = 0.0
@export var impact_scene: PackedScene
@export var impact_lifetime: float = 0.5
@export var impact_scale: float = 1.0
@export var impact_delay: float = 0.1

@export_group("Sound")
@export var swoosh_sounds: Array[AudioStream] = []
@export var swoosh_volume_db: float = -6.0
@export var swoosh_pitch_variation: float = 0.08
@export var hit_sounds: Array[AudioStream] = []
@export var hit_volume_db: float = -3.0
@export var hit_pitch_variation: float = 0.1

@export_group("Attack Tuning")
@export var ATTACK_FPS: float = 10.0
@export var ATTACK_MOVE_SPEED: float = 1.0
@export var ATTACK_LAST_FRAME_HOLD: float = 0.15
@export var ATTACK_COOLDOWN: float = 0.25
@export var attack_damage: int = 5


@export var synergy_manager_path: NodePath = "../SynergyManager"
var _synergy_manager: SynergyManager = null

# ─── Attack Frame Consts (8 Richtungen × 3 Kombos) ───

# DirMode enum — muss mit Player übereinstimmen
enum DirMode { DOWN, UP, LEFT, RIGHT, DOWN_LEFT, DOWN_RIGHT, UP_LEFT, UP_RIGHT }

const ATTACK_DOWN_1: Array[int] = [27, 29, 29]
const ATTACK_DOWN_2: Array[int] = [30, 32, 32]
const ATTACK_DOWN_3: Array[int] = [27, 29, 29]

const ATTACK_UP_1: Array[int] = [36, 38, 38]
const ATTACK_UP_2: Array[int] = [39, 41, 41]
const ATTACK_UP_3: Array[int] = [36, 38, 38]

const ATTACK_SIDE_1: Array[int] = [45, 47, 47]
const ATTACK_SIDE_2: Array[int] = [48, 50, 50]
const ATTACK_SIDE_3: Array[int] = [45, 47, 47]

const ATTACK_DOWN_LEFT_1: Array[int] = [72, 74, 74]
const ATTACK_DOWN_LEFT_2: Array[int] = [75, 77, 77]
const ATTACK_DOWN_LEFT_3: Array[int] = [72, 74, 74]

const ATTACK_UP_RIGHT_1: Array[int] = [81, 83, 83]
const ATTACK_UP_RIGHT_2: Array[int] = [84, 86, 86]
const ATTACK_UP_RIGHT_3: Array[int] = [81, 83, 83]

const COMBO_SPRITE_FLIP_FRAMES := {}

# ─── Slash Direction Tables ───

const DIR_YAW_DEG := {
	DirMode.RIGHT:      270.0,
	DirMode.DOWN_RIGHT: 225.0,
	DirMode.DOWN:       180.0,
	DirMode.DOWN_LEFT:  135.0,
	DirMode.LEFT:       90.0,
	DirMode.UP_LEFT:    45.0,
	DirMode.UP:         0.0,
	DirMode.UP_RIGHT:   315.0,
}

const COMBO_SWING_OFFSET_DEG := {
	DirMode.UP:         { 0: 10.0, 1: 20.0, 2: 10.0 },
	DirMode.UP_RIGHT:   { 0: -10.0, 1: -20.0, 2: -10.0 },
	DirMode.RIGHT:      { 0: -10.0, 1: -20.0, 2: -10.0 },
	DirMode.DOWN_RIGHT: { 0: -10.0, 1: -20.0, 2: -10.0 },
	DirMode.DOWN:       { 0: 10.0, 1: 0.0, 2: 10.0 },
	DirMode.DOWN_LEFT:  { 0: 10.0, 1: 20.0, 2: 10.0 },
	DirMode.LEFT:       { 0: 10.0, 1: 20.0, 2: 10.0 },
	DirMode.UP_LEFT:    { 0: 10.0, 1: 20.0, 2: 10.0 },
}

const COMBO_MIRRORED := {
	DirMode.UP:         { 0: true, 1: false, 2: true },
	DirMode.UP_RIGHT:   { 0: true, 1: false, 2: true },
	DirMode.RIGHT:      { 0: false, 1: true, 2: false },
	DirMode.DOWN_RIGHT: { 0: false, 1: true, 2: false },
	DirMode.DOWN:       { 0: true, 1: false, 2: true },
	DirMode.DOWN_LEFT:  { 0: true, 1: false, 2: true },
	DirMode.LEFT:       { 0: true, 1: false, 2: true },
	DirMode.UP_LEFT:    { 0: false, 1: true, 2: false },
}

# ─── Runtime State ───

var _is_attacking: bool = false
var _attack_step: int = 0
var _attack_time: float = 0.0
var _attack_can_chain: bool = false
var _attack_buffered: bool = false
var _attack_cooldown_timer: float = 0.0
var _attack_dir_mode: int = DirMode.DOWN
var _buffered_dir_mode: int = -1

var _current_attack_frames: Array[int] = []
var _current_attack_duration: float = 0.0
var _current_attack_base_duration: float = 0.0

var _slash_spawned_this_attack: bool = false
var _slash_spawn_frame: int = 1

var _hit_already: bool = false

var _equipped_weapon_id: String = ""

# ─── References (gesetzt via _ready oder vom Player) ───

var _player: CharacterBody3D
var _character: LayeredPixelSprite3D
var _spring_arm: Node3D


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player == null:
		push_error("SwordComponent: Parent muss ein CharacterBody3D (Player) sein!")
		return
	
	_synergy_manager = get_node_or_null(synergy_manager_path) as SynergyManager
	_character = _player.get_node_or_null("charactersprite") as LayeredPixelSprite3D
	_spring_arm = _player.get_node_or_null("SpringArm3D")
	
	call_deferred("_auto_equip_initial_weapon")

# ─── Public API ───

func is_attacking() -> bool:
	return _is_attacking


func can_attack() -> bool:
	return not _is_attacking and _attack_cooldown_timer <= 0.0


func get_equipped_weapon_id() -> String:
	return _equipped_weapon_id


func get_equipped_weapon_data() -> ItemData:
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager:
		return inv_manager.get_item_data(_equipped_weapon_id)
	return null


## Waffe wechseln + Overlay auf dem Sprite updaten.
func equip_weapon(weapon_id: String) -> void:
	_equipped_weapon_id = weapon_id
	_update_weapon_overlay()


## Versucht einen Angriff zu starten. dir_mode = Player.DirMode
func try_attack(dir_mode: int) -> void:
	if _is_attacking:
		# Kombo buffern
		if _attack_can_chain and _attack_step < 3:
			_attack_buffered = true
			_buffered_dir_mode = dir_mode
		return
	
	if _attack_cooldown_timer > 0.0:
		return
	
	_attack_dir_mode = dir_mode
	_start_attack(1)


## Kombo buffern (wenn bereits am Angreifen)
func buffer_combo(dir_mode: int = -1) -> void:
	if _is_attacking and _attack_can_chain and _attack_step < 3:
		_attack_buffered = true
		if dir_mode >= 0:
			_buffered_dir_mode = dir_mode


## Angriff sofort abbrechen (z.B. bei Knockback)
func cancel() -> void:
	if _is_attacking:
		_end_attack()


## Muss jeden Frame aufgerufen werden (vom Player in _physics_process)
func process_attack(delta: float) -> void:
	
	var speed_mult: float = 1.0
	if GameManager and GameManager.player_data:
		speed_mult = GameManager.player_data.get_attack_speed_multiplier()
		
	var effective_delta: float = delta * speed_mult
	# Cooldown immer ticken
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= effective_delta
		if _attack_cooldown_timer < 0.0:
			_attack_cooldown_timer = 0.0
	
	if not _is_attacking:
		return
	
	_update_attack(effective_delta)


## Gibt die Attack-Bewegungsgeschwindigkeit zurück (für Player-Movement)
func get_attack_velocity() -> Vector3:
	if not _is_attacking:
		return Vector3.ZERO
	
	var attack_dir3d: Vector3 = _get_attack_world_dir()
	if attack_dir3d == Vector3.ZERO or _current_attack_duration <= 0.0:
		return Vector3.ZERO
	
	var t: float = clamp(_attack_time, 0.0, _current_attack_duration)
	var progress: float = t / _current_attack_duration
	var move_factor: float = 1.0 - progress
	move_factor *= move_factor
	var strength: float = ATTACK_MOVE_SPEED * move_factor
	
	return Vector3(attack_dir3d.x * strength, 0.0, attack_dir3d.z * strength)


# ─── Internal: Attack State Machine ───

func _start_attack(step: int) -> void:
	_is_attacking = true
	_attack_step = step
	_attack_time = 0.0
	_attack_can_chain = false
	_attack_buffered = false
	_slash_spawned_this_attack = false

	_current_attack_frames = _get_attack_frames_for(_attack_dir_mode, _attack_step)
	_current_attack_base_duration = _get_attack_base_duration(_current_attack_frames)
	_current_attack_duration = _get_attack_duration(_current_attack_frames)
	
	attack_started.emit()
	

func _end_attack() -> void:
	_is_attacking = false
	_attack_step = 0
	_attack_time = 0.0
	_attack_can_chain = false
	_attack_buffered = false
	_current_attack_frames = []
	_current_attack_duration = 0.0
	_current_attack_base_duration = 0.0
	_attack_cooldown_timer = ATTACK_COOLDOWN
	_slash_spawned_this_attack = false
	
	_buffered_dir_mode = -1 
	attack_ended.emit()


func _update_attack(delta: float) -> void:
	if _current_attack_frames.size() == 0 or _current_attack_duration <= 0.0:
		_end_attack()
		return

	_attack_time += delta

	if _attack_time >= _current_attack_duration:
		if _attack_buffered and _attack_step < 3:
			if _buffered_dir_mode >= 0:           # NEU
				_attack_dir_mode = _buffered_dir_mode
				_buffered_dir_mode = -1
			_start_attack(_attack_step + 1)
			return
		else:
			_end_attack()
			return

	var frame_duration: float = 1.0 / ATTACK_FPS
	var frame_index_in_array: int = 0
	var frames_count: int = _current_attack_frames.size()

	if _attack_time < _current_attack_base_duration:
		frame_index_in_array = int(_attack_time / frame_duration)
		frame_index_in_array = clampi(frame_index_in_array, 0, frames_count - 2)
	else:
		frame_index_in_array = frames_count - 1

	_attack_can_chain = _attack_time >= _current_attack_base_duration

	# Slash VFX spawnen
	if not _slash_spawned_this_attack and frame_index_in_array >= _slash_spawn_frame:
		_slash_spawned_this_attack = true
		var world_pos: Vector3 = _get_slash_spawn_position(_attack_dir_mode)
		_spawn_slash_vfx(_attack_step, _attack_dir_mode, world_pos)
		_play_swoosh_sound(world_pos)

	# Frame auf dem Sprite setzen
	var frame_index: int = _current_attack_frames[frame_index_in_array]
	var use_flip: bool = _is_flipped_direction(_attack_dir_mode)

	var extra_flip: bool = false
	if COMBO_SPRITE_FLIP_FRAMES.has(_attack_step):
		var flip_indices: Array = COMBO_SPRITE_FLIP_FRAMES[_attack_step]
		extra_flip = frame_index_in_array in flip_indices

	_set_character_frame(frame_index, use_flip, extra_flip)


# ─── Internal: Frame Helpers ───

func _set_character_frame(frame_index: int, use_flip: bool, extra_flip: bool) -> void:
	if _character == null:
		return
	var flip: bool = use_flip
	if extra_flip:
		flip = not flip
	_character.flip_h = flip
	_character.frame = frame_index


func _is_flipped_direction(dir_mode: int) -> bool:
	match dir_mode:
		DirMode.RIGHT, DirMode.DOWN_RIGHT, DirMode.UP_LEFT:
			return true
		_:
			return false


func _get_attack_frames_for(dir_mode: int, step: int) -> Array[int]:
	match dir_mode:
		DirMode.DOWN:
			if step == 1: return ATTACK_DOWN_1
			elif step == 2: return ATTACK_DOWN_2
			else: return ATTACK_DOWN_3
		DirMode.UP:
			if step == 1: return ATTACK_UP_1
			elif step == 2: return ATTACK_UP_2
			else: return ATTACK_UP_3
		DirMode.LEFT, DirMode.RIGHT:
			if step == 1: return ATTACK_SIDE_1
			elif step == 2: return ATTACK_SIDE_2
			else: return ATTACK_SIDE_3
		DirMode.DOWN_LEFT, DirMode.DOWN_RIGHT:
			if step == 1: return ATTACK_DOWN_LEFT_1
			elif step == 2: return ATTACK_DOWN_LEFT_2
			else: return ATTACK_DOWN_LEFT_3
		DirMode.UP_LEFT, DirMode.UP_RIGHT:
			if step == 1: return ATTACK_UP_RIGHT_1
			elif step == 2: return ATTACK_UP_RIGHT_2
			else: return ATTACK_UP_RIGHT_3
		_:
			return ATTACK_DOWN_1


func _get_attack_base_duration(frames: Array[int]) -> float:
	var count: int = frames.size()
	if count <= 1:
		return 0.0
	return float(count - 1) * (1.0 / ATTACK_FPS)


func _get_attack_duration(frames: Array[int]) -> float:
	var count: int = frames.size()
	if count == 0:
		return 0.0
	var frame_duration: float = 1.0 / ATTACK_FPS
	return _get_attack_base_duration(frames) + frame_duration + ATTACK_LAST_FRAME_HOLD


func _get_attack_world_dir() -> Vector3:
	var dir2: Vector2 = Vector2.ZERO
	match _attack_dir_mode:
		DirMode.DOWN:       dir2 = Vector2(0.0, 1.0)
		DirMode.UP:         dir2 = Vector2(0.0, -1.0)
		DirMode.LEFT:       dir2 = Vector2(-1.0, 0.0)
		DirMode.RIGHT:      dir2 = Vector2(1.0, 0.0)
		DirMode.DOWN_LEFT:  dir2 = Vector2(-1.0, 1.0).normalized()
		DirMode.DOWN_RIGHT: dir2 = Vector2(1.0, 1.0).normalized()
		DirMode.UP_LEFT:    dir2 = Vector2(-1.0, -1.0).normalized()
		DirMode.UP_RIGHT:   dir2 = Vector2(1.0, -1.0).normalized()

	if dir2 == Vector2.ZERO or _spring_arm == null:
		return Vector3.ZERO
	return (_spring_arm.transform.basis * Vector3(dir2.x, 0, dir2.y)).normalized()


# ─── Internal: Slash VFX ───

func _get_slash_spawn_position(dir_mode: int) -> Vector3:
	var pos: Vector3 = _character.global_position if _character else _player.global_position
	var dist := 0.2
	var diag_dist := dist * 0.707

	match dir_mode:
		DirMode.RIGHT:      pos += Vector3(dist, 0.0, 0.0)
		DirMode.LEFT:       pos += Vector3(-dist, 0.0, 0.0)
		DirMode.UP:         pos += Vector3(0.0, 0.0, -0.2 + dist)
		DirMode.DOWN:       pos += Vector3(0.0, 0.0, 0.3 - dist)
		DirMode.DOWN_RIGHT: pos += Vector3(diag_dist, 0.0, diag_dist)
		DirMode.DOWN_LEFT:  pos += Vector3(-diag_dist, 0.0, diag_dist)
		DirMode.UP_RIGHT:   pos += Vector3(diag_dist, 0.0, -diag_dist)
		DirMode.UP_LEFT:    pos += Vector3(-diag_dist, 0.0, -diag_dist)
	return pos


func _spawn_slash_vfx(combo_index: int, dir_mode: int, world_pos: Vector3) -> void:
	if slash_scene == null:
		return

	var vfx := slash_scene.instantiate() as Node3D
	_player.get_tree().current_scene.add_child(vfx)
	vfx.global_position = world_pos
	vfx.process_mode = Node.PROCESS_MODE_ALWAYS

	var base_yaw: float = DIR_YAW_DEG.get(dir_mode, 180.0)
	var combo_idx: int = combo_index - 1
	var combo_offset: float = COMBO_SWING_OFFSET_DEG.get(dir_mode, {}).get(combo_idx, 0.0)

	var pivot: Node3D = vfx.get_node("Node3D")
	pivot.rotation_degrees.y = base_yaw + combo_offset

	var is_mirrored: bool = COMBO_MIRRORED.get(dir_mode, {}).get(combo_idx, false)
	if is_mirrored:
		pivot.scale.x = -1.0

	# Hitbox
	var hit_area: Area3D = pivot.get_node_or_null("HitArea")
	_hit_already = false

	if hit_area:
		hit_area.set_meta("damage", attack_damage)
		hit_area.set_meta("source_position", _player.global_position)
		hit_area.set_meta("attacker", _player)
		hit_area.body_entered.connect(func(body: Node3D) -> void:
			_on_slash_hit(body, hit_area)
		)

	var anim_player: AnimationPlayer = vfx.get_node("Node3D/AnimationPlayer")
	if anim_player and anim_player.has_animation("slash"):
		anim_player.play("slash")

	_cleanup_vfx(vfx, slash_lifetime)


func _on_slash_hit(body: Node3D, hit_area: Area3D) -> void:
	if body == _player:
		return

	if body.has_method("take_damage") and not body.get("_is_dead"):
		var base_damage: int = hit_area.get_meta("damage", attack_damage)
		var actual_damage: int = GameManager.player_data.get_attack_damage(base_damage)
		var source_pos: Vector3 = hit_area.get_meta("source_position", _player.global_position)

		if _synergy_manager != null:
			var mult: float = _synergy_manager.get_damage_multiplier_for_external_hit()
			print(mult)
			actual_damage = int(round(float(actual_damage) * mult))
		
		if not _hit_already:
			body.take_damage(actual_damage, source_pos)
			_hit_already = true
			
			if _synergy_manager != null:
				_synergy_manager.extend_combo_on_normal_hit()
				
			# Impact-VFX zwischen Spieler und Enemy spawnen
			var impact_pos: Vector3 = (_player.global_position + body.global_position) / 2.0
			impact_pos.y += 0.3
			if body.get("is_armored") == true:
				pass 
			else:
				_spawn_impact_vfx(impact_pos)
			
			# Hit-Sound am Enemy
			_play_hit_sound(body.global_position)


func _spawn_impact_vfx(pos: Vector3) -> void:
	if impact_scene == null:
		return

	var vfx := impact_scene.instantiate() as Node3D
	_player.get_tree().current_scene.add_child(vfx)
	vfx.global_position = pos
	vfx.rotation_degrees.y = randf() * 360.0
	vfx.scale = Vector3(impact_scale, impact_scale, impact_scale)

	if impact_delay > 0.0:
		for child in vfx.get_children():
			if child is GPUParticles3D:
				child.emitting = false
		_player.get_tree().create_timer(impact_delay).timeout.connect(func():
			if is_instance_valid(vfx):
				for child in vfx.get_children():
					if child is GPUParticles3D:
						child.emitting = true
		)
	else:
		for child in vfx.get_children():
			if child is GPUParticles3D:
				child.emitting = true

	_player.get_tree().create_timer(impact_lifetime + impact_delay).timeout.connect(vfx.queue_free)


func _cleanup_vfx(vfx: Node3D, lifetime: float) -> void:
	var mesh: MeshInstance3D = vfx.get_node("Node3D/MeshInstance3D")
	var material: ShaderMaterial = mesh.get_surface_override_material(0)
	if material == null and mesh.mesh:
		material = mesh.mesh.surface_get_material(0)

	if material and dissolve_duration > 0.0:
		var wait_time: float = max(0.0, lifetime - dissolve_duration)
		var tween := create_tween()
		tween.tween_interval(wait_time)
		tween.tween_property(material, "shader_parameter/DissolveValue", 1.0, dissolve_duration)
		tween.tween_callback(vfx.queue_free)
	else:
		_player.get_tree().create_timer(lifetime).timeout.connect(vfx.queue_free)


# ─── Internal: Sound ───

func _play_swoosh_sound(world_pos: Vector3) -> void:
	if swoosh_sounds.is_empty():
		return
	AudioPool.play_3d(
		swoosh_sounds.pick_random(),
		world_pos,
		swoosh_volume_db,
		randf_range(1.0 - swoosh_pitch_variation, 1.0 + swoosh_pitch_variation) if swoosh_pitch_variation > 0.0 else 1.0
	)


func _play_hit_sound(world_pos: Vector3) -> void:
	if hit_sounds.is_empty():
		return
	AudioPool.play_3d(
		hit_sounds.pick_random(),
		world_pos,
		hit_volume_db,
		randf_range(1.0 - hit_pitch_variation, 1.0 + hit_pitch_variation)
	)


func _auto_equip_initial_weapon() -> void:
	var inv: Node = get_node_or_null("/root/InventoryManager")
	if inv == null:
		return
	
	# Erste Waffe in der Hotbar suchen und equippen.
	for slot in range(4):
		var item_id: String = inv.get_hotbar_item(slot)
		if item_id == "":
			continue
		var item_data: ItemData = inv.get_item_data(item_id)
		if item_data == null:
			continue
		if item_data.item_type == ItemData.ItemType.WEAPON:
			equip_weapon(item_id)
			return

# ─── Internal: Weapon Overlay ───

func _update_weapon_overlay() -> void:
	if _character == null:
		return

	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		return

	var item_data: ItemData = inv_manager.get_item_data(_equipped_weapon_id)
	if item_data and item_data.get("overlay_texture") != null:
		_character.set_layer("weapon", item_data.overlay_texture)
	else:
		_character.remove_layer("weapon")

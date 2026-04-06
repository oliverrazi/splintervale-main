extends CharacterBody3D

# --- Slash VFX ---
@export_group("Slash VFX")
@export var slash_scene: PackedScene
@export var slash_lifetime: float = 0.3
@export var dissolve_duration := 0.0
@export var impact_scene: PackedScene
@export var impact_lifetime: float = 0.5
@export var impact_scale: float = 1.0
@export var impact_delay: float = 0.1

@export_group("Sound")
@export var swoosh_sounds: Array[AudioStream] = []
@export var swoosh_volume_db := -6.0
@export var swoosh_pitch_variation := 0.08
@export var hit_sounds: Array[AudioStream] = []
@export var hit_volume_db: float = -3.0
@export var hit_pitch_variation: float = 0.1
@export var footstep_sounds: Array[AudioStream] = []
@export var footstep_volume_db: float = -10.0
@export var footstep_pitch_variation: float = 0.15
@export var footstep_interval: float = 0.25 

var _slash_spawned_this_attack: bool = false
var _slash_spawn_frame: int = 2

@export_group("Controls")
@export var SPEED: float = 50.0
@export var JUMP_VELOCITY: float = 4.5

# --- Spritesheet-Layout ---
@export var HFRAMES: int = 9
@export var VFRAMES: int = 11

# --- Animationsgeschwindigkeit ---
@export var WALK_FPS: float = 8.0
@export var ATTACK_FPS: float = 10.0
@export var ATTACK_MOVE_SPEED: float = 1.0
@export var ATTACK_LAST_FRAME_HOLD: float = 0.15
@export var ATTACK_COOLDOWN: float = 0.25

# --- Frames im Sheet (8 Richtungen) ---
# Down
@export var DOWN_IDLE_FRAME: int = 0
@export var DOWN_RUN_START_FRAME: int = 1
@export var DOWN_RUN_END_FRAME: int = 6

# Up
@export var UP_IDLE_FRAME: int = 9
@export var UP_RUN_START_FRAME: int = 10
@export var UP_RUN_END_FRAME: int = 15

# Left (Right ist gespiegelt)
@export var LEFT_IDLE_FRAME: int = 18
@export var LEFT_RUN_START_FRAME: int = 19
@export var LEFT_RUN_END_FRAME: int = 24

# Down-Left (Down-Right ist gespiegelt)
@export var DOWN_LEFT_IDLE_FRAME: int = 54
@export var DOWN_LEFT_RUN_START_FRAME: int = 55
@export var DOWN_LEFT_RUN_END_FRAME: int = 60

# Up-Right (Up-Left ist gespiegelt)
@export var UP_RIGHT_IDLE_FRAME: int = 63
@export var UP_RIGHT_RUN_START_FRAME: int = 64
@export var UP_RIGHT_RUN_END_FRAME: int = 69


@export_group("Item Pickup")
@export var item_hold_frame: int = 90

var _is_frozen: bool = false


@export_group("Combat")
@export var max_health: int = 30
@export var attack_damage: int = 5
@export var knockback_force: float = 5.0
@export var knockback_duration: float = 0.2
@export var invincibility_duration: float = 0.5
@export var hurt_flash_duration: float = 0.15 
@export var hurt_blink_speed: float = 0.1

@export_group("LevelUpNotification")
@export var levelup_popup_scene: PackedScene
@onready var head_anchor: Marker3D = $HeadAnchor


var _nearby_npc: NPC = null
var _nearby_chest: TreasureChest = null

# --- Bei den Variablen ---
var hud: Node = null
var _health: int
var _knockback_velocity: Vector3 = Vector3.ZERO
var _knockback_timer: float = 0.0
var _invincibility_timer: float = 0.0
var _is_knocked_back: bool = false
var _is_hurt_flashing: bool = false
var _hurt_flash_timer: float = 0.0

var _footstep_timer: float = 0.0

# --- Attack-Kombos (8 Richtungen) ---
# Down
const ATTACK_DOWN_1: Array[int] = [27, 27, 29]
const ATTACK_DOWN_2: Array[int] = [30, 30, 32]
const ATTACK_DOWN_3: Array[int] = [27, 27, 29]

# Up
const ATTACK_UP_1: Array[int] = [36, 36, 38]
const ATTACK_UP_2: Array[int] = [39, 39, 41]
const ATTACK_UP_3: Array[int] = [36, 36, 38]

# Left/Right (Right ist gespiegelt)
const ATTACK_SIDE_1: Array[int] = [45, 45, 47]
const ATTACK_SIDE_2: Array[int] = [48, 48, 50]
const ATTACK_SIDE_3: Array[int] = [45, 45, 47]

# Down-Left (Down-Right ist gespiegelt)
const ATTACK_DOWN_LEFT_1: Array[int] = [72, 72, 74]
const ATTACK_DOWN_LEFT_2: Array[int] = [75, 75, 77]
const ATTACK_DOWN_LEFT_3: Array[int] = [72, 72, 74]

# Up-Right (Up-Left ist gespiegelt)
const ATTACK_UP_RIGHT_1: Array[int] = [81, 81, 83]
const ATTACK_UP_RIGHT_2: Array[int] = [84, 84, 86]
const ATTACK_UP_RIGHT_3: Array[int] = [81, 81, 83]

const COMBO_SPRITE_FLIP_FRAMES := {}

const HURT_DOWN_LEFT: int = 61
const HURT_UP_RIGHT: int = 70

@export var SPRITE_FACES_RIGHT: bool = true


const DEATH_FRAME_1: int = 78  # Knie knicken
const DEATH_FRAME_2: int = 79  # Auf den Knien
const DEATH_FRAME_3: int = 80  # Am Boden

const DEATH_FRAME_1_DURATION: float = 0.2  # Kurz
const DEATH_FRAME_2_DURATION: float = 0.6  # Etwas länger
const DEATH_GAME_OVER_DELAY: float = 2.0   # Sekunden bis Game Over Screen

var _is_dead: bool = false
var _death_anim_time: float = 0.0
var _death_phase: int = 0

# --- Intern ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _anim_time: float = 0.0
var _is_moving: bool = false
var _facing_right: bool = true

# 8 Richtungen
enum DirMode { DOWN, UP, LEFT, RIGHT, DOWN_LEFT, DOWN_RIGHT, UP_LEFT, UP_RIGHT }
var _last_dir_mode: int = DirMode.DOWN

# --- Attack-Zustand ---
var _is_attacking: bool = false
var _attack_step: int = 0
var _attack_time: float = 0.0
var _attack_can_chain: bool = false
var _attack_buffered: bool = false
var _attack_cooldown_timer: float = 0.0

var _current_attack_frames: Array[int] = []
var _current_attack_duration: float = 0.0
var _current_attack_base_duration: float = 0.0

var _consumable_cooldown: float = 0.0
const CONSUMABLE_COOLDOWN_TIME: float = 0.5

var _equipped_weapon_id: String = "sword1"


var _hotbar_held: Array[bool] = [false, false, false, false]
var _vector_anchor_slot: int = -1  # Welcher Slot hält Vector Anchor

@onready var character: SmoothPixelSprite3D = $charactersprite
@onready var dodge_component: DodgeComponent = $DodgeComponent
@onready var vector_anchor: VectorAnchorComponent = $VectorAnchorComponent


func _ready() -> void:
	add_to_group("player")
	
	if character:
		character.hframes = HFRAMES
		character.vframes = VFRAMES
	_show_idle()
	
	# Warte einen Frame, dann verbinde mit PlayerData
	call_deferred("_connect_to_player_data")
	
func _connect_to_player_data() -> void:
	# Warte bis GameManager verfügbar ist
	await get_tree().process_frame
	
	# Sicherheitscheck
	if GameManager == null:
		push_error("GameManager not found!")
		return
	
	if GameManager.player_data == null:
		push_error("PlayerData not initialized!")
		return
	
	var pd: PlayerData = GameManager.player_data
	
	# Level-Up Signal verbinden (für Popup)
	if not pd.level_changed.is_connected(_on_level_changed):
		pd.level_changed.connect(_on_level_changed)
	
	# HP Signal verbinden (für HUD Update)
	if not pd.hp_changed.is_connected(_on_hp_changed):
		pd.hp_changed.connect(_on_hp_changed)
	
	# Initiales HUD Update
	_update_hud()

func _update_hud() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		var pd : PlayerData  = GameManager.player_data
		hud.update_hp(pd.current_hp, pd.max_hp)
		hud.update_exp(pd.current_exp, pd.exp_to_next_level)
		hud.set_level(pd.level)
		hud.update_gold(pd.gold)


func _on_hp_changed(current: int, maximum: int) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.animate_hp_change(current)
		
func _on_level_changed(new_level: int) -> void:

	if GameManager.is_loading:
		return
	_spawn_levelup_popup(new_level) # hier deine Anzeige / Popup-Logik

func _exit_tree() -> void:
	if GameManager.player_data.level_changed.is_connected(_on_level_changed):
		GameManager.player_data.level_changed.disconnect(_on_level_changed)

func _spawn_levelup_popup(new_level: int) -> void:
	print("=== SPAWNING LEVEL UP POPUP ===")
	
	if levelup_popup_scene == null:
		push_warning("levelup_popup_scene ist nicht gesetzt.")
		return
	
	var popup := levelup_popup_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(popup)
	popup.global_position = head_anchor.global_position
	
	print("Popup position: ", popup.global_position)
	print("Head anchor position: ", head_anchor.global_position)
	
	var label: Label3D = popup.get_node_or_null("Label3D")
	print("Label3D found: ", label != null)
	if label:
		label.text = "Level Up!"
		print("Label text set to: ", label.text)
	
	var anim_player: AnimationPlayer = popup.get_node_or_null("AnimationPlayer")
	print("AnimationPlayer found: ", anim_player != null)
	
	if anim_player:
		print("Available animations: ", anim_player.get_animation_list())
		anim_player.play("pop")  # Ändere den Namen falls anders
		anim_player.animation_finished.connect(func(_name): popup.queue_free())
	else:
		get_tree().create_timer(2.0).timeout.connect(popup.queue_free)


func set_frozen(frozen: bool) -> void:
	_is_frozen = frozen
	if frozen:
		velocity = Vector3.ZERO


func is_frozen() -> bool:
	return _is_frozen


func get_item_hold_frame() -> int:
	return item_hold_frame


func _physics_process(delta: float) -> void:
	
	if _is_dead:
		_process_death(delta)
		return
	
	if GameManager and GameManager.player_data:
		GameManager.player_data.process_regeneration(delta)
	
	if dodge_component and dodge_component.is_dodging():
		move_and_slide()
		return
		
	if vector_anchor and vector_anchor.is_active():
		if vector_anchor.is_launching():
			return
		else:
			_check_vector_anchor_release()
			return
		
	if _is_frozen:
		return
		
	if _consumable_cooldown > 0.0:
		_consumable_cooldown -= delta
	
		
	_update_nearby_npc()
		
	_process_hotbar_input()
		
	_process_invincibility(delta)
	
	# Knockback verarbeiten
	if _is_knocked_back:
		_process_knockback(delta)
		return
	
	# --- Rest des originalen _physics_process Codes ---
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta
		if _attack_cooldown_timer < 0.0:
			_attack_cooldown_timer = 0.0

	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if input_dir.length_squared() > 0.01:  # length_squared ist performanter
		input_dir = input_dir.normalized()


	var yaw: float = $SpringArm3D.rotation.y
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))

	var world_dir: Vector3 = (right * input_dir.x + forward * input_dir.y).normalized()
	
	if _is_attacking:
		var attack_dir3d: Vector3 = _get_attack_world_dir()
		if attack_dir3d != Vector3.ZERO and _current_attack_duration > 0.0:
			var t: float = clamp(_attack_time, 0.0, _current_attack_duration)
			var progress: float = t / _current_attack_duration
			var move_factor: float = 1.0 - progress
			move_factor *= move_factor
			var strength: float = ATTACK_MOVE_SPEED * move_factor
			velocity.x = attack_dir3d.x * strength
			velocity.z = attack_dir3d.z * strength
	else:
		if world_dir != Vector3.ZERO:
			velocity.x = world_dir.x * SPEED
			velocity.z = world_dir.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0.0, SPEED)
			velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()
	

	if _is_attacking:
		_update_attack(delta)
	else:
		_update_animation(input_dir, delta)
		
func _check_vector_anchor_release() -> void:
	"""Prüft ob Vector Anchor losgelassen wurde während Charging"""
	# Prüfe alle Hotbar-Slots auf Release
	if Input.is_action_just_released("hotbar_w"):
		_try_release_vector_anchor(0)
	elif Input.is_action_just_released("hotbar_a"):
		_try_release_vector_anchor(1)
	elif Input.is_action_just_released("hotbar_s"):
		_try_release_vector_anchor(2)
	elif Input.is_action_just_released("hotbar_d"):
		_try_release_vector_anchor(3)
		
func _try_release_vector_anchor(slot_index: int) -> void:
	"""Versucht Vector Anchor zu releasen wenn der richtige Slot losgelassen wurde"""
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		return
	
	var item_id: String = inv_manager.get_hotbar_item(slot_index)
	if item_id == "":
		return
	
	var item_data: ItemData = inv_manager.get_item_data(item_id)
	if item_data == null:
		return
	
	if item_data.item_type == ItemData.ItemType.EQUIPMENT and item_data.effect_action == "vector_anchor":
		if vector_anchor and vector_anchor.is_charging():
			vector_anchor.stop_charging()

func _set_nearby_chest(chest: TreasureChest) -> void:
	_nearby_chest = chest

func _update_nearby_npc() -> void:
	_nearby_npc = null
	var npcs: Array[Node] = get_tree().get_nodes_in_group("npc")
	var closest_dist: float = INF
	
	for node in npcs:
		var npc: NPC = node as NPC
		if npc and npc.can_interact():
			var dist: float = global_position.distance_to(npc.global_position)
			if dist < closest_dist:
				closest_dist = dist
				_nearby_npc = npc


func reset_death_state() -> void:
	_is_dead = false
	_death_phase = 0
	_death_anim_time = 0.0
	_is_attacking = false
	_is_knocked_back = false
	_is_hurt_flashing = false
	character.modulate = Color.WHITE
	character.modulate.a = 1.0
	
	if dodge_component:
		dodge_component._is_dodging = false
		dodge_component._dodge_cooldown_timer = 0.0
		
	if vector_anchor:
		vector_anchor.cancel()
		
	_show_idle()


func take_damage(amount: int, from_position: Vector3) -> void:
	if dodge_component and dodge_component.is_dodging():
		return
		
	if vector_anchor and vector_anchor.is_launching():
		return
	
	if _invincibility_timer > 0.0:
		return
		
	if vector_anchor and vector_anchor.is_charging():
		vector_anchor.cancel()
	
	# Schaden über PlayerData berechnen (mit Defense)
	GameManager.player_data.take_damage(amount)
	
	var knockback_dir := (global_position - from_position).normalized()
	knockback_dir.y = 0
	_knockback_velocity = knockback_dir * knockback_force
	_knockback_timer = knockback_duration
	_is_knocked_back = true
	_invincibility_timer = invincibility_duration
	
	_is_hurt_flashing = true
	_hurt_flash_timer = hurt_flash_duration
	
	if _is_attacking:
		_end_attack()
	
	if not GameManager.player_data.is_alive():
		_die()
		
func is_alive() -> bool:
	return not _is_dead and GameManager.player_data.is_alive()
		
func _die() -> void:
	if _is_dead:
		return
	
	print("Player died!")
	_is_dead = true
	_death_phase = 0
	_death_anim_time = 0.0
	
	# Alles stoppen
	velocity = Vector3.ZERO
	_is_attacking = false
	_is_knocked_back = false
	_is_hurt_flashing = false
	
	if vector_anchor:
		vector_anchor.cancel()
	

	GameOverScreen.show_game_over(DEATH_GAME_OVER_DELAY)

func _process_death(delta: float) -> void:
	_death_anim_time += delta
	
	match _death_phase:
		0:  # Frame 1 - Knie knicken
			character.frame = DEATH_FRAME_1
			if _death_anim_time >= DEATH_FRAME_1_DURATION:
				_death_phase = 1
				_death_anim_time = 0.0
		
		1:  # Frame 2 - Auf den Knien
			character.frame = DEATH_FRAME_2
			if _death_anim_time >= DEATH_FRAME_2_DURATION:
				_death_phase = 2
				_death_anim_time = 0.0
		
		2:  # Frame 3 - Am Boden (bleibt)
			character.frame = DEATH_FRAME_3


func get_health() -> int:
	return _health


func _get_direction_from_input(dir: Vector2) -> int:
	if dir == Vector2.ZERO:
		return _last_dir_mode
	
	var angle: float = dir.angle()
	var deg: float = rad_to_deg(angle)
	if deg < 0:
		deg += 360.0
	
	# 8 Sektoren à 45°
	if deg >= 337.5 or deg < 22.5:
		return DirMode.RIGHT
	elif deg >= 22.5 and deg < 67.5:
		return DirMode.DOWN_RIGHT
	elif deg >= 67.5 and deg < 112.5:
		return DirMode.DOWN
	elif deg >= 112.5 and deg < 157.5:
		return DirMode.DOWN_LEFT
	elif deg >= 157.5 and deg < 202.5:
		return DirMode.LEFT
	elif deg >= 202.5 and deg < 247.5:
		return DirMode.UP_LEFT
	elif deg >= 247.5 and deg < 292.5:
		return DirMode.UP
	else:
		return DirMode.UP_RIGHT


func _update_animation(dir: Vector2, delta: float) -> void:
	_is_moving = dir != Vector2.ZERO

	if _is_moving:
		_last_dir_mode = _get_direction_from_input(dir)
		
		match _last_dir_mode:
			DirMode.RIGHT, DirMode.DOWN_RIGHT, DirMode.UP_RIGHT:
				_facing_right = true
			DirMode.LEFT, DirMode.DOWN_LEFT, DirMode.UP_LEFT:
				_facing_right = false
		
		_animate_run_8dir(delta)
	else:
		_anim_time = 0.0
		_show_idle()


func _animate_run_8dir(delta: float) -> void:
	_anim_time += delta
	
	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_play_footstep_sound()
		_footstep_timer = footstep_interval
	
	var start_frame: int
	var end_frame: int
	var flip: bool = false
	
	match _last_dir_mode:
		DirMode.DOWN:
			start_frame = DOWN_RUN_START_FRAME
			end_frame = DOWN_RUN_END_FRAME
		DirMode.UP:
			start_frame = UP_RUN_START_FRAME
			end_frame = UP_RUN_END_FRAME
		DirMode.LEFT:
			start_frame = LEFT_RUN_START_FRAME
			end_frame = LEFT_RUN_END_FRAME
		DirMode.RIGHT:
			start_frame = LEFT_RUN_START_FRAME
			end_frame = LEFT_RUN_END_FRAME
			flip = true
		DirMode.DOWN_LEFT:
			start_frame = DOWN_LEFT_RUN_START_FRAME
			end_frame = DOWN_LEFT_RUN_END_FRAME
		DirMode.DOWN_RIGHT:
			start_frame = DOWN_LEFT_RUN_START_FRAME
			end_frame = DOWN_LEFT_RUN_END_FRAME
			flip = true
		DirMode.UP_RIGHT:
			start_frame = UP_RIGHT_RUN_START_FRAME
			end_frame = UP_RIGHT_RUN_END_FRAME
		DirMode.UP_LEFT:
			start_frame = UP_RIGHT_RUN_START_FRAME
			end_frame = UP_RIGHT_RUN_END_FRAME
			flip = true
		_:
			start_frame = DOWN_RUN_START_FRAME
			end_frame = DOWN_RUN_END_FRAME
	
	var run_frames: int = end_frame - start_frame + 1
	if run_frames <= 0:
		run_frames = 1
	
	var base: int = int(floor(_anim_time * WALK_FPS)) % run_frames
	var frame_index: int = start_frame + base
	
	character.frame = frame_index
	character.flip_h = flip


func _show_idle() -> void:
	var frame: int
	var flip: bool = false
	
	match _last_dir_mode:
		DirMode.DOWN:
			frame = DOWN_IDLE_FRAME
		DirMode.UP:
			frame = UP_IDLE_FRAME
		DirMode.LEFT:
			frame = LEFT_IDLE_FRAME
		DirMode.RIGHT:
			frame = LEFT_IDLE_FRAME
			flip = true
		DirMode.DOWN_LEFT:
			frame = DOWN_LEFT_IDLE_FRAME
		DirMode.DOWN_RIGHT:
			frame = DOWN_LEFT_IDLE_FRAME
			flip = true
		DirMode.UP_RIGHT:
			frame = UP_RIGHT_IDLE_FRAME
		DirMode.UP_LEFT:
			frame = UP_RIGHT_IDLE_FRAME
			flip = true
		_:
			frame = DOWN_IDLE_FRAME
	
	character.frame = frame
	character.flip_h = flip


func _set_frame(frame_index: int, use_flip: bool, extra_flip: bool) -> void:
	if not character:
		return

	var flip: bool = use_flip
	
	if extra_flip:
		flip = not flip

	character.flip_h = flip
	character.frame = frame_index


# ---------- Angriff / Combo-Logik ----------



func can_attack() -> bool:
	"""Prüft ob der Spieler angreifen kann oder ob eine Interaktion möglich ist"""
	return _nearby_npc == null or not _nearby_npc.can_interact()


func _choose_attack_direction_from_input(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	
	_last_dir_mode = _get_direction_from_input(dir)
	
	match _last_dir_mode:
		DirMode.RIGHT, DirMode.DOWN_RIGHT, DirMode.UP_RIGHT:
			_facing_right = true
		DirMode.LEFT, DirMode.DOWN_LEFT, DirMode.UP_LEFT:
			_facing_right = false


func _is_flipped_direction(dir_mode: int) -> bool:
	# Gibt true zurück wenn diese Richtung gespiegelt dargestellt wird
	match dir_mode:
		DirMode.RIGHT, DirMode.DOWN_RIGHT, DirMode.UP_LEFT:
			return true
		_:
			return false


func _start_attack(step: int) -> void:
	_is_attacking = true
	_attack_step = step
	_attack_time = 0.0
	_attack_can_chain = false
	_attack_buffered = false
	_slash_spawned_this_attack = false

	_current_attack_frames = _get_attack_frames_for(_last_dir_mode, _attack_step)
	_current_attack_base_duration = _get_attack_base_duration(_current_attack_frames)
	_current_attack_duration = _get_attack_duration(_current_attack_frames)

	#var world_pos: Vector3 = _get_slash_spawn_position(_last_dir_mode)
	#_spawn_slash_vfx(step, _last_dir_mode, world_pos)
	#_play_swoosh_sound(world_pos)


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


func _update_attack(delta: float) -> void:
	if _current_attack_frames.size() == 0 or _current_attack_duration <= 0.0:
		_end_attack()
		return

	_attack_time += delta

	if _attack_time >= _current_attack_duration:
		if _attack_buffered and _attack_step < 3:
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
		if frame_index_in_array < 0:
			frame_index_in_array = 0
		if frame_index_in_array > frames_count - 2:
			frame_index_in_array = frames_count - 2
	else:
		frame_index_in_array = frames_count - 1

	_attack_can_chain = _attack_time >= _current_attack_base_duration
	
	if not _slash_spawned_this_attack and frame_index_in_array >= _slash_spawn_frame:
		_slash_spawned_this_attack = true
		var world_pos: Vector3 = _get_slash_spawn_position(_last_dir_mode)
		_spawn_slash_vfx(_attack_step, _last_dir_mode, world_pos)
		_play_swoosh_sound(world_pos)

	var frame_index: int = _current_attack_frames[frame_index_in_array]
	var use_flip: bool = _is_flipped_direction(_last_dir_mode)
	
	var extra_flip: bool = false
	if COMBO_SPRITE_FLIP_FRAMES.has(_attack_step):
		var flip_indices: Array = COMBO_SPRITE_FLIP_FRAMES[_attack_step]
		extra_flip = frame_index_in_array in flip_indices
	
	_set_frame(frame_index, use_flip, extra_flip)


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
	var frame_duration: float = 1.0 / ATTACK_FPS
	return float(count - 1) * frame_duration


func _get_attack_duration(frames: Array[int]) -> float:
	var count: int = frames.size()
	if count == 0:
		return 0.0
	var frame_duration: float = 1.0 / ATTACK_FPS
	var base_duration: float = _get_attack_base_duration(frames)
	var last_duration: float = frame_duration + ATTACK_LAST_FRAME_HOLD
	return base_duration + last_duration


func _get_attack_world_dir() -> Vector3:
	var dir2: Vector2 = Vector2.ZERO

	match _last_dir_mode:
		DirMode.DOWN:
			dir2 = Vector2(0.0, 1.0)
		DirMode.UP:
			dir2 = Vector2(0.0, -1.0)
		DirMode.LEFT:
			dir2 = Vector2(-1.0, 0.0)
		DirMode.RIGHT:
			dir2 = Vector2(1.0, 0.0)
		DirMode.DOWN_LEFT:
			dir2 = Vector2(-1.0, 1.0).normalized()
		DirMode.DOWN_RIGHT:
			dir2 = Vector2(1.0, 1.0).normalized()
		DirMode.UP_LEFT:
			dir2 = Vector2(-1.0, -1.0).normalized()
		DirMode.UP_RIGHT:
			dir2 = Vector2(1.0, -1.0).normalized()

	if dir2 == Vector2.ZERO:
		return Vector3.ZERO

	return ($SpringArm3D.transform.basis * Vector3(dir2.x, 0, dir2.y)).normalized()


# --- Slash VFX (8 Richtungen) ---

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

var hit_already: bool = false

func _spawn_slash_vfx(combo_index: int, dir_mode: int, world_pos: Vector3) -> void:
	if slash_scene == null:
		return
	
	var vfx := slash_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(vfx)
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
	
	# Hitbox Setup
	var hit_area: Area3D = pivot.get_node_or_null("HitArea")

	hit_already = false
	if hit_area:
		hit_area.set_meta("damage", attack_damage)
		hit_area.set_meta("source_position", global_position)
		hit_area.set_meta("attacker", self)
		

		
		# Verbinde Signal für Treffer
		hit_area.body_entered.connect(func(body: Node3D) -> void:
			_on_slash_hit(body, hit_area)
		)
	else:
		print("ERROR: HitArea not found in slash VFX!")
	
	var anim_player: AnimationPlayer = vfx.get_node("Node3D/AnimationPlayer")
	if anim_player and anim_player.has_animation("slash"):
		anim_player.play("slash")
	
	_cleanup_vfx(vfx, slash_lifetime)
	
func _on_slash_hit(body: Node3D, hit_area: Area3D) -> void:
	# Nicht sich selbst treffen
	if body == self:
		return
	
	# Nur Gegner treffen, die noch leben
	if body.has_method("take_damage") && !body._is_dead:
		
		var base_damage: int = hit_area.get_meta("damage", attack_damage)
		var actual_damage: int = GameManager.player_data.get_attack_damage(base_damage)
		
		var source_pos: Vector3 = hit_area.get_meta("source_position", global_position)
		#print("-> Dealing ", actual_damage, " damage to ", body.name)
		if !hit_already:
			body.take_damage(actual_damage, source_pos)
			hit_already = true
			var impact_pos: Vector3 = (global_position + body.global_position) / 2.0
			impact_pos.y += 0.3
			_spawn_impact_vfx(impact_pos)
		
			_play_hit_sound(body.global_position)
		
	else:
		print("-> Body has no take_damage method")


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
		get_tree().create_timer(lifetime).timeout.connect(vfx.queue_free)


func _get_slash_spawn_position(dir_mode: int) -> Vector3:
	var pos := character.global_position
	var dist := 0.2
	var diag_dist := dist * 0.707  # sqrt(2)/2 für diagonale
	
	match dir_mode:
		DirMode.RIGHT:
			pos += Vector3(dist, 0.0, 0.0)
		DirMode.LEFT:
			pos += Vector3(-dist, 0.0, 0.0)
		DirMode.UP:
			pos += Vector3(0.0, 0.0, -0.2 + dist)
		DirMode.DOWN:
			pos += Vector3(0.0, 0.0, 0.3 - dist)
		DirMode.DOWN_RIGHT:
			pos += Vector3(diag_dist, 0.0, diag_dist)
		DirMode.DOWN_LEFT:
			pos += Vector3(-diag_dist, 0.0, diag_dist)
		DirMode.UP_RIGHT:
			pos += Vector3(diag_dist, 0.0, -diag_dist)
		DirMode.UP_LEFT:
			pos += Vector3(-diag_dist, 0.0, -diag_dist)
	
	return pos


func _play_swoosh_sound(world_pos: Vector3) -> void:
	if swoosh_sounds.is_empty():
		return

	AudioPool.play_3d(
		swoosh_sounds.pick_random(),
		world_pos,
		swoosh_volume_db,
		randf_range(1.0 - swoosh_pitch_variation, 1.0 + swoosh_pitch_variation) if swoosh_pitch_variation > 0.0 else 1.0
	)
	
func _play_footstep_sound() -> void:
	if footstep_sounds.is_empty():
		return
	AudioPool.play_3d(
		footstep_sounds.pick_random(),
		global_position,
		footstep_volume_db,
		randf_range(1.0 - footstep_pitch_variation, 1.0 + footstep_pitch_variation)
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
	
func _get_hurt_frame() -> Dictionary:
	match _last_dir_mode:
		DirMode.DOWN, DirMode.DOWN_LEFT, DirMode.LEFT:
			return {frame = HURT_DOWN_LEFT, flip = false}
		DirMode.DOWN_RIGHT, DirMode.RIGHT:
			return {frame = HURT_DOWN_LEFT, flip = true}
		DirMode.UP, DirMode.UP_RIGHT:
			return {frame = HURT_UP_RIGHT, flip = false}
		DirMode.UP_LEFT:
			return {frame = HURT_UP_RIGHT, flip = true}
		_:
			return {frame = HURT_DOWN_LEFT, flip = false}

func _process_invincibility(delta: float) -> void:
	# Hurt Flash (rot aufleuchten)
	if _is_hurt_flashing:
		_hurt_flash_timer -= delta
		character.modulate = Color(1.5, 0.5, 0.5)  # Rot
		
		if _hurt_flash_timer <= 0.0:
			_is_hurt_flashing = false
			character.modulate = Color.WHITE
	
	# Invincibility Blinken
	if _invincibility_timer > 0.0:
		_invincibility_timer -= delta
		
		if not _is_hurt_flashing:
			# Blinken (transparent/sichtbar wechseln)
			var blink := fmod(_invincibility_timer, hurt_blink_speed * 2.0) < hurt_blink_speed
			character.modulate.a = 0.3 if blink else 1.0
		
		if _invincibility_timer <= 0.0:
			character.modulate = Color.WHITE
			character.modulate.a = 1.0
			
func _process_knockback(delta: float) -> void:
	_knockback_timer -= delta
	velocity.x = _knockback_velocity.x
	velocity.z = _knockback_velocity.z
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, knockback_force * 2.0 * delta)
	
	# Hurt Frame anzeigen
	var hurt_data := _get_hurt_frame()
	character.frame = hurt_data.frame
	character.flip_h = hurt_data.flip
	
	if _knockback_timer <= 0.0:
		_is_knocked_back = false
		_knockback_velocity = Vector3.ZERO
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	move_and_slide()
	
func _spawn_impact_vfx(pos: Vector3) -> void:
	if impact_scene == null:
		return
	
	var vfx := impact_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = pos
	vfx.rotation_degrees.y = randf() * 360.0
	vfx.scale = Vector3(impact_scale, impact_scale, impact_scale)
	
	# Partikel erst nach delay starten
	if impact_delay > 0.0:
		# Alle Partikel erstmal deaktivieren
		for child in vfx.get_children():
			if child is GPUParticles3D:
				child.emitting = false
		
		# Nach delay starten
		get_tree().create_timer(impact_delay).timeout.connect(func():
			if is_instance_valid(vfx):
				for child in vfx.get_children():
					if child is GPUParticles3D:
						child.emitting = true
		)
	else:
		# Sofort starten
		for child in vfx.get_children():
			if child is GPUParticles3D:
				child.emitting = true
	
	# Aufräumen nach lifetime + delay
	get_tree().create_timer(impact_lifetime + impact_delay).timeout.connect(vfx.queue_free)
	
func _process_hotbar_input() -> void:
	if _is_dead:
		return
	
	# Dialog Check
	var dialogue_manager: Node = get_node_or_null("/root/DialogueManager")
	if dialogue_manager:
		if dialogue_manager.is_dialogue_active() or dialogue_manager.is_on_cooldown():
			return
	
	# Pause Check
	if get_tree().paused:
		return
	
	# W-Taste (Slot 0) - Spezialbehandlung für NPC und Kombos
	if Input.is_action_just_pressed("hotbar_w"):
		# NPC in Reichweite? -> Interagieren
		if _nearby_npc and _nearby_npc.can_interact():
			_nearby_npc.interact()
			return
		if _nearby_chest and _nearby_chest.can_interact():
			print("INTERACT")
			_nearby_chest.interact()
			return
		
		# Ansonsten Hotbar-Slot benutzen (mit Kombo-Support)
		_use_hotbar_slot_with_combo(0)
	
	# A, S, D - normale Hotbar-Slots (auch mit Kombo-Support für Waffen)
	if Input.is_action_just_pressed("hotbar_a"):
		_use_hotbar_slot_with_combo(1)
	elif Input.is_action_just_pressed("hotbar_s"):
		_use_hotbar_slot_with_combo(2)
	elif Input.is_action_just_pressed("hotbar_d"):
		_use_hotbar_slot_with_combo(3)


func _use_hotbar_slot_with_combo(slot_index: int) -> void:
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager == null:
		return
	
	var item_id: String = inv_manager.get_hotbar_item(slot_index)
	if item_id == "":
		# Leerer Slot - unbewaffneter Angriff wenn Slot 0 - Nö, warum auch?
		#if slot_index == 0:
			#_handle_weapon_input()
		return
	
	var item_data: ItemData = inv_manager.get_item_data(item_id)
	if item_data == null:
		return
	
	match item_data.item_type:
		ItemData.ItemType.WEAPON:
			_equipped_weapon_id = item_id
			_handle_weapon_input()
		ItemData.ItemType.CONSUMABLE:
			_use_consumable(item_id, item_data, inv_manager)
		ItemData.ItemType.EQUIPMENT:
			_use_equipment(item_id, item_data)
		ItemData.ItemType.KEY_ITEM:
			_use_key_item(item_id, item_data)
		ItemData.ItemType.MATERIAL:
			pass
			
func _handle_weapon_input() -> void:
	"""Behandelt Waffen-Input mit Kombo-Support"""
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_action_pressed("move_down"):
		dir.y += 1
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	
	# Bereits am Angreifen? -> Kombo buffern
	if _is_attacking:
		if _attack_can_chain and _attack_step < 3:
			_attack_buffered = true
	else:
		# Neuer Angriff starten
		if _attack_cooldown_timer <= 0.0:
			_choose_attack_direction_from_input(dir)
			_start_attack(1)

	
func can_interact_with_npc() -> bool:
	return _nearby_npc != null and _nearby_npc.can_interact()
	
func can_interact_with_chest() -> bool:
	return _nearby_chest != null and _nearby_chest.can_interact()

func _use_equipment(item_id: String, item_data: ItemData) -> void:
	"""Benutzt ein Equipment-Item (wie Shift-Boots oder Vector Anchor)"""
	match item_data.effect_action:
		"dodge":
			if dodge_component:
				dodge_component.try_dodge()
		"vector_anchor":
			if vector_anchor and not vector_anchor.is_active():
				vector_anchor.start_charging()
		_:
			print("Equipment used: ", item_data.item_name)

func _use_consumable(item_id: String, item_data: ItemData, inv_manager: Node) -> void:
	# Cooldown Check nur für Consumables
	if _consumable_cooldown > 0.0:
		return
	
	if _is_attacking:
		return
	
	if not item_data.usable:
		return
	
	print("Using consumable: ", item_data.item_name)
	
	if inv_manager.use_item(item_id):
		_consumable_cooldown = CONSUMABLE_COOLDOWN_TIME
		_show_item_use_effect(item_data)


func _use_key_item(item_id: String, item_data: ItemData) -> void:
	# Key Items haben spezielle Verwendungen (z.B. Tür öffnen, Puzzle lösen)
	print("Using key item: ", item_data.item_name)
	
	# Custom Effect Action ausführen
	if item_data.effect_action != "":
		var inv_manager: Node = get_node_or_null("/root/InventoryManager")
		if inv_manager:
			inv_manager._execute_effect_action(item_data.effect_action)


func _show_equip_effect() -> void:
	# Kurzes Aufblitzen beim Waffenwechsel
	if character == null:
		return
	
	var original_color: Color = character.modulate
	character.modulate = Color(1.2, 1.2, 1.2, 1.0)
	
	var tween := create_tween()
	tween.tween_property(character, "modulate", original_color, 0.15)


func _show_item_use_effect(item_data: ItemData) -> void:
	if item_data == null:
		return
	
	if item_data.heal_amount > 0:
		_show_heal_effect()
	
	if item_data.stamina_restore > 0:
		_show_stamina_effect()


func _show_heal_effect() -> void:
	if character == null:
		return
	
	var original_color: Color = character.modulate
	character.modulate = Color(0.5, 1.0, 0.5, 1.0)
	
	var tween := create_tween()
	tween.tween_property(character, "modulate", original_color, 0.4)
	
	_spawn_heal_particles()


func _show_stamina_effect() -> void:
	if character == null:
		return
	
	var original_color: Color = character.modulate
	character.modulate = Color(1.0, 1.0, 0.5, 1.0)
	
	var tween := create_tween()
	tween.tween_property(character, "modulate", original_color, 0.4)


func _spawn_heal_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.amount = 8
	particles.lifetime = 0.8
	
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 30.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 2.0
	material.gravity = Vector3(0, -1, 0)
	material.scale_min = 0.3
	material.scale_max = 0.6
	material.color = Color(0.3, 1.0, 0.4, 1.0)
	particles.process_material = material
	
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	particles.draw_pass_1 = mesh
	
	particles.global_position = global_position + Vector3(0, 0.5, 0)
	get_tree().current_scene.add_child(particles)
	
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)


# Öffentliche Methode um aktuelle Waffe zu bekommen
func get_equipped_weapon() -> String:
	return _equipped_weapon_id


func get_equipped_weapon_data() -> ItemData:
	var inv_manager: Node = get_node_or_null("/root/InventoryManager")
	if inv_manager:
		return inv_manager.get_item_data(_equipped_weapon_id)
	return null

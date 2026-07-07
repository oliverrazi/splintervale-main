extends CharacterBody3D

@export_group("Sound")
@export var footstep_sounds: Array[AudioStream] = []
@export var footstep_volume_db: float = -10.0
@export var footstep_pitch_variation: float = 0.15
@export var footstep_interval: float = 0.25

@export_group("Controls")
@export var SPEED: float = 50.0
@export var JUMP_VELOCITY: float = 4.5

# --- Spritesheet-Layout ---
@export var HFRAMES: int = 9
@export var VFRAMES: int = 11

# --- Animationsgeschwindigkeit ---
@export var WALK_FPS: float = 8.0

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


@export var DOWN_WALK_FRAMES: Array[int] = [2, 3, 5, 6]
@export var UP_WALK_FRAMES: Array[int] = [11,12, 14, 15]
@export var LEFT_WALK_FRAMES: Array[int] = [16, 26, 17, 25]

@export var DOWN_LEFT_WALK_FRAMES: Array[int] = [56, 57, 59, 60]
@export var UP_RIGHT_WALK_FRAMES: Array[int] = [65, 66, 68, 69]


@export_group("Item Pickup")
@export var item_hold_frame: int = 90

var _is_frozen: bool = false
var _is_holding_item: bool = false

@export_group("Combat")
@export var max_health: int = 30
@export var knockback_force: float = 5.0
@export var knockback_duration: float = 0.2
@export var invincibility_duration: float = 0.5
@export var hurt_flash_duration: float = 0.15
@export var hurt_blink_speed: float = 0.1


@export_group("Hurt Feedback")
@export var hurt_sounds: Array[AudioStream] = []
@export var hurt_volume_db: float = -2.0
@export var hurt_pitch_variation: float = 0.08
@export var hurt_hitstop_duration: float = 0.12   ## kräftiger als Standard-Treffer (0.15 default)
@export var hurt_shake_intensity: float = 0.12    ## deutlich stärker als hit_effect (0.03)
@export var hurt_shake_duration: float = 0.3
@export var hurt_zoom_amount: float = 2.5         ## kurzer Punch-In bei Treffer
@export var hurt_zoom_duration: float = 0.25

@export_group("Fall Recovery")
@export var fall_hp_loss_percent: float = 0.1  # 10%
@export var safe_position_update_interval: float = 0.2
@export var fall_respawn_invincibility: float = 1.5
@export var drown_duration: float = 0.7
@export var drown_flip_interval: float = 0.1
@export var drown_frame: int = 92
@export var splash_vfx_scene: PackedScene

var _last_safe_position: Vector3
var _safe_position_timer: float = 0.0

var _is_drowning: bool = false
var _drown_timer: float = 0.0
var _drown_flip_timer: float = 0.0
var _drown_flip_state: bool = false

@export_group("LevelUpNotification")
@export var levelup_popup_scene: PackedScene
@onready var head_anchor: Marker3D = $HeadAnchor

@onready var sword_spin: SwordSpinComponent = $SwordSpinComponent

var _nearby_npc: NPC = null
var _nearby_chest: TreasureChest = null

var hud: Node = null
var _health: int
var _knockback_velocity: Vector3 = Vector3.ZERO
var _knockback_timer: float = 0.0
var _invincibility_timer: float = 0.0
var _is_knocked_back: bool = false
var _is_hurt_flashing: bool = false
var _hurt_flash_timer: float = 0.0

var _is_launched: bool = false
var _launch_left_ground: bool = false
var _launch_vel: Vector3 = Vector3.ZERO

var _footstep_timer: float = 0.0

const HURT_DOWN_LEFT: int = 61
const HURT_UP_RIGHT: int = 70

@export var SPRITE_FACES_RIGHT: bool = true


const DEATH_FRAME_1: int = 78
const DEATH_FRAME_2: int = 79
const DEATH_FRAME_3: int = 80

const DEATH_FRAME_1_DURATION: float = 0.2
const DEATH_FRAME_2_DURATION: float = 0.6
const DEATH_GAME_OVER_DELAY: float = 2.0

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

var _consumable_cooldown: float = 0.0
const CONSUMABLE_COOLDOWN_TIME: float = 0.5

var _hotbar_held: Array[bool] = [false, false, false, false]
var _vector_anchor_slot: int = -1

var _safe_position_locked: bool = false



# ─── Node References ───
@onready var character: LayeredPixelSprite3D = $charactersprite
@onready var dodge_component: DodgeComponent = $DodgeComponent
@onready var vector_anchor: VectorAnchorComponent = $VectorAnchorComponent
@onready var sword: SwordComponent = $SwordComponent


func _ready() -> void:
	add_to_group("player")
	_last_safe_position = global_position
	#GOD-MODE
	#GameManager.player_data.add_exp(99999999)
	safe_margin = 0.005
	floor_snap_length = 0.2
	max_slides = 6

	if character:
		character.hframes = HFRAMES
		character.vframes = VFRAMES
	_show_idle()

	call_deferred("_connect_to_player_data")


func _connect_to_player_data() -> void:
	await get_tree().process_frame

	if GameManager == null:
		push_error("GameManager not found!")
		return
	if GameManager.player_data == null:
		push_error("PlayerData not initialized!")
		return

	var pd: PlayerData = GameManager.player_data

	if not pd.level_changed.is_connected(_on_level_changed):
		pd.level_changed.connect(_on_level_changed)
	if not pd.hp_changed.is_connected(_on_hp_changed):
		pd.hp_changed.connect(_on_hp_changed)

	_update_hud()




func _update_hud() -> void:
	var found_hud = get_tree().get_first_node_in_group("hud")
	if found_hud:
		var pd: PlayerData = GameManager.player_data
		found_hud.update_hp(pd.current_hp, pd.max_hp)
		found_hud.update_exp(pd.current_exp, pd.exp_to_next_level)
		found_hud.set_level(pd.level)
		found_hud.update_gold(pd.gold)


func _on_hp_changed(current: int, maximum: int) -> void:
	var found_hud = get_tree().get_first_node_in_group("hud")
	if found_hud:
		found_hud.animate_hp_change(current)


func _on_level_changed(new_level: int) -> void:
	if GameManager.is_loading:
		return
	_spawn_levelup_popup(new_level)


func _exit_tree() -> void:
	if GameManager.player_data.level_changed.is_connected(_on_level_changed):
		GameManager.player_data.level_changed.disconnect(_on_level_changed)


func _spawn_levelup_popup(new_level: int) -> void:
	if levelup_popup_scene == null:
		push_warning("levelup_popup_scene ist nicht gesetzt.")
		return

	var popup := levelup_popup_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(popup)
	popup.global_position = head_anchor.global_position

	var label: Label3D = popup.get_node_or_null("Label3D")
	if label:
		label.text = "Level Up!"

	var anim_player: AnimationPlayer = popup.get_node_or_null("AnimationPlayer")
	if anim_player:
		anim_player.play("pop")
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


# ─── Main Loop ───

func _physics_process(delta: float) -> void:
	if _is_drowning:
		_process_drowning(delta)
		return
	
	
	if _is_dead:
		_process_death(delta)
		return
		
	if _is_launched:
		_process_launch(delta)
		return

	if GameManager and GameManager.player_data:
		GameManager.player_data.process_regeneration(delta)
		
	_update_hand_visibility() 

	if sword_spin and sword_spin.is_spinning():
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return
	
	if dodge_component and dodge_component.is_dodging():
		# Während Dodge: Schwert-Taste prüfen → Spin-Combo
		_check_sword_spin_input()
		move_and_slide()
		return

	if vector_anchor and vector_anchor.is_active():
		if vector_anchor.is_launching():
			_check_chain_input()
			_check_dive_strike_input()
			return
		elif vector_anchor.is_hanging() or vector_anchor.is_diving():
			return
		else:
			# CHARGING: Release prüfen, aber gedrosselt weiterlaufen lassen
			_check_vector_anchor_release()
			_do_charge_movement(delta)
			return

	if sword:
		sword.process_attack(delta)

	if _is_frozen:
		return

	if _consumable_cooldown > 0.0:
		_consumable_cooldown -= delta

	_update_nearby_npc()

	_process_hotbar_input()
	_process_invincibility(delta)

	if _is_knocked_back:
		_process_knockback(delta)
		return


	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir.length_squared() > 0.01:
		input_dir = input_dir.normalized()

	var yaw: float = $SpringArm3D.rotation.y
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var world_dir: Vector3 = (right * input_dir.x + forward * input_dir.y).normalized()

	# ─── Movement: Sword übernimmt während Angriff ───
	if sword and sword.is_attacking():
		var attack_vel: Vector3 = sword.get_attack_velocity()
		velocity.x = attack_vel.x
		velocity.z = attack_vel.z
	else:
		if world_dir != Vector3.ZERO:
			velocity.x = world_dir.x * SPEED
			velocity.z = world_dir.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0.0, SPEED)
			velocity.z = move_toward(velocity.z, 0.0, SPEED)

	_recover_from_stuck()
	
	move_and_slide()
	
	_update_safe_position(delta)

	# ─── Animation: Sword setzt Frames während Angriff ───
	if sword and sword.is_attacking():
		pass  # SwordComponent setzt die Frames direkt
	else:
		_update_animation(input_dir, delta)


func _do_charge_movement(delta: float) -> void:
	# Schwerkraft beibehalten (falls auf Slope/in Luft)
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Input lesen — identisch zur normalen Bewegung
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir.length_squared() > 0.01:
		input_dir = input_dir.normalized()

	# Kamera-relative Weltrichtung über SpringArm-Yaw
	var yaw: float = $SpringArm3D.rotation.y
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var world_dir: Vector3 = (right * input_dir.x + forward * input_dir.y).normalized()

	# Gedrosselte Geschwindigkeit
	var speed: float = SPEED * vector_anchor.get_charge_move_factor()

	if world_dir != Vector3.ZERO:
		velocity.x = world_dir.x * speed
		velocity.z = world_dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	# Blickrichtung eingefroren halten — das Component setzt den Frame selbst
	_last_dir_mode = vector_anchor.get_charge_locked_dir_mode()

	move_and_slide()
	
# ─── Vector Anchor ───

func _check_vector_anchor_release() -> void:
	if Input.is_action_just_released("hotbar_w"):
		_try_release_vector_anchor(0)
	elif Input.is_action_just_released("hotbar_a"):
		_try_release_vector_anchor(1)
	elif Input.is_action_just_released("hotbar_s"):
		_try_release_vector_anchor(2)
	elif Input.is_action_just_released("hotbar_d"):
		_try_release_vector_anchor(3)
		
func _check_dive_strike_input() -> void:
	var slot: int = -1
	if Input.is_action_just_pressed("hotbar_w"): slot = 0
	elif Input.is_action_just_pressed("hotbar_a"): slot = 1
	elif Input.is_action_just_pressed("hotbar_s"): slot = 2
	elif Input.is_action_just_pressed("hotbar_d"): slot = 3
	
	if slot < 0:
		return
	
	var inv: Node = get_node_or_null("/root/InventoryManager")
	if inv == null:
		return
	var item_id: String = inv.get_hotbar_item(slot)
	if item_id == "":
		return
	var item_data: ItemData = inv.get_item_data(item_id)
	if item_data == null or item_data.item_type != ItemData.ItemType.WEAPON:
		return
	
	if vector_anchor:
		if vector_anchor.try_dive_strike():
			_update_hand_visibility() 

func _check_chain_input() -> void:
	if vector_anchor == null:
		return

	var inv: Node = get_node_or_null("/root/InventoryManager")
	if inv == null:
		return

	# Slot finden, der den Vector Anchor trägt
	var anchor_slot: int = -1
	for slot in range(4):
		var item_id: String = inv.get_hotbar_item(slot)
		if item_id == "":
			continue
		var item_data: ItemData = inv.get_item_data(item_id)
		if item_data != null \
		and item_data.item_type == ItemData.ItemType.EQUIPMENT \
		and item_data.effect_action == "vector_anchor":
			anchor_slot = slot
			break

	if anchor_slot < 0:
		return

	var action_name: String = ""
	match anchor_slot:
		0: action_name = "hotbar_w"
		1: action_name = "hotbar_a"
		2: action_name = "hotbar_s"
		3: action_name = "hotbar_d"

	if action_name != "" and Input.is_action_just_pressed(action_name):
		if vector_anchor.try_chain_launch():
			_update_hand_visibility()

func _check_sword_spin_input() -> void:
	if sword_spin == null or sword_spin.is_spinning():
		return
	
	var slot: int = -1
	if Input.is_action_just_pressed("hotbar_w"): slot = 0
	elif Input.is_action_just_pressed("hotbar_a"): slot = 1
	elif Input.is_action_just_pressed("hotbar_s"): slot = 2
	elif Input.is_action_just_pressed("hotbar_d"): slot = 3
	
	if slot < 0:
		return
	
	# Nur bei Schwert-Slots reagieren
	var inv: Node = get_node_or_null("/root/InventoryManager")
	if inv == null:
		return
	var item_id: String = inv.get_hotbar_item(slot)
	if item_id == "":
		return
	var item_data: ItemData = inv.get_item_data(item_id)
	if item_data == null or item_data.item_type != ItemData.ItemType.WEAPON:
		return
	
	sword_spin.try_start_spin()

func _try_release_vector_anchor(slot_index: int) -> void:
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


# ─── NPC / Chest ───

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


func can_interact_with_npc() -> bool:
	return _nearby_npc != null and _nearby_npc.can_interact()


func can_interact_with_chest() -> bool:
	return _nearby_chest != null and _nearby_chest.can_interact()


# ─── Death ───

func reset_death_state() -> void:
	_is_dead = false
	_death_phase = 0
	_death_anim_time = 0.0
	_is_knocked_back = false
	_is_hurt_flashing = false
	character.modulate = Color.WHITE
	character.modulate.a = 1.0

	if dodge_component:
		dodge_component._is_dodging = false
		dodge_component._dodge_cooldown_timer = 0.0
	if vector_anchor:
		vector_anchor.cancel()
	if sword:
		sword.cancel()

	_show_idle()


func _die() -> void:
	if _is_dead:
		return

	_is_dead = true
	_death_phase = 0
	_death_anim_time = 0.0

	velocity = Vector3.ZERO
	_is_knocked_back = false
	_is_hurt_flashing = false

	if sword:
		sword.cancel()
	if vector_anchor:
		vector_anchor.cancel()

	GameOverScreen.show_game_over(DEATH_GAME_OVER_DELAY)


func _process_death(delta: float) -> void:
	_death_anim_time += delta
	match _death_phase:
		0:
			character.frame = DEATH_FRAME_1
			if _death_anim_time >= DEATH_FRAME_1_DURATION:
				_death_phase = 1
				_death_anim_time = 0.0
		1:
			character.frame = DEATH_FRAME_2
			if _death_anim_time >= DEATH_FRAME_2_DURATION:
				_death_phase = 2
				_death_anim_time = 0.0
		2:
			character.frame = DEATH_FRAME_3


# ─── Damage / Knockback ───

func take_damage(amount: int, from_position: Vector3) -> void:
	if dodge_component and dodge_component.is_dodging():
		return
	if vector_anchor and vector_anchor.is_launching():
		return
	if _invincibility_timer > 0.0:
		return
	if vector_anchor and vector_anchor.is_charging():
		vector_anchor.cancel()

	GameManager.player_data.take_damage(amount)

	var knockback_dir := (global_position - from_position).normalized()
	knockback_dir.y = 0
	_knockback_velocity = knockback_dir * knockback_force
	_knockback_timer = knockback_duration
	_is_knocked_back = true
	_invincibility_timer = invincibility_duration

	_is_hurt_flashing = true
	_hurt_flash_timer = hurt_flash_duration

	if sword and sword.is_attacking():
		sword.cancel()

	_play_hurt_feedback()

	if not GameManager.player_data.is_alive():
		_die()

func _play_hurt_feedback() -> void:
	# SFX über AudioPool (konsistent mit Footsteps/Sword)
	if not hurt_sounds.is_empty():
		AudioPool.play_3d(
			hurt_sounds.pick_random(),
			global_position,
			hurt_volume_db,
			randf_range(1.0 - hurt_pitch_variation, 1.0 + hurt_pitch_variation)
		)

	if not GameEffects:
		return

	# Player-Treffer: kräftiger als der Standard-hit_effect bei Gegner-Treffern.
	GameEffects.hitstop(hurt_hitstop_duration)
	GameEffects.shake(hurt_shake_intensity, hurt_shake_duration)
	GameEffects.zoom(hurt_zoom_amount, hurt_zoom_duration)


func is_alive() -> bool:
	return not _is_dead and GameManager.player_data.is_alive()


func get_health() -> int:
	return _health


func _process_invincibility(delta: float) -> void:
	if _is_hurt_flashing:
		_hurt_flash_timer -= delta
		character.modulate = Color(1.5, 0.5, 0.5)
		if _hurt_flash_timer <= 0.0:
			_is_hurt_flashing = false
			character.modulate = Color.WHITE

	if _invincibility_timer > 0.0:
		_invincibility_timer -= delta
		if not _is_hurt_flashing:
			var blink := fmod(_invincibility_timer, hurt_blink_speed * 2.0) < hurt_blink_speed
			character.modulate.a = 0.3 if blink else 1.0
		if _invincibility_timer <= 0.0:
			character.modulate = Color.WHITE
			character.modulate.a = 1.0

func _recover_from_stuck() -> void:
	var params := PhysicsTestMotionParameters3D.new()
	params.from = global_transform
	params.motion = Vector3.ZERO
	params.margin = 0.001  # sehr kleiner Test-Margin

	var result := PhysicsTestMotionResult3D.new()

	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		var depth := result.get_collision_depth()
		# Nur eingreifen wenn wirklich tief steckt (verhindert false positives)
		if depth > 0.002:
			global_position += result.get_collision_normal() * depth

func _process_knockback(delta: float) -> void:
	_knockback_timer -= delta
	velocity.x = _knockback_velocity.x
	velocity.z = _knockback_velocity.z
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, knockback_force * 2.0 * delta)

	var hurt_data := _get_hurt_frame()
	character.frame = hurt_data.frame
	character.flip_h = hurt_data.flip

	if _knockback_timer <= 0.0:
		_is_knocked_back = false
		_knockback_velocity = Vector3.ZERO

	if not is_on_floor():
		velocity.y -= gravity * delta
		
	_recover_from_stuck()
	
	move_and_slide()

func launch_airborne(dir: Vector3, h_force: float, up_force: float) -> void:
	if _is_dead or _is_drowning:
		return
	if sword and sword.is_attacking():
		sword.cancel()
	if vector_anchor and vector_anchor.is_active():
		vector_anchor.cancel()
	_is_knocked_back = false
	_knockback_velocity = Vector3.ZERO
	var d := dir
	d.y = 0.0
	if d.length() < 0.001:
		d = -global_transform.basis.z
	d = d.normalized()
	_launch_vel = d * h_force + Vector3.UP * up_force
	_launch_left_ground = false
	_is_launched = true

func _process_launch(delta: float) -> void:
	# eigene Velocity, unabhängig von externem Zeroing (set_frozen, _bounce_off_dive)
	_launch_vel.y -= gravity * delta
	velocity = _launch_vel
	#var hd := _get_hurt_frame()
	character.frame = 93
	#character.flip_h = hd.flip
	_recover_from_stuck()
	move_and_slide()
	if not is_on_floor():
		_launch_left_ground = true
	elif _launch_left_ground:
		_is_launched = false
		_is_knocked_back = false
		_knockback_velocity = Vector3.ZERO
		velocity = Vector3.ZERO

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


# ─── Direction / Animation ───

func _get_direction_from_input(dir: Vector2) -> int:
	if dir == Vector2.ZERO:
		return _last_dir_mode

	var angle: float = dir.angle()
	var deg: float = rad_to_deg(angle)
	if deg < 0:
		deg += 360.0

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

func _animate_walk_8dir(delta: float) -> void:
	_anim_time += delta

	_footstep_timer -= delta
	if _footstep_timer <= 0.0:
		_play_footstep_sound()
		_footstep_timer = footstep_interval

	var frames: Array[int] = []
	var flip: bool = false

	match _last_dir_mode:
		DirMode.DOWN:
			frames = DOWN_WALK_FRAMES

		DirMode.UP:
			frames = UP_WALK_FRAMES

		DirMode.LEFT:
			frames = LEFT_WALK_FRAMES

		DirMode.RIGHT:
			frames = LEFT_WALK_FRAMES
			flip = true

		DirMode.DOWN_LEFT:
			frames = DOWN_LEFT_WALK_FRAMES

		DirMode.DOWN_RIGHT:
			frames = DOWN_LEFT_WALK_FRAMES
			flip = true

		DirMode.UP_RIGHT:
			frames = UP_RIGHT_WALK_FRAMES

		DirMode.UP_LEFT:
			frames = UP_RIGHT_WALK_FRAMES
			flip = true

		_:
			frames = DOWN_WALK_FRAMES

	if frames.is_empty():
		_show_idle()
		return

	var frame_index: int = int(floor(_anim_time * WALK_FPS)) % frames.size()

	character.frame = frames[frame_index]
	character.flip_h = flip



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
	var idle_frame: int
	var flip: bool = false

	match _last_dir_mode:
		DirMode.DOWN:
			idle_frame = DOWN_IDLE_FRAME
		DirMode.UP:
			idle_frame = UP_IDLE_FRAME
		DirMode.LEFT:
			idle_frame = LEFT_IDLE_FRAME
		DirMode.RIGHT:
			idle_frame = LEFT_IDLE_FRAME
			flip = true
		DirMode.DOWN_LEFT:
			idle_frame = DOWN_LEFT_IDLE_FRAME
		DirMode.DOWN_RIGHT:
			idle_frame = DOWN_LEFT_IDLE_FRAME
			flip = true
		DirMode.UP_RIGHT:
			idle_frame = UP_RIGHT_IDLE_FRAME
		DirMode.UP_LEFT:
			idle_frame = UP_RIGHT_IDLE_FRAME
			flip = true
		_:
			idle_frame = DOWN_IDLE_FRAME

	character.frame = idle_frame
	character.flip_h = flip


# ─── Hotbar / Items ───

func _process_hotbar_input() -> void:
	if _is_dead:
		return

	var dialogue_manager: Node = get_node_or_null("/root/DialogueManager")
	if dialogue_manager:
		if dialogue_manager.is_dialogue_active() or dialogue_manager.is_on_cooldown():
			return

	if get_tree().paused:
		return

	if Input.is_action_just_pressed("hotbar_w"):
		if _nearby_npc and _nearby_npc.can_interact():
			_nearby_npc.interact()
			return
		if _nearby_chest and _nearby_chest.can_interact():
			_nearby_chest.interact()
			return
		_use_hotbar_slot_with_combo(0)

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
		return

	var item_data: ItemData = inv_manager.get_item_data(item_id)
	if item_data == null:
		return
		
	if item_data.item_type != ItemData.ItemType.WEAPON and _is_action_locked():
		return

	match item_data.item_type:
		ItemData.ItemType.WEAPON:
			# ─── Waffe an SwordComponent delegieren ───
			if sword:
				sword.equip_weapon(item_id)
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
	if sword == null:
		return

	# Richtung bestimmen
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):    dir.y -= 1
	if Input.is_action_pressed("move_down"):  dir.y += 1
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1

	if sword.is_attacking():
		sword.buffer_combo(_get_direction_from_input(dir))
	else:
		# Richtung für Angriff updaten
		if dir != Vector2.ZERO:
			_last_dir_mode = _get_direction_from_input(dir)
			match _last_dir_mode:
				DirMode.RIGHT, DirMode.DOWN_RIGHT, DirMode.UP_RIGHT:
					_facing_right = true
				DirMode.LEFT, DirMode.DOWN_LEFT, DirMode.UP_LEFT:
					_facing_right = false

		sword.try_attack(_last_dir_mode)


func can_attack() -> bool:
	return _nearby_npc == null or not _nearby_npc.can_interact()


func _use_equipment(item_id: String, item_data: ItemData) -> void:
	match item_data.effect_action:
		"dodge":
			if dodge_component:
				dodge_component.try_dodge()
		"vector_anchor":
			if vector_anchor and not vector_anchor.is_active():
				_update_equipment_overlay(item_id, item_data)
				vector_anchor.start_charging()
				_update_hand_visibility() 
		_:
			pass

func lock_safe_position() -> void:
	_safe_position_locked = true

func unlock_safe_position() -> void:
	_safe_position_locked = false


func _update_safe_position(delta: float) -> void:
	if _safe_position_locked:   # ← NEU
		return
	if not is_on_floor():
		return
	if _is_knocked_back or _is_hurt_flashing:
		return
	if dodge_component and dodge_component.is_dodging():
		return
	if vector_anchor and vector_anchor.is_active():
		return
	if sword_spin and sword_spin.is_spinning():
		return
	if _is_standing_on_unsafe_floor():   # ← NEU
		return

	_safe_position_timer -= delta
	if _safe_position_timer <= 0.0:
		_last_safe_position = global_position
		_safe_position_timer = safe_position_update_interval

func _is_standing_on_unsafe_floor() -> bool:
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider and collider.is_in_group("unsafe_floor"):
			return true
	return false

func respawn_after_fall() -> void:
	if _is_dead or _is_drowning:
		return

	_is_drowning = true
	_drown_timer = drown_duration
	_drown_flip_timer = 0.0
	_drown_flip_state = false

	velocity = Vector3.ZERO
	_knockback_velocity = Vector3.ZERO
	_is_knocked_back = false
	_knockback_timer = 0.0
	
	# Aktive States abbrechen
	if vector_anchor and vector_anchor.is_active():
		vector_anchor.cancel()
	if sword and sword.is_attacking():
		sword.cancel()
	if sword_spin and sword_spin.is_spinning():
		sword_spin.cancel() if sword_spin.has_method("cancel") else null
	
	# Sprite auf Drown-Pose
	character.frame = drown_frame
	character.modulate = Color.WHITE
	character.modulate.a = 1.0
	
	_spawn_splash_vfx()
	
func _process_drowning(delta: float) -> void:
	_drown_timer -= delta
	
	# Flackernd gespiegeltes Flailing
	_drown_flip_timer -= delta
	if _drown_flip_timer <= 0.0:
		_drown_flip_state = not _drown_flip_state
		character.flip_h = _drown_flip_state
		_drown_flip_timer = drown_flip_interval
	
	if _drown_timer <= 0.0:
		_finish_drowning()
	
func _finish_drowning() -> void:
	_is_drowning = false

	var pd: PlayerData = GameManager.player_data
	var damage_amount: int = maxi(1, int(pd.max_hp * fall_hp_loss_percent))
	pd.take_damage(damage_amount)

	if not pd.is_alive():
		_die()
		return

	# Teleport an sichere Position
	global_position = _last_safe_position
	velocity = Vector3.ZERO

	# Invincibility nach Respawn
	_invincibility_timer = fall_respawn_invincibility
	_is_hurt_flashing = true
	_hurt_flash_timer = hurt_flash_duration

	# Kurzer Fade-In
	character.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(character, "modulate:a", 1.0, 0.3)

	_show_idle()
	unlock_safe_position()  
	
func _spawn_splash_vfx() -> void:
	if splash_vfx_scene == null:
		_spawn_inline_splash()  # dein bestehender Fallback
		return

	var splash := splash_vfx_scene.instantiate()
	get_tree().current_scene.add_child(splash)

	# Splash sitzt auf der Wasseroberfläche am Eintauchpunkt.
	# global_position des Players = Eintauchpunkt (Player steht im Wasser).
	var impact_point := global_position
	impact_point.y += 0.15 

	if splash.has_method("play"):
		# WaterSplash-API: Eintauchen = direction +1
		splash.global_position = impact_point
		splash.play(impact_point, 1.0, 1.0)
	else:
		# Fallback für Fremd-Scenes: alte Logik
		splash.global_position = impact_point
		for child in splash.get_children():
			if child is GPUParticles3D:
				child.emitting = true

	# Aufräumen nach Lebensdauer (bei nicht-gepoolter Scene)
	get_tree().create_timer(2.0).timeout.connect(splash.queue_free)

func _spawn_inline_splash() -> void:
	# Fallback ohne Scene — minimaler Splash aus Code
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 16
	particles.lifetime = 0.6

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 3.5
	mat.gravity = Vector3(0, -8, 0)
	mat.scale_min = 0.08
	mat.scale_max = 0.18
	mat.color = Color(0.6, 0.85, 1.0, 0.9)
	particles.process_material = mat

	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	particles.draw_pass_1 = sphere

	get_tree().current_scene.add_child(particles)
	particles.global_position = global_position

	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)

func _use_consumable(item_id: String, item_data: ItemData, inv_manager: Node) -> void:
	if _consumable_cooldown > 0.0:
		return
	if sword and sword.is_attacking():
		return
	if not item_data.usable:
		return

	if inv_manager.use_item(item_id):
		_consumable_cooldown = CONSUMABLE_COOLDOWN_TIME
		_show_item_use_effect(item_data)


func _use_key_item(item_id: String, item_data: ItemData) -> void:
	if item_data.effect_action != "":
		var inv_manager: Node = get_node_or_null("/root/InventoryManager")
		if inv_manager:
			inv_manager._execute_effect_action(item_data.effect_action)


# ─── Equipment Overlay (Vector Anchor etc.) ───

func _update_equipment_overlay(item_id: String, item_data: ItemData) -> void:
	if character == null:
		return
	var layer_key: String = item_data.effect_action if item_data.effect_action != "" else "equipment"
	if item_data.get("overlay_texture") != null:
		character.set_layer(layer_key, item_data.overlay_texture)
	else:
		character.remove_layer(layer_key)


func clear_all_overlays() -> void:
	if character:
		character.clear_overlays()


# ─── Visual Effects ───

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

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.0
	mat.gravity = Vector3(0, -1, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.6
	mat.color = Color(0.3, 1.0, 0.4, 1.0)
	particles.process_material = mat

	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	particles.draw_pass_1 = sphere

	particles.global_position = global_position + Vector3(0, 0.5, 0)
	get_tree().current_scene.add_child(particles)

	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)
	
func apply_knockback(from_position: Vector3, force: float = -1.0) -> void:
	# Reiner Rückstoß ohne Schaden (z.B. Schwert prallt an Boss-Rüstung ab)
	if _is_dead or _is_drowning:
		return
	if dodge_component and dodge_component.is_dodging():
		return
	var dir := global_position - from_position
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var f := force if force > 0.0 else knockback_force
	_knockback_velocity = dir * f
	_knockback_timer = knockback_duration
	_is_knocked_back = true
	if sword and sword.is_attacking():
		sword.cancel()


func _play_footstep_sound() -> void:
	if footstep_sounds.is_empty():
		return
	AudioPool.play_3d(
		footstep_sounds.pick_random(),
		global_position,
		footstep_volume_db,
		randf_range(1.0 - footstep_pitch_variation, 1.0 + footstep_pitch_variation)
	)


# ─── Public Getters (Kompatibilität) ───

func get_equipped_weapon() -> String:
	if sword:
		return sword.get_equipped_weapon_id()
	return ""


func get_equipped_weapon_data() -> ItemData:
	if sword:
		return sword.get_equipped_weapon_data()
	return null
	
# ─── Item Hold (Pickup-Animation) ───

func show_item_hold() -> void:
	_is_holding_item = true
	set_frozen(true)
	if sword:
		sword.cancel()
	if character:
		character.frame = item_hold_frame
		# Hand-Layer ausblenden — das Item soll sauber angezeigt werden
		_update_hand_visibility()


func hide_item_hold() -> void:
	_is_holding_item = false
	set_frozen(false)
	_update_hand_visibility()


func _update_hand_visibility() -> void:
	if character == null:
		return
		
	if _is_frozen:
		return
	
	var is_dive_phase: bool = vector_anchor != null and (vector_anchor.is_hanging() or vector_anchor.is_diving())
	var show_vector_anchor: bool = vector_anchor != null and vector_anchor.is_active() and not is_dive_phase
	
	if character.has_layer("weapon"):
		character.set_layer_visible("weapon", not show_vector_anchor and not _is_holding_item)
	
	if character.has_layer("vector_anchor"):
		character.set_layer_visible("vector_anchor", show_vector_anchor and not _is_holding_item)
		
		
func _is_action_locked() -> bool:
	if sword and sword.is_attacking():
		return true
	if sword_spin and sword_spin.is_spinning():
		return true
	if dodge_component and dodge_component.is_active_dodge():
		return true
	if vector_anchor and vector_anchor.is_active():
		return true
	return false
		
		
# CINEMATICS


var _cinematic_mode: bool = false

func set_cinematic_mode(active: bool) -> void:
	_cinematic_mode = active
	if active:
		if sword and sword.has_method("cancel") and sword.is_attacking(): sword.cancel()
		if vector_anchor and vector_anchor.is_active(): vector_anchor.cancel()
		velocity = Vector3.ZERO
		_is_knocked_back = false
		set_frozen(true)
	else:
		set_frozen(false)

func cinematic_face(world_dir: Vector3) -> void:
	if world_dir.length_squared() < 0.0001: return
	var dir2: Vector2
	var spring_arm := get_node_or_null("SpringArm3D")
	if spring_arm:
		var yaw: float = spring_arm.rotation.y
		var forward := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		dir2 = Vector2(world_dir.dot(right), world_dir.dot(forward)).normalized()
	else:
		dir2 = Vector2(world_dir.x, world_dir.z).normalized()
	_last_dir_mode = _get_direction_from_input(dir2)
	match _last_dir_mode:
		DirMode.RIGHT, DirMode.DOWN_RIGHT, DirMode.UP_RIGHT:
			_facing_right = true
		DirMode.LEFT, DirMode.DOWN_LEFT, DirMode.UP_LEFT:
			_facing_right = false
	_show_idle()

func cinematic_show_frame(frame: int, flip_h: bool = false) -> void:
	if character:
		character.frame = frame
		character.flip_h = flip_h

func cinematic_tween_to(target: Vector3, duration: float) -> Tween:
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", target, duration)
	return t

func cinematic_sword_attack(idx: int) -> void:
	# Schwert-Component triggern; passe den Methodennamen ggf. an
	if sword and sword.has_method("try_attack"):
		sword.try_attack(_last_dir_mode)

func cinematic_jump_back(direction: Vector3, h_force: float = 7.0, up_force: float = 5.0) -> void:
	if direction.length_squared() < 0.0001: return
	launch_airborne(direction.normalized(), h_force, up_force)

func cinematic_walk_to(target: Vector3, speed: float, anim_speed_scale: float = 1.0) -> void:
	var start := global_position
	var flat := target - start
	flat.y = 0.0
	if flat.length() < 0.001:
		return
 
	cinematic_face(flat.normalized())
	var dist := flat.length()
	var duration := dist / maxf(speed, 0.01)
 
	_is_moving = true
	_anim_time = 0.0
	var elapsed := 0.0
	while elapsed < duration:
		var dt := get_process_delta_time()
		elapsed += dt
		var k: float = clampf(elapsed / duration, 0.0, 1.0)
		var e: float = k * k * (3.0 - 2.0 * k)
		global_position = start.lerp(target, e)
		_animate_walk_8dir(dt * anim_speed_scale)
		await get_tree().process_frame
 
	global_position = target
	_is_moving = false
	_anim_time = 0.0
	_show_idle()
 
 
# --- Silhouette: Sprite stark abdunkeln / wiederherstellen -----------
func cinematic_set_dark(color: Color) -> void:
	if character:
		character.modulate = color
 
func cinematic_restore_color() -> void:
	if character:
		character.modulate = Color.WHITE
		character.modulate.a = 1.0
 
 
# --- Cutscene-Sprite (z.B. Robe) -------------------------------------
var _saved_cutscene_base: Texture2D = null
 
func cinematic_set_texture(tex: Texture2D) -> void:
	if character == null or tex == null:
		return
	var base_layer := character.get_layer("base") if character.has_layer("base") else null
	if base_layer:
		_saved_cutscene_base = base_layer.texture
	character.set_layer("base", tex, 0)
	if character.has_layer("weapon"):
		character.set_layer_visible("weapon", false)
	if character.has_layer("vector_anchor"):
		character.set_layer_visible("vector_anchor", false)
 
 
func cinematic_restore_texture() -> void:
	if character == null:
		return
	if _saved_cutscene_base:
		character.set_layer("base", _saved_cutscene_base, 0)
		_saved_cutscene_base = null
	if character.has_layer("weapon"):
		character.set_layer_visible("weapon", true)
	if character.has_layer("vector_anchor"):
		character.set_layer_visible("vector_anchor", true)

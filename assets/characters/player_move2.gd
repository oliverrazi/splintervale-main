extends CharacterBody3D

# --- Slash VFX ---
@export_group("Slash VFX")
@export var slash_scene: PackedScene            # Scene für den Slash-Effekt
@export var slash_lifetime: float = 0.4        # Lebensdauer des Effekts
@export var dissolve_duration := 0.0


var _slash_spawned_this_attack: bool = false    # pro Angriffsschritt nur ein Slash

@export_group("Controls")
# --- Steuerung & Physik ---
@export var SPEED: float = 50.0
@export var JUMP_VELOCITY: float = 4.5

# --- Spritesheet-Layout ---
@export var HFRAMES: int = 9           # 9 Spalten
@export var VFRAMES: int = 9           # 9 Zeilen

# --- Animationsgeschwindigkeit ---
@export var WALK_FPS: float = 8.0      # Laufen
@export var ATTACK_FPS: float = 10.0   # Angriffe
@export var ATTACK_MOVE_SPEED: float = 1.0      # Stärke des Vorschubs
@export var ATTACK_LAST_FRAME_HOLD: float = 0.15 # Extra-Zeit für letzten Frame (Sekunden)
@export var ATTACK_COOLDOWN: float = 0.25       # Pause nach Ende des Angriffs (Sekunden)

# --- Frames im 9x9-Sheet ---
# Unten
@export var DOWN_IDLE_FRAME: int = 0         # unten stehen
@export var DOWN_RUN_START_FRAME: int = 1    # unten laufen von 1...
@export var DOWN_RUN_END_FRAME: int = 6      # ...bis 6

# Oben
@export var UP_IDLE_FRAME: int = 9           # oben stehen
@export var UP_RUN_START_FRAME: int = 10     # oben laufen von 10...
@export var UP_RUN_END_FRAME: int = 15       # ...bis 15

# Seitlich (links/rechts)
@export var SIDE_IDLE_FRAME: int = 18        # seitlich Idle
@export var SIDE_RUN_START_FRAME: int = 19   # seitlich laufen von 19...
@export var SIDE_RUN_END_FRAME: int = 24     # ...bis 24

# --- Attack-Kombos (Frames) ---
const ATTACK_DOWN_1: Array[int] = [27, 27, 29]
const ATTACK_DOWN_2: Array[int] = [30, 30, 32]
const ATTACK_DOWN_3: Array[int] = [39, 39, 32]

const ATTACK_UP_1: Array[int] = [36, 36, 38]
const ATTACK_UP_2: Array[int] = [39, 39, 41]
const ATTACK_UP_3: Array[int] = [30, 30, 41] #[42, 42, 37]

const ATTACK_SIDE_1: Array[int] = [45, 45, 47]
const ATTACK_SIDE_2: Array[int] = [48, 48, 50]
const ATTACK_SIDE_3: Array[int] = [48, 48, 50]

const COMBO_SPRITE_FLIP_FRAMES := {
	3: [1],  # 3. Combo: erster Frame (Index 0) gespiegelt
}


# Blickrichtung des Roh-Sprites:
#   true  = Sprite schaut im Sheet nach RECHTS
#   false = Sprite schaut im Sheet nach LINKS
@export var SPRITE_FACES_RIGHT: bool = true

# --- Intern ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _anim_time: float = 0.0            # Zeitakkumulator fürs Laufen
var _is_moving: bool = false
var _facing_right: bool = true         # TRUE = in der Welt nach rechts, FALSE = nach links

# 0 = unten, 1 = oben, 2 = seitlich
var _last_dir_mode: int = 0

# --- Attack-Zustand ---
var _is_attacking: bool = false
var _attack_step: int = 0                  # 0 = kein Angriff, 1..3 = Kombostufe
var _attack_time: float = 0.0
var _attack_can_chain: bool = false        # ob wir ins nächste Combo-Glied dürfen
var _attack_buffered: bool = false         # ob während des Fensters F gedrückt wurde
var _attack_cooldown_timer: float = 0.0    # Cooldown nach Ende

var _current_attack_frames: Array[int] = []
var _current_attack_duration: float = 0.0
var _current_attack_base_duration: float = 0.0   # Dauer bis letzter Frame beginnt

@onready var character: Sprite3D = $charactersprite



func _ready() -> void:
	if character:
		character.hframes = HFRAMES
		character.vframes = VFRAMES
	_show_idle()


func _physics_process(delta: float) -> void:
	# Cooldown runterzählen
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta
		if _attack_cooldown_timer < 0.0:
			_attack_cooldown_timer = 0.0

	# Gravity & Jump
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Eingabe (2D)
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# Angriff-Eingabe behandeln
	_handle_attack_input(input_dir)

	# Weltbewegungsrichtung (3D)
	var world_dir: Vector3 = ($SpringArm3D.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Bewegung anwenden
	if _is_attacking:
		# Während eines Angriffs: kleiner Schritt mit Entschleunigung
		var attack_dir3d: Vector3 = _get_attack_world_dir()
		if attack_dir3d != Vector3.ZERO and _current_attack_duration > 0.0:
			var t: float = clamp(_attack_time, 0.0, _current_attack_duration)
			var progress: float = t / _current_attack_duration    # 0..1
			var move_factor: float = 1.0 - progress               # startet stark, wird schwächer
			move_factor *= move_factor                            # quadratisch abfallend = sanfter
			var strength: float = ATTACK_MOVE_SPEED * move_factor
			velocity.x = attack_dir3d.x * strength
			velocity.z = attack_dir3d.z * strength
	else:
		# Normale Bewegung
		if world_dir != Vector3.ZERO:
			velocity.x = world_dir.x * SPEED
			velocity.z = world_dir.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0.0, SPEED)
			velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()

	# Animationen aktualisieren
	if _is_attacking:
		_update_attack(delta)
	else:
		_update_animation(input_dir, delta)


# ---------- Bewegung / Lauf-Animation ----------

func _update_animation(dir: Vector2, delta: float) -> void:
	_is_moving = dir != Vector2.ZERO

	if _is_moving:
		var horizontal: bool = absf(dir.x) > absf(dir.y)

		if horizontal:
			# Seitwärts – _facing_right = Welt-Richtung
			if dir.x > 0.0:
				_facing_right = true
			elif dir.x < 0.0:
				_facing_right = false

			_last_dir_mode = 2
			_animate_run(SIDE_RUN_START_FRAME, SIDE_RUN_END_FRAME, delta, true)
		else:
			# Vertikal
			if dir.y > 0.0:
				_last_dir_mode = 0   # unten
				_animate_run(DOWN_RUN_START_FRAME, DOWN_RUN_END_FRAME, delta, false)
			elif dir.y < 0.0:
				_last_dir_mode = 1   # oben
				_animate_run(UP_RUN_START_FRAME, UP_RUN_END_FRAME, delta, false)
	else:
		_anim_time = 0.0
		_show_idle()


func _animate_run(start_frame: int, end_frame: int, delta: float, use_side_flip: bool) -> void:
	_anim_time += delta

	var run_frames: int = end_frame - start_frame + 1
	if run_frames <= 0:
		run_frames = 1

	var base: int = int(floor(_anim_time * WALK_FPS)) % run_frames
	var frame_index: int = start_frame + base

	_set_frame(frame_index, use_side_flip, false)


func _show_idle() -> void:
	match _last_dir_mode:
		0:
			_set_frame(DOWN_IDLE_FRAME, false, false)
		1:
			_set_frame(UP_IDLE_FRAME, false, false)
		_:
			_set_frame(SIDE_IDLE_FRAME, true, false)


func _set_frame(frame_index: int, use_side_flip: bool, extra_flip: bool) -> void:
	if not character:
		return

	var flip: bool = false

	if use_side_flip:
		# Horizontales Flip nur seitlich
		if SPRITE_FACES_RIGHT:
			flip = not _facing_right
		else:
			flip = _facing_right
	else:
		flip = false   # oben/unten nicht flippen
		
	if extra_flip:
		flip = not flip

	character.flip_h = flip
	character.frame = frame_index


# ---------- Angriff / Combo-Logik ----------

func _handle_attack_input(dir: Vector2) -> void:
	# Angriffstaste (bitte Input-Action "attack" auf F legen)
	if Input.is_action_just_pressed("attack"):
		if _is_attacking:
			# Während Angriff: Combo buffern, wenn wir im Chain-Fenster sind
			if _attack_can_chain and _attack_step < 3:
				_attack_buffered = true
		else:
			# Neuer Angriff nur, wenn kein Cooldown
			if _attack_cooldown_timer <= 0.0:
				_choose_attack_direction_from_input(dir)
				_start_attack(1)


func _choose_attack_direction_from_input(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		# Kein Input: letzte Richtung beibehalten
		return

	var horizontal: bool = absf(dir.x) > absf(dir.y)

	if horizontal:
		_last_dir_mode = 2
		if dir.x > 0.0:
			_facing_right = true
		elif dir.x < 0.0:
			_facing_right = false
	else:
		if dir.y > 0.0:
			_last_dir_mode = 0   # unten
		elif dir.y < 0.0:
			_last_dir_mode = 1   # oben


func _start_attack(step: int) -> void:
	_is_attacking = true
	_attack_step = step
	_attack_time = 0.0
	_attack_can_chain = false
	_attack_buffered = false
	_slash_spawned_this_attack = false     # Für diesen Angriffsschritt zurücksetzen

	_current_attack_frames = _get_attack_frames_for(_last_dir_mode, _attack_step)
	_current_attack_base_duration = _get_attack_base_duration(_current_attack_frames)
	_current_attack_duration = _get_attack_duration(_current_attack_frames)

	var dir: int = _last_dir_mode
	if _facing_right && _last_dir_mode == 2:
		dir = dir + 1
	
	# Slash-Effekt direkt beim Start dieses Angriffsschritts erzeugen
	var world_pos: Vector3 = _get_slash_spawn_position(dir)
	_spawn_slash_vfx(step, _last_dir_mode, world_pos)




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

	# Ende der gesamten Attack-Animation
	if _attack_time >= _current_attack_duration:
		if _attack_buffered and _attack_step < 3:
			# Nächster Combo-Hit
			_start_attack(_attack_step + 1)
			return
		else:
			_end_attack()
			return

	var frame_duration: float = 1.0 / ATTACK_FPS
	var frame_index_in_array: int = 0
	var frames_count: int = _current_attack_frames.size()

	# Bis kurz vor letztem Frame normal durchsteppen
	if _attack_time < _current_attack_base_duration:
		frame_index_in_array = int(_attack_time / frame_duration)
		if frame_index_in_array < 0:
			frame_index_in_array = 0
		if frame_index_in_array > frames_count - 2:
			frame_index_in_array = frames_count - 2
	else:
		# Letzter Frame wird länger gehalten
		frame_index_in_array = frames_count - 1

	# Chain-Fenster = gesamte Zeit im letzten Frame
	_attack_can_chain = _attack_time >= _current_attack_base_duration

	var frame_index: int = _current_attack_frames[frame_index_in_array]
	var use_side_flip: bool = (_last_dir_mode == 2)
	
	# Prüfen ob dieser Frame in dieser Combo extra gespiegelt werden soll
	var extra_flip: bool = false
	if COMBO_SPRITE_FLIP_FRAMES.has(_attack_step):
		var flip_indices: Array = COMBO_SPRITE_FLIP_FRAMES[_attack_step]
		extra_flip = frame_index_in_array in flip_indices
	
	
	_set_frame(frame_index, use_side_flip, extra_flip)


func _get_attack_frames_for(dir_mode: int, step: int) -> Array[int]:
	if dir_mode == 0:
		# unten
		if step == 1:
			return ATTACK_DOWN_1
		elif step == 2:
			return ATTACK_DOWN_2
		else:
			return ATTACK_DOWN_3
	elif dir_mode == 1:
		# oben
		if step == 1:
			return ATTACK_UP_1
		elif step == 2:
			return ATTACK_UP_2
		else:
			return ATTACK_UP_3
	else:
		# seitlich
		if step == 1:
			return ATTACK_SIDE_1
		elif step == 2:
			return ATTACK_SIDE_2
		else:
			return ATTACK_SIDE_3


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

	if _last_dir_mode == 0:
		dir2 = Vector2(0.0, 1.0)       # unten
	elif _last_dir_mode == 1:
		dir2 = Vector2(0.0, -1.0)      # oben
	else:
		# seitlich -> nach rechts/links in Welt
		if _facing_right:
			dir2 = Vector2(1.0, 0.0)
		else:
			dir2 = Vector2(-1.0, 0.0)

	if dir2 == Vector2.ZERO:
		return Vector3.ZERO

	return ($SpringArm3D.transform.basis * Vector3(dir2.x, 0, dir2.y)).normalized()
	
enum Dir { UP, DOWN, LEFT, RIGHT }

const DIR_YAW_DEG := {
	Dir.RIGHT: 270.0,
	Dir.DOWN:  180.0,
	Dir.LEFT:  90.0,
	Dir.UP:   0.0,
}

const COMBO_SWING_OFFSET_DEG := {
	Dir.UP: {
		0: 10.0,
		1: 20.0,
		2: 20.0,
	},
	Dir.DOWN: {
		0: 10.0,
		1: 0.0,
		2: 0.0,
	},
	Dir.LEFT: {
		0: 10.0,
		1: 20.0,
		2: 20.0,
	},
	Dir.RIGHT: {
		0: -10.0,
		1: -20.0,
		2: -20.0,
	},
}

const COMBO_MIRRORED := {
	Dir.UP: {
		0: true,
		1: false,
		2: false,
	},
	Dir.DOWN: {
		0: true,
		1: false,
		2: false,
	},
	Dir.LEFT: {
		0: true,
		1: false,
		2: false,
	},
	Dir.RIGHT: {
		0: false,
		1: true,
		2: true,
	},
}

func _spawn_slash_vfx(combo_index: int, dir_mode: int, world_pos: Vector3) -> void:
	if slash_scene == null:
		return
	
	var vfx := slash_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = world_pos
	
	var actual_dir: Dir = _dir_mode_to_dir(dir_mode)
	var base_yaw: float = DIR_YAW_DEG.get(actual_dir, 0.0)
	
	var combo_idx: int = combo_index - 1
	var combo_offset: float = COMBO_SWING_OFFSET_DEG.get(actual_dir, {}).get(combo_idx, 0.0)
	
	var pivot: Node3D = vfx.get_node("Node3D")
	pivot.rotation_degrees.y = base_yaw + combo_offset
	
	print(actual_dir)
	# Gespiegelt statt rückwärts: scale.x invertieren
	var is_mirrored: bool = COMBO_MIRRORED.get(actual_dir, {}).get(combo_idx, false)
	if is_mirrored:
		pivot.scale.x = -1.0
	
	# Animation normal abspielen
	var anim_player: AnimationPlayer = vfx.get_node("Node3D/AnimationPlayer")
	if anim_player and anim_player.has_animation("slash"):
		anim_player.play("slash")
	
	_cleanup_vfx(vfx, slash_lifetime)


func _dir_mode_to_dir(dir_mode: int) -> Dir:
	# dir_mode: 0 = unten, 1 = oben, 2 = seitlich
	match dir_mode:
		0:
			return Dir.DOWN
		1:
			return Dir.UP
		2:
			# Seitlich: abhängig von _facing_right
			if _facing_right:
				return Dir.RIGHT
			else:
				return Dir.LEFT
		_:
			return Dir.DOWN


func _cleanup_vfx(vfx: Node3D, lifetime: float) -> void:
	# Optional: Dissolve-Animation vor dem Entfernen
	var mesh: MeshInstance3D = vfx.get_node("Node3D/MeshInstance3D")
	var material: ShaderMaterial = mesh.get_surface_override_material(0)
	if material == null and mesh.mesh:
		material = mesh.mesh.surface_get_material(0)
	
	if material and dissolve_duration > 0.0:
		# Warten bis kurz vor Ende, dann Dissolve starten
		var wait_time: float = max(0.0, lifetime - dissolve_duration)
		var tween := create_tween()
		tween.tween_interval(wait_time)
		tween.tween_property(material, "shader_parameter/DissolveValue", 1.0, dissolve_duration)
		tween.tween_callback(vfx.queue_free)
	else:
		# Einfach nach lifetime entfernen
		get_tree().create_timer(lifetime).timeout.connect(vfx.queue_free)

	
	
func _get_slash_spawn_position(dir: int) -> Vector3:
	var pos := character.global_position
	var dist := 0.2
	match dir:
		Dir.RIGHT: pos += Vector3(dist, 0.0, 0.0)
		Dir.LEFT:  pos += Vector3(-dist, 0.0, 0.0)
		Dir.UP:    pos += Vector3(0.0, 0.0, dist)
		Dir.DOWN:  pos += Vector3(0.0, 0.0, -dist)

	return pos
	

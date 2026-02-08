extends CharacterBody3D
class_name Enemy

## Basisklasse für alle Gegner
## Enthält: Terrain-Waiting, Freeze-System, Health, Knockback, Rewards

# === HEALTH ===
@export_group("Health")
@export var max_health: int = 30
@export var knockback_strength: float = 0.5
@export var hit_flash_duration: float = 0.15

# === DETECTION & FREEZE ===
@export_group("Detection")
@export var detection_range: float = 5.0
@export var lose_interest_range: float = 12.0
@export var freeze_distance: float = 25.0
@export var unfreeze_distance: float = 25.0

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

# Knockback
var _knockback_velocity: Vector3 = Vector3.ZERO
var _hit_timer: float = 0.0

# Animation
var _anim_time: float = 0.0

# Components
var _hp_bar: Node = null
var sprite: Sprite3D = null

# Physics
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


# === VIRTUAL METHODS (Override in Subclass) ===

## Wird aufgerufen nachdem Terrain bereit ist
func _on_ready_after_terrain() -> void:
	pass


## Wird jeden Physics-Frame aufgerufen (wenn nicht frozen/dead)
func _process_ai(_delta: float) -> void:
	pass


## Wird aufgerufen wenn Schaden erhalten wird (für Animation etc.)
func _on_damage_received(_amount: int, _from_position: Vector3) -> void:
	pass


## Wird aufgerufen wenn der Gegner stirbt
func _on_death() -> void:
	pass


## Gibt den aktuellen Hurt-Frame zurück {frame: int, flip: bool}
func _get_hurt_frame() -> Dictionary:
	return {frame = 0, flip = false}


# === LIFECYCLE ===

func _ready() -> void:
	_health = max_health
	_spawn_position = global_position
	
	_player_ref = get_tree().get_first_node_in_group("player")
	
	# Sprite finden
	sprite = get_node_or_null("Sprite3D")
	if sprite:
		sprite.hframes = HFRAMES
		sprite.vframes = VFRAMES
	
	_setup_hp_bar()
	
	# Warte auf Terrain bevor Physics aktiviert wird
	_await_terrain_ready()


func _await_terrain_ready() -> void:
	# Physics erstmal deaktivieren
	set_physics_process(false)
	velocity = Vector3.ZERO
	
	# Warte ein paar Frames damit die Szene vollständig geladen ist
	for i in range(5):
		await get_tree().process_frame
	
	# Jetzt prüfen ob Boden unter uns ist
	var max_attempts := 20
	var attempt := 0
	
	while attempt < max_attempts:
		var space_state := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3(0, 2.0, 0),
			global_position + Vector3(0, -10.0, 0)
		)
		query.exclude = [self]
		
		var result := space_state.intersect_ray(query)
		
		if not result.is_empty():
			# Boden gefunden - Position setzen und Physics aktivieren
			global_position = result.position + Vector3(0, 0.1, 0)
			_spawn_position = global_position
			velocity = Vector3.ZERO
			set_physics_process(true)
			_on_ready_after_terrain()
			return
		
		# Noch kein Boden - warten und nochmal versuchen
		attempt += 1
		await get_tree().create_timer(0.1).timeout
	
	# Fallback: Physics trotzdem aktivieren
	set_physics_process(true)
	_on_ready_after_terrain()


func _process(delta: float) -> void:
	_check_freeze_state()


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Fallen-Check (unter Spawn gefallen)
	if global_position.y < _spawn_position.y - 5.0:
		_respawn_at_spawn()
		return
	
	# Dead-Check
	if _is_dead:
		_process_death(delta)
		return
	
	# AI verarbeiten (in Subclass implementiert)
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
	
	_spawn_position.x = global_position.x
	_spawn_position.z = global_position.z
	
	set_physics_process(false)


func _unfreeze() -> void:
	if not _is_frozen:
		return
	
	_is_frozen = false
	
	global_position.y = _spawn_position.y + 1.0
	velocity = Vector3.ZERO
	
	set_physics_process(true)


func _respawn_at_spawn() -> void:
	global_position = _spawn_position
	global_position.y += 1.5
	velocity = Vector3.ZERO


# === HEALTH SYSTEM ===

func take_damage(amount: int, from_position: Vector3) -> void:
	if _is_dead:
		return
	
	_health -= amount
	_anim_time = 0.0
	
	# HP Bar aktualisieren
	if _hp_bar and _hp_bar.has_method("set_health"):
		_hp_bar.set_health(_health, max_health)
	
	# Knockback berechnen
	var knockback_dir := (global_position - from_position).normalized()
	knockback_dir.y = 0
	_knockback_velocity = knockback_dir * knockback_strength
	
	# Callback für Subclass
	_on_damage_received(amount, from_position)
	
	# Tod prüfen
	if _health <= 0:
		_die()


func _die() -> void:
	if _is_dead:
		return
	
	_is_dead = true
	velocity = Vector3.ZERO
	
	_on_death()


func _process_death(_delta: float) -> void:
	# Override in Subclass für Death-Animation
	pass


func _give_rewards() -> void:
	# EXP vergeben
	if GameManager and GameManager.player_data:
		GameManager.player_data.add_exp(exp_reward)
		
		# Gold vergeben
		var gold_amount := randi_range(gold_reward_min, gold_reward_max)
		GameManager.player_data.add_gold(gold_amount)
		
		# Popup spawnen
		_spawn_reward_popup(exp_reward, gold_amount)


func _spawn_reward_popup(exp_amount: int, gold_amount: int) -> void:
	if reward_popup_scene == null:
		return
	
	var popup := reward_popup_scene.instantiate()
	get_tree().current_scene.add_child(popup)
	popup.global_position = global_position + reward_popup_offset
	
	if popup.has_method("setup_combined"):
		popup.setup_exp(exp_amount)


# === HP BAR ===

func _setup_hp_bar() -> void:
	if hp_bar_scene == null:
		return
	
	_hp_bar = hp_bar_scene.instantiate()
	add_child(_hp_bar)
	_hp_bar.position = hp_bar_offset


# === GETTERS ===

func get_health() -> int:
	return _health


func is_alive() -> bool:
	return not _is_dead


func is_frozen() -> bool:
	return _is_frozen

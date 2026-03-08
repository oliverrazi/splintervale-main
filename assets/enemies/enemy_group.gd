extends Node3D
class_name EnemyGroup

## Verwaltet eine Gruppe von Gegnern mit gemeinsamer Detection und Swarm-Verhalten

@export_group("Detection")
@export var detection_range: float = 6.0
@export var lose_interest_range: float = 18.0
@export var re_aggro_range: float = 1.0

@export_group("Swarm Behavior")
@export var min_enemy_distance: float = 1.5
@export var separation_strength: float = 2.0

var _target: Node3D = null
var _enemies: Array[Enemy] = []
var _group_alerted: bool = false
var _alert_cooldown: float = 0.0
var _initialization_delay: float = 0.5  # Warte nach Szenen-Load

@onready var detection_area: Area3D = $DetectionArea


func _ready() -> void:
	# Alle Enemy-Kinder finden
	for child in get_children():
		if child is Enemy:
			_enemies.append(child)
			_register_enemy(child)
	
	if detection_area:
		var shape := detection_area.get_node_or_null("CollisionShape3D")
		if shape and shape.shape is SphereShape3D:
			shape.shape = shape.shape.duplicate()
			shape.shape.radius = detection_range
		
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)


func _register_enemy(enemy: Enemy) -> void:
	# Goblin-spezifisch
	if enemy.has_method("set_group"):
		enemy.set_group(self)


func _physics_process(delta: float) -> void:
	# Warte kurz nach Szenen-Load bevor Detection aktiv wird
	if _initialization_delay > 0.0:
		_initialization_delay -= delta
		return
	
	# Alert Cooldown verwalten
	if _alert_cooldown > 0.0:
		_alert_cooldown -= delta
		if _alert_cooldown <= 0.0:
			_group_alerted = false
	
	if _target and is_instance_valid(_target):
		var dist := _get_closest_enemy_distance_to_target()
		
		# Lose Interest nur wenn KEIN Enemy nah genug ist UND Gruppe nicht alarmiert
		if dist > lose_interest_range and not _group_alerted:
			_clear_target()
		else:
			_update_enemy_targets()
	else:
		_scan_for_player()


func _scan_for_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	
	# Distanz vom nächsten Enemy messen, nicht vom Group-Node
	var closest_dist := INF
	for enemy in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var dist := enemy.global_position.distance_to(player.global_position)
		closest_dist = min(closest_dist, dist)
	
	if closest_dist <= detection_range:
		_set_target(player)


func _update_enemy_targets() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	
	for enemy in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		
		var dist := enemy.global_position.distance_to(_target.global_position)
		
		# Enemy hat kein Target aber sollte eins haben
		if enemy._target == null and dist <= re_aggro_range:
			if enemy.has_method("set_target_from_group"):
				enemy.set_target_from_group(_target)
			if enemy.has_method("set_target"):
				enemy.set_target(_target)
		
		# Enemy ist im Patrol-State aber Spieler ist nah
		elif _is_enemy_patrolling(enemy) and dist <= re_aggro_range:
			if enemy.has_method("set_target_from_group"):
				enemy.set_target_from_group(_target)
			if enemy.has_method("set_target"):
				enemy.set_target(_target)


func _is_enemy_patrolling(enemy: Enemy) -> bool:
	# Goblin-spezifisch: Prüfe ob im Patrol-State
	if enemy.has_method("get") and "current_state" in enemy:
		# Für Goblin: State 0 und 1 sind PATROL_IDLE und PATROL_WALK
		var state = enemy.get("_state")
		if state != null:
			return state in [0, 1]  # PATROL_IDLE, PATROL_WALK
	
	# Fallback: Wenn kein Target, vermutlich patrolling
	return enemy._target == null


func _get_closest_enemy_distance_to_target() -> float:
	if _target == null:
		return INF
	
	var closest_dist := INF
	for enemy in _enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var dist := enemy.global_position.distance_to(_target.global_position)
		closest_dist = min(closest_dist, dist)
	
	return closest_dist


func alert_group(target: Node3D) -> void:
	if target == null:
		return
	
	_group_alerted = true
	_alert_cooldown = 10.0
	
	_set_target(target)


func _on_detection_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_set_target(body)


func _on_detection_body_exited(_body: Node3D) -> void:
	pass


func _set_target(target: Node3D) -> void:
	_target = target
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			if enemy.has_method("set_target_from_group"):
				enemy.set_target_from_group(target)
			elif enemy.has_method("set_target"):
				enemy.set_target(target)


func _clear_target() -> void:
	_target = null
	_group_alerted = false
	_alert_cooldown = 0.0
	
	for enemy in _enemies:
		if is_instance_valid(enemy):
			if enemy.has_method("clear_target"):
				enemy.clear_target()


func get_target() -> Node3D:
	return _target


func get_enemies() -> Array[Enemy]:
	return _enemies


func get_alive_enemies() -> Array[Enemy]:
	var alive: Array[Enemy] = []
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			alive.append(enemy)
	return alive


# Legacy-Methoden für Abwärtskompatibilität mit Goblin
func get_goblins() -> Array[Enemy]:
	return _enemies


func get_alive_goblins() -> Array[Enemy]:
	return get_alive_enemies()


func get_separation_vector(enemy: Enemy) -> Vector3:
	var separation := Vector3.ZERO
	
	for other in _enemies:
		if other == enemy or not is_instance_valid(other) or not other.is_alive():
			continue
		
		var to_other := other.global_position - enemy.global_position
		to_other.y = 0
		var dist := to_other.length()
		
		if dist < min_enemy_distance and dist > 0.01:
			var strength := (min_enemy_distance - dist) / min_enemy_distance
			separation -= to_other.normalized() * strength * separation_strength
	
	return separation


func get_optimal_strafe_direction(enemy: Enemy, player_pos: Vector3) -> int:
	var enemy_pos := enemy.global_position
	var to_player := player_pos - enemy_pos
	to_player.y = 0
	
	var enemy_angle := atan2(to_player.x, to_player.z)
	
	var left_count := 0
	var right_count := 0
	
	for other in _enemies:
		if other == enemy or not is_instance_valid(other) or not other.is_alive():
			continue
		
		var other_to_player := player_pos - other.global_position
		other_to_player.y = 0
		var other_angle := atan2(other_to_player.x, other_to_player.z)
		
		var angle_diff := other_angle - enemy_angle
		while angle_diff > PI:
			angle_diff -= TAU
		while angle_diff < -PI:
			angle_diff += TAU
		
		if angle_diff > 0:
			left_count += 1
		else:
			right_count += 1
	
	if left_count < right_count:
		return 1
	elif right_count < left_count:
		return -1
	else:
		return 1 if randf() > 0.5 else -1


func remove_enemy(enemy: Enemy) -> void:
	_enemies.erase(enemy)
	
	if get_alive_enemies().size() == 0:
		_clear_target()


# Legacy für Goblin
func remove_goblin(enemy: Enemy) -> void:
	remove_enemy(enemy)

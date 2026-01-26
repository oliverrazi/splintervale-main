extends Node3D
class_name EnemyGroup

@export_group("Detection")
@export var detection_range: float = 6.0
@export var lose_interest_range: float = 18.0
@export var re_aggro_range: float = 1.0 

@export_group("Swarm Behavior")
@export var min_goblin_distance: float = 1.5
@export var separation_strength: float = 2.0

var _target: Node3D = null
var _goblins: Array[Goblin] = []
var _group_alerted: bool = false  # NEU: Gruppe ist alarmiert
var _alert_cooldown: float = 0.0  # NEU: Cooldown bevor Gruppe sich beruhigt

@onready var detection_area: Area3D = $DetectionArea


func _ready() -> void:
	for child in get_children():
		if child is Goblin:
			_goblins.append(child)
			child.set_group(self)
	
	if detection_area:
		var shape := detection_area.get_node_or_null("CollisionShape3D")
		if shape and shape.shape is SphereShape3D:
			shape.shape = shape.shape.duplicate()
			shape.shape.radius = detection_range
		
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)


func _physics_process(delta: float) -> void:
	# Alert Cooldown verwalten
	if _alert_cooldown > 0.0:
		_alert_cooldown -= delta
		if _alert_cooldown <= 0.0:
			_group_alerted = false
	
	if _target and is_instance_valid(_target):
		var dist := _get_closest_goblin_distance_to_target()
		
		# Lose Interest nur wenn KEIN Goblin nah genug ist UND Gruppe nicht alarmiert
		if dist > lose_interest_range and not _group_alerted:
			_clear_target()
		else:
			# NEU: Kontinuierliche Re-Detection für alle Goblins
			_update_goblin_targets()
	else:
		# NEU: Auch ohne aktives Target nach Spieler suchen
		_scan_for_player()


# NEU: Sucht aktiv nach dem Spieler
func _scan_for_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	
	var dist := global_position.distance_to(player.global_position)
	
	if dist <= detection_range:
		_set_target(player)


# NEU: Aktualisiert Targets für alle Goblins
func _update_goblin_targets() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	
	for goblin in _goblins:
		if not is_instance_valid(goblin) or not goblin.is_alive():
			continue
		
		var dist := goblin.global_position.distance_to(_target.global_position)
		
		# Goblin hat kein Target aber sollte eins haben
		if goblin._target == null and dist <= re_aggro_range:
			goblin.set_target(_target)
		
		# Goblin ist im PATROL State aber Spieler ist nah
		elif goblin.current_state in [Goblin.State.PATROL_IDLE, Goblin.State.PATROL_WALK]:
			if dist <= re_aggro_range:
				goblin.set_target(_target)


# NEU: Berechnet die Distanz des nächsten Goblins zum Target
func _get_closest_goblin_distance_to_target() -> float:
	if _target == null:
		return INF
	
	var closest_dist := INF
	for goblin in _goblins:
		if not is_instance_valid(goblin) or not goblin.is_alive():
			continue
		var dist := goblin.global_position.distance_to(_target.global_position)
		closest_dist = min(closest_dist, dist)
	
	return closest_dist


# NEU: Alarmiert die gesamte Gruppe (z.B. wenn ein Goblin angegriffen wird)
func alert_group(target: Node3D) -> void:
	if target == null:
		return
	
	_group_alerted = true
	_alert_cooldown = 10.0  # 10 Sekunden alarmiert bleiben
	
	_set_target(target)
	
	print("Group alerted! All goblins aggro on: ", target.name)


func _on_detection_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_set_target(body)


func _on_detection_body_exited(body: Node3D) -> void:
	pass


func _set_target(target: Node3D) -> void:
	_target = target
	for goblin in _goblins:
		if is_instance_valid(goblin) and goblin.is_alive():
			goblin.set_target(target)


func _clear_target() -> void:
	_target = null
	_group_alerted = false
	_alert_cooldown = 0.0
	
	for goblin in _goblins:
		if is_instance_valid(goblin):
			goblin.clear_target()


func get_target() -> Node3D:
	return _target


func get_goblins() -> Array[Goblin]:
	return _goblins


func get_alive_goblins() -> Array[Goblin]:
	var alive: Array[Goblin] = []
	for goblin in _goblins:
		if is_instance_valid(goblin) and goblin.is_alive():
			alive.append(goblin)
	return alive


func get_separation_vector(goblin: Goblin) -> Vector3:
	var separation := Vector3.ZERO
	
	for other in _goblins:
		if other == goblin or not is_instance_valid(other) or not other.is_alive():
			continue
		
		var to_other := other.global_position - goblin.global_position
		to_other.y = 0
		var dist := to_other.length()
		
		if dist < min_goblin_distance and dist > 0.01:
			var strength := (min_goblin_distance - dist) / min_goblin_distance
			separation -= to_other.normalized() * strength * separation_strength
	
	return separation


func get_optimal_strafe_direction(goblin: Goblin, player_pos: Vector3) -> int:
	var goblin_pos := goblin.global_position
	var to_player := player_pos - goblin_pos
	to_player.y = 0
	
	var goblin_angle := atan2(to_player.x, to_player.z)
	
	var left_count := 0
	var right_count := 0
	
	for other in _goblins:
		if other == goblin or not is_instance_valid(other) or not other.is_alive():
			continue
		
		var other_to_player := player_pos - other.global_position
		other_to_player.y = 0
		var other_angle := atan2(other_to_player.x, other_to_player.z)
		
		var angle_diff := other_angle - goblin_angle
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


func remove_goblin(goblin: Goblin) -> void:
	_goblins.erase(goblin)
	
	# NEU: Wenn alle tot, Gruppe deaktivieren
	if get_alive_goblins().size() == 0:
		_clear_target()

extends Node3D
class_name EnemyGroup

@export_group("Detection")
@export var detection_range: float = 1.0
@export var lose_interest_range: float = 18.0

@export_group("Swarm Behavior")
@export var min_goblin_distance: float = 1.5  # Mindestabstand zwischen Goblins
@export var separation_strength: float = 2.0  # Wie stark sie sich abstoßen

var _target: Node3D = null
var _goblins: Array[Goblin] = []

@onready var detection_area: Area3D = $DetectionArea


func _ready() -> void:
	# Alle Goblin-Children sammeln
	for child in get_children():
		if child is Goblin:
			_goblins.append(child)
			child.set_group(self)
	
	# Detection Area Setup
	if detection_area:
		var shape := detection_area.get_node_or_null("CollisionShape3D")
		if shape and shape.shape is SphereShape3D:
			shape.shape = shape.shape.duplicate()
			shape.shape.radius = detection_range

		
		detection_area.body_entered.connect(_on_detection_body_entered)
		detection_area.body_exited.connect(_on_detection_body_exited)
	


func _physics_process(_delta: float) -> void:
	if _target and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		if dist > lose_interest_range:
			_clear_target()


func _on_detection_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_set_target(body)


func _on_detection_body_exited(body: Node3D) -> void:
	pass  # Wir nutzen lose_interest_range stattdessen


func _set_target(target: Node3D) -> void:
	_target = target
	for goblin in _goblins:
		if is_instance_valid(goblin) and goblin.is_alive():
			goblin.set_target(target)


func _clear_target() -> void:
	_target = null
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


# Berechnet Abstoßungsvektor von anderen Goblins
func get_separation_vector(goblin: Goblin) -> Vector3:
	var separation := Vector3.ZERO
	
	for other in _goblins:
		if other == goblin or not is_instance_valid(other) or not other.is_alive():
			continue
		
		var to_other := other.global_position - goblin.global_position
		to_other.y = 0
		var dist := to_other.length()
		
		if dist < min_goblin_distance and dist > 0.01:
			# Je näher, desto stärker die Abstoßung
			var strength := (min_goblin_distance - dist) / min_goblin_distance
			separation -= to_other.normalized() * strength * separation_strength
	
	return separation


# Bestimmt die Strafe-Richtung basierend auf anderen Goblins
func get_optimal_strafe_direction(goblin: Goblin, player_pos: Vector3) -> int:
	var goblin_pos := goblin.global_position
	var to_player := player_pos - goblin_pos
	to_player.y = 0
	
	# Winkel des Goblins zum Spieler
	var goblin_angle := atan2(to_player.x, to_player.z)
	
	# Zähle Goblins links und rechts
	var left_count := 0
	var right_count := 0
	
	for other in _goblins:
		if other == goblin or not is_instance_valid(other) or not other.is_alive():
			continue
		
		var other_to_player := player_pos - other.global_position
		other_to_player.y = 0
		var other_angle := atan2(other_to_player.x, other_to_player.z)
		
		# Winkel-Differenz
		var angle_diff := other_angle - goblin_angle
		# Normalisieren auf -PI bis PI
		while angle_diff > PI:
			angle_diff -= TAU
		while angle_diff < -PI:
			angle_diff += TAU
		
		if angle_diff > 0:
			left_count += 1
		else:
			right_count += 1
	
	# Gehe in die Richtung mit weniger Goblins
	if left_count < right_count:
		return 1  # Links strafen
	elif right_count < left_count:
		return -1  # Rechts strafen
	else:
		return 1 if randf() > 0.5 else -1  # Zufällig wenn gleich


func remove_goblin(goblin: Goblin) -> void:
	_goblins.erase(goblin)

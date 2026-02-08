@tool
extends Node3D
class_name FogZone

@export_group("Fog Settings")
@export var fog_density: float = 0.05
@export var fog_color: Color = Color(0.5, 0.6, 0.7)
@export var fog_emission: Color = Color(0.0, 0.0, 0.0)
@export var fog_emission_energy: float = 0.0

@export_group("Transition")
@export var zone_priority: int = 0
@export var transition_distance: float = 5.0
@export_range(0.0, 1.0) var transition_sharpness: float = 0.3

# Gecachte Shapes
var _shapes: Array[CollisionShape3D] = []


func _ready() -> void:
	_collect_shapes()
	
	if not Engine.is_editor_hint():
		add_to_group("fog_zone")
		if FogManager:
			FogManager.register_fog_zone(self)


func _exit_tree() -> void:
	if not Engine.is_editor_hint() and FogManager:
		FogManager.unregister_fog_zone(self)


func _collect_shapes() -> void:
	_shapes.clear()
	for child in get_children():
		if child is CollisionShape3D and child.shape != null:
			_shapes.append(child)


func get_influence(player_pos: Vector3) -> float:
	if _shapes.is_empty():
		_collect_shapes()
	
	var max_influence := 0.0
	
	for shape_node in _shapes:
		var influence := _get_shape_influence(shape_node, player_pos)
		if influence >= 1.0:
			return 1.0  # Early exit
		max_influence = max(max_influence, influence)
	
	return max_influence


func _get_shape_influence(shape_node: CollisionShape3D, player_pos: Vector3) -> float:
	var shape := shape_node.shape
	if shape == null:
		return 0.0
	
	var local_pos := shape_node.to_local(player_pos)
	var distance := _get_distance_to_shape(shape, local_pos)
	
	# Innerhalb = voller Nebel
	if distance <= 0.0:
		return 1.0
	
	# Außerhalb Transition = kein Nebel
	if distance >= transition_distance:
		return 0.0
	
	# Übergang: schneller Anstieg basierend auf sharpness
	var t := distance / transition_distance
	var sharpness_factor :float = 1.0 / max(transition_sharpness, 0.05)
	return clamp(1.0 - pow(t, sharpness_factor), 0.0, 1.0)


func _get_distance_to_shape(shape: Shape3D, local_pos: Vector3) -> float:
	if shape is BoxShape3D:
		var half :Vector3= shape.size / 2.0
		if abs(local_pos.x) <= half.x and abs(local_pos.y) <= half.y and abs(local_pos.z) <= half.z:
			return 0.0
		var clamped := Vector3(
			clamp(local_pos.x, -half.x, half.x),
			clamp(local_pos.y, -half.y, half.y),
			clamp(local_pos.z, -half.z, half.z)
		)
		return local_pos.distance_to(clamped)
		
	elif shape is SphereShape3D:
		return max(0.0, local_pos.length() - shape.radius)
		
	elif shape is CylinderShape3D:
		var h_dist := Vector2(local_pos.x, local_pos.z).length()
		var v_dist :float= abs(local_pos.y)
		if h_dist <= shape.radius and v_dist <= shape.height / 2.0:
			return 0.0
		var h_overflow :float= max(0.0, h_dist - shape.radius)
		var v_overflow :float= max(0.0, v_dist - shape.height / 2.0)
		return sqrt(h_overflow * h_overflow + v_overflow * v_overflow)
		
	elif shape is CapsuleShape3D:
		var half_h :float= shape.height / 2.0 - shape.radius
		var closest_y :float= clamp(local_pos.y, -half_h, half_h)
		return max(0.0, local_pos.distance_to(Vector3(0, closest_y, 0)) - shape.radius)
	
	return 0.0


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var found := false
	for child in get_children():
		if child is CollisionShape3D and child.shape != null:
			found = true
			break
	if not found:
		warnings.append("FogZone benötigt mindestens ein CollisionShape3D Child!")
	return warnings

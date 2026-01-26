@tool
extends Area3D
class_name FogZone

@export_group("Fog Settings")
@export var fog_density: float = 0.05
@export var fog_color: Color = Color(0.5, 0.6, 0.7):
	set(value):
		fog_color = value
		_update_visualization()

@export var fog_emission: Color = Color(0.0, 0.0, 0.0)
@export var fog_emission_energy: float = 0.0

@export_group("Transition")
@export var zone_priority: int = 0  # Umbenannt von "priority"
@export var transition_distance: float = 5.0:
	set(value):
		transition_distance = value
		_update_visualization()

@export_group("Editor Visualization")
@export var show_zone_in_editor: bool = true:
	set(value):
		show_zone_in_editor = value
		_update_visualization()

@export var zone_color: Color = Color(0.3, 0.5, 0.8, 0.15):
	set(value):
		zone_color = value
		_update_visualization()

@export var transition_color: Color = Color(0.8, 0.5, 0.3, 0.08):
	set(value):
		transition_color = value
		_update_visualization()

var _shape: Shape3D = null
var _zone_mesh: MeshInstance3D = null
var _transition_mesh: MeshInstance3D = null


func _ready() -> void:
	var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape:
		_shape = collision_shape.shape
		
		if Engine.is_editor_hint():
			_update_visualization()
			if collision_shape.shape:
				collision_shape.shape.changed.connect(_update_visualization)
		else:
			add_to_group("fog_zone")
			if FogManager:
				FogManager.register_fog_zone(self)


func _exit_tree() -> void:
	if not Engine.is_editor_hint() and FogManager:
		FogManager.unregister_fog_zone(self)


func _update_visualization() -> void:
	if not Engine.is_editor_hint():
		return
	
	# Alte Meshes entfernen
	if _zone_mesh and is_instance_valid(_zone_mesh):
		_zone_mesh.queue_free()
		_zone_mesh = null
	if _transition_mesh and is_instance_valid(_transition_mesh):
		_transition_mesh.queue_free()
		_transition_mesh = null
	
	if not show_zone_in_editor:
		return
	
	var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return
	
	_shape = collision_shape.shape
	
	# Zone Mesh erstellen
	_zone_mesh = _create_zone_mesh(_shape, zone_color, false)
	if _zone_mesh:
		add_child(_zone_mesh)
	
	# Transition Mesh erstellen (größer)
	_transition_mesh = _create_zone_mesh(_shape, transition_color, true)
	if _transition_mesh:
		add_child(_transition_mesh)


func _create_zone_mesh(shape: Shape3D, color: Color, is_transition: bool) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh: Mesh = null
	
	if shape is BoxShape3D:
		var box: BoxShape3D = shape as BoxShape3D
		var box_mesh := BoxMesh.new()
		if is_transition:
			box_mesh.size = box.size + Vector3(transition_distance * 2, transition_distance * 2, transition_distance * 2)
		else:
			box_mesh.size = box.size
		mesh = box_mesh
		
	elif shape is SphereShape3D:
		var sphere: SphereShape3D = shape as SphereShape3D
		var sphere_mesh := SphereMesh.new()
		if is_transition:
			sphere_mesh.radius = sphere.radius + transition_distance
			sphere_mesh.height = (sphere.radius + transition_distance) * 2
		else:
			sphere_mesh.radius = sphere.radius
			sphere_mesh.height = sphere.radius * 2
		mesh = sphere_mesh
		
	elif shape is CylinderShape3D:
		var cylinder: CylinderShape3D = shape as CylinderShape3D
		var cyl_mesh := CylinderMesh.new()
		if is_transition:
			cyl_mesh.top_radius = cylinder.radius + transition_distance
			cyl_mesh.bottom_radius = cylinder.radius + transition_distance
			cyl_mesh.height = cylinder.height + transition_distance * 2
		else:
			cyl_mesh.top_radius = cylinder.radius
			cyl_mesh.bottom_radius = cylinder.radius
			cyl_mesh.height = cylinder.height
		mesh = cyl_mesh
	else:
		return null
	
	mesh_instance.mesh = mesh
	
	# Transparentes Material
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	if is_transition:
		mat.albedo_color.a = color.a * 0.5
	
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	return mesh_instance


func get_influence(player_pos: Vector3) -> float:
	if _shape == null:
		return 0.0
	
	var local_pos: Vector3 = to_local(player_pos)
	var distance_to_edge: float = 0.0
	
	if _shape is BoxShape3D:
		var box: BoxShape3D = _shape as BoxShape3D
		var half_extents: Vector3 = box.size / 2.0
		
		var inside_x: bool = abs(local_pos.x) <= half_extents.x
		var inside_y: bool = abs(local_pos.y) <= half_extents.y
		var inside_z: bool = abs(local_pos.z) <= half_extents.z
		var inside: bool = inside_x and inside_y and inside_z
		
		if inside:
			return 1.0
		
		var clamped := Vector3(
			clamp(local_pos.x, -half_extents.x, half_extents.x),
			clamp(local_pos.y, -half_extents.y, half_extents.y),
			clamp(local_pos.z, -half_extents.z, half_extents.z)
		)
		distance_to_edge = local_pos.distance_to(clamped)
		
	elif _shape is SphereShape3D:
		var sphere: SphereShape3D = _shape as SphereShape3D
		var dist_to_center: float = local_pos.length()
		
		if dist_to_center <= sphere.radius:
			return 1.0
		
		distance_to_edge = dist_to_center - sphere.radius
		
	elif _shape is CylinderShape3D:
		var cylinder: CylinderShape3D = _shape as CylinderShape3D
		var horizontal_dist: float = Vector2(local_pos.x, local_pos.z).length()
		var vertical_dist: float = abs(local_pos.y)
		
		var inside_h: bool = horizontal_dist <= cylinder.radius
		var inside_v: bool = vertical_dist <= cylinder.height / 2.0
		
		if inside_h and inside_v:
			return 1.0
		
		var h_overflow: float = max(0.0, horizontal_dist - cylinder.radius)
		var v_overflow: float = max(0.0, vertical_dist - cylinder.height / 2.0)
		distance_to_edge = sqrt(h_overflow * h_overflow + v_overflow * v_overflow)
	
	if distance_to_edge >= transition_distance:
		return 0.0
	
	var t: float = distance_to_edge / transition_distance
	return 1.0 - _smoothstep(0.0, 1.0, t)


func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	
	var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		warnings.append("FogZone benötigt ein CollisionShape3D Child!")
	elif collision_shape.shape == null:
		warnings.append("CollisionShape3D benötigt eine Shape!")
	
	return warnings

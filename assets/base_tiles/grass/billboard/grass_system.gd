@tool
extends Node3D
class_name GrassSystem

@export var grass_texture: Texture2D:
	set(v):
		grass_texture = v
		if _material:
			_material.set_shader_parameter("grass_texture", v)

@export var density: float = 50.0
@export var grass_scale := Vector2(0.02, 0.25)
@export var scale_variation := 0.5
@export var color_variation := 0.15

@export_group("Shape")
@export var shape_points: PackedVector2Array = PackedVector2Array([
	Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)
]):
	set(v):
		shape_points = v
		if Engine.is_editor_hint():
			_update_debug_visuals()

@export_group("Wind")
@export var wind_strength := 0.3:
	set(v):
		wind_strength = v
		if _material:
			_material.set_shader_parameter("wind_strength", v)
@export var wind_speed := 1.5:
	set(v):
		wind_speed = v
		if _material:
			_material.set_shader_parameter("wind_speed", v)

@export_group("LOD")
@export var lod_fade_start := 30.0:
	set(v):
		lod_fade_start = v
		if _material:
			_material.set_shader_parameter("lod_fade_start", v)
@export var lod_fade_end := 50.0:
	set(v):
		lod_fade_end = v
		if _material:
			_material.set_shader_parameter("lod_fade_end", v)

@export_group("Sorting")
@export var depth_bias_strength := 0.02:
	set(v):
		depth_bias_strength = v
		if _material:
			_material.set_shader_parameter("depth_bias_strength", v)

@export_group("Debug")
@export var show_shape_outline := true:
	set(v):
		show_shape_outline = v
		_update_debug_visuals()
@export var regenerate := false:
	set(v):
		if v:
			call_deferred("_generate_grass")

var _multimesh_instance: MultiMeshInstance3D
var _material: ShaderMaterial
var _debug_mesh: MeshInstance3D

func _ready() -> void:
	_setup_material()
	_generate_grass()
	if Engine.is_editor_hint():
		_update_debug_visuals()

func _setup_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://assets/base_tiles/grass/billboard/billboard_shader.gdshader")
	if grass_texture:
		_material.set_shader_parameter("grass_texture", grass_texture)
	_material.set_shader_parameter("wind_strength", wind_strength)
	_material.set_shader_parameter("wind_speed", wind_speed)
	_material.set_shader_parameter("lod_fade_start", lod_fade_start)
	_material.set_shader_parameter("lod_fade_end", lod_fade_end)
	_material.set_shader_parameter("depth_bias_strength", depth_bias_strength)

func _generate_grass() -> void:
	if _multimesh_instance:
		_multimesh_instance.queue_free()
		_multimesh_instance = null
	
	if shape_points.size() < 3:
		return
	
	var positions := _generate_points_in_polygon()
	if positions.is_empty():
		return
	
	var instance_count := positions.size()
	
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _create_quad_mesh()
	multimesh.instance_count = instance_count
	
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	
	for i in instance_count:
		var local_pos: Vector3 = positions[i]
		
		var scale_factor := 1.0 + rng.randf_range(-scale_variation, scale_variation)
		var color_offset := rng.randf_range(-color_variation, color_variation)
		var random_phase := rng.randf() * TAU
		
		var instance_scale := Vector3(
			grass_scale.x * scale_factor,
			grass_scale.y * scale_factor,
			1.0
		)
		
		var transform := Transform3D()
		transform = transform.scaled(instance_scale)
		transform.origin = local_pos
		
		multimesh.set_instance_transform(i, transform)
		multimesh.set_instance_color(i, Color(
			1.0 + color_offset,
			1.0 + color_offset * 0.5,
			1.0,
			1.0
		))
		multimesh.set_instance_custom_data(i, Color(random_phase, 0, 0, 0))
	
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = multimesh
	_multimesh_instance.material_override = _material
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_multimesh_instance)
	
	print("GrassSystem: ", instance_count, " instances generated")

func _generate_points_in_polygon() -> Array[Vector3]:
	var points: Array[Vector3] = []
	
	if shape_points.size() < 3:
		return points
	
	var min_p := shape_points[0]
	var max_p := shape_points[0]
	for p in shape_points:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	
	var area := _polygon_area(shape_points)
	var point_count := int(area * density)
	
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position) + hash(shape_points.size())
	
	var attempts := 0
	var max_attempts := point_count * 10
	
	while points.size() < point_count and attempts < max_attempts:
		attempts += 1
		
		var test_point := Vector2(
			rng.randf_range(min_p.x, max_p.x),
			rng.randf_range(min_p.y, max_p.y)
		)
		
		if Geometry2D.is_point_in_polygon(test_point, shape_points):
			points.append(Vector3(test_point.x, 0, test_point.y))
	
	return points

func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	var n := polygon.size()
	for i in n:
		var j := (i + 1) % n
		area += polygon[i].x * polygon[j].y
		area -= polygon[j].x * polygon[i].y
	return abs(area) / 2.0

func _create_quad_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	mesh.center_offset = Vector3(0, 0.5, 0)
	return mesh

func _update_debug_visuals() -> void:
	if not Engine.is_editor_hint():
		return
	
	if _debug_mesh:
		_debug_mesh.queue_free()
		_debug_mesh = null
	
	if not show_shape_outline or shape_points.size() < 3:
		return
	
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	
	for p in shape_points:
		im.surface_add_vertex(Vector3(p.x, 0.1, p.y))
	im.surface_add_vertex(Vector3(shape_points[0].x, 0.1, shape_points[0].y))
	
	im.surface_end()
	
	_debug_mesh = MeshInstance3D.new()
	_debug_mesh.mesh = im
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.YELLOW_GREEN
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_mesh.material_override = mat
	
	add_child(_debug_mesh)

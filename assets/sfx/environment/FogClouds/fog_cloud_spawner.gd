extends Node3D

@export var cloud_count: int = 6
@export var spawn_radius: float = 25.0
@export var height_min: float = 0.3
@export var height_max: float = 1.5
@export var cloud_color: Color = Color(0.85, 0.88, 0.92, 0.35)
@export var follow_player: bool = true

var _clouds: Array[Dictionary] = []
var _player: Node3D = null


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_create_clouds()


func _create_clouds() -> void:
	for i in range(cloud_count):
		var mesh_instance := MeshInstance3D.new()
		
		# Quad Mesh
		var quad := QuadMesh.new()
		quad.size = Vector2(randf_range(3.0, 6.0), randf_range(1.5, 3.0))
		mesh_instance.mesh = quad
		
		# Material mit Shader
		var mat := _create_fog_material()
		mesh_instance.material_override = mat
		
		add_child(mesh_instance)
		
		# Cloud Data
		var cloud_data := {
			"mesh": mesh_instance,
			"velocity": Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)).normalized() * randf_range(0.2, 0.6),
			"bob_phase": randf() * TAU,
			"bob_speed": randf_range(0.2, 0.4),
			"bob_amount": randf_range(0.1, 0.3),
			"start_y": randf_range(height_min, height_max)
		}
		_clouds.append(cloud_data)
		
		# Startposition
		mesh_instance.position = Vector3(
			randf_range(-spawn_radius, spawn_radius),
			cloud_data.start_y,
			randf_range(-spawn_radius, spawn_radius)
		)


func _create_fog_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 fog_color : source_color = vec4(0.85, 0.88, 0.92, 0.35);
uniform float time_scale : hint_range(0.0, 0.5) = 0.05;

void vertex() {
	// Y-Axis Billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(1.0, 0.0, 0.0, 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0;
	
	// Weiche Wolkenform
	float noise = sin(UV.x * 10.0 + TIME * time_scale) * 0.1 
	            + sin(UV.y * 8.0 - TIME * time_scale * 0.7) * 0.1;
	float edge = 1.0 - smoothstep(0.2 + noise, 0.9 + noise, dist);
	
	ALBEDO = fog_color.rgb;
	ALPHA = fog_color.a * edge;
}
"""
	
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("fog_color", cloud_color)
	mat.set_shader_parameter("time_scale", 0.05)
	
	return mat


func _process(delta: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	
	for cloud_data in _clouds:
		var mesh: MeshInstance3D = cloud_data.mesh
		
		# Bewegung
		mesh.position += cloud_data.velocity * delta
		
		# Bobbing
		mesh.position.y = cloud_data.start_y + sin(time * cloud_data.bob_speed + cloud_data.bob_phase) * cloud_data.bob_amount
		
		# Wrap around
		if mesh.position.x > spawn_radius:
			mesh.position.x = -spawn_radius
		elif mesh.position.x < -spawn_radius:
			mesh.position.x = spawn_radius
		
		if mesh.position.z > spawn_radius:
			mesh.position.z = -spawn_radius
		elif mesh.position.z < -spawn_radius:
			mesh.position.z = spawn_radius
	
	# Folge Spieler
	if follow_player and _player and is_instance_valid(_player):
		global_position.x = _player.global_position.x
		global_position.z = _player.global_position.z

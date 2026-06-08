extends Node3D

## Griffinblade Ambient Motes - true round version.
##
## This version intentionally does NOT use QuadMesh particles.
## Both layers are rendered as tiny SphereMesh particles, so the silhouette
## can never fall back to a visible square even if alpha/shader behavior changes.
##
## Attach this to your existing AmbientSparks Node3D.
## It will reuse a child called "GPUParticles3D" as the base layer and create
## "AmbientMotes_Glint" automatically for rare highlight particles.

const BASE_NODE_NAME := "GPUParticles3D"
const GLINT_NODE_NAME := "AmbientMotes_Glint"

@export_group("Follow")
@export var follow_player: bool = true
@export var offset: Vector3 = Vector3(0.0, 2.0, 0.0)

@export_group("Emission Volume")
@export var emission_box_extents: Vector3 = Vector3(15.0, 4.0, 15.0)
@export var local_coords: bool = true

@export_group("Base Motes")
@export_range(1, 1200, 1) var base_amount: int = 320
@export_range(0.1, 30.0, 0.1) var base_lifetime: float = 9.0
@export_range(0.0, 30.0, 0.1) var base_preprocess: float = 6.0
@export var base_color: Color = Color(0.42, 0.86, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var base_alpha: float = 0.18
@export_range(0.0, 6.0, 0.05) var base_emission_intensity: float = 0.45
@export_range(0.001, 0.08, 0.001) var base_radius: float = 0.011
@export_range(0.01, 3.0, 0.01) var base_scale_min: float = 0.55
@export_range(0.01, 3.0, 0.01) var base_scale_max: float = 1.35
@export_range(0.0, 0.5, 0.01) var base_fade_in_portion: float = 0.16
@export_range(0.5, 1.0, 0.01) var base_fade_out_start: float = 0.70
@export var base_drift_direction: Vector3 = Vector3(0.18, 0.10, -0.08)
@export_range(0.0, 1.0, 0.001) var base_velocity_min: float = 0.015
@export_range(0.0, 1.0, 0.001) var base_velocity_max: float = 0.070
@export var base_gravity: Vector3 = Vector3(0.0, 0.004, 0.0)
@export_range(0.5, 8.0, 0.1) var base_edge_power: float = 2.25
@export_range(0.5, 12.0, 0.1) var base_core_power: float = 5.0

@export_group("Glints")
@export var glint_enabled: bool = true
@export_range(0, 400, 1) var glint_amount: int = 36
@export_range(0.1, 20.0, 0.1) var glint_lifetime: float = 5.0
@export_range(0.0, 20.0, 0.1) var glint_preprocess: float = 3.0
@export var glint_color: Color = Color(0.72, 0.96, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var glint_alpha: float = 0.34
@export_range(0.0, 10.0, 0.05) var glint_emission_intensity: float = 1.75
@export_range(0.001, 0.08, 0.001) var glint_radius: float = 0.007
@export_range(0.01, 3.0, 0.01) var glint_scale_min: float = 0.45
@export_range(0.01, 3.0, 0.01) var glint_scale_max: float = 1.05
@export_range(0.0, 0.5, 0.01) var glint_fade_in_portion: float = 0.10
@export_range(0.5, 1.0, 0.01) var glint_fade_out_start: float = 0.60
@export var glint_drift_direction: Vector3 = Vector3(-0.05, 0.16, 0.08)
@export_range(0.0, 1.0, 0.001) var glint_velocity_min: float = 0.010
@export_range(0.0, 1.0, 0.001) var glint_velocity_max: float = 0.055
@export var glint_gravity: Vector3 = Vector3(0.0, 0.006, 0.0)
@export_range(0.5, 8.0, 0.1) var glint_edge_power: float = 1.60
@export_range(0.5, 12.0, 0.1) var glint_core_power: float = 3.2

@export_group("Geometry")
@export_range(6, 32, 1) var sphere_radial_segments: int = 14
@export_range(4, 16, 1) var sphere_rings: int = 7

var _player: Node3D = null
var _base_particles: GPUParticles3D = null
var _glint_particles: GPUParticles3D = null


func _ready() -> void:
	if follow_player:
		_player = get_tree().get_first_node_in_group("player") as Node3D

	_base_particles = _get_or_create_child_particles(BASE_NODE_NAME)
	_setup_layers()


func _process(_delta: float) -> void:
	if follow_player and _player != null and is_instance_valid(_player):
		global_position = _player.global_position + offset


func refresh() -> void:
	## Call this manually after changing exported values at runtime.
	_setup_layers()


func _setup_layers() -> void:
	if _base_particles == null:
		push_error("AmbientMotes: Missing base GPUParticles3D node.")
		return

	_setup_particle_layer(
		_base_particles,
		base_amount,
		base_lifetime,
		base_preprocess,
		base_radius,
		base_scale_min,
		base_scale_max,
		base_color,
		base_alpha,
		base_emission_intensity,
		base_fade_in_portion,
		base_fade_out_start,
		base_drift_direction,
		base_velocity_min,
		base_velocity_max,
		base_gravity,
		base_edge_power,
		base_core_power,
		false
	)

	if glint_enabled and glint_amount > 0:
		_glint_particles = _get_or_create_child_particles(GLINT_NODE_NAME)
		_setup_particle_layer(
			_glint_particles,
			glint_amount,
			glint_lifetime,
			glint_preprocess,
			glint_radius,
			glint_scale_min,
			glint_scale_max,
			glint_color,
			glint_alpha,
			glint_emission_intensity,
			glint_fade_in_portion,
			glint_fade_out_start,
			glint_drift_direction,
			glint_velocity_min,
			glint_velocity_max,
			glint_gravity,
			glint_edge_power,
			glint_core_power,
			true
		)
	else:
		var existing_glint := get_node_or_null(GLINT_NODE_NAME) as GPUParticles3D
		if existing_glint != null:
			existing_glint.emitting = false
			existing_glint.visible = false


func _setup_particle_layer(
	particles: GPUParticles3D,
	amount: int,
	lifetime: float,
	preprocess: float,
	radius: float,
	scale_min: float,
	scale_max: float,
	tint: Color,
	alpha: float,
	emission_intensity: float,
	fade_in_portion: float,
	fade_out_start: float,
	drift_direction: Vector3,
	velocity_min: float,
	velocity_max: float,
	gravity: Vector3,
	edge_power: float,
	core_power: float,
	additive: bool
) -> void:
	particles.visible = true
	particles.draw_passes = 1
	particles.amount = max(amount, 1)
	particles.lifetime = max(lifetime, 0.1)
	particles.preprocess = clamp(preprocess, 0.0, particles.lifetime)
	particles.randomness = 1.0
	particles.local_coords = local_coords
	particles.fixed_fps = 0
	particles.visibility_aabb = _calculate_visibility_aabb()

	particles.process_material = _create_process_material(
		drift_direction,
		velocity_min,
		velocity_max,
		gravity,
		scale_min,
		scale_max,
		tint,
		alpha,
		fade_in_portion,
		fade_out_start
	)

	particles.draw_pass_1 = _create_sphere_mesh(
		radius,
		_create_sphere_mote_material(
			tint,
			emission_intensity,
			edge_power,
			core_power,
			additive
		)
	)

	particles.emitting = true
	particles.restart()


func _get_or_create_child_particles(node_name: String) -> GPUParticles3D:
	var existing := get_node_or_null(node_name) as GPUParticles3D
	if existing != null:
		return existing

	var created := GPUParticles3D.new()
	created.name = node_name
	add_child(created)
	return created


func _create_process_material(
	drift_direction: Vector3,
	velocity_min: float,
	velocity_max: float,
	gravity: Vector3,
	scale_min: float,
	scale_max: float,
	tint: Color,
	alpha: float,
	fade_in_portion: float,
	fade_out_start: float
) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = emission_box_extents

	var direction := drift_direction
	if direction.length_squared() < 0.0001:
		direction = Vector3.UP

	material.direction = direction.normalized()
	material.spread = 180.0
	material.initial_velocity_min = max(velocity_min, 0.0)
	material.initial_velocity_max = max(max(velocity_min, velocity_max), 0.0)
	material.gravity = gravity
	material.angular_velocity_min = -6.0
	material.angular_velocity_max = 6.0
	material.scale_min = max(scale_min, 0.001)
	material.scale_max = max(scale_max, material.scale_min)
	material.color = Color(tint.r, tint.g, tint.b, clamp(alpha, 0.0, 1.0))
	material.hue_variation_min = -0.018
	material.hue_variation_max = 0.018

	var fade_in : Variant= clamp(fade_in_portion, 0.001, 0.49)
	var fade_out : Variant= clamp(fade_out_start, 0.50, 0.999)

	material.alpha_curve = _create_curve_texture([
		Vector2(0.0, 0.0),
		Vector2(fade_in, 1.0),
		Vector2(fade_out, 1.0),
		Vector2(1.0, 0.0)
	])

	material.scale_curve = _create_curve_texture([
		Vector2(0.0, 0.35),
		Vector2(fade_in, 1.0),
		Vector2(fade_out, 1.0),
		Vector2(1.0, 0.08)
	])

	return material


func _create_sphere_mesh(radius: float, material: Material) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = max(radius, 0.001)
	mesh.height = max(radius * 2.0, 0.002)
	mesh.radial_segments = max(sphere_radial_segments, 6)
	mesh.rings = max(sphere_rings, 4)
	mesh.material = material
	return mesh


func _create_sphere_mote_material(
	tint: Color,
	emission_intensity: float,
	edge_power: float,
	core_power: float,
	additive: bool
) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _get_sphere_mote_shader_code(additive)

	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("emission_intensity", max(emission_intensity, 0.0))
	material.set_shader_parameter("edge_power", max(edge_power, 0.1))
	material.set_shader_parameter("core_power", max(core_power, 0.1))
	return material


func _get_sphere_mote_shader_code(additive: bool) -> String:
	var blend_mode := "blend_add" if additive else "blend_mix"
	return """
shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled, depth_draw_never, fog_disabled, %s;

uniform vec4 tint : source_color = vec4(0.65, 0.9, 1.0, 1.0);
uniform float emission_intensity = 1.0;
uniform float edge_power = 2.0;
uniform float core_power = 4.0;

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float soft_disc = pow(facing, edge_power);
	float core = pow(facing, core_power);

	ALBEDO = tint.rgb * COLOR.rgb;
	EMISSION = tint.rgb * emission_intensity * mix(soft_disc, core, 0.65) * COLOR.a;
	ALPHA = tint.a * COLOR.a * soft_disc;
}
""" % blend_mode


func _create_curve_texture(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	for point in points:
		curve.add_point(point)

	var texture := CurveTexture.new()
	texture.width = 256
	texture.curve = curve
	return texture


func _calculate_visibility_aabb() -> AABB:
	var padding := Vector3.ONE * 2.0
	var extents := emission_box_extents + padding
	return AABB(-extents, extents * 2.0)

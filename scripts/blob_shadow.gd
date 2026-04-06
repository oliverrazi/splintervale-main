## BlobShadow
##
## Fake Bodenschatten für HD-2D Sprites.
## Einfach als Child-Node unter den Character/NPC hängen.
## Nutzt Raycast um auf Terrain3D / Collision-Boden zu projizieren.

@tool
class_name BlobShadow
extends MeshInstance3D

@export_range(0.1, 3.0, 0.05) var shadow_width: float = 0.5 : set = _set_width
@export_range(0.1, 3.0, 0.05) var shadow_depth: float = 0.3 : set = _set_depth
@export_range(0.0, 1.0, 0.05) var shadow_opacity: float = 0.35 : set = _set_opacity
@export var shadow_color: Color = Color(0.0, 0.0, 0.05) : set = _set_color
@export_range(0.0, 1.0, 0.05) var softness: float = 0.4 : set = _set_softness

## Z-Offset (damit Schatten unter den Füßen liegt, nicht am Pivot)
@export var z_offset: float = 0.15

## Höhe über dem Boden (verhindert Z-Fighting)
@export var ground_offset: float = 0.03

## Raycast-Länge nach unten
@export var ray_length: float = 10.0

## Collision Mask für Boden (Standard: Layer 1)
@export_flags_3d_physics var ground_mask: int = 1

## Schatten-Skalierung basierend auf Höhe über dem Boden
@export var scale_with_height: bool = true
@export var max_height_for_scale: float = 3.0
@export_range(0.3, 1.0, 0.05) var min_scale_factor: float = 0.5

## Opacity-Fade basierend auf Höhe
@export var fade_with_height: bool = true
@export var max_height_for_fade: float = 4.0

var _material: ShaderMaterial
var _base_opacity: float


func _ready() -> void:
	_base_opacity = shadow_opacity
	_setup_mesh()
	_setup_material()
	
	# Wichtig: Top-Level damit Position unabhängig vom Parent ist
	top_level = true
	
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _setup_mesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(shadow_width, shadow_depth)
	quad.orientation = PlaneMesh.FACE_Y
	mesh = quad


func _setup_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = _create_shader()
	_material.set_shader_parameter("shadow_color", shadow_color)
	_material.set_shader_parameter("shadow_opacity", shadow_opacity)
	_material.set_shader_parameter("softness", softness)
	material_override = _material


func _create_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.05, 1.0);
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.35;
uniform float softness : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	float inner = 1.0 - softness;
	float alpha = 1.0 - smoothstep(inner, 1.0, dist);
	alpha *= alpha;

	ALBEDO = shadow_color.rgb;
	ALPHA = alpha * shadow_opacity;
}
"""
	return shader


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	var parent := get_parent() as Node3D
	if parent == null:
		return
	
	# Startpunkt: Parent-Position mit Z-Offset (Füße)
	var ray_origin := parent.global_position + Vector3(0.0, 0.5, z_offset)
	var ray_end := ray_origin + Vector3(0.0, -ray_length, 0.0)
	
	# Raycast
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return
	
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, ground_mask)
	query.exclude = _get_parent_rids(parent)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result := space_state.intersect_ray(query)
	
	if result.is_empty():
		visible = false
		return
	
	visible = true
	
	# Schatten auf Trefferpunkt setzen
	var hit_point: Vector3 = result.position
	var hit_normal: Vector3 = result.normal
	
	global_position = hit_point + hit_normal * ground_offset
	
	# Rotation an Bodennormale anpassen (für Hänge)
	if hit_normal != Vector3.UP:
		var up := hit_normal
		var forward := Vector3.FORWARD
		if abs(up.dot(Vector3.FORWARD)) > 0.99:
			forward = Vector3.RIGHT
		var right := up.cross(forward).normalized()
		forward = right.cross(up).normalized()
		global_basis = Basis(right, up, forward)
	else:
		global_rotation = Vector3.ZERO
	
	# Höhe über dem Boden berechnen
	var height_above_ground := parent.global_position.y - hit_point.y
	height_above_ground = max(0.0, height_above_ground)
	
	# Skalierung bei Sprung (Schatten wird kleiner je höher)
	if scale_with_height and height_above_ground > 0.1:
		var t :float = clamp(height_above_ground / max_height_for_scale, 0.0, 1.0)
		var s :float = lerp(1.0, min_scale_factor, t)
		scale = Vector3(s, 1.0, s)
	else:
		scale = Vector3.ONE
	
	# Opacity-Fade bei Sprung (Schatten wird heller je höher)
	if fade_with_height and _material:
		var t :float= clamp(height_above_ground / max_height_for_fade, 0.0, 1.0)
		var current_opacity : Variant= lerp(_base_opacity, 0.0, t)
		_material.set_shader_parameter("shadow_opacity", current_opacity)
	elif _material:
		_material.set_shader_parameter("shadow_opacity", _base_opacity)


func _get_parent_rids(parent: Node3D) -> Array[RID]:
	"""Sammelt RIDs vom Parent damit der Raycast den Character ignoriert"""
	var rids: Array[RID] = []
	if parent is CollisionObject3D:
		rids.append(parent.get_rid())
	for child in parent.get_children():
		if child is CollisionObject3D:
			rids.append(child.get_rid())
	return rids


func _update_mesh_size() -> void:
	if mesh and mesh is QuadMesh:
		(mesh as QuadMesh).size = Vector2(shadow_width, shadow_depth)


# --- Setter ---
func _set_width(v: float) -> void:
	shadow_width = v
	_update_mesh_size()

func _set_depth(v: float) -> void:
	shadow_depth = v
	_update_mesh_size()

func _set_opacity(v: float) -> void:
	shadow_opacity = v
	_base_opacity = v
	if _material:
		_material.set_shader_parameter("shadow_opacity", v)

func _set_color(v: Color) -> void:
	shadow_color = v
	if _material:
		_material.set_shader_parameter("shadow_color", v)

func _set_softness(v: float) -> void:
	softness = v
	if _material:
		_material.set_shader_parameter("softness", v)

extends Node3D
class_name Occludable

@export var fade_speed := 10.0
@export var min_alpha := 0.0
@export var circle_radius := 111.2
@export var circle_softness := 10.6

var _target_fade := 0.0
var _current_fade := 0.0
var _initialized := false
var _materials: Array[StandardMaterial3D] = []
var _mesh_instances: Array[MeshInstance3D] = []
var _player_position := Vector3.ZERO

func _ready() -> void:
	_setup_materials(self)
	_initialized = true

func _setup_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		
		var name_lower := node.name.to_lower()
		if "trunk" in name_lower:
			for child in node.get_children():
				_setup_materials(child)
			return
		
		var orig_mat: Material = mi.get_surface_override_material(0)
		if orig_mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			orig_mat = mi.mesh.surface_get_material(0)
		
		if orig_mat is StandardMaterial3D:
			var mat := orig_mat.duplicate() as StandardMaterial3D
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
			
			mi.material_override = mat
			_materials.append(mat)
			_mesh_instances.append(mi)
	
	for child in node.get_children():
		_setup_materials(child)

func set_occluded(state: bool, player_pos: Vector3 = Vector3.ZERO) -> void:
	_target_fade = 1.0 if state else 0.0
	_player_position = player_pos

func update_player_position(pos: Vector3) -> void:
	_player_position = pos

func _process(delta: float) -> void:
	if not _initialized:
		return
	
	# Prüfen ob wir noch animieren müssen
	var diff : Variant = abs(_current_fade - _target_fade)
	if diff < 0.001:
		# Ziel erreicht - finale Werte setzen falls nötig
		if _current_fade != _target_fade:
			_current_fade = _target_fade
			_update_materials()
		return
	
	# Weiter animieren
	_current_fade = lerp(_current_fade, _target_fade, delta * fade_speed)
	_update_materials()

func _update_materials() -> void:
	for i in _materials.size():
		var mat := _materials[i]
		var mi := _mesh_instances[i]
		
		var dist := Vector2(mi.global_position.x, mi.global_position.z).distance_to(
			Vector2(_player_position.x, _player_position.z)
		)
		
		var circle_mask := smoothstep(circle_radius - circle_softness, circle_radius + circle_softness, dist)
		var target_alpha := lerpf(min_alpha, 1.0, circle_mask)
		var final_alpha := lerpf(1.0, target_alpha, _current_fade)
		
		mat.albedo_color.a = final_alpha

func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

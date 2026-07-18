@tool
class_name DarknessRenderer
extends MeshInstance3D
## Fullscreen-Pass, der alle DarknessVolumes der Szene rendert.
## Ein Node pro Hoehlen-Szene. Ein Draw Call total.
## Setup: MeshInstance3D mit diesem Script, 'shader' und 'edge_noise' zuweisen.

const MAX_VOLUMES := 16

@export var shader: Shader:
	set(value):
		shader = value
		if is_inside_tree():
			_setup_material()

@export var edge_noise: Texture2D:
	set(value):
		edge_noise = value
		_set_param("edge_noise", edge_noise)

@export var darkness_color := Color(0.016, 0.024, 0.045):
	set(value):
		darkness_color = value
		_set_param("darkness_color", darkness_color)

@export_range(0.0, 1.0) var max_opacity := 1.0:
	set(value):
		max_opacity = value
		_set_param("max_opacity", max_opacity)

@export var darken_background := true:
	set(value):
		darken_background = value
		_set_param("darken_background", darken_background)

var _material: ShaderMaterial


func _ready() -> void:
	_setup_mesh()
	_setup_material()
	_push_volumes()


func _process(_delta: float) -> void:
	# Im Editor pro Frame aktualisieren (Volumes werden live gezogen).
	# Zur Laufzeit sind Volumes statisch -> einmalig in _ready gepusht.
	if Engine.is_editor_hint():
		_push_volumes()


## Zur Laufzeit aufrufen, falls Volumes doch mal bewegt/getoggelt werden.
func refresh() -> void:
	_push_volumes()


func _set_param(param: String, value: Variant) -> void:
	if _material:
		_material.set_shader_parameter(param, value)


func _setup_mesh() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	# Niemals wegcullen - der Vertex-Shader macht daraus ein Fullscreen-Quad
	custom_aabb = AABB(Vector3(-1e9, -1e9, -1e9), Vector3(2e9, 2e9, 2e9))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _setup_material() -> void:
	if not shader:
		material_override = null
		_material = null
		return
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.render_priority = 100
	material_override = _material
	# ALLE Parameter pushen - Setter greifen sonst nur bei nachtraeglichen Aenderungen
	_set_param("darkness_color", darkness_color)
	_set_param("max_opacity", max_opacity)
	_set_param("darken_background", darken_background)
	if edge_noise:
		_set_param("edge_noise", edge_noise)
	_push_volumes()


func _push_volumes() -> void:
	if not _material:
		return

	var volumes := get_tree().get_nodes_in_group("darkness_volumes")
	var count := mini(volumes.size(), MAX_VOLUMES)
	if volumes.size() > MAX_VOLUMES:
		push_warning("DarknessRenderer: %d Volumes, Maximum ist %d. Ueberzaehlige werden ignoriert." % [volumes.size(), MAX_VOLUMES])

	var positions := PackedVector3Array()
	var axes_x := PackedVector3Array()
	var axes_y := PackedVector3Array()
	var axes_z := PackedVector3Array()
	var extents := PackedVector3Array()
	var softness := PackedFloat32Array()
	positions.resize(MAX_VOLUMES)
	axes_x.resize(MAX_VOLUMES)
	axes_y.resize(MAX_VOLUMES)
	axes_z.resize(MAX_VOLUMES)
	extents.resize(MAX_VOLUMES)
	softness.resize(MAX_VOLUMES)

	for i in count:
		var vol := volumes[i] as DarknessVolume
		if not vol:
			continue
		var data := vol.get_volume_data()
		positions[i] = data.pos
		axes_x[i] = data.axis_x
		axes_y[i] = data.axis_y
		axes_z[i] = data.axis_z
		extents[i] = data.extents
		softness[i] = data.softness

	_material.set_shader_parameter("volume_count", count)
	_material.set_shader_parameter("volume_pos", positions)
	_material.set_shader_parameter("volume_axis_x", axes_x)
	_material.set_shader_parameter("volume_axis_y", axes_y)
	_material.set_shader_parameter("volume_axis_z", axes_z)
	_material.set_shader_parameter("volume_extents", extents)
	_material.set_shader_parameter("volume_softness", softness)

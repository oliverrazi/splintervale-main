@tool
extends Node3D
class_name ArenaBounds

## Polygon-basiertes Arena-Volumen. XZ-Form via Marker3D-Children,
## Y-Range explizit über min_height / max_height (lokal zu diesem Node).
## Konkave Polygone erlaubt.

@export_group("Height Range")
@export var min_height: float = -2.0
@export var max_height: float = 20.0

@export_group("Debug")
@export var show_in_editor: bool = true
@export var debug_color: Color = Color(0.3, 0.85, 1.0, 1.0)

var _viz: MeshInstance3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
	else:
		set_process(false)
		_cleanup_viz()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if show_in_editor:
		_rebuild_viz()
	else:
		_cleanup_viz()


# === Public API ===

func contains_point(world_pos: Vector3) -> bool:
	var local := to_local(world_pos)
	# Höhencheck zuerst — billig
	if local.y < min_height or local.y > max_height:
		return false
	var poly := _get_polygon_2d()
	if poly.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(Vector2(local.x, local.z), poly)


# === Internals ===

func _get_polygon_2d() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for child in get_children():
		if child is Marker3D:
			pts.append(Vector2(child.position.x, child.position.z))
	return pts


func _ensure_viz() -> void:
	if _viz and is_instance_valid(_viz):
		return
	_viz = MeshInstance3D.new()
	_viz.name = "_ArenaBoundsViz"
	add_child(_viz)
	# owner bleibt null → wird nicht in die Scene gespeichert
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = debug_color
	mat.no_depth_test = false
	_viz.material_override = mat


func _cleanup_viz() -> void:
	if _viz and is_instance_valid(_viz):
		_viz.queue_free()
		_viz = null


func _rebuild_viz() -> void:
	_ensure_viz()
	var poly := _get_polygon_2d()
	if poly.size() < 2:
		_viz.mesh = null
		return

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var a_lo := Vector3(a.x, min_height, a.y)
		var b_lo := Vector3(b.x, min_height, b.y)
		var a_hi := Vector3(a.x, max_height, a.y)
		var b_hi := Vector3(b.x, max_height, b.y)
		# unterer Ring
		im.surface_add_vertex(a_lo); im.surface_add_vertex(b_lo)
		# oberer Ring
		im.surface_add_vertex(a_hi); im.surface_add_vertex(b_hi)
		# vertikale Kante
		im.surface_add_vertex(a_lo); im.surface_add_vertex(a_hi)
	im.surface_end()
	_viz.mesh = im

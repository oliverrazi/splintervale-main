@tool
class_name WaterBody
extends Node3D

## Wasserfläche mit beliebiger Polygon-Form.
## Füge Marker3D-Kinder hinzu, um die Form zu definieren.
## Der Y-Wert des WaterBody-Nodes bestimmt die Wasserhöhe.

@export var water_material: Material:
	set(v):
		water_material = v
		_dirty = true

@export var subdivisions: int = 24:
	set(v):
		subdivisions = clampi(v, 2, 80)
		_dirty = true

@export var show_outline: bool = true:
	set(v):
		show_outline = v
		_update_outline()

@export var outline_color: Color = Color.CYAN:
	set(v):
		outline_color = v
		_update_outline()

@export_group("Killzone")
@export var killzone_enabled: bool = true:
	set(v):
		killzone_enabled = v
		_dirty = true

## Y-Schwellwert ab dem ertrunken wird (relativ zur Wasseroberfläche, negativ = unter Wasser)
@export var drown_y_threshold: float = 0.1:
	set(v):
		drown_y_threshold = v

@export var killzone_depth: float = 4.0:
	set(v):
		killzone_depth = v
		_dirty = true

@export_flags_3d_physics var killzone_layer: int = 4:
	set(v):
		killzone_layer = v
		if is_instance_valid(_area):
			_area.collision_layer = v

@export_flags_3d_physics var killzone_mask: int = 1:
	set(v):
		killzone_mask = v
		if is_instance_valid(_area):
			_area.collision_mask = v

signal body_entered_water(body: Node3D)
signal body_exited_water(body: Node3D)

var _mesh_inst      : MeshInstance3D
var _debug_inst     : MeshInstance3D
var _area           : Area3D
var _col_shape      : CollisionShape3D
var _dirty          : bool = true
var _last_pos       : PackedVector3Array
var _current_poly   : PackedVector2Array   # aktuelles Polygon für Code-Check
var _bodies_in_bbox : Array[Node3D] = []   # alle Bodies im AABB
var _drowned_bodies : Array[Node3D] = []   # bereits getriggerte Bodies


# ── Lifecycle ────────────────────────────────────────────────

func _ready() -> void:
	_purge_saved_internals()
	_ensure_nodes()
	_dirty = true

func _process(_delta: float) -> void:
	# Marker-Positionen tracken (Editor: Form live nachziehen)
	var cur := _snapshot_positions()
	if cur != _last_pos:
		_last_pos = cur
		_dirty = true

	if _dirty:
		_dirty = false
		_rebuild()

func _physics_process(_delta: float) -> void:
	# Polygon-Containment-Check für Bodies im AABB
	if Engine.is_editor_hint() or not killzone_enabled:
		return
	if _current_poly.size() < 3:
		return

	for body in _bodies_in_bbox:
		if not is_instance_valid(body):
			continue
		if body in _drowned_bodies:
			continue
		var lp := to_local(body.global_position)
		# Body muss auf/unter der Wasseroberfläche sein UND im Polygon liegen
		if lp.y <= drown_y_threshold and Geometry2D.is_point_in_polygon(Vector2(lp.x, lp.z), _current_poly):
			_drowned_bodies.append(body)
			_trigger_drown(body)
			body_entered_water.emit(body)


# ── Node-Setup ───────────────────────────────────────────────

## Entfernt __wbody_*-Nodes, die früher versehentlich mit in die
## Szene gespeichert wurden (Altlasten aus der alten owner-Logik).
func _purge_saved_internals() -> void:
	for child in get_children():  # ohne interne Nodes
		if String(child.name).begins_with("__wbody"):
			child.queue_free()

## Sucht ein internes Node per Name (inkl. interner Kinder).
func _find_internal(node_name: String) -> Node:
	for child in get_children(true):
		if child.name == node_name and not child.is_queued_for_deletion():
			return child
	return null

func _ensure_nodes() -> void:
	# ── Wasser-Mesh ──
	if not is_instance_valid(_mesh_inst):
		_mesh_inst = _find_internal("__wbody_mesh") as MeshInstance3D
	if not is_instance_valid(_mesh_inst):
		_mesh_inst = MeshInstance3D.new()
		_mesh_inst.name = "__wbody_mesh"
		add_child(_mesh_inst, false, Node.INTERNAL_MODE_BACK)

	# ── Debug-Outline ──
	if not is_instance_valid(_debug_inst):
		_debug_inst = _find_internal("__wbody_debug") as MeshInstance3D
	if not is_instance_valid(_debug_inst):
		_debug_inst = MeshInstance3D.new()
		_debug_inst.name = "__wbody_debug"
		_debug_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_inst, false, Node.INTERNAL_MODE_BACK)

	# ── Killzone-Area ──
	if not is_instance_valid(_area):
		_area = _find_internal("__wbody_area") as Area3D
		if is_instance_valid(_area):
			_col_shape = _area.get_node_or_null("Shape")
	if not is_instance_valid(_area):
		_area = Area3D.new()
		_area.name            = "__wbody_area"
		_area.monitoring      = true
		_area.monitorable     = false
		add_child(_area, false, Node.INTERNAL_MODE_BACK)

		_col_shape      = CollisionShape3D.new()
		_col_shape.name = "Shape"
		_area.add_child(_col_shape)

	# Properties + Signale IMMER setzen/prüfen — unabhängig davon,
	# ob die Area gefunden oder neu erzeugt wurde. Das war der Bug:
	# gespeicherte Areas hatten keine Signal-Verbindungen mehr.
	_area.collision_layer = killzone_layer
	_area.collision_mask  = killzone_mask
	if not _area.body_entered.is_connected(_on_bbox_entered):
		_area.body_entered.connect(_on_bbox_entered)
	if not _area.body_exited.is_connected(_on_bbox_exited):
		_area.body_exited.connect(_on_bbox_exited)


# ── Marker-Helfer ─────────────────────────────────────────────

func _get_markers() -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D:
			out.append(child)
	return out

func _snapshot_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for m in _get_markers():
		out.append(m.global_position)
	return out

func _polygon_xz() -> PackedVector2Array:
	var out := PackedVector2Array()
	for m in _get_markers():
		var lp := to_local(m.global_position)
		out.append(Vector2(lp.x, lp.z))
	return out


# ── Rebuild ───────────────────────────────────────────────────

func _rebuild() -> void:
	_ensure_nodes()
	var poly := _polygon_xz()
	_current_poly = poly

	if poly.size() < 3:
		_mesh_inst.mesh  = null
		_col_shape.shape = null
		_update_outline()
		return

	# Mesh
	var mesh := _build_mesh(poly)
	_mesh_inst.mesh = mesh
	if water_material and is_instance_valid(mesh):
		_mesh_inst.set_surface_override_material(0, water_material)

	# Killzone: einzelner BoxShape3D über den AABB des Polygons
	_area.monitoring = killzone_enabled
	if killzone_enabled:
		_col_shape.shape    = _build_aabb_shape(poly)
		_col_shape.position = Vector3(
			(_poly_center(poly)).x,
			(drown_y_threshold - killzone_depth) * 0.5,
			(_poly_center(poly)).y
		)
	else:
		_col_shape.shape = null

	_update_outline()


func _poly_center(poly: PackedVector2Array) -> Vector2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in poly:
		mn.x = minf(mn.x, p.x);  mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x);  mx.y = maxf(mx.y, p.y)
	return (mn + mx) * 0.5


func _build_aabb_shape(poly: PackedVector2Array) -> BoxShape3D:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in poly:
		mn.x = minf(mn.x, p.x);  mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x);  mx.y = maxf(mx.y, p.y)

	var box      := BoxShape3D.new()
	var total_h  := drown_y_threshold + killzone_depth
	box.size = Vector3(mx.x - mn.x, total_h, mx.y - mn.y)
	return box


# ── Mesh ──────────────────────────────────────────────────────

func _build_mesh(poly: PackedVector2Array) -> ArrayMesh:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in poly:
		mn.x = minf(mn.x, p.x);  mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x);  mx.y = maxf(mx.y, p.y)

	var sx := (mx.x - mn.x) / float(subdivisions)
	var sz := (mx.y - mn.y) / float(subdivisions)
	if sx == 0.0 or sz == 0.0:
		return null

	var grid    := {}
	var verts   := PackedVector3Array()
	var uvs     := PackedVector2Array()
	var normals := PackedVector3Array()

	for iz in range(subdivisions + 1):
		for ix in range(subdivisions + 1):
			var wx := mn.x + ix * sx
			var wz := mn.y + iz * sz
			var p2 := Vector2(wx, wz)
			if Geometry2D.is_point_in_polygon(p2, poly):
				grid[Vector2i(ix, iz)] = verts.size()
				verts.append(Vector3(wx, 0.0, wz))
				uvs.append(p2 / 10.0)
				normals.append(Vector3.UP)

	if verts.is_empty():
		return null

	var indices := PackedInt32Array()
	for iz in range(subdivisions):
		for ix in range(subdivisions):
			var k00 := Vector2i(ix,     iz)
			var k10 := Vector2i(ix + 1, iz)
			var k01 := Vector2i(ix,     iz + 1)
			var k11 := Vector2i(ix + 1, iz + 1)
			if (k00 in grid) and (k10 in grid) and (k01 in grid) and (k11 in grid):
				var i00: int = grid[k00]
				var i10: int = grid[k10]
				var i01: int = grid[k01]
				var i11: int = grid[k11]
				indices.append_array(PackedInt32Array([i00, i10, i01, i10, i11, i01]))

	if indices.is_empty():
		return null

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ── Killzone Callbacks ────────────────────────────────────────

func _on_bbox_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if body not in _bodies_in_bbox:
		_bodies_in_bbox.append(body)

func _on_bbox_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	_bodies_in_bbox.erase(body)
	if body in _drowned_bodies:
		_drowned_bodies.erase(body)  # Reset → kann erneut ertrinken
		body_exited_water.emit(body)

func _trigger_drown(body: Node3D) -> void:
	if body is Enemy:
		(body as Enemy).start_drowning()
	elif body.is_in_group("player") and body.has_method("respawn_after_fall"):
		body.respawn_after_fall()


# ── Debug-Outline ─────────────────────────────────────────────

func _update_outline() -> void:
	if not is_instance_valid(_debug_inst):
		return
	if not show_outline or not Engine.is_editor_hint():
		_debug_inst.mesh = null
		return

	var poly := _polygon_xz()
	if poly.size() < 2:
		_debug_inst.mesh = null
		return

	var im  := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color  = outline_color
	mat.no_depth_test = true  # Godot 4: 'flags_no_depth_test' existiert nicht mehr

	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(poly.size() + 1):
		var p := poly[i % poly.size()]
		im.surface_add_vertex(Vector3(p.x, 0.05, p.y))
	im.surface_end()

	_debug_inst.mesh = im
	_debug_inst.set_surface_override_material(0, mat)

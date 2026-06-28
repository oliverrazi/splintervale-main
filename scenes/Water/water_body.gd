@tool
class_name WaterBody
extends Node3D

## Wasserfläche mit beliebiger Polygon-Form.
## Füge Marker3D-Kinder hinzu, um die Form zu definieren (im Uhrzeigersinn oder CCW).
## Der Y-Wert des WaterBody-Nodes bestimmt die Wasserhöhe — ideal für Kaskaden.

@export var water_material: Material:
	set(v):
		water_material = v
		_dirty = true

## Unterteilungen des Meshes pro Achse – höher = bessere Wellen-Verformung
@export var subdivisions: int = 24:
	set(v):
		subdivisions = clampi(v, 2, 80)
		_dirty = true

## Debug-Outline im Editor anzeigen
@export var show_outline: bool = true:
	set(v):
		show_outline = v
		_update_outline()

## Farbe der Debug-Outline
@export var outline_color: Color = Color.CYAN:
	set(v):
		outline_color = v
		_update_outline()

@export_group("Killzone")

## Area3D-Killzone an die Polygon-Form binden
@export var killzone_enabled: bool = true:
	set(v):
		killzone_enabled = v
		_dirty = true

## Wie weit die Kollisionszone nach unten geht (für fallende Spieler)
@export var killzone_depth: float = 4.0:
	set(v):
		killzone_depth = v
		_dirty = true

## Wie weit die Zone über die Wasseroberfläche ragt
@export var killzone_above: float = 0.3:
	set(v):
		killzone_above = v
		_dirty = true

## Collision Layer der Area3D
@export_flags_3d_physics var killzone_layer: int = 4:
	set(v):
		killzone_layer = v
		if is_instance_valid(_area):
			_area.collision_layer = v

## Collision Mask der Area3D
@export_flags_3d_physics var killzone_mask: int = 1:
	set(v):
		killzone_mask = v
		if is_instance_valid(_area):
			_area.collision_mask = v

## Wird ausgelöst wenn ein Body die Wasserzone betritt
signal body_entered_water(body: Node3D)
## Wird ausgelöst wenn ein Body die Wasserzone verlässt
signal body_exited_water(body: Node3D)

var _mesh_inst  : MeshInstance3D
var _debug_inst : MeshInstance3D
var _area       : Area3D
var _col_shape  : CollisionShape3D
var _dirty      : bool = true
var _last_pos   : PackedVector3Array


# ── Lifecycle ────────────────────────────────────────────────

func _ready() -> void:
	_ensure_nodes()
	_dirty = true

func _process(_delta: float) -> void:
	var cur := _snapshot_positions()
	if cur != _last_pos:
		_last_pos = cur
		_dirty = true

	if _dirty:
		_dirty = false
		_rebuild()


# ── Node-Setup ───────────────────────────────────────────────

func _ensure_nodes() -> void:
	# Wasser-Mesh
	if not is_instance_valid(_mesh_inst):
		for child in get_children():
			if child is MeshInstance3D and child.name == "__wbody_mesh":
				_mesh_inst = child
				break
		if not is_instance_valid(_mesh_inst):
			_mesh_inst = MeshInstance3D.new()
			_mesh_inst.name = "__wbody_mesh"
			add_child(_mesh_inst)
			if Engine.is_editor_hint():
				_mesh_inst.owner = get_tree().edited_scene_root

	# Debug-Outline
	if not is_instance_valid(_debug_inst):
		for child in get_children():
			if child is MeshInstance3D and child.name == "__wbody_debug":
				_debug_inst = child
				break
		if not is_instance_valid(_debug_inst):
			_debug_inst = MeshInstance3D.new()
			_debug_inst.name = "__wbody_debug"
			_debug_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_debug_inst)
			if Engine.is_editor_hint():
				_debug_inst.owner = get_tree().edited_scene_root

	# Killzone Area3D
	if not is_instance_valid(_area):
		for child in get_children():
			if child is Area3D and child.name == "__wbody_area":
				_area = child
				_col_shape = _area.get_node_or_null("Shape")
				break
		if not is_instance_valid(_area):
			_area = Area3D.new()
			_area.name           = "__wbody_area"
			_area.collision_layer = killzone_layer
			_area.collision_mask  = killzone_mask
			_area.monitoring      = true
			_area.monitorable     = false
			_area.body_entered.connect(_on_body_entered)
			_area.body_exited.connect(_on_body_exited)
			add_child(_area)
			if Engine.is_editor_hint():
				_area.owner = get_tree().edited_scene_root

			_col_shape      = CollisionShape3D.new()
			_col_shape.name = "Shape"
			_area.add_child(_col_shape)
			if Engine.is_editor_hint():
				_col_shape.owner = get_tree().edited_scene_root


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

	if poly.size() < 3:
		_mesh_inst.mesh   = null
		_col_shape.shape  = null
		_update_outline()
		return

	# Mesh
	var mesh := _build_mesh(poly)
	_mesh_inst.mesh = mesh
	if water_material and is_instance_valid(mesh):
		_mesh_inst.set_surface_override_material(0, water_material)

	# Killzone
	_area.monitoring = killzone_enabled
	if killzone_enabled:
		_col_shape.shape = _build_killzone_shape(poly)
	else:
		_col_shape.shape = null

	_update_outline()


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


# ── Killzone Shape ────────────────────────────────────────────

func _build_killzone_shape(poly: PackedVector2Array) -> ConcavePolygonShape3D:
	var tri_idx := Geometry2D.triangulate_polygon(poly)
	if tri_idx.is_empty():
		return null

	var top := killzone_above
	var bot := -killzone_depth
	var faces := PackedVector3Array()

	for i in range(0, tri_idx.size(), 3):
		var a2 := poly[tri_idx[i]]
		var b2 := poly[tri_idx[i + 1]]
		var c2 := poly[tri_idx[i + 2]]

		var at := Vector3(a2.x, top, a2.y)
		var bt := Vector3(b2.x, top, b2.y)
		var ct := Vector3(c2.x, top, c2.y)
		var ab := Vector3(a2.x, bot, a2.y)
		var bb := Vector3(b2.x, bot, b2.y)
		var cb := Vector3(c2.x, bot, c2.y)

		# Deckel (oben)
		faces.append_array([at, bt, ct])
		# Boden (unten, umgekehrt)
		faces.append_array([ab, cb, bb])
		# Seiten (3 Quads = 6 Dreiecke)
		faces.append_array([at, ab, bb]);  faces.append_array([at, bb, bt])
		faces.append_array([bt, bb, cb]);  faces.append_array([bt, cb, ct])
		faces.append_array([ct, cb, ab]);  faces.append_array([ct, ab, at])

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


# ── Killzone Callbacks ────────────────────────────────────────

func _on_body_entered(body: Node3D) -> void:
	body_entered_water.emit(body)

func _on_body_exited(body: Node3D) -> void:
	body_exited_water.emit(body)


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
	mat.shading_mode        = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color        = outline_color
	mat.flags_no_depth_test = true

	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(poly.size() + 1):
		var p := poly[i % poly.size()]
		im.surface_add_vertex(Vector3(p.x, 0.05, p.y))
	im.surface_end()

	_debug_inst.mesh = im
	_debug_inst.set_surface_override_material(0, mat)

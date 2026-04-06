@tool
class_name CaveWallPlacer
extends Node3D
## ═══════════════════════════════════════════════════════════════
## CaveWallPlacer — Blender-Wandmodule, Ecken & Bodenkanten
## ═══════════════════════════════════════════════════════════════
## BLENDER-KONVENTION:
##   X = Breite (entlang der Wand), Y = Höhe, Z = Tiefe
##   Origin = untere linke Ecke der Innenseite
##   Export als .glb mit +Y Up
## ═══════════════════════════════════════════════════════════════

@export_group("Wand-Meshes")
## Gerade Wandmodule (Variationen). Gleiche Höhe empfohlen.
@export var wall_meshes: Array[Mesh] = []: set = _set_wall_meshes
## Innenecke — wird an Vertices platziert wo zwei Wände aufeinandertreffen.
## Leer = keine speziellen Ecken, Wände stoßen stumpf aneinander.
@export var corner_inner_meshes: Array[Mesh] = []: set = _set_corner_inner_meshes

@export_group("Bodenkanten-Meshes")
## Module für offene Kanten (Klippen/Abgründe).
## Werden an Kanten platziert die KEINE Wand haben.
@export var floor_edge_meshes: Array[Mesh] = []: set = _set_floor_edge_meshes

@export_group("Kanten")
## true = Wand, false = offen (Klippe/Eingang → bekommt floor_edge).
## Leer = ALLE Kanten bekommen Wände.
@export var edge_mask: Array[bool] = []: set = _set_edge_mask

@export_group("Skalierung")
## Globale Skalierung aller Wandmodule. Verkleinern/Vergrößern ohne Lücken.
@export_range(0.1, 3.0, 0.05) var wall_scale: float = 1.0: set = _set_wall_scale
## Skalierung der Innenecken
@export_range(0.1, 3.0, 0.05) var corner_scale: float = 1.0: set = _set_corner_scale
## Skalierung der Bodenkanten-Module
@export_range(0.1, 3.0, 0.05) var floor_edge_scale: float = 1.0: set = _set_floor_edge_scale

@export_group("Platzierung")
## Y-Offset relativ zum CavePiece top_y
@export var y_offset: float = 0.0: set = _set_y_offset
## Module vertikal stapeln (für höhere Wände)
@export_range(1, 5) var vertical_stacks: int = 1: set = _set_vertical_stacks
## Versatz nach außen
@export_range(-1.0, 1.0, 0.05) var outward_offset: float = 0.0: set = _set_outward_offset
## Zufällige Rotation pro Modul (Grad)
@export_range(0.0, 5.0, 0.1) var rotation_jitter_deg: float = 0.0: set = _set_rotation_jitter
## Zufälliger Versatz entlang der Wand
@export_range(0.0, 0.3, 0.01) var position_jitter: float = 0.0: set = _set_position_jitter
## Zufälliger Tiefenversatz
@export_range(0.0, 0.2, 0.01) var depth_jitter: float = 0.0: set = _set_depth_jitter
## Skalierungsvariation (±)
@export_range(0.0, 0.15, 0.01) var scale_variation: float = 0.0: set = _set_scale_variation

@export_group("Allgemein")
@export var placement_seed: int = 42: set = _set_placement_seed
@export var wall_material: Material = null: set = _set_wall_material
@export var floor_edge_material: Material = null: set = _set_floor_edge_material
@export var corner_material: Material = null: set = _set_corner_material
@export var auto_update: bool = true: set = _set_auto_update

var _dirty: bool = true
var _rng := RandomNumberGenerator.new()
var _generated: Array[Node] = []
var _parent_poly_cache: PackedVector2Array = PackedVector2Array()


# ═════════════════════════════════════════════════════════════
# LIFECYCLE
# ═════════════════════════════════════════════════════════════

func _ready() -> void:
	_rebuild()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or not auto_update:
		return
	var piece := _get_piece()
	if not piece:
		return
	var poly := piece.get_polygon()
	if poly != _parent_poly_cache:
		_parent_poly_cache = poly
		_dirty = true
	if _dirty:
		_dirty = false
		_rebuild()


func regenerate() -> void:
	_dirty = false
	_rebuild()


func _get_piece() -> CavePiece:
	var p := get_parent()
	if p is CavePiece:
		return p as CavePiece
	return null


# ═════════════════════════════════════════════════════════════
# REBUILD
# ═════════════════════════════════════════════════════════════

func _rebuild() -> void:
	var piece := _get_piece()
	if not piece:
		return
	var poly := piece.get_polygon()
	if poly.size() < 3:
		return

	_parent_poly_cache = poly
	_rng.seed = placement_seed
	_clear()

	var y_top: float = piece.top_y + y_offset
	var center := _poly_center(poly)
	var pc := poly.size()

	var wall_xf: Dictionary = {}
	var corner_xf: Dictionary = {}
	var edge_xf: Dictionary = {}

	# Welche Kanten sind Wände?
	var wall_edges: Array[bool] = []
	for i in range(pc):
		if edge_mask.size() > 0 and i < edge_mask.size():
			wall_edges.append(edge_mask[i])
		else:
			wall_edges.append(true)

	# ── Gerade Wände + Bodenkanten ──
	for ei in range(pc):
		var a := poly[ei]
		var b := poly[(ei + 1) % pc]
		var edge_vec := b - a
		var edge_len := edge_vec.length()
		if edge_len < 0.1:
			continue
		var edge_dir := edge_vec.normalized()

		var perp := Vector2(edge_dir.y, -edge_dir.x)
		var edge_mid := (a + b) * 0.5
		if perp.dot((edge_mid - center).normalized()) < 0:
			perp = -perp
		var outward_3d := Vector3(perp.x, 0.0, perp.y)
		var edge_dir_3d := Vector3(edge_dir.x, 0.0, edge_dir.y)

		if wall_edges[ei] and wall_meshes.size() > 0:
			_fill_edge(a, b, edge_len, edge_dir_3d, outward_3d,
				y_top, wall_meshes, wall_xf, wall_scale)
		elif not wall_edges[ei] and floor_edge_meshes.size() > 0:
			_fill_edge(a, b, edge_len, edge_dir_3d, outward_3d,
				y_top, floor_edge_meshes, edge_xf, floor_edge_scale)

	# ── Innenecken ──
	if corner_inner_meshes.size() > 0:
		for vi in range(pc):
			var prev_ei := (vi - 1 + pc) % pc
			var next_ei := vi
			# Ecke nur wenn beide anliegenden Kanten Wände sind
			if not wall_edges[prev_ei] or not wall_edges[next_ei]:
				continue

			var prev_a := poly[prev_ei]
			var curr := poly[vi]
			var next_b := poly[(vi + 1) % pc]

			_place_corner(prev_a, curr, next_b, center, y_top,
				corner_inner_meshes, corner_xf)

	# ── MultiMeshes ──
	_build_mm(wall_xf, wall_meshes, wall_material, "Walls")
	_build_mm(edge_xf, floor_edge_meshes, floor_edge_material, "FloorEdges")
	_build_mm(corner_xf, corner_inner_meshes, corner_material, "Corners")


# ═════════════════════════════════════════════════════════════
# KANTE FÜLLEN — Lückenlos, AABB-basiert
# ═════════════════════════════════════════════════════════════

func _fill_edge(a: Vector2, b: Vector2, edge_len: float,
		edge_dir_3d: Vector3, outward_3d: Vector3, y_top: float,
		meshes: Array[Mesh], xf: Dictionary, sc: float) -> void:

	var basis := _wall_basis(edge_dir_3d, outward_3d)

	# AABBs cachen
	var aabbs: Array[AABB] = []
	for m in meshes:
		aabbs.append(m.get_aabb())

	var cursor := 0.0

	while cursor < edge_len:
		var mi := _rng.randi_range(0, meshes.size() - 1)
		var aabb := aabbs[mi]
		var module_width := aabb.size.x * sc
		var remaining := edge_len - cursor

		# Letztes Modul: X-Skalierung anpassen damit es genau passt
		var x_scale_factor := 1.0
		if remaining < module_width:
			if remaining < module_width * 0.2:
				break
			x_scale_factor = remaining / module_width

		var actual_width := module_width * x_scale_factor

		for stack in range(vertical_stacks):
			var stack_y := aabb.size.y * sc * float(stack)

			# Position: Mitte des Moduls entlang der Kante
			var t := (cursor + actual_width * 0.5) / edge_len
			t = clampf(t, 0.0, 1.0)
			var pos_2d := a.lerp(b, t)

			var pos := Vector3(pos_2d.x, y_top + stack_y, pos_2d.y)

			# AABB-Origin korrigieren
			pos -= edge_dir_3d * aabb.position.x * sc * x_scale_factor
			pos.y -= aabb.position.y * sc

			# Outward
			pos += outward_3d * outward_offset
			pos -= outward_3d * aabb.position.z * sc

			# Jitter
			if position_jitter > 0.0:
				pos += edge_dir_3d * _rng.randf_range(-position_jitter, position_jitter)
			if depth_jitter > 0.0:
				pos += outward_3d * _rng.randf_range(-depth_jitter, depth_jitter)

			# Rotation
			var rot := basis
			if rotation_jitter_deg > 0.0:
				rot = rot.rotated(Vector3.UP, deg_to_rad(_rng.randf_range(-rotation_jitter_deg, rotation_jitter_deg)))

			# Skalierung: global × anpassung × variation
			var sx := sc * x_scale_factor
			var sy := sc
			var sz := sc
			if scale_variation > 0.0:
				sx *= (1.0 + _rng.randf_range(-scale_variation, scale_variation))
				sy *= (1.0 + _rng.randf_range(-scale_variation * 0.5, scale_variation * 0.5))
				sz *= (1.0 + _rng.randf_range(-scale_variation, scale_variation))

			var final_basis := Basis(rot.x * sx, rot.y * sy, rot.z * sz)

			if not xf.has(mi): xf[mi] = []
			xf[mi].append(Transform3D(final_basis, pos))

		# Cursor: exakt die skalierte Breite weiter → keine Lücken
		cursor += actual_width


# ═════════════════════════════════════════════════════════════
# ECKEN — An Vertices wo zwei Wände aufeinandertreffen
# ═════════════════════════════════════════════════════════════

func _place_corner(prev_a: Vector2, vertex: Vector2, next_b: Vector2,
		center: Vector2, y_top: float,
		meshes: Array[Mesh], xf: Dictionary) -> void:

	# Richtungen der beiden anliegenden Kanten
	var dir_in := (vertex - prev_a).normalized()
	var dir_out := (next_b - vertex).normalized()

	# Bisektrix: mittlere Richtung zwischen den beiden Kanten
	var bisect := (dir_in + dir_out).normalized()

	# Outward: weg vom Polygon-Zentrum
	var to_center := (center - vertex).normalized()
	var outward_2d := -to_center

	# Ecke nach außen versetzen
	var pos_2d := vertex + outward_2d * 0.1
	var pos := Vector3(pos_2d.x, y_top, pos_2d.y)

	# Rotation: Z-Achse (Tiefe) zeigt entlang der Bisektrix nach außen
	var outward_3d := Vector3(outward_2d.x, 0.0, outward_2d.y)
	var bisect_3d := Vector3(bisect.x, 0.0, bisect.y)

	# Basis: X entlang Bisektrix, Z nach außen
	var forward := outward_3d.normalized()
	var right := bisect_3d.normalized()
	var up := forward.cross(right).normalized()
	if up.y < 0.0:
		up = -up
		right = -right
	var rot := Basis(right, up, forward)

	var sc := corner_scale
	rot = Basis(rot.x * sc, rot.y * sc, rot.z * sc)

	for stack in range(vertical_stacks):
		var mi := _rng.randi_range(0, meshes.size() - 1)
		var aabb := meshes[mi].get_aabb()
		var stack_pos := pos
		stack_pos.y += aabb.size.y * sc * float(stack)
		stack_pos.y -= aabb.position.y * sc

		if not xf.has(mi): xf[mi] = []
		xf[mi].append(Transform3D(rot, stack_pos))


# ═════════════════════════════════════════════════════════════
# MULTIMESH
# ═════════════════════════════════════════════════════════════

func _build_mm(transforms: Dictionary, meshes: Array[Mesh],
		mat: Material, group: String) -> void:

	for mi in transforms:
		var tlist: Array = transforms[mi]
		if tlist.is_empty() or mi < 0 or mi >= meshes.size():
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[mi]
		mm.instance_count = tlist.size()
		for i in range(tlist.size()):
			mm.set_instance_transform(i, tlist[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [group, mi]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mat:
			mmi.material_override = mat

		add_child(mmi)
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			mmi.owner = get_tree().edited_scene_root
		_generated.append(mmi)


# ═════════════════════════════════════════════════════════════
# HELPERS
# ═════════════════════════════════════════════════════════════

func _wall_basis(edge_dir_3d: Vector3, outward_3d: Vector3) -> Basis:
	var right := edge_dir_3d.normalized()
	var forward := outward_3d.normalized()
	var up := forward.cross(right).normalized()
	if up.y < 0.0:
		up = -up
		right = -right
	return Basis(right, up, forward)


func _poly_center(poly: PackedVector2Array) -> Vector2:
	var r := Vector2.ZERO
	for p in poly: r += p
	return r / float(poly.size())


func _clear() -> void:
	for child in _generated:
		if is_instance_valid(child):
			child.queue_free()
	_generated.clear()
	for child in get_children():
		if child is MultiMeshInstance3D:
			child.queue_free()


# ═════════════════════════════════════════════════════════════
# SETTERS
# ═════════════════════════════════════════════════════════════

func _set_wall_meshes(v: Array[Mesh]) -> void: wall_meshes = v; _dirty = true
func _set_corner_inner_meshes(v: Array[Mesh]) -> void: corner_inner_meshes = v; _dirty = true
func _set_floor_edge_meshes(v: Array[Mesh]) -> void: floor_edge_meshes = v; _dirty = true
func _set_edge_mask(v: Array[bool]) -> void: edge_mask = v; _dirty = true
func _set_wall_scale(v: float) -> void: wall_scale = v; _dirty = true
func _set_corner_scale(v: float) -> void: corner_scale = v; _dirty = true
func _set_floor_edge_scale(v: float) -> void: floor_edge_scale = v; _dirty = true
func _set_y_offset(v: float) -> void: y_offset = v; _dirty = true
func _set_vertical_stacks(v: int) -> void: vertical_stacks = v; _dirty = true
func _set_outward_offset(v: float) -> void: outward_offset = v; _dirty = true
func _set_rotation_jitter(v: float) -> void: rotation_jitter_deg = v; _dirty = true
func _set_position_jitter(v: float) -> void: position_jitter = v; _dirty = true
func _set_depth_jitter(v: float) -> void: depth_jitter = v; _dirty = true
func _set_scale_variation(v: float) -> void: scale_variation = v; _dirty = true
func _set_placement_seed(v: int) -> void: placement_seed = v; _dirty = true
func _set_wall_material(v: Material) -> void: wall_material = v; _dirty = true
func _set_floor_edge_material(v: Material) -> void: floor_edge_material = v; _dirty = true
func _set_corner_material(v: Material) -> void: corner_material = v; _dirty = true
func _set_auto_update(v: bool) -> void: auto_update = v; _dirty = true

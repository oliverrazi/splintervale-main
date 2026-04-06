@tool
class_name CaveRockPlacer
extends Node3D
## ═══════════════════════════════════════════════════════════════
## CaveRockPlacer — Bodenschutt, Stalagmiten & Stalaktiten
## ═══════════════════════════════════════════════════════════════
## Platziert als Kind eines CavePiece automatisch:
##   - Bodenschutt (lose Felsbrocken am Wandfuß)
##   - Stalagmiten (wachsen vom Boden, mit Clustering)
##   - Stalaktiten (hängen von der Decke, optional)
##
## Wände werden separat über CaveWallPlacer gehandhabt.
## Alles über MultiMeshInstance3D für max. Performance.
## ═══════════════════════════════════════════════════════════════

# ── Meshes ───────────────────────────────────────────────────
@export_group("Meshes")
## Felsbrocken für den Boden. Leer = Fallback-Boxen.
@export var ground_meshes: Array[Mesh] = []: set = _set_ground_meshes
## Stalagmit-Meshes (wachsen vom Boden). Leer = Fallback-Kegel.
@export var stalagmite_meshes: Array[Mesh] = []: set = _set_stalagmite_meshes
## Stalaktit-Meshes (hängen von der Decke). Leer = Fallback-Kegel.
@export var stalactite_meshes: Array[Mesh] = []: set = _set_stalactite_meshes

# ── Kantenauswahl ────────────────────────────────────────────
@export_group("Kanten")
## Welche Kanten bekommen Schutt/Stalagmiten? Leer = alle.
@export var edge_mask: Array[bool] = []: set = _set_edge_mask

# ── Boden-Schutt ─────────────────────────────────────────────
@export_group("Boden-Schutt")
@export var scatter_enabled: bool = true: set = _set_scatter_enabled
@export_range(0.5, 5.0, 0.1) var scatter_spacing: float = 1.8: set = _set_scatter_spacing
@export_range(0.2, 4.0, 0.1) var scatter_spread: float = 1.2: set = _set_scatter_spread
@export_range(0.1, 2.0, 0.05) var scatter_scale: float = 0.5: set = _set_scatter_scale
@export_range(0.0, 0.5, 0.05) var scatter_scale_variation: float = 0.2: set = _set_scatter_scale_variation
@export var ground_material: Material = null: set = _set_ground_material

@export_group("Schutthaufen")
## Rubble-Pile-Meshes (größere Schutthaufen am Wandfuß).
## Leer = keine Schutthaufen.
@export var rubble_meshes: Array[Mesh] = []: set = _set_rubble_meshes
@export var rubble_enabled: bool = true: set = _set_rubble_enabled
## Abstand zwischen Schutthaufen
@export_range(2.0, 10.0, 0.5) var rubble_spacing: float = 4.0: set = _set_rubble_spacing
## Chance pro Position
@export_range(0.0, 1.0, 0.05) var rubble_density: float = 0.5: set = _set_rubble_density
## Versatz nach innen
@export_range(0.0, 3.0, 0.1) var rubble_inward: float = 0.3: set = _set_rubble_inward
## Skalierung
@export_range(0.2, 3.0, 0.05) var rubble_scale: float = 1.0: set = _set_rubble_scale
## Skalierungsvariation
@export_range(0.0, 0.5, 0.05) var rubble_scale_variation: float = 0.2: set = _set_rubble_scale_variation
## Material
@export var rubble_material: Material = null: set = _set_rubble_material

# ── Stalagmiten ──────────────────────────────────────────────
@export_group("Stalagmiten")
@export var stalagmites_enabled: bool = true: set = _set_stalagmites_enabled
@export_range(0.5, 6.0, 0.1) var stalagmite_spacing: float = 2.0: set = _set_stalagmite_spacing
@export_range(0.0, 1.0, 0.05) var stalagmite_density: float = 0.7: set = _set_stalagmite_density
@export_range(0.0, 4.0, 0.1) var stalagmite_inward: float = 1.0: set = _set_stalagmite_inward
@export_range(0.0, 2.0, 0.1) var stalagmite_position_jitter: float = 0.5: set = _set_stalagmite_position_jitter
@export_range(0.02, 4.0, 0.05) var stalagmite_scale: float = 1.0: set = _set_stalagmite_scale
@export_range(0.0, 0.8, 0.05) var stalagmite_scale_variation: float = 0.4: set = _set_stalagmite_scale_variation
@export_range(0.0, 25.0, 1.0) var stalagmite_tilt_deg: float = 8.0: set = _set_stalagmite_tilt_deg
@export var stalagmite_scatter_in_room: bool = true: set = _set_stalagmite_scatter_in_room
@export_range(0, 30) var stalagmite_scatter_count: int = 6: set = _set_stalagmite_scatter_count
@export_range(0.0, 1.0, 0.05) var stalagmite_cluster_chance: float = 0.3: set = _set_stalagmite_cluster_chance
@export var stalagmite_material: Material = null: set = _set_stalagmite_material

# ── Stalaktiten ──────────────────────────────────────────────
@export_group("Stalaktiten")
@export var stalactites_enabled: bool = false: set = _set_stalactites_enabled
@export_range(0.5, 6.0, 0.1) var stalactite_spacing: float = 2.5: set = _set_stalactite_spacing
@export_range(0.0, 1.0, 0.05) var stalactite_density: float = 0.6: set = _set_stalactite_density
@export_range(0.0, 3.0, 0.1) var stalactite_inward: float = 0.8: set = _set_stalactite_inward
@export_range(0.0, 2.0, 0.1) var stalactite_position_jitter: float = 0.6: set = _set_stalactite_position_jitter
@export_range(1.0, 15.0, 0.5) var stalactite_ceiling_y: float = 5.0: set = _set_stalactite_ceiling_y
@export_range(0.2, 3.0, 0.05) var stalactite_scale: float = 1.0: set = _set_stalactite_scale
@export_range(0.0, 0.8, 0.05) var stalactite_scale_variation: float = 0.4: set = _set_stalactite_scale_variation
@export_range(0.0, 25.0, 1.0) var stalactite_tilt_deg: float = 10.0: set = _set_stalactite_tilt_deg
@export var stalactite_scatter_in_room: bool = true: set = _set_stalactite_scatter_in_room
@export_range(0, 20) var stalactite_scatter_count: int = 4: set = _set_stalactite_scatter_count
@export var stalactite_material: Material = null: set = _set_stalactite_material

# ── Allgemein ────────────────────────────────────────────────
@export_group("Allgemein")
@export var placement_seed: int = 42: set = _set_placement_seed
@export var auto_update: bool = true: set = _set_auto_update

var _dirty: bool = true
var _rng := RandomNumberGenerator.new()
var _generated: Array[Node] = []
var _parent_poly_cache: PackedVector2Array = PackedVector2Array()
var _fb_ground: Array[Mesh] = []
var _fb_stalactite: Array[Mesh] = []
var _fb_stalagmite: Array[Mesh] = []
var _fb_rubble: Array[Mesh] = []


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
# FALLBACK-MESHES
# ═════════════════════════════════════════════════════════════

func _ensure_fallbacks() -> void:
	if _fb_ground.is_empty():
		for s in [Vector3(0.7, 0.45, 0.6), Vector3(0.5, 0.35, 0.45),
				Vector3(0.85, 0.4, 0.7), Vector3(0.4, 0.3, 0.35)]:
			var b := BoxMesh.new()
			b.size = s
			_fb_ground.append(b)

	if _fb_stalactite.is_empty():
		for c in [[0.15, 1.2, 8], [0.25, 0.8, 8], [0.1, 1.5, 6],
				[0.3, 0.6, 8], [0.18, 1.0, 6]]:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = c[0]
			cone.height = c[1]
			cone.radial_segments = c[2]
			cone.rings = 1
			_fb_stalactite.append(cone)

	if _fb_stalagmite.is_empty():
		for c in [[0.3, 0.05, 1.4, 10], [0.2, 0.03, 1.0, 8],
				[0.4, 0.08, 1.8, 10], [0.15, 0.02, 0.7, 8],
				[0.35, 0.06, 1.2, 8], [0.5, 0.1, 2.2, 10]]:
			var cone := CylinderMesh.new()
			cone.bottom_radius = c[0]
			cone.top_radius = c[1]
			cone.height = c[2]
			cone.radial_segments = c[3]
			cone.rings = 1
			_fb_stalagmite.append(cone)
			
	if _fb_rubble.is_empty():
		for s in [Vector3(1.5, 0.6, 1.2), Vector3(1.0, 0.4, 0.8),
				Vector3(1.8, 0.7, 1.4)]:
			var b := BoxMesh.new()
			b.size = s
			_fb_rubble.append(b)


func _get_ground() -> Array[Mesh]:
	if ground_meshes.size() > 0: return ground_meshes
	_ensure_fallbacks(); return _fb_ground

func _get_stalactites() -> Array[Mesh]:
	if stalactite_meshes.size() > 0: return stalactite_meshes
	_ensure_fallbacks(); return _fb_stalactite

func _get_stalagmites() -> Array[Mesh]:
	if stalagmite_meshes.size() > 0: return stalagmite_meshes
	_ensure_fallbacks(); return _fb_stalagmite

func _get_rubble() -> Array[Mesh]:
	if rubble_meshes.size() > 0: return rubble_meshes
	_ensure_fallbacks(); return _fb_rubble

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

	var y_top: float = piece.top_y
	var center := _poly_center(poly)
	var pc := poly.size()

	var active_ground := _get_ground()
	var active_stalactites := _get_stalactites()
	var active_stalagmites := _get_stalagmites()
	
	var active_rubble := _get_rubble()
	var rubble_xf: Dictionary = {}

	var ground_xf: Dictionary = {}
	var stalactite_xf: Dictionary = {}
	var stalagmite_xf: Dictionary = {}

	# ── Pro Kante ──
	for ei in range(pc):
		if edge_mask.size() > 0 and ei < edge_mask.size():
			if not edge_mask[ei]:
				continue

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
		var outward_2d := perp

		if scatter_enabled and active_ground.size() > 0:
			_place_ground(a, b, edge_len, outward_2d, y_top, active_ground, ground_xf)
		
		if rubble_enabled and active_rubble.size() > 0:
			_place_rubble(a, b, edge_len, outward_2d, y_top, active_rubble, rubble_xf)

		if stalagmites_enabled and active_stalagmites.size() > 0:
			_place_stalagmites_edge(a, b, edge_len, outward_2d, y_top, active_stalagmites, stalagmite_xf)

		if stalactites_enabled and active_stalactites.size() > 0:
			_place_stalactites_edge(a, b, edge_len, outward_2d, y_top, active_stalactites, stalactite_xf)

	# ── Freistehend im Raum ──
	if stalagmites_enabled and stalagmite_scatter_in_room:
		_scatter_stalagmites_room(poly, y_top, active_stalagmites, stalagmite_xf)

	if stalactites_enabled and stalactite_scatter_in_room:
		_scatter_stalactites_room(poly, y_top, active_stalactites, stalactite_xf)

	# ── MultiMeshes erzeugen ──
	_build_mm(ground_xf, active_ground, ground_material, "Ground")
	_build_mm(stalagmite_xf, active_stalagmites, stalagmite_material, "Stalagmites")
	_build_mm(stalactite_xf, active_stalactites, stalactite_material, "Stalactites")
	_build_mm(rubble_xf, active_rubble, rubble_material, "Rubble")

# ═════════════════════════════════════════════════════════════
# BODEN-SCHUTT
# ═════════════════════════════════════════════════════════════

func _place_ground(a: Vector2, b: Vector2, edge_len: float,
		outward_2d: Vector2, y_top: float,
		meshes: Array[Mesh], xf: Dictionary) -> void:

	var num := maxi(1, int(round(edge_len / scatter_spacing)))
	var inward := -outward_2d

	for i in range(num):
		var t := (float(i) + 0.5) / float(num)
		t += _rng.randf_range(-0.2, 0.2)
		t = clampf(t, 0.05, 0.95)

		var pos_2d := a.lerp(b, t)
		pos_2d += inward * _rng.randf_range(0.2, scatter_spread)

		var pos := Vector3(pos_2d.x, y_top - _rng.randf_range(0.0, 0.15), pos_2d.y)

		var s := maxf(0.1, scatter_scale + _rng.randf_range(-scatter_scale_variation, scatter_scale_variation))
		var sv := Vector3(
			s * _rng.randf_range(0.8, 1.2),
			s * _rng.randf_range(0.8, 1.2),
			s * _rng.randf_range(0.8, 1.2))

		var rot := Basis.IDENTITY
		rot = rot.rotated(Vector3.UP, _rng.randf_range(0.0, TAU))
		rot = rot.rotated(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3))
		rot = rot.rotated(Vector3.FORWARD, _rng.randf_range(-0.3, 0.3))
		rot = Basis(rot.x * sv.x, rot.y * sv.y, rot.z * sv.z)

		var mi := _rng.randi_range(0, meshes.size() - 1)
		if not xf.has(mi): xf[mi] = []
		xf[mi].append(Transform3D(rot, pos))


# ═════════════════════════════════════════════════════════════
# STALAGMITEN — Vom Boden, mit Clustering
# ═════════════════════════════════════════════════════════════

func _place_stalagmites_edge(a: Vector2, b: Vector2, edge_len: float,
		outward_2d: Vector2, y_top: float,
		meshes: Array[Mesh], xf: Dictionary) -> void:

	var num := maxi(1, int(round(edge_len / stalagmite_spacing)))
	var inward := -outward_2d
	var side := (b - a).normalized()

	for i in range(num):
		if _rng.randf() > stalagmite_density:
			continue

		var t := (float(i) + 0.5) / float(num)
		t += _rng.randf_range(-0.15, 0.15)
		t = clampf(t, 0.05, 0.95)

		var pos_2d := a.lerp(b, t)
		pos_2d += inward * (stalagmite_inward + _rng.randf_range(0.0, stalagmite_position_jitter))
		pos_2d += side * _rng.randf_range(-stalagmite_position_jitter * 0.3, stalagmite_position_jitter * 0.3)

		_add_stalagmite(pos_2d, y_top, meshes, xf, 1.0)

		if _rng.randf() < stalagmite_cluster_chance:
			for _c in range(_rng.randi_range(1, 2)):
				var off := Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
				_add_stalagmite(pos_2d + off, y_top, meshes, xf, 0.6)


func _scatter_stalagmites_room(poly: PackedVector2Array, y_top: float,
		meshes: Array[Mesh], xf: Dictionary) -> void:

	var bounds := _poly_bounds(poly)
	var placed := 0
	var attempts := 0

	while placed < stalagmite_scatter_count and attempts < stalagmite_scatter_count * 15:
		attempts += 1
		var test := Vector2(
			_rng.randf_range(bounds[0].x, bounds[1].x),
			_rng.randf_range(bounds[0].y, bounds[1].y))

		if not Geometry2D.is_point_in_polygon(test, poly):
			continue
		if not _inside_margin(test, poly, 0.5):
			continue

		_add_stalagmite(test, y_top, meshes, xf, 1.0)
		placed += 1

		if _rng.randf() < stalagmite_cluster_chance:
			for _c in range(_rng.randi_range(1, 3)):
				var off := Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5))
				var cp := test + off
				if Geometry2D.is_point_in_polygon(cp, poly):
					_add_stalagmite(cp, y_top, meshes, xf, 0.5)
					placed += 1

func _place_rubble(a: Vector2, b: Vector2, edge_len: float,
		outward_2d: Vector2, y_top: float,
		meshes: Array[Mesh], xf: Dictionary) -> void:

	var num := maxi(1, int(round(edge_len / rubble_spacing)))
	var inward := -outward_2d

	for i in range(num):
		if _rng.randf() > rubble_density:
			continue

		var t := (float(i) + 0.5) / float(num)
		t += _rng.randf_range(-0.15, 0.15)
		t = clampf(t, 0.05, 0.95)

		var mi := _rng.randi_range(0, meshes.size() - 1)
		var aabb := meshes[mi].get_aabb()

		var pos_2d := a.lerp(b, t)
		pos_2d += inward * (rubble_inward + _rng.randf_range(0.0, 0.5))

		# Y: auf den Boden, AABB-Unterkante berücksichtigen
		var s := maxf(0.1, rubble_scale + _rng.randf_range(-rubble_scale_variation, rubble_scale_variation))
		var y_base := y_top - aabb.position.y * s
		var pos := Vector3(pos_2d.x, y_base, pos_2d.y)

		# Leicht einsinken
		pos.y -= _rng.randf_range(0.0, 0.1)

		var sx := s * _rng.randf_range(0.85, 1.15)
		var sy := s * _rng.randf_range(0.8, 1.2)
		var sz := s * _rng.randf_range(0.85, 1.15)

		# Nur Y-Rotation (Haufen steht aufrecht)
		var rot := Basis.IDENTITY
		rot = rot.rotated(Vector3.UP, _rng.randf_range(0.0, TAU))
		# Minimale Neigung
		rot = rot.rotated(Vector3.RIGHT, _rng.randf_range(-0.1, 0.1))
		rot = Basis(rot.x * sx, rot.y * sy, rot.z * sz)

		if not xf.has(mi): xf[mi] = []
		xf[mi].append(Transform3D(rot, pos))

func _add_stalagmite(pos_2d: Vector2, y_top: float,
		meshes: Array[Mesh], xf: Dictionary, scale_mod: float) -> void:

	var mi := _rng.randi_range(0, meshes.size() - 1)
	var aabb := meshes[mi].get_aabb()

	var s := maxf(0.1, stalagmite_scale + _rng.randf_range(-stalagmite_scale_variation, stalagmite_scale_variation)) * scale_mod
	var sx := s * _rng.randf_range(0.75, 1.25)
	var sy := s * _rng.randf_range(0.7, 1.4)
	var sz := s * _rng.randf_range(0.75, 1.25)

	var y_base := y_top - aabb.position.y * sy
	var pos := Vector3(pos_2d.x, y_base, pos_2d.y)

	var rot := Basis.IDENTITY
	rot = rot.rotated(Vector3.UP, _rng.randf_range(0.0, TAU))
	var tilt := deg_to_rad(stalagmite_tilt_deg)
	rot = rot.rotated(Vector3.RIGHT, _rng.randf_range(-tilt, tilt))
	rot = rot.rotated(Vector3.FORWARD, _rng.randf_range(-tilt, tilt))
	rot = Basis(rot.x * sx, rot.y * sy, rot.z * sz)

	if not xf.has(mi): xf[mi] = []
	xf[mi].append(Transform3D(rot, pos))


# ═════════════════════════════════════════════════════════════
# STALAKTITEN — Von der Decke
# ═════════════════════════════════════════════════════════════

func _place_stalactites_edge(a: Vector2, b: Vector2, edge_len: float,
		outward_2d: Vector2, y_top: float,
		meshes: Array[Mesh], xf: Dictionary) -> void:

	var num := maxi(1, int(round(edge_len / stalactite_spacing)))
	var inward := -outward_2d
	var side := (b - a).normalized()

	for i in range(num):
		if _rng.randf() > stalactite_density:
			continue

		var t := (float(i) + 0.5) / float(num)
		t += _rng.randf_range(-0.15, 0.15)
		t = clampf(t, 0.05, 0.95)

		var pos_2d := a.lerp(b, t)
		pos_2d += inward * (stalactite_inward + _rng.randf_range(0.0, stalactite_position_jitter))
		pos_2d += side * _rng.randf_range(-stalactite_position_jitter * 0.3, stalactite_position_jitter * 0.3)

		_add_stalactite(Vector3(pos_2d.x, y_top + stalactite_ceiling_y, pos_2d.y), meshes, xf)


func _scatter_stalactites_room(poly: PackedVector2Array, y_top: float,
		meshes: Array[Mesh], xf: Dictionary) -> void:

	var bounds := _poly_bounds(poly)
	var placed := 0
	var attempts := 0

	while placed < stalactite_scatter_count and attempts < stalactite_scatter_count * 10:
		attempts += 1
		var test := Vector2(
			_rng.randf_range(bounds[0].x, bounds[1].x),
			_rng.randf_range(bounds[0].y, bounds[1].y))

		if not Geometry2D.is_point_in_polygon(test, poly):
			continue
		if not _inside_margin(test, poly, 1.0):
			continue

		var y := y_top + stalactite_ceiling_y + _rng.randf_range(-0.5, 0.5)
		_add_stalactite(Vector3(test.x, y, test.y), meshes, xf)
		placed += 1


func _add_stalactite(pos: Vector3, meshes: Array[Mesh], xf: Dictionary) -> void:
	var mi := _rng.randi_range(0, meshes.size() - 1)

	var s := maxf(0.1, stalactite_scale + _rng.randf_range(-stalactite_scale_variation, stalactite_scale_variation))
	var sx := s * _rng.randf_range(0.7, 1.3)
	var sy := s * _rng.randf_range(0.8, 1.5)
	var sz := s * _rng.randf_range(0.7, 1.3)

	var rot := Basis.IDENTITY
	rot = rot.rotated(Vector3.RIGHT, PI)
	rot = rot.rotated(Vector3.UP, _rng.randf_range(0.0, TAU))
	var tilt := deg_to_rad(stalactite_tilt_deg)
	rot = rot.rotated(Vector3.RIGHT, _rng.randf_range(-tilt, tilt))
	rot = rot.rotated(Vector3.FORWARD, _rng.randf_range(-tilt, tilt))
	rot = Basis(rot.x * sx, rot.y * sy, rot.z * sz)

	if not xf.has(mi): xf[mi] = []
	xf[mi].append(Transform3D(rot, pos))


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
# AUFRÄUMEN
# ═════════════════════════════════════════════════════════════

func _clear() -> void:
	for child in _generated:
		if is_instance_valid(child):
			child.queue_free()
	_generated.clear()
	for child in get_children():
		if child is MultiMeshInstance3D:
			child.queue_free()


# ═════════════════════════════════════════════════════════════
# HELPERS
# ═════════════════════════════════════════════════════════════

func _poly_center(poly: PackedVector2Array) -> Vector2:
	var r := Vector2.ZERO
	for p in poly: r += p
	return r / float(poly.size())


func _poly_bounds(poly: PackedVector2Array) -> Array[Vector2]:
	var mn := poly[0]; var mx := poly[0]
	for p in poly:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y)
	return [mn, mx]


func _inside_margin(point: Vector2, poly: PackedVector2Array, margin: float) -> bool:
	var center := _poly_center(poly)
	var to_center := (center - point).normalized()
	return Geometry2D.is_point_in_polygon(point + to_center * margin, poly)


# ═════════════════════════════════════════════════════════════
# SETTERS
# ═════════════════════════════════════════════════════════════

func _set_ground_meshes(v: Array[Mesh]) -> void: ground_meshes = v; _dirty = true
func _set_stalagmite_meshes(v: Array[Mesh]) -> void: stalagmite_meshes = v; _dirty = true
func _set_stalactite_meshes(v: Array[Mesh]) -> void: stalactite_meshes = v; _dirty = true
func _set_edge_mask(v: Array[bool]) -> void: edge_mask = v; _dirty = true
func _set_scatter_enabled(v: bool) -> void: scatter_enabled = v; _dirty = true
func _set_scatter_spacing(v: float) -> void: scatter_spacing = v; _dirty = true
func _set_scatter_spread(v: float) -> void: scatter_spread = v; _dirty = true
func _set_scatter_scale(v: float) -> void: scatter_scale = v; _dirty = true
func _set_scatter_scale_variation(v: float) -> void: scatter_scale_variation = v; _dirty = true
func _set_ground_material(v: Material) -> void: ground_material = v; _dirty = true
func _set_stalagmites_enabled(v: bool) -> void: stalagmites_enabled = v; _dirty = true
func _set_stalagmite_spacing(v: float) -> void: stalagmite_spacing = v; _dirty = true
func _set_stalagmite_density(v: float) -> void: stalagmite_density = v; _dirty = true
func _set_stalagmite_inward(v: float) -> void: stalagmite_inward = v; _dirty = true
func _set_stalagmite_position_jitter(v: float) -> void: stalagmite_position_jitter = v; _dirty = true
func _set_stalagmite_scale(v: float) -> void: stalagmite_scale = v; _dirty = true
func _set_stalagmite_scale_variation(v: float) -> void: stalagmite_scale_variation = v; _dirty = true
func _set_stalagmite_tilt_deg(v: float) -> void: stalagmite_tilt_deg = v; _dirty = true
func _set_stalagmite_scatter_in_room(v: bool) -> void: stalagmite_scatter_in_room = v; _dirty = true
func _set_stalagmite_scatter_count(v: int) -> void: stalagmite_scatter_count = v; _dirty = true
func _set_stalagmite_cluster_chance(v: float) -> void: stalagmite_cluster_chance = v; _dirty = true
func _set_stalagmite_material(v: Material) -> void: stalagmite_material = v; _dirty = true
func _set_stalactites_enabled(v: bool) -> void: stalactites_enabled = v; _dirty = true
func _set_stalactite_spacing(v: float) -> void: stalactite_spacing = v; _dirty = true
func _set_stalactite_density(v: float) -> void: stalactite_density = v; _dirty = true
func _set_stalactite_inward(v: float) -> void: stalactite_inward = v; _dirty = true
func _set_stalactite_position_jitter(v: float) -> void: stalactite_position_jitter = v; _dirty = true
func _set_stalactite_ceiling_y(v: float) -> void: stalactite_ceiling_y = v; _dirty = true
func _set_stalactite_scale(v: float) -> void: stalactite_scale = v; _dirty = true
func _set_stalactite_scale_variation(v: float) -> void: stalactite_scale_variation = v; _dirty = true
func _set_stalactite_tilt_deg(v: float) -> void: stalactite_tilt_deg = v; _dirty = true
func _set_stalactite_scatter_in_room(v: bool) -> void: stalactite_scatter_in_room = v; _dirty = true
func _set_stalactite_scatter_count(v: int) -> void: stalactite_scatter_count = v; _dirty = true
func _set_stalactite_material(v: Material) -> void: stalactite_material = v; _dirty = true
func _set_placement_seed(v: int) -> void: placement_seed = v; _dirty = true
func _set_auto_update(v: bool) -> void: auto_update = v; _dirty = true
func _set_rubble_meshes(v: Array[Mesh]) -> void: rubble_meshes = v; _dirty = true
func _set_rubble_enabled(v: bool) -> void: rubble_enabled = v; _dirty = true
func _set_rubble_spacing(v: float) -> void: rubble_spacing = v; _dirty = true
func _set_rubble_density(v: float) -> void: rubble_density = v; _dirty = true
func _set_rubble_inward(v: float) -> void: rubble_inward = v; _dirty = true
func _set_rubble_scale(v: float) -> void: rubble_scale = v; _dirty = true
func _set_rubble_scale_variation(v: float) -> void: rubble_scale_variation = v; _dirty = true
func _set_rubble_material(v: Material) -> void: rubble_material = v; _dirty = true

@tool
class_name FloorScatter
extends Node3D
## ═══════════════════════════════════════════════════════════════
## FloorScatter — Zufällige kleine Steine auf dem Boden
## ═══════════════════════════════════════════════════════════════
## Als Kind eines CavePiece: streut kleine Meshes auf den Boden.
## Nutzt direkt MultiMesh (kein Baking nötig).
## ═══════════════════════════════════════════════════════════════

@export_group("Meshes")
## Kleine Stein-Meshes. Leer = Fallback-Boxen.
@export var meshes: Array[Mesh] = []: set = _set_meshes

@export_group("Platzierung")
@export_range(1, 200) var count: int = 30: set = _set_count
@export_range(0.1, 2.0, 0.05) var scale_min: float = 0.15: set = _set_scale_min
@export_range(0.1, 2.0, 0.05) var scale_max: float = 0.5: set = _set_scale_max
## Mindestabstand vom Polygonrand
@export_range(0.0, 3.0, 0.1) var edge_margin: float = 0.3: set = _set_edge_margin
@export var material_override: Material = null: set = _set_material
@export var placement_seed: int = 42: set = _set_seed

var _dirty: bool = true
var _generated: Array[Node] = []
var _rng := RandomNumberGenerator.new()
var _fallback: Array[Mesh] = []
var _parent_poly_cache: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	# Deferred: warten bis alle Geschwister/Parent geladen sind
	call_deferred("_rebuild")


func _process(_delta: float) -> void:
	var piece := _get_piece()
	if not piece:
		return
	var poly := piece.get_polygon()

	if Engine.is_editor_hint():
		# Editor: live update wenn sich Polygon ändert
		if poly != _parent_poly_cache:
			_parent_poly_cache = poly
			_dirty = true
		if _dirty:
			_dirty = false
			_rebuild()
	else:
		# Runtime: einmalig beim ersten Frame mit gültigem Polygon
		if _generated.is_empty() and poly.size() >= 3:
			_rebuild()


func _get_piece() -> CavePiece:
	var p := get_parent()
	if p is CavePiece:
		return p as CavePiece
	return null


func _get_meshes() -> Array[Mesh]:
	if meshes.size() > 0:
		return meshes
	if _fallback.is_empty():
		for s in [Vector3(0.3, 0.15, 0.25), Vector3(0.2, 0.1, 0.18),
				Vector3(0.15, 0.08, 0.12), Vector3(0.25, 0.12, 0.2)]:
			var b := BoxMesh.new()
			b.size = s
			_fallback.append(b)
	return _fallback


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

	var active := _get_meshes()
	if active.is_empty():
		return

	var y_top: float = piece.top_y
	var bounds := _bounds(poly)
	var xf: Dictionary = {}

	var placed := 0
	var attempts := 0

	while placed < count and attempts < count * 10:
		attempts += 1

		var test := Vector2(
			_rng.randf_range(bounds[0].x, bounds[1].x),
			_rng.randf_range(bounds[0].y, bounds[1].y))

		if not Geometry2D.is_point_in_polygon(test, poly):
			continue

		# Randabstand prüfen
		if edge_margin > 0.0:
			var center := _center(poly)
			var to_c := (center - test).normalized()
			if not Geometry2D.is_point_in_polygon(test + to_c * edge_margin, poly):
				continue

		var mi := _rng.randi_range(0, active.size() - 1)
		var s := _rng.randf_range(scale_min, scale_max)
		var sx := s * _rng.randf_range(0.8, 1.2)
		var sy := s * _rng.randf_range(0.7, 1.3)
		var sz := s * _rng.randf_range(0.8, 1.2)

		var rot := Basis.IDENTITY
		rot = rot.rotated(Vector3.UP, _rng.randf_range(0.0, TAU))
		rot = rot.rotated(Vector3.RIGHT, _rng.randf_range(-0.2, 0.2))
		rot = rot.rotated(Vector3.FORWARD, _rng.randf_range(-0.2, 0.2))
		rot = Basis(rot.x * sx, rot.y * sy, rot.z * sz)

		# Leicht einsinken
		var pos := Vector3(test.x, y_top - _rng.randf_range(0.0, 0.05), test.y)

		if not xf.has(mi): xf[mi] = []
		xf[mi].append(Transform3D(rot, pos))
		placed += 1

	# MultiMeshes erzeugen
	for mi in xf:
		var tlist: Array = xf[mi]
		if tlist.is_empty():
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = active[mi]
		mm.instance_count = tlist.size()
		for i in range(tlist.size()):
			mm.set_instance_transform(i, tlist[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Scatter_%d" % mi
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if material_override:
			mmi.material_override = material_override

		add_child(mmi)
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			mmi.owner = get_tree().edited_scene_root
		_generated.append(mmi)


func _clear() -> void:
	for n in _generated:
		if is_instance_valid(n): n.queue_free()
	_generated.clear()
	for c in get_children():
		if c is MultiMeshInstance3D: c.queue_free()


func _center(poly: PackedVector2Array) -> Vector2:
	var r := Vector2.ZERO
	for p in poly: r += p
	return r / float(poly.size())


func _bounds(poly: PackedVector2Array) -> Array[Vector2]:
	var mn := poly[0]; var mx := poly[0]
	for p in poly:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y)
	return [mn, mx]


func _set_meshes(v: Array[Mesh]) -> void: meshes = v; _dirty = true
func _set_count(v: int) -> void: count = v; _dirty = true
func _set_scale_min(v: float) -> void: scale_min = v; _dirty = true
func _set_scale_max(v: float) -> void: scale_max = v; _dirty = true
func _set_edge_margin(v: float) -> void: edge_margin = v; _dirty = true
func _set_material(v: Material) -> void: material_override = v; _dirty = true
func _set_seed(v: int) -> void: placement_seed = v; _dirty = true

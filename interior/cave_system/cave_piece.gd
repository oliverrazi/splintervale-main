@tool
class_name CavePiece
extends Node3D
## Höhlen-Baustein: Extrudiertes Vieleck mit natürlichen Formen.

@export var use_markers: bool = true: set = _set_use_markers
@export var manual_polygon: PackedVector2Array = PackedVector2Array(): set = _set_manual_polygon

@export_group("Form")
@export_range(0.1, 30.0, 0.1) var depth: float = 4.0: set = _set_depth
@export var top_y: float = 0.0: set = _set_top_y

@export_group("Natürlichkeit")
## Zwischenpunkte pro Kante — mehr = feinere Zacken
@export_range(0, 12) var edge_subdivisions: int = 4: set = _set_edge_subdivisions
## Seitliche Verschiebung der Kantenpunkte
@export_range(0.0, 3.0, 0.05) var edge_noise_strength: float = 0.5: set = _set_edge_noise_strength
## Noise-Frequenz für Kanten (höher = chaotischer)
@export_range(0.1, 5.0, 0.1) var edge_noise_frequency: float = 1.5: set = _set_edge_noise_frequency
## Boden-Subdivision (jedes Dreieck wird 4^n mal unterteilt)
@export_range(0, 3) var surface_subdivisions: int = 2: set = _set_surface_subdivisions
## Höhenvariation auf dem Boden
@export_range(0.0, 2.0, 0.05) var surface_noise_strength: float = 0.15: set = _set_surface_noise_strength
## Vertikale Segmente der Seitenwände
@export_range(1, 8) var side_segments: int = 3: set = _set_side_segments
## Noise-Stärke auf den Seitenwänden (Felsstruktur)
@export_range(0.0, 2.0, 0.05) var side_noise_strength: float = 0.3: set = _set_side_noise_strength
## Noise-Seed (ändern für andere Zufallsform)
@export var noise_seed: int = 42: set = _set_noise_seed

@export_group("UV")
@export_range(0.01, 4.0, 0.01) var top_uv_scale: float = 0.25: set = _set_top_uv_scale
@export_range(0.01, 4.0, 0.01) var side_uv_scale: float = 0.25: set = _set_side_uv_scale
@export_range(0.01, 4.0, 0.01) var bottom_uv_scale: float = 0.25: set = _set_bottom_uv_scale

@export_group("Material")
@export var top_material: Material = null: set = _set_top_material
@export var side_material: Material = null: set = _set_side_material
@export var bottom_material: Material = null: set = _set_bottom_material

@export_group("Optionen")
@export var generate_bottom: bool = true: set = _set_generate_bottom
@export var generate_collision: bool = true: set = _set_generate_collision

@export_group("Boden-Variation")
## Farbvariation über Noise (0 = keine, 1 = stark)
@export_range(0.0, 1.0, 0.05) var color_variation: float = 0.5: set = _set_color_variation
## Noise-Frequenz (kleiner = größere Flecken)
@export_range(0.1, 5.0, 0.1) var color_noise_frequency: float = 0.8: set = _set_color_noise_frequency
## Ab welcher Distanz zum Rand beginnt der Fade (Meter)
## Innerhalb dieser Zone → Farbe fadet zu neutral (1,1,1)
@export_range(0.0, 5.0, 0.1) var edge_fade_distance: float = 1.5: set = _set_edge_fade_distance
## Feuchtigkeit in Senken (steuert Roughness im Shader)
@export_range(0.0, 1.0, 0.05) var wetness_variation: float = 0.3: set = _set_wetness_variation
## Noise-Seed
@export var color_noise_seed: int = 123: set = _set_color_noise_seed

var _mesh_instance: MeshInstance3D = null
var _col_body: StaticBody3D = null
var _noise: FastNoiseLite = null
var _dirty: bool = true
var _last_positions: Array[Vector3] = []


func _ready() -> void:
	_setup_noise()
	_ensure_children()
	_rebuild()
	child_entered_tree.connect(func(_n: Node) -> void: _dirty = true)
	child_exiting_tree.connect(func(_n: Node) -> void: _dirty = true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		if use_markers and _markers_moved():
			_dirty = true
		if _dirty:
			_dirty = false
			_rebuild()


func _setup_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.3
	_noise.seed = noise_seed


func mark_dirty() -> void:
	_dirty = true

# ═════════════════════════════════════════════════════════════
# POLYGON + KANTEN-NOISE
# ═════════════════════════════════════════════════════════════

func get_polygon() -> PackedVector2Array:
	return _read_markers() if use_markers else manual_polygon


## Gibt das Polygon MIT Kanten-Noise zurück (zerklüftete Ränder)
func get_noisy_polygon() -> PackedVector2Array:
	var base := get_polygon()
	if base.size() < 3 or edge_subdivisions == 0:
		return base
	if not _noise:
		_setup_noise()

	var result := PackedVector2Array()
	var center := _poly_center(base)

	for i in range(base.size()):
		var a := base[i]
		var b := base[(i + 1) % base.size()]

		# Original-Punkt immer behalten
		result.append(a)

		# Richtung senkrecht zur Kante (nach außen)
		var edge := b - a
		var perp := Vector2(edge.y, -edge.x).normalized()
		var mid := (a + b) * 0.5
		if perp.dot((mid - center).normalized()) < 0:
			perp = -perp

		# Zwischenpunkte mit Noise einfügen
		for s in range(1, edge_subdivisions + 1):
			var t := float(s) / float(edge_subdivisions + 1)
			var p := a.lerp(b, t)
			# Noise basiert auf Weltposition → konsistent bei Verschiebung
			var n := _noise.get_noise_2d(p.x * edge_noise_frequency, p.y * edge_noise_frequency)
			p += perp * n * edge_noise_strength
			result.append(p)

	return result


func _read_markers() -> PackedVector2Array:
	var result := PackedVector2Array()
	for child in get_children():
		if child is Marker3D:
			result.append(Vector2(child.position.x, child.position.z))
	return result


func _markers_moved() -> bool:
	var markers: Array[Node] = []
	for child in get_children():
		if child is Marker3D:
			markers.append(child)
	if markers.size() != _last_positions.size():
		_cache_positions(markers)
		return true
	for i in range(markers.size()):
		if not markers[i].position.is_equal_approx(_last_positions[i]):
			_cache_positions(markers)
			return true
	return false


func _cache_positions(markers: Array[Node]) -> void:
	_last_positions.clear()
	for m in markers:
		_last_positions.append(m.position)


func create_markers(points: PackedVector2Array) -> void:
	for child in get_children():
		if child is Marker3D:
			child.queue_free()
	for i in range(points.size()):
		var m := Marker3D.new()
		m.name = "P%02d" % i
		m.position = Vector3(points[i].x, 0.0, points[i].y)
		add_child(m)
		if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
			m.owner = get_tree().edited_scene_root
	_dirty = true


# ═════════════════════════════════════════════════════════════
# SETUP
# ═════════════════════════════════════════════════════════════

func _ensure_children() -> void:
	if not _mesh_instance:
		_mesh_instance = get_node_or_null("Mesh") as MeshInstance3D
		if not _mesh_instance:
			_mesh_instance = MeshInstance3D.new()
			_mesh_instance.name = "Mesh"
			add_child(_mesh_instance)
			if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
				_mesh_instance.owner = get_tree().edited_scene_root
	if not _col_body:
		_col_body = get_node_or_null("Col") as StaticBody3D
		if not _col_body:
			_col_body = StaticBody3D.new()
			_col_body.name = "Col"
			add_child(_col_body)
			if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
				_col_body.owner = get_tree().edited_scene_root


func _default_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat


# ═════════════════════════════════════════════════════════════
# REBUILD
# ═════════════════════════════════════════════════════════════

func _rebuild() -> void:
	var base_poly := get_polygon()
	if base_poly.size() < 3:
		return
	_ensure_children()
	if not _noise:
		_setup_noise()

	var poly := get_noisy_polygon()
	if poly.size() < 3:
		return

	var holes := _collect_holes()   # NEU

	var mesh := ArrayMesh.new()

	_add_cap(mesh, poly, top_y, true, top_uv_scale, holes)   # holes durchreichen
	mesh.surface_set_material(0, top_material if top_material else _default_mat(Color(0.25, 0.22, 0.2)))

	_add_sides(mesh, poly)
	mesh.surface_set_material(1, side_material if side_material else _default_mat(Color(0.18, 0.15, 0.13)))

	if generate_bottom:
		_add_cap(mesh, poly, top_y - depth, false, bottom_uv_scale, holes)
		mesh.surface_set_material(2, bottom_material if bottom_material else _default_mat(Color(0.12, 0.1, 0.09)))

	_add_hole_walls(mesh, holes)   # NEU — Lochwände

	_mesh_instance.mesh = mesh

	if generate_collision:
		_build_collision(poly)   # liest weiterhin das ganze Mesh → Lochwände inklusive


# ═════════════════════════════════════════════════════════════
# CAP — mit Subdivision + Surface Noise
# ═════════════════════════════════════════════════════════════

func _add_cap(mesh: ArrayMesh, poly: PackedVector2Array, y: float,
		facing_up: bool, uv_sc: float, holes: Array = []) -> void:
	# NEU: Triangulation mit Löchern statt direktem triangulate_polygon
	var tri_result := _triangulate_with_holes(poly, holes)
	var work_poly: PackedVector2Array = tri_result["verts"]
	var idx: PackedInt32Array = tri_result["indices"]
	if idx.is_empty():
		return

	# Basis-Vertices aus dem (ggf. gebrückten) Polygon
	var verts: Array[Vector3] = []
	for p in work_poly:
		verts.append(Vector3(p.x, y, p.y))
	# Subdivision
	var fv: Array[Vector3] = verts
	var fi: PackedInt32Array = idx
	if surface_subdivisions > 0:
		var r := _subdivide(verts, idx, surface_subdivisions)
		fv = r.v
		fi = r.i

	# Surface Noise (Höhenvariation)
	if surface_noise_strength > 0.0 and _noise:
		for i in range(fv.size()):
			var v := fv[i]
			var n := _noise.get_noise_2d(v.x * 2.5, v.z * 2.5)
			v.y += n * surface_noise_strength
			fv[i] = v

# ── Vertex Colors berechnen ──
	var colors := PackedColorArray()

	var color_noise := FastNoiseLite.new()
	color_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	color_noise.frequency = color_noise_frequency
	color_noise.seed = color_noise_seed

	# Zweiter Noise: größere Flecken für dunkle Zonen
	var dark_noise := FastNoiseLite.new()
	dark_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dark_noise.frequency = color_noise_frequency * 0.4
	dark_noise.seed = color_noise_seed + 333

	# Dritter Noise: Farbtemperatur (warm/kalt)
	var temp_noise := FastNoiseLite.new()
	temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	temp_noise.frequency = color_noise_frequency * 0.3
	temp_noise.seed = color_noise_seed + 555

	# Feuchtigkeit
	var wet_noise := FastNoiseLite.new()
	wet_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wet_noise.frequency = color_noise_frequency * 0.6
	wet_noise.seed = color_noise_seed + 999

	for i in range(fv.size()):
		var v := fv[i]
		var point_2d := Vector2(v.x, v.z)

		# ── Edge-Fade: wie weit sind wir vom Rand entfernt? ──
		var dist_to_edge := _distance_to_polygon_edge(point_2d, poly)
		var interior_factor := 1.0
		if edge_fade_distance > 0.0:
			# 0 = am Rand (neutral), 1 = weit innen (volle Variation)
			interior_factor = clampf(dist_to_edge / edge_fade_distance, 0.0, 1.0)
			# Smoothstep für sanften Übergang
			interior_factor = interior_factor * interior_factor * (3.0 - 2.0 * interior_factor)

		# ── 1. Helligkeits-Noise (kleine Flecken) ──
		var fine_noise := color_noise.get_noise_2d(v.x, v.z)
		# Stärker: [-1,1] → [-variation, +variation*0.5]
		# Dunkler ist stärker als heller (natürlicher)
		var brightness := 1.0 + fine_noise * color_variation * 0.7

		# ── 2. Dunkle Zonen (große Flecken) ──
		var dark := dark_noise.get_noise_2d(v.x, v.z)
		# Nur dunkle Flecken, keine hellen (einseitig)
		if dark < 0.0:
			brightness += dark * color_variation * 0.5

		# ── 3. Höhenbasiert: Senken dunkler ──
		if surface_noise_strength > 0.0:
			var height_factor := (v.y - y) / maxf(surface_noise_strength, 0.01)
			brightness += height_factor * color_variation * 0.3

		# ── 4. Farbtemperatur-Shift ──
		var temp := temp_noise.get_noise_2d(v.x, v.z)
		var r_shift := temp * color_variation * 0.2
		var b_shift := -temp * color_variation * 0.15

		# ── 5. Alles mit Edge-Fade modulieren ──
		# Am Rand → (1, 1, 1, 1) = neutral, kein Effekt
		# Innen → volle Variation
		var r_val := lerpf(1.0, clampf(brightness + r_shift, 0.15, 1.3), interior_factor)
		var g_val := lerpf(1.0, clampf(brightness, 0.15, 1.2), interior_factor)
		var b_val := lerpf(1.0, clampf(brightness + b_shift, 0.15, 1.3), interior_factor)

		# ── 6. Feuchtigkeit (Alpha) — auch mit Edge-Fade ──
		var wetness := wet_noise.get_noise_2d(v.x, v.z)
		wetness = clampf((wetness + 1.0) * 0.5 * wetness_variation, 0.0, 1.0)
		# Senken sind feuchter
		if surface_noise_strength > 0.0:
			var depth := clampf(-(v.y - y) / maxf(surface_noise_strength, 0.01), 0.0, 1.0)
			wetness = clampf(wetness + depth * 0.3, 0.0, 1.0)
		# Am Rand: keine Feuchtigkeit (neutral = trocken = alpha 1)
		wetness *= interior_factor

		colors.append(Color(r_val, g_val, b_val, 1.0 - wetness))

	# ── Arrays zusammenbauen ──
	var normal := Vector3.UP if facing_up else Vector3.DOWN
	var out_verts := PackedVector3Array()
	var out_norms := PackedVector3Array()
	var out_uvs := PackedVector2Array()

	for i in range(fv.size()):
		out_verts.append(fv[i])
		out_norms.append(normal)
		out_uvs.append(Vector2(fv[i].x, fv[i].z) * uv_sc)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_verts
	arrays[Mesh.ARRAY_NORMAL] = out_norms
	arrays[Mesh.ARRAY_TEX_UV] = out_uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = fi
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# ═════════════════════════════════════════════════════════════
# SEITEN — Multi-Segment mit Noise
# ═════════════════════════════════════════════════════════════

func _add_sides(mesh: ArrayMesh, poly: PackedVector2Array) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var pc := poly.size()
	var center := _poly_center(poly)
	var y_top := top_y
	var total_depth := depth
	var acc := 0.0

	for i in range(pc):
		var j := (i + 1) % pc
		var a := poly[i]
		var b := poly[j]

		# Outward-Richtung
		var mid := (a + b) * 0.5
		var outward_2d := (mid - center).normalized()
		var normal := Vector3(outward_2d.x, 0.0, outward_2d.y)

		var edge_len := a.distance_to(b)
		var u0 := acc * side_uv_scale
		var u1 := (acc + edge_len) * side_uv_scale
		acc += edge_len

		# Vertikale Punkte-Reihen (side_segments + 1 Reihen)
		var rows: Array[Array] = []
		for seg in range(side_segments + 1):
			var t := float(seg) / float(side_segments)
			var y_val := y_top - total_depth * t

			var va := Vector3(a.x, y_val, a.y)
			var vb := Vector3(b.x, y_val, b.y)

			# Noise auf mittlere Segmente (nicht Top/Bottom-Kante)
			if seg > 0 and seg < side_segments and side_noise_strength > 0.0:
				var na := _noise.get_noise_3d(va.x * 2.0, va.y * 2.0, va.z * 2.0)
				var nb := _noise.get_noise_3d(vb.x * 2.0, vb.y * 2.0, vb.z * 2.0)
				# Auswärts-Verschiebung (Felsbauch)
				va += Vector3(outward_2d.x, 0, outward_2d.y) * na * side_noise_strength
				vb += Vector3(outward_2d.x, 0, outward_2d.y) * nb * side_noise_strength
				# Leichte Y-Verschiebung
				va.y += na * side_noise_strength * 0.3
				vb.y += nb * side_noise_strength * 0.3

			rows.append([va, vb])

		# Quads zwischen Reihen generieren
		for seg in range(side_segments):
			var v_top_val := float(seg) / float(side_segments) * total_depth * side_uv_scale
			var v_bot_val := float(seg + 1) / float(side_segments) * total_depth * side_uv_scale

			var tl: Vector3 = rows[seg][0]
			var tr: Vector3 = rows[seg][1]
			var bl: Vector3 = rows[seg + 1][0]
			var br: Vector3 = rows[seg + 1][1]

			var base := verts.size()
			verts.append(tl); verts.append(tr)
			verts.append(bl); verts.append(br)
			for _k in range(4):
				norms.append(normal)
			uvs.append(Vector2(u0, v_top_val))
			uvs.append(Vector2(u1, v_top_val))
			uvs.append(Vector2(u0, v_bot_val))
			uvs.append(Vector2(u1, v_bot_val))

			indices.append(base + 0)
			indices.append(base + 2)
			indices.append(base + 1)
			indices.append(base + 1)
			indices.append(base + 2)
			indices.append(base + 3)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# ═════════════════════════════════════════════════════════════
# COLLISION
# ═════════════════════════════════════════════════════════════

func _build_collision(poly: PackedVector2Array) -> void:
	for c in _col_body.get_children():
		c.queue_free()

	# Trimesh-Collision aus dem tatsächlichen Mesh (mit Noise)
	# Das garantiert dass Collision exakt zur sichtbaren Geometrie passt
	if not _mesh_instance or not _mesh_instance.mesh:
		return

	var mesh: ArrayMesh = _mesh_instance.mesh as ArrayMesh
	if not mesh:
		return

	# Faces aus allen Surfaces sammeln (Top + Sides + Bottom)
	var all_faces := PackedVector3Array()

	for surf_idx in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surf_idx)
		if arrays.is_empty():
			continue

		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]

		if indices and indices.size() >= 3:
			# Indexed mesh
			for i in range(0, indices.size(), 3):
				all_faces.append(verts[indices[i]])
				all_faces.append(verts[indices[i + 1]])
				all_faces.append(verts[indices[i + 2]])
		elif verts.size() >= 3:
			# Non-indexed mesh
			for i in range(0, verts.size(), 3):
				all_faces.append(verts[i])
				all_faces.append(verts[i + 1])
				all_faces.append(verts[i + 2])

	if all_faces.is_empty():
		return

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(all_faces)

	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.name = "Shape"
	_col_body.add_child(cs)
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		cs.owner = get_tree().edited_scene_root


# ═════════════════════════════════════════════════════════════
# SUBDIVISION
# ═════════════════════════════════════════════════════════════

func _subdivide(verts: Array[Vector3], idx: PackedInt32Array, levels: int) -> Dictionary:
	var cv: Array[Vector3] = verts.duplicate()
	var ci := idx
	for _l in range(levels):
		var ni := PackedInt32Array()
		var cache := {}
		for t in range(0, ci.size(), 3):
			var i0 := ci[t]; var i1 := ci[t + 1]; var i2 := ci[t + 2]
			var m01 := _midpt(cv, cache, i0, i1)
			var m12 := _midpt(cv, cache, i1, i2)
			var m20 := _midpt(cv, cache, i2, i0)
			ni.append_array(PackedInt32Array([i0, m01, m20]))
			ni.append_array(PackedInt32Array([m01, i1, m12]))
			ni.append_array(PackedInt32Array([m20, m12, i2]))
			ni.append_array(PackedInt32Array([m01, m12, m20]))
		ci = ni
	return { "v": cv, "i": ci }


func _midpt(v: Array[Vector3], c: Dictionary, a: int, b: int) -> int:
	var k := mini(a, b) * 100000 + maxi(a, b)
	if c.has(k):
		return c[k]
	var m := (v[a] + v[b]) * 0.5
	var idx := v.size()
	v.append(m)
	c[k] = idx
	return idx


func _poly_center(poly: PackedVector2Array) -> Vector2:
	var r := Vector2.ZERO
	for p in poly:
		r += p
	return r / float(poly.size())



func _distance_to_polygon_edge(point: Vector2, poly: PackedVector2Array) -> float:
	## Kürzeste Distanz eines Punktes zum nächsten Polygonrand
	var min_dist := INF
	var pc := poly.size()
	for i in range(pc):
		var a := poly[i]
		var b := poly[(i + 1) % pc]
		var dist := _point_to_segment_distance(point, a, b)
		min_dist = minf(min_dist, dist)
	return min_dist


func _point_to_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := p - a
	var t := clampf(ap.dot(ab) / maxf(ab.dot(ab), 0.0001), 0.0, 1.0)
	var closest := a + ab * t
	return p.distance_to(closest)
	
func _triangulate_with_holes(outer: PackedVector2Array,
		holes: Array) -> Dictionary:
	if holes.is_empty():
		return {
			"verts": outer,
			"indices": Geometry2D.triangulate_polygon(outer),
		}

	# Alle Löcher in EINEM Boolean-Durchgang aus dem Boden stanzen.
	# clip_polygons normalisiert Wicklung selbst und liefert bei
	# innenliegenden Löchern Außenkontur (CCW) + Loch-Ring (CW).
	var contours: Array[PackedVector2Array] = [outer]
	for h in holes:
		var hp: PackedVector2Array = h["polygon"]
		var next: Array[PackedVector2Array] = []
		for c in contours:
			var res := Geometry2D.clip_polygons(c, hp)
			for r in res:
				next.append(r)
		contours = next

	# Outer-Ring (größte Fläche) vom Rest trennen. Alle anderen sind Löcher.
	var outer_idx := 0
	var max_area := -1.0
	for i in range(contours.size()):
		var a := _signed_area(contours[i])
		if absf(a) > max_area:
			max_area = absf(a)
			outer_idx = i

	var outer_ring: PackedVector2Array = contours[outer_idx]
	var hole_rings: Array[PackedVector2Array] = []
	for i in range(contours.size()):
		if i != outer_idx:
			hole_rings.append(contours[i])

	return _triangulate_ringed(outer_ring, hole_rings)


func _signed_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	var n := poly.size()
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


func _triangulate_ringed(outer_ring: PackedVector2Array,
		hole_rings: Array[PackedVector2Array]) -> Dictionary:
	# Outer CCW, Löcher CW erzwingen (das erwartet der Ohr-Verketter).
	if _signed_area(outer_ring) < 0.0:
		outer_ring.reverse()
	for i in range(hole_rings.size()):
		if _signed_area(hole_rings[i]) > 0.0:
			hole_rings[i].reverse()

	# Jedes Loch über eine Brücke zum nächstgelegenen Outer-Punkt einnähen —
	# ABER die Brücke wird gegen alle bereits gelegten Brücken auf Schnitt
	# geprüft. Das ist der Schritt, der beim alten _stitch_holes fehlte und
	# der die Reihenfolge-abhängigen Kreuzungen erzeugt hat.
	var merged: PackedVector2Array = outer_ring.duplicate()
	var bridges: Array = []   # Array von [Vector2, Vector2] zum Schnitt-Check

	for ring in hole_rings:
		var beste_brücke := _finde_kreuzungsfreie_bruecke(merged, ring, bridges)
		if beste_brücke.is_empty():
			push_error("CavePiece '%s': kein kreuzungsfreier Brückenpunkt für ein Loch gefunden." % name)
			continue
		var mi: int = beste_brücke["merged_idx"]
		var hi: int = beste_brücke["hole_idx"]

		var neu := PackedVector2Array()
		for k in range(mi + 1):
			neu.append(merged[k])
		for k in range(ring.size() + 1):
			neu.append(ring[(hi + k) % ring.size()])
		neu.append(merged[mi])
		for k in range(mi + 1, merged.size()):
			neu.append(merged[k])

		bridges.append([merged[mi], ring[hi]])
		merged = neu

	var indices := Geometry2D.triangulate_polygon(merged)
	if indices.is_empty():
		push_error("CavePiece '%s': triangulate_polygon nach Verkettung leer." % name)

	return { "verts": merged, "indices": indices }


func _finde_kreuzungsfreie_bruecke(merged: PackedVector2Array,
		ring: PackedVector2Array, bestehende: Array) -> Dictionary:
	# Alle Brücken-Kandidaten nach Länge sortiert durchgehen, die erste
	# nehmen, die keine bestehende Brücke und keine Polygonkante schneidet.
	var kandidaten: Array = []
	for mi in range(merged.size()):
		for hi in range(ring.size()):
			kandidaten.append({
				"merged_idx": mi, "hole_idx": hi,
				"dist": merged[mi].distance_squared_to(ring[hi]),
			})
	kandidaten.sort_custom(func(a, b): return a["dist"] < b["dist"])

	for kand in kandidaten:
		var pm: Vector2 = merged[kand["merged_idx"]]
		var ph: Vector2 = ring[kand["hole_idx"]]
		var frei := true

		# Gegen bestehende Brücken prüfen
		for br in bestehende:
			if _segmente_kreuzen(pm, ph, br[0], br[1]):
				frei = false
				break
		if not frei:
			continue

		# Gegen Kanten des merged-Polygons prüfen (außer die am Brückenpunkt)
		for i in range(merged.size()):
			var a := merged[i]
			var b := merged[(i + 1) % merged.size()]
			if a == pm or b == pm:
				continue
			if _segmente_kreuzen(pm, ph, a, b):
				frei = false
				break
		if not frei:
			continue

		# Gegen Kanten des Loch-Rings prüfen (außer die am Loch-Brückenpunkt)
		for i in range(ring.size()):
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			if a == ph or b == ph:
				continue
			if _segmente_kreuzen(pm, ph, a, b):
				frei = false
				break
		if frei:
			return kand

	return {}


func _segmente_kreuzen(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var r :Variant = Geometry2D.segment_intersects_segment(a1, a2, b1, b2)
	return r != null

# ─── NEU: Lochwände (nach unten extrudiert, Normalen nach innen) ───
func _add_hole_walls(mesh: ArrayMesh, holes: Array) -> void:
	for h in holes:
		var poly: PackedVector2Array = h["polygon"]
		var hole_depth: float = h["depth"]
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()

		var pc := poly.size()
		var center := _poly_center(poly)
		var acc := 0.0

		for i in range(pc):
			var j := (i + 1) % pc
			var a := poly[i]
			var b := poly[j]
			var mid := (a + b) * 0.5
			# Lochwand-Normale zeigt nach INNEN (zum Lochzentrum)
			var inward_2d := (center - mid).normalized()
			var normal := Vector3(inward_2d.x, 0.0, inward_2d.y)

			var edge_len := a.distance_to(b)
			var u0 := acc * side_uv_scale
			var u1 := (acc + edge_len) * side_uv_scale
			acc += edge_len

			var rows: Array[Array] = []
			for seg in range(side_segments + 1):
				var t := float(seg) / float(side_segments)
				var y_val := top_y - hole_depth * t
				var va := Vector3(a.x, y_val, a.y)
				var vb := Vector3(b.x, y_val, b.y)
				if seg > 0 and seg < side_segments and side_noise_strength > 0.0:
					var na := _noise.get_noise_3d(va.x * 2.0, va.y * 2.0, va.z * 2.0)
					var nb := _noise.get_noise_3d(vb.x * 2.0, vb.y * 2.0, vb.z * 2.0)
					# Verschiebung nach innen (Lochwand wölbt sich)
					va += Vector3(inward_2d.x, 0, inward_2d.y) * na * side_noise_strength
					vb += Vector3(inward_2d.x, 0, inward_2d.y) * nb * side_noise_strength
				rows.append([va, vb])

			for seg in range(side_segments):
				var v_top := float(seg) / float(side_segments) * hole_depth * side_uv_scale
				var v_bot := float(seg + 1) / float(side_segments) * hole_depth * side_uv_scale
				var tl: Vector3 = rows[seg][0]
				var tr: Vector3 = rows[seg][1]
				var bl: Vector3 = rows[seg + 1][0]
				var br: Vector3 = rows[seg + 1][1]
				var base := verts.size()
				verts.append(tl); verts.append(tr)
				verts.append(bl); verts.append(br)
				for _k in range(4):
					norms.append(normal)
				uvs.append(Vector2(u0, v_top))
				uvs.append(Vector2(u1, v_top))
				uvs.append(Vector2(u0, v_bot))
				uvs.append(Vector2(u1, v_bot))
				# Winding umgekehrt ggü. Außenwand, weil Normale nach innen zeigt
				indices.append(base + 0)
				indices.append(base + 1)
				indices.append(base + 2)
				indices.append(base + 1)
				indices.append(base + 3)
				indices.append(base + 2)

		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var surf_idx := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var wall_mat: Material = h["material"]
		mesh.surface_set_material(surf_idx,
			wall_mat if wall_mat else (side_material if side_material else _default_mat(Color(0.15, 0.12, 0.1))))


func _collect_holes() -> Array:
	var holes := []
	for child in get_children():
		if child is CaveHole:
			var poly: PackedVector2Array = child.get_hole_polygon()
			if poly.size() >= 3:
				# Optional: Kanten-Noise aufs Loch anwenden
				poly = _apply_hole_noise(child, poly)
				holes.append({
					"polygon": poly,
					"depth": child.hole_depth if child.hole_depth > 0.0 else depth,
					"material": child.wall_material,
				})
	return holes


func _apply_hole_noise(hole: CaveHole, base: PackedVector2Array) -> PackedVector2Array:
	if hole.edge_subdivisions == 0 or hole.edge_noise_strength <= 0.0:
		return base
	if not _noise:
		_setup_noise()

	var result := PackedVector2Array()
	var center := _poly_center(base)
	for i in range(base.size()):
		var a := base[i]
		var b := base[(i + 1) % base.size()]
		result.append(a)
		var edge := b - a
		var perp := Vector2(edge.y, -edge.x).normalized()
		var mid := (a + b) * 0.5
		# Beim Loch: Noise nach INNEN (zum Zentrum) für natürliche Ränder
		if perp.dot((mid - center).normalized()) < 0:
			perp = -perp
		for s in range(1, hole.edge_subdivisions + 1):
			var t := float(s) / float(hole.edge_subdivisions + 1)
			var p := a.lerp(b, t)
			var n := _noise.get_noise_2d(p.x * 1.5, p.y * 1.5)
			p += perp * n * hole.edge_noise_strength
			result.append(p)
	return result

# ═════════════════════════════════════════════════════════════
# SETTERS
# ═════════════════════════════════════════════════════════════

func _set_use_markers(v: bool) -> void: use_markers = v; _dirty = true
func _set_manual_polygon(v: PackedVector2Array) -> void: manual_polygon = v; _dirty = true
func _set_depth(v: float) -> void: depth = v; _dirty = true
func _set_top_y(v: float) -> void: top_y = v; _dirty = true
func _set_edge_subdivisions(v: int) -> void: edge_subdivisions = v; _dirty = true
func _set_edge_noise_strength(v: float) -> void: edge_noise_strength = v; _dirty = true
func _set_edge_noise_frequency(v: float) -> void: edge_noise_frequency = v; _dirty = true
func _set_surface_subdivisions(v: int) -> void: surface_subdivisions = v; _dirty = true
func _set_surface_noise_strength(v: float) -> void: surface_noise_strength = v; _dirty = true
func _set_side_segments(v: int) -> void: side_segments = v; _dirty = true
func _set_side_noise_strength(v: float) -> void: side_noise_strength = v; _dirty = true
func _set_noise_seed(v: int) -> void: noise_seed = v; _setup_noise(); _dirty = true
func _set_top_uv_scale(v: float) -> void: top_uv_scale = v; _dirty = true
func _set_side_uv_scale(v: float) -> void: side_uv_scale = v; _dirty = true
func _set_bottom_uv_scale(v: float) -> void: bottom_uv_scale = v; _dirty = true
func _set_top_material(v: Material) -> void: top_material = v; _dirty = true
func _set_side_material(v: Material) -> void: side_material = v; _dirty = true
func _set_bottom_material(v: Material) -> void: bottom_material = v; _dirty = true
func _set_generate_bottom(v: bool) -> void: generate_bottom = v; _dirty = true
func _set_generate_collision(v: bool) -> void: generate_collision = v; _dirty = true

func _set_color_variation(v: float) -> void: color_variation = v; _dirty = true
func _set_color_noise_frequency(v: float) -> void: color_noise_frequency = v; _dirty = true
func _set_edge_fade_distance(v: float) -> void: edge_fade_distance = v; _dirty = true
func _set_wetness_variation(v: float) -> void: wetness_variation = v; _dirty = true
func _set_color_noise_seed(v: int) -> void: color_noise_seed = v; _dirty = true

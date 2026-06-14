@tool
class_name BreakableFloor
extends Node3D
## Ein brechender Boden über einem vordefinierten Loch.
## Liegt als intakter Deckel mit Kollision über dem Loch. Betritt der Player
## ihn, zittert er kurz (Vorwarnung), dann zerbricht er prozedural in fallende
## Brocken und gibt das darunterliegende Loch frei → Player fällt durch.
##
## Aufbau im Editor:
##   - Als Kind (oder neben) das CavePiece mit dem passenden Loch platzieren.
##   - Polygon des Deckels über `cover_polygon` ODER Marker3D-Kinder definieren
##     (deckungsgleich mit dem CaveHole-Loch darunter).
##   - top_y so setzen, dass der Deckel exakt auf Bodenhöhe liegt.

signal broke   ## emittiert im Moment des Zerbrechens

@export var floor_id: StringName  ## für GameManager-Persistenz

@export_group("Form")
## Deckel-Polygon (lokale XZ). Leer lassen → Marker3D-Kinder nutzen.
@export var cover_polygon: PackedVector2Array = PackedVector2Array():
	set(v): cover_polygon = v; _dirty = true
@export var top_y: float = 0.0:
	set(v): top_y = v; _dirty = true
@export var thickness: float = 0.1:
	set(v): thickness = v; _dirty = true

@export_group("Fracturing")
## Anzahl der Bruchstücke (Voronoi-Zellen).
@export_range(3, 40) var fragment_count: int = 14:
	set(v): fragment_count = v; _dirty = true
@export var fracture_seed: int = 7:
	set(v): fracture_seed = v; _dirty = true

@export_group("Material")
@export var top_material: Material = null:
	set(v): top_material = v; _dirty = true
@export var side_material: Material = null:
	set(v): side_material = v; _dirty = true

@export_group("Trigger")
@export var collision_layer: int = 1
@export var collision_mask: int = 1
## Zittern vor dem Brechen als Vorwarnung.
@export var warn_duration: float = 0.3
@export var warn_shake_strength: float = 0.04

@export_group("Break Physics")
@export var fragment_collision_layer: int = 0
@export var fragment_collision_mask: int = 0
@export var fall_impulse: float = 0.5          ## etwas stärker für sichtbares Driften
@export var tumble_strength: float = 0.5       ## wie wild die Scheiben trudeln
@export var fragment_lifetime: float = 4.0
@export var dissolve_duration: float = 1.2

@export_group("Cracks")
@export var enable_cracks: bool = true
@export var crack_texture: Texture2D = null    ## deine Riss-Textur (PNG)
@export var crack_uses_alpha: bool = false     ## true wenn PNG echten Alpha hat
@export var crack_darkness: float = 0.85
const CRACK_SHADER_PATH := "res://interior/cave_system/shaders/floor_cracks.gdshader"

var _crack_material: ShaderMaterial = null

var _cover_body: StaticBody3D = null        ## intakter Deckel (Kollision)
var _cover_mesh: MeshInstance3D = null
var _trigger_area: Area3D = null
var _fragments: Array[RigidBody3D] = []
var _fragments_root: Node3D = null
var _state: int = 0   ## 0 = intakt, 1 = warnt, 2 = gebrochen
var _warn_timer: float = 0.0
var _cover_origin: Vector3 = Vector3.ZERO
var _dirty: bool = true



func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild_editor_preview()
		return

	# Runtime: bereits gebrochen? → gar nicht erst aufbauen
	if floor_id != &"" and GameManager.get_flag("floor_broken_" + str(floor_id)):
		return

	_build_intact_cover()
	_build_fragments()
	_build_trigger()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		if _dirty:
			_dirty = false
			_rebuild_editor_preview()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _state == 1:
		_warn_timer -= delta
		# Zittern um den Ursprung
		if is_instance_valid(_cover_mesh):
			var offset := Vector3(
				randf_range(-warn_shake_strength, warn_shake_strength),
				0.0,
				randf_range(-warn_shake_strength, warn_shake_strength)
			)
			_cover_mesh.position = _cover_origin + offset
		if _warn_timer <= 0.0:
			_do_break()


# ─── Polygon ───

func _get_cover_polygon() -> PackedVector2Array:
	if cover_polygon.size() >= 3:
		return cover_polygon
	# sonst aus Marker3D-Kindern
	var result := PackedVector2Array()
	for child in get_children():
		if child is Marker3D:
			result.append(Vector2(child.position.x, child.position.z))
	return result


# ─── Intakter Deckel ───

func _emit_break_dust() -> void:
	var poly := _get_cover_polygon()
	if poly.size() < 3:
		return

	var min_p := poly[0]
	var max_p := poly[0]
	for p in poly:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var span: float = maxf(max_p.x - min_p.x, max_p.y - min_p.y) * 1.4
	var center := _polygon_center_3d()

	var shader := load("res://scripts/shader/cave/resonance_dust_volume.gdshader") as Shader
	if shader == null:
		return

	var root := Node3D.new()
	root.name = "BreakDust"
	add_child(root)
	root.global_position = center

	var materials: Array[ShaderMaterial] = []
	for i in range(4):
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(span, span * 0.6)
		quad.mesh = mesh
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("opacity", 0.9)
		mat.set_shader_parameter("noise_offset", Vector2(randf() * 10.0, randf() * 10.0))
		quad.material_override = mat
		materials.append(mat)
		quad.position = Vector3(
			randf_range(-span, span) * 0.15,
			randf_range(0.0, span * 0.2),
			randf_range(-span, span) * 0.15
		)
		root.add_child(quad)

	var tween := create_tween()
	tween.set_parallel(true)
	for mat in materials:
		tween.tween_method(
			func(v): mat.set_shader_parameter("progress", v),
			0.0, 1.0, 2.0
		)
	tween.tween_property(root, "global_position", center + Vector3(0, 0.5, 0), 2.0)
	tween.chain().tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
	)

func _build_intact_cover() -> void:
	var poly := _get_cover_polygon()
	if poly.size() < 3:
		push_warning("BreakableFloor '%s': Polygon < 3 Punkte" % floor_id)
		return

	_cover_body = StaticBody3D.new()
	_cover_body.collision_layer = collision_layer
	_cover_body.collision_mask = collision_mask
	_cover_body.add_to_group("unsafe_floor") 
	add_child(_cover_body)

	_cover_mesh = MeshInstance3D.new()
	_cover_mesh.mesh = _build_slab_mesh(poly, top_y, thickness)

	if enable_cracks:
		_crack_material = _make_crack_material()
		_cover_mesh.material_override = _crack_material
	elif top_material:
		_cover_mesh.material_override = top_material

	_cover_body.add_child(_cover_mesh)
	_cover_origin = _cover_mesh.position

	# Trimesh-Kollision aus dem Deckel
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_mesh_faces(_cover_mesh.mesh))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_cover_body.add_child(cs)

func _make_crack_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var shader := load(CRACK_SHADER_PATH) as Shader
	if shader == null:
		push_warning("BreakableFloor: Riss-Shader fehlt unter %s" % CRACK_SHADER_PATH)
		return mat
	mat.shader = shader
	mat.set_shader_parameter("crack_progress", 0.0)
	mat.set_shader_parameter("base_crack_progress", 0.35)
	mat.set_shader_parameter("crack_darkness", crack_darkness)
	mat.set_shader_parameter("crack_uses_alpha", crack_uses_alpha)
	if crack_texture:
		mat.set_shader_parameter("crack_texture", crack_texture)

	# Polygon-Schwerpunkt im normalisierten UV2-Raum → Risse sitzen visuell mittig
	var center := _crack_center_uv()
	mat.set_shader_parameter("crack_center", center)

	if top_material is StandardMaterial3D:
		var sm := top_material as StandardMaterial3D
		mat.set_shader_parameter("base_color", sm.albedo_color)
		if sm.albedo_texture:
			mat.set_shader_parameter("base_texture", sm.albedo_texture)
	return mat


func _crack_center_uv() -> Vector2:
	# Schwerpunkt des Polygons, normalisiert auf die Bounding-Box (UV2-Raum)
	var poly := _get_cover_polygon()
	if poly.size() < 3:
		return Vector2(0.5, 0.5)
	var min_p := poly[0]
	var max_p := poly[0]
	for p in poly:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var span := max_p - min_p
	span.x = maxf(span.x, 0.0001)
	span.y = maxf(span.y, 0.0001)
	var c := _poly_center(poly)  # hast du schon als Helfer
	return Vector2((c.x - min_p.x) / span.x, (c.y - min_p.y) / span.y)

# ─── Fragmente (prozedural, eingefroren) ───

func _build_fragments() -> void:
	var poly := _get_cover_polygon()
	if poly.size() < 3:
		return

	_fragments_root = Node3D.new()
	_fragments_root.name = "Fragments"
	add_child(_fragments_root)
	_fragments_root.visible = false

	var cells := _voronoi_fracture(poly, fragment_count, fracture_seed)
	for cell in cells:
		if cell.size() < 3:
			continue
		var body := RigidBody3D.new()
		body.collision_layer = 0      # ← kollidiert mit nichts
		body.collision_mask = 0       # ← reagiert auf nichts
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
		body.continuous_cd = false

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = _build_slab_mesh(cell, top_y, thickness)
		if top_material:
			mesh_inst.material_override = top_material
		body.add_child(mesh_inst)

		# Keine CollisionShape mehr — Fragmente sind reine Optik
		_fragments_root.add_child(body)
		_fragments.append(body)


# ─── Trigger ───

func _build_trigger() -> void:
	var poly := _get_cover_polygon()
	if poly.size() < 3:
		return
	_trigger_area = Area3D.new()
	_trigger_area.collision_layer = 0
	_trigger_area.collision_mask = collision_mask  # Player-Layer
	add_child(_trigger_area)

	# Flacher Trigger knapp über dem Deckel
	var col := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for p in poly:
		pts.append(Vector3(p.x, top_y + 0.02, p.y))
		pts.append(Vector3(p.x, top_y + 0.4, p.y))  # etwas Höhe für sichere Erkennung
	shape.points = pts
	col.shape = shape
	_trigger_area.add_child(col)
	_trigger_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _state != 0:
		return
	if not body.is_in_group("player"):
		return
	if body.has_method("lock_safe_position"):
		body.lock_safe_position()
	_start_warning()


func _start_warning() -> void:
	_state = 1
	_warn_timer = warn_duration
	GameEffects.shake(0.1, warn_duration)

	# Risse über die Warndauer von der Mitte nach außen wachsen lassen
	if _crack_material:
		var tween := create_tween()
		tween.tween_method(
			func(v): _crack_material.set_shader_parameter("crack_progress", v),
			0.0, 1.0, warn_duration
		)


func _do_break() -> void:
	if _state == 2:
		return
	_state = 2

	# Deckel + Kollision entfernen → Loch ist frei, Player fällt
	if is_instance_valid(_cover_body):
		_cover_body.queue_free()
		_cover_body = null

	# Fragmente aktivieren und fallen lassen
	_fragments_root.visible = true
	var center := _polygon_center_3d()
	for body in _fragments:
		body.visible = true
		body.freeze = false

		# Auseinanderdriften: jede Scheibe etwas in eine andere Richtung
		var dir := (body.global_position - center)
		dir.y = 0.0
		if dir.length() < 0.001:
			dir = Vector3(randf() - 0.5, 0, randf() - 0.5)
		dir = dir.normalized()

		# leichter Auswärts- + Abwärtsimpuls, pro Scheibe variiert
		var outward := dir * fall_impulse * randf_range(0.5, 1.5)
		var downward := Vector3.DOWN * randf_range(0.1, 0.4)
		body.apply_central_impulse((outward + downward) * body.mass)

		# KRÄFTIGES Trudeln — das verkauft das Brechen
		body.angular_velocity = Vector3(
			randf_range(-PI, PI),
			randf_range(-PI, PI),
			randf_range(-PI, PI)
		) * tumble_strength

	GameEffects.shake(0.3, 0.25)
	_emit_break_dust()

	if floor_id != &"":
		GameManager.set_flag("floor_broken_" + str(floor_id), true)

	broke.emit()
	_schedule_despawn()


func _schedule_despawn() -> void:
	await get_tree().create_timer(fragment_lifetime).timeout
	for body in _fragments:
		if is_instance_valid(body):
			body.queue_free()
	_fragments.clear()
	if is_instance_valid(_fragments_root):
		_fragments_root.queue_free()


# ─── Mesh-Bau ───

func _build_slab_mesh(poly: PackedVector2Array, y: float, depth: float) -> ArrayMesh:
	# Dünnes extrudiertes Polygon: obere Cap + Seiten + untere Cap.
	var mesh := ArrayMesh.new()
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return mesh

	# ── Top Cap ──
	# ── Top Cap ──
	var tv := PackedVector3Array()
	var tn := PackedVector3Array()
	var tuv := PackedVector2Array()
	var tuv2 := PackedVector2Array()   # NEU: normalisierte UVs für Risse

	# Bounding-Box des Polygons für 0-1 Normalisierung
	var min_p := poly[0]
	var max_p := poly[0]
	for p in poly:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var span := max_p - min_p
	span.x = maxf(span.x, 0.0001)
	span.y = maxf(span.y, 0.0001)

	for p in poly:
		tv.append(Vector3(p.x, y, p.y))
		tn.append(Vector3.UP)
		tuv.append(Vector2(p.x, p.y) * 0.25)
		# normalisiert 0-1 über den Deckel
		tuv2.append(Vector2((p.x - min_p.x) / span.x, (p.y - min_p.y) / span.y))
	var top_arr := []
	top_arr.resize(Mesh.ARRAY_MAX)
	top_arr[Mesh.ARRAY_VERTEX] = tv
	top_arr[Mesh.ARRAY_NORMAL] = tn
	top_arr[Mesh.ARRAY_TEX_UV] = tuv
	top_arr[Mesh.ARRAY_TEX_UV2] = tuv2   # NEU
	top_arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, top_arr)
	if top_material:
		mesh.surface_set_material(0, top_material)

	# ── Seiten + Bottom in einer zweiten Surface ──
	var sv := PackedVector3Array()
	var sn := PackedVector3Array()
	var suv := PackedVector2Array()
	var si := PackedInt32Array()
	var pc := poly.size()
	var center := _poly_center(poly)
	for i in range(pc):
		var a := poly[i]
		var b := poly[(i + 1) % pc]
		var mid := (a + b) * 0.5
		var outward := (mid - center).normalized()
		var normal := Vector3(outward.x, 0, outward.y)
		var tl := Vector3(a.x, y, a.y)
		var tr := Vector3(b.x, y, b.y)
		var bl := Vector3(a.x, y - depth, a.y)
		var br := Vector3(b.x, y - depth, b.y)
		var base := sv.size()
		sv.append(tl); sv.append(tr); sv.append(bl); sv.append(br)
		for _k in range(4):
			sn.append(normal)
		suv.append(Vector2(0, 0)); suv.append(Vector2(1, 0))
		suv.append(Vector2(0, 1)); suv.append(Vector2(1, 1))
		si.append(base + 0); si.append(base + 2); si.append(base + 1)
		si.append(base + 1); si.append(base + 2); si.append(base + 3)

	# Bottom Cap (nach unten)
	var bottom_base := sv.size()
	for p in poly:
		sv.append(Vector3(p.x, y - depth, p.y))
		sn.append(Vector3.DOWN)
		suv.append(Vector2(p.x, p.y) * 0.25)
	# umgekehrte Winding für nach unten zeigende Fläche
	for t in range(0, idx.size(), 3):
		si.append(bottom_base + idx[t])
		si.append(bottom_base + idx[t + 2])
		si.append(bottom_base + idx[t + 1])

	var side_arr := []
	side_arr.resize(Mesh.ARRAY_MAX)
	side_arr[Mesh.ARRAY_VERTEX] = sv
	side_arr[Mesh.ARRAY_NORMAL] = sn
	side_arr[Mesh.ARRAY_TEX_UV] = suv
	side_arr[Mesh.ARRAY_INDEX] = si
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, side_arr)
	if side_material:
		mesh.surface_set_material(1, side_material)

	return mesh


# ─── Voronoi-Fracturing ───

func _voronoi_fracture(poly: PackedVector2Array, count: int, seed_val: int) -> Array:
	# Zerlegt das Polygon in `count` Zellen: pro zufälligem Zentrum wird das
	# Polygon mit den Mittelsenkrechten zu allen anderen Zentren geclippt.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Bounding-Box für Sample-Punkte
	var min_p := poly[0]
	var max_p := poly[0]
	for p in poly:
		min_p = min_p.min(p)
		max_p = max_p.max(p)

	# Zellzentren innerhalb des Polygons sampeln
	var sites := PackedVector2Array()
	var attempts := 0
	while sites.size() < count and attempts < count * 30:
		attempts += 1
		var candidate := Vector2(
			rng.randf_range(min_p.x, max_p.x),
			rng.randf_range(min_p.y, max_p.y)
		)
		if Geometry2D.is_point_in_polygon(candidate, poly):
			sites.append(candidate)

	var cells := []
	for i in range(sites.size()):
		var cell := poly
		for j in range(sites.size()):
			if i == j:
				continue
			cell = _clip_halfplane(cell, sites[i], sites[j])
			if cell.size() < 3:
				break
		if cell.size() >= 3:
			cells.append(cell)
	return cells


func _clip_halfplane(poly: PackedVector2Array, site: Vector2, other: Vector2) -> PackedVector2Array:
	# Behält die Polygon-Seite, die näher an `site` als an `other` liegt
	# (Sutherland-Hodgman gegen die Mittelsenkrechte).
	if poly.size() < 3:
		return poly
	var mid := (site + other) * 0.5
	var n := (other - site)  # Normale zeigt von site weg
	var result := PackedVector2Array()
	var pc := poly.size()
	for i in range(pc):
		var cur := poly[i]
		var nxt := poly[(i + 1) % pc]
		var cur_side := n.dot(cur - mid)
		var nxt_side := n.dot(nxt - mid)
		# "innen" = näher an site = negative Seite
		if cur_side <= 0.0:
			result.append(cur)
		if (cur_side <= 0.0) != (nxt_side <= 0.0):
			# Kante schneidet die Mittelsenkrechte → Schnittpunkt
			var t := cur_side / (cur_side - nxt_side)
			result.append(cur.lerp(nxt, t))
	return result


# ─── Helfer ───

func _poly_center(poly: PackedVector2Array) -> Vector2:
	var r := Vector2.ZERO
	for p in poly:
		r += p
	return r / float(poly.size())


func _polygon_center_3d() -> Vector3:
	var c := _poly_center(_get_cover_polygon())
	return to_global(Vector3(c.x, top_y, c.y))


func _mesh_faces(mesh: ArrayMesh) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for s in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var indices = arr[Mesh.ARRAY_INDEX]
		if indices and indices.size() >= 3:
			for i in range(0, indices.size(), 3):
				faces.append(verts[indices[i]])
				faces.append(verts[indices[i + 1]])
				faces.append(verts[indices[i + 2]])
	return faces


# ─── Editor-Vorschau ───

func _rebuild_editor_preview() -> void:
	for c in get_children():
		if c.name == "EditorPreview":
			c.queue_free()
	var poly := _get_cover_polygon()
	if poly.size() < 3:
		return
	var preview := MeshInstance3D.new()
	preview.name = "EditorPreview"
	preview.mesh = _build_slab_mesh(poly, top_y, thickness)
	if top_material:
		preview.material_override = top_material
	add_child(preview)

@tool
extends Node3D
class_name GrassSystem
## Verstreut Billboard-Pflanzen (Gras, Blumen, ...) innerhalb eines durch
## shape_points definierten Polygons.
##
## ARCHITEKTUR (v2):
##   - Punkte werden in ein Chunk-Gitter (chunk_size) einsortiert.
##   - Pro (Chunk x Profil) entsteht EIN MultiMeshInstance3D mit eng
##     anliegender custom_aabb → Godots Frustum-Culling greift automatisch.
##   - visibility_range_end pro Chunk → hartes Distanz-Culling ohne eigene Logik.
##   - Generierung läuft (außer im Editor) auf einem WorkerThread.
##
## Die alte öffentliche API (shape_points, density, wind_*, ...) bleibt erhalten.
## Neu: profiles[] — wenn leer, wird automatisch ein Gras-Profil aus den
## Legacy-Feldern (grass_texture, grass_scale, ...) gebaut → abwärtskompatibel.

# ============================================================
#  PROFILE (neu) — mehrere Pflanzentypen
# ============================================================
@export var profiles: Array[ScatterProfile] = []:
	set(v):
		profiles = v
		if Engine.is_editor_hint():
			_mark_dirty()

# ============================================================
#  LEGACY-FELDER — werden in ein implizites Gras-Profil übersetzt,
#  falls profiles[] leer ist. So bricht keine bestehende Szene.
# ============================================================
@export_group("Legacy Grass (used if profiles[] empty)")
@export var grass_texture: Texture2D:
	set(v):
		if grass_texture == v: return
		grass_texture = v
		if Engine.is_editor_hint(): _mark_dirty()
@export var grass_scale := Vector2(0.02, 0.2)
@export var scale_variation := 0.5
@export var color_variation := 1.0

@export var density: float = 50.0:
	set(v):
		if density == v: return
		density = v
		if Engine.is_editor_hint(): _mark_dirty()

# ============================================================
#  CHUNKING (neu)
# ============================================================
@export_group("Chunking")
## Kantenlänge eines Chunks in Meter. Klein = besseres Culling, mehr Draw-Calls.
## Für eine Miniaturwelt mit naher Kamera sind 6–10 m ideal.
@export var chunk_size: float = 8.0:
	set(v):
		if chunk_size == v: return
		chunk_size = max(v, 1.0)
		if Engine.is_editor_hint(): _mark_dirty()
## Distanz (Meter), ab der ein Chunk komplett verschwindet (visibility_range_end).
## Sollte zur Kamera-Sichtweite passen. 0 = deaktiviert.
@export var chunk_visible_distance: float = 28.0:
	set(v):
		chunk_visible_distance = max(v, 0.0)
		_apply_visibility_to_existing()
## Breite des Fade-Übergangs am Sichtbarkeits-Rand (Meter).
@export var chunk_fade_margin: float = 8.0:
	set(v):
		chunk_fade_margin = max(v, 0.0)
		_apply_visibility_to_existing()

@export_group("Distance Thinning")
## Ab dieser Distanz (Meter) werden Instanzen pro Chunk ausgedünnt.
@export var thin_start_distance: float = 20.0
## Ab dieser Distanz ist nur noch thin_min_ratio der Instanzen vorhanden.
@export var thin_end_distance: float = 45.0
## Minimaler Anteil der Instanzen bei/jenseits thin_end_distance.
@export_range(0.0, 1.0) var thin_min_ratio: float = 1.0
## Player/Kamera-Referenz für die Thinning-Distanz. Leer = PlayerManager autoload.
@export var thinning_reference_path: NodePath

# ============================================================
#  SHAPE
# ============================================================
@export_group("Shape")
@export var shape_points: PackedVector2Array = PackedVector2Array([
	Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)
]):
	set(v):
		if shape_points == v: return
		shape_points = v
		if Engine.is_editor_hint():
			_update_debug_visuals()
			_mark_dirty()

# ============================================================
#  WIND
# ============================================================
@export_group("Wind")
@export var wind_strength := 0.3:
	set(v):
		wind_strength = v
		_set_param_all("wind_strength", v)
@export var wind_speed := 1.5:
	set(v):
		wind_speed = v
		_set_param_all("wind_speed", v)
## Größe der Windwellen – kleiner = größere Böen.
@export var wind_scale := 0.1:
	set(v):
		wind_scale = v
		_set_param_all("wind_scale", v)
## Hauptwindrichtung (X, Z).
@export var wind_direction := Vector2(1.0, 0.3):
	set(v):
		wind_direction = v
		_set_param_all("wind_direction", v)

# ============================================================
#  LOD (Shader-seitiges Fade — ergänzt das Chunk-Culling)
# ============================================================
@export_group("Shader LOD")
@export var lod_fade_start := 30.0:
	set(v):
		lod_fade_start = v
		_set_param_all("lod_fade_start", v)
@export var lod_fade_end := 50.0:
	set(v):
		lod_fade_end = v
		_set_param_all("lod_fade_end", v)

@export_group("Sorting")
@export var depth_bias_strength := 0.02:
	set(v):
		depth_bias_strength = v
		_set_param_all("depth_bias_strength", v)

# ============================================================
#  EDGE FALLOFF
# ============================================================
@export_group("Edge Falloff")
## Abstand vom Polygonrand, ab dem die Höhe reduziert wird (Meter).
@export var edge_falloff_distance := 2.0:
	set(v):
		if edge_falloff_distance == v: return
		edge_falloff_distance = v
		if Engine.is_editor_hint(): _mark_dirty()
## Easing-Kurve des Falloffs (1 = linear, <1 = schnell, >1 = langsam).
@export var edge_falloff_curve := 1.5:
	set(v):
		if edge_falloff_curve == v: return
		edge_falloff_curve = v
		if Engine.is_editor_hint(): _mark_dirty()

# ============================================================
#  ASYNC
# ============================================================
@export_group("Async Loading")
## Distanz zur Kamera, unter der sofort (synchron) geladen wird.
@export var async_load_distance := 40.0
## Generierung immer synchron erzwingen.
@export var force_sync := false

# ============================================================
#  DEBUG
# ============================================================
@export_group("Debug")
@export var show_shape_outline := true:
	set(v):
		show_shape_outline = v
		_update_debug_visuals()
@export var debug_chunk_bounds := false:
	set(v):
		debug_chunk_bounds = v
		if Engine.is_editor_hint(): _update_debug_visuals()
@export var regenerate := false:
	set(v):
		if v:
			call_deferred("_generate")

# ============================================================
#  INTERNAL STATE
# ============================================================
const SHADER_PATH := "res://assets/base_tiles/grass/billboard/billboard_shader.gdshader"

var _chunk_root: Node3D                       # Container für alle Chunk-Instanzen
var _materials: Array[ShaderMaterial] = []    # Ein Material pro Profil
var _debug_mesh: MeshInstance3D
var _dirty := false
var _task_id: int = -1
var _generation_id: int = 0
var _shared_quad: QuadMesh                    # Ein Mesh für alle MultiMeshes


func _ready() -> void:
	_shared_quad = _create_quad_mesh()
	_rebuild_materials()

	if Engine.is_editor_hint() or force_sync:
		_generate()
	else:
		var cam := get_viewport().get_camera_3d() if get_viewport() else null
		var dist := INF
		if cam:
			dist = global_position.distance_to(cam.global_position)
		if dist <= async_load_distance:
			_generate()
		else:
			_generate_async()

	if Engine.is_editor_hint():
		_update_debug_visuals()


func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


# ============================================================
#  PROFILE-AUFLÖSUNG (Legacy → Profil)
# ============================================================

## Liefert die effektive Profilliste. Ist profiles[] leer, wird ein Gras-Profil
## aus den Legacy-Feldern synthetisiert.
func _resolve_profiles() -> Array[ScatterProfile]:
	var valid: Array[ScatterProfile] = []
	for p in profiles:
		if p != null and p.texture != null:
			valid.append(p)
	if not valid.is_empty():
		return valid

	# Legacy-Fallback
	if grass_texture == null:
		return valid  # leer → nichts zu tun
	var legacy := ScatterProfile.new()
	legacy.profile_name = "LegacyGrass"
	legacy.texture = grass_texture
	legacy.density_weight = 1.0
	legacy.scale = grass_scale
	legacy.scale_variation = scale_variation
	legacy.color_variation = color_variation
	legacy.edge_min_height = 0.2
	valid.append(legacy)
	return valid


func _rebuild_materials() -> void:
	_materials.clear()
	var resolved := _resolve_profiles()
	var shader := load(SHADER_PATH) as Shader
	for p in resolved:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("grass_texture", p.texture)
		mat.set_shader_parameter("wind_strength", wind_strength * p.wind_multiplier)
		mat.set_shader_parameter("wind_speed", wind_speed)
		mat.set_shader_parameter("wind_scale", wind_scale)
		mat.set_shader_parameter("wind_direction", wind_direction)
		mat.set_shader_parameter("lod_fade_start", lod_fade_start)
		mat.set_shader_parameter("lod_fade_end", lod_fade_end)
		mat.set_shader_parameter("depth_bias_strength", depth_bias_strength)
		_materials.append(mat)


func _set_param_all(param: String, value) -> void:
	# Wind-Strength ist profil-abhängig (multiplier) → Sonderbehandlung.
	if param == "wind_strength":
		var resolved := _resolve_profiles()
		for i in _materials.size():
			var mult := 1.0
			if i < resolved.size():
				mult = resolved[i].wind_multiplier
			_materials[i].set_shader_parameter("wind_strength", value * mult)
		return
	for mat in _materials:
		mat.set_shader_parameter(param, value)


# ============================================================
#  DIRTY / FLUSH (Editor)
# ============================================================

func _mark_dirty() -> void:
	if not _dirty:
		_dirty = true
		call_deferred("_flush_dirty")

func _flush_dirty() -> void:
	if _dirty:
		_dirty = false
		_rebuild_materials()
		_generate()


# ============================================================
#  GENERIERUNG
# ============================================================

func _generate() -> void:
	_generation_id += 1
	_clear_chunks()

	var params := _snapshot_params()
	var result := _compute(params)
	_apply(result)


func _generate_async() -> void:
	_generation_id += 1
	_clear_chunks()

	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1

	var params := _snapshot_params()
	var gen_id := _generation_id
	_task_id = WorkerThreadPool.add_task(
		func() -> void:
			var result := _compute(params)
			call_deferred("_on_async_complete", result, gen_id)
	)


func _on_async_complete(result: Dictionary, gen_id: int) -> void:
	_task_id = -1
	if gen_id != _generation_id:
		return
	if not is_inside_tree():
		return
	_clear_chunks()
	_apply(result)


func _clear_chunks() -> void:
	if _chunk_root and is_instance_valid(_chunk_root):
		_chunk_root.queue_free()
	_chunk_root = null


# ============================================================
#  SNAPSHOT (thread-sicher)
# ============================================================

func _snapshot_params() -> Dictionary:
	var prof_snaps: Array = []
	for p in _resolve_profiles():
		prof_snaps.append(p.snapshot())

	# Thinning-Referenzposition EINMAL hier (Main-Thread) abgreifen.
	var ref_pos := _get_reference_position()

	return {
		"shape_points": shape_points.duplicate(),
		"density": density,
		"global_position": global_position,
		"chunk_size": chunk_size,
		"edge_falloff_distance": edge_falloff_distance,
		"edge_falloff_curve": edge_falloff_curve,
		"profiles": prof_snaps,
		"thin_start": thin_start_distance,
		"thin_end": thin_end_distance,
		"thin_min_ratio": thin_min_ratio,
		"reference_pos": ref_pos,
	}


func _get_reference_position() -> Vector3:
	# Explizite Referenz?
	if thinning_reference_path != NodePath():
		var n := get_node_or_null(thinning_reference_path) as Node3D
		if n:
			return n.global_position
	# PlayerManager autoload?
	if not Engine.is_editor_hint() and has_node("/root/PlayerManager"):
		var pm := get_node("/root/PlayerManager")
		if pm.has_method("ensure_player"):
			var pl := pm.ensure_player() as Node3D
			if pl and pl.is_inside_tree():
				return pl.global_position
	# Editor / Fallback: aktive Kamera.
	var vp := get_viewport()
	if vp:
		var cam := vp.get_camera_3d()
		if cam:
			return cam.global_position
	return global_position


# ============================================================
#  PURE COMPUTE (thread-sicher, kein SceneTree-Zugriff)
#  Ergebnis: { "chunks": [ {key, aabb_center, aabb_size, profile_data:[...]}, ... ] }
#  profile_data[i] = { "transforms":PackedFloat32Array, "colors":..., "custom":..., "count":int }
# ============================================================

func _compute(p: Dictionary) -> Dictionary:
	var sp: PackedVector2Array = p["shape_points"]
	if sp.size() < 3:
		return {}
	var prof_snaps: Array = p["profiles"]
	if prof_snaps.is_empty():
		return {}

	var gp: Vector3 = p["global_position"]
	var dens: float = p["density"]
	var csize: float = p["chunk_size"]
	var efd: float = p["edge_falloff_distance"]
	var efc: float = p["edge_falloff_curve"]
	var ref_pos: Vector3 = p["reference_pos"]
	var thin_start: float = p["thin_start"]
	var thin_end: float = p["thin_end"]
	var thin_min: float = p["thin_min_ratio"]

	# --- Profil-Gewichte → kumulierte Verteilung für gewichtete Auswahl ---
	var weights: Array[float] = []
	var weight_sum := 0.0
	for ps in prof_snaps:
		var w: float = ps["density_weight"]
		weights.append(w)
		weight_sum += w
	if weight_sum <= 0.0:
		return {}

	# --- Punkte im Polygon erzeugen ---
	var positions := _points_in_polygon(sp, dens, gp)
	if positions.is_empty():
		return {}

	# --- Distance-Field für Edge-Falloff ---
	var use_edge := efd > 0.0
	var df_grid := PackedFloat32Array()
	var df_min := Vector2.ZERO
	var df_cell := 0.5
	var df_rx := 0
	var df_ry := 0
	if use_edge:
		var df := _bake_distance_field(sp, efd, df_cell)
		df_grid = df["grid"]
		df_min = df["min"]
		df_rx = df["res_x"]
		df_ry = df["res_y"]

	# --- Noise-Sampler pro Profil (thread-lokal) ---
	var noises: Array = []
	for ps in prof_snaps:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = ps["noise_frequency"]
		n.seed = 42
		noises.append(n)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(gp)

	# --- Buckets: chunk_key -> profile_index -> Array[Dictionary] ---
	# Wir sammeln rohe Instanzdaten, bauen die PackedArrays am Ende.
	var buckets: Dictionary = {}

	for local_pos in positions:
		# --- Profil gewichtet wählen ---
		var r := rng.randf() * weight_sum
		var prof_idx := 0
		var acc := 0.0
		for i in weights.size():
			acc += weights[i]
			if r <= acc:
				prof_idx = i
				break
		var ps: Dictionary = prof_snaps[prof_idx]

		var world_x := local_pos.x + gp.x
		var world_z := local_pos.z + gp.z
		var world_pos := Vector3(world_x, gp.y + local_pos.y, world_z)

		# --- Distanz-Thinning: ferne Instanzen wahrscheinlichkeitsbasiert verwerfen ---
		if thin_end > thin_start:
			var d := ref_pos.distance_to(world_pos)
			if d > thin_start:
				var t := clampf((d - thin_start) / (thin_end - thin_start), 0.0, 1.0)
				var bias: float = ps["lod_thin_bias"]
				# keep_ratio sinkt von 1.0 auf thin_min; bias>1 dünnt stärker aus
				var keep := lerpf(1.0, thin_min, pow(t, 1.0 / bias))
				if rng.randf() > keep:
					continue

		# --- Chunk-Key (Welt-Raum gerastert) ---
		var cx := int(floor(world_x / csize))
		var cz := int(floor(world_z / csize))
		var ckey := Vector2i(cx, cz)

		if not buckets.has(ckey):
			buckets[ckey] = {}
		if not buckets[ckey].has(prof_idx):
			buckets[ckey][prof_idx] = []

		# --- Per-Instanz Werte ---
		var sv: float = ps["scale_variation"]
		var cv: float = ps["color_variation"]
		var gs: Vector2 = ps["scale"]
		var emh: float = ps["edge_min_height"]
		var ncs: float = ps["noise_color_strength"]
		var ncc: Color = ps["noise_color_cool"]
		var ncw: Color = ps["noise_color_warm"]

		var scale_factor := 1.0 + rng.randf_range(-sv, sv)
		var color_offset := rng.randf_range(-cv, cv)
		var random_phase := rng.randf() * TAU

		var edge_factor := 1.0
		if use_edge:
			var ed := _sample_df(Vector2(local_pos.x, local_pos.z),
				df_grid, df_min, df_cell, df_rx, df_ry)
			if ed < efd:
				var et := pow(ed / efd, efc)
				edge_factor = emh + (1.0 - emh) * et

		var noise: FastNoiseLite = noises[prof_idx]
		var nval := (noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
		var blend := nval * ncs
		var nr := ncc.r + (ncw.r - ncc.r) * blend
		var ng := ncc.g + (ncw.g - ncc.g) * blend
		var nb := ncc.b + (ncw.b - ncc.b) * blend
		var col := Color(
			(1.0 + color_offset) * nr,
			(1.0 + color_offset * 0.5) * ng,
			nb, 1.0)

		var sx := gs.x * scale_factor
		var sy := gs.y * scale_factor * edge_factor

		buckets[ckey][prof_idx].append({
			"pos": local_pos, "sx": sx, "sy": sy,
			"col": col, "phase": random_phase,
		})

	# --- Buckets → kompakte Chunk-Datensätze mit PackedArrays ---
	var num_profiles := prof_snaps.size()
	var chunks: Array = []

	for ckey in buckets.keys():
		var profile_map: Dictionary = buckets[ckey]

		# AABB über ALLE Profile dieses Chunks (lokal zum GrassSystem-Node).
		var aabb_min := Vector3(INF, INF, INF)
		var aabb_max := Vector3(-INF, -INF, -INF)

		var profile_data: Array = []
		profile_data.resize(num_profiles)

		for prof_idx in range(num_profiles):
			if not profile_map.has(prof_idx):
				profile_data[prof_idx] = null
				continue
			var insts: Array = profile_map[prof_idx]
			var cnt := insts.size()
			if cnt == 0:
				profile_data[prof_idx] = null
				continue

			var transforms := PackedFloat32Array()
			transforms.resize(cnt * 12)        # 3x4 row-major
			var colors := PackedFloat32Array()
			colors.resize(cnt * 4)
			var customs := PackedFloat32Array()
			customs.resize(cnt * 4)

			for k in cnt:
				var inst: Dictionary = insts[k]
				var lp: Vector3 = inst["pos"]
				var sx: float = inst["sx"]
				var sy: float = inst["sy"]

				# Transform3D row-major: basis (3x3) + origin
				var o := k * 12
				transforms[o + 0] = sx
				transforms[o + 1] = 0.0
				transforms[o + 2] = 0.0
				transforms[o + 3] = lp.x
				transforms[o + 4] = 0.0
				transforms[o + 5] = sy
				transforms[o + 6] = 0.0
				transforms[o + 7] = lp.y
				transforms[o + 8] = 0.0
				transforms[o + 9] = 0.0
				transforms[o + 10] = 1.0
				transforms[o + 11] = lp.z

				var co := k * 4
				var c: Color = inst["col"]
				colors[co + 0] = c.r
				colors[co + 1] = c.g
				colors[co + 2] = c.b
				colors[co + 3] = c.a

				customs[co + 0] = inst["phase"]
				customs[co + 1] = 0.0
				customs[co + 2] = 0.0
				customs[co + 3] = 0.0

				# AABB erweitern (Quad wächst von Fuß nach oben um sy,
				# seitlich um ~sx; großzügig für Billboard-Rotation).
				var half := maxf(sx, sy) * 0.75
				var pmin := Vector3(lp.x - half, lp.y, lp.z - half)
				var pmax := Vector3(lp.x + half, lp.y + sy, lp.z + half)
				aabb_min = aabb_min.min(pmin)
				aabb_max = aabb_max.max(pmax)

			profile_data[prof_idx] = {
				"transforms": transforms,
				"colors": colors,
				"customs": customs,
				"count": cnt,
			}

		if aabb_min.x == INF:
			continue  # Chunk leer (alles ausgedünnt)

		# Chunk-Center in WELT-Koordinaten (für visibility_range / Position).
		chunks.append({
			"key": ckey,
			"aabb_center": (aabb_min + aabb_max) * 0.5,
			"aabb_min": aabb_min,
			"aabb_max": aabb_max,
			"profile_data": profile_data,
		})

	return { "chunks": chunks }


# ============================================================
#  APPLY (Main-Thread — baut Nodes)
# ============================================================

func _apply(result: Dictionary) -> void:
	if result.is_empty() or not result.has("chunks"):
		return
	var chunks: Array = result["chunks"]
	if chunks.is_empty():
		return

	_chunk_root = Node3D.new()
	_chunk_root.name = "GrassChunks"
	add_child(_chunk_root)

	var total := 0
	for chunk in chunks:
		var aabb_min: Vector3 = chunk["aabb_min"]
		var aabb_max: Vector3 = chunk["aabb_max"]
		var aabb_size := aabb_max - aabb_min
		var profile_data: Array = chunk["profile_data"]

		for prof_idx in range(profile_data.size()):
			var pd = profile_data[prof_idx]
			if pd == null:
				continue
			var cnt: int = pd["count"]
			if cnt == 0:
				continue

			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _shared_quad
			mm.instance_count = cnt
			mm.buffer = _interleave_buffer(pd["transforms"], pd["colors"], pd["customs"], cnt)

			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if prof_idx < _materials.size():
				mmi.material_override = _materials[prof_idx]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			# Eng anliegende AABB → korrektes Frustum-Culling.
			mmi.custom_aabb = AABB(aabb_min, aabb_size)

			# Hartes Distanz-Culling.
			if chunk_visible_distance > 0.0:
				mmi.visibility_range_end = chunk_visible_distance
				mmi.visibility_range_end_margin = chunk_fade_margin
				mmi.visibility_range_fade_mode = \
					GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

			_chunk_root.add_child(mmi)
			total += cnt

	if not Engine.is_editor_hint():
		print("GrassSystem '%s': %d instances in %d chunks" % [name, total, chunks.size()])


## Baut den interleaved MultiMesh-Buffer:
## [12 transform floats][4 color floats][4 custom floats] pro Instanz.
func _interleave_buffer(
	transforms: PackedFloat32Array, colors: PackedFloat32Array,
	customs: PackedFloat32Array, cnt: int
) -> PackedFloat32Array:
	var stride := 12 + 4 + 4   # = 20 (TRANSFORM_3D + colors + custom)
	var buf := PackedFloat32Array()
	buf.resize(cnt * stride)
	for i in cnt:
		var b := i * stride
		var t := i * 12
		var c := i * 4
		for j in 12:
			buf[b + j] = transforms[t + j]
		for j in 4:
			buf[b + 12 + j] = colors[c + j]
		for j in 4:
			buf[b + 16 + j] = customs[c + j]
	return buf


func _apply_visibility_to_existing() -> void:
	if not _chunk_root or not is_instance_valid(_chunk_root):
		return
	for child in _chunk_root.get_children():
		if child is MultiMeshInstance3D:
			if chunk_visible_distance > 0.0:
				child.visibility_range_end = chunk_visible_distance
				child.visibility_range_end_margin = chunk_fade_margin
				child.visibility_range_fade_mode = \
					GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			else:
				child.visibility_range_end = 0.0


# ============================================================
#  STATIC GEO-HELPERS (thread-sicher)
# ============================================================

func _points_in_polygon(sp: PackedVector2Array, dens: float, gp: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if sp.size() < 3:
		return points
	var min_p := sp[0]
	var max_p := sp[0]
	for p in sp:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var area := _polygon_area(sp)
	var point_count := int(area * dens)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(gp) + hash(sp.size())
	var attempts := 0
	var max_attempts := point_count * 10
	while points.size() < point_count and attempts < max_attempts:
		attempts += 1
		var tp := Vector2(rng.randf_range(min_p.x, max_p.x), rng.randf_range(min_p.y, max_p.y))
		if Geometry2D.is_point_in_polygon(tp, sp):
			points.append(Vector3(tp.x, 0, tp.y))
	return points


func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	var n := polygon.size()
	for i in n:
		var j := (i + 1) % n
		area += polygon[i].x * polygon[j].y
		area -= polygon[j].x * polygon[i].y
	return abs(area) / 2.0


func _bake_distance_field(sp: PackedVector2Array, efd: float, cell_size: float) -> Dictionary:
	var min_p := sp[0]
	var max_p := sp[0]
	for p in sp:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var pad := efd + 1.0
	min_p -= Vector2(pad, pad)
	max_p += Vector2(pad, pad)
	var res_x := int(ceil((max_p.x - min_p.x) / cell_size)) + 1
	var res_y := int(ceil((max_p.y - min_p.y) / cell_size)) + 1
	var ec := sp.size()
	var ax := PackedFloat32Array(); ax.resize(ec)
	var ay := PackedFloat32Array(); ay.resize(ec)
	var abx := PackedFloat32Array(); abx.resize(ec)
	var aby := PackedFloat32Array(); aby.resize(ec)
	var ablsq := PackedFloat32Array(); ablsq.resize(ec)
	for i in ec:
		var j := (i + 1) % ec
		var sa := sp[i]; var sb := sp[j]
		ax[i] = sa.x; ay[i] = sa.y
		var dx := sb.x - sa.x; var dy := sb.y - sa.y
		abx[i] = dx; aby[i] = dy
		ablsq[i] = dx * dx + dy * dy
	var grid := PackedFloat32Array()
	grid.resize(res_x * res_y)
	for gy in res_y:
		var py := min_p.y + gy * cell_size
		for gx in res_x:
			var px := min_p.x + gx * cell_size
			var md := 1e18
			for e in ec:
				var apx := px - ax[e]; var apy := py - ay[e]
				var lsq := ablsq[e]
				var t: float
				if lsq < 0.0001: t = 0.0
				else: t = clampf((apx * abx[e] + apy * aby[e]) / lsq, 0.0, 1.0)
				var cx := ax[e] + abx[e] * t - px
				var cy := ay[e] + aby[e] * t - py
				var d := cx * cx + cy * cy
				if d < md: md = d
			grid[gy * res_x + gx] = sqrt(md)
	return { "grid": grid, "min": min_p, "res_x": res_x, "res_y": res_y }


func _sample_df(point: Vector2, grid: PackedFloat32Array, grid_min: Vector2,
		cell_size: float, res_x: int, res_y: int) -> float:
	var fx := (point.x - grid_min.x) / cell_size
	var fy := (point.y - grid_min.y) / cell_size
	var ix := int(fx); var iy := int(fy)
	if ix < 0: ix = 0; fx = 0.0
	elif ix >= res_x - 1: ix = res_x - 2; fx = float(ix) + 1.0
	if iy < 0: iy = 0; fy = 0.0
	elif iy >= res_y - 1: iy = res_y - 2; fy = float(iy) + 1.0
	var tx := fx - float(ix); var ty := fy - float(iy)
	var idx := iy * res_x + ix
	var d00 := grid[idx]; var d10 := grid[idx + 1]
	var d01 := grid[idx + res_x]; var d11 := grid[idx + res_x + 1]
	return d00 * (1.0 - tx) * (1.0 - ty) + d10 * tx * (1.0 - ty) \
		+ d01 * (1.0 - tx) * ty + d11 * tx * ty


func _create_quad_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	mesh.center_offset = Vector3(0, 0.5, 0)
	return mesh


# ============================================================
#  DEBUG VISUALS (Editor)
# ============================================================

func _update_debug_visuals() -> void:
	if not Engine.is_editor_hint():
		return
	if _debug_mesh and is_instance_valid(_debug_mesh):
		_debug_mesh.queue_free()
	_debug_mesh = null
	if not show_shape_outline or shape_points.size() < 3:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in shape_points:
		im.surface_add_vertex(Vector3(p.x, 0.1, p.y))
	im.surface_add_vertex(Vector3(shape_points[0].x, 0.1, shape_points[0].y))
	im.surface_end()
	_debug_mesh = MeshInstance3D.new()
	_debug_mesh.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.YELLOW_GREEN
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_mesh.material_override = mat
	add_child(_debug_mesh)

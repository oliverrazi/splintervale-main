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
@export var chunk_visible_distance: float = 45.0:
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
@export_range(0.0, 1.0) var thin_min_ratio: float = 0.25
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
#  BAKING (vorberechnete Daten statt Laufzeit-Generierung)
# ============================================================
@export_group("Baking")
## Eindeutiger Bake-Dateiname (ohne Pfad/Endung). Leer = Node-Name wird genutzt.
## Wichtig bei mehreren Flächen mit gleichem Node-Namen → manuell eindeutig setzen.
@export var bake_id: String = ""
## Im Editor drücken: erzeugt die Daten einmal und speichert sie als .res.
@export var bake_now: bool = false:
	set(v):
		if v and Engine.is_editor_hint():
			call_deferred("_do_bake")
## Wenn true und eine Bake-Datei existiert, wird sie beim Start geladen
## statt generiert. Bei false immer Laufzeit-Generierung (zum Bearbeiten).
@export var use_baked: bool = true
## Löscht die Bake-Datei dieser Fläche (zurück zu Laufzeit-Generierung).
@export var clear_bake: bool = false:
	set(v):
		if v and Engine.is_editor_hint():
			call_deferred("_clear_bake_file")

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

## --- Ladezeit-Diagnose (statisch, über ALLE Flächen aggregiert) ---
## Aktiviert detaillierte Zeitmessung beim Generieren. Zum Profilen einschalten.
@export var measure_load_time: bool = true
static var _stat_sync_ms: float = 0.0         # summierte synchrone Generierzeit (blockiert Start)
static var _stat_async_ms: float = 0.0        # summierte asynchrone Generierzeit (Hintergrund)
static var _stat_sync_count: int = 0
static var _stat_async_count: int = 0
static var _stat_total_instances: int = 0


func _ready() -> void:
	add_to_group("grass_system")
	_shared_quad = _create_quad_mesh()
	_rebuild_materials()

	# Bake-Pfad zuerst: existiert eine gebackene Datei und soll sie genutzt werden?
	if use_baked and not Engine.is_editor_hint() and _has_bake_file():
		_load_baked()
	elif Engine.is_editor_hint() or force_sync:
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
	elif measure_load_time:
		# Einmalige Gesamt-Zusammenfassung kurz nach dem Laden (idempotent).
		_schedule_load_summary()


## Plant eine einmalige Gesamt-Ausgabe der Ladezeit-Statistik.
## Mehrfachaufruf von verschiedenen Flächen ist unkritisch (statischer Guard).
static var _summary_scheduled: bool = false
func _schedule_load_summary() -> void:
	if _summary_scheduled:
		return
	_summary_scheduled = true
	# 3 Sekunden warten, damit auch asynchrone Flächen fertig sind.
	get_tree().create_timer(3.0).timeout.connect(_print_load_summary)

func _print_phases(result) -> void:
	if not (result is Dictionary and result.has("_phases")):
		return
	var ph: Dictionary = result["_phases"]
	print("           └─ Punkte: %.1f ms | DistField: %.1f ms | Schleife: %.1f ms | Bau: %.1f ms | (%d Punkte gewürfelt)" % [
		ph["points"] / 1000.0, ph["df"] / 1000.0,
		ph["loop"] / 1000.0, ph["build"] / 1000.0,
		ph["point_count"]])


func _print_load_summary() -> void:
	print("\n========== GRASS LOAD SUMMARY ==========")
	print("Synchron (blockiert Start): %.1f ms über %d Flächen" % [_stat_sync_ms, _stat_sync_count])
	print("Asynchron (Hintergrund):    %.1f ms über %d Flächen" % [_stat_async_ms, _stat_async_count])
	print("Instanzen gesamt:           %d" % _stat_total_instances)
	if _stat_sync_count > 0:
		print("Durchschnitt pro Sync-Fläche: %.1f ms" % (_stat_sync_ms / _stat_sync_count))
	print("WICHTIG: Nur die SYNCHRONE Summe verzögert den sichtbaren Start.")
	print("=========================================\n")


func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


## Von ScatterZone aufgerufen, wenn sich eine Zone ändert (Editor).
## Debounced, damit nicht bei jedem Slider-Pixel neu gebaut wird.
func regenerate_from_zone_change() -> void:
	if not Engine.is_editor_hint():
		return
	_mark_dirty()


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
		# Profil-spezifische Tönung (Tint, Höhen-Tinting, AO) setzen.
		if p.has_method("apply_shader_params"):
			p.apply_shader_params(mat)
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

	var t_start := Time.get_ticks_usec() if measure_load_time else 0
	var params := _snapshot_params()
	var result := _compute(params)
	_apply(result)

	if measure_load_time:
		var ms := (Time.get_ticks_usec() - t_start) / 1000.0
		var inst := int(result.get("total_instances", 0)) if result is Dictionary else 0
		_stat_sync_ms += ms
		_stat_sync_count += 1
		_stat_total_instances += inst
		print("[GrassLoad] SYNC  '%s': %.1f ms (%d Instanzen) | Summe sync: %.1f ms über %d Flächen" % [
			name, ms, inst, _stat_sync_ms, _stat_sync_count])
		_print_phases(result)


func _generate_async() -> void:
	_generation_id += 1
	_clear_chunks()

	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1

	var params := _snapshot_params()
	var gen_id := _generation_id
	var measure := measure_load_time
	_task_id = WorkerThreadPool.add_task(
		func() -> void:
			var t0 := Time.get_ticks_usec() if measure else 0
			var result := _compute(params)
			if measure and result is Dictionary:
				result["_gen_us"] = Time.get_ticks_usec() - t0
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

	if measure_load_time and result.has("_gen_us"):
		var ms := float(result["_gen_us"]) / 1000.0
		var inst := int(result.get("total_instances", 0))
		_stat_async_ms += ms
		_stat_async_count += 1
		_stat_total_instances += inst
		print("[GrassLoad] ASYNC '%s': %.1f ms (%d Instanzen, Hintergrund) | Summe async: %.1f ms über %d Flächen" % [
			name, ms, inst, _stat_async_ms, _stat_async_count])
		_print_phases(result)


func _clear_chunks() -> void:
	if _chunk_root and is_instance_valid(_chunk_root):
		_chunk_root.queue_free()
	_chunk_root = null


# ============================================================
#  BAKING
# ============================================================

const BAKE_DIR := "res://data/grass_bakes/"

func _bake_path() -> String:
	var id : Variant= bake_id if bake_id != "" else name
	return BAKE_DIR.path_join(str(id) + ".res")

func _has_bake_file() -> bool:
	return ResourceLoader.exists(_bake_path())

## Erzeugt die Daten einmal und speichert sie als GrassBakeData-Resource.
func _do_bake() -> void:
	if not Engine.is_editor_hint():
		return
	# Sicherstellen, dass der Zielordner existiert.
	var abs_dir := ProjectSettings.globalize_path(BAKE_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)

	var t0 := Time.get_ticks_usec()
	var params := _snapshot_params()
	var result := _compute(params)
	if result.is_empty() or not result.has("chunks"):
		push_warning("GrassSystem '%s': Bake fehlgeschlagen (keine Daten)." % name)
		bake_now = false
		return

	var bake := GrassBakeData.new()
	bake.profile_count = _resolve_profiles().size()

	var chunks: Array = result["chunks"]
	for chunk in chunks:
		var aabb_min: Vector3 = chunk["aabb_min"]
		var aabb_max: Vector3 = chunk["aabb_max"]
		var aabb := AABB(aabb_min, aabb_max - aabb_min)
		var profile_data: Array = chunk["profile_data"]
		for prof_idx in range(profile_data.size()):
			var pd = profile_data[prof_idx]
			if pd == null:
				continue
			var cnt: int = pd["count"]
			if cnt == 0:
				continue
			# Fertigen interleaved Buffer bauen und speichern.
			var buf := _interleave_buffer(pd["transforms"], pd["colors"], pd["customs"], cnt)
			bake.add_entry(prof_idx, cnt, aabb, buf)

	var path := _bake_path()
	var err := ResourceSaver.save(bake, path)
	bake_now = false
	if err != OK:
		push_error("GrassSystem '%s': Bake-Speichern fehlgeschlagen (%d)." % [name, err])
		return
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("GrassSystem '%s': GEBACKT → %s (%d Einträge, %d Instanzen, %.0f ms)" % [
		name, path, bake.entry_count(), bake.total_instances, ms])

## Lädt die gebackene Resource und baut die Chunk-Nodes direkt (kein _compute).
func _load_baked() -> void:
	var t0 := Time.get_ticks_usec() if measure_load_time else 0
	var bake := ResourceLoader.load(_bake_path()) as GrassBakeData
	if bake == null:
		push_warning("GrassSystem '%s': Bake-Datei defekt, generiere stattdessen." % name)
		_generate()
		return

	_clear_chunks()
	_chunk_root = Node3D.new()
	_chunk_root.name = "GrassChunks"
	add_child(_chunk_root)

	var n := bake.entry_count()
	for i in n:
		var cnt: int = bake.counts[i]
		if cnt == 0:
			continue
		var prof_idx: int = bake.profile_indices[i]

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _shared_quad
		mm.instance_count = cnt
		mm.buffer = bake.buffers[i]   # fertiger interleaved Buffer

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if prof_idx < _materials.size():
			mmi.material_override = _materials[prof_idx]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(bake.aabb_positions[i], bake.aabb_sizes[i])
		if chunk_visible_distance > 0.0:
			mmi.visibility_range_end = chunk_visible_distance
			mmi.visibility_range_end_margin = chunk_fade_margin
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_chunk_root.add_child(mmi)

	if measure_load_time:
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("[GrassLoad] BAKED '%s': %.1f ms (%d Instanzen geladen)" % [
			name, ms, bake.total_instances])

func _clear_bake_file() -> void:
	clear_bake = false
	var path := _bake_path()
	if not ResourceLoader.exists(path):
		print("GrassSystem '%s': keine Bake-Datei zum Löschen." % name)
		return
	var abs := ProjectSettings.globalize_path(path)
	var err := DirAccess.remove_absolute(abs)
	if err == OK:
		print("GrassSystem '%s': Bake-Datei gelöscht." % name)
	else:
		push_warning("GrassSystem '%s': Löschen fehlgeschlagen (%d)." % [name, err])


# ============================================================
#  SNAPSHOT (thread-sicher)
# ============================================================

func _snapshot_params() -> Dictionary:
	var prof_snaps: Array = []
	for p in _resolve_profiles():
		prof_snaps.append(p.snapshot())

	# Thinning-Referenzposition EINMAL hier (Main-Thread) abgreifen.
	var ref_pos := _get_reference_position()

	# Überschneidende ScatterZones einsammeln (Main-Thread, thread-sicher als Snapshot).
	var zone_snaps := _collect_zone_snapshots()

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
		"zones": zone_snaps,
		"_profile": measure_load_time,
	}


## Sammelt alle ScatterZone-Kinder DIESER Grasfläche.
## Kind-Modell: die Zone gehört eindeutig zu ihrer Elternfläche, deren Profile
## sie per profile_index nutzt. Koordinaten liegen damit im selben Raum.
func _collect_zone_snapshots() -> Array:
	var result: Array = []
	for child in get_children():
		if child.has_method("snapshot") and child.is_in_group("scatter_zone"):
			result.append(child.snapshot())
	return result


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
	var zones: Array = p.get("zones", [])

	# --- Phasen-Profiling ---
	var _prof : Variant= p.get("_profile", false)
	var _t0 := Time.get_ticks_usec()
	var _ph_points := 0
	var _ph_df := 0
	var _ph_loop := 0
	var _ph_build := 0

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
	if _prof:
		_ph_points = Time.get_ticks_usec() - _t0
		_t0 = Time.get_ticks_usec()

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
	if _prof:
		_ph_df = Time.get_ticks_usec() - _t0
		_t0 = Time.get_ticks_usec()

	# --- Noise-Sampler pro Profil + vorberechnetes Gitter ---
	# OPT: Statt get_noise_2d pro Halm (teuer bei 100k+ Halmen) sampeln wir das
	# Noise auf einem groben Gitter (noise_cell Meter) und interpolieren bilinear.
	# Die Farbvariation ändert sich räumlich langsam → Gitter erfasst sie voll.
	var noise_cell := 2.0
	# Bounding-Box des Polygons in WELT-Koordinaten (für das Gitter).
	var nb_min := Vector2(INF, INF)
	var nb_max := Vector2(-INF, -INF)
	for spv in sp:
		nb_min = nb_min.min(spv)
		nb_max = nb_max.max(spv)
	# Padding, damit auch Zonen-Punkte knapp außerhalb noch im Gitter liegen.
	nb_min -= Vector2(noise_cell, noise_cell)
	nb_max += Vector2(noise_cell, noise_cell)
	var n_origin := Vector2(gp.x + nb_min.x, gp.z + nb_min.y)  # Welt-Ursprung des Gitters
	var n_res_x := int(ceil((nb_max.x - nb_min.x) / noise_cell)) + 2
	var n_res_y := int(ceil((nb_max.y - nb_min.y) / noise_cell)) + 2

	# Pro Profil ein gebaktes Noise-Gitter (PackedFloat32Array, Werte 0..1).
	var noise_grids: Array = []
	for ps in prof_snaps:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = ps["noise_frequency"]
		n.seed = 42
		var grid := PackedFloat32Array()
		grid.resize(n_res_x * n_res_y)
		for gy in n_res_y:
			var wy := n_origin.y + gy * noise_cell
			for gx in n_res_x:
				var wx := n_origin.x + gx * noise_cell
				grid[gy * n_res_x + gx] = (n.get_noise_2d(wx, wy) + 1.0) * 0.5
		noise_grids.append(grid)

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

		# --- ScatterZones: EXCLUDE schneidet Löcher, REPLACE verdrängt Gras ---
		# Zonen rechnen im ELTERN-lokalen Raum → local_pos verwenden.
		var zone_edge_factor := 1.0
		var skip_point := false
		for zsnap in zones:
			var zmode: int = zsnap["mode"]
			# Höhenfenster: außerhalb → Zone ignoriert diesen Halm.
			if not ScatterZone.in_height_window(zsnap, local_pos):
				continue
			var sd := ScatterZone.signed_distance(zsnap, local_pos)
			if zmode == ScatterZone.Mode.EXCLUDE:
				if sd <= 0.0:
					# voll innerhalb → kein Gras
					skip_point = true
					break
				elif sd < efd:
					# weicher Rand: Halm wird zum Loch hin kürzer
					var zt := pow(sd / efd, efc)
					zone_edge_factor = minf(zone_edge_factor, zt)
			elif zmode == ScatterZone.Mode.REPLACE:
				if sd <= 0.0:
					# Innerhalb der REPLACE-Zone: Gras wird verdrängt — aber im
					# Übergangsring (blend_width) kommt es nach außen zurück.
					var bw: float = zsnap["blend_width"]
					if bw > 0.0 and sd > -bw:
						# Im Ring von -bw bis 0: am Rand viel Gras, zum Zentrum keins.
						# grass_return: 0 am inneren Ende, 1 am Rand.
						var grass_return := 1.0 - clampf((-sd) / bw, 0.0, 1.0)
						# grass_return hoch nahe Rand → Gras eher behalten.
						if rng.randf() > grass_return:
							skip_point = true
							break
					else:
						# tief im Zentrum → kein Gras
						skip_point = true
						break
		if skip_point:
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
		# Zonen-Rand-Verkürzung einrechnen (der stärkere Effekt gewinnt).
		edge_factor = minf(edge_factor, zone_edge_factor)

		var ngrid: PackedFloat32Array = noise_grids[prof_idx]
		var nval := _sample_noise_grid(world_x, world_z, ngrid,
			n_origin, noise_cell, n_res_x, n_res_y)
		var blend := nval * ncs
		var nr := ncc.r + (ncw.r - ncc.r) * blend
		var ng := ncc.g + (ncw.g - ncc.g) * blend
		var nb := ncc.b + (ncw.b - ncc.b) * blend
		# color_offset wirkt GLEICHMÄSSIG auf alle Kanäle = reine Helligkeits-
		# variation, kein Farbstich (wichtig für weiße Blumen).
		var bright := 1.0 + color_offset
		var col := Color(bright * nr, bright * ng, bright * nb, 1.0)

		var sx := gs.x * scale_factor
		var sy := gs.y * scale_factor * edge_factor

		buckets[ckey][prof_idx].append({
			"pos": local_pos, "sx": sx, "sy": sy,
			"col": col, "phase": random_phase,
		})

	# === ScatterZones: REPLACE/ADD streuen ihr Profil innerhalb der Zone ===
	# Beide Modi erzeugen hier Instanzen des per profile_index referenzierten
	# Profils. (EXCLUDE erzeugt nichts; das wurde oben durch Verwerfen erledigt.)
	for zsnap in zones:
		var zmode: int = zsnap["mode"]
		if zmode == ScatterZone.Mode.EXCLUDE:
			continue
		var zpidx: int = zsnap["profile_index"]
		if zpidx < 0 or zpidx >= prof_snaps.size():
			continue  # ungültiger Index → überspringen

		var zps: Dictionary = prof_snaps[zpidx]
		# _points_in_zone liefert jetzt ELTERN-LOKALE Punkte (gleicher Raum wie sp).
		var zone_points := _points_in_zone(zsnap, dens, zsnap["density_multiplier"])

		var z_ngrid: PackedFloat32Array = noise_grids[zpidx]
		for zlocal in zone_points:
			# Höhenfenster respektieren (lokal)
			if not ScatterZone.in_height_window(zsnap, zlocal):
				continue
			var lx := zlocal.x
			var lz := zlocal.z
			# Muss innerhalb der eigentlichen Grasfläche liegen (Polygon, lokal)
			if not Geometry2D.is_point_in_polygon(Vector2(lx, lz), sp):
				continue

			# weicher Zonenrand: zur Zonengrenze hin kürzer
			var sd := ScatterZone.signed_distance(zsnap, zlocal)

			# Blumen-Ausdünnung im Übergangsring: zum Rand (sd≈0) hin weniger
			# Blumen, komplementär zum zurückkehrenden Gras → beide überlappen.
			var bw: float = zsnap["blend_width"]
			if bw > 0.0 and sd > -bw:
				# flower_keep: 1 tief im Zentrum (sd≈-bw), 0 am Rand (sd≈0).
				var flower_keep := clampf((-sd) / bw, 0.0, 1.0)
				if rng.randf() > flower_keep:
					continue

			var z_edge := 1.0
			if sd > -efd and efd > 0.0:
				var dd := clampf((-sd) / efd, 0.0, 1.0)
				z_edge = pow(dd, efc)
				z_edge = maxf(z_edge, float(zps["edge_min_height"]))

			var z_scale := 1.0 + rng.randf_range(-zps["scale_variation"], zps["scale_variation"])
			var z_coff := rng.randf_range(-zps["color_variation"], zps["color_variation"])
			var z_phase := rng.randf() * TAU

			# Welt-X/Z für Noise (konsistent mit dem Hauptgras)
			var zwx := lx + gp.x
			var zwz := lz + gp.z
			var znval := _sample_noise_grid(zwx, zwz, z_ngrid,
				n_origin, noise_cell, n_res_x, n_res_y)
			var zblend: float = znval * zps["noise_color_strength"]
			var zcc: Color = zps["noise_color_cool"]
			var zcw: Color = zps["noise_color_warm"]
			# Gleichmäßige Helligkeitsvariation auf allen Kanälen (kein Farbstich).
			var zbright := 1.0 + z_coff
			var zcol := Color(
				zbright * (zcc.r + (zcw.r - zcc.r) * zblend),
				zbright * (zcc.g + (zcw.g - zcc.g) * zblend),
				zbright * (zcc.b + (zcw.b - zcc.b) * zblend), 1.0)

			var zgs: Vector2 = zps["scale"]
			var zsx := zgs.x * z_scale
			var zsy := zgs.y * z_scale * z_edge

			# Chunk-Key im Weltraum (wie das Hauptgras)
			var zcx := int(floor(zwx / csize))
			var zcz := int(floor(zwz / csize))
			var zckey := Vector2i(zcx, zcz)
			if not buckets.has(zckey):
				buckets[zckey] = {}
			if not buckets[zckey].has(zpidx):
				buckets[zckey][zpidx] = []
			buckets[zckey][zpidx].append({
				"pos": Vector3(lx, zlocal.y, lz),
				"sx": zsx, "sy": zsy, "col": zcol, "phase": z_phase,
			})

	# --- Buckets → kompakte Chunk-Datensätze mit PackedArrays ---
	if _prof:
		_ph_loop = Time.get_ticks_usec() - _t0
		_t0 = Time.get_ticks_usec()

	var num_profiles := prof_snaps.size()
	var chunks: Array = []
	var total_instances := 0

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
			total_instances += cnt

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

	if _prof:
		_ph_build = Time.get_ticks_usec() - _t0

	var res := { "chunks": chunks, "total_instances": total_instances }
	if _prof:
		res["_phases"] = {
			"points": _ph_points, "df": _ph_df,
			"loop": _ph_loop, "build": _ph_build,
			"point_count": positions.size(),
		}
	return res


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

## Erzeugt Punkte (ELTERN-LOKALE Koordinaten) innerhalb der Form einer ScatterZone.
## density_base: Basisdichte der Grasfläche. mult: density_multiplier der Zone.
func _points_in_zone(zsnap: Dictionary, density_base: float, mult: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if mult <= 0.0:
		return points
	var origin: Vector3 = zsnap["local_origin"]
	var fwd_basis: Basis = zsnap["fwd_basis"]  # lokal(Zone) -> lokal(Eltern)

	var area: float
	var ext_x: float
	var ext_z: float
	if zsnap["shape"] == ScatterZone.Shape.CIRCLE:
		var rad: float = zsnap["radius"]
		area = PI * rad * rad
		ext_x = rad
		ext_z = rad
	else:
		var s: Vector2 = zsnap["size"]
		area = (s.x * 2.0) * (s.y * 2.0)
		ext_x = s.x
		ext_z = s.y

	var count := int(area * density_base * mult)
	if count <= 0:
		return points

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(origin) + int(zsnap["profile_index"])

	var attempts := 0
	var max_attempts := count * 10
	while points.size() < count and attempts < max_attempts:
		attempts += 1
		var zx := rng.randf_range(-ext_x, ext_x)
		var zz := rng.randf_range(-ext_z, ext_z)
		if zsnap["shape"] == ScatterZone.Shape.CIRCLE:
			var rad: float = zsnap["radius"]
			if zx * zx + zz * zz > rad * rad:
				continue
		# Zonenraum -> Elternraum
		var ep := origin + fwd_basis * Vector3(zx, 0.0, zz)
		points.append(ep)
	return points


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


## Bilineare Interpolation des vorberechneten Noise-Gitters (Welt-Koordinaten).
## Ersetzt teures get_noise_2d pro Halm. grid-Werte sind bereits 0..1.
func _sample_noise_grid(wx: float, wz: float, grid: PackedFloat32Array,
		origin: Vector2, cell: float, res_x: int, res_y: int) -> float:
	var fx := (wx - origin.x) / cell
	var fy := (wz - origin.y) / cell
	var ix := int(fx)
	var iy := int(fy)
	# Klemmen auf gültigen Bereich
	if ix < 0:
		ix = 0
	elif ix > res_x - 2:
		ix = res_x - 2
	if iy < 0:
		iy = 0
	elif iy > res_y - 2:
		iy = res_y - 2
	var tx := clampf(fx - float(ix), 0.0, 1.0)
	var ty := clampf(fy - float(iy), 0.0, 1.0)
	var idx := iy * res_x + ix
	var v00 := grid[idx]
	var v10 := grid[idx + 1]
	var v01 := grid[idx + res_x]
	var v11 := grid[idx + res_x + 1]
	return v00 * (1.0 - tx) * (1.0 - ty) + v10 * tx * (1.0 - ty) \
		+ v01 * (1.0 - tx) * ty + v11 * tx * ty


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

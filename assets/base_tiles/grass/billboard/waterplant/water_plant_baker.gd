@tool
class_name WaterPlantBaker
extends Node3D

## Editor-Baker (Scatter): die Marker3D-Children definieren ein POLYGON
## (Eckpunkte, Reihenfolge im Baum = Umlauf). Innerhalb der Flaeche werden
## scatter_count Pflanzen geclustert verteilt, in Chunks sortiert und als
## WaterPlantData (.tres) gespeichert.
##
## Workflow: mind. 3 Marker3D als Children setzen, die die Flaeche umranden ->
## "bake" im Inspector togglen.

@export var plant_texture: Texture2D
@export var shader: Shader


@export_group("Editor-Anzeige")
## Zeichnet das Marker-Polygon als Linien (plus optionale Fuellflaeche) im
## Editor-Viewport. Reine Editor-Hilfe, wird nie gespeichert oder mitgebakt.
@export var show_area: bool = true : set = _set_show_area
@export var area_color: Color = Color(0.35, 0.85, 1.0, 1.0)
## Halbtransparente Flaechen-Fuellung zusaetzlich zum Umriss.
@export var fill_area: bool = true
## Linien durch Geometrie hindurch zeichnen (immer sichtbar).
@export var area_always_on_top: bool = true

@export_group("Mesh")
@export var plant_height: float = 0.35
@export var plant_width: float = 0.18
@export var segments: int = 5

@export_group("Ausrichtung")
## Optionale Neigung zur Kamera (um X). 0 = komplett aufrecht (Standard).
## Nur hochdrehen, wenn du die Quads bewusst kippen willst.
@export var camera_pitch_deg: float = 0.0
## Vertikaler Versatz der ganzen Gruppe (Welt-Y), z. B. um Pflanzen aus dem
## Terrain auf die Wasseroberflaeche zu heben.
@export var y_offset: float = 0.0

@export_group("Variation")
## Hoehen-Skalierung: zufaellig zwischen min und max (Multiplikator auf plant_height).
@export var height_scale_min: float = 0.8
@export var height_scale_max: float = 1.3
## Breiten-Skalierung: zufaellig zwischen min und max (Multiplikator auf plant_width).
## Unabhaengig von der Hoehe -> schlanke und breite Pflanzen gemischt.
@export var width_scale_min: float = 0.85
@export var width_scale_max: float = 1.25
## Koppelt Breite teilweise an Hoehe (0 = voellig unabhaengig, 1 = grosse
## Pflanzen sind auch proportional breiter). Verhindert unnatuerlich
## duenne hohe oder breite niedrige Pflanzen.
@export var width_height_coupling: float = 0.4
@export var yaw_jitter_deg: float = 25.0
@export_group("Farb-Variation")
## Modus-Regler fuer die Buntheit. 0 = kein Hue-Shift (natuerlich, alle gleich-
## farbig). 1 = subtile Variation. Hoeher (2-5) = kraeftig bunt/korallenartig.
## Multipliziert den hue_jitter-Bereich -> der eigentliche Buntheits-Hebel.
@export var color_spread: float = 1.0
## Basis-Streuung des Farbtons (0..1 = Anteil Farbkreis). Wird mit color_spread
## multipliziert. Bei 0.5 und color_spread=1 schon deutliche Vielfalt.
@export var hue_jitter: float = 0.1
## Zufaellige Helligkeits-Variation (multiplikativ, +/-). Gibt Tiefe -
## manche Pflanzen heller, manche dunkler, wie natuerlicher Bewuchs.
@export var value_jitter: float = 0.15
@export var random_seed: int = 1337

@export_group("Scatter")
## Marker3D-Children definieren das POLYGON (Eckpunkte, Reihenfolge = Umlauf).
## Innerhalb dieser Flaeche werden Pflanzen verteilt. Mindestens 3 Marker.
## Ziel-Gesamtzahl der Pflanzen.
@export var scatter_count: int = 200
## Anzahl Cluster-Zentren (Bueschel/Kolonien). Weniger = grosse Kolonien,
## mehr = viele kleine Gruppen.
@export var cluster_count: int = 8
## Radius eines Bueschels in Welt-Einheiten. Wie weit Pflanzen um ihr
## Cluster-Zentrum streuen.
@export var cluster_radius: float = 1.5
## 0 = strenge Bueschel, 1 = fast gleichmaessig verstreut. Anteil der Pflanzen,
## der frei im Polygon verteilt wird statt geclustert -> franst die Kolonien aus.
@export var scatter_looseness: float = 0.25
## Weicher Mindestabstand: verhindert nur exakte Ueberlappung, erlaubt aber
## Bueschelbildung. 0 = aus. Klein halten (z.B. 0.1).
@export var min_distance: float = 0.1

@export_group("Chunking")
## Kantenlaenge eines Chunks in Welt-Einheiten (XZ-Raster). Marker werden nach
## Position in dieses Raster sortiert; jeder belegte Chunk wird eine eigene
## MultiMesh mit eigener AABB -> praezises Frustum-Culling. Kleiner = feineres
## Culling, aber mehr Draw Calls. Faustregel: etwa die sichtbare Reichweite.
@export var chunk_size: float = 8.0

@export_group("Output")
@export var output_path: String = "res://water_plants/baked_plants.tres"
@export var bake: bool = false : set = _set_bake

@export_group("Vorschau")
## Zeigt das Bake-Ergebnis live im Editor-Viewport (animiert).
@export var show_preview: bool = true : set = _set_show_preview
## Erzeugt die Vorschau neu aus den aktuellen Markern, ohne zu speichern.
@export var refresh_preview: bool = false : set = _set_refresh_preview

const PREVIEW_NAME := "_WaterPlantPreview"

const AREA_NAME := "_WaterPlantAreaViz"

var _area_viz_hash: int = 0

func _ready() -> void:
	if Engine.is_editor_hint():
		if show_preview:
			_rebuild_preview()
		# Erzwingt beim Oeffnen der Szene einen ersten Viz-Aufbau.
		_area_viz_hash = 0
		
## Laeuft nur im Editor. Erkennt Aenderungen an Marker-Positionen oder
## Viz-Einstellungen ueber einen Hash und baut die Anzeige nur dann neu.
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if not show_area:
		return
	var pts := _collect_marker_points()
	var h := hash([pts, area_color, fill_area, area_always_on_top, y_offset])
	if h != _area_viz_hash:
		_area_viz_hash = h
		_rebuild_area_viz(pts)

func _set_show_area(v: bool) -> void:
	show_area = v
	if Engine.is_editor_hint():
		if v:
			_area_viz_hash = 0  # naechster _process baut neu
		else:
			_clear_area_viz()

func _collect_marker_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for child in get_children():
		if child is Marker3D:
			pts.push_back(child.position)
	return pts

func _clear_area_viz() -> void:
	var existing := get_node_or_null(AREA_NAME)
	if existing:
		existing.free()

func _rebuild_area_viz(points: PackedVector3Array) -> void:
	_clear_area_viz()
	if points.size() < 3:
		return

	# Bake-Ebene: Durchschnitts-Y der Marker + y_offset (identisch zur
	# Berechnung in _scatter_positions -> die Anzeige zeigt exakt die Hoehe,
	# auf der die Pflanzen landen).
	var base_y := 0.0
	for p in points:
		base_y += p.y
	base_y = base_y / float(points.size()) + y_offset

	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.albedo_color = area_color
	line_mat.no_depth_test = area_always_on_top
	line_mat.render_priority = 10

	var im := ImmediateMesh.new()

	# --- Geschlossener Umriss auf Bake-Hoehe ---
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, line_mat)
	for p in points:
		im.surface_add_vertex(Vector3(p.x, base_y, p.z))
	im.surface_add_vertex(Vector3(points[0].x, base_y, points[0].z))
	im.surface_end()

	# --- Vertikale Stummel: Marker-Position -> Bake-Ebene ---
	# Macht sichtbar, welcher Marker zu welcher Ecke gehoert, auch wenn
	# Marker hoeher/tiefer liegen als die Bake-Ebene.
	im.surface_begin(Mesh.PRIMITIVE_LINES, line_mat)
	for p in points:
		im.surface_add_vertex(p)
		im.surface_add_vertex(Vector3(p.x, base_y, p.z))
	im.surface_end()

	# --- Halbtransparente Fuellflaeche (trianguliert) ---
	if fill_area:
		var poly2d := PackedVector2Array()
		for p in points:
			poly2d.push_back(Vector2(p.x, p.z))
		var tris := Geometry2D.triangulate_polygon(poly2d)
		if not tris.is_empty():
			var fill_mat: StandardMaterial3D = line_mat.duplicate()
			fill_mat.albedo_color = Color(
				area_color.r, area_color.g, area_color.b, area_color.a * 0.15)
			fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, fill_mat)
			for idx in tris:
				var v := poly2d[idx]
				im.surface_add_vertex(Vector3(v.x, base_y, v.y))
			im.surface_end()

	var mi := MeshInstance3D.new()
	mi.name = AREA_NAME
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.owner = null  # nie in die Szene speichern

func _set_bake(v: bool) -> void:
	if v and Engine.is_editor_hint():
		_do_bake()
	bake = false

func _set_show_preview(v: bool) -> void:
	show_preview = v
	if Engine.is_editor_hint():
		if v:
			_rebuild_preview()
		else:
			_clear_preview()

func _set_refresh_preview(v: bool) -> void:
	if v and Engine.is_editor_hint():
		_rebuild_preview()
	refresh_preview = false

## Baut das WaterPlantData. Die Marker3D-Children definieren ein Polygon;
## innerhalb dieser Flaeche werden Pflanzen geclustert verteilt.
func _build_data() -> WaterPlantData:
	var markers: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D:
			markers.append(child)

	if markers.size() < 3:
		push_warning("WaterPlantBaker: mindestens 3 Marker3D noetig, um eine Flaeche aufzuspannen.")
		return null

	if plant_texture == null or shader == null:
		push_error("WaterPlantBaker: plant_texture und shader muessen gesetzt sein.")
		return null

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	var mesh := WaterPlantMesh.build(plant_height, plant_width, segments)
	var pitch := deg_to_rad(camera_pitch_deg)
	var cs: float = maxf(chunk_size, 0.5)

	# --- Pflanzen-Positionen im Polygon verteilen (geclustert) ---
	var positions := _scatter_positions(markers, rng)
	if positions.is_empty():
		push_warning("WaterPlantBaker: keine Positionen gescattert (Polygon zu klein?).")
		return null

	# --- Positionen nach XZ in ein Chunk-Raster sortieren ---
	# Key: Vector2i(chunk_x, chunk_z) -> Liste der Positionen in diesem Chunk.
	var grid: Dictionary = {}
	for p in positions:
		var cx := int(floor(p.x / cs))
		var cz := int(floor(p.z / cs))
		var key := Vector2i(cx, cz)
		if not grid.has(key):
			grid[key] = []
		grid[key].append(p)

	# --- Geteiltes Material (eine globale Welle fuer alle Chunks) ---
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("albedo_tex", plant_texture)

	# --- Pro belegtem Chunk eine MultiMesh bauen ---
	var chunks: Array[WaterPlantChunk] = []
	var total_aabb := AABB()
	var total_first := true
	var total_count := 0
	var chunk_script := load("res://assets/base_tiles/grass/billboard/waterplant/water_plant_chunk.gd")

	for key in grid.keys():
		var chunk_positions: Array = grid[key]

		# KRITISCH: use_colors / use_custom_data VOR instance_count.
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = chunk_positions.size()

		var chunk_aabb := AABB()
		var chunk_first := true

		for i in range(chunk_positions.size()):
			var pos: Vector3 = chunk_positions[i]
			var xform := _make_instance_transform(pos, rng, pitch)
			mm.set_instance_transform(i, xform)

			var phase := rng.randf()
			var amp := rng.randf()
			var freq := rng.randf()

			# Hue-Shift pro Pflanze: skaliert mit color_spread (Modus-Regler).
			# Wird in custom_data.a abgelegt und im Shader ECHT rotiert.
			# 0.5 = kein Shift (neutral), Abweichung = Rotation auf dem Farbkreis.
			var hue_shift := rng.randf_range(-hue_jitter, hue_jitter) * color_spread
			mm.set_instance_custom_data(i, Color(phase, amp, freq, 0.5 + hue_shift))

			# COLOR traegt die per-Instance Helligkeit (manche Pflanzen heller/
			# dunkler -> Tiefe). Saettigung wird global ueber den Shader geregelt.
			var val_mul_i := 1.0 + rng.randf_range(-value_jitter, value_jitter)
			mm.set_instance_color(i, Color(val_mul_i, val_mul_i, val_mul_i, 1.0))

			var inst_aabb := xform * mesh.get_aabb()
			if chunk_first:
				chunk_aabb = inst_aabb
				chunk_first = false
			else:
				chunk_aabb = chunk_aabb.merge(inst_aabb)

		var chunk := WaterPlantChunk.new()
		chunk.set_script(chunk_script)
		chunk.multimesh = mm
		chunk.aabb = chunk_aabb
		chunks.append(chunk)

		total_count += chunk_positions.size()
		if total_first:
			total_aabb = chunk_aabb
			total_first = false
		else:
			total_aabb = total_aabb.merge(chunk_aabb)

	var data := WaterPlantData.new()
	data.set_script(load("res://assets/base_tiles/grass/billboard/waterplant/water_plant_data.gd"))
	data.chunks = chunks
	data.material = mat
	data.bounds_aabb = total_aabb
	data.instance_count = total_count
	return data

## Verteilt scatter_count Positionen im Polygon, geclustert um zufaellige
## Zentren, mit Anteil freier Streuung (looseness).
## WICHTIG: arbeitet in WELT-Koordinaten (global_position der Marker).
## Die gebackenen Daten sind dadurch unabhaengig davon, wo Baker- und
## Runtime-Node im Baum/Raum stehen.
func _scatter_positions(markers: Array[Marker3D], rng: RandomNumberGenerator) -> Array:
	# Polygon als 2D-XZ-Punkte in WELT-Koordinaten.
	var poly := PackedVector2Array()
	var y_sum := 0.0
	for m in markers:
		var gp := m.global_position
		poly.push_back(Vector2(gp.x, gp.z))
		y_sum += gp.y
	var base_y := y_sum / float(markers.size()) + y_offset

	# Bounding-Box des Polygons fuer Kandidaten-Wuerfeln.
	var min_x := poly[0].x
	var max_x := poly[0].x
	var min_z := poly[0].y
	var max_z := poly[0].y
	for v in poly:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
		min_z = minf(min_z, v.y)
		max_z = maxf(max_z, v.y)

	# Cluster-Zentren im Polygon platzieren.
	var centers := PackedVector2Array()
	var safety := 0
	while centers.size() < cluster_count and safety < cluster_count * 200:
		safety += 1
		var c := Vector2(rng.randf_range(min_x, max_x), rng.randf_range(min_z, max_z))
		if Geometry2D.is_point_in_polygon(c, poly):
			centers.push_back(c)
	if centers.is_empty():
		return []  # Polygon degeneriert

	var result: Array = []
	var placed_2d := PackedVector2Array()
	var min_d_sq := min_distance * min_distance
	var attempts := 0
	var max_attempts := scatter_count * 30

	while result.size() < scatter_count and attempts < max_attempts:
		attempts += 1
		var pt: Vector2
		if rng.randf() < scatter_looseness:
			pt = Vector2(rng.randf_range(min_x, max_x), rng.randf_range(min_z, max_z))
		else:
			var center: Vector2 = centers[rng.randi() % centers.size()]
			var ang := rng.randf() * TAU
			var r := (rng.randf() + rng.randf()) * 0.5 * cluster_radius
			pt = center + Vector2(cos(ang), sin(ang)) * r

		if not Geometry2D.is_point_in_polygon(pt, poly):
			continue

		if min_d_sq > 0.0:
			var too_close := false
			for q in placed_2d:
				if pt.distance_squared_to(q) < min_d_sq:
					too_close = true
					break
			if too_close:
				continue

		placed_2d.push_back(pt)
		result.push_back(Vector3(pt.x, base_y, pt.y))

	if result.size() < scatter_count:
		push_warning("WaterPlantBaker: nur %d von %d Pflanzen platziert (Flaeche/min_distance?)." % [result.size(), scatter_count])

	return result

## Berechnet die Instanz-Transform fuer einen Marker (Position, Yaw-Jitter,
## Hoehen-/Breiten-Skalierung mit Kopplung, Kamera-Pitch). Ausgelagert, damit
## die Chunk-Schleife schlank bleibt.
func _make_instance_transform(pos: Vector3, rng: RandomNumberGenerator, pitch: float) -> Transform3D:
	var yaw := deg_to_rad(rng.randf_range(-yaw_jitter_deg, yaw_jitter_deg))

	var h_scale := rng.randf_range(height_scale_min, height_scale_max)
	var w_rand := rng.randf_range(width_scale_min, width_scale_max)
	var h_norm := 0.0
	if height_scale_max > height_scale_min:
		h_norm = (h_scale - height_scale_min) / (height_scale_max - height_scale_min)
	var w_scale : Variant= lerp(w_rand, w_rand * lerp(0.85, 1.15, h_norm), width_height_coupling)

	var basis := Basis(Vector3.UP, yaw)
	basis = basis * Basis(Vector3.RIGHT, pitch)
	basis = basis.scaled(Vector3(w_scale, h_scale, 1.0))
	# y_offset ist bereits in der Scatter-Hoehe (pos.y) enthalten.
	return Transform3D(basis, pos)

func _do_bake() -> void:
	var data := _build_data()
	if data == null:
		return

	var dir := output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	# Verdraengt eine evtl. im Editor gecachte alte Version dieses Pfads,
	# bevor gespeichert wird. FLAG_CHANGE_PATH allein reicht dafuer nicht
	# zuverlaessig, wenn der Pfad bereits von einer anderen Instanz belegt ist.
	data.take_over_path(output_path)

	var err := ResourceSaver.save(data, output_path,
		ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		push_error("WaterPlantBaker: Speichern fehlgeschlagen (err %d) -> %s" % [err, output_path])
		return

	print("WaterPlantBaker: %d Pflanzen in %d Chunks gebakt -> %s"
		% [data.instance_count, data.chunks.size(), output_path])

	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.update_file(output_path)

	if show_preview:
		_rebuild_preview()

# --- Editor-Vorschau ---

func _clear_preview() -> void:
	var existing := get_node_or_null(PREVIEW_NAME)
	if existing:
		existing.free()

func _rebuild_preview() -> void:
	_clear_preview()
	if not show_preview:
		return
	var data := _build_data()
	if data == null:
		return
	# Container-Node, darunter eine MultiMeshInstance3D pro Chunk.
	# Die gebackenen Transforms sind WELT-Koordinaten -> Container per
	# top_level aus der Baker-Transform ausklinken und auf Identity setzen.
	var container := Node3D.new()
	container.name = PREVIEW_NAME
	add_child(container)
	container.owner = null
	container.top_level = true
	container.global_transform = Transform3D.IDENTITY
	for chunk in data.chunks:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = chunk.multimesh
		mmi.material_override = data.material
		mmi.custom_aabb = chunk.aabb.grow(0.5)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.add_child(mmi)
		mmi.owner = null

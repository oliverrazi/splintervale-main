# fountain_baker.gd
# @tool-Generator fuer Brunnen-Wassermeshes (Griffinblade / Godot 4.5).
# Erzeugt parametrisch zwei Meshes:
#   - Parabel-Krone (Rotationskoerper, UV.v entlang echter Bogenlaenge)
#   - Ueberlaufschleier (Zylindermantel, linear)
# Bake-Everything-Ansatz: Editor-Zeit-Authoring -> fertige ArrayMesh-Knoten.
@tool
extends Node3D
class_name FountainBaker

enum Form { PARABOLA_CROWN, OVERFLOW_VEIL }

@export var form: Form = Form.PARABOLA_CROWN:
	set(v): form = v; _request_rebuild()

@export var fountain_material: Material:
	set(v): fountain_material = v; _request_rebuild()

@export_group("Gemeinsam")
## Anzahl Segmente um den Ring (u-Aufloesung).
@export_range(8, 256) var radial_segments: int = 64:
	set(v): radial_segments = v; _request_rebuild()
## Anzahl Segmente entlang des Wasserlaufs (v-Aufloesung).
@export_range(2, 128) var length_segments: int = 32:
	set(v): length_segments = v; _request_rebuild()

@export_group("Parabel-Krone")
## Radius am Duesenursprung (oben, eng).
@export var crown_inner_radius: float = 0.04:
	set(v): crown_inner_radius = v; _request_rebuild()
## Radius am Auftreffpunkt (unten, weit).
@export var crown_outer_radius: float = 0.18:
	set(v): crown_outer_radius = v; _request_rebuild()
## Scheitelhoehe der Parabel ueber dem Ursprung.
@export var crown_height: float = 0.10:
	set(v): crown_height = v; _request_rebuild()
## Vertikaler Versatz des Ursprungs (Duesenhoehe ueber Becken).
@export var crown_base_y: float = 0.12:
	set(v): crown_base_y = v; _request_rebuild()

@export_group("Ueberlaufschleier")
@export var veil_radius: float = 0.20:
	set(v): veil_radius = v; _request_rebuild()
@export var veil_height: float = 0.08:
	set(v): veil_height = v; _request_rebuild()
@export var veil_top_y: float = 0.0:
	set(v): veil_top_y = v; _request_rebuild()

var _mesh_instance: MeshInstance3D
var _rebuild_queued := false

func _ready() -> void:
	_ensure_child()
	_rebuild()

func _request_rebuild() -> void:
	if not is_inside_tree():
		return
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild")

func _ensure_child() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		return
	# Vorhandenes Kind wiederverwenden, falls Szene neu geladen wurde.
	for c in get_children():
		if c is MeshInstance3D:
			_mesh_instance = c
			return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "FountainWater"
	add_child(_mesh_instance)
	if Engine.is_editor_hint() and get_tree():
		_mesh_instance.owner = get_tree().edited_scene_root

func _rebuild() -> void:
	_rebuild_queued = false
	_ensure_child()
	var mesh: ArrayMesh
	match form:
		Form.PARABOLA_CROWN:
			mesh = _build_parabola_crown()
		Form.OVERFLOW_VEIL:
			mesh = _build_overflow_veil()
	_mesh_instance.mesh = mesh
	if fountain_material:
		_mesh_instance.material_override = fountain_material

# --- Parabel-Krone ---
# Profil: Wasser startet am inneren Radius, steigt zum Scheitel, faellt zum aeusseren Radius.
# Wir sampeln die Parabel ueber Parameter t in [0,1], berechnen (radius, y),
# und verteilen UV.v entlang der KUMULIERTEN BOGENLAENGE -> nichtlineare Geschwindigkeit.
func _build_parabola_crown() -> ArrayMesh:
	# 1) Profilpunkte + Bogenlaenge berechnen.
	var profile: Array[Vector2] = [] # (radius, y)
	for j in range(length_segments + 1):
		var t := float(j) / float(length_segments)
		var radius : Variant= lerp(crown_inner_radius, crown_outer_radius, t)
		# Parabel: steigt von base_y zum Scheitel bei t=0.4, faellt darunter.
		# y(t) = base_y + height * (1 - ((t - peak_t)/...)^2)-aehnlich, hier sauber via Wurf.
		# Aufsteigender Ast bis peak, dann fallend unter base.
		var peak_t := 0.35
		var y: float
		if t <= peak_t:
			var tt := t / peak_t
			y = crown_base_y + crown_height * (1.0 - (1.0 - tt) * (1.0 - tt))
		else:
			var tt := (t - peak_t) / (1.0 - peak_t)
			# faellt vom Scheitel unter die Basis (ins Becken).
			y = crown_base_y + crown_height * (1.0 - tt * tt) - (crown_height + crown_base_y) * tt
		profile.append(Vector2(radius, y))

	# Kumulierte Bogenlaenge fuer UV.v.
	var arc: Array[float] = [0.0]
	var total := 0.0
	for j in range(1, profile.size()):
		total += profile[j].distance_to(profile[j - 1])
		arc.append(total)
	for j in range(arc.size()):
		arc[j] = arc[j] / max(total, 0.0001)

	return _revolve(profile, arc)

# --- Ueberlaufschleier ---
# Zylindermantel: konstanter Radius, faellt linear. UV.v linear (gleichfoermige Geschwindigkeit).
func _build_overflow_veil() -> ArrayMesh:
	var profile: Array[Vector2] = []
	var arc: Array[float] = []
	for j in range(length_segments + 1):
		var t := float(j) / float(length_segments)
		var y := veil_top_y - t * veil_height
		profile.append(Vector2(veil_radius, y))
		arc.append(t) # linear
	return _revolve(profile, arc)

# Rotiert ein (radius,y)-Profil um die Y-Achse zu einem Mantel.
# u = Winkel (0..1), v = arc-Wert (0..1, Wasserlauf-Richtung).
func _revolve(profile: Array[Vector2], arc: Array[float]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings := profile.size()
	var cols := radial_segments + 1 # +1 fuer nahtlose UV-Wiederholung

	for i in range(cols):
		var u := float(i) / float(radial_segments)
		var ang := u * TAU
		var cos_a := cos(ang)
		var sin_a := sin(ang)
		for j in range(rings):
			var r := profile[j].x
			var y := profile[j].y
			var pos := Vector3(cos_a * r, y, sin_a * r)
			# Normale zeigt radial nach aussen (fuer Fresnel ausreichend).
			var nrm := Vector3(cos_a, 0.0, sin_a).normalized()
			st.set_uv(Vector2(u, arc[j]))
			st.set_normal(nrm)
			st.add_vertex(pos)

	# Indizes (zwei Dreiecke pro Quad).
	for i in range(radial_segments):
		for j in range(rings - 1):
			var a := i * rings + j
			var b := a + 1
			var c := (i + 1) * rings + j
			var d := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)

	st.generate_tangents()
	return st.commit()

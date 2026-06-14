@tool
extends Node3D
class_name ScatterZone
## Definiert einen Bereich, in dem das Streuen von Gras/Pflanzen verändert wird.
## Wird von GrassSystem beim Generieren über die Gruppe "scatter_zone" gefunden
## und auf alle überschneidenden Flächen angewendet.
##
## MODI:
##   EXCLUDE  - hier wächst nichts (mit weichem Höhen-Verlauf zum Rand)
##   REPLACE  - hier wächst NUR das Zonen-Profil (Gras wird verdrängt)
##   ADD      - hier wächst das Zonen-Profil ZUSÄTZLICH zum normalen Gras
##
## FORM: Kreis (radius) oder Rechteck (size). Der Rand ist über den Falloff
## der Grasfläche weich, wirkt also organisch und nicht eckig.

enum Mode { EXCLUDE, REPLACE, ADD }
enum Shape { CIRCLE, RECTANGLE }

@export var mode: Mode = Mode.EXCLUDE:
	set(v):
		mode = v
		update_configuration_warnings()
		_notify_dirty()

@export var shape: Shape = Shape.CIRCLE:
	set(v):
		shape = v
		_notify_dirty()

@export_group("Shape")
## Radius bei CIRCLE (Meter).
@export var radius: float = 3.0:
	set(v):
		radius = max(v, 0.0)
		_notify_dirty()
## Halbe Kantenlängen bei RECTANGLE (X, Z) (Meter).
@export var size: Vector2 = Vector2(3.0, 3.0):
	set(v):
		size = v.max(Vector2.ZERO)
		_notify_dirty()

@export_group("Height Window")
## Zone wirkt nur, wenn der Grashalm vertikal innerhalb dieses Fensters um die
## Zonen-Y-Position liegt. Verhindert auf Schrägen ungewolltes Erfassen.
## 0 = unbegrenzt (Höhe wird ignoriert).
@export var height_tolerance: float = 0.0:
	set(v):
		height_tolerance = max(v, 0.0)
		_notify_dirty()

@export_group("Profile (REPLACE / ADD)")
## Index des Profils im profiles[]-Array der GrassSystem-Fläche, das hier
## gestreut wird. Z.B. 1 = zweites Profil (erste Blume). Bei EXCLUDE ungenutzt.
## Tipp: Blumen-Profile in der Grasfläche mit density_weight 0.0 anlegen, damit
## sie NUR in Zonen erscheinen und nicht flächig gestreut werden.
@export var profile_index: int = 1:
	set(v):
		profile_index = max(v, 0)
		_notify_dirty()
## Wie dicht das Profil in der Zone gestreut wird, relativ zur Basisdichte der
## Grasfläche. 1.0 = gleiche Dichte wie das Gras, höher = dichteres Beet.
@export var density_multiplier: float = 1.0:
	set(v):
		density_multiplier = max(v, 0.0)
		_notify_dirty()
## Breite des weichen Übergangs am Zonenrand (Meter, nach innen gemessen).
## In diesem Ring dünnen die Blumen nach außen aus UND das normale Gras kommt
## zurück → natürliches Ausfransen statt harter Kante. 0 = harte Grenze.
@export var blend_width: float = 2.0:
	set(v):
		blend_width = max(v, 0.0)
		_notify_dirty()

@export_group("Debug")
@export var show_outline: bool = true:
	set(v):
		show_outline = v
		_update_debug_visual()

var _debug_mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("scatter_zone")
	if Engine.is_editor_hint():
		_update_debug_visual()


func _exit_tree() -> void:
	# Beim Verschieben/Löschen im Editor müssen betroffene Grasflächen neu bauen.
	if Engine.is_editor_hint():
		_notify_zone_changed()


# ============================================================
#  ABFRAGE (thread-sicher nutzbar, weil reine Mathematik auf
#  einem Snapshot — siehe snapshot())
# ============================================================

## Liefert einen reinen Daten-Snapshot für die thread-sichere Nutzung im
## GrassSystem-Worker. Positionen sind RELATIV zur Elternfläche.
func snapshot() -> Dictionary:
	# Kind-Modell: Position/Rotation RELATIV zur Elternfläche (GrassSystem).
	# So rechnet GrassSystem._compute durchgehend in seinem eigenen lokalen Raum.
	var local_xform := transform  # transform = relativ zum Parent
	return {
		"mode": mode,
		"shape": shape,
		"radius": radius,
		"size": size,
		"height_tolerance": height_tolerance,
		"density_multiplier": density_multiplier,
		"blend_width": blend_width,
		"profile_index": profile_index,
		# Ursprung & inverse Basis im ELTERN-lokalen Raum
		"local_origin": local_xform.origin,
		"inv_basis": local_xform.basis.inverse(),
		"fwd_basis": local_xform.basis,
	}


# ============================================================
#  STATISCHE TEST-HELFER (vom GrassSystem-Worker genutzt)
#  Geben den "Einfluss" 0..1 zurück: 1 = voll in der Zone,
#  0 = außerhalb, dazwischen = im weichen Rand.
#  edge_dist (Meter) = Abstand nach innen ab dem voll wirksam.
# ============================================================

## Signed distance: <0 innerhalb der Form, >0 außerhalb (Meter).
## local_pos: Position des Grashalms im ELTERN-lokalen Raum (wie GrassSystem rechnet).
static func signed_distance(snap: Dictionary, local_pos: Vector3) -> float:
	# In den Zonenraum transformieren (relativ zum Zonen-Ursprung im Elternraum)
	var p: Vector3 = snap["inv_basis"] * (local_pos - snap["local_origin"])
	if snap["shape"] == Shape.CIRCLE:
		var d := Vector2(p.x, p.z).length()
		return d - snap["radius"]
	else:
		var s: Vector2 = snap["size"]
		var qx: float = absf(p.x) - s.x
		var qz: float = absf(p.z) - s.y
		var outside := Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length()
		var inside := minf(maxf(qx, qz), 0.0)
		return outside + inside


## Prüft, ob der Punkt im vertikalen Höhenfenster der Zone liegt.
## local_pos: Position im ELTERN-lokalen Raum.
static func in_height_window(snap: Dictionary, local_pos: Vector3) -> bool:
	var tol: float = snap["height_tolerance"]
	if tol <= 0.0:
		return true
	var zone_y: float = snap["local_origin"].y
	return absf(local_pos.y - zone_y) <= tol


# ============================================================
#  EDITOR: Änderung an Grasflächen melden + Debug-Outline
# ============================================================

func _notify_dirty() -> void:
	if Engine.is_editor_hint():
		_update_debug_visual()
		_notify_zone_changed()

func _notify_zone_changed() -> void:
	# Alle Grasflächen, die diese Zone betreffen könnten, neu generieren lassen.
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	for gs in tree.get_nodes_in_group("grass_system"):
		if gs.has_method("regenerate_from_zone_change"):
			gs.call("regenerate_from_zone_change")


func _update_debug_visual() -> void:
	if not Engine.is_editor_hint():
		return
	if _debug_mesh and is_instance_valid(_debug_mesh):
		_debug_mesh.queue_free()
	_debug_mesh = null
	if not show_outline:
		return

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	if shape == Shape.CIRCLE:
		var segs := 48
		for i in segs + 1:
			var a := TAU * float(i) / float(segs)
			im.surface_add_vertex(Vector3(cos(a) * radius, 0.05, sin(a) * radius))
	else:
		var hx := size.x
		var hz := size.y
		im.surface_add_vertex(Vector3(-hx, 0.05, -hz))
		im.surface_add_vertex(Vector3(hx, 0.05, -hz))
		im.surface_add_vertex(Vector3(hx, 0.05, hz))
		im.surface_add_vertex(Vector3(-hx, 0.05, hz))
		im.surface_add_vertex(Vector3(-hx, 0.05, -hz))
	im.surface_end()

	_debug_mesh = MeshInstance3D.new()
	_debug_mesh.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Farbe je Modus: rot = EXCLUDE, grün = ADD, blau = REPLACE
	match mode:
		Mode.EXCLUDE: mat.albedo_color = Color(1.0, 0.3, 0.3)
		Mode.ADD:     mat.albedo_color = Color(0.3, 1.0, 0.4)
		Mode.REPLACE: mat.albedo_color = Color(0.4, 0.6, 1.0)
	_debug_mesh.material_override = mat
	add_child(_debug_mesh)


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if mode != Mode.EXCLUDE and profile_index < 0:
		w.append("REPLACE/ADD benötigen einen gültigen profile_index (>= 0).")
	return w

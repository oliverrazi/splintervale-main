## ============================================================================
## cave_mouth_parallax.gd  (v3)
## ----------------------------------------------------------------------------
## Prozeduraler Hoehleneingang per Parallax (v3 - Atmosphaere) auf einem Quad.
##
## Aufbauend auf v2, mit den v3-Reglern fuer:
##   - weichen, aufgebrochenen Uebergang Fels->Oeffnung (kante_*, kontakt, feather)
##   - mehr Tiefe/Dunkelheit (tiefen_daempfung, vertikal_dunkel, kern_restlicht)
##   - Ueberhang-Schattenlippe oben (ueberhang_*)
##
## Uebergang via CaveEntrance-Pattern (PlayerManager + SceneTransition).
##
## Setup:
##   1. Shader nach res://shaders/cave_mouth_parallax.gdshader (v3-Inhalt).
##   2. Node3D mit Script an die Fels-Oeffnung, Szene neu laden.
##   3. target_scene + spawn_point_id setzen.
##   4. neigung_grad an Kamerawinkel, dann Atmosphaere-Regler justieren.
## ============================================================================
@tool
extends Node3D
class_name CaveMouthParallax

# --- Uebergang (CaveEntrance-Pattern) --------------------------------------
@export_file("*.tscn") var target_scene: String = ""
@export var spawn_point_id: String = ""

# --- Quad-Geometrie ---------------------------------------------------------
@export var quad_groesse: Vector2 = Vector2(1.6, 1.9):
	set(v): quad_groesse = v; _mark_dirty()
@export var versatz_tiefe: float = 0.06:
	set(v): versatz_tiefe = v; _mark_dirty()
@export_range(-45.0, 45.0) var neigung_grad: float = 14.0:
	set(v): neigung_grad = v; _mark_dirty()

# --- Tunnel-Form ------------------------------------------------------------
@export_group("Tunnel")
@export_range(0.0, 2.5) var tiefe: float = 1.25: set = _s_tiefe
@export_range(8, 64) var schritte: int = 36: set = _s_schritte
@export_range(0.0, 1.0) var verjuengung: float = 0.42: set = _s_verjuengung
@export_range(0.0, 1.0) var roehre_rundung: float = 0.82: set = _s_rundung
@export_range(0.0, 0.5) var wand_rauheit: float = 0.2: set = _s_rauheit

# --- Tiefe / Atmosphaere ----------------------------------------------------
@export_group("Atmosphaere")
@export_range(0.0, 1.0) var tiefen_daempfung: float = 0.9: set = _s_daempfung
@export_range(0.5, 5.0) var fade_kurve: float = 2.4: set = _s_fade
@export_range(0.0, 0.15) var kern_restlicht: float = 0.03: set = _s_restlicht
@export_range(0.0, 1.0) var vertikal_dunkel: float = 0.45: set = _s_vertikal

# --- Weicher Uebergang ------------------------------------------------------
@export_group("Uebergang")
@export_range(0.05, 0.6) var kante_breite: float = 0.32: set = _s_kbreite
@export_range(0.0, 0.5) var kante_aufbruch: float = 0.22: set = _s_kaufbruch
@export_range(0.0, 1.0) var kontakt_schatten: float = 0.7: set = _s_kontakt
@export_range(0.0, 0.4) var feather_alpha: float = 0.14: set = _s_feather

# --- Ueberhang --------------------------------------------------------------
@export_group("Ueberhang")
@export_range(0.0, 1.0) var ueberhang_staerke: float = 0.55: set = _s_uebstaerke
@export_range(0.0, 1.0) var ueberhang_hoehe: float = 0.4: set = _s_uebhoehe

# --- Glimmen (Resonanzen-Slot) ---------------------------------------------
@export_group("Glimmen")
@export_range(0.0, 4.0) var glimm_staerke: float = 0.0: set = _s_glimm
@export var glimm_farbe: Color = Color(0.35, 0.62, 0.85): set = _s_glimmfarbe
@export_range(0.0, 4.0) var glimm_puls: float = 0.0: set = _s_glimmpuls

# --- Trigger ----------------------------------------------------------------
@export_group("Trigger")
@export var trigger_groesse: Vector3 = Vector3(1.4, 1.9, 0.9)
@export var trigger_versatz: Vector3 = Vector3(0.0, 0.0, 0.4)

const SHADER_PFAD := "res://scripts/shader/cave_mouth_parallax_v3.gdshader"

var _quad: MeshInstance3D
var _material: ShaderMaterial
var _trigger: Area3D
var _triggered := false
var _dirty := false


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint() and _trigger:
		_trigger.body_entered.connect(_on_body_entered)


func _process(_dt: float) -> void:
	if _dirty and Engine.is_editor_hint():
		_dirty = false
		_rebuild()


func _mark_dirty() -> void:
	_dirty = true


func _rebuild() -> void:
	if is_instance_valid(_quad): _quad.queue_free()
	if is_instance_valid(_trigger): _trigger.queue_free()

	_quad = MeshInstance3D.new()
	_quad.name = "ParallaxQuad"
	var mesh := QuadMesh.new()
	mesh.size = quad_groesse
	_quad.mesh = mesh

	_material = ShaderMaterial.new()
	var shader := load(SHADER_PFAD)
	if shader:
		_material.shader = shader
	else:
		push_warning("CaveMouthParallax: Shader fehlt unter %s" % SHADER_PFAD)
	_material.resource_local_to_scene = true
	mesh.material = _material
	_apply_all_params()

	_quad.position = Vector3(0.0, 0.0, -versatz_tiefe)
	_quad.rotation_degrees = Vector3(neigung_grad, 0.0, 0.0)
	add_child(_quad)
	if Engine.is_editor_hint() and get_tree():
		_quad.owner = get_tree().edited_scene_root

	_build_trigger()


func _build_trigger() -> void:
	_trigger = Area3D.new()
	_trigger.name = "CaveEntranceTrigger"
	_trigger.collision_layer = 0
	_trigger.monitoring = true
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = trigger_groesse
	col.shape = box
	col.position = trigger_versatz
	_trigger.add_child(col)
	add_child(_trigger)
	if Engine.is_editor_hint() and get_tree():
		_trigger.owner = get_tree().edited_scene_root


func _apply_all_params() -> void:
	if not _material: return
	_material.set_shader_parameter("tiefe", tiefe)
	_material.set_shader_parameter("schritte", schritte)
	_material.set_shader_parameter("verjuengung", verjuengung)
	_material.set_shader_parameter("roehre_rundung", roehre_rundung)
	_material.set_shader_parameter("wand_rauheit", wand_rauheit)
	_material.set_shader_parameter("tiefen_daempfung", tiefen_daempfung)
	_material.set_shader_parameter("fade_kurve", fade_kurve)
	_material.set_shader_parameter("kern_restlicht", kern_restlicht)
	_material.set_shader_parameter("vertikal_dunkel", vertikal_dunkel)
	_material.set_shader_parameter("kante_breite", kante_breite)
	_material.set_shader_parameter("kante_aufbruch", kante_aufbruch)
	_material.set_shader_parameter("kontakt_schatten", kontakt_schatten)
	_material.set_shader_parameter("feather_alpha", feather_alpha)
	_material.set_shader_parameter("ueberhang_staerke", ueberhang_staerke)
	_material.set_shader_parameter("ueberhang_hoehe", ueberhang_hoehe)
	_material.set_shader_parameter("glimm_staerke", glimm_staerke)
	_material.set_shader_parameter("glimm_farbe", Vector3(glimm_farbe.r, glimm_farbe.g, glimm_farbe.b))
	_material.set_shader_parameter("glimm_puls", glimm_puls)


func _p(name: String, value) -> void:
	if _material: _material.set_shader_parameter(name, value)


# --- Uebergang (CaveEntrance-Pattern) --------------------------------------
func _on_body_entered(body: Node3D) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	if target_scene == "":
		push_warning("CaveMouthParallax: keine target_scene gesetzt.")
		return
	_triggered = true
	if has_node("/root/PlayerManager"):
		get_node("/root/PlayerManager").pending_spawn_id = spawn_point_id
	SceneTransition.transition_to(target_scene)


# --- Live-Setter ------------------------------------------------------------
func _s_tiefe(v): tiefe = v; _p("tiefe", v)
func _s_schritte(v): schritte = v; _p("schritte", v)
func _s_verjuengung(v): verjuengung = v; _p("verjuengung", v)
func _s_rundung(v): roehre_rundung = v; _p("roehre_rundung", v)
func _s_rauheit(v): wand_rauheit = v; _p("wand_rauheit", v)
func _s_daempfung(v): tiefen_daempfung = v; _p("tiefen_daempfung", v)
func _s_fade(v): fade_kurve = v; _p("fade_kurve", v)
func _s_restlicht(v): kern_restlicht = v; _p("kern_restlicht", v)
func _s_vertikal(v): vertikal_dunkel = v; _p("vertikal_dunkel", v)
func _s_kbreite(v): kante_breite = v; _p("kante_breite", v)
func _s_kaufbruch(v): kante_aufbruch = v; _p("kante_aufbruch", v)
func _s_kontakt(v): kontakt_schatten = v; _p("kontakt_schatten", v)
func _s_feather(v): feather_alpha = v; _p("feather_alpha", v)
func _s_uebstaerke(v): ueberhang_staerke = v; _p("ueberhang_staerke", v)
func _s_uebhoehe(v): ueberhang_hoehe = v; _p("ueberhang_hoehe", v)
func _s_glimm(v): glimm_staerke = v; _p("glimm_staerke", v)
func _s_glimmfarbe(v): glimm_farbe = v; _p("glimm_farbe", Vector3(v.r, v.g, v.b))
func _s_glimmpuls(v): glimm_puls = v; _p("glimm_puls", v)

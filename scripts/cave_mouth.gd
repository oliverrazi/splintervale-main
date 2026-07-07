## ============================================================================
## cave_mouth_textured.gd  (v2)
## ----------------------------------------------------------------------------
## Hoehleneingang per textur-basiertem Parallax (Farb-Textur + Depth-Map).
## Passt zum Shader cave_mouth_textured_v2.gdshader.
##
## Neue v2-Regler:
##   - Anti-Flacker: march_lod, winkel_fade (gegen Flimmern bei flachem Winkel)
##   - Schatteneinbettung: kontakt_*, ueberhang_*, feather (nahtloser Uebergang)
##   - kamera_push + render_priority (Z-Fighting-Absicherung)
##
## Texturen zuweisen: farb_textur (Screenshot) + tiefen_karte (Depth-Map).
## Depth-Map anschauen: Loch DUNKEL, Rand HELL. Umgekehrt -> tiefe_invertieren.
##
## Uebergang via CaveEntrance-Pattern (PlayerManager + SceneTransition).
## ============================================================================
@tool
extends Node3D
class_name CaveMouthTextured

# --- Uebergang --------------------------------------------------------------
@export_file("*.tscn") var target_scene: String = ""
@export var spawn_point_id: String = ""

# --- Texturen ---------------------------------------------------------------
@export var farb_textur: Texture2D:
	set(v): farb_textur = v; _apply_textures()
@export var tiefen_karte: Texture2D:
	set(v): tiefen_karte = v; _apply_textures()
@export var tiefe_invertieren: bool = false:
	set(v): tiefe_invertieren = v; _p("tiefe_invertieren", v)

# --- Quad-Geometrie ---------------------------------------------------------
@export var quad_groesse: Vector2 = Vector2(1.6, 1.9):
	set(v): quad_groesse = v; _mark_dirty()
## In den Fels versenken (m) - Z-Fighting-Abstand zur Wand dahinter.
@export var versatz_tiefe: float = 0.2:
	set(v): versatz_tiefe = v; _mark_dirty()
@export_range(-45.0, 45.0) var neigung_grad: float = 14.0:
	set(v): neigung_grad = v; _mark_dirty()

# --- Parallax ---------------------------------------------------------------
@export_group("Parallax")
@export_range(0.0, 1.5) var tiefe: float = 0.5: set = _s_tiefe
@export_range(8, 64) var schritte: int = 48: set = _s_schritte
@export_range(0, 8) var verfeinerung: int = 6: set = _s_verfeinerung

# --- Anti-Flacker -----------------------------------------------------------
@export_group("Anti-Flacker")
## Fixes LOD fuers Depth-Sampling. Erhoehen (0.5-1.5) falls noch Flimmern.
@export_range(0.0, 4.0) var march_lod: float = 0.0: set = _s_lod
## Parallax-Fade bei flachem Winkel. Default AUS (0) - verursacht sonst
## Helligkeits-"Atmen" bei Kamerabewegung. Nur bei Bedarf aktivieren.
@export_range(0.0, 0.8) var winkel_fade: float = 0.0: set = _s_winkel
## Glaettung des Depth-Samplings gegen Block-/Treppen-Artefakte. Braucht Mipmaps!
@export_range(0.0, 4.0) var depth_glatt: float = 1.2: set = _s_dglatt
## Fixes LOD fuers Farb-Sampling. Erhoehen (0.5-2.0) falls die Oeffnung bei
## Kamerabewegung heller/dunkler flackert.
@export_range(0.0, 4.0) var farb_lod: float = 0.0: set = _s_flod

# --- Palette ----------------------------------------------------------------
@export_group("Palette")
@export var tint: Color = Color(1, 1, 1):
	set(v): tint = v; _p("tint", Vector3(v.r, v.g, v.b))
@export_range(0.0, 2.0) var helligkeit: float = 1.0: set = _s_hell
@export_range(0.0, 2.0) var kontrast: float = 1.0: set = _s_kontrast
@export_range(0.0, 2.0) var saettigung: float = 1.0: set = _s_saett

# --- Tiefe ------------------------------------------------------------------
@export_group("Tiefe")
@export var tiefen_farbe: Color = Color(0.02, 0.02, 0.03):
	set(v): tiefen_farbe = v; _p("tiefen_farbe", Vector3(v.r, v.g, v.b))
@export_range(0.0, 1.0) var tiefen_daempfung: float = 0.85: set = _s_daempf
@export_range(0.5, 4.0) var tiefen_kurve: float = 1.8: set = _s_tkurve

# --- Schatteneinbettung -----------------------------------------------------
@export_group("Schatten")
@export_range(0.0, 1.0) var kontakt_staerke: float = 0.6: set = _s_kstaerke
@export_range(0.05, 0.7) var kontakt_breite: float = 0.35: set = _s_kbreite
@export_range(0.0, 1.0) var ueberhang_staerke: float = 0.5: set = _s_uebst
@export_range(0.0, 1.0) var ueberhang_hoehe: float = 0.45: set = _s_uebho
@export_range(0.0, 0.4) var feather: float = 0.12: set = _s_feather
## Form der Rand-/Schattenzone: 0 = rechteckig (fuellt Quad-Ecken), 1 = rund.
@export_range(0.0, 1.0) var form_rundung: float = 0.25: set = _s_frundung

# --- Glimmen ----------------------------------------------------------------
@export_group("Glimmen")
@export_range(0.0, 4.0) var glimm_staerke: float = 0.0: set = _s_glimm
@export var glimm_farbe: Color = Color(0.35, 0.62, 0.85):
	set(v): glimm_farbe = v; _p("glimm_farbe", Vector3(v.r, v.g, v.b))
@export_range(0.0, 4.0) var glimm_puls: float = 0.0: set = _s_glimmp

# --- Dunst (aufsteigender Hoehlennebel) ------------------------------------
@export_group("Dunst")
## Staerke des Dunsts. 0 = aus. Subtil halten (0.2-0.5).
@export_range(0.0, 2.0) var dunst_staerke: float = 0.0: set = _s_dstaerke
@export var dunst_farbe: Color = Color(0.5, 0.52, 0.55): set = _s_dfarbe
@export_range(0.0, 1.0) var dunst_speed: float = 0.12: set = _s_dspeed
@export_range(0.5, 6.0) var dunst_dichte: float = 2.5: set = _s_ddichte
@export_range(0.0, 1.0) var dunst_tiefe_bias: float = 0.6: set = _s_dtiefe
@export_range(0.0, 1.0) var dunst_boden: float = 0.55: set = _s_dboden
## Aufstiegsrichtung: 1.0 = aufsteigen, -1.0 = fallen. Umschalten falls verkehrt.
@export var dunst_richtung: float = 1.0: set = _s_drichtung

# --- Aussen-AO (Fels-Schatten um die Oeffnung) -----------------------------
@export_group("Aussen-AO")
## AO-Schatten auf dem Fels aktivieren (laesst Oeffnung eingegraben wirken).
@export var ao_aktiv: bool = true:
	set(v): ao_aktiv = v; _mark_dirty()
## Groesse des AO-Quads relativ zur Oeffnung (1.8 = 80% groesser).
@export var ao_groesse_faktor: float = 1.8:
	set(v): ao_groesse_faktor = v; _mark_dirty()
@export_range(0.0, 1.0) var ao_staerke: float = 0.55: set = _s_aostaerke
@export_range(0.0, 1.0) var ao_innen: float = 0.28: set = _s_aoinnen
@export_range(0.0, 1.5) var ao_aussen: float = 0.95: set = _s_aoaussen
@export_range(0.5, 4.0) var ao_kurve: float = 1.6: set = _s_aokurve
## Abstand des AO-Quads vor der Felswand (m). Klein, gegen Z-Fighting.
@export var ao_wand_abstand: float = 0.02:
	set(v): ao_wand_abstand = v; _mark_dirty()

# --- Trigger ----------------------------------------------------------------
@export_group("Trigger")
@export var trigger_groesse: Vector3 = Vector3(1.4, 1.9, 0.9)
@export var trigger_versatz: Vector3 = Vector3(0.0, 0.0, 0.4)

const SHADER_PFAD := "res://scripts/shader/cave_mouth_textured.gdshader"
const AO_SHADER_PFAD := "res://scripts/shader/cave_ao_decal.gdshader"

var _quad: MeshInstance3D
var _material: ShaderMaterial
var _ao_quad: MeshInstance3D
var _ao_material: ShaderMaterial
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
	# WICHTIG: Alle FRUEHER generierten Kinder per Name entfernen, nicht nur die
	# Variablen-Referenzen. Bei @tool-Scripts koennen aus vorherigen Durchlaeufen
	# gespeicherte Quads als Szenen-Kinder existieren, auf die _quad/_ao_quad
	# nicht mehr zeigen -> sie wuerden sich sonst stapeln (Ursache des Z-Fighting-
	# Flackerns durch mehrere ueberlappende ParallaxQuads).
	_cleanup_generierte_kinder()

	# --- AO-Quad ZUERST (liegt hinter dem Parallax-Quad, an der Felswand) ---
	if ao_aktiv:
		_build_ao_quad()

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
		push_warning("CaveMouthTextured: Shader fehlt unter %s" % SHADER_PFAD)
	_material.resource_local_to_scene = true
	_material.render_priority = 1   # vor die Felswand sortieren
	mesh.material = _material
	_apply_all_params()

	_quad.position = Vector3(0.0, 0.0, -versatz_tiefe)
	_quad.rotation_degrees = Vector3(neigung_grad, 0.0, 0.0)
	add_child(_quad)
	# KEIN owner setzen: die Geometrie wird zur Laufzeit/beim Laden immer neu
	# erzeugt und darf NICHT in die Szene gespeichert werden, sonst sammelt sie
	# sich bei jedem @tool-Rebuild an.

	_build_trigger()


## Entfernt ALLE von diesem Node generierten Kinder (auch aus frueheren
## @tool-Durchlaeufen gespeicherte). Findet sie per Namenspraefix.
func _cleanup_generierte_kinder() -> void:
	var namen := ["ParallaxQuad", "AO_Decal", "CaveEntranceTrigger"]
	for child in get_children():
		for n in namen:
			if child.name.begins_with(n):
				remove_child(child)
				child.queue_free()
				break
	_quad = null
	_ao_quad = null
	_trigger = null


func _build_ao_quad() -> void:
	_ao_quad = MeshInstance3D.new()
	_ao_quad.name = "AO_Decal"
	var mesh := QuadMesh.new()
	mesh.size = quad_groesse * ao_groesse_faktor
	_ao_quad.mesh = mesh

	_ao_material = ShaderMaterial.new()
	var shader := load(AO_SHADER_PFAD)
	if shader:
		_ao_material.shader = shader
	else:
		push_warning("CaveMouthTextured: AO-Shader fehlt unter %s" % AO_SHADER_PFAD)
	_ao_material.resource_local_to_scene = true
	# render_priority 0 (unter dem Parallax-Quad mit priority 1).
	_ao_material.render_priority = 0
	mesh.material = _ao_material
	_apply_ao_params()

	# Liegt an der Felswand, minimal davor (Richtung Kamera = +Z lokal, also
	# knapp vor der Wand aber hinter dem Parallax-Quad).
	_ao_quad.position = Vector3(0.0, 0.0, ao_wand_abstand)
	add_child(_ao_quad)
	# KEIN owner (siehe _rebuild): nicht in die Szene speichern.


func _apply_ao_params() -> void:
	if not _ao_material: return
	_ao_material.set_shader_parameter("ao_staerke", ao_staerke)
	_ao_material.set_shader_parameter("ao_innen", ao_innen)
	_ao_material.set_shader_parameter("ao_aussen", ao_aussen)
	_ao_material.set_shader_parameter("ao_kurve", ao_kurve)


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
	# KEIN owner (siehe _rebuild): nicht in die Szene speichern.


func _apply_all_params() -> void:
	if not _material: return
	_material.set_shader_parameter("tiefe", tiefe)
	_material.set_shader_parameter("schritte", schritte)
	_material.set_shader_parameter("verfeinerung", verfeinerung)
	_material.set_shader_parameter("tiefe_invertieren", tiefe_invertieren)
	_material.set_shader_parameter("march_lod", march_lod)
	_material.set_shader_parameter("winkel_fade", winkel_fade)
	_material.set_shader_parameter("depth_glatt", depth_glatt)
	_material.set_shader_parameter("farb_lod", farb_lod)
	_material.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_material.set_shader_parameter("helligkeit", helligkeit)
	_material.set_shader_parameter("kontrast", kontrast)
	_material.set_shader_parameter("saettigung", saettigung)
	_material.set_shader_parameter("tiefen_farbe", Vector3(tiefen_farbe.r, tiefen_farbe.g, tiefen_farbe.b))
	_material.set_shader_parameter("tiefen_daempfung", tiefen_daempfung)
	_material.set_shader_parameter("tiefen_kurve", tiefen_kurve)
	_material.set_shader_parameter("kontakt_staerke", kontakt_staerke)
	_material.set_shader_parameter("kontakt_breite", kontakt_breite)
	_material.set_shader_parameter("ueberhang_staerke", ueberhang_staerke)
	_material.set_shader_parameter("ueberhang_hoehe", ueberhang_hoehe)
	_material.set_shader_parameter("feather", feather)
	_material.set_shader_parameter("form_rundung", form_rundung)
	_material.set_shader_parameter("glimm_staerke", glimm_staerke)
	_material.set_shader_parameter("glimm_farbe", Vector3(glimm_farbe.r, glimm_farbe.g, glimm_farbe.b))
	_material.set_shader_parameter("glimm_puls", glimm_puls)
	_material.set_shader_parameter("dunst_staerke", dunst_staerke)
	_material.set_shader_parameter("dunst_farbe", Vector3(dunst_farbe.r, dunst_farbe.g, dunst_farbe.b))
	_material.set_shader_parameter("dunst_speed", dunst_speed)
	_material.set_shader_parameter("dunst_dichte", dunst_dichte)
	_material.set_shader_parameter("dunst_tiefe_bias", dunst_tiefe_bias)
	_material.set_shader_parameter("dunst_boden", dunst_boden)
	_material.set_shader_parameter("dunst_richtung", dunst_richtung)
	_apply_textures()


func _apply_textures() -> void:
	if not _material: return
	if farb_textur: _material.set_shader_parameter("farb_textur", farb_textur)
	if tiefen_karte: _material.set_shader_parameter("tiefen_karte", tiefen_karte)


func _p(name: String, value) -> void:
	if _material: _material.set_shader_parameter(name, value)


# --- Uebergang (CaveEntrance-Pattern) --------------------------------------
func _on_body_entered(body: Node3D) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	if target_scene == "":
		push_warning("CaveMouthTextured: keine target_scene gesetzt.")
		return
	_triggered = true
	if has_node("/root/PlayerManager"):
		get_node("/root/PlayerManager").pending_spawn_id = spawn_point_id
	SceneTransition.transition_to(target_scene)


# --- Live-Setter ------------------------------------------------------------
func _s_tiefe(v): tiefe = v; _p("tiefe", v)
func _s_schritte(v): schritte = v; _p("schritte", v)
func _s_verfeinerung(v): verfeinerung = v; _p("verfeinerung", v)
func _s_lod(v): march_lod = v; _p("march_lod", v)
func _s_winkel(v): winkel_fade = v; _p("winkel_fade", v)
func _s_dglatt(v): depth_glatt = v; _p("depth_glatt", v)
func _s_flod(v): farb_lod = v; _p("farb_lod", v)
func _s_hell(v): helligkeit = v; _p("helligkeit", v)
func _s_kontrast(v): kontrast = v; _p("kontrast", v)
func _s_saett(v): saettigung = v; _p("saettigung", v)
func _s_daempf(v): tiefen_daempfung = v; _p("tiefen_daempfung", v)
func _s_tkurve(v): tiefen_kurve = v; _p("tiefen_kurve", v)
func _s_kstaerke(v): kontakt_staerke = v; _p("kontakt_staerke", v)
func _s_kbreite(v): kontakt_breite = v; _p("kontakt_breite", v)
func _s_uebst(v): ueberhang_staerke = v; _p("ueberhang_staerke", v)
func _s_uebho(v): ueberhang_hoehe = v; _p("ueberhang_hoehe", v)
func _s_feather(v): feather = v; _p("feather", v)
func _s_frundung(v): form_rundung = v; _p("form_rundung", v)
func _s_glimm(v): glimm_staerke = v; _p("glimm_staerke", v)
func _s_glimmp(v): glimm_puls = v; _p("glimm_puls", v)

# --- Dunst-Setter -----------------------------------------------------------
func _s_dstaerke(v): dunst_staerke = v; _p("dunst_staerke", v)
func _s_dfarbe(v): dunst_farbe = v; _p("dunst_farbe", Vector3(v.r, v.g, v.b))
func _s_dspeed(v): dunst_speed = v; _p("dunst_speed", v)
func _s_ddichte(v): dunst_dichte = v; _p("dunst_dichte", v)
func _s_dtiefe(v): dunst_tiefe_bias = v; _p("dunst_tiefe_bias", v)
func _s_dboden(v): dunst_boden = v; _p("dunst_boden", v)
func _s_drichtung(v): dunst_richtung = v; _p("dunst_richtung", v)

# --- AO-Setter (wirken auf das AO-Material) ---------------------------------
func _ao_p(name: String, value) -> void:
	if _ao_material: _ao_material.set_shader_parameter(name, value)

func _s_aostaerke(v): ao_staerke = v; _ao_p("ao_staerke", v)
func _s_aoinnen(v): ao_innen = v; _ao_p("ao_innen", v)
func _s_aoaussen(v): ao_aussen = v; _ao_p("ao_aussen", v)
func _s_aokurve(v): ao_kurve = v; _ao_p("ao_kurve", v)

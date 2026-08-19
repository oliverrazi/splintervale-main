@tool
extends Node3D
class_name FloorOccluder

## Blendet diese Ebene aus, wenn der Player darunter ist.
## Nutzt Material-Override für den Fade, danach visible=false für Nullkosten.

@export var player_group: StringName = &"player"
@export_group("Schwellen (relativ zur eigenen Y-Position)")
## Unter diesem Offset wird ausgeblendet. Negativ = unterhalb der Ebene.
@export var hide_below_offset: float = -0.5
## Ab diesem Offset wird wieder eingeblendet. MUSS über hide_below_offset liegen.
@export var show_above_offset: float = -0.15
@export_group("Fade")
@export var fade_duration: float = 0.25
@export var fade_curve: Curve
@export var fade_shader: Shader

var _player: Node3D
var _is_hidden: bool = false
var _tween: Tween
var _geometry: Array[GeometryInstance3D] = []

var _debug_erste_frames: int = 0

var _hard_hide: Array[GeometryInstance3D] = []

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(false)
	_starte_initialisierung()


func _starte_initialisierung() -> void:
	await _warte_auf_baker()
	_sammle_geometrie(self)
	_setze_alpha(1.0)
	_suche_player()


func _warte_auf_baker() -> void:
	var baker: Array[MultiMeshBaker] = []
	_sammle_baker(self, baker)
	if baker.is_empty():
		# Trotzdem einen Frame warten — andere deferred Systeme.
		await get_tree().process_frame
		return
	for b in baker:
		if b.bake_on_ready and b._baked_nodes.is_empty():
			await b.bake_finished
	# Ein Frame Puffer, damit add_child() durch ist.
	await get_tree().process_frame


func _sammle_baker(node: Node, out: Array[MultiMeshBaker]) -> void:
	for child in node.get_children():
		if child is MultiMeshBaker:
			out.append(child)
		_sammle_baker(child, out)


func _suche_player() -> void:
	_player = get_tree().get_first_node_in_group(player_group) as Node3D
	if _player == null:
		# Player noch nicht da (Szenenwechsel / deferred Load) — nächsten Frame erneut.
		await get_tree().process_frame
		if not is_inside_tree():
			return
		_suche_player()
		return
	set_process(true)

func _sammle_geometrie(node: Node) -> void:
	for child in node.get_children():
		var geo := child as GeometryInstance3D
		if geo != null:
			if geo is MeshInstance3D and _hat_fade_uniform(geo as MeshInstance3D):
				_geometry.append(geo)
			else:
				_hard_hide.append(geo)
		_sammle_geometrie(child)


func _hat_fade_uniform(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or fade_shader == null:
		return false
	for surf in range(mi.mesh.get_surface_count()):
		var sm := mi.get_active_material(surf) as ShaderMaterial
		if sm != null and sm.shader == fade_shader:
			return true
	return false
		
func _praepariere_material(geo: GeometryInstance3D) -> void:
	## Importierte Materialien sind oft TRANSPARENCY_DISABLED — dann ignoriert
	## Godot die Instance-Transparency. Wir duplizieren das Material pro
	## Instanz und schalten den Alpha-Pfad frei.
	var mi := geo as MeshInstance3D
	if mi == null:
		return
	var mesh: Mesh = mi.mesh
	if mesh == null:
		return
	for surf in range(mesh.get_surface_count()):
		var mat: Material = mi.get_active_material(surf)
		var std := mat as StandardMaterial3D
		if std == null:
			continue
		if std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var kopie: StandardMaterial3D = std.duplicate() as StandardMaterial3D
		kopie.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.set_surface_override_material(surf, kopie)

func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		set_process(false)
		_suche_player()
		return
	var rel_y: float = _player.global_position.y - global_position.y
	if not _is_hidden and rel_y < hide_below_offset:
		_starte_fade(true)
	elif _is_hidden and rel_y > show_above_offset:
		_starte_fade(false)
		
func _starte_fade(nach_versteckt: bool) -> void:
	print("_starte_fade(nach_versteckt=%s)" % str(nach_versteckt))
	_is_hidden = nach_versteckt
	if _tween != null and _tween.is_valid():
		_tween.kill()

	# Harte Gruppe: beim Einblenden sofort sichtbar, beim Ausblenden
	# erst am Ende des Fades — sonst klaffen für 0.25s Löcher, wo die
	# Walls schon weg, der Boden aber noch da ist.
	if not nach_versteckt:
		visible = true
		_setze_hard_hide(true)

	var ziel: float = 0.0 if nach_versteckt else 1.0
	_tween = create_tween()
	_tween.tween_method(_setze_alpha, _aktuelles_alpha(), ziel, fade_duration)

	if nach_versteckt:
		_tween.tween_callback(func() -> void:
			_setze_hard_hide(false)
			visible = false
		)


func _setze_hard_hide(sichtbar: bool) -> void:
	var count := 0
	for i in range(_hard_hide.size() - 1, -1, -1):
		var geo: GeometryInstance3D = _hard_hide[i]
		if not is_instance_valid(geo):
			_hard_hide.remove_at(i)
			continue
		geo.visible = sichtbar
		count += 1
	print("_setze_hard_hide(%s): %d Nodes geschaltet, Beispiel: %s visible=%s" % [
		str(sichtbar), count,
		_hard_hide[0].name if not _hard_hide.is_empty() else "LEER",
		str(_hard_hide[0].visible) if not _hard_hide.is_empty() else "?"
	])

var _alpha: float = 1.0

func _aktuelles_alpha() -> float:
	return _alpha
	

func _setze_alpha(a: float) -> void:
	_alpha = a
	var opak: bool = is_equal_approx(a, 1.0)
	for i in range(_geometry.size() - 1, -1, -1):
		var geo: GeometryInstance3D = _geometry[i]
		if not is_instance_valid(geo):
			_geometry.remove_at(i)
			continue
		geo.set_instance_shader_parameter(&"occluder_fade", a)
		geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if opak \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

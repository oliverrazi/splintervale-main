@tool
extends MeshInstance3D
class_name FogPatch
## Eine einzelne, flach liegende Nebelfläche, die du SELBST in der Welt
## platzierst und skalierst. Ersetzt das frühere FogCloudField.
##
## Benutzung:
##   1) Node hinzufügen -> MeshInstance3D -> dieses Script anhängen
##      (oder direkt einen "FogPatch"-Node erstellen)
##   2) `fog_shader` = fog_drift.gdshader zuweisen
##   3) im Editor an die gewünschte Stelle ziehen, knapp über den Boden
##      (z.B. y = Bodenhöhe + 0.1), `size` auf die Fläche stellen
##   4) so viele platzieren, wie du Nebelbereiche brauchst
##
## Liegt dank PlaneMesh von Haus aus flach (horizontal). Bewegung kommt
## über den langsam wabernden Noise – der Patch selbst bleibt stehen.

@export var fog_shader: Shader:
	set(v): fog_shader = v; _rebuild()

@export var size: Vector2 = Vector2(6.0, 6.0):
	set(v): size = v; _rebuild()

@export_group("Aussehen")
@export var fog_color: Color = Color(0.72, 0.78, 0.85):
	set(v): fog_color = v; _set_param("fog_color", v)
@export_range(0.0, 1.0) var opacity: float = 0.40:
	set(v): opacity = v; _set_param("opacity", v)
@export_range(0.0, 1.0) var coverage: float = 0.45:
	set(v): coverage = v; _set_param("coverage", v)
@export_range(0.05, 1.0) var radial_softness: float = 0.65:
	set(v): radial_softness = v; _set_param("radial_softness", v)
@export_range(0.01, 1.0) var noise_softness: float = 0.40:
	set(v): noise_softness = v; _set_param("noise_softness", v)

@export_group("Bewegung")
## Klein halten für fast stehenden Nebel. 0 = komplett still.
@export_range(0.0, 2.0) var anim_speed: float = 0.4:
	set(v): anim_speed = v; _set_param("anim_speed", v)
@export var drift: Vector2 = Vector2(0.6, 0.35):
	set(v): drift = v; _set_param("drift", v)

@export_group("Schärfe / Tiefe")
@export var noise_scale: float = 2.0:
	set(v): noise_scale = v; _set_param("noise_scale", v)
@export var detail_scale: float = 5.0:
	set(v): detail_scale = v; _set_param("detail_scale", v)
@export var soft_distance: float = 1.5:
	set(v): soft_distance = v; _set_param("soft_distance", v)

var _mat: ShaderMaterial


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if not (mesh is PlaneMesh):
		mesh = PlaneMesh.new()          # liegt flach (horizontal)
	(mesh as PlaneMesh).size = size
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if fog_shader == null:
		return
	if _mat == null:
		_mat = ShaderMaterial.new()
	_mat.shader = fog_shader
	material_override = _mat

	# Jeder Patch bekommt anhand seiner Position ein eigenes Noise-Muster,
	# damit benachbarte Flächen nicht identisch aussehen.
	var off := Vector2(global_position.x, global_position.z) * 0.13
	_mat.set_shader_parameter("noise_offset", off)

	_set_param("fog_color", fog_color)
	_set_param("opacity", opacity)
	_set_param("coverage", coverage)
	_set_param("radial_softness", radial_softness)
	_set_param("noise_softness", noise_softness)
	_set_param("anim_speed", anim_speed)
	_set_param("drift", drift)
	_set_param("noise_scale", noise_scale)
	_set_param("detail_scale", detail_scale)
	_set_param("soft_distance", soft_distance)


func _set_param(name: String, value) -> void:
	if _mat:
		_mat.set_shader_parameter(name, value)


## Nebel-Dichte sanft faden (z.B. Director beim Intro-Reveal).
func set_opacity(target: float, duration: float = 1.0) -> void:
	if _mat == null:
		return
	var t := create_tween()
	t.tween_method(func(v): _mat.set_shader_parameter("opacity", v), opacity, target, duration)
	opacity = target

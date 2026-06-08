extends Node3D
class_name FogCloudField
## Verwaltet ein Feld treibender Nebelwolken (Quads mit fog_drift.gdshader).
##
## Platziere diesen Node dort in der Welt, wo der Nebel liegen soll – die
## Wolken treiben um die Position dieses Nodes herum und wrappen nahtlos,
## sobald sie den Feldrand erreichen (Endlos-Drift, kein Pop).
##
## Empfehlung für AAA-Tiefe: ZWEI Felder verwenden
##   1) Bodennebel  – flach liegende Quads, niedrig, langsamer Drift
##   2) Wolkenbank   – hohe, vertikale Quads im Mittel-/Hintergrund
##
## fog_drift.gdshader im Inspector der Property `fog_shader` zuweisen.

@export var fog_shader: Shader

@export_group("Feld")
@export var count: int = 14
@export var field_size: Vector3 = Vector3(40, 6, 40)  ## Ausdehnung (X,Y,Z)
@export var drift: Vector3 = Vector3(0.6, 0.0, 0.15)  ## m/s
@export var face_camera: bool = true                  ## Quads zur Kamera drehen

@export_group("Wolken")
@export var size_min: float = 8.0
@export var size_max: float = 18.0
@export var color: Color = Color(0.74, 0.79, 0.86)
@export var opacity: float = 0.55
@export var coverage: float = 0.5
@export var edge_softness: float = 0.5

class _Cloud:
	var mi: MeshInstance3D
	var mat: ShaderMaterial

var _clouds: Array[_Cloud] = []
var _current_opacity: float
var _half: Vector3


func _ready() -> void:
	_current_opacity = opacity
	_half = field_size * 0.5

	if not fog_shader:
		push_warning("FogCloudField: 'fog_shader' nicht zugewiesen (fog_drift.gdshader).")
		return

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE  # Skalierung über den Node-Scale

	for i in count:
		var c := _Cloud.new()
		c.mi = MeshInstance3D.new()
		c.mi.mesh = quad
		c.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		c.mat = ShaderMaterial.new()
		c.mat.shader = fog_shader
		c.mat.set_shader_parameter("fog_color", color)
		c.mat.set_shader_parameter("opacity", _current_opacity)
		c.mat.set_shader_parameter("coverage", coverage)
		c.mat.set_shader_parameter("edge_softness", edge_softness)
		# Pro Wolke einzigartiges Noise-Muster und Tempo:
		c.mat.set_shader_parameter("noise_offset", Vector2(randf() * 10.0, randf() * 10.0))
		c.mat.set_shader_parameter("time_scale", randf_range(0.7, 1.3))
		c.mi.material_override = c.mat

		var s := randf_range(size_min, size_max)
		c.mi.scale = Vector3(s, s, s)
		c.mi.position = Vector3(
			randf_range(-_half.x, _half.x),
			randf_range(-_half.y, _half.y),
			randf_range(-_half.z, _half.z)
		)

		add_child(c.mi)
		_clouds.append(c)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	for c in _clouds:
		var p := c.mi.position + drift * delta
		# Nahtloser Wrap um die Feldmitte
		p.x = fposmod(p.x + _half.x, field_size.x) - _half.x
		p.z = fposmod(p.z + _half.z, field_size.z) - _half.z
		c.mi.position = p

		if face_camera and cam:
			var to := cam.global_position
			to.y = c.mi.global_position.y  # Y-locked, kippt nicht
			if c.mi.global_position.distance_squared_to(to) > 0.01:
				c.mi.look_at(to, Vector3.UP)


## Nebel-Dichte sanft faden (z.B. beim Intro-Reveal).
func set_opacity(target: float, duration: float = 1.0) -> void:
	var t := create_tween()
	t.tween_method(_apply_opacity, _current_opacity, target, duration)


func _apply_opacity(v: float) -> void:
	_current_opacity = v
	for c in _clouds:
		c.mat.set_shader_parameter("opacity", v)


## Nebel-Farbe an die Umgebung anpassen (z.B. Wald -> Höhle).
func set_color(target: Color, duration: float = 1.5) -> void:
	var t := create_tween()
	t.tween_method(_apply_color, color, target, duration)


func _apply_color(v: Color) -> void:
	color = v
	for c in _clouds:
		c.mat.set_shader_parameter("fog_color", v)

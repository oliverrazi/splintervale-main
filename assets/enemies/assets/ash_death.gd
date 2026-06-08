extends Node3D
class_name AshDeath

## Pixel-Art Death Effect mit Crossfade-Uebergang.
##
## Choreografie:
##   t=0.00s   Snapshot. Ghost ist black silhouette mit alpha=0.
##             Original ist sichtbar mit alpha=1.
##   t=0.00-0.18s   CROSSFADE: Original alpha 1->0, Ghost alpha 0->1.
##                  Visuell: Goblin "verkohlt" sich nahtlos.
##   t=0.18s   Original wird auf visible=false gesetzt (cleanup).
##   t=0.18-0.30s   Hold (verkohlte Silhouette).
##   t=0.30s   Dissolve startet, Light Flare, Flakes + Embers Burst.
##   t=1.00s   Dissolve fertig.
##   t=2.60s   Cleanup.

@export_group("Timing")
@export var crossfade_duration: float = 0.18
@export var pre_dissolve_hold: float = 0.12
@export var dissolve_duration: float = 0.7
@export var lifetime: float = 2.6

@export_group("Wind")
@export var wind_dir: Vector2 = Vector2(1.0, -0.35)

@export_group("Light Flare")
@export var light_peak_energy: float = 0.7

@onready var ghost: MeshInstance3D = $Ghost
@onready var smoke: GPUParticles3D = $Smoke
@onready var flakes: GPUParticles3D = $Flakes
@onready var embers: GPUParticles3D = $Embers
@onready var death_light: OmniLight3D = $DeathLight

var _material: ShaderMaterial
var _from_sprite: Node3D = null


func play(from_sprite: MeshInstance3D, dissolve_time: float = -1.0) -> void:
	if dissolve_time > 0.0:
		dissolve_duration = dissolve_time

	global_transform = from_sprite.global_transform
	_from_sprite = from_sprite

	if from_sprite.mesh:
		ghost.mesh = from_sprite.mesh

	# Sphere-Emission auf Sprite-Groesse skalieren
	var sprite_size := Vector2(0.3, 0.3)
	if from_sprite.mesh is QuadMesh:
		sprite_size = (from_sprite.mesh as QuadMesh).size

	var base_radius: float = min(sprite_size.x, sprite_size.y) * 0.4
	_setup_sphere_emission(flakes, base_radius * 1.0)
	_setup_sphere_emission(embers, base_radius * 0.75)
	_setup_sphere_emission(smoke, base_radius * 0.6)

	var base_mat := ghost.material_override as ShaderMaterial
	if base_mat == null:
		push_error("AshDeath: Ghost hat kein ShaderMaterial als material_override.")
		queue_free()
		return
	_material = base_mat.duplicate() as ShaderMaterial
	ghost.material_override = _material

	_copy_param(from_sprite, "texture", "albedo_tex")
	_copy_param(from_sprite, "hframes", "hframes")
	_copy_param(from_sprite, "vframes", "vframes")
	_copy_param(from_sprite, "frame", "frame")
	_copy_param(from_sprite, "flip_h", "flip_h")
	if "modulate" in from_sprite:
		_material.set_shader_parameter("sprite_modulate", from_sprite.modulate)

	# Ghost startet als BEREITS SCHWARZE Silhouette, aber unsichtbar (fade_in=0)
	_material.set_shader_parameter("wind_dir", wind_dir)
	_material.set_shader_parameter("dissolve", 0.0)
	_material.set_shader_parameter("wind_skew", 0.0)
	_material.set_shader_parameter("white_mix", 0.0)
	_material.set_shader_parameter("black_mix", 1.0)
	_material.set_shader_parameter("fade_in", 0.0)

	# === CROSSFADE: Original fadet aus, Ghost fadet rein ===
	var crossfade_tw := create_tween().set_parallel()
	# Original-Sprite alpha 1 -> 0
	crossfade_tw.tween_property(from_sprite, "modulate:a", 0.0, crossfade_duration) \
		.set_ease(Tween.EASE_IN_OUT)
	# Ghost fade_in 0 -> 1
	crossfade_tw.tween_property(_material, "shader_parameter/fade_in", 1.0, crossfade_duration) \
		.set_ease(Tween.EASE_IN_OUT)
	# Cleanup: nach Crossfade wirklich ausschalten
	crossfade_tw.chain().tween_callback(_hide_original)

	var dissolve_start: float = crossfade_duration + pre_dissolve_hold

	var tree := get_tree()
	tree.create_timer(crossfade_duration).timeout.connect(_start_smoke)
	tree.create_timer(dissolve_start).timeout.connect(_start_dissolve)
	tree.create_timer(lifetime).timeout.connect(queue_free)


func _setup_sphere_emission(particles: GPUParticles3D, radius: float) -> void:
	if not particles or not particles.process_material:
		return
	var proc := particles.process_material.duplicate() as ParticleProcessMaterial
	if proc == null:
		return
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = radius
	particles.process_material = proc


func _hide_original() -> void:
	# Nach dem Crossfade den Original wirklich ausschalten - Failsafe
	# falls modulate.a doch nicht alles fadet.
	if _from_sprite and is_instance_valid(_from_sprite):
		_from_sprite.visible = false


func _start_smoke() -> void:
	if is_inside_tree() and smoke:
		smoke.emitting = true


func _start_dissolve() -> void:
	if not is_inside_tree() or not _material:
		return

	var tw := create_tween().set_parallel()
	tw.tween_property(_material, "shader_parameter/dissolve", 1.0, dissolve_duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_material, "shader_parameter/wind_skew", 1.0, dissolve_duration)

	if death_light:
		var light_tw := create_tween()
		light_tw.tween_property(death_light, "light_energy", light_peak_energy, 0.12)
		light_tw.tween_property(death_light, "light_energy", 0.0, dissolve_duration - 0.12) \
			.set_ease(Tween.EASE_OUT)

	if flakes:
		flakes.emitting = true
	if embers:
		embers.emitting = true


func _copy_param(from: Object, prop: StringName, shader_param: StringName) -> void:
	if prop in from:
		_material.set_shader_parameter(shader_param, from.get(prop))

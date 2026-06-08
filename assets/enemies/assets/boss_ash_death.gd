extends AshDeath
class_name BossAshDeath

## Erweiterte Version des AshDeath fuer Optional-Bosses (Oger, etc).
##
## Erbt die komplette Crossfade-Dissolve-Pipeline und erweitert:
## - Groesserer, langsamer Dissolve (1.1s statt 0.7s)
## - Hoehere Pixel-Resolution (128) - feinere Dissolve-Bloecke fuer scharfen Look
## - Deutlich mehr Partikel (7x Goblin-Defaults)
## - Glut-Funken-Restlicht: glimmender OmniLight + kleine Embers am Boden, 3s lang
## - SubViewport-Handling: friert den Boss-Render-Frame beim play() ein

@export_group("Boss Calibration")
## Pixel-Resolution fuer Dissolve. HOEHER = feinere Bloecke = schaerfer.
## Goblin nutzt 64. Boss-Sprite ist groesser, also brauchen wir hoehere
## Resolution um die gleiche Pixel-Schaerfe zu erreichen.
## Falls die Bloecke immer noch zu gross wirken: weiter hochsetzen (192, 256).
@export var boss_dissolve_pixel_resolution: float = 128.0

## Partikel-Mengen-Multiplikator vs. Goblin-Defaults.
## 7.0 = ordentlich Schippe. Falls noch mehr gewuenscht: hoch auf 10+.
@export var particle_amount_multiplier: float = 10.0

@export_group("Ember Glow Afterlife")
@export var ember_glow_duration: float = 3.0
@export var ember_glow_light_color: Color = Color(0.7, 0.2, 1.0)
@export var ember_glow_initial_energy: float = 0.4

@export_group("SubViewport Freeze")
@export var freeze_subviewport: bool = true

@onready var ember_light: OmniLight3D = $EmberGlowLight
@onready var ember_particles: GPUParticles3D = $EmberGlowParticles

var _frozen_viewport: SubViewport = null


func play(from_sprite: MeshInstance3D, dissolve_time: float = -1.0) -> void:
	if freeze_subviewport:
		_freeze_render_viewport(from_sprite)

	if dissolve_time <= 0.0:
		dissolve_duration = 2.1
	lifetime = 4.5

	_boost_particle_amounts()

	super(from_sprite, dissolve_time)

	# Pixel-Resolution am Ghost-Material ueberschreiben (nach super(),
	# weil dort das Material erst dupliziert wird)
	if _material:
		_material.set_shader_parameter("dissolve_pixel_resolution", boss_dissolve_pixel_resolution)

	var ember_start: float = crossfade_duration + pre_dissolve_hold + dissolve_duration * 0.7
	get_tree().create_timer(ember_start).timeout.connect(_start_ember_afterlife)


func _freeze_render_viewport(from_sprite: MeshInstance3D) -> void:
	if not from_sprite or not is_instance_valid(from_sprite):
		return

	var node: Node = from_sprite
	while node:
		if node.has_node("RenderViewport"):
			var vp := node.get_node("RenderViewport") as SubViewport
			if vp:
				_frozen_viewport = vp
				vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
				return
		node = node.get_parent()


func _boost_particle_amounts() -> void:
	if flakes:
		flakes.amount = int(flakes.amount * particle_amount_multiplier)
	if embers:
		embers.amount = int(embers.amount * particle_amount_multiplier)
	if smoke:
		smoke.amount = int(smoke.amount * particle_amount_multiplier)


func _start_ember_afterlife() -> void:
	if not is_inside_tree():
		return

	if ember_light:
		ember_light.position.y = -0.3
	if ember_particles:
		ember_particles.position.y = -0.3
		ember_particles.emitting = true

	if ember_light:
		var fade_in: float = 0.3
		var fade_out: float = ember_glow_duration - fade_in

		ember_light.light_color = ember_glow_light_color
		var tw := create_tween()
		tw.tween_property(ember_light, "light_energy", ember_glow_initial_energy, fade_in) \
			.set_ease(Tween.EASE_OUT)
		tw.tween_property(ember_light, "light_energy", 0.0, fade_out) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

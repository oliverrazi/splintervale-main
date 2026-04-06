## CaveCrystal — Glowing crystal decoration for caves.
##
## Creates a pixel-art crystal sprite with an OmniLight3D that pulses gently.
## Optionally interactable (collectible, breakable, or activatable).
##
## Setup:
##   1. Add to your cave scene under CaveDecorations.
##   2. Assign a crystal sprite texture.
##   3. Position where desired.
##   4. The light is auto-created.

class_name CaveCrystal
extends Node3D

# ── Configuration ─────────────────────────────────────────────────────────────

@export_group("Appearance")
@export var crystal_texture: Texture2D = null
@export var crystal_color: Color = Color(0.3, 0.7, 1.0)
@export var crystal_size: float = 1.0
@export var pixel_size: float = 0.01  # For Sprite3D pixel scale

@export_group("Light")
@export var light_enabled: bool = true
@export var light_energy: float = 0.6
@export var light_range: float = 4.0
@export var light_height_offset: float = 0.3
@export var pulse_speed: float = 1.5
@export var pulse_amount: float = 0.3

@export_group("Interaction")
@export var interactable: bool = false
@export var interaction_type: InteractionType = InteractionType.NONE
@export var cave_object_id: String = ""  # For persistence via GlobalCaveData

@export_group("Particles")
@export var sparkle_particles: bool = true
@export var sparkle_amount: int = 6

enum InteractionType {
	NONE,
	COLLECTIBLE,    ## Disappears when collected, gives item
	BREAKABLE,      ## Can be destroyed by attack
	ACTIVATABLE,    ## Toggles on/off (puzzle element)
}

# ── Signals ───────────────────────────────────────────────────────────────────

signal crystal_collected(crystal: CaveCrystal)
signal crystal_broken(crystal: CaveCrystal)
signal crystal_activated(crystal: CaveCrystal, active: bool)

# ── Internal ──────────────────────────────────────────────────────────────────

var _sprite: Sprite3D
var _light: OmniLight3D
var _particles: GPUParticles3D
var _interaction_area: Area3D
var _base_energy: float
var _phase: float
var _is_active: bool = true
var _collected: bool = false


func _ready() -> void:
	_phase = randf() * TAU  # Random start phase
	_base_energy = light_energy

	_create_sprite()
	if light_enabled:
		_create_light()
	if sparkle_particles:
		_create_sparkle_particles()
	if interactable:
		_create_interaction_area()

	# Check persistence
	if not cave_object_id.is_empty():
		var cave_sys := _find_cave_system()
		if cave_sys:
			var _cave_data: Node = get_node_or_null("/root/GlobalCaveData")
			if _cave_data:
				var was_collected: bool = _cave_data.get_cave_flag(cave_sys.cave_id, cave_object_id, false)
				if was_collected:
					_collected = true
					visible = false
					set_process(false)


func _process(_delta: float) -> void:
	if not _is_active or _collected:
		return

	if _light:
		# Smooth pulsing glow
		var t: float = (Time.get_ticks_msec() / 1000.0) * pulse_speed + _phase
		var pulse := (sin(t) + 1.0) * 0.5
		pulse = smoothstep(0.2, 0.8, pulse)
		_light.light_energy = _base_energy * (1.0 - pulse_amount + pulse * pulse_amount)


func _create_sprite() -> void:
	_sprite = Sprite3D.new()
	_sprite.name = "CrystalSprite"
	if crystal_texture:
		_sprite.texture = crystal_texture
	_sprite.pixel_size = pixel_size
	_sprite.modulate = crystal_color
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_sprite.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	# Scale
	_sprite.scale = Vector3.ONE * crystal_size
	add_child(_sprite)


func _create_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "CrystalGlow"
	_light.light_color = crystal_color
	_light.light_energy = light_energy
	_light.omni_range = light_range
	_light.omni_attenuation = 1.8
	_light.shadow_enabled = false
	_light.position.y = light_height_offset
	add_child(_light)


func _create_sparkle_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "Sparkles"
	_particles.amount = sparkle_amount
	_particles.lifetime = 2.0
	_particles.explosiveness = 0.0
	_particles.randomness = 1.0
	_particles.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3 * crystal_size

	mat.direction = Vector3(0, 1, 0)
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.15
	mat.gravity = Vector3(0, 0.1, 0)
	mat.spread = 180.0

	mat.scale_min = 0.02
	mat.scale_max = 0.05

	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.add_point(0.0, Color(crystal_color.r, crystal_color.g, crystal_color.b, 0.0))
	grad.add_point(0.3, Color(crystal_color.r, crystal_color.g, crystal_color.b, 0.7))
	grad.add_point(0.7, Color(crystal_color.r, crystal_color.g, crystal_color.b, 0.5))
	grad.add_point(1.0, Color(crystal_color.r, crystal_color.g, crystal_color.b, 0.0))
	color_ramp.gradient = grad
	mat.color_ramp = color_ramp

	_particles.process_material = mat

	# Small additive quad for sparkle
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = draw_mat
	_particles.draw_pass_1 = quad

	add_child(_particles)


func _create_interaction_area() -> void:
	_interaction_area = Area3D.new()
	_interaction_area.name = "InteractionArea"
	_interaction_area.collision_layer = 0
	_interaction_area.collision_mask = 2  # Player layer

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8 * crystal_size
	shape.shape = sphere
	_interaction_area.add_child(shape)
	add_child(_interaction_area)


# ── Interaction API ───────────────────────────────────────────────────────────

## Call this when the player interacts with or attacks the crystal.
func interact() -> void:
	if _collected or not _is_active:
		return

	match interaction_type:
		InteractionType.COLLECTIBLE:
			_collect()
		InteractionType.BREAKABLE:
			_break()
		InteractionType.ACTIVATABLE:
			_toggle()


func _collect() -> void:
	_collected = true
	crystal_collected.emit(self)
	_persist_state(true)

	# Collect animation — burst of particles then disappear
	if _particles:
		_particles.amount = 20
		_particles.one_shot = true
		_particles.explosiveness = 1.0
		_particles.restart()

	# Fade out
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func(): visible = false; set_process(false))


func _break() -> void:
	_collected = true
	crystal_broken.emit(self)
	_persist_state(true)

	# Shatter effect — bigger particle burst
	if _particles:
		_particles.amount = 30
		_particles.one_shot = true
		_particles.explosiveness = 1.0
		var pmat: ParticleProcessMaterial = _particles.process_material
		if pmat:
			pmat.initial_velocity_min = 1.0
			pmat.initial_velocity_max = 3.0
			pmat.gravity = Vector3(0, -4, 0)
		_particles.restart()

	# Flash then disappear
	if _light:
		var tween := create_tween()
		tween.tween_property(_light, "light_energy", _base_energy * 5.0, 0.1)
		tween.tween_property(_light, "light_energy", 0.0, 0.3)

	var tween2 := create_tween()
	tween2.tween_interval(0.1)
	tween2.tween_property(_sprite, "modulate:a", 0.0, 0.2)
	tween2.tween_callback(func(): visible = false; set_process(false))


func _toggle() -> void:
	_is_active = not _is_active
	crystal_activated.emit(self, _is_active)

	if _light:
		_light.visible = _is_active
	if _particles:
		_particles.emitting = _is_active

	# Visual feedback
	var target_mod := crystal_color if _is_active else Color(crystal_color * 0.2, 1.0)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", target_mod, 0.3)


func _persist_state(value: Variant) -> void:
	if cave_object_id.is_empty():
		return
	var cave_sys := _find_cave_system()
	if cave_sys:
		var cave_data: Node = get_node_or_null("/root/GlobalCaveData")
		if cave_data:
			cave_data.set_cave_flag(cave_sys.cave_id, cave_object_id, value)


func _find_cave_system() -> CaveSystem:
	var node := get_parent()
	while node:
		if node is CaveSystem:
			return node
		node = node.get_parent()
	return null


## Persistence hook — called by CaveSystem on load.
func restore_cave_state(cave_id: String) -> void:
	if cave_object_id.is_empty():
		return
	var cave_data: Node = get_node_or_null("/root/GlobalCaveData")
	if not cave_data:
		return
	var was_collected: bool = cave_data.get_cave_flag(cave_id, cave_object_id, false)
	if was_collected and interaction_type in [InteractionType.COLLECTIBLE, InteractionType.BREAKABLE]:
		_collected = true
		visible = false
		set_process(false)

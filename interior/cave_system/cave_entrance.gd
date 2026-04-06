## CaveEntrance — Overworld trigger that transitions the player into a cave scene.
##
## Place this as a child of your overworld scene. It creates a visual entrance
## (dark hole / rocky opening) and an Area3D trigger. When the player overlaps,
## a cinematic fade-to-black plays before switching to the target cave scene.
##
## Setup:
##   1. Attach this script to a Node3D in your overworld.
##   2. Set [member cave_scene_path] to the .tscn of your cave.
##   3. Position the node where the cave mouth should appear.
##   4. Sculpt a shallow depression in Terrain3D underneath for visual depth.
##   5. Optionally assign [member entrance_sprite] if you have custom art.

class_name CaveEntrance
extends Node3D

## Path to the cave scene that this entrance leads to.
@export_file("*.tscn") var cave_scene_path: String = ""

## Spawn point name inside the cave scene where the player appears.
@export var cave_spawn_id: String = "entrance_default"

## Radius of the interaction trigger area.
@export var trigger_radius: float = 1.5

## If true, requires player to press interact key instead of auto-enter.
@export var require_interaction: bool = false

## Optional custom entrance sprite. If null, a procedural dark circle is created.
@export var entrance_sprite: Texture2D = null

## Fade duration for the transition in seconds.
@export var fade_duration: float = 0.8

## Particle intensity for the ambient entrance atmosphere.
@export_range(0.0, 1.0) var atmosphere_intensity: float = 0.6

# ── Internal ──────────────────────────────────────────────────────────────────

var _player_inside: bool = false
var _transitioning: bool = false
var _fade_overlay: ColorRect
var _area: Area3D

@onready var _entrance_visual: Node3D = $EntranceVisual if has_node("EntranceVisual") else null


func _ready() -> void:
	_build_trigger_area()
	_build_entrance_visual()
	_build_ambient_particles()
	_build_fade_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if not require_interaction:
		return
	if _player_inside and not _transitioning:
		if event.is_action_pressed("interact"):
			_begin_transition()


# ── Construction ──────────────────────────────────────────────────────────────

func _build_trigger_area() -> void:
	_area = Area3D.new()
	_area.name = "CaveEntranceTrigger"
	_area.collision_layer = 0
	_area.collision_mask = 2  # Adjust to your player layer
	_area.monitoring = true

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = trigger_radius
	shape.shape = sphere
	_area.add_child(shape)

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	add_child(_area)


func _build_entrance_visual() -> void:
	if _entrance_visual:
		return  # User provided their own visual

	# Create a dark elliptical hole in the ground
	var visual := Node3D.new()
	visual.name = "EntranceVisual"

	# Dark ground circle — simulates the cave opening from above
	var hole_mesh := MeshInstance3D.new()
	hole_mesh.name = "HoleMesh"
	var quad := QuadMesh.new()
	quad.size = Vector2(trigger_radius * 2.2, trigger_radius * 1.8)
	hole_mesh.mesh = quad
	hole_mesh.rotation.x = -PI / 2.0  # Lay flat
	hole_mesh.position.y = 0.02  # Just above terrain to avoid z-fight

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.03, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hole_mesh.material_override = mat
	visual.add_child(hole_mesh)

	# Rocky edge sprites — place around the perimeter
	# (In production, replace with your pixel art rock border sprites)
	var edge_ring := _create_edge_ring(trigger_radius * 1.1, 12)
	visual.add_child(edge_ring)

	add_child(visual)
	_entrance_visual = visual


func _create_edge_ring(radius: float, count: int) -> Node3D:
	var ring := Node3D.new()
	ring.name = "EdgeRing"

	for i in count:
		var angle := (TAU / count) * i
		var rock := MeshInstance3D.new()
		var box := BoxMesh.new()
		var rock_size := randf_range(0.2, 0.45)
		box.size = Vector3(rock_size, rock_size * 0.6, rock_size * 0.8)
		rock.mesh = box

		var mat := StandardMaterial3D.new()
		var shade := randf_range(0.08, 0.18)
		mat.albedo_color = Color(shade, shade * 0.95, shade * 0.9)
		rock.material_override = mat

		rock.position = Vector3(
			cos(angle) * radius + randf_range(-0.1, 0.1),
			randf_range(0.0, 0.15),
			sin(angle) * radius + randf_range(-0.1, 0.1)
		)
		rock.rotation.y = randf() * TAU
		ring.add_child(rock)

	return ring


func _build_ambient_particles() -> void:
	if atmosphere_intensity <= 0.0:
		return

	# Dust / mist rising from the cave entrance
	var particles := GPUParticles3D.new()
	particles.name = "EntranceMist"
	particles.amount = int(24 * atmosphere_intensity)
	particles.lifetime = 3.0
	particles.explosiveness = 0.0
	particles.randomness = 0.4
	particles.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.initial_velocity_min = 0.15
	mat.initial_velocity_max = 0.4
	mat.gravity = Vector3(0, 0.05, 0)
	mat.spread = 25.0
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = trigger_radius * 0.8
	mat.scale_min = 0.3
	mat.scale_max = 0.8
	mat.color = Color(0.15, 0.15, 0.18, 0.3 * atmosphere_intensity)

	# Fade out over lifetime
	var color_ramp := GradientTexture1D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.2, 0.2, 0.22, 0.35))
	gradient.set_color(1, Color(0.1, 0.1, 0.12, 0.0))
	color_ramp.gradient = gradient
	mat.color_ramp = color_ramp

	particles.process_material = mat

	# Simple quad mesh for each particle
	var draw_mesh := QuadMesh.new()
	draw_mesh.size = Vector2(0.3, 0.3)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mesh.material = draw_mat
	particles.draw_pass_1 = draw_mesh

	add_child(particles)


func _build_fade_overlay() -> void:
	# We build a CanvasLayer + ColorRect for the fade transition.
	# This persists across scenes if added to an autoload, but for safety
	# we create it here and transfer it during transition.
	var canvas := CanvasLayer.new()
	canvas.name = "CaveTransitionCanvas"
	canvas.layer = 100  # On top of everything

	_fade_overlay = ColorRect.new()
	_fade_overlay.name = "FadeOverlay"
	_fade_overlay.color = Color(0, 0, 0, 0)
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	canvas.add_child(_fade_overlay)
	add_child(canvas)


# ── Transition Logic ──────────────────────────────────────────────────────────

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	if not require_interaction and not _transitioning:
		_begin_transition()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false


func _begin_transition() -> void:
	if _transitioning or cave_scene_path.is_empty():
		return
	_transitioning = true

	# Disable player input (assumes player has a method or property for this)
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)

	# Fade to black
	var tween := create_tween()
	tween.tween_property(_fade_overlay, "color:a", 1.0, fade_duration)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(_execute_scene_change)


func _execute_scene_change() -> void:
	# Store spawn info for the cave system to read
	var cave_data: Node = get_node_or_null("/root/GlobalCaveData")
	if cave_data:
		cave_data.pending_spawn_id = cave_spawn_id
		cave_data.return_position = global_position
		cave_data.return_scene_path = get_tree().current_scene.scene_file_path

	# Change scene
	get_tree().change_scene_to_file(cave_scene_path)

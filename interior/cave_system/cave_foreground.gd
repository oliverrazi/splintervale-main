## CaveForeground — Manages foreground rock elements that render over the player.
##
## In the reference screenshot, notice how rock formations in the bottom-left
## and bottom-right corners partially obscure the view. This creates a powerful
## sense of being INSIDE the cave, looking through a gap in the rocks.
##
## This system manages:
##   • Foreground rock sprites/meshes rendered above the player layer
##   • Opacity control — foreground fades when player walks behind it
##   • Camera-relative positioning (rocks stay at screen edges)
##   • Optional parallax offset for depth illusion
##   • Smooth fade transitions
##
## Architecture:
##   Foreground elements use a higher render layer or Y position
##   combined with transparency to overlay the game world.
##   Two modes: FIXED (world-space) and CAMERA-RELATIVE (screen-space feel).

class_name CaveForeground
extends Node3D

# ── Configuration ─────────────────────────────────────────────────────────────

@export_group("Behavior")
## How foreground elements are positioned.
enum ForegroundMode {
	FIXED,           ## World-space — rocks stay where placed (like the reference)
	CAMERA_RELATIVE, ## Moves with camera — always at screen edges
}
@export var mode: ForegroundMode = ForegroundMode.FIXED

## When player walks behind foreground, fade to this alpha.
@export_range(0.0, 1.0) var player_behind_alpha: float = 0.3
## Distance at which fade begins when player approaches foreground.
@export var fade_distance: float = 3.0
## Speed of the fade transition.
@export var fade_speed: float = 4.0

@export_group("Camera Relative (only for CAMERA_RELATIVE mode)")
## Offset from camera in local space.
@export var camera_offset: Vector3 = Vector3(0, 2, -3)
## How much foreground elements shift when camera moves (parallax).
@export_range(0.0, 1.0) var parallax_factor: float = 0.15

@export_group("Rendering")
## Y position offset — higher = renders more "on top" in 2.5D.
@export var render_height: float = 4.0
## Render priority for sorting (higher = drawn later = on top).
@export var render_priority: int = 20
## Apply a dark tint to foreground (silhouette effect).
@export var foreground_darkening: float = 0.7
## Base tint color.
@export var foreground_tint: Color = Color(0.08, 0.07, 0.06)

# ── Internal ──────────────────────────────────────────────────────────────────

var _foreground_pieces: Array[Dictionary] = []
# Each: { "node": Node3D, "mesh": MeshInstance3D/Sprite3D, "base_alpha": float,
#          "current_alpha": float, "world_pos": Vector3 }

var _player: Node3D
var _camera: Camera3D


func _ready() -> void:
	# Register any pre-placed children
	for child in get_children():
		if child is MeshInstance3D or child is Sprite3D:
			_register_foreground_piece(child)
		elif child is Node3D:
			# Check if it's a container with mesh children
			for subchild in child.get_children():
				if subchild is MeshInstance3D or subchild is Sprite3D:
					_register_foreground_piece(subchild)


func _process(delta: float) -> void:
	if not _player:
		_player = get_tree().get_first_node_in_group("player")
	if not _camera:
		_camera = get_viewport().get_camera_3d()

	if mode == ForegroundMode.CAMERA_RELATIVE and _camera:
		_update_camera_relative()

	if _player:
		_update_player_proximity_fade(delta)


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — Adding Foreground Elements
# ═══════════════════════════════════════════════════════════════════════════════

## Add a Sprite3D foreground rock at the given position.
## [param texture] is your pixel art rock silhouette (with alpha).
## [param pos] is the world XZ position; Y is set automatically.
func add_foreground_sprite(texture: Texture2D, pos: Vector3,
		scale: float = 1.0, flip_h: bool = false) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = 0.01
	sprite.position = Vector3(pos.x, render_height, pos.z)
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.render_priority = render_priority
	sprite.flip_h = flip_h
	sprite.scale = Vector3.ONE * scale

	# Dark silhouette tint
	sprite.modulate = Color(foreground_tint.r, foreground_tint.g, foreground_tint.b, 1.0)
	sprite.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	add_child(sprite)
	_register_foreground_piece(sprite)
	return sprite


## Add a MeshInstance3D foreground rock.
## [param mesh] is a rock mesh (same as used in CaveRockGeometry).
## These will be darkened/silhouetted automatically.
func add_foreground_mesh(mesh: Mesh, pos: Vector3,
		rotation_y: float = 0.0, scale: float = 1.5) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.position = Vector3(pos.x, render_height, pos.z)
	mesh_inst.rotation.y = rotation_y
	mesh_inst.scale = Vector3.ONE * scale

	# Apply dark foreground material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = foreground_tint
	mat.roughness = 0.95
	mat.metallic = 0.0
	# Make it very dark — these are silhouettes
	mat.emission_enabled = false
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(mesh_inst)
	_register_foreground_piece(mesh_inst)
	return mesh_inst


## Add a foreground frame — rocks around the screen edges.
## This creates the "looking through a cave opening" effect from the reference.
## [param textures] dictionary with keys: "bottom_left", "bottom_right",
## "top_left", "top_right" (all optional). Values are Texture2D.
func add_foreground_frame(textures: Dictionary, offsets: Dictionary = {}) -> void:
	var default_offsets := {
		"bottom_left": Vector3(-6, 0, 4),
		"bottom_right": Vector3(6, 0, 4),
		"top_left": Vector3(-5, 0, -4),
		"top_right": Vector3(5, 0, -4),
	}

	for key in textures:
		if textures[key] is Texture2D:
			var offset: Vector3 = offsets.get(key, default_offsets.get(key, Vector3.ZERO))
			var flip : float = key.contains("right")
			add_foreground_sprite(textures[key], offset, 1.5, flip)


## Add procedural foreground rocks (for prototyping without textures).
## Creates dark box-like shapes at the cave edges.
func add_procedural_frame(cave_bounds: AABB) -> void:
	var positions := [
		# Bottom-left cluster
		Vector3(cave_bounds.position.x - 1.0, 0, cave_bounds.end.z + 1.0),
		Vector3(cave_bounds.position.x + 0.5, 0, cave_bounds.end.z + 0.5),
		Vector3(cave_bounds.position.x - 0.5, 0, cave_bounds.end.z + 1.5),
		# Bottom-right cluster
		Vector3(cave_bounds.end.x + 1.0, 0, cave_bounds.end.z + 1.0),
		Vector3(cave_bounds.end.x - 0.5, 0, cave_bounds.end.z + 0.5),
		Vector3(cave_bounds.end.x + 0.5, 0, cave_bounds.end.z + 1.5),
		# Top edges (lighter presence)
		Vector3(cave_bounds.position.x, 0, cave_bounds.position.z - 0.5),
		Vector3(cave_bounds.end.x, 0, cave_bounds.position.z - 0.5),
	]

	for i in positions.size():
		var mesh := BoxMesh.new()
		var s := randf_range(1.0, 2.5)
		mesh.size = Vector3(s, s * randf_range(0.8, 1.5), s * randf_range(0.6, 1.2))
		var rot := randf() * TAU
		add_foreground_mesh(mesh, positions[i], rot, randf_range(1.0, 1.8))


# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL — Registration & Updates
# ═══════════════════════════════════════════════════════════════════════════════

func _register_foreground_piece(node: Node) -> void:
	var entry := {
		"node": node,
		"base_alpha": 1.0,
		"current_alpha": 1.0,
		"world_pos": node.global_position,
	}

	# Ensure correct render height
	if node is Node3D:
		node.position.y = render_height

	# Apply render priority
	if node is Sprite3D:
		node.render_priority = render_priority
	elif node is MeshInstance3D:
		# MeshInstance doesn't have render_priority directly,
		# but the high Y position handles sorting in 2.5D.
		pass

	_foreground_pieces.append(entry)


func _update_camera_relative() -> void:
	if not _camera:
		return

	# In camera-relative mode, foreground moves with camera
	# but with parallax offset
	var cam_pos := _camera.global_position
	var target_pos := cam_pos + camera_offset

	# Apply parallax — foreground shifts slightly less than camera
	global_position = global_position.lerp(target_pos, 1.0 - parallax_factor)


func _update_player_proximity_fade(delta: float) -> void:
	## When the player walks near/behind foreground elements, fade them
	## so the player remains visible. This is critical for playability.
	if not _player:
		return

	var player_pos := _player.global_position

	for entry in _foreground_pieces:
		var node: Node3D = entry["node"]
		if not is_instance_valid(node):
			continue

		# Calculate XZ distance (ignore Y — foreground is above)
		var node_pos := node.global_position
		var dist := Vector2(player_pos.x - node_pos.x, player_pos.z - node_pos.z).length()

		# Target alpha based on distance
		var target_alpha: float
		if dist < fade_distance:
			var t := dist / fade_distance  # 0 = on top, 1 = at fade edge
			target_alpha = lerpf(player_behind_alpha, 1.0, t)
		else:
			target_alpha = 1.0

		# Smooth transition
		entry["current_alpha"] = lerpf(entry["current_alpha"], target_alpha, delta * fade_speed)

		# Apply alpha
		_apply_alpha(node, entry["current_alpha"])


func _apply_alpha(node: Node, alpha: float) -> void:
	if node is Sprite3D:
		node.modulate.a = alpha
	elif node is MeshInstance3D:
		var mat: Material = node.material_override
		if mat is StandardMaterial3D:
			if alpha < 0.99:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			else:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mat.albedo_color.a = alpha
		elif mat is ShaderMaterial:
			mat.set_shader_parameter("opacity", alpha)


# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY
# ═══════════════════════════════════════════════════════════════════════════════

## Set the darkness level of all foreground elements.
func set_foreground_darkness(darkness: float) -> void:
	foreground_darkening = clamp(darkness, 0.0, 1.0)
	var tint_val := 1.0 - foreground_darkening
	foreground_tint = Color(tint_val * 0.12, tint_val * 0.11, tint_val * 0.1)

	for entry in _foreground_pieces:
		var node = entry["node"]
		if node is Sprite3D:
			node.modulate = Color(foreground_tint.r, foreground_tint.g, foreground_tint.b, node.modulate.a)
		elif node is MeshInstance3D and node.material_override is StandardMaterial3D:
			node.material_override.albedo_color = Color(foreground_tint.r, foreground_tint.g, foreground_tint.b,
				node.material_override.albedo_color.a)


## Force all foreground to full visibility.
func show_all() -> void:
	for entry in _foreground_pieces:
		entry["current_alpha"] = 1.0
		_apply_alpha(entry["node"], 1.0)


## Force all foreground to faded state.
func fade_all() -> void:
	for entry in _foreground_pieces:
		entry["current_alpha"] = player_behind_alpha
		_apply_alpha(entry["node"], player_behind_alpha)

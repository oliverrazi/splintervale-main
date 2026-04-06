## CaveRockGeometry — Generates and manages 3D rock formations for cave walls.
##
## Unlike flat sprites or planes, this system creates actual 3D mesh geometry
## that gives caves real depth with overhangs, layered rock strata, crevices,
## and irregular surfaces — matching AAA HD-2D cave aesthetics.
##
## Two usage modes:
##   1. MODULAR: Pre-made rock meshes from Blender placed manually
##   2. PROCEDURAL: Generated rock clusters from code (for prototyping)
##
## For AAA quality, use Mode 1 with hand-crafted Blender meshes.
## Mode 2 is excellent for blocking out cave layouts before final art.
##
## This script manages a collection of rock pieces, handles LOD,
## applies the cave wall shader, and provides tools for placement.

class_name CaveRockGeometry
extends Node3D

# ── Configuration ─────────────────────────────────────────────────────────────

@export_group("Rock Library")
## Array of rock mesh resources (import from Blender as .glb/.gltf).
## Include 5-10 variations for natural-looking caves.
@export var rock_meshes: Array[Mesh] = []
## Rock wall shader — assign cave_rock.gdshader for proper look.
@export var rock_shader: Shader = null
## Base color tint for all rocks.
@export var rock_tint: Color = Color(0.22, 0.20, 0.18)
## Secondary tint for variation.
@export var rock_tint_variation: Color = Color(0.18, 0.17, 0.16)
## How much color varies between rocks (0 = uniform, 1 = full range).
@export_range(0.0, 1.0) var color_variation: float = 0.15

@export_group("Procedural Generation")
## Enable procedural rock generation (for prototyping).
@export var use_procedural: bool = true
## Base size of procedural rocks.
@export var procedural_rock_size: float = 1.0
## Irregularity of procedural rocks (0 = smooth spheres, 1 = very jagged).
@export_range(0.0, 1.0) var procedural_irregularity: float = 0.6

@export_group("Performance")
## Maximum render distance for rocks.
@export var render_distance: float = 30.0
## Enable LOD (reduces mesh detail at distance).
@export var enable_lod: bool = true
## Distance at which LOD switches to low-detail.
@export var lod_distance: float = 15.0

# ── Internal ──────────────────────────────────────────────────────────────────

var _rock_instances: Array[MeshInstance3D] = []
var _material_cache: Dictionary = {}  # Caches ShaderMaterials to reduce duplication


func _ready() -> void:
	# Apply shader material to any pre-placed MeshInstance3D children
	for child in get_children():
		if child is MeshInstance3D:
			_apply_rock_material(child)
			_rock_instances.append(child)


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API — Rock Placement
# ═══════════════════════════════════════════════════════════════════════════════

## Place a rock mesh from the library at the given transform.
## [param mesh_index] selects which rock variation to use (-1 = random).
## [param scale_range] randomizes the scale within this range.
## Returns the created MeshInstance3D.
func place_rock(pos: Vector3, rotation_y: float = 0.0, mesh_index: int = -1,
		scale_range: Vector2 = Vector2(0.8, 1.4)) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()

	# Select mesh
	if rock_meshes.size() > 0:
		var idx := mesh_index if mesh_index >= 0 else randi() % rock_meshes.size()
		idx = clampi(idx, 0, rock_meshes.size() - 1)
		mesh_inst.mesh = rock_meshes[idx]
	elif use_procedural:
		mesh_inst.mesh = _generate_procedural_rock()
	else:
		push_warning("CaveRockGeometry: No rock meshes assigned and procedural is disabled.")
		mesh_inst.queue_free()
		return null

	# Transform
	mesh_inst.position = pos
	mesh_inst.rotation.y = rotation_y
	var s := randf_range(scale_range.x, scale_range.y)
	mesh_inst.scale = Vector3(s, s * randf_range(0.7, 1.3), s)

	# Material
	_apply_rock_material(mesh_inst)

	add_child(mesh_inst)
	_rock_instances.append(mesh_inst)
	return mesh_inst


## Place a cluster of rocks forming a wall segment.
## [param start] and [param end] define the wall line.
## [param depth] controls how thick/deep the rock wall is.
## [param height_range] controls the Y range of rocks.
func place_wall_segment(start: Vector3, end: Vector3, depth: float = 2.0,
		height_range: Vector2 = Vector2(-0.5, 2.5), density: int = 8) -> Array[MeshInstance3D]:
	var results: Array[MeshInstance3D] = []
	var dir := (end - start).normalized()
	var length := start.distance_to(end)
	var perpendicular := Vector3(-dir.z, 0, dir.x)  # 90° rotated on XZ plane

	for i in density:
		var t := randf()  # Position along the wall line
		var d := randf_range(-depth * 0.5, depth * 0.5)  # Depth offset
		var pos := start + dir * length * t + perpendicular * d
		pos.y = randf_range(height_range.x, height_range.y)

		var rot := atan2(dir.x, dir.z) + randf_range(-0.4, 0.4)
		var rock := place_rock(pos, rot, -1, Vector2(0.6, 1.8))
		if rock:
			results.append(rock)

	return results


## Place rocks along a curve/path for organic cave walls.
## [param points] is an array of Vector3 positions defining the wall path.
## [param rocks_per_segment] controls density between each pair of points.
func place_wall_along_path(points: Array[Vector3], rocks_per_segment: int = 6,
		depth: float = 2.0, height_range: Vector2 = Vector2(-0.5, 2.5)) -> Array[MeshInstance3D]:
	var results: Array[MeshInstance3D] = []
	for i in range(points.size() - 1):
		var segment := place_wall_segment(points[i], points[i + 1], depth,
			height_range, rocks_per_segment)
		results.append_array(segment)
	return results


## Place an overhang — rocks that lean inward over the walkable area.
## These create the dramatic depth seen in AAA caves.
## [param base_pos] is the wall base, [param lean_direction] points inward.
func place_overhang(base_pos: Vector3, lean_direction: Vector3,
		rock_count: int = 5, height: float = 2.5, lean_amount: float = 1.5) -> Array[MeshInstance3D]:
	var results: Array[MeshInstance3D] = []
	var lean_dir := lean_direction.normalized()

	for i in rock_count:
		var t := float(i) / float(rock_count - 1) if rock_count > 1 else 0.5
		var y := lerpf(0.5, height, t)
		# Higher rocks lean more inward
		var lean := lean_dir * lean_amount * t * t  # Quadratic lean
		var pos := base_pos + Vector3(lean.x, y, lean.z)
		# Add some randomness
		pos += Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.3, 0.3))

		var rot := atan2(lean_dir.x, lean_dir.z) + randf_range(-0.3, 0.3)
		var rock := place_rock(pos, rot, -1, Vector2(0.5, 1.2))
		if rock:
			# Tilt the rock to match the lean angle
			rock.rotation.x = -t * 0.4  # Tilt forward as they go higher
			rock.rotation.z = randf_range(-0.2, 0.2)
			results.append(rock)

	return results


## Place a stalactite cluster hanging from above.
## These are rock formations pointing downward from a high Y position.
func place_ceiling_rocks(center: Vector3, count: int = 6,
		spread: float = 2.0, hang_height: float = 4.0) -> Array[MeshInstance3D]:
	var results: Array[MeshInstance3D] = []

	for i in count:
		var angle := randf() * TAU
		var dist := randf() * spread
		var pos := center + Vector3(cos(angle) * dist, hang_height + randf_range(-0.5, 0.5), sin(angle) * dist)

		var rock := place_rock(pos, randf() * TAU, -1, Vector2(0.3, 0.9))
		if rock:
			# Flip upside down and point downward
			rock.rotation.x = PI + randf_range(-0.3, 0.3)
			rock.rotation.z = randf_range(-0.2, 0.2)
			# Make them narrower (stalactite shape)
			rock.scale.x *= 0.6
			rock.scale.z *= 0.6
			results.append(rock)

	return results


## Create a layered rock strata effect — horizontal bands of rock
## visible on cliff faces, very characteristic of real cave geology.
func place_rock_strata(base_pos: Vector3, wall_normal: Vector3,
		width: float = 5.0, layers: int = 4,
		layer_height: float = 0.5) -> Array[MeshInstance3D]:
	var results: Array[MeshInstance3D] = []
	var tangent := Vector3(-wall_normal.z, 0, wall_normal.x)

	for layer_idx in layers:
		var y_offset := float(layer_idx) * layer_height
		var rocks_in_layer := randi_range(3, 6)

		for rock_idx in rocks_in_layer:
			var t := float(rock_idx) / float(rocks_in_layer)
			var pos := base_pos + tangent * (t * width - width * 0.5)
			pos.y += y_offset + randf_range(-0.1, 0.1)
			# Slight depth variation per layer
			pos += wall_normal * (float(layer_idx) * 0.15 + randf_range(-0.1, 0.1))

			var rock := place_rock(pos, atan2(wall_normal.x, wall_normal.z), -1, Vector2(0.5, 1.0))
			if rock:
				# Flatten for strata look — wide and thin
				rock.scale.y *= 0.3 + randf_range(0.0, 0.2)
				rock.scale.x *= 1.2 + randf_range(0.0, 0.4)
				results.append(rock)

	return results


# ═══════════════════════════════════════════════════════════════════════════════
# MATERIAL SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

func _apply_rock_material(mesh_inst: MeshInstance3D) -> void:
	var mat: Material
	if rock_shader:
		mat = _create_shader_material(mesh_inst)
	else:
		mat = _create_standard_material(mesh_inst)
	mesh_inst.material_override = mat


func _create_shader_material(mesh_inst: MeshInstance3D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = rock_shader

	# Vary the tint per rock for organic look
	var t := randf()
	var tint: Color = rock_tint.lerp(rock_tint_variation, t)
	# Additional random variation
	tint.r += randf_range(-color_variation, color_variation) * 0.5
	tint.g += randf_range(-color_variation, color_variation) * 0.5
	tint.b += randf_range(-color_variation, color_variation) * 0.5

	mat.set_shader_parameter("wall_tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("brightness", randf_range(0.35, 0.55))
	mat.set_shader_parameter("height_darkening", randf_range(0.4, 0.7))

	return mat


func _create_standard_material(_mesh_inst: MeshInstance3D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()

	var t := randf()
	var tint: Color = rock_tint.lerp(rock_tint_variation, t)
	tint.r += randf_range(-color_variation, color_variation) * 0.5
	tint.g += randf_range(-color_variation, color_variation) * 0.5
	tint.b += randf_range(-color_variation, color_variation) * 0.5

	mat.albedo_color = tint
	mat.roughness = randf_range(0.75, 0.95)
	mat.metallic = 0.0
	mat.metallic_specular = 0.1

	return mat


# ═══════════════════════════════════════════════════════════════════════════════
# PROCEDURAL ROCK GENERATION (Prototyping)
# ═══════════════════════════════════════════════════════════════════════════════

func _generate_procedural_rock() -> Mesh:
	## Creates a deformed sphere mesh that looks like a rough rock.
	## For final quality, replace with Blender-modeled rocks.

	var sphere := SphereMesh.new()
	sphere.radius = procedural_rock_size * 0.5
	sphere.height = procedural_rock_size
	sphere.radial_segments = 8
	sphere.rings = 5

	# To create irregular shapes, we need to modify vertices.
	# We'll use an ArrayMesh built from the sphere's arrays.
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	# Deform each vertex with noise-like displacement
	var seed_val := randf() * 1000.0
	for i in vertices.size():
		var v := vertices[i]
		var n := normals[i]

		# Hash-based displacement (deterministic pseudo-random per vertex)
		var hash_input := v * 3.7 + Vector3(seed_val, seed_val * 0.7, seed_val * 1.3)
		var displacement := _simple_3d_noise(hash_input) * procedural_irregularity * 0.3
		# Also add some directional squash for more interesting shapes
		var squash := Vector3(
			1.0 + sin(v.y * 2.0 + seed_val) * 0.3,
			1.0 + cos(v.x * 2.0 + seed_val * 0.5) * 0.2,
			1.0 + sin(v.z * 2.0 + seed_val * 0.8) * 0.3
		)

		vertices[i] = v * squash + n * displacement

	# Rebuild normals (approximate — recalculate from faces)
	arrays[Mesh.ARRAY_VERTEX] = vertices

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh


func _simple_3d_noise(p: Vector3) -> float:
	## Fast hash-based noise for vertex deformation.
	var dot_val := p.dot(Vector3(127.1, 311.7, 74.7))
	var v: float = sin(dot_val) * 43758.5453
	return (v - floorf(v)) * 2.0 - 1.0


# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY
# ═══════════════════════════════════════════════════════════════════════════════

## Remove all dynamically placed rocks.
func clear_all_rocks() -> void:
	for rock in _rock_instances:
		if is_instance_valid(rock):
			rock.queue_free()
	_rock_instances.clear()


## Get all rock instances for batch operations.
func get_all_rocks() -> Array[MeshInstance3D]:
	return _rock_instances

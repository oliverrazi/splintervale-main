@tool
extends Node3D
class_name GrassSystemBkp

@export var grass_texture: Texture2D:
	set(v):
		if grass_texture == v:
			return
		grass_texture = v
		if _material:
			_material.set_shader_parameter("grass_texture", v)

@export var density: float = 50.0
@export var grass_scale := Vector2(0.02, 0.2)
@export var scale_variation := 0.5
@export var color_variation := 1.0

@export_group("Shape")
@export var shape_points: PackedVector2Array = PackedVector2Array([
	Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)
]):
	set(v):
		if shape_points == v:
			return
		shape_points = v
		if Engine.is_editor_hint():
			_update_debug_visuals()

@export_group("Wind")
@export var wind_strength := 0.3:
	set(v):
		if wind_strength == v:
			return
		wind_strength = v
		if _material:
			_material.set_shader_parameter("wind_strength", v)
@export var wind_speed := 1.5:
	set(v):
		if wind_speed == v:
			return
		wind_speed = v
		if _material:
			_material.set_shader_parameter("wind_speed", v)
## Size of wind waves – smaller = larger gusts
@export var wind_scale := 0.1:
	set(v):
		if wind_scale == v:
			return
		wind_scale = v
		if _material:
			_material.set_shader_parameter("wind_scale", v)
## Main wind direction (X, Z)
@export var wind_direction := Vector2(1.0, 0.3):
	set(v):
		if wind_direction == v:
			return
		wind_direction = v
		if _material:
			_material.set_shader_parameter("wind_direction", v)

@export_group("LOD")
@export var lod_fade_start := 30.0:
	set(v):
		if lod_fade_start == v:
			return
		lod_fade_start = v
		if _material:
			_material.set_shader_parameter("lod_fade_start", v)
@export var lod_fade_end := 50.0:
	set(v):
		if lod_fade_end == v:
			return
		lod_fade_end = v
		if _material:
			_material.set_shader_parameter("lod_fade_end", v)

@export_group("Sorting")
@export var depth_bias_strength := 0.02:
	set(v):
		if depth_bias_strength == v:
			return
		depth_bias_strength = v
		if _material:
			_material.set_shader_parameter("depth_bias_strength", v)

@export_group("Noise Coloring")
## Blend between base green and a warm yellow tone using noise
@export var noise_color_strength := 0.5:
	set(v):
		if noise_color_strength == v:
			return
		noise_color_strength = v
		if Engine.is_editor_hint():
			_mark_dirty()
## Scale of the noise pattern – smaller = larger patches
@export var noise_frequency := 0.15:
	set(v):
		if noise_frequency == v:
			return
		noise_frequency = v
		if Engine.is_editor_hint():
			_mark_dirty()
## The warm/yellow tint color at full noise influence
@export var noise_color_warm := Color(1.15, 1.1, 0.7, 1.0):
	set(v):
		if noise_color_warm == v:
			return
		noise_color_warm = v
		if Engine.is_editor_hint():
			_mark_dirty()
## The rich green tint at zero noise influence
@export var noise_color_cool := Color(0.85, 1.05, 0.8, 1.0):
	set(v):
		if noise_color_cool == v:
			return
		noise_color_cool = v
		if Engine.is_editor_hint():
			_mark_dirty()
@export var noise_seed := 42:
	set(v):
		if noise_seed == v:
			return
		noise_seed = v
		if Engine.is_editor_hint():
			_mark_dirty()

@export_group("Edge Falloff")
## How far from the polygon edge the height reduction begins (in world units)
@export var edge_falloff_distance := 2.0:
	set(v):
		if edge_falloff_distance == v:
			return
		edge_falloff_distance = v
		if Engine.is_editor_hint():
			_mark_dirty()
## Minimum height multiplier at the very edge (0 = flat, 1 = no effect)
@export var edge_min_height := 0.2:
	set(v):
		if edge_min_height == v:
			return
		edge_min_height = v
		if Engine.is_editor_hint():
			_mark_dirty()
## Easing curve for the falloff (1 = linear, <1 = fast start, >1 = slow start)
@export var edge_falloff_curve := 1.5:
	set(v):
		if edge_falloff_curve == v:
			return
		edge_falloff_curve = v
		if Engine.is_editor_hint():
			_mark_dirty()

@export_group("Async Loading")
## Distance from camera below which grass loads immediately (sync)
@export var async_load_distance := 40.0
## Force synchronous loading regardless of distance
@export var force_sync := false

@export_group("Debug")
@export var show_shape_outline := true:
	set(v):
		if show_shape_outline == v:
			return
		show_shape_outline = v
		_update_debug_visuals()
@export var regenerate := false:
	set(v):
		if v:
			call_deferred("_generate_grass")

var _multimesh_instance: MultiMeshInstance3D
var _material: ShaderMaterial
var _debug_mesh: MeshInstance3D
var _dirty := false
var _task_id: int = -1
var _generation_id: int = 0  # Incremented on each generation to discard stale results

func _ready() -> void:
	_setup_material()

	if Engine.is_editor_hint() or force_sync:
		_generate_grass()
	else:
		var cam := get_viewport().get_camera_3d() if get_viewport() else null
		var dist := INF
		if cam:
			dist = global_position.distance_to(cam.global_position)

		if dist <= async_load_distance:
			_generate_grass()
		else:
			_generate_grass_async()

	if Engine.is_editor_hint():
		_update_debug_visuals()

func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1

func _mark_dirty() -> void:
	if not _dirty:
		_dirty = true
		call_deferred("_flush_dirty")

func _flush_dirty() -> void:
	if _dirty:
		_dirty = false
		_generate_grass()

func _setup_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://assets/base_tiles/grass/billboard/billboard_shader.gdshader")
	if grass_texture:
		_material.set_shader_parameter("grass_texture", grass_texture)
	_material.set_shader_parameter("wind_strength", wind_strength)
	_material.set_shader_parameter("wind_speed", wind_speed)
	_material.set_shader_parameter("wind_scale", wind_scale)
	_material.set_shader_parameter("wind_direction", wind_direction)
	_material.set_shader_parameter("lod_fade_start", lod_fade_start)
	_material.set_shader_parameter("lod_fade_end", lod_fade_end)
	_material.set_shader_parameter("depth_bias_strength", depth_bias_strength)

# ============================================================
#  SYNC GENERATION (editor + nearby grass)
# ============================================================

func _generate_grass() -> void:
	# Cancel any pending async task by bumping generation ID
	_generation_id += 1

	if _multimesh_instance:
		_multimesh_instance.queue_free()
		_multimesh_instance = null

	var params := _snapshot_params()
	var result := _compute_grass_data(params)
	if result.is_empty():
		return
	_apply_grass_result(result)

# ============================================================
#  ASYNC GENERATION (distant grass — no main thread stall)
# ============================================================

func _generate_grass_async() -> void:
	_generation_id += 1

	if _multimesh_instance:
		_multimesh_instance.queue_free()
		_multimesh_instance = null

	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1

	var params := _snapshot_params()
	var gen_id := _generation_id
	_task_id = WorkerThreadPool.add_task(
		func() -> void:
			var result := _compute_grass_data(params)
			call_deferred("_on_async_complete", result, gen_id)
	)

func _on_async_complete(result: Dictionary, gen_id: int) -> void:
	_task_id = -1

	# Stale result — a newer generation was triggered in the meantime
	if gen_id != _generation_id:
		return
	# Node was removed from tree while thread was running
	if not is_inside_tree():
		return

	if _multimesh_instance:
		_multimesh_instance.queue_free()
		_multimesh_instance = null

	if result.is_empty():
		return
	_apply_grass_result(result)

# ============================================================
#  SNAPSHOT — captures all params for thread-safe computation
# ============================================================

func _snapshot_params() -> Dictionary:
	return {
		"shape_points": shape_points.duplicate(),
		"density": density,
		"global_position": global_position,
		"grass_scale": grass_scale,
		"scale_variation": scale_variation,
		"color_variation": color_variation,
		"edge_falloff_distance": edge_falloff_distance,
		"edge_min_height": edge_min_height,
		"edge_falloff_curve": edge_falloff_curve,
		"noise_color_strength": noise_color_strength,
		"noise_color_cool": noise_color_cool,
		"noise_color_warm": noise_color_warm,
		"noise_frequency": noise_frequency,
		"noise_seed": noise_seed,
	}

# ============================================================
#  PURE COMPUTATION — fully thread-safe, no scene tree access
# ============================================================

func _compute_grass_data(p: Dictionary) -> Dictionary:
	var sp: PackedVector2Array = p["shape_points"]
	if sp.size() < 3:
		return {}

	var gp: Vector3 = p["global_position"]
	var dens: float = p["density"]
	var gs: Vector2 = p["grass_scale"]
	var sv: float = p["scale_variation"]
	var cv: float = p["color_variation"]
	var efd: float = p["edge_falloff_distance"]
	var emh: float = p["edge_min_height"]
	var efc: float = p["edge_falloff_curve"]
	var ncs: float = p["noise_color_strength"]
	var ncc: Color = p["noise_color_cool"]
	var ncw: Color = p["noise_color_warm"]

	# --- Generate positions ---
	var positions := _generate_points_in_polygon_static(sp, dens, gp)
	if positions.is_empty():
		return {}

	# --- Bake distance field if needed ---
	var use_edge_falloff := efd > 0.0
	var df_grid := PackedFloat32Array()
	var df_min := Vector2.ZERO
	var df_cell_size := 0.5
	var df_res_x := 0
	var df_res_y := 0

	if use_edge_falloff:
		var df := _bake_distance_field_static(sp, efd, df_cell_size)
		df_grid = df["grid"]
		df_min = df["min"]
		df_res_x = df["res_x"]
		df_res_y = df["res_y"]

	# --- Create noise sampler (thread-local instance) ---
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = p["noise_frequency"]
	noise.seed = p["noise_seed"]

	# --- Build MultiMesh ---
	var instance_count := positions.size()

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _create_quad_mesh()
	multimesh.instance_count = instance_count

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(gp)

	for i in instance_count:
		var local_pos: Vector3 = positions[i]

		var scale_factor := 1.0 + rng.randf_range(-sv, sv)
		var color_offset := rng.randf_range(-cv, cv)
		var random_phase := rng.randf() * TAU

		# --- Edge falloff via distance field lookup ---
		var edge_factor := 1.0
		if use_edge_falloff:
			var edge_dist := _sample_df(
				Vector2(local_pos.x, local_pos.z),
				df_grid, df_min, df_cell_size, df_res_x, df_res_y
			)
			if edge_dist < efd:
				var t := edge_dist / efd
				t = pow(t, efc)
				edge_factor = emh + (1.0 - emh) * t

		# --- Noise-based color tinting ---
		var world_x := local_pos.x + gp.x
		var world_z := local_pos.z + gp.z
		var noise_val := (noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5

		var blend := noise_val * ncs
		var nr := ncc.r + (ncw.r - ncc.r) * blend
		var ng := ncc.g + (ncw.g - ncc.g) * blend
		var nb := ncc.b + (ncw.b - ncc.b) * blend

		var final_color := Color(
			(1.0 + color_offset) * nr,
			(1.0 + color_offset * 0.5) * ng,
			nb,
			1.0
		)

		var sx := gs.x * scale_factor
		var sy := gs.y * scale_factor * edge_factor

		multimesh.set_instance_transform(i, Transform3D(
			Vector3(sx, 0, 0),
			Vector3(0, sy, 0),
			Vector3(0, 0, 1),
			local_pos
		))
		multimesh.set_instance_color(i, final_color)
		multimesh.set_instance_custom_data(i, Color(random_phase, 0, 0, 0))

	return { "multimesh": multimesh, "count": instance_count }

# ============================================================
#  APPLY — main thread only, adds node to scene tree
# ============================================================

func _apply_grass_result(result: Dictionary) -> void:
	var multimesh: MultiMesh = result["multimesh"]
	var count: int = result["count"]

	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = multimesh
	_multimesh_instance.material_override = _material
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_multimesh_instance)

	print("GrassSystem: ", count, " instances generated")

# ============================================================
#  STATIC HELPERS — no instance state, fully thread-safe
# ============================================================

static func _generate_points_in_polygon_static(
	sp: PackedVector2Array, dens: float, gp: Vector3
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if sp.size() < 3:
		return points

	var min_p := sp[0]
	var max_p := sp[0]
	for p in sp:
		min_p = min_p.min(p)
		max_p = max_p.max(p)

	var area := _polygon_area_static(sp)
	var point_count := int(area * dens)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(gp) + hash(sp.size())

	var attempts := 0
	var max_attempts := point_count * 10

	while points.size() < point_count and attempts < max_attempts:
		attempts += 1
		var test_point := Vector2(
			rng.randf_range(min_p.x, max_p.x),
			rng.randf_range(min_p.y, max_p.y)
		)
		if Geometry2D.is_point_in_polygon(test_point, sp):
			points.append(Vector3(test_point.x, 0, test_point.y))

	return points

static func _polygon_area_static(polygon: PackedVector2Array) -> float:
	var area := 0.0
	var n := polygon.size()
	for i in n:
		var j := (i + 1) % n
		area += polygon[i].x * polygon[j].y
		area -= polygon[j].x * polygon[i].y
	return abs(area) / 2.0

static func _bake_distance_field_static(
	sp: PackedVector2Array, efd: float, cell_size: float
) -> Dictionary:
	var min_p := sp[0]
	var max_p := sp[0]
	for p in sp:
		min_p = min_p.min(p)
		max_p = max_p.max(p)

	var pad := efd + 1.0
	min_p -= Vector2(pad, pad)
	max_p += Vector2(pad, pad)

	var res_x := int(ceil((max_p.x - min_p.x) / cell_size)) + 1
	var res_y := int(ceil((max_p.y - min_p.y) / cell_size)) + 1

	var edge_count := sp.size()
	var ax := PackedFloat32Array()
	var ay := PackedFloat32Array()
	var abx := PackedFloat32Array()
	var aby := PackedFloat32Array()
	var ab_len_sq := PackedFloat32Array()
	ax.resize(edge_count)
	ay.resize(edge_count)
	abx.resize(edge_count)
	aby.resize(edge_count)
	ab_len_sq.resize(edge_count)

	for i in edge_count:
		var j := (i + 1) % edge_count
		var sa := sp[i]
		var sb := sp[j]
		ax[i] = sa.x
		ay[i] = sa.y
		var dx := sb.x - sa.x
		var dy := sb.y - sa.y
		abx[i] = dx
		aby[i] = dy
		ab_len_sq[i] = dx * dx + dy * dy

	var total := res_x * res_y
	var grid := PackedFloat32Array()
	grid.resize(total)

	for gy in res_y:
		var py := min_p.y + gy * cell_size
		for gx in res_x:
			var px := min_p.x + gx * cell_size
			var min_dist := 1e18

			for e in edge_count:
				var apx := px - ax[e]
				var apy := py - ay[e]
				var lsq := ab_len_sq[e]
				var t: float
				if lsq < 0.0001:
					t = 0.0
				else:
					t = clampf((apx * abx[e] + apy * aby[e]) / lsq, 0.0, 1.0)
				var cx := ax[e] + abx[e] * t - px
				var cy := ay[e] + aby[e] * t - py
				var d := cx * cx + cy * cy
				if d < min_dist:
					min_dist = d

			grid[gy * res_x + gx] = sqrt(min_dist)

	return { "grid": grid, "min": min_p, "res_x": res_x, "res_y": res_y }

static func _sample_df(
	point: Vector2,
	grid: PackedFloat32Array, grid_min: Vector2,
	cell_size: float, res_x: int, res_y: int
) -> float:
	var fx := (point.x - grid_min.x) / cell_size
	var fy := (point.y - grid_min.y) / cell_size

	var ix := int(fx)
	var iy := int(fy)

	if ix < 0:
		ix = 0
		fx = 0.0
	elif ix >= res_x - 1:
		ix = res_x - 2
		fx = float(ix) + 1.0
	if iy < 0:
		iy = 0
		fy = 0.0
	elif iy >= res_y - 1:
		iy = res_y - 2
		fy = float(iy) + 1.0

	var tx := fx - float(ix)
	var ty := fy - float(iy)

	var idx := iy * res_x + ix
	var d00 := grid[idx]
	var d10 := grid[idx + 1]
	var d01 := grid[idx + res_x]
	var d11 := grid[idx + res_x + 1]

	return d00 * (1.0 - tx) * (1.0 - ty) + d10 * tx * (1.0 - ty) \
		 + d01 * (1.0 - tx) * ty + d11 * tx * ty

static func _create_quad_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	mesh.center_offset = Vector3(0, 0.5, 0)
	return mesh

# ============================================================
#  DEBUG VISUALS (editor only)
# ============================================================

func _update_debug_visuals() -> void:
	if not Engine.is_editor_hint():
		return

	if _debug_mesh:
		_debug_mesh.queue_free()
		_debug_mesh = null

	if not show_shape_outline or shape_points.size() < 3:
		return

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	for p in shape_points:
		im.surface_add_vertex(Vector3(p.x, 0.1, p.y))
	im.surface_add_vertex(Vector3(shape_points[0].x, 0.1, shape_points[0].y))

	im.surface_end()

	_debug_mesh = MeshInstance3D.new()
	_debug_mesh.mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.YELLOW_GREEN
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_mesh.material_override = mat

	add_child(_debug_mesh)

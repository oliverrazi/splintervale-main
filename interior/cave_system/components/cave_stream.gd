## CaveStream — Self-contained water stream / river / puddle component.
##
## Drop this into your cave scene, configure its shape and flow direction,
## and it creates the water mesh, applies the water shader, adds caustic
## projection, and optionally plays ambient water audio.
##
## For simple puddles, set [member flow_speed] to 0.
## For rivers, set [member flow_direction] and [member flow_speed].

class_name CaveStream
extends Node3D

# ── Configuration ─────────────────────────────────────────────────────────────

@export_group("Shape")
## Width of the stream (X axis).
@export var stream_width: float = 2.0
## Length of the stream (Z axis / flow direction).
@export var stream_length: float = 6.0
## Subdivisions for the water mesh (more = smoother edges and vertex painting).
@export var subdivisions: int = 8

@export_group("Water")
@export var water_shader: Shader = null  # Assign cave_water.gdshader
@export var flow_direction: Vector2 = Vector2(0.0, 1.0)
@export var flow_speed: float = 0.3
@export var color_shallow: Color = Color(0.12, 0.18, 0.25)
@export var color_deep: Color = Color(0.03, 0.06, 0.10)
@export var opacity: float = 0.85
@export var water_y_offset: float = -0.05  # Slightly below floor level

@export_group("Caustics")
@export var enable_caustics: bool = true
@export var caustics_shader: Shader = null  # Assign cave_caustics.gdshader
@export var caustic_intensity: float = 0.25
@export var caustic_spread: float = 1.3  # How far caustics extend beyond water

@export_group("Audio")
@export var enable_audio: bool = true
@export var water_sound: AudioStream = null
@export var audio_volume_db: float = -18.0
@export var audio_max_distance: float = 12.0
@export var audio_bus: String = "CaveReverb"

# ── Internal ──────────────────────────────────────────────────────────────────

var _water_mesh: MeshInstance3D
var _caustic_mesh: MeshInstance3D
var _audio_player: AudioStreamPlayer3D


func _ready() -> void:
	_create_water_mesh()
	if enable_caustics:
		_create_caustic_projection()
	if enable_audio and water_sound:
		_create_audio()


func _create_water_mesh() -> void:
	_water_mesh = MeshInstance3D.new()
	_water_mesh.name = "WaterSurface"

	var plane := PlaneMesh.new()
	plane.size = Vector2(stream_width, stream_length)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	_water_mesh.mesh = plane
	_water_mesh.position.y = water_y_offset

	# Apply water shader material
	var mat := ShaderMaterial.new()
	if water_shader:
		mat.shader = water_shader
		mat.set_shader_parameter("flow_direction", flow_direction)
		mat.set_shader_parameter("flow_speed", flow_speed)
		mat.set_shader_parameter("color_shallow", Vector3(color_shallow.r, color_shallow.g, color_shallow.b))
		mat.set_shader_parameter("color_deep", Vector3(color_deep.r, color_deep.g, color_deep.b))
		mat.set_shader_parameter("opacity", opacity)
	else:
		# Fallback — simple transparent blue material
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(color_shallow.r, color_shallow.g, color_shallow.b, opacity)
		fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_water_mesh.material_override = fallback

	if water_shader:
		_water_mesh.material_override = mat

	add_child(_water_mesh)


func _create_caustic_projection() -> void:
	_caustic_mesh = MeshInstance3D.new()
	_caustic_mesh.name = "CausticProjection"

	var plane := PlaneMesh.new()
	plane.size = Vector2(stream_width * caustic_spread, stream_length * caustic_spread)
	_caustic_mesh.mesh = plane
	# Caustics sit just above the floor, slightly above water
	_caustic_mesh.position.y = water_y_offset + 0.02

	if caustics_shader:
		var mat := ShaderMaterial.new()
		mat.shader = caustics_shader
		mat.set_shader_parameter("intensity", caustic_intensity)
		mat.set_shader_parameter("caustic_color", Vector3(color_shallow.r * 1.5, color_shallow.g * 1.5, color_shallow.b * 1.5))
		_caustic_mesh.material_override = mat
	else:
		# Without shader, skip caustics
		_caustic_mesh.visible = false

	add_child(_caustic_mesh)


func _create_audio() -> void:
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.name = "WaterAudio"
	_audio_player.stream = water_sound
	_audio_player.volume_db = audio_volume_db
	_audio_player.max_distance = audio_max_distance
	_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	_audio_player.bus = audio_bus
	_audio_player.autoplay = true
	# Loop handling — if using AudioStreamOggVorbis, set loop in the resource.
	add_child(_audio_player)


## Update flow direction at runtime (e.g., for branching streams).
func set_flow_direction(dir: Vector2) -> void:
	flow_direction = dir
	if _water_mesh and _water_mesh.material_override is ShaderMaterial:
		_water_mesh.material_override.set_shader_parameter("flow_direction", dir)

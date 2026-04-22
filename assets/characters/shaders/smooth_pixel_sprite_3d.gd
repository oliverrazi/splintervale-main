## SmoothPixelSprite3D v4
##
## Drop-in Sprite3D-Ersatz mit:
## - Smooth Pixel Filtering (kein Flimmern)
## - Korrektes Billboard (Full / Y / Y+Tilt / None)
## - modulate-Property (wie Sprite3D)
##
## KEIN manueller Textur-Import nötig.

@tool
class_name SmoothPixelSprite3D
extends MeshInstance3D

enum BillboardMode {
	FULL,      ## Sprite schaut komplett zur Kamera (empfohlen für Top-Down)
	Y_ONLY,    ## Dreht nur um Y-Achse
	Y_TILTED,  ## Y-Billboard + Neigung (HD-2D Style)
	NONE,      ## Kein Billboard
}

enum FilterAlgorithm {
	SMOOTHSTEP,  ## Weichste Kanten (empfohlen)
	IQ_LINEAR,   ## Etwas schärfer
	CPTPOTATO,   ## Beste Mipmap-Unterstützung
}

# --- Textur & Spritesheet ---
@export var texture: Texture2D : set = _set_texture
@export var hframes: int = 1 : set = _set_hframes
@export var vframes: int = 1 : set = _set_vframes
@export var frame: int = 0 : set = _set_frame
@export var flip_h: bool = false : set = _set_flip_h
@export var pixel_size: float = 0.01 : set = _set_pixel_size

# --- Modulate (wie Sprite3D.modulate) ---
## Farbmodulation inkl. Alpha. Funktioniert wie Sprite3D.modulate.
## character.modulate = Color.WHITE → normal
## character.modulate.a = 0.5 → halbtransparent
## character.modulate = Color.RED → rot eingefärbt
@export var modulate: Color = Color.WHITE : set = _set_modulate

# --- Billboard ---
@export var billboard_mode: BillboardMode = BillboardMode.FULL : set = _set_billboard_mode
@export_range(0.0, 0.5, 0.01) var tilt_amount: float = 0.15 : set = _set_tilt_amount

# --- Shader-Einstellungen ---
@export var filter_algorithm: FilterAlgorithm = FilterAlgorithm.SMOOTHSTEP : set = _set_filter_algorithm
@export_range(0.3, 3.0, 0.1) var aa_sharpness: float = 1.2 : set = _set_aa_sharpness
@export_range(0.0, 1.0, 0.1) var frame_bleed_guard: float = 0.5 : set = _set_frame_bleed_guard

@export_range(0.0, 0.1, 0.001) var depth_bias: float = 0.0 : set = _set_depth_bias

# --- Internes ---
var _material: ShaderMaterial
var _shader_path: String = "res://assets/characters/shaders/pixel_art_smooth_v4.gdshader"


func _ready() -> void:
	_setup_mesh()
	_setup_material()
	_update_all()


func _setup_mesh() -> void:
	if not mesh or not mesh is QuadMesh:
		mesh = QuadMesh.new()


func _setup_material() -> void:
	_material = ShaderMaterial.new()
	var shader = load(_shader_path) as Shader
	if shader == null:
		push_warning("SmoothPixelSprite3D: Shader nicht gefunden: %s" % _shader_path)
		return
	_material.shader = shader
	material_override = _material


func _update_all() -> void:
	_update_texture()
	_update_frame()
	_update_shader_params()


func _update_texture() -> void:
	if _material == null or texture == null:
		return
	_material.set_shader_parameter("sprite_texture", texture)
	_update_quad_size()


func _update_quad_size() -> void:
	if texture == null or mesh == null:
		return
	var tex_size := texture.get_size()
	var frame_w := tex_size.x / float(hframes)
	var frame_h := tex_size.y / float(vframes)
	(mesh as QuadMesh).size = Vector2(frame_w, frame_h) * pixel_size


func _update_frame() -> void:
	if _material == null or texture == null:
		return
	var clamped_frame := clampi(frame, 0, hframes * vframes - 1)
	var fx := clamped_frame % hframes
	var fy := clamped_frame / hframes
	var f_size := Vector2(1.0 / float(hframes), 1.0 / float(vframes))
	var f_coords := Vector2(float(fx) * f_size.x, float(fy) * f_size.y)
	_material.set_shader_parameter("frame_size", f_size)
	_material.set_shader_parameter("frame_coords", f_coords)


func _update_shader_params() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("flip_h", flip_h)
	_material.set_shader_parameter("modulate", modulate)
	_material.set_shader_parameter("billboard_mode", int(billboard_mode))
	_material.set_shader_parameter("tilt_amount", tilt_amount)
	_material.set_shader_parameter("filter_mode", int(filter_algorithm))
	_material.set_shader_parameter("aa_sharpness", aa_sharpness)
	_material.set_shader_parameter("frame_bleed_guard", frame_bleed_guard)

	_material.set_shader_parameter("depth_bias", depth_bias)

# --- Setter ---
func _set_texture(value: Texture2D) -> void:
	texture = value
	if _material:
		_update_texture()
		_update_frame()

func _set_hframes(value: int) -> void:
	hframes = max(1, value)
	if _material:
		_update_quad_size()
		_update_frame()

func _set_vframes(value: int) -> void:
	vframes = max(1, value)
	if _material:
		_update_quad_size()
		_update_frame()

func _set_frame(value: int) -> void:
	frame = value
	if _material:
		_update_frame()

func _set_flip_h(value: bool) -> void:
	flip_h = value
	if _material:
		_material.set_shader_parameter("flip_h", flip_h)

func _set_pixel_size(value: float) -> void:
	pixel_size = value
	_update_quad_size()

func _set_modulate(value: Color) -> void:
	modulate = value
	if _material:
		_material.set_shader_parameter("modulate", modulate)

func _set_billboard_mode(value: BillboardMode) -> void:
	billboard_mode = value
	if _material:
		_material.set_shader_parameter("billboard_mode", int(billboard_mode))

func _set_tilt_amount(value: float) -> void:
	tilt_amount = value
	if _material:
		_material.set_shader_parameter("tilt_amount", tilt_amount)

func _set_filter_algorithm(value: FilterAlgorithm) -> void:
	filter_algorithm = value
	if _material:
		_material.set_shader_parameter("filter_mode", int(filter_algorithm))

func _set_aa_sharpness(value: float) -> void:
	aa_sharpness = value
	if _material:
		_material.set_shader_parameter("aa_sharpness", aa_sharpness)

func _set_frame_bleed_guard(value: float) -> void:
	frame_bleed_guard = value
	if _material:
		_material.set_shader_parameter("frame_bleed_guard", frame_bleed_guard)

func _set_depth_bias(value: float) -> void:
	depth_bias = value
	if _material:
		_material.set_shader_parameter("depth_bias", depth_bias)

@tool
extends GPUParticles3D
## CauldronSmoke v3
## Kein custom Shader — nutzt StandardMaterial3D mit Billboard.
## Einfach auf GPUParticles3D legen, fertig.

@export var smoke_color  : Color = Color(0.45, 0.9, 0.5)  ## Gebräu-Tint
@export var smoke_amount : int   = 22
@export var quad_size    : float = 0.20   ## Größe pro Rauch-Wolke (Meter)
@export var rise_speed   : float = 0.35  ## Aufstiegs-Geschwindigkeit

func _ready() -> void:
	_build()

# Im Editor bei Export-Änderungen neu aufbauen
func _validate_property(_property: Dictionary) -> void:
	if Engine.is_editor_hint():
		_build()

func _build() -> void:
	amount         = smoke_amount
	lifetime       = 2.8
	explosiveness  = 0.0
	randomness     = 0.7
	one_shot       = false
	local_coords   = false
	visibility_aabb = AABB(Vector3(-1.5, -0.2, -1.5), Vector3(3, 3, 3))

	# ── ParticleProcessMaterial ──────────────────────────────────────
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction              = Vector3(0, 1, 0)
	pm.spread                 = 18.0
	pm.gravity                = Vector3(0, 0, 0)
	pm.initial_velocity_min   = rise_speed * 0.7
	pm.initial_velocity_max   = rise_speed * 1.3
	pm.angular_velocity_min   = -30.0
	pm.angular_velocity_max   =  30.0
	pm.scale_min              = 0.5
	pm.scale_max              = 1.5
	pm.damping_min            = 0.05
	pm.damping_max            = 0.3
	pm.turbulence_enabled              = true
	pm.turbulence_influence_min        = 0.03
	pm.turbulence_influence_max        = 0.10
	pm.turbulence_noise_speed_random   = 0.3

	# Farbverlauf: Tint → Grau → transparent
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	g.colors  = PackedColorArray([
		Color(smoke_color.r, smoke_color.g, smoke_color.b, 0.0),
		Color(smoke_color.r, smoke_color.g, smoke_color.b, 0.6),
		Color(0.65, 0.65, 0.65, 0.25),
		Color(0.75, 0.75, 0.75, 0.0),
	])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt

	process_material = pm

	# ── Mesh + Material ─────────────────────────────────────────────
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)

	var mat                         := StandardMaterial3D.new()
	mat.transparency                 = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode                   = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode               = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale         = true   # Partikel-Skalierung bleibt erhalten
	mat.vertex_color_use_as_albedo   = true   # liest COLOR vom Gradient
	mat.shading_mode                 = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.depth_draw_mode              = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.no_depth_test                = true
	mat.cull_mode                    = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture               = _make_soft_circle(64)
	mat.albedo_color                 = Color.WHITE   # Farbe kommt vom Gradient

	quad.surface_set_material(0, mat)
	draw_pass_1 = quad

	if Engine.is_editor_hint():
		print("[CauldronSmoke] Aufgebaut. Partikel: %d | Farbe: %s" % [smoke_amount, smoke_color])

## Erzeugt eine weiche Kreistextur (kein externes PNG nötig)
static func _make_soft_circle(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius  := size * 0.5

	for y in size:
		for x in size:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center) / radius
			# smoothstep: Mitte = 1.0, Rand = 0.0, außerhalb = 0.0
			var alpha := 1.0 - smoothstep(0.35, 1.0, dist)
			# leichte Aufhellung in der Mitte für Volumen-Eindruck
			var brightness := 1.0 + (1.0 - smoothstep(0.0, 0.5, dist)) * 0.12
			var c := Color(brightness, brightness, brightness, alpha)
			img.set_pixel(x, y, c)

	return ImageTexture.create_from_image(img)

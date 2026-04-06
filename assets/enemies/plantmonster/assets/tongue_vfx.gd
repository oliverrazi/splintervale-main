extends Node3D
class_name TongueVFX

## Visuelle Effekte für die Pflanzenmonster-Zunge
## Seifenblasen-artige Giftblasen die von der Zungenspitze aufsteigen

# === BUBBLE SETTINGS ===
@export_group("Bubble Settings")
@export var bubble_color: Color = Color(0.25, 0.9, 0.2, 0.6)
@export var bubble_color_highlight: Color = Color(0.5, 1.0, 0.4, 0.8)
@export var bubble_glow_color: Color = Color(0.3, 1.0, 0.2, 1.0)
@export var bubble_amount: int = 10
@export var bubble_lifetime_min: float = 0.6
@export var bubble_lifetime_max: float = 1.2
@export var bubble_size_min: float = 0.02
@export var bubble_size_max: float = 0.06
@export var bubble_rise_speed: float = 0.5
@export var bubble_wobble_strength: float = 0.3
@export var bubble_wobble_speed: float = 3.0

# === IMPACT SETTINGS ===
@export_group("Impact Settings")
@export var impact_bubble_amount: int = 15
@export var impact_speed: float = 2.5

# === GLOW SETTINGS ===
@export_group("Glow Settings")
@export var glow_enabled: bool = true
@export var glow_energy: float = 0.5
@export var glow_range: float = 0.6
@export var glow_pulse_speed: float = 4.0
@export var glow_pulse_strength: float = 0.2

# === INTERNAL ===
var _bubble_particles: GPUParticles3D = null
var _impact_particles: GPUParticles3D = null
var _glow_light: OmniLight3D = null
var _active: bool = false


func _ready() -> void:
	_setup_bubble_particles()
	_setup_impact_particles()
	_setup_glow_light()


func _process(delta: float) -> void:
	if not _active:
		return
	
	_update_glow_pulse()


# === SETUP ===

func _setup_bubble_particles() -> void:
	_bubble_particles = GPUParticles3D.new()
	_bubble_particles.name = "BubbleParticles"
	_bubble_particles.amount = bubble_amount
	_bubble_particles.lifetime = bubble_lifetime_max
	_bubble_particles.explosiveness = 0.0
	_bubble_particles.randomness = 0.8
	_bubble_particles.emitting = false
	_bubble_particles.one_shot = false
	
	var mat := ParticleProcessMaterial.new()
	
	# Blasen steigen leicht auf mit zufälliger Bewegung
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = bubble_rise_speed * 0.5
	mat.initial_velocity_max = bubble_rise_speed
	mat.gravity = Vector3(0, 0.3, 0)  # Leichter Auftrieb
	
	# Größenvariation
	mat.scale_min = bubble_size_min / 0.04
	mat.scale_max = bubble_size_max / 0.04
	
	# Turbulenz für Wobble-Effekt
	mat.turbulence_enabled = true
	mat.turbulence_noise_scale = 1.5
	mat.turbulence_noise_strength = bubble_wobble_strength
	mat.turbulence_noise_speed = Vector3(bubble_wobble_speed, bubble_wobble_speed * 0.5, bubble_wobble_speed)
	mat.turbulence_noise_speed_random = 0.5
	
	# Farbe: Halbtransparent mit Highlight
	var color_gradient := Gradient.new()
	color_gradient.add_point(0.0, bubble_color_highlight)
	color_gradient.add_point(0.3, bubble_color)
	color_gradient.add_point(0.7, bubble_color)
	color_gradient.add_point(0.9, Color(bubble_color.r, bubble_color.g, bubble_color.b, 0.3))
	color_gradient.add_point(1.0, Color(bubble_color.r, bubble_color.g, bubble_color.b, 0.0))
	var color_texture := GradientTexture1D.new()
	color_texture.gradient = color_gradient
	mat.color_ramp = color_texture
	
	# Größe über Zeit: Wachsen, dann platzen
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.2, 1.0))
	scale_curve.add_point(Vector2(0.8, 1.1))
	scale_curve.add_point(Vector2(0.95, 1.3))  # Kurz größer werden
	scale_curve.add_point(Vector2(1.0, 0.0))   # Dann "platzen"
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	mat.scale_curve = scale_texture
	
	_bubble_particles.process_material = mat
	_bubble_particles.draw_pass_1 = _create_bubble_mesh()
	
	add_child(_bubble_particles)


func _setup_impact_particles() -> void:
	_impact_particles = GPUParticles3D.new()
	_impact_particles.name = "ImpactParticles"
	_impact_particles.amount = impact_bubble_amount
	_impact_particles.lifetime = 0.5
	_impact_particles.explosiveness = 1.0
	_impact_particles.randomness = 0.9
	_impact_particles.emitting = false
	_impact_particles.one_shot = true
	
	var mat := ParticleProcessMaterial.new()
	
	# Explosion in alle Richtungen
	mat.direction = Vector3(0, 0.5, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = impact_speed * 0.4
	mat.initial_velocity_max = impact_speed
	mat.gravity = Vector3(0, -2, 0)
	
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	
	mat.damping_min = 2.0
	mat.damping_max = 4.0
	
	# Turbulenz
	mat.turbulence_enabled = true
	mat.turbulence_noise_scale = 2.0
	mat.turbulence_noise_strength = 0.8
	
	# Farbe: Heller Flash dann verschwinden
	var color_gradient := Gradient.new()
	color_gradient.add_point(0.0, bubble_glow_color)
	color_gradient.add_point(0.15, bubble_color_highlight)
	color_gradient.add_point(0.5, bubble_color)
	color_gradient.add_point(1.0, Color(0, 0, 0, 0))
	var color_texture := GradientTexture1D.new()
	color_texture.gradient = color_gradient
	mat.color_ramp = color_texture
	
	# Schnelles Schrumpfen/Platzen
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.2))
	scale_curve.add_point(Vector2(0.1, 1.4))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(0.8, 0.6))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	mat.scale_curve = scale_texture
	
	_impact_particles.process_material = mat
	_impact_particles.draw_pass_1 = _create_bubble_mesh()
	
	add_child(_impact_particles)


func _setup_glow_light() -> void:
	if not glow_enabled:
		return
	
	_glow_light = OmniLight3D.new()
	_glow_light.name = "TongueGlow"
	_glow_light.light_color = bubble_glow_color
	_glow_light.light_energy = glow_energy
	_glow_light.omni_range = glow_range
	_glow_light.omni_attenuation = 2.0
	_glow_light.visible = false
	
	add_child(_glow_light)


func _create_bubble_mesh() -> ArrayMesh:
	# Seifenblasen-Mesh: Kugel mit Highlight
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	
	var segments := 12
	var rings := 8
	var radius := 0.04
	
	# Kugel generieren
	for ring in range(rings + 1):
		var v := float(ring) / rings
		var phi := v * PI
		var y := cos(phi) * radius
		var ring_radius := sin(phi) * radius
		
		for seg in range(segments + 1):
			var u := float(seg) / segments
			var theta := u * TAU
			
			var x := cos(theta) * ring_radius
			var z := sin(theta) * ring_radius
			
			vertices.append(Vector3(x, y, z))
			normals.append(Vector3(x, y, z).normalized())
			uvs.append(Vector2(u, v))
	
	# Indices
	for ring in range(rings):
		for seg in range(segments):
			var current := ring * (segments + 1) + seg
			var next_seg := ring * (segments + 1) + seg + 1
			var next_ring := (ring + 1) * (segments + 1) + seg
			var next_both := (ring + 1) * (segments + 1) + seg + 1
			
			indices.append(current)
			indices.append(next_ring)
			indices.append(next_seg)
			
			indices.append(next_seg)
			indices.append(next_ring)
			indices.append(next_both)
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Seifenblasen-Material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = bubble_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	
	# Emission für Glow
	mat.emission_enabled = true
	mat.emission = bubble_glow_color
	mat.emission_energy_multiplier = 0.4
	
	# Rim/Fresnel-Effekt für Seifenblasen-Look
	mat.rim_enabled = true
	mat.rim = 0.8
	mat.rim_tint = 0.5
	
	# Metallic und Roughness für Reflektion
	mat.metallic = 0.2
	mat.roughness = 0.1
	
	# Refraction für echten Blasen-Effekt (optional, performance-intensiv)
	# mat.refraction_enabled = true
	# mat.refraction_scale = 0.05
	
	mesh.surface_set_material(0, mat)
	
	return mesh


# === GLOW UPDATE ===

func _update_glow_pulse() -> void:
	if _glow_light == null or not _glow_light.visible:
		return
	
	var time := Time.get_ticks_msec() / 1000.0
	var pulse := 1.0 + sin(time * glow_pulse_speed) * glow_pulse_strength
	_glow_light.light_energy = glow_energy * pulse


# === PUBLIC API ===

func start(pos: Vector3) -> void:
	_active = true
	position = pos
	_bubble_particles.emitting = true
	
	if _glow_light:
		_glow_light.visible = true


func stop() -> void:
	_active = false
	_bubble_particles.emitting = false
	
	if _glow_light:
		_glow_light.visible = false


func update_position(pos: Vector3, direction: Vector3 = Vector3.ZERO) -> void:
	position = pos
	
	# Optional: Blasen-Richtung leicht anpassen
	if direction != Vector3.ZERO and _bubble_particles.process_material:
		var mat := _bubble_particles.process_material as ParticleProcessMaterial
		# Blasen steigen auf, aber leicht in Zungenrichtung versetzt
		mat.direction = Vector3(direction.x * 0.2, 1, direction.z * 0.2).normalized()


func spawn_impact(pos: Vector3) -> void:
	_impact_particles.position = pos - position  # Relativ zur Node-Position
	_impact_particles.restart()
	_impact_particles.emitting = true
	
	# Glow-Flash
	if _glow_light:
		var prev_energy := _glow_light.light_energy
		_glow_light.light_energy = glow_energy * 3.0
		
		var tween := create_tween()
		tween.tween_property(_glow_light, "light_energy", prev_energy, 0.15)


func set_colors(main: Color, highlight: Color, glow: Color) -> void:
	bubble_color = main
	bubble_color_highlight = highlight
	bubble_glow_color = glow
	
	# Update materials...
	_update_particle_colors()
	
	if _glow_light:
		_glow_light.light_color = glow


func _update_particle_colors() -> void:
	if _bubble_particles and _bubble_particles.process_material:
		var mat := _bubble_particles.process_material as ParticleProcessMaterial
		var gradient := Gradient.new()
		gradient.add_point(0.0, bubble_color_highlight)
		gradient.add_point(0.3, bubble_color)
		gradient.add_point(0.7, bubble_color)
		gradient.add_point(0.9, Color(bubble_color.r, bubble_color.g, bubble_color.b, 0.3))
		gradient.add_point(1.0, Color(bubble_color.r, bubble_color.g, bubble_color.b, 0.0))
		var texture := GradientTexture1D.new()
		texture.gradient = gradient
		mat.color_ramp = texture

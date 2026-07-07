@tool
class_name Waterfall
extends Node3D

# === Konfiguration ===
@export var waterfall_height: float = 6.0 : set = _set_height
@export var waterfall_width: float  = 2.0 : set = _set_width
@export var flow_intensity: float   = 1.0  # multipliziert flow_speed

@export var wetness_radius: float = 5.0

@export_group("Editor")
@export var show_bounds_preview: bool = true : set = _set_show_bounds
var _bounds_helper: MeshInstance3D

@export_group("LOD")
@export var lod_far_dist: float  = 15.0   # ab hier: keine Particles
@export var lod_cull_dist: float = 35.0   # ab hier: alles aus

@export_group("GodRay")
@export var enable_godray: bool = true : set = _set_godray_enabled
@export var godray_intensity: float = 1.2 : set = _set_godray_intensity
@export var godray_color: Color = Color(0.149, 0.116, 0.0, 1.0) : set = _set_godray_color
@export var godray_length_factor: float = 1.4  # relativ zur Wasserfall-Höhe
@export var godray_width: float = 1.2

@onready var godray: MeshInstance3D = get_node_or_null("GodRay")
@onready var godray_2: MeshInstance3D = get_node_or_null("GodRay2")
@onready var godray_3: MeshInstance3D = get_node_or_null("GodRay3")


@onready var impact_mist: GPUParticles3D = get_node_or_null("ImpactMist")
# === Nodes ===
@onready var fall_mesh:     MeshInstance3D    = get_node_or_null("FallMesh")
@onready var impact_foam:   MeshInstance3D    = get_node_or_null("ImpactFoam")
@onready var outer_foam_halo:   MeshInstance3D    = get_node_or_null("OuterFoamHalo")
@onready var impact_core:   MeshInstance3D    = get_node_or_null("ImpactCore")
@onready var top_mist:      GPUParticles3D    = get_node_or_null("TopMist")
@onready var side_spray:    GPUParticles3D    = get_node_or_null("SideSpray")
@onready var impact_burst:  GPUParticles3D    = get_node_or_null("ImpactBurst")
@onready var pool_ripples:  GPUParticles3D    = get_node_or_null("PoolRipples")
@onready var impact_light:  OmniLight3D       = get_node_or_null("ImpactLight")
@onready var audio:         AudioStreamPlayer3D = get_node_or_null("AudioStreamPlayer3D")
@onready var notifier: VisibleOnScreenNotifier3D = get_node_or_null("VisibilityNotifier")

var _player: Node3D
var _current_lod: int = -1
var _lod_timer: float = 0.0
var _is_on_screen: bool = true

# Ersetze die _player-Lookup-Logik komplett:

func _ready() -> void:
	_apply_dimensions()
	
	if Engine.is_editor_hint():
		return
		
	if has_node("/root/WetnessUpdater"):
		WetnessUpdater.register_waterfall(self, wetness_radius)
	
	if notifier:
		notifier.screen_entered.connect(_on_screen_entered)
		notifier.screen_exited.connect(_on_screen_exited)
	else:
		_is_on_screen = true  # ohne Notifier nehmen wir an: immer sichtbar
	_current_lod = -1
	_update_lod(true)
	
func _exit_tree() -> void:
	if has_node("/root/WetnessUpdater"):
		WetnessUpdater.unregister_waterfall(self)

func _get_player() -> Node3D:
	# Cache prüfen, ggf. neu suchen (Player kann zwischen Szenen wechseln)
	if is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player

func _update_lod(force: bool = false) -> void:
	var player := _get_player()
	var new_lod: int
	if not is_instance_valid(player):
		# Editor-Preview oder Player noch nicht in Szene → volle Qualität
		new_lod = 0
	else:
		var dist := global_position.distance_to(player.global_position)
		if not _is_on_screen or dist > lod_cull_dist:
			new_lod = 2
		elif dist > lod_far_dist:
			new_lod = 1
		else:
			new_lod = 0
	if new_lod == _current_lod and not force:
		return
	_current_lod = new_lod
	_apply_lod()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_lod_timer += delta
	if _lod_timer >= 0.4:
		_lod_timer = 0.0
		_update_lod()


func _apply_lod() -> void:
	var full := _current_lod == 0
	var mesh_only := _current_lod <= 1
	if impact_mist: impact_mist.emitting = full
	
	if fall_mesh:    fall_mesh.visible = mesh_only
	if impact_foam:  impact_foam.visible = mesh_only
	if top_mist:     top_mist.emitting = full
	if side_spray:   side_spray.emitting = full
	if impact_burst: impact_burst.emitting = full
	if pool_ripples: pool_ripples.emitting = full
	if impact_light: impact_light.visible = full
	if audio:        audio.stream_paused = not mesh_only

func _on_screen_entered() -> void:
	_is_on_screen = true
	_update_lod(true)

func _on_screen_exited() -> void:
	_is_on_screen = false
	_update_lod(true)

# === Dimensions ===
func _set_height(v: float) -> void:
	waterfall_height = v
	if is_inside_tree(): _apply_dimensions()

func _set_width(v: float) -> void:
	waterfall_width = v
	if is_inside_tree(): _apply_dimensions()

func _apply_dimensions() -> void:
	# === FallMesh: das Wasserfall-Quad ===
	if fall_mesh:
		fall_mesh.scale = Vector3(waterfall_width, waterfall_height, 1.0)
		fall_mesh.position.y = waterfall_height * 0.5
	
	# === ImpactFoam: dichter Schaum-Ring direkt am Aufprall ===
	if impact_foam:
		impact_foam.scale = Vector3(waterfall_width * 3.5, waterfall_width * 1.8, waterfall_width * 2.8)
	
	# === OuterFoamHalo: breiter Schaum-Halo drumherum ===
	if outer_foam_halo:
		outer_foam_halo.scale = Vector3(waterfall_width * 2.2, waterfall_width * 0.5, waterfall_width * 2.2)
	
	# === ImpactCore: 3D-Schaumkuppel ===
	if impact_core:
		impact_core.scale = Vector3(waterfall_width * 1.65, waterfall_width * 0.55, waterfall_width * 0.4)
	
	# === TopMist: Lip-Droplets oben ===
	if top_mist:
		top_mist.position = Vector3(0, waterfall_height, 0.05)  # vor der FallMesh
		var tm_mat := top_mist.process_material as ParticleProcessMaterial
		if tm_mat:
			tm_mat.emission_box_extents = Vector3(waterfall_width * 0.35, 0.03, 0.05)
		# Per-Particle Scale: mit Wasserfall-Größe skalieren
		var size_factor: float = clamp(waterfall_width * 0.5, 0.5, 2.0)
		_set_particle_quad_size(top_mist, 0.05 * size_factor)
	
	# === SideSpray: Seitlich entlang des Falls ===
	if side_spray:
		# Position: mittig in der Fallhöhe
		side_spray.position = Vector3(0, waterfall_height * 0.8, -0.5)
		var ss_mat := side_spray.process_material as ParticleProcessMaterial
		if ss_mat:
			ss_mat.emission_box_extents = Vector3(
				waterfall_width * 0.9,
				waterfall_height * 0.4,
				0.05
			)
		var size_factor: float = clamp(waterfall_width * 0.5, 0.5, 2.0)
		_set_particle_quad_size(side_spray, 0.04 * size_factor)
	
	# === ImpactBurst: Splash-Fontäne am Boden ===
	if impact_burst:
		impact_burst.position = Vector3(0, waterfall_height * 0.8,-0.5)  # exakt am Aufprall
		var ib_mat := impact_burst.process_material as ParticleProcessMaterial
		if ib_mat:
			ib_mat.emission_ring_radius = waterfall_width * 0.3
			ib_mat.emission_ring_inner_radius = 0.0
			ib_mat.emission_ring_height = 0.05
		var size_factor: float = clamp(waterfall_width * 0.5, 0.5, 2.0)
		_set_particle_quad_size(impact_burst, 0.06 * size_factor)
	
	# === ImpactMist: dichte Bodenwolke ===
	if impact_mist:
		var im_mat := impact_mist.process_material as ParticleProcessMaterial
		if im_mat:
			im_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			im_mat.emission_box_extents = Vector3(
				waterfall_width * 1.8,
				0.02,
				waterfall_width * 1.4
			)
		# Mist-Puffs skalieren mit Wasserfall-Größe
		var size_factor: float = clamp(waterfall_width * 0.65,waterfall_width *  1.0, waterfall_width * 0.5)
		_set_particle_quad_size(impact_mist, 1.0 * size_factor)
	
	# === PoolRipples: konzentrische Wellen ===
	if pool_ripples:
		var pr_mat := pool_ripples.process_material as ParticleProcessMaterial
		if pr_mat:
			pr_mat.emission_ring_radius = waterfall_width * 0.5
		var size_factor: float = clamp(waterfall_width * 0.5, 0.5, 2.0)
		_set_particle_quad_size(pool_ripples, 0.4 * size_factor)
	
	# === GodRays ===
	# (dein bestehender GodRay-Code bleibt wie er ist)
	
	# === Bounds-Helper ===
	_update_bounds_preview()


# Helper: setzt die Größe des QuadMesh eines Particle-Systems
func _set_particle_quad_size(particles: GPUParticles3D, size: float) -> void:
	if particles == null: return
	var mesh := particles.draw_pass_1
	if mesh is QuadMesh:
		(mesh as QuadMesh).size = Vector2(size, size)
		
func _set_show_bounds(v: bool) -> void:
	show_bounds_preview = v
	_update_bounds_preview()

func _update_bounds_preview() -> void:
	if not Engine.is_editor_hint():
		return
	if _bounds_helper == null and show_bounds_preview:
		_bounds_helper = MeshInstance3D.new()
		_bounds_helper.name = "_BoundsPreviewHelper"
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		_bounds_helper.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.7, 1.0, 0.15)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bounds_helper.material_override = mat
		add_child(_bounds_helper)
	if _bounds_helper:
		_bounds_helper.visible = show_bounds_preview
		_bounds_helper.scale = Vector3(waterfall_width, waterfall_height, waterfall_width)
		_bounds_helper.position.y = waterfall_height * 0.5

func set_flow_intensity(v: float) -> void:
	flow_intensity = v
	var mat := fall_mesh.get_active_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("flow_speed", 1.6 * v)
		
func _set_godray_enabled(v: bool) -> void:
	enable_godray = v
	if godray: godray.visible = v

func _set_godray_intensity(v: float) -> void:
	godray_intensity = v
	_update_godray_material()

func _set_godray_color(v: Color) -> void:
	godray_color = v
	_update_godray_material()

func _update_godray_material() -> void:
	if godray == null: return
	var mat := godray.get_active_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("intensity", godray_intensity)
		mat.set_shader_parameter("ray_color", godray_color)

@tool
class_name Waterfall
extends Node3D

# === Konfiguration ===
@export var waterfall_height: float = 6.0 : set = _set_height
@export var waterfall_width: float  = 2.0 : set = _set_width
@export var flow_intensity: float   = 1.0  # multipliziert flow_speed

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
	
	if notifier:
		notifier.screen_entered.connect(_on_screen_entered)
		notifier.screen_exited.connect(_on_screen_exited)
	else:
		_is_on_screen = true  # ohne Notifier nehmen wir an: immer sichtbar
	_current_lod = -1
	_update_lod(true)

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
	if fall_mesh:
		fall_mesh.scale = Vector3(waterfall_width, waterfall_height, 1.0)
		fall_mesh.position.y = waterfall_height * 0.5
	if top_mist:
		top_mist.position.y = waterfall_height
		var mist_mat := top_mist.process_material as ParticleProcessMaterial
		if mist_mat:
			mist_mat.emission_box_extents = Vector3(waterfall_width * 0.35, 0.03, 0.05)
			mist_mat.spread = 12.0
	if side_spray:
		var spray_mat := side_spray.process_material as ParticleProcessMaterial
		if spray_mat:
			spray_mat.emission_box_extents = Vector3(
				waterfall_width * 0.55, waterfall_height * 0.4, 0.05
			)
	if impact_burst:
		var burst_mat := impact_burst.process_material as ParticleProcessMaterial
		if burst_mat:
			burst_mat.emission_ring_radius = waterfall_width * 0.3
	if impact_foam:
		impact_foam.scale = Vector3(waterfall_width * 1.6, 1.0, waterfall_width * 1.6)
		
	if godray:
		var ray_configs = [
	# [node,      x_world, width, scale_y_factor, y_rot_deg]
		[godray,    0.0,   0.7,  1.8,   0.0],
		[godray_2,  -1.2,  0.25, 2.0,   -20.0],
		[godray_3,  1.4,   0.35, 1.6,   18.0],
	]
		for cfg in ray_configs:
			var ray = cfg[0] as MeshInstance3D
			if ray:
				ray.scale = Vector3(cfg[1], waterfall_height * cfg[2], 1.0)
				ray.position = Vector3(cfg[1], waterfall_height * 0.7, waterfall_width * 0.3)
				ray.rotation_degrees.y = cfg[3]
		godray.scale = Vector3(
			godray_width,
			waterfall_height * 1.8,  # 1.8 statt 1.4 – ragt weit nach oben raus
			1.0
		)
		godray.position = Vector3(
			waterfall_width * 0.25,
			waterfall_height * 0.7,  # höher positioniert
			waterfall_width * 0.3
		)
			
	if impact_mist:
		var im_mat := impact_mist.process_material as ParticleProcessMaterial
		if im_mat:
			im_mat.emission_ring_radius = waterfall_width * 0.35  # kleiner als 0.6
			im_mat.emission_ring_inner_radius = 0.0
			im_mat.emission_ring_height = 0.05



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

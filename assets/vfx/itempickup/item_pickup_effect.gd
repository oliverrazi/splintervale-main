extends Node3D
class_name ItemPickupEffect

signal effect_finished

@export_group("Animation")
@export var rise_height: float = 0.3
@export var rise_duration: float = 0.4
@export var hold_duration: float = 1.5
@export var fade_duration: float = 0.3


@export_group("Rays")
@export var ray_count: int = 8
@export var ray_length: float = 0.8
@export var ray_width: float = 0.04
@export var ray_rotation_speed: float = 0.5
@export var ray_color: Color = Color(1.0, 1.0, 0.9, 0.7)

@export_group("Sound")
@export var pickup_sound: AudioStream = null
@export var pickup_volume_db: float = -3.0

var _item_sprite: Sprite3D = null
var _rays_pivot: Node3D = null
var _rays: Array[MeshInstance3D] = []

var _ui_canvas: CanvasLayer = null
var _ui_panel: PanelContainer = null
var _ui_label: RichTextLabel = null

var _phase: int = 0  # 0=rise, 1=hold, 2=fade
var _phase_time: float = 0.0
var _can_skip: bool = false
var _skip_cooldown: float = 0.3

var _font: FontFile = null


func _ready() -> void:
	# Font laden (gleiche wie DialogueManager)
	var font_path: String = "res://menu/assets/fonts/Merriweather-Regular.ttf"
	if ResourceLoader.exists(font_path):
		_font = load(font_path)


func start(player: Node3D, item_data: ItemData, custom_text: String = "") -> void:
	# Position über dem Spieler
	global_position = player.global_position + Vector3(0, 1.2, 0)
	
	# Item Sprite erstellen
	_create_item_sprite(item_data.icon)
	
	# Strahlen erstellen
	_create_rays()
	
	# UI erstellen
	_create_ui(item_data, custom_text)
	
	# Sound
	if pickup_sound:
		var audio := AudioStreamPlayer.new()
		audio.stream = pickup_sound
		audio.volume_db = pickup_volume_db
		add_child(audio)
		audio.play()
	
	# Animation starten
	_phase = 0
	_phase_time = 0.0
	_can_skip = false
	
	
	set_process(true)


func _create_item_sprite(icon: Texture2D) -> void:
	_item_sprite = Sprite3D.new()
	_item_sprite.texture = icon
	_item_sprite.pixel_size = 0.015
	_item_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_item_sprite.transparent = true
	_item_sprite.no_depth_test = false
	_item_sprite.position = Vector3.ZERO
	add_child(_item_sprite)


func _create_rays() -> void:
	_rays_pivot = Node3D.new()
	_rays_pivot.position = Vector3.ZERO
	add_child(_rays_pivot)
	
	var angle_step: float = TAU / ray_count
	
	for i in range(ray_count):
		var ray := MeshInstance3D.new()
		
		# Quad Mesh für den Strahl
		var quad := QuadMesh.new()
		quad.size = Vector2(ray_width, ray_length)
		ray.mesh = quad
		
		# Material
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ray_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		ray.material_override = mat
		
		# Positionierung - Strahl nach außen
		var angle: float = i * angle_step
		ray.position = Vector3(cos(angle) * ray_length * 0.5, sin(angle) * ray_length * 0.5, 0)
		ray.rotation.z = angle - PI / 2
		
		_rays_pivot.add_child(ray)
		_rays.append(ray)
	
	_set_rays_alpha(0.0)


func _create_ui(item_data: ItemData, custom_text: String) -> void:
	_ui_canvas = CanvasLayer.new()
	_ui_canvas.layer = 60
	add_child(_ui_canvas)
	
	# Panel
	_ui_panel = PanelContainer.new()
	_ui_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ui_panel.anchor_top = 0.7
	_ui_panel.anchor_bottom = 0.85
	_ui_panel.anchor_left = 0.2
	_ui_panel.anchor_right = 0.8
	_ui_panel.offset_top = 0
	_ui_panel.offset_bottom = 0
	_ui_panel.offset_left = 0
	_ui_panel.offset_right = 0
	
	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(0.8, 0.7, 0.4, 0.8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 8
	style.shadow_offset = Vector2(2, 4)
	_ui_panel.add_theme_stylebox_override("panel", style)
	
	_ui_canvas.add_child(_ui_panel)
	
	# Margin
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_ui_panel.add_child(margin)
	
	# VBox für zentrierten Text
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	# Text Label
	_ui_label = RichTextLabel.new()
	_ui_label.bbcode_enabled = true
	_ui_label.fit_content = true
	_ui_label.scroll_active = false
	_ui_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	if _font:
		_ui_label.add_theme_font_override("normal_font", _font)
		_ui_label.add_theme_font_override("bold_font", _font)
	_ui_label.add_theme_font_size_override("normal_font_size", 20)
	_ui_label.add_theme_font_size_override("bold_font_size", 24)
	_ui_label.add_theme_color_override("default_color", Color(1.0, 0.95, 0.85))
	
	vbox.add_child(_ui_label)
	
	# Text setzen
	var display_text: String = ""
	if custom_text != "":
		display_text = custom_text
	else:
		# Standard-Text mit Item-Name
		var rarity_color: Color = item_data.get_rarity_color()
		var color_hex: String = rarity_color.to_html(false)
		display_text = "[center]You got [b][color=#%s]%s[/color][/b]![/center]" % [color_hex, item_data.item_name]
	
	_ui_label.text = display_text
	
	# Initial unsichtbar
	_ui_panel.modulate.a = 0.0


func _process(delta: float) -> void:
	_phase_time += delta
	
	# Skip Cooldown
	if not _can_skip and _phase_time >= _skip_cooldown:
		_can_skip = true
	
	# Strahlen rotieren
	if _rays_pivot:
		_rays_pivot.rotation.z += delta * ray_rotation_speed
	
	match _phase:
		0:  # Rise Phase
			_process_rise(delta)
		1:  # Hold Phase
			_process_hold(delta)
		2:  # Fade Phase
			_process_fade(delta)


func _input(event: InputEvent) -> void:
	if not _can_skip:
		return
	
	if _phase == 2:
		return
	
	# Skip mit beliebiger Taste
	if event.is_action_pressed("hotbar_w") or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_phase = 2
		_phase_time = 0.0
		get_viewport().set_input_as_handled()


func _process_rise(delta: float) -> void:
	var progress: float = _phase_time / rise_duration
	
	if progress >= 1.0:
		progress = 1.0
		_phase = 1
		_phase_time = 0.0
	
	# Easing (ease out)
	var eased: float = 1.0 - pow(1.0 - progress, 2)
	
	# Item steigt
	if _item_sprite:
		_item_sprite.position.y = eased * rise_height
	
	# Strahlen einblenden
	_set_rays_alpha(eased * ray_color.a)
	_set_rays_scale(eased)
	
	# UI einblenden
	if _ui_panel:
		_ui_panel.modulate.a = eased


func _process_hold(delta: float) -> void:
	if _phase_time >= hold_duration:
		_phase = 2
		_phase_time = 0.0
	
	# Leichtes Pulsieren der Strahlen
	var pulse: float = 1.0 + sin(_phase_time * 4.0) * 0.1
	_set_rays_scale(pulse)
	
	# Item leicht bobben
	if _item_sprite:
		_item_sprite.position.y = rise_height + sin(_phase_time * 3.0) * 0.05


func _process_fade(delta: float) -> void:
	var progress: float = _phase_time / fade_duration
	
	if progress >= 1.0:
		_finish_effect()
		return
	
	var alpha: float = 1.0 - progress
	
	if _item_sprite:
		_item_sprite.modulate.a = alpha
	
	_set_rays_alpha(alpha * ray_color.a)
	
	if _ui_panel:
		_ui_panel.modulate.a = alpha


func _set_rays_alpha(alpha: float) -> void:
	for ray in _rays:
		if ray and ray.material_override:
			var mat: StandardMaterial3D = ray.material_override as StandardMaterial3D
			mat.albedo_color.a = alpha


func _set_rays_scale(scale_factor: float) -> void:
	for ray in _rays:
		if ray:
			ray.scale = Vector3(scale_factor, scale_factor, scale_factor)


func _finish_effect() -> void:
	set_process(false)
	set_process_input(false)
	effect_finished.emit()
	queue_free()
	
var _particles: GPUParticles3D = null


func _create_sparkle_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.emitting = true
	_particles.amount = 16
	_particles.lifetime = 0.8
	_particles.explosiveness = 0.0
	_particles.randomness = 1.0
	
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 180.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 1.5
	material.gravity = Vector3(0, 0.5, 0)
	material.scale_min = 0.1
	material.scale_max = 0.3
	material.color = Color(1.0, 1.0, 0.8, 1.0)
	_particles.process_material = material
	
	var mesh := SphereMesh.new()
	mesh.radius = 0.02
	mesh.height = 0.04
	_particles.draw_pass_1 = mesh
	
	add_child(_particles)

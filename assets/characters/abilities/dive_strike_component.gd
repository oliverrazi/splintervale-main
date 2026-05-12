extends Node
class_name DiveStrikeComponent

## Dive Strike Component - Vertikaler Schwert-Stoß aus der Luft.
## Wird typischerweise während eines VectorAnchor-Launchs ausgelöst:
## - HANG-Phase: 0.5s Anticipation, Spieler schwebt mit Energie-Aufladung
## - STRIKE-Phase: Vertikaler Fall mit Damage entlang der Strecke
## - IMPACT: AOE-Damage + VFX + Camera-Shake bei Bodenkontakt
##
## Verbraucht die gesamte verbleibende Resonance beim Auslösen,
## der RP-Wert wird als Damage-Bonus genutzt.

signal dive_started
signal dive_completed
signal dive_cancelled(reason: String)

# === REFERENCES ===
@export var player_path: NodePath = ".."
@export var sprite_path: NodePath = "../charactersprite"
@export var spring_arm_path: NodePath = "../SpringArm3D"

# === DIVE STRIKE ===
@export_group("Dive Strike")
@export var dive_strike_enabled: bool = true
@export var dive_hang_duration: float = 0.5
@export var dive_strike_speed: float = 20.0
@export var dive_max_duration: float = 1.2
@export var dive_pierce_enemies: bool = true
@export var dive_invincible: bool = true

@export_group("Dive Strike Damage")
@export var dive_resonance_damage_divisor: float = 4.0
@export var dive_resonance_regen_lockout: float = 2.0
@export var dive_aoe_radius: float = 0.0
@export var dive_aoe_damage_factor: float = 0.6
@export var dive_knockback_strength: float = 1.5

@export_group("Dive Strike Frames")
@export var DIVE_HANG_FRAME: int = 91
@export var DIVE_STRIKE_FRAME: int = 91

@export_group("Dive Strike Visual")
@export var afterimage_enabled: bool = true
@export var dive_afterimage_count: int = 14
@export var dive_afterimage_color: Color = Color(0.85, 0.7, 1.0, 0.85)
@export var dive_afterimage_fade_time: float = 0.35
@export var dive_hang_bob_amplitude: float = 0.05
@export var dive_hang_scale_pulse: float = 0.04
@export var dive_trail_color: Color = Color(0.95, 0.85, 1.0, 1.0)
@export var dive_impact_color: Color = Color(0.9, 0.75, 1.0, 1.0)
@export var dive_camera_shake_strength: float = 0.03
@export var dive_camera_shake_duration: float = 0.08

@export_group("Dive Impact VFX")
@export var dive_impact_scene: PackedScene
@export var dive_impact_scale: float = 1.0
@export var dive_impact_delay: float = 0.0
@export var dive_impact_lifetime: float = 0.5
@export var dive_impact_y_offset: float = 0.3

@export_group("Dive Hitstop")
@export var dive_hitstop_on_direct_hit: float = 0.10
@export var dive_hitstop_on_impact: float = 0.15

@export_group("Dive Strike Sound")
@export var dive_hang_sound: AudioStream
@export var dive_strike_sound: AudioStream
@export var dive_impact_sound: AudioStream

const SYNERGY_ID: String = "dive_strike"

# === STATE ===
enum State { IDLE, HANG, STRIKE }
var _state: State = State.IDLE

var _dive_hang_time: float = 0.0
var _dive_strike_time: float = 0.0
var _dive_hit_enemies: Dictionary = {}
var _dive_start_pos: Vector3 = Vector3.ZERO
var _dive_afterimage_timer: float = 0.0
var _dive_afterimages_spawned: int = 0
var _dive_player_base_y: float = 0.0
var _dive_charge_particles: GPUParticles3D = null
var _dive_resonance_used: float = 0.0

# === CACHED REFERENCES ===
var _player: CharacterBody3D = null
var _sprite: Node3D = null
var _spring_arm: Node3D = null
@export var synergy_manager_path: NodePath = "../SynergyManager"
var _synergy_manager: SynergyManager = null
var _current_damage_multiplier: float = 1.0

var _has_registered_hit: bool = false
var _projected_combo: int = 0
var _projected_multiplier: float = 1.0

func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_spring_arm = get_node_or_null(spring_arm_path) as Node3D
	
	var sprite_node = get_node_or_null(sprite_path)
	if sprite_node != null:
		_sprite = sprite_node
		
	_synergy_manager = get_node_or_null(synergy_manager_path) as SynergyManager
	
	if _player == null:
		push_error("DiveStrikeComponent: Player not found at path: " + str(player_path))
	if _sprite == null:
		push_error("DiveStrikeComponent: Sprite not found at path: " + str(sprite_path))


func _physics_process(delta: float) -> void:
	match _state:
		State.HANG:
			_process_dive_hang(delta)
		State.STRIKE:
			_process_dive_strike(delta)
		State.IDLE:
			pass


# ============================================
# PUBLIC API
# ============================================

func is_active() -> bool:
	return _state != State.IDLE

func is_hanging() -> bool:
	return _state == State.HANG

func is_diving() -> bool:
	return _state == State.STRIKE


func try_start_dive() -> bool:
	if not dive_strike_enabled:
		return false
	if _state != State.IDLE:
		return false
	
	# Synergy-Manager: Heat + History updaten, Multiplier merken
	if _synergy_manager != null:
		var result := _synergy_manager.register_synergy_use(SYNERGY_ID)
		if not result.allowed:
			return false
		_current_damage_multiplier = result.damage_multiplier
		_projected_combo = result.combo_count
		_projected_multiplier = result.damage_multiplier
	else:
		_current_damage_multiplier = 1.0
		_projected_combo = 0
		_projected_multiplier = 1.0
	
	_has_registered_hit = false
	
	# Resonance verbrauchen
	_dive_resonance_used = 0.0
	if GameManager != null and GameManager.player_data != null:
		var pd: PlayerData = GameManager.player_data
		_dive_resonance_used = max(0.0, pd.current_resonance)
		pd.current_resonance = 0.0
		
		if "_resonance_regen_timer" in pd:
			pd._resonance_regen_timer = dive_resonance_regen_lockout
		
		pd.resonance_changed.emit(0, pd.max_resonance)
	
	_start_dive_hang()
	return true


## Notbremse — bricht den Dive ab, falls von außen nötig (z.B. Spieler stirbt)
func cancel(reason: String = "cancelled") -> void:
	if _state == State.IDLE:
		return
	
	_remove_dive_charge_particles()
	if _sprite:
		_sprite.modulate = Color.WHITE
	
	_state = State.IDLE
	dive_cancelled.emit(reason)


# ============================================
# DIVE HANG
# ============================================

func _start_dive_hang() -> void:
	_dive_start_pos = _player.global_position
	_dive_player_base_y = _dive_start_pos.y
	_dive_hang_time = 0.0
	_dive_hit_enemies.clear()
	_dive_afterimages_spawned = 0
	_dive_afterimage_timer = 0.0
	
	if dive_invincible and "_invincibility_timer" in _player:
		_player._invincibility_timer = max(_player._invincibility_timer, dive_hang_duration + dive_max_duration + 0.2)
	
	_show_dive_frame(DIVE_HANG_FRAME)
	_spawn_dive_charge_particles()
	_play_sound(dive_hang_sound)
	
	_state = State.HANG
	dive_started.emit()


func _process_dive_hang(delta: float) -> void:
	_dive_hang_time += delta
	
	# Schwebender Bob + subtile Scale-Pulsation
	var t: float = _dive_hang_time / dive_hang_duration
	var bob: float = sin(t * PI) * dive_hang_bob_amplitude
	_player.global_position = Vector3(_dive_start_pos.x, _dive_player_base_y + bob, _dive_start_pos.z)
	
	if _sprite:
		var pulse: float = 1.0 + sin(t * PI * 2.0) * dive_hang_scale_pulse
		var current: Color = _sprite.modulate
		_sprite.modulate = Color(pulse, pulse, pulse, current.a)
	
	_show_dive_frame(DIVE_HANG_FRAME)
	
	if _dive_hang_time >= dive_hang_duration:
		_start_dive_strike()


# ============================================
# DIVE STRIKE
# ============================================

func _start_dive_strike() -> void:
	if _sprite:
		_sprite.modulate = Color.WHITE
	
	_remove_dive_charge_particles()
	_dive_strike_time = 0.0
	_show_dive_frame(DIVE_STRIKE_FRAME)
	_play_sound(dive_strike_sound)
	
	_state = State.STRIKE


func _process_dive_strike(delta: float) -> void:
	_dive_strike_time += delta
	
	var current_pos: Vector3 = _player.global_position
	var movement_y: float = -dive_strike_speed * delta
	var new_pos: Vector3 = current_pos + Vector3(0, movement_y, 0)
	
	var space_state := _player.get_world_3d().direct_space_state
	
	# ─── Step 1: SWEPT RAY für Boden-Detection ───
	var ray_start: Vector3 = current_pos + Vector3(0, 0.5, 0)
	var ray_end: Vector3 = new_pos + Vector3(0, -0.2, 0)
	
	var ray_query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	ray_query.collision_mask = _player.collision_mask
	ray_query.exclude = [_player.get_rid()]
	ray_query.hit_back_faces = false
	
	var ray_hit := space_state.intersect_ray(ray_query)
	
	var hit_ground: bool = false
	var ground_pos: Vector3 = new_pos
	
	if not ray_hit.is_empty():
		var ground_collider = ray_hit.get("collider")
		if ground_collider != null and is_instance_valid(ground_collider):
			var ground_is_enemy: bool = ground_collider is Enemy \
				or ground_collider.is_in_group("enemies") \
				or ground_collider.is_in_group("enemy")
			if not ground_is_enemy:
				hit_ground = true
				ground_pos = ray_hit.position
	
	# ─── Step 2: Sphere-Check für Enemy-Hits ───
	var shape_query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape_query.shape = sphere
	var sweep_center: Vector3 = current_pos.lerp(new_pos, 0.5) + Vector3(0, 0.3, 0)
	shape_query.transform = Transform3D(Basis(), sweep_center)
	shape_query.collision_mask = _player.collision_mask
	shape_query.exclude = [_player.get_rid()]
	
	var enemy_results := space_state.intersect_shape(shape_query, 8)
	for result in enemy_results:
		var collider = result.get("collider")
		if collider == null or not is_instance_valid(collider):
			continue
		var is_enemy: bool = collider is Enemy \
			or collider.is_in_group("enemies") \
			or collider.is_in_group("enemy")
		if is_enemy:
			_try_hit_dive_enemy(collider, false)
			if not dive_pierce_enemies:
				hit_ground = true
				ground_pos = new_pos
	
	# ─── Safety-Timeout ───
	if _dive_strike_time >= dive_max_duration:
		print("[Dive Strike] Timeout — kein Boden in ", dive_max_duration, "s gefunden")
		hit_ground = true
		var rescue_ray := PhysicsRayQueryParameters3D.create(
			current_pos + Vector3(0, 0.5, 0),
			current_pos + Vector3(0, -50.0, 0)
		)
		rescue_ray.collision_mask = _player.collision_mask
		rescue_ray.exclude = [_player.get_rid()]
		var rescue_hit := space_state.intersect_ray(rescue_ray)
		if not rescue_hit.is_empty():
			ground_pos = rescue_hit.position
		else:
			ground_pos = current_pos
	
	if hit_ground:
		_on_dive_impact(ground_pos)
		return
	
	_player.global_position = new_pos
	
	# Afterimages
	if afterimage_enabled and _sprite != null and _dive_afterimages_spawned < dive_afterimage_count:
		var interval: float = (dive_max_duration * 0.7) / float(dive_afterimage_count)
		_dive_afterimage_timer += delta
		if _dive_afterimage_timer >= interval:
			_spawn_dive_afterimage()
			_dive_afterimage_timer = 0.0
			_dive_afterimages_spawned += 1
	
	_show_dive_frame(DIVE_STRIKE_FRAME)


func _on_dive_impact(impact_pos: Vector3) -> void:
	# Player auf Boden snapping
	var space_state := _player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		impact_pos + Vector3(0, 0.5, 0),
		impact_pos + Vector3(0, -5.0, 0)
	)
	ray.collision_mask = _player.collision_mask
	ray.exclude = [_player.get_rid()]
	var hit := space_state.intersect_ray(ray)
	
	var ground_pos: Vector3 = impact_pos
	if not hit.is_empty():
		ground_pos = hit.position + Vector3(0, 0.02, 0)
	
	_player.global_position = ground_pos
	
	# AOE Damage
	_apply_dive_aoe_damage(ground_pos)
	
	# VFX
	_spawn_dive_impact_vfx(ground_pos)
	_apply_camera_shake()
	_play_sound(dive_impact_sound)
	
	#if dive_hitstop_on_impact > 0.0 and GameEffects:
		#GameEffects.hitstop(dive_hitstop_on_impact)
	
	# Player-State zurücksetzen
	if _player.has_method("_show_idle"):
		_player._show_idle()
	if "_attack_cooldown_timer" in _player:
		_player._attack_cooldown_timer = 0.0
	
	_state = State.IDLE
	dive_completed.emit()


# ============================================
# DAMAGE
# ============================================

func _try_hit_dive_enemy(enemy: Node, is_aoe: bool) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	
	var eid: int = enemy.get_instance_id()
	if _dive_hit_enemies.has(eid):
		return
	_dive_hit_enemies[eid] = true
	
	if not enemy.has_method("take_damage"):
		return
	if "_is_dead" in enemy and enemy._is_dead:
		return
	
	# Synergie beim ersten Hit registrieren — danach nur noch Combo-Timer refreshen
	if _synergy_manager != null:
		if not _has_registered_hit:
			_synergy_manager.register_synergy_hit(_projected_combo, _projected_multiplier)
			_has_registered_hit = true
		else:
			_synergy_manager.refresh_combo_timer()
	
	var direct_damage: int = _calculate_dive_damage()
	var damage: int = direct_damage if not is_aoe else int(round(direct_damage * dive_aoe_damage_factor))
	
	enemy.take_damage(damage, _player.global_position)
	
	# Knockback
	var knockback_dir: Vector3 = enemy.global_position - _player.global_position
	knockback_dir.y = 0
	if knockback_dir.length_squared() > 0.0001:
		knockback_dir = knockback_dir.normalized()
		if "_knockback_velocity" in enemy:
			enemy._knockback_velocity += knockback_dir * dive_knockback_strength
	
	# Impact-VFX
	var impact_pos: Vector3 = enemy.global_position + Vector3(0, dive_impact_y_offset, 0)
	CombatVFXUtils.spawn_impact(self, dive_impact_scene, impact_pos, dive_impact_scale, dive_impact_delay, dive_impact_lifetime)
	
	# Hitstop bei direkten Treffern
	if not is_aoe and dive_hitstop_on_direct_hit > 0.0 and GameEffects:
		GameEffects.hitstop(dive_hitstop_on_direct_hit)


func _apply_dive_aoe_damage(impact_pos: Vector3) -> void:
	for group in ["enemies", "enemy"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D:
				var dist: float = node.global_position.distance_to(impact_pos)
				if dist <= dive_aoe_radius:
					_try_hit_dive_enemy(node, true)


func _calculate_dive_damage() -> int:
	var sword_base: int = 5
	if "sword" in _player and _player.sword != null and "attack_damage" in _player.sword:
		sword_base = _player.sword.attack_damage
	
	var normal_damage: int = sword_base
	if GameManager != null and GameManager.player_data != null and GameManager.player_data.has_method("get_attack_damage"):
		normal_damage = GameManager.player_data.get_attack_damage(sword_base)
	
	var resonance_bonus: int = int(floor(_dive_resonance_used / dive_resonance_damage_divisor))
	
	var total: float = float(normal_damage + resonance_bonus) * _current_damage_multiplier
	return int(round(total))


# ============================================
# VFX
# ============================================

func _spawn_dive_charge_particles() -> void:
	if _player == null:
		return
	
	_dive_charge_particles = GPUParticles3D.new()
	_dive_charge_particles.emitting = true
	_dive_charge_particles.amount = 20
	_dive_charge_particles.lifetime = 0.6
	_dive_charge_particles.local_coords = false
	
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.6
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 5.0
	proc.gravity = Vector3(0, 4.0, 0)
	proc.initial_velocity_min = 1.0
	proc.initial_velocity_max = 1.8
	proc.scale_min = 0.15
	proc.scale_max = 0.3
	
	var grad := Gradient.new()
	grad.add_point(0.0, Color(dive_trail_color.r, dive_trail_color.g, dive_trail_color.b, 0.0))
	grad.add_point(0.4, dive_trail_color)
	grad.add_point(1.0, Color(dive_trail_color.r, dive_trail_color.g, dive_trail_color.b, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	proc.color_ramp = grad_tex
	
	_dive_charge_particles.process_material = proc
	
	var spark := SphereMesh.new()
	spark.radius = 0.04
	spark.height = 0.08
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.emission_enabled = true
	spark_mat.emission = dive_trail_color
	spark_mat.emission_energy_multiplier = 2.5
	spark_mat.albedo_color = dive_trail_color
	spark.material = spark_mat
	_dive_charge_particles.draw_pass_1 = spark
	
	get_tree().current_scene.add_child(_dive_charge_particles)
	_dive_charge_particles.global_position = _player.global_position


func _remove_dive_charge_particles() -> void:
	if _dive_charge_particles != null and is_instance_valid(_dive_charge_particles):
		_dive_charge_particles.emitting = false
		var p := _dive_charge_particles
		get_tree().create_timer(0.6).timeout.connect(func():
			if is_instance_valid(p):
				p.queue_free()
		)
	_dive_charge_particles = null


func _spawn_dive_afterimage() -> void:
	if _sprite == null:
		return
	
	var ghost_color: Color = dive_afterimage_color
	
	if _sprite.has_method("get_all_layer_keys") and _sprite.has_method("get_layer"):
		for layer_key in _sprite.get_all_layer_keys():
			var layer_sprite = _sprite.get_layer(layer_key)
			if layer_sprite == null or not layer_sprite.visible or layer_sprite.texture == null:
				continue
			
			var ghost := Sprite3D.new()
			ghost.texture = layer_sprite.texture
			ghost.hframes = layer_sprite.hframes
			ghost.vframes = layer_sprite.vframes
			ghost.frame = layer_sprite.frame
			ghost.flip_h = layer_sprite.flip_h
			ghost.pixel_size = layer_sprite.pixel_size
			ghost.centered = true
			ghost.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			ghost.render_priority = -1
			ghost.modulate = ghost_color
			
			get_tree().current_scene.add_child(ghost)
			ghost.global_transform = layer_sprite.global_transform
			
			var tween := create_tween()
			tween.set_parallel(true)
			tween.tween_property(ghost, "modulate:a", 0.0, dive_afterimage_fade_time).set_ease(Tween.EASE_IN)
			tween.tween_property(ghost, "scale", ghost.scale * 0.85, dive_afterimage_fade_time).set_ease(Tween.EASE_IN)
			tween.chain().tween_callback(ghost.queue_free)
		return
	
	if _sprite is Sprite3D:
		var source := _sprite as Sprite3D
		if source.texture == null:
			return
		var ghost := Sprite3D.new()
		ghost.texture = source.texture
		ghost.hframes = source.hframes
		ghost.vframes = source.vframes
		ghost.frame = source.frame
		ghost.flip_h = source.flip_h
		ghost.pixel_size = source.pixel_size
		ghost.centered = source.centered
		ghost.billboard = source.billboard
		ghost.modulate = ghost_color
		get_tree().current_scene.add_child(ghost)
		ghost.global_transform = source.global_transform
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(ghost, "modulate:a", 0.0, dive_afterimage_fade_time).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(ghost.queue_free)


func _spawn_dive_impact_vfx(pos: Vector3) -> void:
	var impact := Node3D.new()
	get_tree().current_scene.add_child(impact)
	impact.global_position = pos
	
	# Großer Bodenring
	var ring := MeshInstance3D.new()
	var ring_quad := QuadMesh.new()
	ring_quad.size = Vector2(0.3, 0.3)
	ring.mesh = ring_quad
	ring.rotation.x = -PI / 2.0
	
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = _create_impact_ring_shader()
	ring_mat.set_shader_parameter("ring_color", dive_impact_color)
	ring_mat.set_shader_parameter("progress", 0.0)
	ring_mat.set_shader_parameter("noise_seed", randf() * 100.0)
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	impact.add_child(ring)
	
	var ring2 := MeshInstance3D.new()
	var ring_quad2 := QuadMesh.new()
	ring_quad2.size = Vector2(0.2, 0.2)
	ring2.mesh = ring_quad2
	ring2.rotation.x = -PI / 2.0
	
	var ring_mat2 := ShaderMaterial.new()
	ring_mat2.shader = _create_impact_ring_shader()
	ring_mat2.set_shader_parameter("ring_color", Color(dive_impact_color.r * 1.2, dive_impact_color.g * 1.1, dive_impact_color.b, 1.0))
	ring_mat2.set_shader_parameter("progress", 0.0)
	ring_mat2.set_shader_parameter("noise_seed", randf() * 100.0 + 25.0)
	ring2.material_override = ring_mat2
	ring2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	impact.add_child(ring2)
	
	# Staubpartikel
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 16
	particles.lifetime = 0.45
	particles.explosiveness = 0.9
	
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.08
	proc.direction = Vector3(0, 0.3, 0)
	proc.spread = 70.0
	proc.flatness = 0.7
	proc.initial_velocity_min = 1.5
	proc.initial_velocity_max = 3.0
	proc.gravity = Vector3(0, -3.0, 0)
	proc.damping_min = 3.0
	proc.damping_max = 5.0
	proc.scale_min = 0.35
	proc.scale_max = 0.8
	
	var grad := Gradient.new()
	grad.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
	grad.add_point(0.25, dive_impact_color)
	grad.add_point(1.0, Color(dive_impact_color.r, dive_impact_color.g, dive_impact_color.b, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	proc.color_ramp = grad_tex
	particles.process_material = proc
	
	var spark := SphereMesh.new()
	spark.radius = 0.04
	spark.height = 0.08
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.emission_enabled = true
	spark_mat.emission = dive_impact_color
	spark_mat.emission_energy_multiplier = 2.0
	spark.material = spark_mat
	particles.draw_pass_1 = spark
	impact.add_child(particles)
	
	# Animation der Ringe
	var tween := get_tree().create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(ring, "scale", Vector3(4.5, 4.5, 4.5), 0.45).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(p: float):
		if is_instance_valid(ring_mat):
			ring_mat.set_shader_parameter("progress", p)
	, 0.0, 1.0, 0.5)
	
	tween.tween_property(ring2, "scale", Vector3(3.2, 3.2, 3.2), 0.35).set_ease(Tween.EASE_OUT).set_delay(0.06)
	tween.tween_method(func(p: float):
		if is_instance_valid(ring_mat2):
			ring_mat2.set_shader_parameter("progress", p)
	, 0.0, 1.0, 0.4).set_delay(0.08)
	
	tween.chain().tween_callback(impact.queue_free)


func _apply_camera_shake() -> void:
	if _spring_arm == null:
		return
	if _spring_arm.has_method("shake"):
		_spring_arm.shake(dive_camera_shake_strength, dive_camera_shake_duration)
		return
	
	var original_pos: Vector3 = _spring_arm.position
	var shake_tween := create_tween()
	var steps: int = 6
	for i in range(steps):
		var rand_offset := Vector3(
			randf_range(-1, 1) * dive_camera_shake_strength,
			randf_range(-1, 1) * dive_camera_shake_strength,
			0
		)
		shake_tween.tween_property(_spring_arm, "position", original_pos + rand_offset, dive_camera_shake_duration / steps)
	shake_tween.tween_property(_spring_arm, "position", original_pos, dive_camera_shake_duration / steps)


# ============================================
# FRAMES
# ============================================

func _show_dive_frame(frame_index: int) -> void:
	if _sprite == null:
		return
	_sprite.frame = frame_index


# ============================================
# SHARED HELPERS (dupliziert aus VectorAnchorComponent)
# ============================================

func _create_impact_ring_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform vec4 ring_color : source_color = vec4(0.7, 0.9, 1.0, 1.0);
uniform float progress = 0.0;
uniform float noise_seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p + noise_seed, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 2.0;
	float angle = atan(centered.y, centered.x);
	
	float ring_pos = progress * 0.85;
	float ring_width = 0.12 * (1.0 - progress * 0.6);
	
	float n1 = fbm(vec2(angle * 1.5, noise_seed)) * 0.12;
	float n2 = noise(vec2(angle * 3.0 + noise_seed * 0.3, progress * 2.0)) * 0.08;
	float n3 = noise(vec2(angle * 6.0 - noise_seed * 0.7, progress * 3.0)) * 0.04;
	
	float thickness_var = noise(vec2(angle * 2.0 + noise_seed, 0.0)) * 0.04;
	ring_width += thickness_var;
	
	float distorted_dist = dist + n1 + n2 + n3;
	float dist_to_ring = abs(distorted_dist - ring_pos);
	
	float inner_edge = smoothstep(ring_width, ring_width * 0.3, dist_to_ring);
	float outer_edge = 1.0 - smoothstep(0.0, ring_width * 0.5, dist_to_ring);
	float ring_alpha = inner_edge * outer_edge;
	
	float energy = noise(vec2(angle * 8.0 + progress * 10.0, noise_seed)) * 0.3 + 0.7;
	float inner_glow = smoothstep(ring_pos, ring_pos - ring_width * 0.5, distorted_dist) * 0.5;
	float fade = 1.0 - smoothstep(0.6, 1.0, progress);
	
	vec3 color = ring_color.rgb * energy + vec3(inner_glow);
	float alpha = ring_alpha * fade * ring_color.a;
	
	if (alpha < 0.01) {
		discard;
	}
	
	ALBEDO = color;
	ALPHA = alpha;
	EMISSION = color * (1.5 + inner_glow * 2.0);
}
"""
	return shader


func _play_sound(sound: AudioStream) -> void:
	if sound == null:
		return
	
	var audio := AudioStreamPlayer3D.new()
	audio.stream = sound
	audio.volume_db = -3.0
	_player.add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

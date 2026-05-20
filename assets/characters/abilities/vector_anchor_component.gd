extends Node
class_name VectorAnchorComponent

## Vector Anchor Component - Als Child-Node zum Player hinzufügen
## Ermöglicht dem Spieler, sich auf die gegenüberliegende Seite eines Ziels zu katapultieren

signal charging_started
signal charging_stopped
signal target_acquired(target: Node3D)
signal target_lost
signal projectile_fired(target: Node3D)
signal launch_started
signal launch_completed
signal ability_cancelled(reason: String)
signal target_confused(target: Node3D, duration: float)

# === REFERENCES ===
@export var player_path: NodePath = ".."
@export var sprite_path: NodePath = "../charactersprite"
@export var spring_arm_path: NodePath = "../SpringArm3D"

# === CHARGING SETTINGS ===
@export_group("Charging")
@export var radius_start: float = 1.0
@export var radius_max: float = 5.0
@export var radius_growth_rate: float = 1.5
@export var radius_height: float = 0.3
@export var resonance_drain_per_second: float = 10.0

@export_group("Charge Visual")
@export var charge_fade_in_time: float = 0.12
@export var charge_fade_out_time: float = 0.12
@export var charge_fade_start_scale: float = 0.92

# === PROJECTILE SETTINGS ===
@export_group("Projectile")
@export var projectile_speed: float = 25.0
@export var projectile_color: Color = Color(0.7, 0.85, 1.0, 1.0)
@export var flash_color: Color = Color(0.894, 0.596, 0.392, 1.0)

# === LAUNCH/FLIGHT SETTINGS ===
@export_group("Launch")
@export var launch_duration: float = 0.8
@export var launch_arc_height: float = 2.5
@export var launch_invincible: bool = true
@export var use_idle_frame_on_land: bool = true

# === LAUNCH DAMAGE ===
@export_group("Launch Damage")
@export var launch_damage_base: int = 6
@export var launch_damage_per_attunement: float = 1.2
@export var launch_knockback_strength: float = 2.5
@export var launch_pierce_enemies: bool = true

# === ENEMY CONFUSION ===
@export_group("Enemy Confusion")
@export var confuse_enemy: bool = true
@export var confusion_duration: float = 1.0
@export var confusion_trigger_point: float = 0.4

# === COLLISION ===
@export_group("Collision")
@export var collision_delay: float = 0.15

# === AFTERIMAGE SETTINGS ===
@export_group("Afterimage")
@export var afterimage_enabled: bool = true
@export var afterimage_count: int = 8
@export var afterimage_color: Color = Color(0.6, 0.85, 1.0, 0.85)
@export var afterimage_fade_time: float = 0.3

# === FRAME INDICES ===
@export_group("Frames - Charging/Release")
@export var use_custom_charge_frames: bool = false
@export var CHARGE_DOWN_FRAME: int = 0
@export var CHARGE_UP_FRAME: int = 9
@export var CHARGE_SIDE_FRAME: int = 18
@export var CHARGE_DOWN_LEFT_FRAME: int = 54
@export var CHARGE_UP_RIGHT_FRAME: int = 63

@export_group("Frames - In Air")
@export var use_custom_air_frames: bool = false
@export var AIR_DOWN_FRAME: int = 0
@export var AIR_UP_FRAME: int = 9
@export var AIR_SIDE_FRAME: int = 18
@export var AIR_DOWN_LEFT_FRAME: int = 54
@export var AIR_UP_RIGHT_FRAME: int = 63

# === TARGET INDICATOR ===
@export_group("Target Indicator")
@export var target_indicator_y_offset: float = 0.35
@export var target_indicator_size: float = 0.55
@export var target_indicator_fill_color: Color = Color(0.55, 0.82, 1.0, 1.0)
@export var target_indicator_highlight_color: Color = Color(0.92, 0.98, 1.0, 1.0)
@export var target_indicator_outline_color: Color = Color(0.03, 0.05, 0.11, 1.0)
@export var target_indicator_outline_thickness: float = 0.055
@export var target_indicator_bob_amplitude: float = 0.07
@export var target_indicator_bob_speed: float = 3.2
@export var target_indicator_pop_in_time: float = 0.18

@export_group("Bounce")
@export var bounce_enabled: bool = true
@export var bounce_speed_multiplier: float = 0.35  # Wie viel der Restgeschwindigkeit erhalten bleibt
@export var bounce_upward_kick: float = 2.0         # Vertikaler Impuls beim Abprallen
@export var bounce_gravity: float = 18.0
@export var bounce_max_duration: float = 1.6        # Sicherheits-Timeout
@export var bounce_invincible: bool = false


@export_group("Launch Impact VFX")
@export var launch_impact_scene: PackedScene
@export var launch_impact_scale: float = 0.7
@export var launch_impact_delay: float = 0.0
@export var launch_impact_lifetime: float = 0.4
@export var launch_impact_y_offset: float = 0.3

# === SOUND ===
@export_group("Sound")
@export var charge_loop_sound: AudioStream
@export var release_sound: AudioStream
@export var launch_sound: AudioStream
@export var land_sound: AudioStream

@export var dive_strike_path: NodePath = "../DiveStrikeComponent"

# === TARGETING ===
const TARGETABLE_GROUPS: Array[String] = ["enemies", "enemy", "targetable", "projectile"]

# === STATE ===
enum State { IDLE, CHARGING, PROJECTILE, LAUNCHING, DIVE_DELEGATED, BOUNCING, RECOVERY }

var _state: State = State.IDLE
var _current_radius: float = 0.0
var _charge_time: float = 0.0
var _current_target: Node3D = null
var _projectile_node: Node3D = null
var _launch_progress: float = 0.0
var _launch_start_pos: Vector3
var _launch_end_pos: Vector3
var _launch_target_pos: Vector3
var _afterimage_timer: float = 0.0
var _afterimages_spawned: int = 0
var _confusion_triggered: bool = false
var _launch_time: float = 0.0
var _hit_enemies_this_launch: Dictionary = {}  
var _bounce_velocity: Vector3 = Vector3.ZERO
var _bounce_time: float = 0.0
var _bounce_start_y: float = 0.0

# === VISUALS ===
var _radius_mesh: MeshInstance3D = null
var _charge_audio: AudioStreamPlayer3D = null
var _radius_tween: Tween = null

# === TARGET INDICATOR RUNTIME ===
var _target_indicator_root: Node3D = null
var _target_indicator_mesh: MeshInstance3D = null
var _target_indicator_material: ShaderMaterial = null
var _target_indicator_time: float = 0.0
var _target_indicator_shader: Shader = null

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
var _dive_strike: DiveStrikeComponent = null

# === 8 Directions ===
enum DirMode { DOWN, UP, LEFT, RIGHT, DOWN_LEFT, DOWN_RIGHT, UP_LEFT, UP_RIGHT }


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_spring_arm = get_node_or_null(spring_arm_path) as Node3D
	
	var sprite_node = get_node_or_null(sprite_path)
	if sprite_node != null:
		_sprite = sprite_node
		
	_dive_strike = get_node_or_null(dive_strike_path) as DiveStrikeComponent
	if _dive_strike != null:
		_dive_strike.dive_completed.connect(_on_dive_completed)
		_dive_strike.dive_cancelled.connect(_on_dive_cancelled)
	
	if _player == null:
		push_error("VectorAnchorComponent: Player not found at path: " + str(player_path))
	if _sprite == null:
		push_error("VectorAnchorComponent: Sprite not found at path: " + str(sprite_path))


func _physics_process(delta: float) -> void:
	match _state:
		State.CHARGING:
			_process_charging(delta)
		State.PROJECTILE:
			_process_projectile(delta)
		State.LAUNCHING:
			_process_launching(delta)
		State.DIVE_DELEGATED:
			pass
		State.BOUNCING:
			_process_bouncing(delta)
		State.RECOVERY:
			pass


# ============================================
# PUBLIC API
# ============================================

func start_charging() -> bool:
	if _state != State.IDLE:
		return false
	
	if _player == null:
		return false
	
	if not _has_resonance(resonance_drain_per_second * 0.016):
		ability_cancelled.emit("not_enough_resonance")
		return false
	
	_state = State.CHARGING
	_current_radius = radius_start
	_charge_time = 0.0
	_current_target = null
	
	_player.velocity = Vector3.ZERO
	
	_create_radius_visual()
	_start_charge_sound()
	
	if _player.has_method("_end_attack"):
		_player._end_attack()
	
	charging_started.emit()
	return true


func stop_charging() -> void:
	if _state != State.CHARGING:
		return
	
	charging_stopped.emit()
	
	if _current_target != null and is_instance_valid(_current_target):
		_fire_projectile()
	else:
		_cancel_ability("no_target")


func cancel() -> void:
	charging_stopped.emit()
	_cancel_ability("cancelled")


func is_active() -> bool:
	return _state != State.IDLE


func is_charging() -> bool:
	return _state == State.CHARGING


func is_launching() -> bool:
	return _state == State.LAUNCHING


func get_current_target() -> Node3D:
	return _current_target
	
func is_hanging() -> bool:
	return _dive_strike != null and _dive_strike.is_hanging()

func is_diving() -> bool:
	return _dive_strike != null and _dive_strike.is_diving()

func try_dive_strike() -> bool:
	if _state != State.LAUNCHING:
		return false
	if _dive_strike == null:
		return false

	if not _dive_strike.try_start_dive():
		return false
		
	_state = State.DIVE_DELEGATED
	
	return true


# ============================================
# CHARGING STATE
# ============================================

func _process_charging(delta: float) -> void:
	var drain: float = resonance_drain_per_second * delta
	if not _consume_resonance(drain):
		_cancel_ability("not_enough_resonance")
		return
	
	_charge_time += delta
	
	_current_radius = min(radius_max, radius_start + radius_growth_rate * _charge_time)
	_update_radius_visual()
	_update_target()
	
	if _current_target != null and is_instance_valid(_current_target):
		_sync_target_indicator()
	
	_show_charge_frame()


func _update_target() -> void:
	var best_target: Node3D = null
	var best_score: float = -INF
	
	var player_pos: Vector3 = _player.global_position
	var player_forward: Vector3 = _get_player_forward()
	
	for group in TARGETABLE_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D:
				var target_pos: Vector3 = _get_target_anchor_position(node)
				if node.has_method("is_vector_anchor_targetable") and not node.is_vector_anchor_targetable():
					continue
				var to_target: Vector3 = target_pos - player_pos
				var distance: float = to_target.length()
				
				if distance > _current_radius or distance < 0.5:
					continue
				
				var height_diff: float = abs(target_pos.y - player_pos.y)
				if height_diff > radius_height:
					continue
				
				var direction: Vector3 = to_target.normalized()
				var dot: float = direction.dot(player_forward)
				var score: float = dot * 2.0 - distance / _current_radius
				
				if score > best_score:
					best_score = score
					best_target = node
	
	if best_target != _current_target:
		if _current_target != null:
			_remove_target_indicator()
			target_lost.emit()
		
		_current_target = best_target
		
		if _current_target != null:
			_create_target_indicator()
			target_acquired.emit(_current_target)


func _get_player_forward() -> Vector3:
	var dir_mode: int = _player._last_dir_mode
	var dir2: Vector2 = Vector2.ZERO
	
	match dir_mode:
		DirMode.DOWN:
			dir2 = Vector2(0, 1)
		DirMode.UP:
			dir2 = Vector2(0, -1)
		DirMode.LEFT:
			dir2 = Vector2(-1, 0)
		DirMode.RIGHT:
			dir2 = Vector2(1, 0)
		DirMode.DOWN_LEFT:
			dir2 = Vector2(-1, 1).normalized()
		DirMode.DOWN_RIGHT:
			dir2 = Vector2(1, 1).normalized()
		DirMode.UP_LEFT:
			dir2 = Vector2(-1, -1).normalized()
		DirMode.UP_RIGHT:
			dir2 = Vector2(1, -1).normalized()
	
	if _spring_arm:
		var yaw: float = _spring_arm.rotation.y
		var forward := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		return (right * dir2.x + forward * dir2.y).normalized()
	
	return Vector3(dir2.x, 0, dir2.y).normalized()


# ============================================
# PROJECTILE STATE
# ============================================

func _fire_projectile() -> void:
	if _current_target == null:
		_cancel_ability("no_target")
		return
	
	_face_target(_current_target.global_position)
	_show_charge_frame()
	
	_remove_radius_visual()
	_stop_charge_sound()
	
	_create_projectile()
	_state = State.PROJECTILE
	
	_play_sound(release_sound)
	projectile_fired.emit(_current_target)


func _create_projectile() -> void:
	_projectile_node = Node3D.new()
	_projectile_node.name = "EnergyBeam"
	get_tree().current_scene.add_child(_projectile_node)
	
	# Zwei Layer: heller Kern + weicher äußerer Glow.
	# Beide als Billboard-Cross (zwei gekreuzte Quads) — keine Caps, keine Nähte.
	var core := MeshInstance3D.new()
	core.name = "BeamCore"
	core.mesh = _build_beam_cross_mesh(0.135)
	core.material_override = _create_beam_material(1.25, 1.4)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_projectile_node.add_child(core)
	
	var glow := MeshInstance3D.new()
	glow.name = "BeamGlow"
	glow.mesh = _build_beam_cross_mesh(0.16)
	glow.material_override = _create_beam_material(0.55, 2.2)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_projectile_node.add_child(glow)


func _build_beam_cross_mesh(thickness: float) -> ArrayMesh:
	# Zwei gekreuzte Quads in + Form. Unit-Length entlang Z,
	# die tatsächliche Länge kommt über scale.z auf der MeshInstance.
	var arr_mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	
	var h: float = 0.5
	var t: float = thickness
	
	# Horizontales Quad (liegt in XZ, Normal +Y)
	verts.append_array([
		Vector3(-t, 0.0, -h), Vector3( t, 0.0, -h),
		Vector3( t, 0.0,  h), Vector3(-t, 0.0,  h),
	])
	uvs.append_array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	])
	indices.append_array([0, 1, 2, 0, 2, 3])
	
	# Vertikales Quad (liegt in YZ, Normal +X)
	verts.append_array([
		Vector3(0.0, -t, -h), Vector3(0.0,  t, -h),
		Vector3(0.0,  t,  h), Vector3(0.0, -t,  h),
	])
	uvs.append_array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	])
	indices.append_array([4, 5, 6, 4, 6, 7])
	
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh


func _create_beam_material(brightness: float, softness: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _get_beam_shader()
	mat.set_shader_parameter("beam_color", projectile_color)
	mat.set_shader_parameter("brightness", brightness)
	mat.set_shader_parameter("softness", softness)
	mat.set_shader_parameter("time", 0.0)
	return mat

var _beam_shader_cache: Shader = null

func _get_beam_shader() -> Shader:
	if _beam_shader_cache != null:
		return _beam_shader_cache
	_beam_shader_cache = Shader.new()
	_beam_shader_cache.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(0.7, 0.9, 1.0, 1.0);
uniform float brightness = 1.0;
uniform float softness = 1.5;
uniform float time = 0.0;

void fragment() {
	float width_dist = abs(UV.x - 0.5) * 2.0;
	float width_falloff = pow(max(0.0, 1.0 - width_dist), softness);
	
	// Weicher Taper an beiden Enden — kein hartes Abschneiden
	float length_mask = smoothstep(0.0, 0.05, UV.y) * smoothstep(1.0, 0.94, UV.y);
	
	// Energiefluss entlang der Länge
	float flow = fract(UV.y * 3.5 - time * 7.0);
	float striation = 0.80 + smoothstep(0.25, 0.0, abs(flow - 0.5)) * 0.4;
	
	// Hochfrequentes Flackern für Plasma-Gefühl
	float flicker = 0.92 + sin(time * 28.0) * 0.06 + sin(time * 41.0) * 0.03;
	
	// Heißer weißer Kern, kalte Farbe nach außen
	vec3 hot = mix(beam_color.rgb, vec3(1.0), pow(width_falloff, 3.0));
	vec3 col = mix(beam_color.rgb, hot, width_falloff);
	
	float intensity = width_falloff * length_mask * striation * flicker * brightness;
	
	// blend_add addiert ALBEDO direkt zum Framebuffer — Intensität modulieren wir über die Farbe
	ALBEDO = col * intensity;
	ALPHA = 1.0;
	EMISSION = col * intensity * 1.8;
}
"""
	return _beam_shader_cache



func _process_projectile(delta: float) -> void:
	if _projectile_node == null or _current_target == null:
		_cancel_ability("projectile_lost")
		return
	
	if not is_instance_valid(_current_target):
		_cancel_ability("target_invalid")
		return
	
	var player_pos: Vector3 = _player.global_position + Vector3(0, 0.5, 0)
	var target_pos: Vector3 = _get_target_anchor_position(_current_target) + Vector3(0, 0.3, 0)
	var total_distance: float = player_pos.distance_to(target_pos)
	var direction: Vector3 = (target_pos - player_pos).normalized()
	
	var current_time: float = Time.get_ticks_msec() / 1000.0
	
	if not _projectile_node.has_meta("start_time"):
		_projectile_node.set_meta("start_time", current_time)
	
	var start_time: float = _projectile_node.get_meta("start_time")
	var elapsed: float = current_time - start_time
	var beam_head_dist: float = elapsed * projectile_speed
	
	if beam_head_dist >= total_distance:
		_on_projectile_hit()
		return
	
	var beam_length: float = beam_head_dist
	var beam_center: Vector3 = player_pos + direction * (beam_length * 0.5)
	
	_projectile_node.global_position = beam_center
	_projectile_node.look_at(target_pos, Vector3.UP)
	
	var core := _projectile_node.get_node_or_null("BeamCore") as MeshInstance3D
	if core:
		core.scale = Vector3(1.0, 1.0, beam_length)
		if core.material_override is ShaderMaterial:
			core.material_override.set_shader_parameter("time", current_time)
	
	var glow := _projectile_node.get_node_or_null("BeamGlow") as MeshInstance3D
	if glow:
		glow.scale = Vector3(1.0, 1.0, beam_length)
		if glow.material_override is ShaderMaterial:
			glow.material_override.set_shader_parameter("time", current_time)


func _on_projectile_hit() -> void:
	if _projectile_node:
		_spawn_impact_effect(_projectile_node.global_position)
		_projectile_node.queue_free()
		_projectile_node = null
	
	_remove_target_indicator()
	
	if _current_target.is_in_group("projectile"):
		_reflect_projectile(_current_target)
		_cancel_ability("projectile_reflected")
		return
		
	if _current_target.has_method("vector_anchor_blocks") and _current_target.vector_anchor_blocks():
		var blocker: Node = _current_target
		_cancel_ability("blocked")              # Komponente zuerst sauber zurück auf IDLE
		if blocker.has_method("on_vector_anchor_blocked"):
			blocker.on_vector_anchor_blocked(_player)
		return
	
	_start_launch()


func _reflect_projectile(projectile: Node3D) -> void:
	if projectile.has_method("reflect"):
		projectile.reflect()
	elif projectile.get("velocity") != null:
		projectile.velocity = -projectile.velocity


# ============================================
# LAUNCH STATE
# ============================================

func _start_launch() -> void:
	_hit_enemies_this_launch.clear()
	
	if _current_target == null or not is_instance_valid(_current_target):
		print("[VectorAnchor] _start_launch ABORT: target invalid")
		_cancel_ability("target_invalid")
		return
	
	var start_pos: Vector3 = _player.global_position
	var target_pos: Vector3 = _get_target_anchor_position(_current_target)
	
	var end_pos: Vector3 = target_pos * 2.0 - start_pos
	end_pos.y = start_pos.y
	
	print("[VectorAnchor] Launch attempt:")
	print("  start_pos=", start_pos)
	print("  target_pos=", target_pos)
	print("  end_pos=", end_pos)
	print("  distance=", start_pos.distance_to(end_pos))
	
	var space_state := _player.get_world_3d().direct_space_state
	var exclude_rids: Array = [_player.get_rid()]
	# Feinere Fallbacks, inklusive sehr kurzer Distanzen hinter dem Target
	var test_positions: Array[Vector3] = [end_pos]
	var dir_to_end: Vector3 = (end_pos - target_pos).normalized()
	for dist in [2.0, 1.5, 1.2, 0.9, 0.7, 0.5, 0.3]:
		var alt: Vector3 = target_pos + dir_to_end * dist
		alt.y = start_pos.y
		test_positions.append(alt)
	
	var resolved_end_pos: Vector3 = Vector3.ZERO
	var found_valid: bool = false
	
	for candidate in test_positions:
		var result := _check_launch_destination(candidate, exclude_rids)
		if result.valid:
			resolved_end_pos = result.position
			found_valid = true
			print("  Ziel OK bei ", candidate, " → Landepunkt=", resolved_end_pos)
			break
		else:
			print("  Ziel blockiert bei ", candidate, ": ", result.reason)
	
	# Letzter Ausweg: In-Place-Launch. Der Spieler bleibt fast stehen,
	# aber alle Gameplay-Effekte (Enemy-Confusion, Hit-Damage, VFX) laufen normal ab.
	if not found_valid:
		print("[VectorAnchor] Alle Positionen blockiert — In-Place-Launch")
		resolved_end_pos = start_pos
	
	end_pos = resolved_end_pos
	print("[VectorAnchor] Launch START → end_pos=", end_pos)
	
	_state = State.LAUNCHING
	_launch_progress = 0.0
	_afterimage_timer = 0.0
	_afterimages_spawned = 0
	_confusion_triggered = false
	_launch_time = 0.0
	
	_launch_start_pos = start_pos
	_launch_target_pos = target_pos
	_launch_end_pos = end_pos
	
	if launch_invincible:
		_player._invincibility_timer = max(_player._invincibility_timer, launch_duration + 0.1)
	
	_play_sound(launch_sound)
	launch_started.emit()

func _check_launch_destination(candidate: Vector3, exclude_rids: Array) -> Dictionary:
	# Schritt 1: Raycast nach unten um echten Boden zu finden.
	# Wir starten etwas über dem Kandidaten und strahlen weit nach unten.
	var space_state := _player.get_world_3d().direct_space_state
	var ray_start: Vector3 = candidate + Vector3(0, 1.0, 0)
	var ray_end: Vector3 = candidate + Vector3(0, -3.0, 0)
	
	var ray_query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	ray_query.collision_mask = _player.collision_mask
	ray_query.exclude = exclude_rids
	ray_query.hit_back_faces = false
	
	var hit := space_state.intersect_ray(ray_query)
	if hit.is_empty():
		return {"valid": false, "reason": "kein Boden gefunden", "position": candidate}
	
	var ground_y: float = hit.position.y
	
	# Zu weit unterhalb oder oberhalb der Ausgangshöhe → Klippe oder Wand über uns
	var y_diff: float = ground_y - candidate.y
	if y_diff > 0.8:
		return {"valid": false, "reason": "Boden zu hoch (+%.2fm)" % y_diff, "position": candidate}
	if y_diff < -2.0:
		return {"valid": false, "reason": "Boden zu tief (%.2fm)" % y_diff, "position": candidate}
	
	# Schritt 2: Prüfe, ob auf Kopfhöhe des Players Freiraum ist.
	# Kleine Sphere 0.9m über dem tatsächlichen Boden.
	var head_check_pos: Vector3 = Vector3(candidate.x, ground_y + 0.9, candidate.z)
	var shape_query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	shape_query.shape = sphere
	shape_query.transform = Transform3D(Basis(), head_check_pos)
	shape_query.collision_mask = _player.collision_mask
	shape_query.exclude = exclude_rids
	
	var head_results := space_state.intersect_shape(shape_query, 1)
	if head_results.size() > 0:
		return {"valid": false, "reason": "Kopfhöhe blockiert", "position": candidate}
	
	# Landepunkt leicht über dem Boden, damit Player nicht reinclippt
	var landing: Vector3 = Vector3(candidate.x, ground_y + 0.02, candidate.z)
	return {"valid": true, "reason": "Bodenkontakt", "position": landing}

func _process_launching(delta: float) -> void:
	_launch_progress += delta / launch_duration
	_launch_time += delta
	
	if _launch_progress >= 1.0:
		_complete_launch()
		return
	
	if confuse_enemy and not _confusion_triggered and _launch_progress >= confusion_trigger_point:
		if _current_target != null and is_instance_valid(_current_target):
			_confuse_target(_current_target)
		_confusion_triggered = true
	
	var t: float = _launch_progress
	var horizontal_pos: Vector3 = _launch_start_pos.lerp(_launch_end_pos, t)
	var arc: float = 4.0 * launch_arc_height * t * (1.0 - t)
	
	var new_pos: Vector3 = horizontal_pos
	new_pos.y = _launch_start_pos.y + arc
	
	if _launch_time >= collision_delay:
		var space_state := _player.get_world_3d().direct_space_state
		var shape_query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.3
		shape_query.shape = sphere
		shape_query.transform = Transform3D(Basis(), new_pos + Vector3(0, 0.3, 0))
		shape_query.collision_mask = _player.collision_mask
		shape_query.exclude = [_player.get_rid()]
		
		# Bis zu 8 Kollisionen pro Frame einsammeln, sodass Wand + Enemy gleichzeitig erkannt werden
		var results := space_state.intersect_shape(shape_query, 8)
		
		var blocking_hit := false
		for result in results:
			var collider = result.get("collider")
			if collider == null or not is_instance_valid(collider):
				continue
			
			var is_enemy: bool = collider is Enemy \
				or collider.is_in_group("enemies") \
				or collider.is_in_group("enemy")
			
			if is_enemy:
				_try_hit_launch_enemy(collider)
				if not launch_pierce_enemies:
					blocking_hit = true
			else:
				blocking_hit = true
		
		if blocking_hit:
			if bounce_enabled:
				_start_bounce(new_pos)
			else:
				_face_target(_launch_target_pos)
				if _player.has_method("_show_idle"):
					_player._show_idle()
				
				if "_attack_cooldown_timer" in _player:
					_player._attack_cooldown_timer = 0.0
				
				_state = State.IDLE
				_current_target = null
				
				ability_cancelled.emit("collision")
			return
	
	_player.global_position = new_pos
	
	if afterimage_enabled and _sprite != null:
		var afterimage_interval: float = launch_duration / float(afterimage_count)
		_afterimage_timer += delta
		if _afterimage_timer >= afterimage_interval and _afterimages_spawned < afterimage_count:
			_spawn_afterimage()
			_afterimage_timer = 0.0
			_afterimages_spawned += 1
	
	_show_air_frame()


func _complete_launch() -> void:
	_player.global_position = _launch_end_pos
	
	if confuse_enemy and not _confusion_triggered:
		if _current_target != null and is_instance_valid(_current_target):
			_confuse_target(_current_target)
	
	_face_target(_launch_target_pos)
	
	if use_idle_frame_on_land and _player.has_method("_show_idle"):
		_player._show_idle()
	
	if "_attack_cooldown_timer" in _player:
		_player._attack_cooldown_timer = 0.0
	
	_play_sound(land_sound)
	
	_state = State.IDLE
	_current_target = null
	
	launch_completed.emit()

func _start_bounce(collision_pos: Vector3) -> void:
	# Aktuelle Flugrichtung schätzen aus dem Launch-Vektor
	var flight_dir: Vector3 = _launch_end_pos - _launch_start_pos
	flight_dir.y = 0.0
	
	if flight_dir.length_squared() < 0.0001:
		# Edge case: kein klarer Vektor — fallback auf Richtung weg vom Target
		flight_dir = _player.global_position - _launch_target_pos
		flight_dir.y = 0.0
	
	if flight_dir.length_squared() < 0.0001:
		# Immer noch nichts — gib auf, normaler Stop
		_face_target(_launch_target_pos)
		if _player.has_method("_show_idle"):
			_player._show_idle()
		_state = State.IDLE
		_current_target = null
		ability_cancelled.emit("collision")
		return
	
	flight_dir = flight_dir.normalized()
	
	# Restgeschwindigkeit aus Launch-Parametern abschätzen
	var launch_distance: float = _launch_start_pos.distance_to(_launch_end_pos)
	var launch_speed: float = launch_distance / launch_duration
	
	# Bounce: in entgegengesetzte horizontale Richtung + hoch
	_bounce_velocity = -flight_dir * launch_speed * bounce_speed_multiplier
	_bounce_velocity.y = bounce_upward_kick
	
	_bounce_time = 0.0
	_bounce_start_y = _launch_start_pos.y
	
	# Player leicht zurücksetzen damit er nicht direkt wieder kollidiert
	_player.global_position -= flight_dir * 0.05
	
	# Invincibility verlängern falls aktiv
	if bounce_invincible and "_invincibility_timer" in _player:
		_player._invincibility_timer = max(_player._invincibility_timer, bounce_max_duration + 0.1)
	
	_face_target(_launch_target_pos)
	if _player.has_method("_show_idle"):
		_player._show_idle()
	
	_state = State.BOUNCING


func _process_bouncing(delta: float) -> void:
	_bounce_time += delta
	
	# Schwerkraft anwenden
	_bounce_velocity.y -= bounce_gravity * delta
	
	# Bewegung berechnen
	var movement: Vector3 = _bounce_velocity * delta
	var new_pos: Vector3 = _player.global_position + movement
	
	# Horizontaler Wand-Check (verhindert Reinclippen wenn Bounce Richtung doch ungünstig ist)
	var space_state := _player.get_world_3d().direct_space_state
	var shape_query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape_query.shape = sphere
	shape_query.transform = Transform3D(Basis(), new_pos + Vector3(0, 0.3, 0))
	shape_query.collision_mask = _player.collision_mask
	shape_query.exclude = [_player.get_rid()]
	
	var results := space_state.intersect_shape(shape_query, 4)
	var hit_wall: bool = false
	for r in results:
		var collider = r.get("collider")
		if collider == null or not is_instance_valid(collider):
			continue
		# Enemies ignorieren beim Bounce — nicht doppelt schaden
		var is_enemy: bool = collider is Enemy \
			or collider.is_in_group("enemies") \
			or collider.is_in_group("enemy")
		if not is_enemy:
			hit_wall = true
			break
	
	if hit_wall:
		# Horizontale Geschwindigkeit auf null, vertikale behalten — der Player rutscht runter
		_bounce_velocity.x = 0.0
		_bounce_velocity.z = 0.0
		new_pos.x = _player.global_position.x
		new_pos.z = _player.global_position.z
	
	_player.global_position = new_pos
	
	# Bounce endet wenn: zurück auf Start-Höhe gefallen, Timeout, oder fast keine vertikale Bewegung mehr
	var falling: bool = _bounce_velocity.y < 0.0
	var below_floor: bool = _player.global_position.y <= _bounce_start_y
	var landed: bool = falling and below_floor
	var timeout: bool = _bounce_time >= bounce_max_duration
	
	if landed or timeout:
		_player.global_position.y = _bounce_start_y
		_end_bounce()


func _end_bounce() -> void:
	_bounce_velocity = Vector3.ZERO
	
	if "_attack_cooldown_timer" in _player:
		_player._attack_cooldown_timer = 0.0
	
	_state = State.IDLE
	_current_target = null
	
	ability_cancelled.emit("bounce_complete")

func _confuse_target(target: Node3D) -> void:
	target_confused.emit(target, confusion_duration)
	
	if target.has_method("apply_confusion"):
		target.apply_confusion(confusion_duration)
	elif target.has_method("stun"):
		target.stun(confusion_duration)
	elif target.has_method("set_confused"):
		target.set_confused(true, confusion_duration)
	else:
		if "_is_confused" in target:
			target._is_confused = true
			get_tree().create_timer(confusion_duration).timeout.connect(func():
				if is_instance_valid(target) and "_is_confused" in target:
					target._is_confused = false
			)

func _try_hit_launch_enemy(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	
	var eid: int = enemy.get_instance_id()
	if _hit_enemies_this_launch.has(eid):
		return
	_hit_enemies_this_launch[eid] = true
	
	if not enemy.has_method("take_damage"):
		return
	
	# Tote oder verschwindende Enemies ignorieren
	if "_is_dead" in enemy and enemy._is_dead:
		return
	
	var damage: int = _calculate_launch_damage()
	
	# take_damage setzt selbst einen kleinen Knockback basierend auf from_position.
	# Wir nutzen die Spielerposition als from_position → Knockback zeigt natürlich weg.
	enemy.take_damage(damage, _player.global_position, true)
	
	# Zusätzlicher Knockback in Flugrichtung für den "durchgeschleudert"-Effekt
	var flight_dir: Vector3 = _launch_end_pos - _launch_start_pos
	flight_dir.y = 0.0
	if flight_dir.length_squared() > 0.0001:
		flight_dir = flight_dir.normalized()
		if "_knockback_velocity" in enemy:
			enemy._knockback_velocity += flight_dir * launch_knockback_strength
			
	var impact_pos: Vector3 = (_player.global_position + enemy.global_position) * 0.5
	impact_pos.y += launch_impact_y_offset
	CombatVFXUtils.spawn_impact(self, launch_impact_scene, impact_pos, launch_impact_scale, launch_impact_delay, launch_impact_lifetime)

func _calculate_launch_damage() -> int:
	var attunement: int = 3
	if GameManager != null and GameManager.player_data != null:
		attunement = GameManager.player_data.base_attunement
	return launch_damage_base + int(round(attunement * launch_damage_per_attunement))

# ============================================
# VISUALS - RADIUS
# ============================================

func _create_radius_visual() -> void:
	_radius_mesh = MeshInstance3D.new()
	
	var quad := QuadMesh.new()
	quad.size = Vector2(_current_radius * 2.2, _current_radius * 2.2)
	_radius_mesh.mesh = quad
	
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = _create_radius_shader()
	shader_mat.set_shader_parameter("inner_color", Color(0.4, 0.75, 1.0, 0.25))
	shader_mat.set_shader_parameter("mid_color", Color(0.5, 0.85, 1.0, 0.4))
	shader_mat.set_shader_parameter("edge_color", Color(0.7, 0.95, 1.0, 0.7))
	shader_mat.set_shader_parameter("time", 0.0)
	shader_mat.set_shader_parameter("opacity", 0.0)
	shader_mat.render_priority = -5
	_radius_mesh.material_override = shader_mat
	
	_radius_mesh.rotation_degrees.x = -90
	_radius_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_radius_mesh.scale = Vector3.ONE * charge_fade_start_scale
	_radius_mesh.sorting_offset = 10.0
	
	_player.add_child(_radius_mesh)
	_radius_mesh.position = Vector3(0, 0.02, 0)
	
	if _radius_tween:
		_radius_tween.kill()
	
	_radius_tween = create_tween()
	_radius_tween.set_parallel(true)
	_radius_tween.tween_property(
		_radius_mesh,
		"scale",
		Vector3.ONE,
		charge_fade_in_time
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	_radius_tween.tween_method(func(v: float):
		if is_instance_valid(_radius_mesh):
			var mat := _radius_mesh.material_override as ShaderMaterial
			if mat:
				mat.set_shader_parameter("opacity", v)
	, 0.0, 1.0, charge_fade_in_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _create_radius_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;

uniform vec4 inner_color : source_color = vec4(0.4, 0.75, 1.0, 0.25);
uniform vec4 mid_color : source_color = vec4(0.5, 0.85, 1.0, 0.4);
uniform vec4 edge_color : source_color = vec4(0.7, 0.95, 1.0, 0.7);
uniform float time = 0.0;
uniform float opacity = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}


void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float dist = length(centered_uv) * 2.0;
	float angle = atan(centered_uv.y, centered_uv.x);
	
	float wave1 = sin(angle * 6.0 + time * 2.5) * 0.025;
	float wave2 = sin(angle * 10.0 - time * 3.2) * 0.015;
	float wave3 = sin(angle * 15.0 + time * 4.0) * 0.01;
	float wave4 = fbm(vec2(angle * 2.0, time * 0.5)) * 0.03;
	float total_wave = wave1 + wave2 + wave3 + wave4;
	
	float circle_edge = 0.88 + total_wave;
	
	if (dist > circle_edge + 0.08) {
		discard;
	}
	
	float energy_pattern = fbm(centered_uv * 8.0 + vec2(time * 0.3, time * 0.2));
	float energy_pattern2 = fbm(centered_uv * 12.0 - vec2(time * 0.4, time * 0.15));
	float combined_energy = (energy_pattern + energy_pattern2) * 0.5;
	
	float pulse1 = sin((dist * 8.0 - time * 3.0)) * 0.5 + 0.5;
	float pulse2 = sin((dist * 12.0 - time * 4.5 + 1.5)) * 0.5 + 0.5;
	float pulses = (pulse1 + pulse2) * 0.15;
	
	vec4 color;
	if (dist < 0.4) {
		color = mix(inner_color, mid_color, dist / 0.4);
	} else {
		color = mix(mid_color, edge_color, (dist - 0.4) / 0.5);
	}
	
	color.rgb += combined_energy * 0.15 * color.rgb;
	color.rgb += pulses * edge_color.rgb;
	
	float edge_fade = 1.0 - smoothstep(circle_edge - 0.1, circle_edge + 0.05, dist);
	
	float rim = smoothstep(circle_edge - 0.06, circle_edge - 0.02, dist) *
				(1.0 - smoothstep(circle_edge - 0.02, circle_edge + 0.02, dist));
	rim *= 1.5;
	
	float alpha = color.a * edge_fade;
	alpha = clamp(alpha, 0.0, 0.5);
	
	float breathe = 1.0 + sin(time * 1.8) * 0.08;
	
	vec3 final_color = color.rgb + rim * edge_color.rgb;
	float intensity = alpha * breathe * opacity;
	
	float inner_fade = smoothstep(0.12, 0.28, dist);
	
	ALBEDO = final_color * intensity;
	ALPHA = alpha * breathe * opacity * inner_fade;
	EMISSION = (color.rgb * 0.8 + rim * edge_color.rgb * 2.0) * breathe * opacity * inner_fade;
}
"""
	return shader


func _update_radius_visual() -> void:
	if _radius_mesh == null:
		return
	
	var quad: QuadMesh = _radius_mesh.mesh as QuadMesh
	if quad:
		quad.size = Vector2(_current_radius * 2.2, _current_radius * 2.2)
	
	var mat: ShaderMaterial = _radius_mesh.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("time", _charge_time)


func _remove_radius_visual() -> void:
	if _radius_mesh == null:
		return
	
	var fading_mesh := _radius_mesh
	_radius_mesh = null
	
	if _radius_tween:
		_radius_tween.kill()
		_radius_tween = null
	
	var global_xform := fading_mesh.global_transform
	var parent := fading_mesh.get_parent()
	if parent:
		parent.remove_child(fading_mesh)
		get_tree().current_scene.add_child(fading_mesh)
		fading_mesh.global_transform = global_xform
	
	var fade_tween := create_tween()
	fade_tween.set_parallel(true)
	fade_tween.tween_property(
		fading_mesh,
		"scale",
		Vector3.ONE * 0.96,
		charge_fade_out_time
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	
	fade_tween.tween_method(func(v: float):
		if is_instance_valid(fading_mesh):
			var mat := fading_mesh.material_override as ShaderMaterial
			if mat:
				mat.set_shader_parameter("opacity", v)
	, 1.0, 0.0, charge_fade_out_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	
	fade_tween.chain().tween_callback(func():
		if is_instance_valid(fading_mesh):
			fading_mesh.queue_free()
	)


# ============================================
# VISUALS - TARGET INDICATOR
# ============================================

func _create_target_indicator() -> void:
	if _current_target == null or not is_instance_valid(_current_target):
		return
	
	_remove_target_indicator()
	
	_target_indicator_root = Node3D.new()
	_target_indicator_root.name = "VectorAnchorArrow"
	get_tree().current_scene.add_child(_target_indicator_root)
	
	_target_indicator_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(target_indicator_size, target_indicator_size)
	_target_indicator_mesh.mesh = quad
	_target_indicator_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_target_indicator_mesh.sorting_offset = 1.0  # leicht bevorzugt sortiert
	
	_target_indicator_material = ShaderMaterial.new()
	_target_indicator_material.shader = _get_target_arrow_shader()
	_target_indicator_material.set_shader_parameter("fill_color", target_indicator_fill_color)
	_target_indicator_material.set_shader_parameter("highlight_color", target_indicator_highlight_color)
	_target_indicator_material.set_shader_parameter("outline_color", target_indicator_outline_color)
	_target_indicator_material.set_shader_parameter("outline_thickness", target_indicator_outline_thickness)
	_target_indicator_material.set_shader_parameter("time", 0.0)
	_target_indicator_mesh.material_override = _target_indicator_material
	
	_target_indicator_root.add_child(_target_indicator_mesh)
	_target_indicator_time = 0.0
	
	# Scale pop-in
	_target_indicator_root.scale = Vector3(0.001, 0.001, 0.001)
	var pop_tween := create_tween()
	pop_tween.tween_property(
		_target_indicator_root,
		"scale",
		Vector3.ONE,
		target_indicator_pop_in_time
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	_sync_target_indicator()


func _sync_target_indicator() -> void:
	if _target_indicator_root == null or not is_instance_valid(_target_indicator_root):
		return
	if _current_target == null or not is_instance_valid(_current_target):
		_remove_target_indicator()
		return
	
	_target_indicator_time += get_physics_process_delta_time()
	
	# Position: schwebend über dem Ziel + Bob
	var bob: float = sin(_target_indicator_time * target_indicator_bob_speed) * target_indicator_bob_amplitude
	var target_pos: Vector3 = _get_target_indicator_position(_current_target)
	_target_indicator_root.global_position = target_pos + Vector3(0.0, target_indicator_y_offset + bob, 0.0)
	
	# Y-Achsen-Billboard (Arrow zeigt immer nach unten, dreht sich aber zur Kamera)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var to_cam: Vector3 = cam.global_position - _target_indicator_root.global_position
		to_cam.y = 0.0
		if to_cam.length_squared() > 0.0001:
			var yaw: float = atan2(to_cam.x, to_cam.z)
			_target_indicator_root.rotation = Vector3(0.0, yaw, 0.0)
	
	if _target_indicator_material:
		_target_indicator_material.set_shader_parameter("time", _target_indicator_time)


func _remove_target_indicator() -> void:
	if _target_indicator_root != null and is_instance_valid(_target_indicator_root):
		_target_indicator_root.queue_free()
	_target_indicator_root = null
	_target_indicator_mesh = null
	_target_indicator_material = null


func _get_target_arrow_shader() -> Shader:
	if _target_indicator_shader == null:
		_target_indicator_shader = _create_target_arrow_shader()
	return _target_indicator_shader


func _create_target_arrow_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_test_disabled, blend_mix;

uniform vec4 fill_color : source_color = vec4(0.55, 0.82, 1.0, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.92, 0.98, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(0.03, 0.05, 0.11, 1.0);
uniform float outline_thickness = 0.055;
uniform float time = 0.0;

// iq's triangle SDF
float sd_triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
	vec2 e0 = p1 - p0; vec2 e1 = p2 - p1; vec2 e2 = p0 - p2;
	vec2 v0 = p - p0;  vec2 v1 = p - p1;  vec2 v2 = p - p2;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
					 vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
					 vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

void fragment() {
	// UV [0,1] -> p [-1, 1]. In QuadMesh UV.y = 1 entspricht dem unteren Rand in Weltkoordinaten.
	vec2 p = (UV - vec2(0.5)) * 2.0;
	
	// Arrow-Dreieck: Spitze zeigt nach unten (positives p.y = unten im world)
	vec2 tip = vec2(0.0, 0.72);
	vec2 base_l = vec2(-0.62, -0.22);
	vec2 base_r = vec2(0.62, -0.22);
	
	float d = sd_triangle(p, tip, base_l, base_r);
	float aa = max(fwidth(d) * 1.1, 0.002);
	
	// Inner + Outline Masken
	float inside_mask = smoothstep(aa, -aa, d);
	float outer_edge = smoothstep(outline_thickness + aa, outline_thickness - aa, d);
	float outline_mask = clamp(outer_edge - inside_mask, 0.0, 1.0);
	
	// Subtiler Gradient auf der Füllung (oben heller, Spitze voller Ton)
	float fill_grad = smoothstep(-0.25, 0.72, p.y);
	vec3 fill_rgb = mix(highlight_color.rgb, fill_color.rgb, fill_grad);
	
	// Rim highlight nahe der Innenkante (glänzender Look)
	float rim = smoothstep(0.0, -0.09, d) - smoothstep(-0.09, -0.18, d);
	rim = clamp(rim, 0.0, 1.0);
	fill_rgb = mix(fill_rgb, highlight_color.rgb, rim * 0.45);
	
	// Sanftes Pulsieren
	float pulse = 0.88 + sin(time * 3.6) * 0.12;
	
	// Finaler Composite
	vec3 col = fill_rgb * pulse;
	float alpha = inside_mask;
	
	if (outline_mask > 0.001) {
		col = mix(col, outline_color.rgb, outline_mask);
		alpha = max(alpha, outline_mask * outline_color.a);
	}
	
	if (alpha < 0.01) {
		discard;
	}
	
	ALBEDO = col;
	ALPHA = alpha;
	EMISSION = fill_rgb * inside_mask * 0.55 * pulse;
}
"""
	return shader

# ============================================
# VISUALS - EFFECTS
# ============================================

func _spawn_impact_effect(pos: Vector3) -> void:
	var impact := Node3D.new()
	impact.name = "ImpactEffect"
	get_tree().current_scene.add_child(impact)
	
	#var bob: float = sin(_target_indicator_time * target_indicator_bob_speed) * target_indicator_bob_amplitude
	var target_pos: Vector3 = _current_target.global_position
	#_target_indicator_root.global_position = target_pos + Vector3(0.0, target_indicator_y_offset + bob, 0.0)
	
	
	impact.global_position = target_pos
	
	var light := OmniLight3D.new()
	light.light_color = projectile_color
	light.light_energy = 6.0
	light.omni_range = 2.0
	light.omni_attenuation = 2.0
	#impact.add_child(light)
	
	var flash_sphere := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	flash_sphere.mesh = sphere
	
	var flash_mat := ShaderMaterial.new()
	flash_mat.shader = _create_impact_flash_shader()
	flash_mat.set_shader_parameter("flash_color", projectile_color)
	flash_mat.set_shader_parameter("time", 0.0)
	flash_sphere.material_override = flash_mat
	flash_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	#impact.add_child(flash_sphere)
	
	var ring := MeshInstance3D.new()
	ring.name = "RingWave"
	var ring_quad := QuadMesh.new()
	ring_quad.size = Vector2(0.6, 0.6)
	ring.mesh = ring_quad
	ring.rotation.x = -PI / 2.0
	
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = _create_impact_ring_shader()
	ring_mat.set_shader_parameter("ring_color", flash_color) 
	ring_mat.set_shader_parameter("progress", 0.0)
	ring_mat.set_shader_parameter("noise_seed", randf() * 100.0)
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	impact.add_child(ring)
	
	var ring2 := MeshInstance3D.new()
	ring2.name = "RingWave2"
	var ring_quad2 := QuadMesh.new()
	ring_quad2.size = Vector2(0.5, 0.5)
	ring2.mesh = ring_quad2
	ring2.rotation.x = -PI / 2.0
	
	var ring_mat2 := ShaderMaterial.new()
	ring_mat2.shader = _create_impact_ring_shader()
	ring_mat2.set_shader_parameter("ring_color", Color(projectile_color.r * 1.3, projectile_color.g * 1.1, projectile_color.b, 1.0))
	ring_mat2.set_shader_parameter("progress", 0.0)
	ring_mat2.set_shader_parameter("noise_seed", randf() * 100.0 + 50.0)
	ring2.material_override = ring_mat2
	ring2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	impact.add_child(ring2)
	
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 24
	particles.lifetime = 0.5
	particles.explosiveness = 0.95
	
	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.direction = Vector3(0, 0.5, 0)
	proc_mat.spread = 180.0
	proc_mat.initial_velocity_min = 2.0
	proc_mat.initial_velocity_max = 4.0
	proc_mat.gravity = Vector3(0, -4, 0)
	proc_mat.damping_min = 2.0
	proc_mat.damping_max = 4.0
	proc_mat.scale_min = 0.4
	proc_mat.scale_max = 1.0
	
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.2, projectile_color)
	gradient.add_point(1.0, Color(projectile_color.r, projectile_color.g, projectile_color.b, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	proc_mat.color_ramp = gradient_tex
	
	particles.process_material = proc_mat
	
	var spark := SphereMesh.new()
	spark.radius = 0.03
	spark.height = 0.06
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.emission_enabled = true
	spark_mat.emission = projectile_color
	spark_mat.emission_energy_multiplier = 2.0
	spark.material = spark_mat
	particles.draw_pass_1 = spark
	impact.add_child(particles)
	
	# Kugelförmige Schockwelle (expandierender Hohlkörper — kein Oval-Problem)
	var shock := MeshInstance3D.new()
	shock.name = "Shockwave"
	var shock_sphere := SphereMesh.new()
	shock_sphere.radius = 0.25
	shock_sphere.height = 0.5
	shock_sphere.radial_segments = 24
	shock_sphere.rings = 12
	shock.mesh = shock_sphere
	
	var shock_mat := StandardMaterial3D.new()
	shock_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shock_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shock_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shock_mat.albedo_color = Color(projectile_color.r, projectile_color.g, projectile_color.b, 0.35)
	shock_mat.emission_enabled = true
	shock_mat.emission = projectile_color
	shock_mat.emission_energy_multiplier = 2.5
	shock_mat.cull_mode = BaseMaterial3D.CULL_FRONT  # nur Rückseiten = Hohlkörper-Effekt
	shock.material_override = shock_mat
	shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	#impact.add_child(shock)
	
	var tween := get_tree().create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(light, "light_energy", 0.0, 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash_sphere, "scale", Vector3(2.0, 2.0, 2.0), 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(t: float):
		if is_instance_valid(flash_mat):
			flash_mat.set_shader_parameter("time", t)
	, 0.0, 1.0, 0.25)
	
	tween.tween_property(ring, "scale", Vector3(6.0, 6.0, 6.0), 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(p: float):
		if is_instance_valid(ring_mat):
			ring_mat.set_shader_parameter("progress", p)
	, 0.0, 1.0, 0.4)
	
	tween.tween_property(ring2, "scale", Vector3(5.0, 5.0, 5.0), 0.35).set_ease(Tween.EASE_OUT).set_delay(0.06)
	tween.tween_method(func(p: float):
		if is_instance_valid(ring_mat2):
			ring_mat2.set_shader_parameter("progress", p)
	, 0.0, 1.0, 0.35).set_delay(0.06)
	
	tween.chain().tween_callback(impact.queue_free)
	
	tween.tween_property(shock, "scale", Vector3(3.5, 3.5, 3.5), 0.35).set_ease(Tween.EASE_OUT)
	tween.tween_property(shock_mat, "albedo_color:a", 0.0, 0.35).set_ease(Tween.EASE_OUT)


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


func _create_impact_flash_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 flash_color : source_color = vec4(0.7, 0.9, 1.0, 1.0);
uniform float time = 0.0;

void fragment() {
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float fade = 1.0 - smoothstep(0.0, 1.0, time);
	float core = 1.0 - fresnel * 0.5;
	
	vec3 color = flash_color.rgb * core;
	float alpha = fade * (0.8 + fresnel * 0.2);
	
	ALBEDO = color;
	ALPHA = alpha * flash_color.a;
	EMISSION = color * (3.0 + fresnel * 2.0) * fade;
}
"""
	return shader


func _spawn_afterimage() -> void:
	if _sprite == null:
		return
	
	var flight_dir: Vector3 = (_launch_end_pos - _launch_start_pos)
	flight_dir.y = 0.0
	if flight_dir.length_squared() > 0.0001:
		flight_dir = flight_dir.normalized()
	else:
		flight_dir = Vector3.ZERO
	
	if _sprite.has_method("get_all_layer_keys") and _sprite.has_method("get_layer"):
		for layer_key in _sprite.get_all_layer_keys():
			var layer_sprite = _sprite.get_layer(layer_key)
			if layer_sprite == null or not layer_sprite.visible:
				continue
			if layer_sprite.texture == null:
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
			ghost.modulate = afterimage_color
			
			get_tree().current_scene.add_child(ghost)
			ghost.global_transform = layer_sprite.global_transform
			
			ghost.global_position -= flight_dir * 0.02 * float(_afterimages_spawned + 1)
			ghost.global_position.y = layer_sprite.global_position.y
			
			var tween := create_tween()
			tween.set_parallel(true)
			tween.tween_property(ghost, "modulate:a", 0.0, afterimage_fade_time).set_ease(Tween.EASE_IN)
			tween.tween_property(ghost, "scale", ghost.scale * 0.8, afterimage_fade_time).set_ease(Tween.EASE_IN)
			
			var end_pos: Vector3 = ghost.global_position + Vector3(0, 0.1, 0)
			tween.tween_property(ghost, "global_position", end_pos, afterimage_fade_time).set_ease(Tween.EASE_OUT)
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
		ghost.flip_v = source.flip_v
		ghost.pixel_size = source.pixel_size
		ghost.centered = source.centered
		ghost.billboard = source.billboard
		ghost.render_priority = source.render_priority - 1
		ghost.modulate = afterimage_color
		
		get_tree().current_scene.add_child(ghost)
		ghost.global_transform = source.global_transform
		ghost.global_position -= flight_dir * 0.02 * float(_afterimages_spawned + 1)
		
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(ghost, "modulate:a", 0.0, afterimage_fade_time).set_ease(Tween.EASE_IN)
		tween.tween_property(ghost, "scale", ghost.scale * 0.8, afterimage_fade_time).set_ease(Tween.EASE_IN)
		
		var end_pos: Vector3 = ghost.global_position + Vector3(0, 0.1, 0)
		tween.tween_property(ghost, "global_position", end_pos, afterimage_fade_time).set_ease(Tween.EASE_OUT)
		tween.chain().tween_callback(ghost.queue_free)


# ============================================
# FRAMES
# ============================================

func _show_charge_frame() -> void:
	if _sprite == null or _player == null:
		return
	
	if not use_custom_charge_frames:
		if _player.has_method("_show_idle"):
			_player._show_idle()
		return
	
	var dir_mode: int = _player._last_dir_mode
	var frame: int
	var flip: bool = false
	
	match dir_mode:
		DirMode.DOWN:
			frame = CHARGE_DOWN_FRAME
		DirMode.UP:
			frame = CHARGE_UP_FRAME
		DirMode.LEFT:
			frame = CHARGE_SIDE_FRAME
		DirMode.RIGHT:
			frame = CHARGE_SIDE_FRAME
			flip = true
		DirMode.DOWN_LEFT:
			frame = CHARGE_DOWN_LEFT_FRAME
		DirMode.DOWN_RIGHT:
			frame = CHARGE_DOWN_LEFT_FRAME
			flip = true
		DirMode.UP_RIGHT:
			frame = CHARGE_UP_RIGHT_FRAME
		DirMode.UP_LEFT:
			frame = CHARGE_UP_RIGHT_FRAME
			flip = true
		_:
			frame = CHARGE_DOWN_FRAME
	
	_sprite.frame = frame
	_sprite.flip_h = flip


func _show_air_frame() -> void:
	if _sprite == null or _player == null:
		return
	
	var to_target: Vector3 = _launch_target_pos - _player.global_position
	to_target.y = 0
	var dir_mode: int = _direction_from_vector(to_target)
	
	_player._last_dir_mode = dir_mode
	match dir_mode:
		DirMode.RIGHT, DirMode.DOWN_RIGHT, DirMode.UP_RIGHT:
			_player._facing_right = true
		DirMode.LEFT, DirMode.DOWN_LEFT, DirMode.UP_LEFT:
			_player._facing_right = false
	
	if not use_custom_air_frames:
		if _player.has_method("_show_idle"):
			_player._show_idle()
		return
	
	var frame: int
	var flip: bool = false
	
	match dir_mode:
		DirMode.DOWN:
			frame = AIR_DOWN_FRAME
		DirMode.UP:
			frame = AIR_UP_FRAME
		DirMode.LEFT:
			frame = AIR_SIDE_FRAME
		DirMode.RIGHT:
			frame = AIR_SIDE_FRAME
			flip = true
		DirMode.DOWN_LEFT:
			frame = AIR_DOWN_LEFT_FRAME
		DirMode.DOWN_RIGHT:
			frame = AIR_DOWN_LEFT_FRAME
			flip = true
		DirMode.UP_RIGHT:
			frame = AIR_UP_RIGHT_FRAME
		DirMode.UP_LEFT:
			frame = AIR_UP_RIGHT_FRAME
			flip = true
		_:
			frame = AIR_DOWN_FRAME
	
	_sprite.frame = frame
	_sprite.flip_h = flip


func _face_target(target_pos: Vector3) -> void:
	var direction: Vector3 = target_pos - _player.global_position
	direction.y = 0
	
	if direction.length_squared() < 0.001:
		return
	
	var dir_mode: int = _direction_from_vector(direction)
	_player._last_dir_mode = dir_mode
	
	match dir_mode:
		DirMode.RIGHT, DirMode.DOWN_RIGHT, DirMode.UP_RIGHT:
			_player._facing_right = true
		DirMode.LEFT, DirMode.DOWN_LEFT, DirMode.UP_LEFT:
			_player._facing_right = false


func _direction_from_vector(vec: Vector3) -> int:
	if vec.length_squared() < 0.001:
		return DirMode.DOWN
	
	var dir2: Vector2
	if _spring_arm:
		var yaw: float = _spring_arm.rotation.y
		var forward := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		dir2 = Vector2(vec.dot(right), vec.dot(forward)).normalized()
	else:
		dir2 = Vector2(vec.x, vec.z).normalized()
	
	var deg: float = rad_to_deg(dir2.angle())
	if deg < 0:
		deg += 360.0
	
	if deg >= 337.5 or deg < 22.5:
		return DirMode.RIGHT
	elif deg >= 22.5 and deg < 67.5:
		return DirMode.DOWN_RIGHT
	elif deg >= 67.5 and deg < 112.5:
		return DirMode.DOWN
	elif deg >= 112.5 and deg < 157.5:
		return DirMode.DOWN_LEFT
	elif deg >= 157.5 and deg < 202.5:
		return DirMode.LEFT
	elif deg >= 202.5 and deg < 247.5:
		return DirMode.UP_LEFT
	elif deg >= 247.5 and deg < 292.5:
		return DirMode.UP
	else:
		return DirMode.UP_RIGHT


# ============================================
# HELPERS
# ============================================

func _has_resonance(amount: float) -> bool:
	if GameManager == null or GameManager.player_data == null:
		return true
	return GameManager.player_data.current_resonance >= amount


func _consume_resonance(amount: float) -> bool:
	if GameManager == null or GameManager.player_data == null:
		return true
	
	var pd: PlayerData = GameManager.player_data
	
	if pd.current_resonance >= amount:
		pd.current_resonance -= amount
		
		if "resonance_regen_delay" in pd and "_resonance_regen_timer" in pd:
			pd._resonance_regen_timer = pd.resonance_regen_delay
		
		pd.resonance_changed.emit(int(pd.current_resonance), pd.max_resonance)
		return true
	
	return false


func _cancel_ability(reason: String) -> void:
	_remove_radius_visual()
	_remove_target_indicator()
	# _remove_dive_charge_particles()  ← DIESE ZEILE LÖSCHEN
	_stop_charge_sound()
	
	if _projectile_node:
		_projectile_node.queue_free()
		_projectile_node = null
	
	# Dive abbrechen falls aktiv
	if _dive_strike != null and _dive_strike.is_active():
		_dive_strike.cancel(reason)
	
	_state = State.IDLE
	_current_target = null
	
	ability_cancelled.emit(reason)
	

func _get_target_anchor_position(target: Node3D) -> Vector3:
	if target == null:
		return Vector3.ZERO
	if target.has_method("get_vector_anchor_anchor_position"):
		return target.get_vector_anchor_anchor_position()
	return target.global_position


func _get_target_indicator_position(target: Node3D) -> Vector3:
	if target == null:
		return Vector3.ZERO
	if target.has_method("get_vector_anchor_indicator_position"):
		return target.get_vector_anchor_indicator_position()
	return target.global_position


# ============================================
# SOUND
# ============================================

func _start_charge_sound() -> void:
	if charge_loop_sound == null:
		return
	
	_charge_audio = AudioStreamPlayer3D.new()
	_charge_audio.stream = charge_loop_sound
	_charge_audio.volume_db = -6.0
	_player.add_child(_charge_audio)
	_charge_audio.play()


func _stop_charge_sound() -> void:
	if _charge_audio:
		_charge_audio.stop()
		_charge_audio.queue_free()
		_charge_audio = null


func _play_sound(sound: AudioStream) -> void:
	if sound == null:
		return
	
	var audio := AudioStreamPlayer3D.new()
	audio.stream = sound
	audio.volume_db = -3.0
	_player.add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)
	
# ============================================
# DIVE STRIKE CALLBACKS
# ============================================

func _on_dive_completed() -> void:
	# Dive ist sauber durchgelaufen — VectorAnchor in IDLE überführen.
	_state = State.IDLE
	_current_target = null
	launch_completed.emit()


func _on_dive_cancelled(_reason: String) -> void:
	# Dive wurde abgebrochen — auch zurück in IDLE.
	_state = State.IDLE
	_current_target = null
	ability_cancelled.emit("dive_cancelled")

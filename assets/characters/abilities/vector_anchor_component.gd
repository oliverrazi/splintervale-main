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
signal target_confused(target: Node3D, duration: float)  # NEU: Für Gegner-Verwirrung

# === REFERENCES ===
@export var player_path: NodePath = ".."
@export var sprite_path: NodePath = "../charactersprite"
@export var spring_arm_path: NodePath = "../SpringArm3D"

# === CHARGING SETTINGS ===
@export_group("Charging")
@export var radius_start: float = 1.0           # Anfangsradius in Metern
@export var radius_max: float = 5.0             # Maximaler Radius
@export var radius_growth_rate: float = 1.5     # Meter pro Sekunde
@export var radius_height: float = 0.3          # Höhe des Radius (für Targeting)
@export var resonance_drain_per_second: float = 10.0

# === PROJECTILE SETTINGS ===
@export_group("Projectile")
@export var projectile_speed: float = 25.0      # Meter pro Sekunde
@export var projectile_color: Color = Color(0.7, 0.85, 1.0, 1.0)

# === LAUNCH/FLIGHT SETTINGS ===
@export_group("Launch")
@export var launch_duration: float = 0.8        # Flugzeit in Sekunden (länger = langsamer)
@export var launch_arc_height: float = 2.5      # Bogenhöhe über dem Ziel
@export var launch_invincible: bool = true      # Unverwundbar während Flug
@export var use_idle_frame_on_land: bool = true # Zeigt Idle-Frame bei Landung

# === ENEMY CONFUSION ===
@export_group("Enemy Confusion")
@export var confuse_enemy: bool = true          # Gegner verwirren
@export var confusion_duration: float = 1.0     # Wie lange der Gegner verwirrt ist
@export var confusion_trigger_point: float = 0.4  # Bei welchem Flug-% verwirren (0.5 = Mitte/über Gegner)

# === COLLISION ===
@export_group("Collision")
@export var collision_delay: float = 0.15       # Sekunden bevor Kollision checkt (für Start an Wand)

# === AFTERIMAGE SETTINGS (während Flug) ===
@export_group("Afterimage")
@export var afterimage_enabled: bool = true
@export var afterimage_count: int = 8
@export var afterimage_color: Color = Color(0.6, 0.85, 1.0, 0.85)
@export var afterimage_fade_time: float = 0.3

# === FRAME INDICES ===
@export_group("Frames - Charging/Release")
@export var use_custom_charge_frames: bool = false  # False = benutze Idle-Frames
@export var CHARGE_DOWN_FRAME: int = 0
@export var CHARGE_UP_FRAME: int = 9
@export var CHARGE_SIDE_FRAME: int = 18
@export var CHARGE_DOWN_LEFT_FRAME: int = 54
@export var CHARGE_UP_RIGHT_FRAME: int = 63

@export_group("Frames - In Air")
@export var use_custom_air_frames: bool = false  # False = benutze Idle-Frames
@export var AIR_DOWN_FRAME: int = 0
@export var AIR_UP_FRAME: int = 9
@export var AIR_SIDE_FRAME: int = 18
@export var AIR_DOWN_LEFT_FRAME: int = 54
@export var AIR_UP_RIGHT_FRAME: int = 63

# === SOUND ===
@export_group("Sound")
@export var charge_loop_sound: AudioStream
@export var release_sound: AudioStream
@export var launch_sound: AudioStream
@export var land_sound: AudioStream

# === TARGETING ===
const TARGETABLE_GROUPS: Array[String] = ["enemies", "enemy", "targetable", "projectile"]

# === STATE ===
enum State { IDLE, CHARGING, PROJECTILE, LAUNCHING, RECOVERY }
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
var _confusion_triggered: bool = false  # Ob Gegner schon verwirrt wurde
var _launch_time: float = 0.0  # Vergangene Zeit seit Launch-Start

# === VISUALS ===
var _radius_mesh: MeshInstance3D = null
var _target_indicator: Node3D = null
var _charge_audio: AudioStreamPlayer3D = null

# === CACHED REFERENCES ===
var _player: CharacterBody3D = null
var _sprite: Node3D = null  # Kann Sprite3D oder SmoothPixelSprite3D sein
var _spring_arm: Node3D = null

# === 8 Directions ===
enum DirMode { DOWN, UP, LEFT, RIGHT, DOWN_LEFT, DOWN_RIGHT, UP_LEFT, UP_RIGHT }


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_spring_arm = get_node_or_null(spring_arm_path) as Node3D
	
	# Sprite kann Sprite3D oder SmoothPixelSprite3D oder andere sein
	var sprite_node = get_node_or_null(sprite_path)
	if sprite_node != null:
		_sprite = sprite_node
	
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
		State.RECOVERY:
			pass


# ============================================
# PUBLIC API
# ============================================

func start_charging() -> bool:
	"""Startet das Charging. Gibt false zurück wenn nicht möglich."""
	if _state != State.IDLE:
		return false
	
	if _player == null:
		return false
	
	# Prüfen ob genug Resonance für mindestens einen Frame
	if not _has_resonance(resonance_drain_per_second * 0.016):
		ability_cancelled.emit("not_enough_resonance")
		return false
	
	_state = State.CHARGING
	_current_radius = radius_start
	_charge_time = 0.0
	_current_target = null
	
	# Spieler stoppen
	_player.velocity = Vector3.ZERO
	
	# Radius-Visualisierung erstellen
	_create_radius_visual()
	
	# Sound starten
	_start_charge_sound()
	
	# Player-Attack abbrechen falls aktiv
	if _player.has_method("_end_attack"):
		_player._end_attack()
	
	charging_started.emit()
	return true


func stop_charging() -> void:
	"""Beendet das Charging und feuert bei gültigem Ziel."""
	if _state != State.CHARGING:
		return
	
	if _current_target != null and is_instance_valid(_current_target):
		# Gültiges Ziel -> Projektil feuern
		_fire_projectile()
	else:
		# Kein Ziel -> Abbrechen
		_cancel_ability("no_target")


func cancel() -> void:
	"""Bricht die Fähigkeit sofort ab."""
	_cancel_ability("cancelled")


func is_active() -> bool:
	"""Gibt true zurück wenn die Fähigkeit aktiv ist (nicht IDLE)."""
	return _state != State.IDLE


func is_charging() -> bool:
	return _state == State.CHARGING


func is_launching() -> bool:
	return _state == State.LAUNCHING


func get_current_target() -> Node3D:
	return _current_target


# ============================================
# CHARGING STATE
# ============================================

func _process_charging(delta: float) -> void:
	# Resonance drainieren
	var drain: float = resonance_drain_per_second * delta
	if not _consume_resonance(drain):
		_cancel_ability("not_enough_resonance")
		return
	
	_charge_time += delta
	
	# Radius wachsen lassen
	_current_radius = min(radius_max, radius_start + radius_growth_rate * _charge_time)
	_update_radius_visual()
	
	# Ziel suchen
	_update_target()
	
	# Charging-Frame anzeigen
	_show_charge_frame()


func _update_target() -> void:
	var best_target: Node3D = null
	var best_score: float = -INF
	
	var player_pos: Vector3 = _player.global_position
	var player_forward: Vector3 = _get_player_forward()
	
	for group in TARGETABLE_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D:
				var target_pos: Vector3 = node.global_position
				var to_target: Vector3 = target_pos - player_pos
				var distance: float = to_target.length()
				
				# Distanz-Check
				if distance > _current_radius or distance < 0.5:
					continue
				
				# Höhen-Check
				var height_diff: float = abs(target_pos.y - player_pos.y)
				if height_diff > radius_height:
					continue
				
				# Score berechnen (Vorne = besser, näher = besser)
				var direction: Vector3 = to_target.normalized()
				var dot: float = direction.dot(player_forward)
				var score: float = dot * 2.0 - distance / _current_radius
				
				if score > best_score:
					best_score = score
					best_target = node
	
	# Target gewechselt?
	if best_target != _current_target:
		if _current_target != null:
			_remove_target_indicator()
			target_lost.emit()
		
		_current_target = best_target
		
		if _current_target != null:
			_create_target_indicator()
			target_acquired.emit(_current_target)


func _get_player_forward() -> Vector3:
	"""Gibt die Blickrichtung des Spielers zurück."""
	var dir_mode: int = _player._last_dir_mode
	var dir2: Vector2 = Vector2.ZERO
	
	match dir_mode:
		DirMode.DOWN: dir2 = Vector2(0, 1)
		DirMode.UP: dir2 = Vector2(0, -1)
		DirMode.LEFT: dir2 = Vector2(-1, 0)
		DirMode.RIGHT: dir2 = Vector2(1, 0)
		DirMode.DOWN_LEFT: dir2 = Vector2(-1, 1).normalized()
		DirMode.DOWN_RIGHT: dir2 = Vector2(1, 1).normalized()
		DirMode.UP_LEFT: dir2 = Vector2(-1, -1).normalized()
		DirMode.UP_RIGHT: dir2 = Vector2(1, -1).normalized()
	
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
	
	# Spieler zum Ziel drehen
	_face_target(_current_target.global_position)
	
	# Release-Frame zeigen
	_show_charge_frame()
	
	# Radius entfernen
	_remove_radius_visual()
	_stop_charge_sound()
	
	# Projektil erstellen
	_create_projectile()
	
	_state = State.PROJECTILE
	
	# Sound
	_play_sound(release_sound)
	
	projectile_fired.emit(_current_target)


func _create_projectile() -> void:
	_projectile_node = Node3D.new()
	get_tree().current_scene.add_child(_projectile_node)
	_projectile_node.global_position = _player.global_position + Vector3(0, 0.5, 0)
	
	# Mesh für Projektil
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	mesh_instance.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = projectile_color
	mat.emission_enabled = true
	mat.emission = projectile_color
	mat.emission_energy_multiplier = 3.0
	mesh_instance.material_override = mat
	
	_projectile_node.add_child(mesh_instance)
	
	# Trail-Partikel
	var particles := GPUParticles3D.new()
	particles.amount = 20
	particles.lifetime = 0.2
	particles.emitting = true
	
	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.direction = Vector3(0, 0, 0)
	proc_mat.spread = 180.0
	proc_mat.initial_velocity_min = 0.1
	proc_mat.initial_velocity_max = 0.3
	proc_mat.gravity = Vector3.ZERO
	proc_mat.scale_min = 0.5
	proc_mat.scale_max = 1.0
	
	var gradient := Gradient.new()
	gradient.set_color(0, projectile_color)
	gradient.set_color(1, Color(projectile_color.r, projectile_color.g, projectile_color.b, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	proc_mat.color_ramp = gradient_tex
	
	particles.process_material = proc_mat
	
	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	var quad_mat := StandardMaterial3D.new()
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.vertex_color_use_as_albedo = true
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = quad_mat
	particles.draw_pass_1 = quad
	
	_projectile_node.add_child(particles)


func _process_projectile(delta: float) -> void:
	if _projectile_node == null or _current_target == null:
		_cancel_ability("projectile_lost")
		return
	
	if not is_instance_valid(_current_target):
		_cancel_ability("target_invalid")
		return
	
	var target_pos: Vector3 = _current_target.global_position + Vector3(0, 0.3, 0)
	var current_pos: Vector3 = _projectile_node.global_position
	var direction: Vector3 = (target_pos - current_pos).normalized()
	var distance: float = current_pos.distance_to(target_pos)
	
	# Projektil bewegen
	var move_dist: float = projectile_speed * delta
	
	if move_dist >= distance:
		# Ziel erreicht -> Launch starten
		_on_projectile_hit()
	else:
		_projectile_node.global_position += direction * move_dist


func _on_projectile_hit() -> void:
	# Projektil entfernen
	if _projectile_node:
		# Impact-Effekt
		_spawn_impact_effect(_projectile_node.global_position)
		_projectile_node.queue_free()
		_projectile_node = null
	
	# Ziel-Indikator entfernen
	_remove_target_indicator()
	
	# Projektil-Reflektion bei Projektil-Zielen
	if _current_target.is_in_group("projectile"):
		_reflect_projectile(_current_target)
		_cancel_ability("projectile_reflected")
		return
	
	# Launch starten
	_start_launch()


func _reflect_projectile(projectile: Node3D) -> void:
	"""Reflektiert ein Projektil zurück."""
	if projectile.has_method("reflect"):
		projectile.reflect()
	elif projectile.get("velocity") != null:
		projectile.velocity = -projectile.velocity
	# Keine weitere Aktion - Spieler bleibt stehen


# ============================================
# LAUNCH STATE
# ============================================

func _start_launch() -> void:
	if _current_target == null or not is_instance_valid(_current_target):
		_cancel_ability("target_invalid")
		return
	
	# Positionen berechnen
	var start_pos: Vector3 = _player.global_position
	var target_pos: Vector3 = _current_target.global_position
	
	# Gespiegelte Position berechnen
	var end_pos: Vector3 = target_pos * 2.0 - start_pos
	end_pos.y = start_pos.y  # Gleiche Höhe
	
	# VORAB Kollisions-Check für Endposition
	var space_state := _player.get_world_3d().direct_space_state
	
	# Prüfe ob Endposition frei ist (Sphere-Check)
	var shape_query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape_query.shape = sphere
	shape_query.transform = Transform3D(Basis(), end_pos + Vector3(0, 0.5, 0))
	shape_query.collision_mask = _player.collision_mask
	shape_query.exclude = [_player.get_rid()]
	
	var results := space_state.intersect_shape(shape_query, 1)
	if results.size() > 0:
		# Endposition blockiert - finde eine sichere Position
		# Versuche näher am Ziel zu landen
		var dir_to_end: Vector3 = (end_pos - target_pos).normalized()
		for dist in [0.8, 1.2, 1.6, 2.0]:
			var test_pos: Vector3 = target_pos + dir_to_end * dist
			test_pos.y = start_pos.y
			shape_query.transform = Transform3D(Basis(), test_pos + Vector3(0, 0.5, 0))
			results = space_state.intersect_shape(shape_query, 1)
			if results.size() == 0:
				end_pos = test_pos
				break
		
		# Wenn immer noch blockiert, abbrechen
		if results.size() > 0:
			_cancel_ability("destination_blocked")
			return
	
	_state = State.LAUNCHING
	_launch_progress = 0.0
	_afterimage_timer = 0.0
	_afterimages_spawned = 0
	_confusion_triggered = false
	_launch_time = 0.0
	
	_launch_start_pos = start_pos
	_launch_target_pos = target_pos
	_launch_end_pos = end_pos
	
	# Invincibility
	if launch_invincible:
		_player._invincibility_timer = max(_player._invincibility_timer, launch_duration + 0.1)
	
	# Sound
	_play_sound(launch_sound)
	
	launch_started.emit()


func _process_launching(delta: float) -> void:
	_launch_progress += delta / launch_duration
	_launch_time += delta
	
	if _launch_progress >= 1.0:
		_complete_launch()
		return
	
	# Gegner verwirren wenn Spieler über ihm ist (bei confusion_trigger_point)
	if confuse_enemy and not _confusion_triggered and _launch_progress >= confusion_trigger_point:
		if _current_target != null and is_instance_valid(_current_target):
			_confuse_target(_current_target)
		_confusion_triggered = true
	
	# Bogen-Position berechnen
	var t: float = _launch_progress
	
	# Horizontale Interpolation
	var horizontal_pos: Vector3 = _launch_start_pos.lerp(_launch_end_pos, t)
	
	# Vertikale Parabel (Bogen)
	var arc: float = 4.0 * launch_arc_height * t * (1.0 - t)
	
	var new_pos: Vector3 = horizontal_pos
	new_pos.y = _launch_start_pos.y + arc
	
	# Kollisions-Check NUR nach collision_delay (damit man von Wand wegkommt)
	if _launch_time >= collision_delay:
		var space_state := _player.get_world_3d().direct_space_state
		var shape_query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.3
		shape_query.shape = sphere
		shape_query.transform = Transform3D(Basis(), new_pos + Vector3(0, 0.3, 0))
		shape_query.collision_mask = _player.collision_mask
		shape_query.exclude = [_player.get_rid()]
		
		var results := space_state.intersect_shape(shape_query, 1)
		
		if results.size() > 0:
			# Kollision! Bleibe an aktueller Position und beende
			
			# Zum Ziel drehen
			_face_target(_launch_target_pos)
			if _player.has_method("_show_idle"):
				_player._show_idle()
			
			# Attack-Cooldown zurücksetzen
			if "_attack_cooldown_timer" in _player:
				_player._attack_cooldown_timer = 0.0
			
			# State zurücksetzen
			_state = State.IDLE
			_current_target = null
			
			ability_cancelled.emit("collision")
			return
	
	# Keine Kollision - Position setzen
	_player.global_position = new_pos
	
	# Afterimages spawnen
	if afterimage_enabled and _sprite != null:
		var afterimage_interval: float = launch_duration / float(afterimage_count)
		_afterimage_timer += delta
		if _afterimage_timer >= afterimage_interval and _afterimages_spawned < afterimage_count:
			_spawn_afterimage()
			_afterimage_timer = 0.0
			_afterimages_spawned += 1
	
	# Air-Frame anzeigen (Richtung zum Ziel)
	_show_air_frame()


func _complete_launch() -> void:
	# Endposition setzen
	_player.global_position = _launch_end_pos
	
	# Falls Verwirrung noch nicht ausgelöst wurde (z.B. sehr kurzer Flug), jetzt machen
	if confuse_enemy and not _confusion_triggered:
		if _current_target != null and is_instance_valid(_current_target):
			_confuse_target(_current_target)
	
	# Zum Ziel drehen (VON der Endposition AUS zum Ziel schauen)
	_face_target(_launch_target_pos)
	
	# Idle-Frame anzeigen
	if use_idle_frame_on_land and _player.has_method("_show_idle"):
		_player._show_idle()
	
	# Attack-Cooldown zurücksetzen für sofortigen Angriff!
	if "_attack_cooldown_timer" in _player:
		_player._attack_cooldown_timer = 0.0
	
	# Sound
	_play_sound(land_sound)
	
	# State zurücksetzen
	_state = State.IDLE
	_current_target = null
	
	launch_completed.emit()


func _confuse_target(target: Node3D) -> void:
	"""Verwirrt den Gegner für eine kurze Zeit."""
	# Signal emittieren (für externe Listener)
	target_confused.emit(target, confusion_duration)
	
	# Direkt auf dem Gegner die Methode aufrufen falls vorhanden
	if target.has_method("apply_confusion"):
		target.apply_confusion(confusion_duration)
	elif target.has_method("stun"):
		target.stun(confusion_duration)
	elif target.has_method("set_confused"):
		target.set_confused(true, confusion_duration)
	else:
		# Fallback: Versuche _is_confused oder ähnliche Properties zu setzen
		if "_is_confused" in target:
			target._is_confused = true
			# Timer zum Zurücksetzen
			get_tree().create_timer(confusion_duration).timeout.connect(func():
				if is_instance_valid(target) and "_is_confused" in target:
					target._is_confused = false
			)


# ============================================
# VISUALS - RADIUS
# ============================================

func _create_radius_visual() -> void:
	_radius_mesh = MeshInstance3D.new()
	
	# Flaches Quad das den ganzen Radius abdeckt
	var quad := QuadMesh.new()
	quad.size = Vector2(_current_radius * 2.2, _current_radius * 2.2)
	_radius_mesh.mesh = quad
	
	# Shader-Material für Gradient-Ring
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = _create_radius_shader()
	shader_mat.set_shader_parameter("ring_radius", _current_radius)
	shader_mat.set_shader_parameter("ring_color", Color(0.7, 0.9, 1.0, 1.0))
	shader_mat.set_shader_parameter("inner_fade", 0.3)  # Langer Verlauf nach innen
	shader_mat.set_shader_parameter("outer_fade", 0.08) # Kurzer Verlauf nach außen
	shader_mat.set_shader_parameter("ring_width", 0.12)
	shader_mat.set_shader_parameter("pulse_speed", 3.0)
	shader_mat.set_shader_parameter("time", 0.0)
	_radius_mesh.material_override = shader_mat
	
	# Rotation (flach auf dem Boden)
	_radius_mesh.rotation_degrees.x = -90
	
	# Cast shadows aus
	_radius_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	_player.add_child(_radius_mesh)
	_radius_mesh.position = Vector3(0, 0.03, 0)


func _create_radius_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float ring_radius = 1.0;
uniform vec4 ring_color : source_color = vec4(0.7, 0.9, 1.0, 1.0);
uniform float inner_fade = 0.3;   // Wie weit der innere Gradient reicht
uniform float outer_fade = 0.08;  // Wie weit der äußere Gradient reicht
uniform float ring_width = 0.12;  // Kernbreite des Rings
uniform float pulse_speed = 3.0;
uniform float time = 0.0;

void fragment() {
	// Distanz vom Zentrum (UV geht von 0-1, wir brauchen -0.5 bis 0.5)
	vec2 centered_uv = UV - vec2(0.5);
	float dist = length(centered_uv) * 2.0;  // 0 im Zentrum, 1 am Rand des Quads
	
	// Normalisiere auf Ring-Radius (relativ zur Quad-Größe)
	float normalized_dist = dist;
	
	// Ring-Position (bei 0.9 = 90% des Quad-Radius = der eigentliche Ring)
	float ring_pos = 0.9;
	
	// Distanz zum Ring
	float dist_to_ring = abs(normalized_dist - ring_pos);
	
	// Alpha berechnen mit asymmetrischem Falloff
	float alpha = 0.0;
	
	if (normalized_dist < ring_pos) {
		// Innen: Langer Verlauf
		float inner_dist = ring_pos - normalized_dist;
		float inner_alpha = 1.0 - smoothstep(0.0, inner_fade, inner_dist);
		alpha = inner_alpha;
	} else {
		// Außen: Kurzer Verlauf
		float outer_dist = normalized_dist - ring_pos;
		float outer_alpha = 1.0 - smoothstep(0.0, outer_fade, outer_dist);
		alpha = outer_alpha;
	}
	
	// Kern des Rings (volle Helligkeit)
	float core_alpha = 1.0 - smoothstep(0.0, ring_width, dist_to_ring);
	alpha = max(alpha * 0.6, core_alpha);
	
	// Pulsieren
	float pulse = 1.0 + sin(time * pulse_speed) * 0.15;
	alpha *= pulse;
	
	// Emission für Glow-Effekt
	float emission_strength = core_alpha * 2.0 + alpha * 0.5;
	
	ALBEDO = ring_color.rgb;
	ALPHA = alpha * ring_color.a;
	EMISSION = ring_color.rgb * emission_strength;
}
"""
	return shader


func _update_radius_visual() -> void:
	if _radius_mesh == null:
		return
	
	# Quad-Größe updaten
	var quad: QuadMesh = _radius_mesh.mesh as QuadMesh
	if quad:
		quad.size = Vector2(_current_radius * 2.2, _current_radius * 2.2)
	
	# Shader-Parameter updaten
	var mat: ShaderMaterial = _radius_mesh.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("ring_radius", _current_radius)
		mat.set_shader_parameter("time", _charge_time)


func _remove_radius_visual() -> void:
	if _radius_mesh:
		_radius_mesh.queue_free()
		_radius_mesh = null


# ============================================
# VISUALS - TARGET INDICATOR
# ============================================

func _create_target_indicator() -> void:
	if _current_target == null:
		return
	
	_target_indicator = Node3D.new()
	
	# Ring um das Ziel
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.35
	torus.rings = 16
	torus.ring_segments = 16
	mesh.mesh = torus
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.5, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.rotation_degrees.x = 90
	
	_target_indicator.add_child(mesh)
	
	_current_target.add_child(_target_indicator)
	_target_indicator.position = Vector3(0, 0.1, 0)


func _remove_target_indicator() -> void:
	if _target_indicator and is_instance_valid(_target_indicator):
		_target_indicator.queue_free()
		_target_indicator = null


# ============================================
# VISUALS - EFFECTS
# ============================================

func _spawn_impact_effect(pos: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 16
	particles.lifetime = 0.3
	particles.explosiveness = 1.0
	
	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.direction = Vector3(0, 0, 0)
	proc_mat.spread = 180.0
	proc_mat.initial_velocity_min = 2.0
	proc_mat.initial_velocity_max = 4.0
	proc_mat.gravity = Vector3(0, -2, 0)
	proc_mat.scale_min = 0.5
	proc_mat.scale_max = 1.5
	proc_mat.color = projectile_color
	
	particles.process_material = proc_mat
	
	var sphere := SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	var sphere_mat := StandardMaterial3D.new()
	sphere_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere_mat.albedo_color = projectile_color
	sphere_mat.emission_enabled = true
	sphere_mat.emission = projectile_color
	sphere_mat.emission_energy_multiplier = 2.0
	sphere.material = sphere_mat
	particles.draw_pass_1 = sphere
	
	get_tree().current_scene.add_child(particles)
	particles.global_position = pos
	
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)


func _spawn_afterimage() -> void:
	if _sprite == null:
		print("VectorAnchor: Cannot spawn afterimage - sprite is null")
		return
	
	# Prüfen ob sprite die nötigen Properties hat
	if not ("texture" in _sprite and "frame" in _sprite):
		print("VectorAnchor: Sprite missing texture/frame properties")
		return
	
	var ghost := Sprite3D.new()
	ghost.texture = _sprite.texture
	ghost.hframes = _sprite.hframes if "hframes" in _sprite else 1
	ghost.vframes = _sprite.vframes if "vframes" in _sprite else 1
	ghost.frame = _sprite.frame
	ghost.flip_h = _sprite.flip_h if "flip_h" in _sprite else false
	ghost.pixel_size = _sprite.pixel_size if "pixel_size" in _sprite else 0.01
	ghost.centered = _sprite.centered if "centered" in _sprite else true
	ghost.offset = _sprite.offset if "offset" in _sprite else Vector2.ZERO
	ghost.billboard = _sprite.billboard if "billboard" in _sprite else BaseMaterial3D.BILLBOARD_DISABLED
	ghost.transparent = true
	ghost.render_priority = -1
	
	ghost.global_transform = _sprite.global_transform
	ghost.modulate = afterimage_color
	
	get_tree().current_scene.add_child(ghost)
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ghost, "modulate:a", 0.0, afterimage_fade_time).set_ease(Tween.EASE_IN)
	tween.tween_property(ghost, "scale", ghost.scale * 0.8, afterimage_fade_time)
	tween.chain().tween_callback(ghost.queue_free)


# ============================================
# FRAMES
# ============================================

func _show_charge_frame() -> void:
	if _sprite == null or _player == null:
		return
	
	# Wenn keine custom Frames, benutze Player's Idle-Frames
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
	
	# Richtung ZUM ZIEL berechnen (nicht Flugrichtung!)
	var to_target: Vector3 = _launch_target_pos - _player.global_position
	to_target.y = 0
	var dir_mode: int = _direction_from_vector(to_target)
	
	# Spieler-Richtung updaten
	_player._last_dir_mode = dir_mode
	match dir_mode:
		DirMode.RIGHT, DirMode.DOWN_RIGHT, DirMode.UP_RIGHT:
			_player._facing_right = true
		DirMode.LEFT, DirMode.DOWN_LEFT, DirMode.UP_LEFT:
			_player._facing_right = false
	
	# Wenn keine custom Frames, benutze Player's Idle-Frames
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
	"""Dreht den Spieler zum Ziel (von der aktuellen Position aus)."""
	var direction: Vector3 = target_pos - _player.global_position
	direction.y = 0
	
	if direction.length_squared() < 0.001:
		return  # Zu nah, keine Drehung nötig
	
	var dir_mode: int = _direction_from_vector(direction)
	_player._last_dir_mode = dir_mode
	
	# _facing_right setzen - INVERTIERT da wir ZUM Ziel schauen wollen
	match dir_mode:
		DirMode.RIGHT, DirMode.DOWN_RIGHT, DirMode.UP_RIGHT:
			_player._facing_right = true
		DirMode.LEFT, DirMode.DOWN_LEFT, DirMode.UP_LEFT:
			_player._facing_right = false
		# DOWN und UP: facing_right bleibt wie es war


func _direction_from_vector(vec: Vector3) -> int:
	"""Konvertiert einen Richtungsvektor zu DirMode - angepasst an Player's Logik."""
	if vec.length_squared() < 0.001:
		return DirMode.DOWN
	
	# In Kamera-Raum konvertieren falls SpringArm vorhanden (wie im Player)
	var dir2: Vector2
	if _spring_arm:
		var yaw: float = _spring_arm.rotation.y
		var forward := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		# Projiziere vec auf die Kamera-Achsen
		dir2 = Vector2(vec.dot(right), vec.dot(forward)).normalized()
	else:
		dir2 = Vector2(vec.x, vec.z).normalized()
	
	var deg: float = rad_to_deg(dir2.angle())
	if deg < 0:
		deg += 360.0
	
	# Winkel zu Richtung (angepasst an Player's _get_direction_from_input)
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
		
		# Regen-Timer zurücksetzen (falls vorhanden)
		if "resonance_regen_delay" in pd and "_resonance_regen_timer" in pd:
			pd._resonance_regen_timer = pd.resonance_regen_delay
		
		# Signal feuern
		pd.resonance_changed.emit(int(pd.current_resonance), pd.max_resonance)
		return true
	return false


func _cancel_ability(reason: String) -> void:
	_remove_radius_visual()
	_remove_target_indicator()
	_stop_charge_sound()
	
	if _projectile_node:
		_projectile_node.queue_free()
		_projectile_node = null
	
	_state = State.IDLE
	_current_target = null
	
	ability_cancelled.emit(reason)


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

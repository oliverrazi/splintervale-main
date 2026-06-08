extends Node
class_name DodgeComponent

## Dodge Component - Als Child-Node zum Player hinzufügen
## Benötigt: Player muss CharacterBody3D sein mit "charactersprite" (SmoothPixelSprite3D)

signal dodge_started
signal dodge_ended
signal dodge_failed(reason: String)

# === REFERENCES ===
@export var player_path: NodePath = ".."
@export var sprite_path: NodePath = "../charactersprite"
@export var spring_arm_path: NodePath = "../SpringArm3D"

# === DODGE SETTINGS ===
@export_group("Dodge")
@export var dodge_speed: float = 120.0
@export var dodge_duration: float = 0.22
@export var dodge_cooldown: float = 0.6
@export var dodge_invincibility: bool = true
@export var resonance_cost: int = 8
@export var velocity_fade_duration: float = 0.15  # Sanftes Auslaufen

# === AFTERIMAGE SETTINGS ===
@export_group("Afterimage")
@export var afterimage_enabled: bool = true
@export var afterimage_count: int = 5
@export var afterimage_interval: float = 0.04
@export var afterimage_fade_time: float = 0.3
@export var afterimage_color: Color = Color(0.6, 0.85, 1.0, 0.9)
@export var afterimage_emission_strength: float = 2.0

# === SHIMMER SETTINGS ===
@export_group("Shimmer")
@export var shimmer_enabled: bool = true
@export var shimmer_amount: int = 30
@export var shimmer_lifetime: float = 0.4
@export var shimmer_color: Color = Color(0.7, 0.9, 1.0, 1.0)

# === DODGE FRAMES ===
@export_group("Dodge Frames - Directional")
@export var DODGE_DOWN_FRAME: int = 1     
@export var DODGE_UP_FRAME: int = 10        
@export var DODGE_SIDE_FRAME: int = 19
@export var DODGE_DOWN_LEFT_FRAME: int = 55
@export var DODGE_UP_RIGHT_FRAME: int = 64

# Back-Dodge Frames (Rückwärts in Blickrichtung)
@export_group("Dodge Frames - Back-Dodge")
@export var BACKDODGE_DOWN_FRAME: int = 1      # Schaut nach unten, dodgt rückwärts (nach oben)
@export var BACKDODGE_UP_FRAME: int = 10        # Schaut nach oben, dodgt rückwärts (nach unten)
@export var BACKDODGE_SIDE_FRAME: int = 19      # Schaut zur Seite, dodgt rückwärts
@export var BACKDODGE_DOWN_LEFT_FRAME: int = 55
@export var BACKDODGE_UP_RIGHT_FRAME: int = 64

# === SOUND ===
@export_group("Sound")
@export var dodge_sounds: Array[AudioStream] = []
@export var dodge_volume_db: float = -4.0

# === 8 Richtungen ===
enum DirMode { DOWN, UP, LEFT, RIGHT, DOWN_LEFT, DOWN_RIGHT, UP_LEFT, UP_RIGHT }

# === INTERNAL STATE ===
var _is_dodging: bool = false
var _is_fading_out: bool = false
var _dodge_timer: float = 0.0
var _dodge_cooldown_timer: float = 0.0
var _fade_timer: float = 0.0
var _dodge_direction: Vector3 = Vector3.ZERO
var _afterimage_timer: float = 0.0
var _afterimages_spawned: int = 0
var _shimmer_particles: GPUParticles3D = null
var _is_back_dodge: bool = false
var _facing_dir_mode: int = DirMode.DOWN  # Blickrichtung (bleibt bei Back-Dodge)
var _move_dir_mode: int = DirMode.DOWN    # Bewegungsrichtung

# === CACHED REFERENCES ===
var _player: CharacterBody3D = null
var _sprite: LayeredPixelSprite3D = null  # CHANGED: war Sprite3D
var _spring_arm: Node3D = null


var _cinematic_dodge_active: bool = false

func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_sprite = _find_sprite()  # CHANGED: eigene Suche statt as Sprite3D
	_spring_arm = get_node_or_null(spring_arm_path) as Node3D
	
	if _player == null:
		push_error("DodgeComponent: Player not found at path: ", player_path)
	if _sprite == null:
		push_error("DodgeComponent: SmoothPixelSprite3D not found at path: ", sprite_path)


func _find_sprite() -> LayeredPixelSprite3D:
	# Erst den konfigurierten Pfad versuchen
	var found := get_node_or_null(sprite_path)
	if found is LayeredPixelSprite3D:
		return found
	
	# Fallback: Im Parent nach SmoothPixelSprite3D suchen
	var parent := get_node_or_null(player_path)
	if parent:
		for child in parent.get_children():
			if child is LayeredPixelSprite3D:
				return child
	
	push_warning("DodgeComponent: No LayeredPixelSprite3D found!")
	return null


func _physics_process(delta: float) -> void:
	# Cooldown Timer
	if _dodge_cooldown_timer > 0.0:
		_dodge_cooldown_timer -= delta
	
	# Velocity Fade-Out nach Dodge
	if _is_fading_out:
		_process_fade_out(delta)
	
	# Dodge Processing
	if _is_dodging:
		_process_dodge(delta)


# ============================================
# PUBLIC API
# ============================================

func try_dodge() -> bool:
	"""Versucht einen Dodge zu starten. Gibt true zurück wenn erfolgreich."""
	if not can_dodge():
		return false
	
	if not _consume_resonance():
		dodge_failed.emit("not_enough_resonance")
		return false
	
	_start_dodge()
	return true


func can_dodge() -> bool:
	if _player == null:
		return false
	if _is_dodging:
		return false
	if _dodge_cooldown_timer > 0.0:
		return false
	if _player.has_method("is_alive") and not _player.is_alive():
		return false
	# Während eines aktiven Schwertangriffs kein Dodge.
	if _player.has_method("_is_action_locked") and _player._is_action_locked():
		return false
	return true

func force_end_for_spin() -> void:
	_is_dodging = false
	_is_fading_out = false
	# Cooldown setzen, damit nach dem Spin kein sofortiger erneuter Dodge kommt
	_dodge_cooldown_timer = dodge_cooldown
	
	if _shimmer_particles != null and is_instance_valid(_shimmer_particles):
		_shimmer_particles.emitting = false
		var p_ref := _shimmer_particles
		get_tree().create_timer(shimmer_lifetime + 0.1).timeout.connect(func():
			if is_instance_valid(p_ref):
				p_ref.queue_free()
		)
		_shimmer_particles = null
	
	if _sprite:
		_sprite.modulate.a = 1.0


func has_enough_resonance() -> bool:
	if GameManager == null or GameManager.player_data == null:
		return true
	return GameManager.player_data.current_resonance >= resonance_cost


func is_dodging() -> bool:
	return _is_dodging or _is_fading_out


func is_active_dodge() -> bool:
	"""Gibt true zurück nur während der aktiven Dodge-Phase (nicht Fade-Out)"""
	return _is_dodging


func get_cooldown_remaining() -> float:
	return max(0.0, _dodge_cooldown_timer)


func cinematic_dodge(world_dir: Vector3) -> bool:
	if _player == null or _sprite == null: return false
	if _is_dodging: return false
	if world_dir.length_squared() < 0.0001: return false
	var dir := world_dir.normalized()
	_facing_dir_mode = _player._last_dir_mode
	_move_dir_mode = _world_dir_to_dir_mode(dir)
	_is_back_dodge = false
	_dodge_direction = dir
	_is_dodging = true
	_is_fading_out = false
	_dodge_timer = dodge_duration
	_afterimage_timer = 0.0
	_afterimages_spawned = 0
	_cinematic_dodge_active = true
	if dodge_invincibility:
		_player._invincibility_timer = max(_player._invincibility_timer, dodge_duration + 0.05)
	if afterimage_enabled: _spawn_afterimage()
	_cleanup_shimmer()
	if shimmer_enabled: _start_shimmer_trail()
	_play_dodge_sound()
	dodge_started.emit()
	return true

func _world_dir_to_dir_mode(world_dir: Vector3) -> int:
	var dir2: Vector2
	if _spring_arm:
		var yaw: float = _spring_arm.rotation.y
		var forward := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		dir2 = Vector2(world_dir.dot(right), world_dir.dot(forward)).normalized()
	else:
		dir2 = Vector2(world_dir.x, world_dir.z).normalized()
	return _get_direction_from_input(dir2)

# ============================================
# INTERNAL - DODGE LOGIC
# ============================================

func _consume_resonance() -> bool:
	if GameManager == null or GameManager.player_data == null:
		return true
	return GameManager.player_data.use_resonance(resonance_cost)


func _start_dodge() -> void:
	if _player == null or _sprite == null:
		return
	
	# Player-States zurücksetzen
	if _player.has_method("_end_attack"):
		_player._end_attack()
	
	if _player.get("_is_knocked_back"):
		_player._is_knocked_back = false
		_player._knockback_velocity = Vector3.ZERO
	
	# Aktuelle Blickrichtung speichern
	_facing_dir_mode = _player._last_dir_mode
	
	# Richtung bestimmen
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if input_dir.length_squared() > 0.01:
		# Direktionaler Dodge
		input_dir = input_dir.normalized()
		_move_dir_mode = _get_direction_from_input(input_dir)
		_is_back_dodge = false
		
		# Facing aktualisieren bei direktionalem Dodge
		match _move_dir_mode:
			DirMode.RIGHT, DirMode.DOWN_RIGHT, DirMode.UP_RIGHT:
				_player._facing_right = true
			DirMode.LEFT, DirMode.DOWN_LEFT, DirMode.UP_LEFT:
				_player._facing_right = false
		
		_player._last_dir_mode = _move_dir_mode
		_facing_dir_mode = _move_dir_mode
	else:
		# Back-Dodge: Bewegung rückwärts, Blickrichtung bleibt!
		_move_dir_mode = _get_opposite_direction(_facing_dir_mode)
		_is_back_dodge = true
		# _player._last_dir_mode und _facing_right bleiben unverändert!
	
	# Weltrichtung berechnen
	_dodge_direction = _get_dodge_world_direction(_move_dir_mode)
	
	# State setzen
	_is_dodging = true
	_is_fading_out = false
	_dodge_timer = dodge_duration
	_afterimage_timer = 0.0
	_afterimages_spawned = 0
	
	# Invincibility
	if dodge_invincibility:
		_player._invincibility_timer = max(_player._invincibility_timer, dodge_duration + velocity_fade_duration + 0.05)
	
	# Erstes Afterimage sofort
	if afterimage_enabled:
		_spawn_afterimage()
	
	# Alte Shimmer Partikel aufräumen bevor neue erstellt werden!
	_cleanup_shimmer()
	
	# Shimmer Trail
	if shimmer_enabled:
		_start_shimmer_trail()
	
	# Sound
	_play_dodge_sound()
	
	dodge_started.emit()


func _process_dodge(delta: float) -> void:
	if _player == null:
		_end_dodge()
		return
	
	_dodge_timer -= delta
	
	# Bewegung
	_player.velocity.x = _dodge_direction.x * dodge_speed
	_player.velocity.z = _dodge_direction.z * dodge_speed
	
	# Afterimages spawnen
	if afterimage_enabled:
		_afterimage_timer += delta
		if _afterimage_timer >= afterimage_interval and _afterimages_spawned < afterimage_count:
			_spawn_afterimage()
			_afterimage_timer = 0.0
			_afterimages_spawned += 1
	
	# Frame anzeigen
	_show_dodge_frame()
	
	if not _cinematic_dodge_active:
		_player.velocity.x = _dodge_direction.x * dodge_speed
		_player.velocity.z = _dodge_direction.z * dodge_speed
	
	# Dodge beenden -> Fade-Out starten
	if _dodge_timer <= 0.0:
		if _cinematic_dodge_active:
			_cinematic_dodge_active = false
			_end_dodge()
		else:
			_start_fade_out()

	


func _start_fade_out() -> void:
	"""Startet das sanfte Auslaufen der Geschwindigkeit"""
	_is_dodging = false
	_is_fading_out = true
	_fade_timer = velocity_fade_duration
	_dodge_cooldown_timer = dodge_cooldown
	
	# Shimmer stoppen (nicht löschen - soll noch ausfaden)
	if _shimmer_particles != null and is_instance_valid(_shimmer_particles):
		_shimmer_particles.emitting = false
		# Verzögert aufräumen damit Partikel ausfaden können
		var particles_ref := _shimmer_particles
		get_tree().create_timer(shimmer_lifetime + 0.1).timeout.connect(func():
			if is_instance_valid(particles_ref):
				particles_ref.queue_free()
		)
		_shimmer_particles = null


func _process_fade_out(delta: float) -> void:
	"""Sanftes Abbremsen nach dem Dodge"""
	if _player == null:
		_end_fade_out()
		return
	
	_fade_timer -= delta
	
	if _fade_timer <= 0.0:
		_end_fade_out()
		return
	
	# Geschwindigkeit linear reduzieren
	var fade_progress: float = _fade_timer / velocity_fade_duration
	_player.velocity.x = _dodge_direction.x * dodge_speed * fade_progress
	_player.velocity.z = _dodge_direction.z * dodge_speed * fade_progress
	
	# Weiterhin Dodge-Frame zeigen während Fade-Out
	_show_dodge_frame()


func _end_fade_out() -> void:
	_is_fading_out = false
	_dodge_direction = Vector3.ZERO
	
	if _player:
		_player.velocity.x = 0.0
		_player.velocity.z = 0.0
	
	if _sprite:
		_sprite.modulate.a = 1.0
	
	dodge_ended.emit()


func _end_dodge() -> void:
	"""Notfall-Ende ohne Fade-Out"""
	_is_dodging = false
	_is_fading_out = false
	_dodge_cooldown_timer = dodge_cooldown
	_dodge_direction = Vector3.ZERO
	
	if _player:
		_player.velocity.x = 0.0
		_player.velocity.z = 0.0
	
	if _sprite:
		_sprite.modulate.a = 1.0
	
	if _shimmer_particles != null and is_instance_valid(_shimmer_particles):
		_shimmer_particles.emitting = false
	
	dodge_ended.emit()


# ============================================
# DIRECTION HELPERS
# ============================================

func _get_direction_from_input(dir: Vector2) -> int:
	if dir == Vector2.ZERO:
		return _facing_dir_mode
	
	var deg: float = rad_to_deg(dir.angle())
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


func _get_opposite_direction(dir_mode: int) -> int:
	match dir_mode:
		DirMode.DOWN: return DirMode.UP
		DirMode.UP: return DirMode.DOWN
		DirMode.LEFT: return DirMode.RIGHT
		DirMode.RIGHT: return DirMode.LEFT
		DirMode.DOWN_LEFT: return DirMode.UP_RIGHT
		DirMode.DOWN_RIGHT: return DirMode.UP_LEFT
		DirMode.UP_LEFT: return DirMode.DOWN_RIGHT
		DirMode.UP_RIGHT: return DirMode.DOWN_LEFT
		_: return DirMode.UP


func _get_dodge_world_direction(dir_mode: int) -> Vector3:
	var dir2: Vector2 = Vector2.ZERO
	
	match dir_mode:
		DirMode.DOWN: dir2 = Vector2(0.0, 1.0)
		DirMode.UP: dir2 = Vector2(0.0, -1.0)
		DirMode.LEFT: dir2 = Vector2(-1.0, 0.0)
		DirMode.RIGHT: dir2 = Vector2(1.0, 0.0)
		DirMode.DOWN_LEFT: dir2 = Vector2(-1.0, 1.0).normalized()
		DirMode.DOWN_RIGHT: dir2 = Vector2(1.0, 1.0).normalized()
		DirMode.UP_LEFT: dir2 = Vector2(-1.0, -1.0).normalized()
		DirMode.UP_RIGHT: dir2 = Vector2(1.0, -1.0).normalized()
	
	if dir2 == Vector2.ZERO:
		return Vector3.ZERO
	
	if _spring_arm:
		var yaw: float = _spring_arm.rotation.y
		var forward := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		return (right * dir2.x + forward * dir2.y).normalized()
	else:
		return Vector3(dir2.x, 0, dir2.y).normalized()


# ============================================
# VISUALS - DODGE FRAMES
# ============================================

func _show_dodge_frame() -> void:
	if _sprite == null:
		return
	
	var frame: int
	var flip: bool = false
	
	if _is_back_dodge:
		# Back-Dodge: Benutze Back-Dodge Frames, basierend auf BLICK-Richtung
		match _facing_dir_mode:
			DirMode.DOWN:
				frame = BACKDODGE_DOWN_FRAME
			DirMode.UP:
				frame = BACKDODGE_UP_FRAME
			DirMode.LEFT:
				frame = BACKDODGE_SIDE_FRAME
			DirMode.RIGHT:
				frame = BACKDODGE_SIDE_FRAME
				flip = true
			DirMode.DOWN_LEFT:
				frame = BACKDODGE_DOWN_LEFT_FRAME
			DirMode.DOWN_RIGHT:
				frame = BACKDODGE_DOWN_LEFT_FRAME
				flip = true
			DirMode.UP_RIGHT:
				frame = BACKDODGE_UP_RIGHT_FRAME
			DirMode.UP_LEFT:
				frame = BACKDODGE_UP_RIGHT_FRAME
				flip = true
			_:
				frame = BACKDODGE_DOWN_FRAME
	else:
		# Direktionaler Dodge: Benutze normale Dodge-Frames
		match _move_dir_mode:
			DirMode.DOWN:
				frame = DODGE_DOWN_FRAME
			DirMode.UP:
				frame = DODGE_UP_FRAME
			DirMode.LEFT:
				frame = DODGE_SIDE_FRAME
			DirMode.RIGHT:
				frame = DODGE_SIDE_FRAME
				flip = true
			DirMode.DOWN_LEFT:
				frame = DODGE_DOWN_LEFT_FRAME
			DirMode.DOWN_RIGHT:
				frame = DODGE_DOWN_LEFT_FRAME
				flip = true
			DirMode.UP_RIGHT:
				frame = DODGE_UP_RIGHT_FRAME
			DirMode.UP_LEFT:
				frame = DODGE_UP_RIGHT_FRAME
				flip = true
			_:
				frame = DODGE_DOWN_FRAME
	
	_sprite.frame = frame
	_sprite.flip_h = flip


# ============================================
# VISUALS - AFTERIMAGES (FIXED für SmoothPixelSprite3D)
# ============================================

func _spawn_afterimage() -> void:
	if _sprite == null:
		return
	
	# Für jeden sichtbaren Layer ein eigenes Ghost-Sprite3D erstellen
	for layer_key in _sprite.get_all_layer_keys():
		var layer_sprite: SmoothPixelSprite3D = _sprite.get_layer(layer_key)
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
		ghost.transparent = true
		ghost.no_depth_test = false
		ghost.render_priority = -1
		ghost.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ghost.modulate = afterimage_color
		
		# Zur Szene hinzufügen (nicht in Container)
		get_tree().current_scene.add_child(ghost)
		
		# Position exakt vom Layer-Sprite übernehmen
		ghost.global_transform = layer_sprite.global_transform
		
		# Leicht nach hinten versetzen
		ghost.global_position -= _dodge_direction * 0.02 * (_afterimages_spawned + 1)
		ghost.global_position.y = layer_sprite.global_position.y
		
		# Fade-Animation pro Ghost
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(ghost, "modulate:a", 0.0, afterimage_fade_time).set_ease(Tween.EASE_IN)
		tween.tween_property(ghost, "scale", ghost.scale * 0.8, afterimage_fade_time).set_ease(Tween.EASE_IN)
		
		var end_pos: Vector3 = ghost.global_position + Vector3(0, 0.1, 0)
		tween.tween_property(ghost, "global_position", end_pos, afterimage_fade_time).set_ease(Tween.EASE_OUT)
		
		tween.chain().tween_callback(ghost.queue_free)


# ============================================
# VISUALS - SHIMMER TRAIL (FIXED)
# ============================================

func _start_shimmer_trail() -> void:
	if _player == null:
		return
	
	_shimmer_particles = GPUParticles3D.new()
	_shimmer_particles.emitting = true
	_shimmer_particles.amount = shimmer_amount
	_shimmer_particles.lifetime = shimmer_lifetime
	_shimmer_particles.explosiveness = 0.0
	_shimmer_particles.randomness = 0.5
	_shimmer_particles.fixed_fps = 60
	_shimmer_particles.interpolate = true
	
	# Process Material
	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc_mat.emission_sphere_radius = 0.15
	proc_mat.direction = Vector3(0, 1, 0)
	proc_mat.spread = 30.0
	proc_mat.initial_velocity_min = 0.5
	proc_mat.initial_velocity_max = 1.5
	proc_mat.gravity = Vector3(0, 1.5, 0)
	proc_mat.damping_min = 1.0
	proc_mat.damping_max = 2.0
	
	proc_mat.scale_min = 0.8
	proc_mat.scale_max = 1.5
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.5, 0.6))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_curve_tex := CurveTexture.new()
	scale_curve_tex.curve = scale_curve
	proc_mat.scale_curve = scale_curve_tex
	
	var gradient := Gradient.new()
	gradient.set_color(0, shimmer_color)
	gradient.add_point(0.3, Color(shimmer_color.r * 0.8, shimmer_color.g * 0.9, shimmer_color.b, 0.7))
	gradient.set_color(gradient.get_point_count() - 1, Color(shimmer_color.r * 0.5, shimmer_color.g * 0.7, shimmer_color.b, 0.0))
	
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	proc_mat.color_ramp = gradient_tex
	
	_shimmer_particles.process_material = proc_mat
	
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.06, 0.06)
	
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_mat.albedo_color = Color.WHITE
	mesh_mat.emission_enabled = true
	mesh_mat.emission = shimmer_color
	mesh_mat.emission_energy_multiplier = 3.0
	mesh.material = mesh_mat
	
	_shimmer_particles.draw_pass_1 = mesh
	
	_player.add_child(_shimmer_particles)
	_shimmer_particles.position = Vector3(0, 0.3, 0)


func _cleanup_shimmer() -> void:
	if _shimmer_particles != null and is_instance_valid(_shimmer_particles):
		_shimmer_particles.emitting = false
		_shimmer_particles.queue_free()
		_shimmer_particles = null


# ============================================
# SOUND
# ============================================

func _play_dodge_sound() -> void:
	if dodge_sounds.is_empty():
		return
	
	var audio := AudioStreamPlayer3D.new()
	audio.stream = dodge_sounds.pick_random()
	audio.volume_db = dodge_volume_db
	audio.pitch_scale = randf_range(0.95, 1.05)
	
	if _player:
		audio.global_position = _player.global_position
	
	get_tree().current_scene.add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

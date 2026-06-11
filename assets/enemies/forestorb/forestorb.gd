extends Enemy
class_name ForestOrb

## Unheimlich leuchtender Waldorb
## Umkreist den Spieler, zieht eng an ihm vorbei (Scheinattacken),
## dann kommt der echte Charge-Angriff.
## Frei fliegend (keine Gravitation), mit OmniLight3D + Sprite-Glow-Pulse.

# === MOVEMENT ===
@export_group("Movement")
@export var FLOAT_SPEED: float = 2.0
@export var hover_height: float = 0.35
@export var bob_amplitude: float = 0.15
@export var bob_frequency: float = 1.5

# === ORBIT ===
@export_group("Orbit")
@export var orbit_radius: float = 2.5
@export var orbit_radius_variance: float = 0.5
@export var orbit_speed_min: float = 1.2
@export var orbit_speed_max: float = 3.0
@export var orbit_speed_change_rate: float = 1.5
@export var orbit_direction_change_chance: float = 0.15

# === SWOOP (enge Vorbeiflüge) ===
@export_group("Swoop")
@export var swoop_radius: float = 0.35  ## Wie nah am Spieler der Orb vorbeizieht
@export var swoop_speed_multiplier: float = 2.5  ## Geschwindigkeitsfaktor beim Swoop
@export var swoop_tighten_speed: float = 4.0  ## Wie schnell der Radius schrumpft
@export var swoop_widen_speed: float = 2.0  ## Wie schnell er sich zurückzieht
@export var swoop_pass_angle: float = 2.5  ## Radiant — wie viel Winkel der enge Vorbeiflug dauert
@export var swoops_before_attack_min: int = 2
@export var swoops_before_attack_max: int = 4
@export var swoop_interval_min: float = 1.5
@export var swoop_interval_max: float = 3.0

# === ATTACK ===
@export_group("Attack")
@export var damage: int = 10
@export var charge_speed: float = 10.0
@export var charge_max_duration: float = 1.0
@export var attack_cooldown: float = 2.0
@export var charge_hit_radius: float = 0.4

@export var windup_duration: float = 0.8
@export var windup_vibrate_amplitude: float = 0.04   ## Vibrations-Stärke in Metern
@export var windup_vibrate_frequency: float = 35.0   ## Vibrations-Tempo (Hz)
@export var windup_glow_color: Color = Color(1.0, 0.1, 0.05, 1.0)  ## Sattes Rot
@export var windup_glow_energy: float = 4.0
@export var windup_glow_pulse_speed: float = 6.0

# === GLOW ===
@export_group("Glow")
@export var glow_color: Color = Color(0.3, 0.8, 0.2, 1.0)
@export var glow_energy: float = 1.5
@export var glow_radius: float = 3.0
@export var glow_pulse_speed: float = 2.0
@export var glow_pulse_intensity: float = 0.3
@export var glow_charge_energy: float = 3.0
@export var glow_charge_color: Color = Color(0.8, 0.2, 0.1, 1.0)
@export var glow_swoop_energy: float = 2.2
@export var glow_swoop_color: Color = Color(0.5, 0.9, 0.15, 1.0)

# === MINI ORBS VFX ===
@export_group("Mini Orbs")
@export var mini_orb_count: int = 3
@export var mini_orb_radius: float = 0.3
@export var mini_orb_speed: float = 3.0
@export var mini_orb_size: float = 0.06
@export var mini_orb_color: Color = Color(0.4, 1.0, 0.3, 0.8)
@export var mini_orb_bob_amplitude: float = 0.05
@export var mini_orb_bob_speed: float = 4.0
@export var mini_orb_charge_radius: float = 0.15
@export var mini_orb_charge_speed: float = 8.0

# === ANIMATION ===
@export_group("Animation")
@export var DIRECTION_HYSTERESIS: float = 20.0

@export_group("Death Fall")
@export var death_fall_gravity: float = 18.0
@export var death_fall_max_speed: float = 12.0
@export var death_fall_ground_offset: float = 0.05  ## Wie hoch über _spawn-Boden er liegen bleibt
@export var death_fall_timeout: float = 2.0         ## Sicherheits-Timeout falls kein Boden gefunden wird
@export var death_fall_wobble: float = 6.0


# === FRAME DEFINITIONS ===
const IDLE_FRAMES := {
	DirMode.RIGHT: 0,
	DirMode.DOWN_RIGHT: 2,
	DirMode.DOWN: 4,
	DirMode.DOWN_LEFT: 2,
	DirMode.LEFT: 0,
	DirMode.UP_LEFT: 6,
	DirMode.UP: 8,
	DirMode.UP_RIGHT: 6,
}

const FLIPPED_DIRS := [DirMode.DOWN_LEFT, DirMode.LEFT, DirMode.UP_LEFT]


# === DIRECTION ===
enum DirMode {
	RIGHT, DOWN_RIGHT, DOWN, DOWN_LEFT,
	LEFT, UP_LEFT, UP, UP_RIGHT
}
var _facing_dir: DirMode = DirMode.DOWN


# === STATE MACHINE ===
enum State {
	PATROL_IDLE,
	PATROL_FLOAT,
	ALERT,
	ORBIT,
	SWOOP_TIGHTEN,
	SWOOP_PASS,
	SWOOP_WIDEN,
	ATTACK_WINDUP,
	ATTACK_CHARGE,
	ATTACK_COOLDOWN,
	HIT,
	DEAD
}
var _state: State = State.PATROL_IDLE
var _state_timer: float = 0.0

# === ORBIT ===
var _orbit_angle: float = 0.0
var _orbit_speed_current: float = 2.0
var _orbit_speed_target: float = 2.0
var _orbit_direction: float = 1.0
var _orbit_timer: float = 0.0
var _current_orbit_radius: float = 2.5
var _target_orbit_radius: float = 2.5
var _base_orbit_radius: float = 2.5

# === SWOOP ===
var _swoop_count: int = 0
var _swoops_needed: int = 3
var _swoop_angle_traveled: float = 0.0

# === ATTACK ===
var _charge_direction: Vector3 = Vector3.ZERO
var _attack_cooldown_timer: float = 0.0
var _has_hit_player: bool = false

# === PATROL ===
var _patrol_target: Vector3

# === BOBBING ===
var _bob_time: float = 0.0

# === GLOW ===
var _glow_light: OmniLight3D = null
var _glow_time: float = 0.0

# === HITBOX ===
var _charge_hitbox: Area3D = null

# === MINI ORBS ===
var _mini_orbs: Array[MeshInstance3D] = []
var _mini_orb_lights: Array[OmniLight3D] = []
var _mini_orb_angles: Array[float] = []
var _mini_orb_time: float = 0.0

var _windup_origin: Vector3 = Vector3.ZERO
var _windup_time: float = 0.0

var _death_fall_velocity: float = 0.0
var _death_ground_y: float = 0.0
var _death_has_ground: bool = false

# === LIFECYCLE ===

func _on_ready_after_terrain() -> void:
	_last_position_check = global_position
	_state = State.PATROL_IDLE
	_state_timer = randf_range(patrol_wait_time_min, patrol_wait_time_max)
	_bob_time = randf() * TAU
	_setup_glow()
	_setup_charge_hitbox()
	_setup_mini_orbs()

	global_position.y = _spawn_position.y + hover_height
	_spawn_position.y = global_position.y


func _setup_glow() -> void:
	_glow_light = OmniLight3D.new()
	_glow_light.name = "GlowLight"
	_glow_light.light_color = glow_color
	_glow_light.light_energy = glow_energy
	_glow_light.omni_range = glow_radius
	_glow_light.omni_attenuation = 2.0
	_glow_light.shadow_enabled = false
	add_child(_glow_light)


func _setup_charge_hitbox() -> void:
	_charge_hitbox = Area3D.new()
	_charge_hitbox.name = "ChargeHitbox"
	_charge_hitbox.collision_layer = 0
	_charge_hitbox.collision_mask = 1
	_charge_hitbox.monitoring = false

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = charge_hit_radius
	shape.shape = sphere
	_charge_hitbox.add_child(shape)
	_charge_hitbox.body_entered.connect(_on_charge_hit)
	add_child(_charge_hitbox)


func _setup_mini_orbs() -> void:
	for i in range(mini_orb_count):
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "MiniOrb_%d" % i
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = mini_orb_size
		sphere_mesh.height = mini_orb_size * 2.0
		sphere_mesh.radial_segments = 8
		sphere_mesh.rings = 4
		mesh_instance.mesh = sphere_mesh

		var material := StandardMaterial3D.new()
		material.albedo_color = mini_orb_color
		material.emission_enabled = true
		material.emission = mini_orb_color
		material.emission_energy_multiplier = 2.0
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_instance.material_override = material

		add_child(mesh_instance)
		_mini_orbs.append(mesh_instance)

		var light := OmniLight3D.new()
		light.name = "MiniOrbLight_%d" % i
		light.light_color = mini_orb_color
		light.light_energy = 0.3
		light.omni_range = 0.5
		light.omni_attenuation = 2.0
		light.shadow_enabled = false
		mesh_instance.add_child(light)
		_mini_orb_lights.append(light)

		_mini_orb_angles.append((TAU / mini_orb_count) * i)


# === PHYSICS (Override: kein Gravity) ===

func _physics_process(delta: float) -> void:
	if _is_dead:
		_process_death(delta)
		_update_mini_orbs(delta)
		return

	if _is_invincible:
		_invincibility_timer -= delta
		if _invincibility_timer <= 0.0:
			_is_invincible = false

	_process_ai(delta)
	_update_bob(delta)
	_update_glow(delta)
	_update_mini_orbs(delta)

	move_and_slide()


func _update_bob(delta: float) -> void:
	_bob_time += delta * bob_frequency * TAU
	var bob_offset := sin(_bob_time) * bob_amplitude
	if sprite:
		sprite.position.y = bob_offset
	if _glow_light:
		_glow_light.position.y = bob_offset


func _update_glow(delta: float) -> void:
	if _glow_light == null:
		return

	_glow_time += delta
	var pulse := sin(_glow_time * glow_pulse_speed * TAU) * glow_pulse_intensity

	match _state:
		State.ATTACK_WINDUP:
			var ramp := clampf(_windup_time / maxf(windup_duration, 0.01), 0.0, 1.0)
			var fast_pulse := sin(_windup_time * windup_glow_pulse_speed * TAU) * glow_pulse_intensity
			_glow_light.light_color = windup_glow_color
			_glow_light.light_energy = lerpf(glow_swoop_energy, windup_glow_energy, ramp) + fast_pulse
		State.ATTACK_CHARGE:
			_glow_light.light_color = glow_charge_color
			_glow_light.light_energy = glow_charge_energy + pulse
		State.SWOOP_TIGHTEN, State.SWOOP_PASS:
			_glow_light.light_color = glow_swoop_color
			_glow_light.light_energy = glow_swoop_energy + pulse
		_:
			_glow_light.light_color = glow_color
			_glow_light.light_energy = glow_energy + pulse
			

	if sprite and _state != State.HIT:
		if _state == State.ATTACK_WINDUP:
			var red_pulse := 0.7 + sin(_windup_time * windup_glow_pulse_speed * TAU) * 0.3
			sprite.modulate = Color(1.0, red_pulse * 0.4, red_pulse * 0.3, 1.0)
		else:
			var glow_mod := 1.0 + pulse * 0.3
			sprite.modulate = Color(glow_mod, glow_mod, glow_mod, 1.0)


func _update_mini_orbs(delta: float) -> void:
	_mini_orb_time += delta

	var is_charging := _state == State.ATTACK_CHARGE or _state == State.ATTACK_WINDUP
	var current_speed := mini_orb_charge_speed if is_charging else mini_orb_speed
	var current_radius := mini_orb_charge_radius if is_charging else mini_orb_radius

	for i in range(_mini_orbs.size()):
		_mini_orb_angles[i] += current_speed * delta

		var angle := _mini_orb_angles[i]
		var bob := sin(_mini_orb_time * mini_orb_bob_speed + angle) * mini_orb_bob_amplitude
		var orb_pos := Vector3(
			cos(angle) * current_radius,
			bob,
			sin(angle) * current_radius
		)
		_mini_orbs[i].position = orb_pos

		# Fade bei Tod
		if _is_dead and sprite:
			var mat := _mini_orbs[i].material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = sprite.modulate.a
				mat.emission_energy_multiplier = 2.0 * sprite.modulate.a
			_mini_orb_lights[i].light_energy = 0.3 * sprite.modulate.a


# === MAIN AI LOOP ===

func _process_ai(delta: float) -> void:
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta

	if _state not in [State.DEAD, State.HIT, State.ATTACK_WINDUP, State.ATTACK_CHARGE, State.SWOOP_TIGHTEN, State.SWOOP_PASS, State.SWOOP_WIDEN]:
		_check_player_detection()

	match _state:
		State.PATROL_IDLE:
			_process_patrol_idle(delta)
		State.PATROL_FLOAT:
			_process_patrol_float(delta)
		State.ALERT:
			_process_alert(delta)
		State.ORBIT:
			_process_orbit(delta)
		State.SWOOP_TIGHTEN:
			_process_swoop_tighten(delta)
		State.SWOOP_PASS:
			_process_swoop_pass(delta)
		State.SWOOP_WIDEN:
			_process_swoop_widen(delta)
		State.ATTACK_CHARGE:
			_process_attack_charge(delta)
		State.ATTACK_COOLDOWN:
			_process_attack_cooldown(delta)
		State.HIT:
			_process_hit(delta)
		State.ATTACK_WINDUP:
			_process_attack_windup(delta)


# === PLAYER DETECTION ===

func _check_player_detection() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var distance := global_position.distance_to(player.global_position)
	if distance <= detection_range:
		if _state in [State.PATROL_IDLE, State.PATROL_FLOAT]:
			_target = player
			_enter_state(State.ALERT)
	elif distance > lose_interest_range:
		if _state in [State.ORBIT, State.ATTACK_COOLDOWN]:
			_target = null
			_enter_state(State.PATROL_IDLE)


# === STATE MANAGEMENT ===

func _enter_state(new_state: State) -> void:
	_state = new_state
	_anim_time = 0.0

	match new_state:
		State.PATROL_IDLE:
			_state_timer = randf_range(patrol_wait_time_min, patrol_wait_time_max)
			velocity = Vector3.ZERO
			_reset_stuck_detection()

		State.PATROL_FLOAT:
			_patrol_target = _get_random_patrol_point()
			_patrol_target.y = _spawn_position.y
			_reset_stuck_detection()

		State.ALERT:
			_state_timer = alert_duration
			velocity = Vector3.ZERO
			spawn_alert_popup()
			_face_target()

		State.ORBIT:
			_reset_stuck_detection()
			_orbit_speed_current = orbit_speed_min
			_orbit_speed_target = randf_range(orbit_speed_min, orbit_speed_max)
			_orbit_direction = 1.0 if randf() > 0.5 else -1.0
			_orbit_timer = randf_range(swoop_interval_min, swoop_interval_max)
			_base_orbit_radius = orbit_radius + randf_range(-orbit_radius_variance, orbit_radius_variance)
			_current_orbit_radius = _base_orbit_radius
			_target_orbit_radius = _base_orbit_radius
			_swoop_count = 0
			_swoops_needed = randi_range(swoops_before_attack_min, swoops_before_attack_max)
			_sync_orbit_angle()

		State.SWOOP_TIGHTEN:
			_target_orbit_radius = swoop_radius
			_orbit_speed_target = orbit_speed_max * swoop_speed_multiplier

		State.SWOOP_PASS:
			_swoop_angle_traveled = 0.0

		State.SWOOP_WIDEN:
			_target_orbit_radius = _base_orbit_radius
			_orbit_speed_target = randf_range(orbit_speed_min, orbit_speed_max)

		State.ATTACK_WINDUP:
			_state_timer = windup_duration
			_windup_time = 0.0
			_windup_origin = global_position
			velocity = Vector3.ZERO
			_face_target()
			
		State.ATTACK_CHARGE:
			_has_hit_player = false
			_state_timer = charge_max_duration
			_charge_hitbox.monitoring = true
			if _target and is_instance_valid(_target):
				var target_center := _target.global_position + Vector3(0, hover_height * 0.5, 0)
				_charge_direction = (target_center - global_position).normalized()

		State.ATTACK_COOLDOWN:
			_charge_hitbox.monitoring = false
			_attack_cooldown_timer = attack_cooldown
			_state_timer = 0.8
			velocity = Vector3.ZERO

		State.HIT:
			_hit_timer = 0.3
			_charge_hitbox.monitoring = false
			_reset_stuck_detection()


# === STATE PROCESSORS ===

func _process_patrol_idle(delta: float) -> void:
	_animate_idle()
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.PATROL_FLOAT)


func _process_patrol_float(delta: float) -> void:
	var dir := (_patrol_target - global_position)
	var dist := dir.length()

	if dist < 0.3:
		_enter_state(State.PATROL_IDLE)
		return

	dir = dir.normalized()
	var move_dir_xz := Vector3(dir.x, 0, dir.z)
	if move_dir_xz.length() > 0.01:
		_update_facing_direction(move_dir_xz.normalized())

	velocity = dir * FLOAT_SPEED

	_animate_idle()

	if _check_if_stuck(delta):
		_enter_state(State.PATROL_IDLE)


func _process_alert(delta: float) -> void:
	_animate_idle()
	_face_target()

	_state_timer -= delta
	if _state_timer <= 0.0:
		if _target and is_instance_valid(_target):
			_enter_state(State.ORBIT)
		else:
			_enter_state(State.PATROL_IDLE)


func _process_orbit(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state(State.PATROL_IDLE)
		return

	var dist_to_target := global_position.distance_to(_target.global_position)
	if dist_to_target > lose_interest_range:
		_target = null
		_enter_state(State.PATROL_IDLE)
		return

	_update_orbit_speed(delta)
	_advance_orbit(delta)
	_animate_idle()

	_orbit_timer -= delta
	if _orbit_timer <= 0.0:
		if _swoop_count >= _swoops_needed and _attack_cooldown_timer <= 0.0:
			_enter_state(State.ATTACK_WINDUP)
		else:
			_enter_state(State.SWOOP_TIGHTEN)


func _process_swoop_tighten(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state(State.PATROL_IDLE)
		return

	_current_orbit_radius = move_toward(_current_orbit_radius, _target_orbit_radius, swoop_tighten_speed * delta)
	_orbit_speed_current = move_toward(_orbit_speed_current, _orbit_speed_target, orbit_speed_change_rate * 3.0 * delta)

	_advance_orbit(delta)
	_animate_idle()

	if absf(_current_orbit_radius - swoop_radius) < 0.05:
		_enter_state(State.SWOOP_PASS)


func _process_swoop_pass(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state(State.PATROL_IDLE)
		return

	_advance_orbit(delta)
	_animate_idle()

	_swoop_angle_traveled += absf(_orbit_speed_current * _orbit_direction * delta)

	if _swoop_angle_traveled >= swoop_pass_angle:
		_swoop_count += 1
		_enter_state(State.SWOOP_WIDEN)


func _process_swoop_widen(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		_enter_state(State.PATROL_IDLE)
		return

	_current_orbit_radius = move_toward(_current_orbit_radius, _target_orbit_radius, swoop_widen_speed * delta)
	_orbit_speed_current = move_toward(_orbit_speed_current, _orbit_speed_target, orbit_speed_change_rate * delta)

	_advance_orbit(delta)
	_animate_idle()

	if absf(_current_orbit_radius - _base_orbit_radius) < 0.1:
		# Zurück in ORBIT ohne swoop_count/swoops_needed zu resetten
		_orbit_timer = randf_range(swoop_interval_min, swoop_interval_max)
		_state = State.ORBIT
		_target_orbit_radius = _base_orbit_radius
		_orbit_speed_target = randf_range(orbit_speed_min, orbit_speed_max)


func _process_attack_charge(delta: float) -> void:
	velocity = _charge_direction * charge_speed

	_face_target()
	_animate_idle()

	_state_timer -= delta
	if _state_timer <= 0.0 or _has_hit_player:
		_enter_state(State.ATTACK_COOLDOWN)

func _process_attack_windup(delta: float) -> void:
	_windup_time += delta
	velocity = Vector3.ZERO

	# Schweben halten + hochfrequentes Vibrieren um den Ursprung
	var vib_x := sin(_windup_time * windup_vibrate_frequency * TAU) * windup_vibrate_amplitude
	var vib_z := cos(_windup_time * windup_vibrate_frequency * TAU * 1.3) * windup_vibrate_amplitude
	global_position.x = _windup_origin.x + vib_x
	global_position.z = _windup_origin.z + vib_z

	_face_target()
	_animate_idle()

	_state_timer -= delta
	if _state_timer <= 0.0:
		global_position.x = _windup_origin.x
		global_position.z = _windup_origin.z
		_enter_state(State.ATTACK_CHARGE)

func _process_attack_cooldown(delta: float) -> void:
	_animate_idle()

	_state_timer -= delta
	if _state_timer <= 0.0:
		if _target and is_instance_valid(_target):
			var dist := global_position.distance_to(_target.global_position)
			if dist <= lose_interest_range:
				_enter_state(State.ORBIT)
			else:
				_target = null
				_enter_state(State.PATROL_IDLE)
		else:
			_enter_state(State.PATROL_IDLE)


func _process_hit(delta: float) -> void:
	_hit_timer -= delta

	velocity.x = _knockback_velocity.x
	velocity.y = 0.0
	velocity.z = _knockback_velocity.z
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, knockback_strength * 3.0 * delta)

	var flash := fmod(_anim_time, hit_flash_duration * 2.0) < hit_flash_duration
	if sprite:
		sprite.frame = IDLE_FRAMES[_facing_dir]
		sprite.flip_h = _facing_dir in FLIPPED_DIRS
		sprite.modulate = Color(1.5, 0.5, 0.5) if flash else Color.WHITE
	_anim_time += delta

	if _hit_timer <= 0.0:
		if _health <= 0:
			_die()
		elif _target and is_instance_valid(_target):
			_enter_state(State.ORBIT)
		else:
			_enter_state(State.PATROL_IDLE)


# === ORBIT HELPERS ===

func _sync_orbit_angle() -> void:
	if _target and is_instance_valid(_target):
		var to_self := global_position - _target.global_position
		to_self.y = 0
		_orbit_angle = atan2(to_self.z, to_self.x)


func _update_orbit_speed(delta: float) -> void:
	_orbit_speed_current = move_toward(_orbit_speed_current, _orbit_speed_target, orbit_speed_change_rate * delta)
	if absf(_orbit_speed_current - _orbit_speed_target) < 0.1:
		_orbit_speed_target = randf_range(orbit_speed_min, orbit_speed_max)

	if randf() < orbit_direction_change_chance * delta:
		_orbit_direction *= -1.0


func _advance_orbit(delta: float) -> void:
	if not _target or not is_instance_valid(_target):
		return

	_orbit_angle += _orbit_speed_current * _orbit_direction * delta

	var target_pos := _target.global_position
	var orbit_pos := Vector3(
		target_pos.x + cos(_orbit_angle) * _current_orbit_radius,
		target_pos.y + hover_height,
		target_pos.z + sin(_orbit_angle) * _current_orbit_radius
	)

	var to_orbit := orbit_pos - global_position
	var move_speed := _orbit_speed_current * _current_orbit_radius
	velocity = to_orbit.normalized() * minf(move_speed, to_orbit.length() / maxf(delta, 0.001))

	var move_dir_xz := Vector3(velocity.x, 0, velocity.z)
	if move_dir_xz.length() > 0.1:
		_update_facing_direction(move_dir_xz.normalized())


# === CHARGE HIT ===

func _on_charge_hit(body: Node3D) -> void:
	if _has_hit_player:
		return

	if body.is_in_group("player") and body.has_method("take_damage"):
		_has_hit_player = true
		body.take_damage(damage, global_position)


# === DEATH (Custom: Dissolve + Glow-Fade) ===

func _process_death_custom(delta: float) -> bool:
	match _death_phase:
		0:  # Hold
			_death_timer += delta
			if sprite:
				sprite.frame = IDLE_FRAMES[_facing_dir]
				sprite.flip_h = _facing_dir in FLIPPED_DIRS
				sprite.modulate = Color.WHITE

			if _death_timer >= death_hold_time:
				# Glow erlischt schlagartig – die Magie verlässt den Orb
				if _glow_light:
					_glow_light.light_energy = 0.0
				_death_fall_velocity = 0.0
				_death_ground_y = _find_death_ground()
				_death_phase = 1
				_death_timer = 0.0
			return true

		1:  # Fall wie ein Stein
			_death_timer += delta
			_death_fall_velocity = minf(_death_fall_velocity + death_fall_gravity * delta, death_fall_max_speed)
			global_position.y -= _death_fall_velocity * delta

			# Sprite kippelt leicht im Fall
			if sprite:
				var wobble := sin(_death_timer * 18.0) * deg_to_rad(death_fall_wobble)
				sprite.rotation.z = wobble

			var landed := _death_has_ground and global_position.y <= _death_ground_y + death_fall_ground_offset
			if landed:
				global_position.y = _death_ground_y + death_fall_ground_offset
			if landed or _death_timer >= death_fall_timeout:
				if sprite:
					sprite.rotation.z = 0.0
				_give_rewards()
				_spawn_death_vfx()
				_death_phase = 2
				_death_timer = 0.0
			return true

		2:  # Dissolve mit Glow-Fade
			_death_timer += delta
			var progress := clampf(_death_timer / maxf(death_dissolve_time, 0.01), 0.0, 1.0)

			if sprite:
				sprite.modulate.a = 1.0 - progress

			if _glow_light:
				_glow_light.light_energy = 0.0  # bleibt aus

			if progress >= 1.0:
				_finish_death()
				return false
			return true

	return false


func _find_death_ground() -> float:
	# Raycast nach unten, um den echten Boden zu finden (Terrain3D / Collision Layer 1)
	var space := get_world_3d().direct_space_state
	var from := global_position
	var to := global_position + Vector3(0, -20.0, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [self]
	var result := space.intersect_ray(query)
	if result:
		_death_has_ground = true
		return result.position.y
	_death_has_ground = false
	return global_position.y - 10.0  # Fallback: fällt frei bis Timeout


# === DIRECTION ===

func _update_facing_direction(dir: Vector3) -> void:
	if dir.is_zero_approx():
		return

	var angle := atan2(dir.x, dir.z)
	angle = rad_to_deg(angle)
	if angle < 0:
		angle += 360.0

	var new_dir := _angle_to_direction(angle)

	if new_dir != _facing_dir:
		var current_center := _direction_to_center_angle(_facing_dir)
		var angle_diff := absf(_angle_difference(angle, current_center))
		if angle_diff > 22.5 + DIRECTION_HYSTERESIS:
			_facing_dir = new_dir


func _angle_to_direction(angle: float) -> DirMode:
	if angle >= 337.5 or angle < 22.5:
		return DirMode.DOWN
	elif angle >= 22.5 and angle < 67.5:
		return DirMode.DOWN_RIGHT
	elif angle >= 67.5 and angle < 112.5:
		return DirMode.RIGHT
	elif angle >= 112.5 and angle < 157.5:
		return DirMode.UP_RIGHT
	elif angle >= 157.5 and angle < 202.5:
		return DirMode.UP
	elif angle >= 202.5 and angle < 247.5:
		return DirMode.UP_LEFT
	elif angle >= 247.5 and angle < 292.5:
		return DirMode.LEFT
	else:
		return DirMode.DOWN_LEFT


func _direction_to_center_angle(dir: DirMode) -> float:
	match dir:
		DirMode.DOWN: return 0.0
		DirMode.DOWN_RIGHT: return 45.0
		DirMode.RIGHT: return 90.0
		DirMode.UP_RIGHT: return 135.0
		DirMode.UP: return 180.0
		DirMode.UP_LEFT: return 225.0
		DirMode.LEFT: return 270.0
		DirMode.DOWN_LEFT: return 315.0
		_: return 0.0


func _angle_difference(a: float, b: float) -> float:
	var diff := fmod(a - b + 180.0, 360.0) - 180.0
	return diff


# === ANIMATION ===

func _animate_idle() -> void:
	if sprite:
		sprite.frame = IDLE_FRAMES[_facing_dir]
		sprite.flip_h = _facing_dir in FLIPPED_DIRS


# === HELPERS ===

func _face_target() -> void:
	if _target and is_instance_valid(_target):
		var dir := (_target.global_position - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			_update_facing_direction(dir.normalized())


# === ENEMY OVERRIDES ===

func _on_damage_received(_amount: int, from_position: Vector3) -> void:
	var knockback_dir := (global_position - from_position).normalized()
	_update_facing_direction(-knockback_dir)
	_enter_state(State.HIT)


func _on_death() -> void:
	_charge_hitbox.monitoring = false
	velocity = Vector3.ZERO
	_state = State.DEAD


func _get_hurt_frame() -> Dictionary:
	var frame: int = IDLE_FRAMES[_facing_dir]
	var flip: bool = _facing_dir in FLIPPED_DIRS
	return {frame = frame, flip = flip}

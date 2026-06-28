## FishSchool
##
## Manager-Node pro Gewässer. Spawnt N Fische, treibt ALLE zentral in EINEM
## _physics_process (kein Per-Fisch-Node-Denken). Verantwortlich für:
##   - Boids-Steering (Separation immer; Alignment+Cohesion nur für schooling-Fische)
##   - Wander (organisches Umherschweifen)
##   - State-Machine IDLE/CRUISE/DART (treibt Velocity-Skalierung + Anim-Speed)
##   - Schwebe-Ebene (konstantes Boden-Y + Schwebehöhe + individuelles Bobbing)
##   - Wandschutz in zwei Stufen:
##       1) gestaffelte Whisker-Raycasts (weiches Wegdrehen, vorausschauend)
##       2) harter Kollisions-Cast pro Frame (Sicherheitsnetz gegen Wand-Clipping)
##   - Sprite-Animation (frame + flip_h direkt auf SmoothPixelSprite3D)
##
## Boden ist konstant bei Y pro Zone -> keine Down-Rays nötig.

@tool
class_name FishSchool
extends Node3D

# ============================================================
#  EXPORTS — Authoring
# ============================================================

@export_group("Spawn")
## Wie viele Fische in dieser Zone leben.
@export var fish_count: int = 30 : set = _set_fish_count
## Anteil der Fische, die schwärmen (Rest sind Einzelgänger). 0..1
@export_range(0.0, 1.0, 0.05) var schooling_ratio: float = 0.7
## Sprite-Sheet eines Fisches.
@export var fish_texture: Texture2D
## Spritesheet-Layout.
@export var hframes: int = 3
@export var vframes: int = 1
## Welt-Pixelgröße des Sprites (wie SmoothPixelSprite3D.pixel_size).
@export var sprite_pixel_size: float = 0.01
## Skalierungsvariation pro Fisch (1.0 = alle gleich groß; 0.2 = ±20%).
@export_range(0.0, 0.6, 0.05) var size_variation: float = 0.2
## Optionaler Spawn-Seed für reproduzierbare Verteilung.
@export var random_seed: int = 0

@export_group("Zone")
## Horizontale Ausdehnung der Wasserzone (lokale XZ-Halbgrößen).
@export var zone_extents: Vector2 = Vector2(8.0, 8.0)
## Boden-Y in Weltkoordinaten (konstant pro Zone).
@export var floor_y: float = 0.0
## Schwebehöhe über dem Boden (Mitte des Bobbing).
@export var hover_height: float = 0.6
## Amplitude des vertikalen Bobbing.
@export_range(0.0, 0.5, 0.01) var bob_amplitude: float = 0.08
## Geschwindigkeit des Bobbing.
@export var bob_speed: float = 1.5

@export_group("Movement")
## Normale Reisegeschwindigkeit (CRUISE).
@export var cruise_speed: float = 0.8
## Spitzengeschwindigkeit beim Darten.
@export var dart_speed: float = 3.0
## Maximale Lenkkraft (wie schnell Richtung geändert wird).
@export var steer_force: float = 4.0
## Wie stark Geschwindigkeit pro Frame geglättet wird (Trägheit).
@export_range(1.0, 20.0, 0.5) var velocity_damping: float = 6.0

@export_group("Boids")
## Radius, in dem Nachbarn wahrgenommen werden.
@export var neighbor_radius: float = 1.5
## Mindestabstand (Separation drückt darunter auseinander).
@export var separation_dist: float = 0.5
@export_range(0.0, 4.0, 0.1) var separation_weight: float = 2.0
@export_range(0.0, 4.0, 0.1) var alignment_weight: float = 1.0
@export_range(0.0, 4.0, 0.1) var cohesion_weight: float = 0.8
@export_range(0.0, 4.0, 0.1) var wander_weight: float = 1.0

@export_group("Wall Avoidance")
## Reichweite der vorausschauenden Whisker-Raycasts.
@export var whisker_length: float = 1.2
## Seitlicher Öffnungswinkel der Whisker (Grad).
@export var whisker_angle_deg: float = 30.0
## Wie stark der Fisch von Wänden weggedrückt wird.
@export_range(0.0, 8.0, 0.1) var avoid_weight: float = 4.0
## Collision-Mask für Wände (Layer 1 = Bit 0 = Wert 1).
@export_flags_3d_physics var wall_mask: int = 1
## Alle wie viele Frames ein Fisch seine Whisker neu castet (Staffelung).
@export var whisker_interval: int = 4

@export_group("State Machine")
## Wahrscheinlichkeit pro Sekunde, in IDLE zu wechseln.
@export_range(0.0, 1.0, 0.01) var idle_chance: float = 0.15
## Wahrscheinlichkeit pro Sekunde zu darten.
@export_range(0.0, 1.0, 0.01) var dart_chance: float = 0.12
## Dauerbereich IDLE (Sekunden).
@export var idle_duration: Vector2 = Vector2(0.8, 2.5)
## Dauerbereich DART (Sekunden).
@export var dart_duration: Vector2 = Vector2(0.25, 0.6)
## Dauerbereich CRUISE bevor neu gewürfelt wird.
@export var cruise_duration: Vector2 = Vector2(1.0, 3.0)

@export_group("Animation")
## Frame-Rate der Schwimm-Animation bei CRUISE.
@export var anim_fps_cruise: float = 6.0
## Frame-Rate bei DART (schnellerer Flossenschlag).
@export var anim_fps_dart: float = 14.0
## Frame-Rate bei IDLE (langsam).
@export var anim_fps_idle: float = 2.5

# ============================================================
#  INTERN
# ============================================================

var _fish: Array[FishData] = []
var _rng := RandomNumberGenerator.new()
var _frame_counter: int = 0
var _space: PhysicsDirectSpaceState3D = null

# Wiederverwendete Query (kein Alloc pro Cast).
var _ray_query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rng.seed = random_seed if random_seed != 0 else randi()
	_ray_query.collision_mask = wall_mask
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true
	_spawn_fish()


func _set_fish_count(value: int) -> void:
	fish_count = max(0, value)
	# Im Editor nur den Wert speichern; Spawn passiert zur Laufzeit.


# ------------------------------------------------------------
#  SPAWN
# ------------------------------------------------------------
func _spawn_fish() -> void:
	_clear_fish()
	for i in fish_count:
		var f := FishData.new()
		f.schooling = _rng.randf() < schooling_ratio

		# Position: zufällig in der Zone, auf Schwebe-Ebene.
		var lx := _rng.randf_range(-zone_extents.x, zone_extents.x)
		var lz := _rng.randf_range(-zone_extents.y, zone_extents.y)
		var local_pos := Vector3(lx, hover_height, lz)
		f.position = to_global(local_pos)
		f.position.y = floor_y + hover_height

		# Startrichtung zufällig in XZ.
		var ang := _rng.randf_range(0.0, TAU)
		f.heading = Vector3(cos(ang), 0.0, sin(ang))
		f.velocity = f.heading * cruise_speed
		f.dart_dir = f.heading

		f.bob_phase = _rng.randf_range(0.0, TAU)
		f.state = FishData.State.CRUISE
		f.state_timer = _rng.randf_range(cruise_duration.x, cruise_duration.y)
		f.anim_time = _rng.randf()
		f.ray_offset = i % max(1, whisker_interval)

		# Sprite-Node erzeugen.
		var spr := SmoothPixelSprite3D.new()
		spr.texture = fish_texture
		spr.hframes = hframes
		spr.vframes = vframes
		spr.pixel_size = sprite_pixel_size * _rng.randf_range(
			1.0 - size_variation, 1.0 + size_variation)
		spr.billboard_mode = SmoothPixelSprite3D.BillboardMode.Y_TILTED
		spr.frame = 0
		add_child(spr)
		spr.global_position = f.position
		f.sprite = spr

		_fish.append(f)


func _clear_fish() -> void:
	for f in _fish:
		if is_instance_valid(f.sprite):
			f.sprite.queue_free()
	_fish.clear()


# ------------------------------------------------------------
#  MAIN LOOP — zentral für alle Fische
# ------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _fish.is_empty():
		return

	_space = get_world_3d().direct_space_state
	_frame_counter += 1

	for i in _fish.size():
		var f: FishData = _fish[i]
		_update_state(f, delta)
		var steer := _compute_steering(f)
		_integrate(f, steer, delta)
		_apply_hover_and_bob(f, delta)
		_resolve_wall_collision(f)
		_write_sprite(f, delta)


# ------------------------------------------------------------
#  STATE MACHINE
# ------------------------------------------------------------
func _update_state(f: FishData, delta: float) -> void:
	f.state_timer -= delta
	if f.state_timer > 0.0:
		return

	# Timer abgelaufen -> nächsten State würfeln.
	match f.state:
		FishData.State.DART:
			# Nach Dart immer zurück in Cruise.
			f.state = FishData.State.CRUISE
			f.state_timer = _rng.randf_range(cruise_duration.x, cruise_duration.y)
		FishData.State.IDLE:
			f.state = FishData.State.CRUISE
			f.state_timer = _rng.randf_range(cruise_duration.x, cruise_duration.y)
		_:  # CRUISE
			var roll := _rng.randf()
			if roll < dart_chance:
				f.state = FishData.State.DART
				f.state_timer = _rng.randf_range(dart_duration.x, dart_duration.y)
				# Dart-Richtung = aktuelle Heading, leicht zufällig versetzt.
				var jitter := _rng.randf_range(-0.4, 0.4)
				f.dart_dir = f.heading.rotated(Vector3.UP, jitter).normalized()
			elif roll < dart_chance + idle_chance:
				f.state = FishData.State.IDLE
				f.state_timer = _rng.randf_range(idle_duration.x, idle_duration.y)
			else:
				f.state_timer = _rng.randf_range(cruise_duration.x, cruise_duration.y)


func _target_speed(f: FishData) -> float:
	match f.state:
		FishData.State.DART:
			return dart_speed
		FishData.State.IDLE:
			return 0.0
		_:
			return cruise_speed


# ------------------------------------------------------------
#  STEERING (Boids + Wander + Wall-Avoidance)
# ------------------------------------------------------------
func _compute_steering(f: FishData) -> Vector3:
	var steer := Vector3.ZERO

	# --- Nachbarschaft (eine Iteration; billig bei <=60) ---
	var sep := Vector3.ZERO
	var ali := Vector3.ZERO
	var coh := Vector3.ZERO
	var coh_count := 0
	var ali_count := 0

	for other in _fish:
		if other == f:
			continue
		var to := other.position - f.position
		to.y = 0.0
		var d := to.length()
		if d <= 0.0001 or d > neighbor_radius:
			continue

		# Separation gilt IMMER (auch Einzelgänger weichen aus).
		if d < separation_dist:
			sep -= to / d  # je näher, desto stärker weg

		# Alignment + Cohesion nur für Schwarm-Fische untereinander.
		if f.schooling and other.schooling:
			ali += other.velocity
			ali_count += 1
			coh += other.position
			coh_count += 1

	if sep != Vector3.ZERO:
		steer += sep.normalized() * separation_weight
	if ali_count > 0:
		ali /= float(ali_count)
		if ali != Vector3.ZERO:
			steer += ali.normalized() * alignment_weight
	if coh_count > 0:
		coh /= float(coh_count)
		var to_center := coh - f.position
		to_center.y = 0.0
		if to_center != Vector3.ZERO:
			steer += to_center.normalized() * cohesion_weight

	# --- Wander (organisches Schweifen) ---
	# Bei DART: Richtung ist eingefroren, kein Wander.
	if f.state == FishData.State.DART:
		steer += f.dart_dir * (steer_force * 1.5)
	else:
		var wander_ang := _rng.randf_range(-0.5, 0.5)
		var wander := f.heading.rotated(Vector3.UP, wander_ang)
		steer += wander * wander_weight

	# --- Soft-Boundary: zurück zur Zonenmitte, wenn nahe am Rand ---
	steer += _boundary_steer(f)

	# --- Whisker-Wandvermeidung (gestaffelt) ---
	steer += _whisker_avoidance(f)

	return steer


func _boundary_steer(f: FishData) -> Vector3:
	# Lokale Position relativ zur Zone.
	var local := to_local(f.position)
	var push := Vector3.ZERO
	var margin := 1.0
	if local.x > zone_extents.x - margin:
		push.x -= 1.0
	elif local.x < -zone_extents.x + margin:
		push.x += 1.0
	if local.z > zone_extents.y - margin:
		push.z -= 1.0
	elif local.z < -zone_extents.y + margin:
		push.z += 1.0
	if push != Vector3.ZERO:
		return (global_transform.basis * push).normalized() * (avoid_weight * 0.5)
	return Vector3.ZERO


# ------------------------------------------------------------
#  WHISKER RAYCASTS (Stufe 1: vorausschauend, weich)
# ------------------------------------------------------------
func _whisker_avoidance(f: FishData) -> Vector3:
	if _space == null:
		return Vector3.ZERO

	# Staffelung: nur alle whisker_interval Frames neu casten,
	# AUSSER im DART-State -> dann immer (Sicherheit beim Burst).
	var do_cast := f.state == FishData.State.DART \
		or (_frame_counter + f.ray_offset) % whisker_interval == 0
	if not do_cast:
		return Vector3.ZERO

	var dir := f.heading
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	dir = dir.normalized()

	var ang := deg_to_rad(whisker_angle_deg)
	var dirs := [
		dir,
		dir.rotated(Vector3.UP, ang),
		dir.rotated(Vector3.UP, -ang),
	]

	var avoid := Vector3.ZERO
	for d in dirs:
		_ray_query.from = f.position
		_ray_query.to = f.position + d * whisker_length
		var hit := _space.intersect_ray(_ray_query)
		if hit:
			# Weg von der Wand entlang der Normalen + Reststrecke gewichtet.
			var n: Vector3 = hit.normal
			n.y = 0.0
			var dist: float = f.position.distance_to(hit.position)
			var strength := 1.0 - clampf(dist / whisker_length, 0.0, 1.0)
			avoid += n.normalized() * strength

	if avoid != Vector3.ZERO:
		return avoid.normalized() * avoid_weight
	return Vector3.ZERO


# ------------------------------------------------------------
#  INTEGRATION
# ------------------------------------------------------------
func _integrate(f: FishData, steer: Vector3, delta: float) -> void:
	steer.y = 0.0
	# Lenkkraft begrenzen.
	if steer.length() > steer_force:
		steer = steer.normalized() * steer_force

	var target_speed := _target_speed(f)
	var desired := f.velocity + steer * delta

	# Auf Zielgeschwindigkeit bringen (smooth).
	var cur_speed := desired.length()
	if cur_speed > 0.0001:
		var new_speed := lerpf(cur_speed, target_speed,
			clampf(velocity_damping * delta, 0.0, 1.0))
		desired = desired.normalized() * new_speed
	desired.y = 0.0

	f.velocity = desired
	f.position += f.velocity * delta

	# Heading glätten (für Whisker + Sprite-Flip).
	if f.velocity.length_squared() > 0.0001:
		f.heading = f.heading.lerp(f.velocity.normalized(),
			clampf(8.0 * delta, 0.0, 1.0)).normalized()


# ------------------------------------------------------------
#  SCHWEBE-EBENE + BOBBING
# ------------------------------------------------------------
func _apply_hover_and_bob(f: FishData, delta: float) -> void:
	f.bob_phase += bob_speed * delta
	var bob := sin(f.bob_phase) * bob_amplitude
	f.position.y = floor_y + hover_height + bob


# ------------------------------------------------------------
#  HARTE KOLLISION (Stufe 2: Sicherheitsnetz pro Frame)
# ------------------------------------------------------------
func _resolve_wall_collision(f: FishData) -> void:
	if _space == null:
		return
	var vel_xz := Vector3(f.velocity.x, 0.0, f.velocity.z)
	if vel_xz.length_squared() < 0.0001:
		return

	var step := vel_xz.length() * get_physics_process_delta_time()
	var look := maxf(step + 0.15, 0.2)  # kurz, nur Sicherheitsnetz
	_ray_query.from = f.position
	_ray_query.to = f.position + vel_xz.normalized() * look
	var hit := _space.intersect_ray(_ray_query)
	if hit:
		# Position direkt vor der Wand klemmen.
		var n: Vector3 = hit.normal
		n.y = 0.0
		if n != Vector3.ZERO:
			n = n.normalized()
		f.position = hit.position + n * 0.1
		f.position.y = floor_y + hover_height
		# Velocity an Wand reflektieren (gleitet entlang).
		var v := Vector3(f.velocity.x, 0.0, f.velocity.z)
		f.velocity = v.bounce(n) * 0.5
		f.heading = f.velocity.normalized() if f.velocity.length_squared() > 0.0001 else n


# ------------------------------------------------------------
#  SPRITE: Position, Flip, Frame-Animation
# ------------------------------------------------------------
func _write_sprite(f: FishData, delta: float) -> void:
	if not is_instance_valid(f.sprite):
		return
	f.sprite.global_position = f.position

	# Seitliches Flippen: Sprite zeigt von der Seite.
	# Heading.x < 0 -> nach links -> flip.
	if absf(f.heading.x) > 0.05:
		f.sprite.flip_h = f.heading.x < 0.0

	# Frame-Animation je nach State.
	var fps := anim_fps_cruise
	match f.state:
		FishData.State.DART:
			fps = anim_fps_dart
		FishData.State.IDLE:
			fps = anim_fps_idle
	f.anim_time += delta * fps
	var total_frames := hframes * vframes
	if total_frames > 1:
		f.sprite.frame = int(f.anim_time) % total_frames


func _exit_tree() -> void:
	_clear_fish()

## FishManager
##
## EINE Node pro Gewässer. Sammelt alle FishSpawnPoint-Kinder (Marker3D mit
## fish_spawn_point.gd) ein, spawnt deren Fische und treibt ALLE zentral in
## EINEM _physics_process. Kein Per-Fisch-Node, kein Per-Marker-Update.
##
## Pro Fisch:
##   - Boids: Separation immer; Alignment+Cohesion nur für schooling-Gruppen
##   - State-Machine IDLE / CRUISE / DART (ruckartiges, lebendiges Verhalten)
##   - Home-Pull: weicher Zug zum Marker, NUR wenn zu weit weg (kein Käfig)
##   - feste Schwebehöhe = Y des Markers + Bobbing
##   - Wandschutz: gestaffelte Whisker-Raycasts + harter Sicherheits-Cast
##   - Sprite-Animation (frame + flip_h auf SmoothPixelSprite3D)
##
## Setup:
##   FishManager (diese Node — EIGENSTÄNDIG, NICHT unter dem Wasser-Mesh!
##                Wasser-Meshes sind oft stark/nicht-uniform skaliert; als
##                Kind davon würden die Sprites diese Streckung erben. Häng
##                den Manager als unskalierte Geschwister-Node neben das Wasser.)
##    ├─ FishSpawnPoint (Marker3D + fish_spawn_point.gd)
##    ├─ FishSpawnPoint
##    └─ ...
##
## Der Fisch braucht das Wasser nicht: Er weicht nur Layer-1-Collisions aus
## und hält eine feste Y-Höhe (= Marker-Höhe). Keinerlei Abhängigkeit zum
## Wasser-Mesh.
##
## WICHTIG: fish_scene MUSS gesetzt sein (Root = SmoothPixelSprite3D),
## sonst sieht man nichts.

@tool
class_name FishManager
extends Node3D

# ============================================================
#  EXPORTS
# ============================================================

@export_group("Sprite")
## Die Fisch-Szene (Root = SmoothPixelSprite3D, im Editor korrekt konfiguriert
## mit Textur, hframes, vframes, pixel_size, billboard_mode = Full).
## Das ist der zuverlässige Weg — wie der Goblin-Sprite.
@export var fish_scene: PackedScene
## Optionaler Textur-Override (falls eine Szene für mehrere Fischarten genutzt
## wird). Leer lassen, um die Textur aus der Szene zu behalten.
@export var fish_texture_override: Texture2D
## Größenvariation pro Fisch (0 = alle gleich; 0.2 = ±20%).
## Multipliziert die pixel_size, die in der Szene gesetzt ist.
@export_range(0.0, 0.6, 0.05) var size_variation: float = 0.2

@export_group("Movement")
@export var cruise_speed: float = 0.8
@export var dart_speed: float = 3.0
@export var steer_force: float = 4.0
@export_range(1.0, 20.0, 0.5) var velocity_damping: float = 6.0
## Vertikales Bobbing um die Marker-Höhe.
@export_range(0.0, 0.5, 0.01) var bob_amplitude: float = 0.08
@export var bob_speed: float = 1.5

@export_group("Home Pull")
## Ab welchem Anteil des Radius der Fisch zurückgezogen wird (0.8 = ab 80%).
@export_range(0.3, 1.5, 0.05) var home_soft_edge: float = 0.8
## Wie stark der Rückzug ist, wenn er greift.
@export_range(0.0, 8.0, 0.1) var home_weight: float = 3.0
## Streifradius-Multiplikator für Einzelgänger (count == 1).
@export var loner_roam_multiplier: float = 1.5

@export_group("Boids")
@export var neighbor_radius: float = 1.5
@export var separation_dist: float = 0.5
@export_range(0.0, 4.0, 0.1) var separation_weight: float = 2.0
@export_range(0.0, 4.0, 0.1) var alignment_weight: float = 1.0
@export_range(0.0, 4.0, 0.1) var cohesion_weight: float = 0.8
@export_range(0.0, 4.0, 0.1) var wander_weight: float = 1.0

@export_group("Wall Avoidance")
@export var whisker_length: float = 1.8
@export var whisker_angle_deg: float = 35.0
@export_range(0.0, 8.0, 0.1) var avoid_weight: float = 6.0
## Collision-Mask für Wände (Layer 1 = Wert 1).
@export_flags_3d_physics var wall_mask: int = 1
@export var whisker_interval: int = 4

@export_group("State Machine")
@export_range(0.0, 1.0, 0.01) var idle_chance: float = 0.32
@export_range(0.0, 1.0, 0.01) var dart_chance: float = 0.10
@export var idle_duration: Vector2 = Vector2(1.2, 3.5)
@export var dart_duration: Vector2 = Vector2(0.25, 0.6)
@export var cruise_duration: Vector2 = Vector2(0.8, 2.2)

@export_group("Animation")
## Welche Frame-Indizes die Schwimm-Animation durchläuft.
## Das Sheet kann mehr Slots haben (hframes*vframes) als animierte Frames!
## Beispiel: 3x2-Sheet, aber nur Frame 0 und 1 nutzen -> [0, 1].
@export var swim_frames: PackedInt32Array = PackedInt32Array([0, 1])
@export var anim_fps_cruise: float = 6.0
@export var anim_fps_dart: float = 14.0
@export var anim_fps_idle: float = 2.5

@export_group("Debug")
## Gibt beim Start eine Zusammenfassung in die Konsole (Anzahl Fische etc.).
@export var verbose_spawn_log: bool = true

# ============================================================
#  INTERN
# ============================================================

var _fish: Array[FishData] = []
var _rng := RandomNumberGenerator.new()
var _frame_counter: int = 0
var _space: PhysicsDirectSpaceState3D = null
var _ray_query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# --- Validierung: häufigste "ich sehe nichts"-Ursachen abfangen ---
	if fish_scene == null:
		push_error("FishManager: 'fish_scene' ist nicht gesetzt — es werden KEINE Fische sichtbar sein. Weise die Fisch-Szene (Root = SmoothPixelSprite3D) im Inspector zu.")
		return

	_ray_query.collision_mask = wall_mask
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true

	_spawn_from_markers()


# ------------------------------------------------------------
#  SPAWN — aus allen FishSpawnPoint-Kindern
# ------------------------------------------------------------
func _spawn_from_markers() -> void:
	_clear_fish()

	var markers: Array[FishSpawnPoint] = []
	for child in get_children():
		if child is FishSpawnPoint:
			markers.append(child)

	if markers.is_empty():
		push_warning("FishManager: Keine FishSpawnPoint-Marker als Kinder gefunden. Füge Marker3D-Nodes mit fish_spawn_point.gd hinzu.")
		return

	var total := 0
	for marker in markers:
		_spawn_marker_fish(marker)
		total += max(0, marker.count)

	if verbose_spawn_log:
		print("FishManager: %d Marker, %d Fische gespawnt." % [markers.size(), _fish.size()])
		if _fish.size() != total:
			push_warning("FishManager: Erwartete %d Fische, aber %d gespawnt." % [total, _fish.size()])


func _spawn_marker_fish(marker: FishSpawnPoint) -> void:
	if marker.count < 1 or marker.radius <= 0.0:
		return

	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = marker.spawn_seed if marker.spawn_seed != 0 else randi()

	var home := marker.global_position  # feste Y-Höhe = Marker-Höhe
	var is_loner := marker.count == 1
	var roam := marker.radius * (loner_roam_multiplier if is_loner else 1.0)

	for i in marker.count:
		var f := FishData.new()
		# Einzelgänger sind nie schwärmend; Gruppen folgen Marker-Setting.
		f.schooling = marker.schooling and not is_loner
		f.home = home
		f.home_radius = roam

		# Startposition: zufällig in einem Kreis um den Marker.
		var ang := local_rng.randf_range(0.0, TAU)
		var dist := local_rng.randf_range(0.0, marker.radius * 0.8)
		f.position = home + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		f.position.y = home.y  # feste Höhe

		var hang := local_rng.randf_range(0.0, TAU)
		f.heading = Vector3(cos(hang), 0.0, sin(hang))
		f.velocity = f.heading * cruise_speed
		f.dart_dir = f.heading

		f.bob_phase = local_rng.randf_range(0.0, TAU)
		f.state = FishData.State.CRUISE
		f.state_timer = local_rng.randf_range(cruise_duration.x, cruise_duration.y)
		f.anim_time = local_rng.randf()
		f.ray_offset = _fish.size() % max(1, whisker_interval)

		# Sprite: Szene instanziieren (Goblin-Muster, zuverlässig).
		# Die Szene-Root ist ein SmoothPixelSprite3D, das im Editor bereits
		# korrekt mit Textur/hframes/vframes/pixel_size/billboard initialisiert
		# wurde. Beim instantiate() läuft _ready() mit den RICHTIGEN Werten —
		# kein Default-1x1-Problem, keine fragile Setter-Reihenfolge.
		var spr := fish_scene.instantiate() as SmoothPixelSprite3D
		if spr == null:
			push_error("FishManager: fish_scene-Root ist kein SmoothPixelSprite3D!")
			return

		var start_frame: int = swim_frames[0] if swim_frames.size() > 0 else 0

		add_child(spr)

		# Override nur, was pro Fisch variiert:
		if fish_texture_override != null:
			spr.texture = fish_texture_override
		spr.pixel_size = spr.pixel_size * local_rng.randf_range(
			1.0 - size_variation, 1.0 + size_variation)
		spr.frame = start_frame

		spr.global_position = f.position
		f.sprite = spr

		_fish.append(f)


func _clear_fish() -> void:
	for f in _fish:
		if is_instance_valid(f.sprite):
			f.sprite.queue_free()
	_fish.clear()


# ------------------------------------------------------------
#  MAIN LOOP
# ------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _fish.is_empty():
		return

	_space = get_world_3d().direct_space_state
	_frame_counter += 1

	for f in _fish:
		_update_state(f, delta)
		var steer := _compute_steering(f)
		_integrate(f, steer, delta)
		_apply_bob(f, delta)
		_resolve_wall_collision(f)
		_write_sprite(f, delta)


# ------------------------------------------------------------
#  STATE MACHINE
# ------------------------------------------------------------
func _update_state(f: FishData, delta: float) -> void:
	f.state_timer -= delta
	if f.state_timer > 0.0:
		return

	match f.state:
		FishData.State.DART:
			f.state = FishData.State.CRUISE
			f.state_timer = _rng.randf_range(cruise_duration.x, cruise_duration.y)
		FishData.State.IDLE:
			f.state = FishData.State.CRUISE
			f.state_timer = _rng.randf_range(cruise_duration.x, cruise_duration.y)
		_:
			var roll := _rng.randf()
			if roll < dart_chance:
				f.state = FishData.State.DART
				f.state_timer = _rng.randf_range(dart_duration.x, dart_duration.y)
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
#  STEERING
# ------------------------------------------------------------
func _compute_steering(f: FishData) -> Vector3:
	var steer := Vector3.ZERO

	# Whisker-Wandvermeidung ZUERST (setzt f.near_wall). Gilt auch im IDLE,
	# damit ein Fisch, der an eine Wand gerät, trotzdem wegdriftet.
	var wall_avoid := _whisker_avoidance(f)

	# Im IDLE steht der Fisch: KEIN Wander, Boids oder Home-Pull. Nur
	# Wandvermeidung wirkt noch. So kommt er wirklich zum Stehen.
	if f.state == FishData.State.IDLE:
		return wall_avoid

	var sep := Vector3.ZERO
	var ali := Vector3.ZERO
	var coh := Vector3.ZERO
	var ali_count := 0
	var coh_count := 0

	for other in _fish:
		if other == f:
			continue
		var to := other.position - f.position
		to.y = 0.0
		var d := to.length()
		if d <= 0.0001 or d > neighbor_radius:
			continue

		if d < separation_dist:
			sep -= to / d

		# Nur Fische DESSELBEN Schwarms (gleiches Home) richten sich aneinander aus.
		if f.schooling and other.schooling and other.home.is_equal_approx(f.home):
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

	# Wander / Dart (wall_avoid wurde oben bereits berechnet).
	if f.state == FishData.State.DART:
		# Bei naher Wand den Dart-Impuls stark dämpfen, sonst rast der Fisch
		# voll in die Wand. Die Wandvermeidung übernimmt dann.
		var dart_scale := 0.2 if f.near_wall else 1.5
		steer += f.dart_dir * (steer_force * dart_scale)
	else:
		var wander_ang := _rng.randf_range(-0.5, 0.5)
		var wander := f.heading.rotated(Vector3.UP, wander_ang)
		steer += wander * wander_weight

	# Home-Pull (weich, nur ab home_soft_edge * radius).
	steer += _home_steer(f)

	steer += wall_avoid

	return steer


func _home_steer(f: FishData) -> Vector3:
	var to_home := f.home - f.position
	to_home.y = 0.0
	var d := to_home.length()
	var soft := f.home_radius * home_soft_edge
	if d <= soft:
		return Vector3.ZERO  # innerhalb: völlig frei
	# außerhalb der weichen Grenze: linear stärker werdender Zug
	var over := (d - soft) / maxf(f.home_radius - soft, 0.001)
	return to_home.normalized() * (home_weight * clampf(over, 0.0, 1.5))


# ------------------------------------------------------------
#  WHISKER (Stufe 1)
# ------------------------------------------------------------
func _whisker_avoidance(f: FishData) -> Vector3:
	if _space == null:
		return f.last_avoid

	# Cast-Strategie:
	#  - Fische NAH an einer Wand (near_wall) oder im DART casten JEDEN Frame,
	#    damit sie nicht anstoßen.
	#  - Frei schwimmende Fische casten nur gestaffelt (Performance).
	#  - Zwischen Casts wird der letzte Avoid-Vektor gehalten, statt auf 0 zu
	#    springen — so vergisst der Fisch die Wand nicht zwischen den Frames.
	var do_cast := f.near_wall \
		or f.state == FishData.State.DART \
		or (_frame_counter + f.ray_offset) % whisker_interval == 0
	if not do_cast:
		return f.last_avoid

	var dir := f.heading
	if dir.length_squared() < 0.0001:
		return f.last_avoid
	dir = dir.normalized()

	var ang := deg_to_rad(whisker_angle_deg)
	var dirs := [dir, dir.rotated(Vector3.UP, ang), dir.rotated(Vector3.UP, -ang)]

	var avoid := Vector3.ZERO
	var closest := 1.0  # 1.0 = nichts in Reichweite, 0.0 = direkt an Wand
	for d in dirs:
		_ray_query.from = f.position
		_ray_query.to = f.position + d * whisker_length
		var hit := _space.intersect_ray(_ray_query)
		if hit:
			var n: Vector3 = hit.normal
			n.y = 0.0
			var dist: float = f.position.distance_to(hit.position)
			var norm_dist := clampf(dist / whisker_length, 0.0, 1.0)
			closest = minf(closest, norm_dist)
			# Nähe quadratisch gewichtet -> nah an Wand DOMINANT.
			var strength := 1.0 - norm_dist
			strength = strength * strength
			if n.length_squared() > 0.0001:
				avoid += n.normalized() * strength

	# near_wall-Flag für nächsten Frame: castet dann jeden Frame.
	f.near_wall = closest < 0.6

	if avoid != Vector3.ZERO:
		# NICHT normalisieren — die Nähe-Stärke soll erhalten bleiben.
		f.last_avoid = avoid * avoid_weight
	else:
		f.last_avoid = Vector3.ZERO
	return f.last_avoid


# ------------------------------------------------------------
#  INTEGRATION
# ------------------------------------------------------------
func _integrate(f: FishData, steer: Vector3, delta: float) -> void:
	steer.y = 0.0
	if steer.length() > steer_force:
		steer = steer.normalized() * steer_force

	var target_speed := _target_speed(f)
	var desired := f.velocity + steer * delta
	var cur_speed := desired.length()
	if cur_speed > 0.0001:
		# Im IDLE (target 0) deutlich härter bremsen, damit der Fisch sichtbar
		# anhält statt langsam weiterzukriechen.
		var damp := velocity_damping
		if f.state == FishData.State.IDLE:
			damp = velocity_damping * 3.0
		var new_speed := lerpf(cur_speed, target_speed,
			clampf(damp * delta, 0.0, 1.0))
		desired = desired.normalized() * new_speed
	desired.y = 0.0

	f.velocity = desired
	f.position += f.velocity * delta

	if f.velocity.length_squared() > 0.0001:
		f.heading = f.heading.lerp(f.velocity.normalized(),
			clampf(8.0 * delta, 0.0, 1.0)).normalized()


# ------------------------------------------------------------
#  BOBBING (feste Höhe = Marker-Y)
# ------------------------------------------------------------
func _apply_bob(f: FishData, delta: float) -> void:
	f.bob_phase += bob_speed * delta
	f.position.y = f.home.y + sin(f.bob_phase) * bob_amplitude


# ------------------------------------------------------------
#  HARTE KOLLISION (Stufe 2)
# ------------------------------------------------------------
func _resolve_wall_collision(f: FishData) -> void:
	if _space == null:
		return
	var vel_xz := Vector3(f.velocity.x, 0.0, f.velocity.z)
	if vel_xz.length_squared() < 0.0001:
		return

	var step := vel_xz.length() * get_physics_process_delta_time()
	var look := maxf(step + 0.15, 0.2)
	_ray_query.from = f.position
	_ray_query.to = f.position + vel_xz.normalized() * look
	var hit := _space.intersect_ray(_ray_query)
	if hit:
		var n: Vector3 = hit.normal
		n.y = 0.0
		if n.length_squared() > 0.0001:
			n = n.normalized()
		else:
			n = -vel_xz.normalized()
		f.position = hit.position + n * 0.1
		f.position.y = f.home.y
		var v := Vector3(f.velocity.x, 0.0, f.velocity.z)
		f.velocity = v.bounce(n) * 0.5
		if f.velocity.length_squared() > 0.0001:
			f.heading = f.velocity.normalized()
		else:
			f.heading = n


# ------------------------------------------------------------
#  SPRITE
# ------------------------------------------------------------
func _write_sprite(f: FishData, delta: float) -> void:
	if not is_instance_valid(f.sprite):
		return
	f.sprite.global_position = f.position

	if absf(f.heading.x) > 0.05:
		f.sprite.flip_h = f.heading.x < 0.0

	var fps := anim_fps_cruise
	match f.state:
		FishData.State.DART:
			fps = anim_fps_dart
		FishData.State.IDLE:
			fps = anim_fps_idle
	f.anim_time += delta * fps
	var n := swim_frames.size()
	if n > 0:
		var idx := int(f.anim_time) % n
		f.sprite.frame = swim_frames[idx]


func _exit_tree() -> void:
	_clear_fish()

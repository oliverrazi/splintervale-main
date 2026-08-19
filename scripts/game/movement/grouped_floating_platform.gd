class_name GroupedFloatingPlatform
extends AnimatableBody3D
## Einzelne Plattform, die ihren Fluss aus einem FloatingPlatformGroup-Vorfahren bezieht.
## Fluss läuft entlang Z (spawn_z -> despawn_z). X und Y bleiben wie im Editor platziert;
## auf Y kommen nur Dip (Ab-/Auftauchen) und Bob/Schaukeln additiv dazu.
## Loop: DRIFT -> DIVE (am Despawn) -> RETURN (verdeckt zurück) -> SURFACE (am Spawn) -> DRIFT.

enum State { DRIFT, DIVE, RETURN, SURFACE }

var _group: FloatingPlatformGroup = null

var _spawn_z: float = 0.0
var _flow_sign: float = 1.0       # +1: Fluss in +Z, -1: Fluss in -Z.
var _route_length: float = 0.0

var _authored_x: float = 0.0      # Bleibt konstant (seitlicher Versatz aus dem Editor).
var _authored_y: float = 0.0      # Ruhehöhe aus dem Editor (Dip/Bob kommen additiv drauf).

var _state: int = State.DRIFT
var _distance: float = 0.0        # 0 = Spawn, _route_length = Despawn.
var _vert: float = 0.0
var _dive_t: float = 0.0
var _return_t: float = 0.0
var _surface_t: float = 0.0

var _phase: float = 0.0
var _prev_z: float = 0.0
var _drift_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	_group = _find_group()
	if _group == null:
		push_error("GroupedFloatingPlatform: kein FloatingPlatformGroup-Vorfahre gefunden.")
		set_physics_process(false)
		return
	if not _group.has_valid_markers():
		push_error("GroupedFloatingPlatform: Gruppe hat keine gültigen spawn/despawn-Marker.")
		set_physics_process(false)
		return

	# Carry läuft manuell über get_drift_velocity() -> sync_to_physics MUSS aus sein.
	sync_to_physics = false

	_spawn_z = _group.get_spawn_z()
	var route_vec: float = _group.get_despawn_z() - _spawn_z
	_route_length = absf(route_vec)
	if _route_length < 0.001:
		push_error("GroupedFloatingPlatform: spawn_z und despawn_z liegen aufeinander.")
		set_physics_process(false)
		return
	_flow_sign = signf(route_vec)

	# Editor-Position festhalten: X/Y bleiben, Z bestimmt die Staffelung.
	_authored_x = global_position.x
	_authored_y = global_position.y

	var raw: float = (global_position.z - _spawn_z) * _flow_sign
	_distance = fposmod(raw, _route_length)

	_state = State.DRIFT
	_vert = 0.0

	if _group.randomize_phase:
		_phase = randf() * TAU

	_prev_z = _flow_z()
	_apply_transform()


func _physics_process(delta: float) -> void:
	var drift_speed: float = _group.drift_speed
	var dip_depth: float = _group.dip_depth

	match _state:
		State.DRIFT:
			_distance += drift_speed * delta
			if _distance >= _route_length:
				_distance = _route_length
				_state = State.DIVE
				_dive_t = 0.0
			_vert = 0.0

		State.DIVE:
			_dive_t += delta
			var dt: float = _group.dive_time
			var df := 1.0 if dt <= 0.0 else clampf(_dive_t / dt, 0.0, 1.0)
			_vert = -dip_depth * _smooth(df)
			if df >= 1.0:
				_state = State.RETURN
				_return_t = 0.0
				_vert = -dip_depth

		State.RETURN:
			_return_t += delta
			var rt: float = _group.return_time
			var rf := 1.0 if rt <= 0.0 else clampf(_return_t / rt, 0.0, 1.0)
			_distance = lerpf(_route_length, 0.0, _smooth(rf))
			_vert = -dip_depth
			if rf >= 1.0:
				_distance = 0.0
				_state = State.SURFACE
				_surface_t = 0.0

		State.SURFACE:
			_surface_t += delta
			var st: float = _group.surface_time
			var sf := 1.0 if st <= 0.0 else clampf(_surface_t / st, 0.0, 1.0)
			_vert = -dip_depth * (1.0 - _smooth(sf))
			if sf >= 1.0:
				_vert = 0.0
				_state = State.DRIFT

	_apply_transform()

	# Carry nur während sichtbarer Drift, sonst reißt die schnelle RETURN-Fahrt den Player mit.
	var now_z := _flow_z()
	if _state == State.DRIFT:
		_drift_velocity = Vector3(0.0, 0.0, (now_z - _prev_z) / delta)
	else:
		_drift_velocity = Vector3.ZERO
	_prev_z = now_z


func get_drift_velocity() -> Vector3:
	return _drift_velocity


func _flow_z() -> float:
	return _spawn_z + _flow_sign * _distance


func _apply_transform() -> void:
	var dip_depth: float = _group.dip_depth

	var pos := Vector3(_authored_x, _authored_y + _vert, _flow_z())

	# "surfaced": 1 an der Oberfläche, 0 voll abgetaucht. Schaukeln fadet mit dem Abtauchen aus.
	var surfaced := 1.0
	if dip_depth > 0.0:
		surfaced = clampf(1.0 + _vert / dip_depth, 0.0, 1.0)

	var t := Time.get_ticks_msec() / 1000.0 + _phase

	# Zwei überlagerte Wellen pro Achse (nicht-ganzzahliges Frequenzverhältnis, eigene Phase)
	# -> organische, praktisch nie exakt wiederholte Bewegung statt Metronom.
	var bf: float = _group.bob_frequency
	var bob := (
		sin(t * TAU * bf) * 0.7
		+ sin(t * TAU * bf * 1.73 + 1.3) * 0.3
	) * _group.bob_amplitude
	pos.y += bob * surfaced

	var rfreq: float = _group.roll_frequency
	var roll := deg_to_rad(_group.roll_amplitude_deg) * (
		sin(t * TAU * rfreq + 0.6) * 0.7
		+ sin(t * TAU * rfreq * 1.91 + 2.1) * 0.3
	) * surfaced

	var pfreq: float = _group.pitch_frequency
	var pitch := deg_to_rad(_group.pitch_amplitude_deg) * (
		sin(t * TAU * pfreq + 1.7) * 0.7
		+ sin(t * TAU * pfreq * 1.61 + 0.4) * 0.3
	) * surfaced

	var basis := Basis.from_euler(Vector3(pitch, 0.0, roll))
	global_transform = Transform3D(basis, pos)


func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _find_group() -> FloatingPlatformGroup:
	var n := get_parent()
	while n != null:
		if n is FloatingPlatformGroup:
			return n
		n = n.get_parent()
	return null

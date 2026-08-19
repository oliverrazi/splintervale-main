class_name FloatingPlatform
extends AnimatableBody3D
## Schwimmende Plattform mit Loop:
## DRIFT (Spawn -> Despawn, sichtbar) -> DIVE (am Despawn abtauchen)
## -> RETURN (verdeckt schnell zurück zum Spawn) -> SURFACE (am Spawn auftauchen) -> DRIFT ...

## Startpunkt des Flusses – hier taucht die Plattform wieder auf (externer Marker).
@export var spawn_point: Node3D
## Endpunkt des Flusses – hier taucht die Plattform ab und loopt zurück (externer Marker).
@export var despawn_point: Node3D
## Drift-Geschwindigkeit entlang der Strecke in m/s (sichtbare Fahrt).
@export var drift_speed: float = 0.8

@export_group("Loop-Timing")
## Wie tief (Welt-Y) die Plattform beim Loop abtaucht, bis der Player sie nicht mehr sieht.
@export var dip_depth: float = 3.0
## Dauer des Abtauchens am Despawn (Sekunden).
@export var dive_time: float = 0.6
## Dauer der verdeckten Rückfahrt Despawn -> Spawn. Klein = "schießt schnell zurück".
@export var return_time: float = 0.5
## Dauer des Auftauchens am Spawn (Sekunden).
@export var surface_time: float = 0.6

@export_group("Schaukeln")
@export var bob_amplitude: float = 0.06
@export var bob_frequency: float = 0.6
@export var roll_amplitude_deg: float = 2.5
@export var roll_frequency: float = 0.45
@export var pitch_amplitude_deg: float = 1.5
@export var pitch_frequency: float = 0.37
@export var randomize_phase: bool = true


enum State { DRIFT, DIVE, RETURN, SURFACE }

var _spawn: Vector3
var _route_dir: Vector3
var _route_length: float

var _state: int = State.DRIFT
var _distance: float = 0.0        # 0 = Spawn, _route_length = Despawn.
var _vert: float = 0.0            # Aktueller vertikaler Offset (<= 0, Welt-Y).
var _dive_t: float = 0.0
var _return_t: float = 0.0
var _surface_t: float = 0.0

var _phase: float = 0.0
var _prev_h: Vector3 = Vector3.ZERO
var _drift_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	if spawn_point == null or despawn_point == null:
		push_error("FloatingPlatform: spawn_point/despawn_point nicht gesetzt.")
		set_physics_process(false)
		return

	# Carry läuft manuell über get_drift_velocity() im Player-Script.
	# sync_to_physics MUSS aus sein, sonst schleudert die schnelle RETURN-Fahrt
	# alles weg, was auf der Plattform steht.
	sync_to_physics = false

	_spawn = spawn_point.global_position
	var route_vec := despawn_point.global_position - _spawn
	_route_length = route_vec.length()
	if _route_length < 0.001:
		push_error("FloatingPlatform: spawn und despawn liegen aufeinander.")
		set_physics_process(false)
		return
	_route_dir = route_vec / _route_length

	# Editor-Position auf die Strecke projizieren (Plattform liegt laut Aufbau auf der Linie).
	_distance = clampf((global_position - _spawn).dot(_route_dir), 0.0, _route_length)
	_state = State.DRIFT
	_vert = 0.0

	if randomize_phase:
		_phase = randf() * TAU

	_prev_h = _base_position()
	_apply_transform()


func _physics_process(delta: float) -> void:
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
			var df := 1.0 if dive_time <= 0.0 else clampf(_dive_t / dive_time, 0.0, 1.0)
			_vert = -dip_depth * _smooth(df)
			if df >= 1.0:
				_state = State.RETURN
				_return_t = 0.0
				_vert = -dip_depth

		State.RETURN:
			_return_t += delta
			var rf := 1.0 if return_time <= 0.0 else clampf(_return_t / return_time, 0.0, 1.0)
			# Verdeckt von Despawn (_route_length) zurück zu Spawn (0).
			_distance = lerpf(_route_length, 0.0, _smooth(rf))
			_vert = -dip_depth
			if rf >= 1.0:
				_distance = 0.0
				_state = State.SURFACE
				_surface_t = 0.0

		State.SURFACE:
			_surface_t += delta
			var sf := 1.0 if surface_time <= 0.0 else clampf(_surface_t / surface_time, 0.0, 1.0)
			_vert = -dip_depth * (1.0 - _smooth(sf))
			if sf >= 1.0:
				_vert = 0.0
				_state = State.DRIFT

	_apply_transform()

	# Horizontale Carry-Velocity nur während der sichtbaren Drift-Fahrt.
	# Sonst würde die schnelle RETURN-Bewegung den Player mitreißen.
	var now := _base_position()
	if _state == State.DRIFT:
		var moved := now - _prev_h
		_drift_velocity = Vector3(moved.x, 0.0, moved.z) / delta
	else:
		_drift_velocity = Vector3.ZERO
	_prev_h = now


func get_drift_velocity() -> Vector3:
	return _drift_velocity


# Reine Strecken-Position (ohne Schaukeln/Dip).
func _base_position() -> Vector3:
	return _spawn + _route_dir * _distance


func _apply_transform() -> void:
	var pos := _base_position()
	pos.y += _vert

	# "surfaced": 1 an der Oberfläche, 0 voll abgetaucht. Schaukeln fadet mit dem Abtauchen aus.
	var surfaced := 1.0
	if dip_depth > 0.0:
		surfaced = clampf(1.0 + _vert / dip_depth, 0.0, 1.0)

	var t := Time.get_ticks_msec() / 1000.0 + _phase
	pos.y += sin(t * TAU * bob_frequency) * bob_amplitude * surfaced

	var roll := deg_to_rad(roll_amplitude_deg) * sin(t * TAU * roll_frequency) * surfaced
	var pitch := deg_to_rad(pitch_amplitude_deg) * sin(t * TAU * pitch_frequency) * surfaced
	var basis := Basis.from_euler(Vector3(pitch, 0.0, roll))

	global_transform = Transform3D(basis, pos)


func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

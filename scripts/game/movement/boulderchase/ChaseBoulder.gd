extends Area3D
class_name ChaseBoulder

## Rollende Felskugel für die Boulder-Chase-Sequenz.
##
## Bewegt wird sie NICHT selbst — der BoulderChaseDirector schiebt den
## übergeordneten PathFollow3D entlang der Path3D. Diese Node rollt lediglich
## automatisch anhand ihrer eigenen horizontalen Weltbewegung und moduliert
## darüber auch ihren Roll-Sound (schwillt an, je schneller sie wird).
##
## Trefferabfrage über Area3D.body_entered — RigidBody-contact_monitor erkennt
## CharacterBody3D unzuverlässig (Learning aus dem Projekt).
##
## Erwartete Struktur:
##   PathFollow3D  (loop = false, rotation_mode = ROTATION_NONE)
##     ChaseBoulder (diese Node, lokal auf Ruheposition = i.d.R. 0,0,0)
##       MeshInstance3D
##       CollisionShape3D (SphereShape3D)

@export var roll_radius: float = 0.25    ## Sichtbarer Kugelradius (miniature scale!) — steuert Drehtempo
@export var roll_direction: float = 1.0  ## Vorzeichen der Rolldrehung; -1.0 falls sie "rückwärts" rollt
@export var roll_enabled: bool = true

@export_group("Natural Roll")
@export var wobble_strength: float = 0.15    ## 0 = perfekt gerade, höher = mehr Torkeln
@export var wobble_freq_a: float = 1.0       ## Frequenz der Seitwärts-Neigung (pro Umdrehung)
@export var wobble_freq_b: float = 0.6       ## Frequenz des Gier-Versatzes
@export var bump_strength: float = 0.12      ## Stärke gelegentlicher Stolperer
@export var bump_interval_min: float = 0.35
@export var bump_interval_max: float = 1.1

@export_group("Roll Sound")
@export var roll_sound: AudioStream          ## loopend (Loop im Import-Dock setzen)
@export var roll_bus: String = "SFX"
@export var roll_volume_db: float = -6.0
@export var roll_volume_range: float = 8.0   ## um so viel leiser bei Minimal-Speed (statt komplett still)
@export var roll_min_speed: float = 1.0      ## darunter stumm
@export var roll_max_speed: float = 45.0     ## dort volle Lautstärke (an boulder_speed koppeln)
@export var roll_pitch_min: float = 0.85
@export var roll_pitch_max: float = 1.15

const _SILENCE_DB := -80.0

var _rest_position: Vector3
var _last_roll_pos: Vector3
var _has_last_pos: bool = false
var _roll_phase: float = 0.0
var _wobble_seed: float = 0.0
var _bump_timer: float = 0.0
var _roll_audio: AudioStreamPlayer3D = null


func _ready() -> void:
	_rest_position = position
	monitoring = false                   # Trefferabfrage erst im CHASE scharf
	_last_roll_pos = global_position
	_has_last_pos = true
	_wobble_seed = randf() * 100.0
	_bump_timer = randf_range(bump_interval_min, bump_interval_max)

	if roll_sound != null:
		_roll_audio = AudioStreamPlayer3D.new()
		var s := roll_sound.duplicate() as AudioStream   # Kopie, damit wir Loop setzen dürfen
		_force_loop(s)
		_roll_audio.stream = s
		_roll_audio.bus = roll_bus
		_roll_audio.volume_db = _SILENCE_DB
		_roll_audio.process_mode = Node.PROCESS_MODE_ALWAYS   # kein Stottern bei Hitstop
		add_child(_roll_audio)


func _physics_process(delta: float) -> void:
	if not _has_last_pos:
		_last_roll_pos = global_position
		_has_last_pos = true
		return

	# Nur horizontale Bewegung erzeugt Rollen — der Intro-Fall (vertikal) tut es nicht.
	var move: Vector3 = global_position - _last_roll_pos
	move.y = 0.0
	var dist: float = move.length()

	if roll_enabled and dist > 0.00001 and roll_radius > 0.0001:
		var dir: Vector3 = move / dist
		var roll_amt: float = dist / roll_radius
		_roll_phase += roll_amt

		# Hauptrotation — ohne die sähe es aus wie Rutschen.
		var main_axis: Vector3 = Vector3.UP.cross(dir)
		if main_axis.length_squared() > 0.000001:
			global_rotate(main_axis.normalized(), roll_amt * roll_direction)

		# Wobble: Neigung um die Fahrtrichtung + Gier um die Hochachse.
		# An die gerollte Strecke gekoppelt → torkelt natürlich, statt stur geradeaus.
		if wobble_strength > 0.0:
			var lean: float = sin(_roll_phase * wobble_freq_a + _wobble_seed) * wobble_strength * roll_amt
			var veer: float = sin(_roll_phase * wobble_freq_b + _wobble_seed * 1.7) * wobble_strength * roll_amt
			global_rotate(dir, lean)
			global_rotate(Vector3.UP, veer)

		# Gelegentlicher Stolperer auf zufälliger Achse (über eine Unebenheit gerollt).
		_bump_timer -= delta
		if _bump_timer <= 0.0:
			_bump_timer = randf_range(bump_interval_min, bump_interval_max)
			var bump_axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
			if bump_axis.length_squared() > 0.0001:
				global_rotate(bump_axis.normalized(), randf_range(-1.0, 1.0) * bump_strength)

	# Roll-Sound an die Geschwindigkeit koppeln — aber ab dem ersten Rollen hörbar
	# (Lautstärke von einem Boden bis roll_volume_db, nicht von kompletter Stille).
	if _roll_audio != null and _roll_audio.playing and delta > 0.0:
		var speed: float = dist / delta
		var t: float = clampf((speed - roll_min_speed) / maxf(roll_max_speed - roll_min_speed, 0.001), 0.0, 1.0)
		_roll_audio.volume_db = lerpf(roll_volume_db - roll_volume_range, roll_volume_db, t)
		_roll_audio.pitch_scale = lerpf(roll_pitch_min, roll_pitch_max, t)

	_last_roll_pos = global_position


func start_roll_sound() -> void:
	if _roll_audio != null and not _roll_audio.playing:
		_roll_audio.play()   # Lautstärke setzt der Modulations-Block im nächsten Frame


func stop_roll_sound() -> void:
	if _roll_audio != null and _roll_audio.playing:
		_roll_audio.stop()


func _force_loop(s: AudioStream) -> void:
	# Loop erzwingen, egal wie der Stream importiert wurde.
	if s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif "loop" in s:
		s.set("loop", true)   # AudioStreamOggVorbis / AudioStreamMP3


func reset_roll() -> void:
	rotation = Vector3.ZERO
	_last_roll_pos = global_position
	_roll_phase = 0.0


func hide_boulder() -> void:
	visible = false
	monitoring = false


func set_hit_detection(active: bool) -> void:
	monitoring = active


## Kugel sichtbar über der Ruheposition platzieren (für den Intro-Fall).
func prepare_drop(drop_height: float) -> void:
	visible = true
	monitoring = false
	reset_roll()
	position = _rest_position + Vector3(0.0, drop_height, 0.0)


## Von der (angehobenen) Höhe auf die Ruheposition fallen lassen.
## Gibt das finished-Signal zurück, damit der Director auf die Landung warten kann.
func drop_to_rest(time: float) -> Signal:
	var t := create_tween()
	t.tween_property(self, "position", _rest_position, time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return t.finished

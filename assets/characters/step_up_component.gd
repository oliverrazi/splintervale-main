class_name StepUpComponent
extends Node

## Laesst einen CharacterBody3D kleine Aufwaertskanten automatisch
## uebersteigen (Kollisionsnaehte, ueberstehende Boxen, Bordsteine).
## Godot-Ersatz fuer den "Step Offset" von Unity/Unreal.
##
## Integration im Player, NACH move_and_slide(), mit der GEWOLLTEN
## Bewegungsrichtung (nicht der Velocity — die ist nach move_and_slide
## an der Wand bereits abprojiziert und taugt nicht als Richtung):
##
##   move_and_slide()
##   if step_up:
##       step_up.try_step_up(delta, world_dir)

@export var body: CharacterBody3D

## Maximale Kantenhoehe, die automatisch ueberstiegen wird (Meter).
## Bei 0.3m Spielerhoehe sind 0.05-0.08 sinnvoll.
@export var max_step_height: float = 0.06

## Wie weit vorwaerts in Step-Hoehe getestet/versetzt wird (Meter).
## Etwa halber Kapselradius ist ein guter Wert.
@export var step_forward_distance: float = 0.05

## Konsole-Ausgabe, welches Gate einen Step-Versuch abbricht.
@export var debug_logging: bool = false


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D
	assert(body != null, "StepUpComponent braucht einen CharacterBody3D")


func try_step_up(delta: float, move_dir: Vector3 = Vector3.ZERO) -> void:
	if not body.is_on_floor():
		_dbg("Abbruch: nicht am Boden")
		return
	if not body.is_on_wall():
		_dbg("Abbruch: kein Wandkontakt")
		return

	# Richtung: bevorzugt die uebergebene Bewegungsabsicht,
	# sonst gegen die Wandnormale.
	var dir := move_dir
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		var wn := body.get_wall_normal()
		wn.y = 0.0
		if wn.length_squared() < 0.0001:
			_dbg("Abbruch: keine brauchbare Richtung")
			return
		dir = -wn.normalized()
	else:
		dir = dir.normalized()

	# 1) Ist ueber uns Platz fuer den Step?
	var up := Vector3.UP * max_step_height
	if _motion_blocked(body.global_transform, up):
		_dbg("Abbruch: kein Platz nach oben")
		return

	# 2) Kommen wir in Step-Hoehe vorwaerts?
	var xform := body.global_transform.translated(up)
	var forward := dir * step_forward_distance
	if _motion_blocked(xform, forward):
		_dbg("Abbruch: in Step-Hoehe weiterhin blockiert (echte Wand)")
		return
	xform = xform.translated(forward)

	# 3) Von dort wieder auf den Boden setzen
	var down_params := PhysicsTestMotionParameters3D.new()
	down_params.from = xform
	down_params.motion = Vector3.DOWN * (max_step_height * 2.0)
	var down_result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), down_params, down_result):
		_dbg("Abbruch: kein Boden unter der Zielposition")
		return

	# Nur steppen, wenn die Landeflaeche begehbar ist
	var n := down_result.get_collision_normal()
	if n.angle_to(Vector3.UP) > body.floor_max_angle:
		_dbg("Abbruch: Landeflaeche zu steil")
		return

	body.global_position = xform.origin + down_result.get_travel()
	body.velocity.y = 0.0
	_dbg("Step ausgefuehrt")


func _motion_blocked(from: Transform3D, motion: Vector3) -> bool:
	var params := PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion
	return PhysicsServer3D.body_test_motion(body.get_rid(), params)


func _dbg(msg: String) -> void:
	if debug_logging:
		print("[StepUp] ", msg)

@tool
class_name Rockslide
extends Node3D
## Geröll auf einer Erhöhung, das bei Trigger den Hang hinunterrollt und
## dem Player Schaden zufügt (wie die einstürzende Wand).
##
## Aufbau im Editor:
##   - Dieses Script auf einen Node3D.
##   - Als Kinder ein paar RigidBody3D-Steine platzieren (mit MeshInstance3D
##     + runder CollisionShape3D, z.B. SphereShape3D). Auf der Erhöhung ablegen.
##   - Eine Area3D als Trigger (oder trigger_area zuweisen).
##   - roll_direction in die Hang-Abwärtsrichtung setzen.

signal triggered

@export var rockslide_id: StringName  ## GameManager-Persistenz

@export_group("Trigger")
## Area3D, die den Player erkennt. Leer → erstes Area3D-Kind wird genutzt.
@export var trigger_area: Area3D = null

@export_group("Roll Physics")
## Abrollrichtung in WELT-Koordinaten (z.B. (1,0,0) für Hang nach +X).
@export var roll_direction: Vector3 = Vector3(1, 0, 0)
@export var roll_impulse: float = 3.0
@export var roll_torque: float = 4.0          ## hohe Rotation → rollt statt rutscht
@export var impulse_randomness: float = 0.8
@export var stagger_delay: float = 0.08       ## Steine lösen leicht versetzt

@export_group("Damage")
@export var base_damage: int = 5
@export var hit_area_scale: float = 1.6
@export var reference_impact_speed: float = 6.0
@export var min_impact_speed: float = 1.0
@export var min_damage_mult: float = 0.6
@export var max_damage_mult: float = 2.5
@export var player_collision_mask: int = 1     ## Layer, auf dem der Player liegt

@export_group("Despawn")
@export var fade_in_duration: float = 0.3
@export var rock_lifetime: float = 5.0         ## ab Losrollen bis Fade-Start
@export var dissolve_duration: float = 1.2

var _rocks: Array[RigidBody3D] = []
var _hit_areas: Array[Area3D] = []
var _triggered: bool = false
var _initial_states: Array[Dictionary] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# Bereits ausgelöst? → Steine gleich entfernen (liegen unten / sind weg)
	if rockslide_id != &"" and GameManager.get_flag("rockslide_" + str(rockslide_id)):
		_remove_all_rocks()
		return

	_collect_rocks()
	print("Rockslide: %d Steine gefunden" % _rocks.size())
	_setup_trigger()
	_freeze_rocks()


func _collect_rocks() -> void:
	for child in get_children():
		if child is RigidBody3D:
			_rocks.append(child)
			# runde Treffer-Area an jeden Stein hängen
			_attach_hit_area(child)


func _attach_hit_area(rock: RigidBody3D) -> void:
	var hit_area := Area3D.new()
	hit_area.collision_layer = 0
	hit_area.collision_mask = player_collision_mask
	hit_area.monitoring = true

	var area_col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	# Radius aus der vorhandenen CollisionShape des Steins ableiten
	var r := _estimate_rock_radius(rock)
	sphere.radius = r * hit_area_scale
	area_col.shape = sphere
	hit_area.add_child(area_col)
	rock.add_child(hit_area)
	hit_area.body_entered.connect(_on_rock_hit.bind(rock))
	_hit_areas.append(hit_area)


func _estimate_rock_radius(rock: RigidBody3D) -> float:
	# Versuch: vorhandene CollisionShape auslesen
	for child in rock.get_children():
		if child is CollisionShape3D and child.shape:
			var s : Variant= child.shape
			if s is SphereShape3D:
				return s.radius
			elif s is BoxShape3D:
				return s.size.length() * 0.5
			elif s is CapsuleShape3D:
				return s.radius
	# Fallback: aus dem Mesh-AABB
	for child in rock.get_children():
		if child is MeshInstance3D and child.mesh:
			return child.mesh.get_aabb().size.length() * 0.5
	return 0.3  # Default für Miniatur-Welt


func _setup_trigger() -> void:
	if trigger_area == null:
		for child in get_children():
			if child is Area3D:
				trigger_area = child
				break
	if trigger_area == null:
		push_warning("Rockslide '%s': keine Trigger-Area gefunden" % rockslide_id)
		return
	trigger_area.body_entered.connect(_on_trigger_entered)


func _freeze_rocks() -> void:
	for rock in _rocks:
		rock.freeze = true
		rock.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		# unsichtbar bis zum Losrollen
		var mesh := _find_mesh(rock)
		if is_instance_valid(mesh):
			mesh.transparency = 1.0
			mesh.set_meta("base_scale", mesh.scale)
			mesh.scale = Vector3.ZERO

func _find_mesh(rock: Node) -> MeshInstance3D:
	for child in rock.get_children():
		if child is MeshInstance3D:
			return child
		# GLB kann Mesh tiefer verschachtelt haben → eine Ebene tiefer suchen
		for sub in child.get_children():
			if sub is MeshInstance3D:
				return sub
	return null

func _on_trigger_entered(body: Node) -> void:
	if _triggered:
		return
	if not body.is_in_group("player"):
		return
	_start_rockslide()


func _start_rockslide() -> void:
	if _triggered:
		return
	_triggered = true

	if rockslide_id != &"":
		GameManager.set_flag("rockslide_" + str(rockslide_id), true)

	triggered.emit()
	_release_rocks()


func _release_rocks() -> void:
	var roll_dir := roll_direction
	roll_dir.y = 0.0
	if roll_dir.length() < 0.001:
		roll_dir = Vector3(1, 0, 0)
	roll_dir = roll_dir.normalized()

	# Achse für das Rollen: senkrecht zur Rollrichtung (horizontal)
	var roll_axis := Vector3.UP.cross(roll_dir).normalized()

	for i in range(_rocks.size()):
		var rock := _rocks[i]
		_release_single_rock(rock, roll_dir, roll_axis, i)


func _release_single_rock(rock: RigidBody3D, roll_dir: Vector3, roll_axis: Vector3, index: int) -> void:
	# leicht versetzt lösen → kaskadierendes Geröll
	if stagger_delay > 0.0 and index > 0:
		await get_tree().create_timer(stagger_delay * index).timeout
	if not is_instance_valid(rock):
		return

	rock.freeze = false
	
	var mesh := _find_mesh(rock)
	if is_instance_valid(mesh):
		var target_scale: Vector3 = mesh.get_meta("base_scale", Vector3.ONE)
		var grow := create_tween()
		grow.set_parallel(true)
		grow.tween_property(mesh, "transparency", 0.0, fade_in_duration)
		grow.tween_property(mesh, "scale", target_scale, fade_in_duration*1.5)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var rand := Vector3(
		randf_range(-impulse_randomness, impulse_randomness),
		0.0,
		randf_range(-impulse_randomness, impulse_randomness)
	)
	var dir := (roll_dir + rand).normalized()
	rock.apply_central_impulse(dir * roll_impulse * rock.mass)

	# Drehung um die Roll-Achse → Stein rollt vorwärts
	rock.angular_velocity = roll_axis * roll_torque

	# Fade nach Lebenszeit
	_schedule_rock_fade(rock)


func _schedule_rock_fade(rock: RigidBody3D) -> void:
	await get_tree().create_timer(rock_lifetime).timeout
	if not is_instance_valid(rock):
		return
	rock.freeze = true

	var mesh := _find_mesh(rock)
	if is_instance_valid(mesh):
		var shrink := create_tween()
		shrink.set_parallel(true)
		shrink.tween_property(mesh, "transparency", 1.0, dissolve_duration)
		shrink.tween_property(mesh, "scale", Vector3.ZERO, dissolve_duration)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await shrink.finished

	if is_instance_valid(rock):
		rock.queue_free()


func _on_rock_hit(hit_body: Node, rock: RigidBody3D) -> void:
	if not _triggered:
		return
	if not is_instance_valid(hit_body) or not is_instance_valid(rock):
		return
	if not hit_body.is_in_group("player"):
		return
	if not hit_body.has_method("take_damage"):
		return

	var impact_speed: float = rock.linear_velocity.length()
	if impact_speed < min_impact_speed:
		return

	var mult: float = clampf(impact_speed / reference_impact_speed, min_damage_mult, max_damage_mult)
	var dmg: int = maxi(1, int(round(base_damage * mult)))
	hit_body.take_damage(dmg, rock.global_position)


func _remove_all_rocks() -> void:
	for child in get_children():
		if child is RigidBody3D:
			child.queue_free()

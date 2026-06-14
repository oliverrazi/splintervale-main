class_name CrumbleWall
extends Node3D

## Eine zerstörbare Wand mit pre-fractured Brocken aus Blender.
## Brocken verursachen beim Aufprall auf den Player Schaden (Impact-Speed × Masse).

signal crumbled

@export var wall_id: StringName
@export var intact_mesh: MeshInstance3D
@export var fragments_root: Node3D
@export var fragment_collision_layer: int = 1
@export var fragment_collision_mask: int = 1  ## muss Player-Layer (1) enthalten

@export_group("Crumble Physics")
@export var impulse_strength: float = 2.5
@export var impulse_randomness: float = 1.5
@export var torque_strength: float = 0.8
@export var explosion_origin_offset: Vector3 = Vector3.ZERO
## Gerichteter Schub in WELT-Koordinaten (z.B. (0,0,-1)). Unabhängig von Node-Rotation.
@export var directional_push: Vector3 = Vector3.ZERO
@export var directional_strength: float = 3.0
## Wenn true, wird directional_push als lokal zur Wand interpretiert.
@export var directional_push_local: bool = false

@export_group("Damage")
@export var base_damage: int = 4
@export var hit_area_scale: float = 2.0   ## Trefferzone vs. tatsächliche Brockengröße
@export var reference_impact_speed: float = 6.0
@export var min_impact_speed: float = 0.8  ## runter von 2.0 — Miniaturwelt-Geschwindigkeiten
@export var min_damage_mult: float = 0.6
@export var max_damage_mult: float = 2.5

@export_group("Dust")
@export var emit_dust: bool = true
@export var dust_duration: float = 2.4          ## Gesamtlebensdauer der Wolke
@export var dust_opacity: float = 0.9
@export var dust_billboard_count: int = 4       ## gekreuzte Flächen für Volumen
@export var dust_size_scale: float = 1.6        ## Wolkengröße relativ zur Wand-AABB
@export var dust_rise_height: float = 0.6  

const DUST_VOLUME_SHADER_PATH  := "res://scripts/shader/cave/resonance_dust_volume.gdshader"

@export_group("Despawn")
@export var fragment_lifetime: float = 6.0
@export var dissolve_duration: float = 1.5



var _fragments: Array[RigidBody3D] = []
var _crumbled: bool = false


func _ready() -> void:
	if wall_id != &"" and GameManager.get_flag("wall_crumbled_" + wall_id):
		_apply_persistent_crumbled_state()
		return
	_build_fragments()


func _build_fragments() -> void:
	if not is_instance_valid(fragments_root):
		push_error("CrumbleWall '%s': fragments_root nicht gesetzt" % wall_id)
		return

	# Kopie der Kinder, da wir während der Iteration queue_free aufrufen
	var meshes: Array[Node] = fragments_root.get_children()
	for mesh in meshes:
		if mesh is not MeshInstance3D:
			continue
		var body := _wrap_in_rigidbody(mesh)
		_fragments.append(body)

	fragments_root.visible = false
	for body in _fragments:
		body.freeze = true
		body.visible = false


func _wrap_in_rigidbody(mesh: MeshInstance3D) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = fragment_collision_layer
	body.collision_mask = fragment_collision_mask
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.continuous_cd = true

	fragments_root.add_child(body)
	body.global_transform = mesh.global_transform
	body.global_basis = body.global_basis.orthonormalized()

	var shape := mesh.mesh.create_convex_shape(true, true)

	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)

	# Separate Area3D für zuverlässige Player-Treffererkennung
	var hit_area := Area3D.new()
	hit_area.collision_layer = 0
	hit_area.collision_mask = 1
	hit_area.monitoring = true

	var area_col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	# Radius aus AABB des Brockens ableiten, dann großzügig aufblasen
	var aabb := mesh.mesh.get_aabb()
	sphere.radius = maxf(aabb.size.length() * 0.5, 0.05) * hit_area_scale
	area_col.shape = sphere
	hit_area.add_child(area_col)
	body.add_child(hit_area)
	hit_area.body_entered.connect(_on_fragment_hit.bind(body))

	var mesh_copy := mesh.duplicate() as MeshInstance3D
	mesh_copy.transform = Transform3D.IDENTITY
	body.add_child(mesh_copy)

	mesh.queue_free()
	return body


func _on_fragment_hit(hit_body: Node, fragment: RigidBody3D) -> void:
	if not _crumbled:
		return
	if not is_instance_valid(hit_body) or not is_instance_valid(fragment):
		return
	if not hit_body.is_in_group("player"):
		return
	if not hit_body.has_method("take_damage"):
		return

	var impact_speed: float = fragment.linear_velocity.length()
	if impact_speed < min_impact_speed:
		return

	var mult: float = clampf(impact_speed / reference_impact_speed, min_damage_mult, max_damage_mult)
	var dmg: int = maxi(1, int(round(base_damage * mult)))

	# from_position = Brockenposition → dein Knockback stößt korrekt vom Stein weg.
	# Mehrfachschaden im selben Moment wird durch deinen _invincibility_timer abgefangen.
	hit_body.take_damage(dmg, fragment.global_position)


func crumble() -> void:
	if _crumbled:
		return
	if not is_instance_valid(fragments_root):
		push_error("CrumbleWall '%s': crumble() ohne gültigen fragments_root" % wall_id)
		return
	_crumbled = true

	if is_instance_valid(intact_mesh):
		_emit_dust()  # Staub VOR dem Ausblenden, solange die AABB noch steht
		intact_mesh.visible = false
		_disable_static_collision(intact_mesh)

	fragments_root.visible = true
	var origin := global_position + explosion_origin_offset
	var push_world: Vector3
	if directional_push_local:
		push_world = global_transform.basis * directional_push
	else:
		push_world = directional_push  # direkt Welt-Koordinaten
	if push_world.length() > 0.001:
		push_world = push_world.normalized()
	else:
		push_world = Vector3.ZERO

	for body in _fragments:
		body.visible = true
		body.freeze = false

		var dir := (body.global_position - origin).normalized()
		if dir == Vector3.ZERO:
			dir = Vector3.UP
		var rand_dir := dir + Vector3(
			randf_range(-impulse_randomness, impulse_randomness),
			randf_range(0.0, impulse_randomness),
			randf_range(-impulse_randomness, impulse_randomness)
		)
		var impulse := rand_dir.normalized() * impulse_strength
		impulse += push_world * directional_strength
		body.apply_central_impulse(impulse * body.mass)

		body.apply_torque_impulse(Vector3(
			randf_range(-torque_strength, torque_strength),
			randf_range(-torque_strength, torque_strength),
			randf_range(-torque_strength, torque_strength)
		))

	GameEffects.shake(0.4, 0.3)

	if wall_id != &"":
		GameManager.set_flag("wall_crumbled_" + wall_id, true)

	crumbled.emit()
	_schedule_despawn()


func _emit_dust() -> void:
	if not emit_dust or not is_instance_valid(intact_mesh):
		return

	var aabb: AABB = intact_mesh.get_aabb()
	var center_local: Vector3 = aabb.position + aabb.size * 0.5
	var emit_xform: Transform3D = intact_mesh.global_transform
	var emit_origin: Vector3 = emit_xform * center_local

	# Wolkengröße an der größten horizontalen Ausdehnung der Wand orientieren
	var span: float = maxf(aabb.size.x, aabb.size.z) * dust_size_scale
	var height: float = aabb.size.y * dust_size_scale

	var root := Node3D.new()
	root.name = "DustCloud"
	add_child(root)
	root.global_position = emit_origin

	var shader := load(DUST_VOLUME_SHADER_PATH) as Shader
	var materials: Array[ShaderMaterial] = []

	# Mehrere gekreuzte Quads → Volumen aus allen Blickwinkeln
	for i in range(dust_billboard_count):
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(span, height)
		quad.mesh = mesh
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat := ShaderMaterial.new()
		if shader:
			mat.shader = shader
			mat.set_shader_parameter("opacity", dust_opacity)
			mat.set_shader_parameter("noise_offset",
				Vector2(randf() * 10.0, randf() * 10.0))
		else:
			push_warning("CrumbleWall: Dust-Volume-Shader fehlt unter %s" % DUST_VOLUME_SHADER_PATH)
		quad.material_override = mat
		materials.append(mat)

		# Minimaler Versatz in der Tiefe und seitlich → Dichte ohne Kreuzung
		var offset := Vector3(
			randf_range(-span, span) * 0.15,
			randf_range(-height, height) * 0.1,
			randf_range(-span, span) * 0.15
		)
		quad.position = offset
		root.add_child(quad)

	# progress 0→1 über die Lebenszeit tweenen (steuert Shader-Lifecycle)
	var tween := create_tween()
	tween.set_parallel(true)
	for mat in materials:
		tween.tween_method(
			func(v): mat.set_shader_parameter("progress", v),
			0.0, 1.0, dust_duration
		)
	# Wolke steigt leicht auf, während sie lebt
	tween.tween_property(root, "global_position",
		emit_origin + Vector3(0, dust_rise_height, 0), dust_duration)

	tween.chain().tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
	)


func _schedule_despawn() -> void:
	await get_tree().create_timer(fragment_lifetime).timeout
	_dissolve_and_free()


func _dissolve_and_free() -> void:
	for body in _fragments:
		if not is_instance_valid(body):
			continue
		body.freeze = true
		# erstes MeshInstance3D-Child finden
		var mesh: MeshInstance3D = null
		for child in body.get_children():
			if child is MeshInstance3D:
				mesh = child
				break
		if is_instance_valid(mesh):
			var tween := create_tween()
			# MeshInstance3D.transparency: 0 = sichtbar, 1 = unsichtbar
			tween.tween_property(mesh, "transparency", 1.0, dissolve_duration)

	await get_tree().create_timer(dissolve_duration + 0.1).timeout
	queue_free()


func _start_dissolve(mesh: MeshInstance3D) -> void:
	var mat := mesh.get_active_material(0)
	if mat is ShaderMaterial:
		var tween := create_tween()
		tween.tween_method(
			func(v): mat.set_shader_parameter("dissolve_amount", v),
			0.0, 1.0, dissolve_duration
		)


func _apply_persistent_crumbled_state() -> void:
	if is_instance_valid(intact_mesh):
		intact_mesh.queue_free()
	if is_instance_valid(fragments_root):
		fragments_root.queue_free()
	_crumbled = true


func _disable_static_collision(node: Node) -> void:
	var parent := node.get_parent()
	if parent is StaticBody3D:
		for child in parent.get_children():
			if child is CollisionShape3D:
				child.set_deferred("disabled", true)

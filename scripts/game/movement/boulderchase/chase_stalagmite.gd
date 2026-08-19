extends Node3D
class_name ChaseStalagmite

## Ein Stalagmit auf der Boulder-Route. Solides Hindernis für den Player,
## das der Boulder beim Durchrollen zerschlägt: ein paar Steinchen fliegen
## (per Default) nach links, dazu Sound + optional Fog. Wird beim Chase-Retry
## über reset() wieder aufgebaut.
##
## STRUKTUR-UNABHÄNGIG: Dieses Script an den ROOT deiner Stalagmiten-Szene
## hängen (beliebiger Node3D — auch direkt an ein MeshInstance3D). Beim
## Zerschlagen wird der ganze Teilbaum ausgeblendet (self.visible) und alle
## CollisionShapes darunter werden rekursiv deaktiviert. Die Steinchen und der
## Fog hängen bewusst am Parent, damit sie sichtbar bleiben.
##
## Erkennung läuft layer-unabhängig über den BoulderChaseDirector
## (Abstands-Check gegen Gruppe "chase_stalagmite") — der Stalagmit selbst
## muss also kein PhysicsBody sein.

@export var debug: bool = false                ## Konsolen-Ausgabe beim Zerschlagen (Diagnose)

@export_group("Debris")
@export var pebble_scene: PackedScene = preload("res://assets/base_tiles/cave_texture/cave-stone1.tscn")         
@export var pebble_count: int = 6
@export var pebble_size_min: float = 0.05
@export var pebble_size_max: float = 0.12
@export var pebble_lifetime: float = 4.0
@export var pebble_collision_mask: int = 1     ## Boden-Layer
@export var burst_direction: Vector3 = Vector3.LEFT   ## WELT-Richtung des Auswurfs ("nach links")
@export var burst_impulse: float = 5.0         ## ~Auswurf-Geschwindigkeit (Welt-Einh./s) — höher = spektakulärer
@export var burst_up_kick: float = 3.0
@export var burst_spread: float = 0.5
@export var spawn_offset: Vector3 = Vector3(0.0, 0.4, 0.0)   ## Ausbruchspunkt relativ zur Node-Position

@export_group("Sound")
@export var shatter_sound: AudioStream = preload("res://assets/audio/sfx/cave/rock-break.wav")
@export var shatter_volume_db: float = -2.0
@export var shatter_pitch_semitones: float = 3.0   ## zufällige Transpose ± Halbtöne, damit nicht alle gleich klingen

@export_group("Dust")
@export var dust_shader: Shader = preload("res://scripts/shader/cave/resonance_dust_volume.gdshader")
@export var dust_size: float = 0.9
@export var dust_duration: float = 1.2
@export var dust_opacity: float = 0.85
@export var dust_billboard_count: int = 3
@export var dust_rise_height: float = 0.4

var _shattered: bool = false
var _pebbles: Array[Node] = []
var _convex_cache: Dictionary = {}

# Eigene CollisionShapes (beim _ready eingesammelt — Debris-Steinchen sind nie dabei,
# die entstehen erst später und hängen am Parent).
var _own_collision: Array[CollisionShape3D] = []


func _ready() -> void:
	add_to_group("chase_stalagmite")
	_collect_own_nodes()
	_prewarm_debris()


func _collect_own_nodes() -> void:
	_own_collision.clear()
	# Root kann selbst eine CollisionShape sein — über Node-Referenz prüfen
	# (Compiler typisiert self sonst als ChaseStalagmite und lehnt den is-Check ab).
	var me: Node = self
	if me is CollisionShape3D:
		_own_collision.append(me as CollisionShape3D)
	_collect_recursive(self)


func _collect_recursive(node: Node) -> void:
	for c in node.get_children():
		if c is CollisionShape3D:
			_own_collision.append(c)
		_collect_recursive(c)


func is_shattered() -> bool:
	return _shattered


func shatter() -> void:
	if _shattered:
		return
	_shattered = true

	# Optik + Kollision aus → Player und Boulder kommen durch.
	_hide_intact()
	_set_collision(false)

	if debug:
		print("[ChaseStalagmite] '%s' class=%s → visible=%s  visible_in_tree=%s" \
			% [name, get_class(), visible, is_visible_in_tree()])

	var origin: Vector3 = global_position + spawn_offset
	var base_dir: Vector3 = burst_direction
	if base_dir.length_squared() < 0.0001:
		base_dir = Vector3.LEFT
	base_dir = base_dir.normalized()

	for i in range(pebble_count):
		var pebble := _make_pebble()
		# WICHTIG: an den Parent, NICHT unter self — sonst werden die Steinchen
		# mit unsichtbar, sobald wir das Stalagmit-Mesh (self) ausblenden.
		_debris_parent().add_child(pebble)
		_pebbles.append(pebble)

		if pebble is Node3D:
			(pebble as Node3D).global_position = origin + Vector3(
				randf_range(-0.15, 0.15), randf_range(-0.1, 0.1), randf_range(-0.15, 0.15)
			)
		if pebble is RigidBody3D:
			var rb := pebble as RigidBody3D
			rb.freeze = false
			rb.sleeping = false
			var dir := base_dir + Vector3(
				randf_range(-burst_spread, burst_spread),
				randf_range(0.0, burst_spread),
				randf_range(-burst_spread, burst_spread)
			)
			if dir.length_squared() < 0.0001:
				dir = base_dir
			var impulse := dir.normalized() * burst_impulse + Vector3.UP * burst_up_kick
			rb.apply_central_impulse(impulse * rb.mass)
			rb.apply_torque_impulse(Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1)))
		_free_after(pebble, pebble_lifetime)

	if shatter_sound != null:
		var semis: float = randf_range(-shatter_pitch_semitones, shatter_pitch_semitones)
		AudioPool.play_3d(shatter_sound, origin, shatter_volume_db, pow(2.0, semis / 12.0))

	_spawn_dust(origin)


func reset() -> void:
	# Alte Steinchen wegräumen und Stalagmit wieder aufbauen.
	for p in _pebbles:
		if is_instance_valid(p):
			p.queue_free()
	_pebbles.clear()

	_shattered = false
	_show_intact()
	_set_collision(true)


func _set_collision(on: bool) -> void:
	for c in _own_collision:
		if is_instance_valid(c):
			c.set_deferred("disabled", not on)


func _hide_intact() -> void:
	# Ganzen Stalagmit-Teilbaum ausblenden. Debris hängt am Parent (nicht unter
	# self) und bleibt dadurch sichtbar.
	visible = false


func _show_intact() -> void:
	visible = true


# ─── Steinchen ─────────────────────────────────────────────────────

func _make_pebble() -> Node:
	if pebble_scene != null:
		var inst := pebble_scene.instantiate()
		if inst is RigidBody3D:
			var rb := inst as RigidBody3D
			rb.freeze = false
			rb.sleeping = false
			if rb.collision_mask == 0:
				rb.collision_mask = pebble_collision_mask
			return rb
		return _wrap_mesh(inst)
	return _make_procedural()


func _wrap_mesh(visual: Node) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = pebble_collision_mask
	body.continuous_cd = true
	body.add_child(visual)
	if visual is Node3D:
		(visual as Node3D).transform = Transform3D.IDENTITY

	var mesh_inst := visual as MeshInstance3D
	if mesh_inst == null:
		mesh_inst = _find_first_mesh(visual)

	var col := CollisionShape3D.new()
	if mesh_inst != null and mesh_inst.mesh != null:
		col.shape = _convex_for(mesh_inst.mesh)
	else:
		var s := SphereShape3D.new()
		s.radius = 0.08
		col.shape = s
	body.add_child(col)
	return body


func _convex_for(mesh: Mesh) -> Shape3D:
	if mesh == null:
		var s := SphereShape3D.new()
		s.radius = 0.08
		return s
	if _convex_cache.has(mesh):
		return _convex_cache[mesh]
	var shape: Shape3D = mesh.create_convex_shape()   # simplify=false → schnell, einmal gecacht
	_convex_cache[mesh] = shape
	return shape


func _prewarm_debris() -> void:
	if pebble_scene == null:
		return
	var inst := pebble_scene.instantiate()
	var mesh_inst := inst as MeshInstance3D
	if mesh_inst == null:
		mesh_inst = _find_first_mesh(inst)
	if mesh_inst != null and mesh_inst.mesh != null:
		_convex_for(mesh_inst.mesh)
	inst.free()


func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


func _make_procedural() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = pebble_collision_mask
	body.continuous_cd = true

	var size: float = randf_range(pebble_size_min, pebble_size_max)
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.49, 0.46)
	mat.roughness = 1.0
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3.ONE * size
	col.shape = box_shape
	body.add_child(col)

	body.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	return body


func _free_after(node: Node, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(node):
		node.queue_free()


## Elternknoten für Steinchen/Fog — bewusst NICHT self, damit sie sichtbar
## bleiben, wenn das Stalagmit-Mesh (self) beim Zerschlagen unsichtbar wird.
func _debris_parent() -> Node:
	var p := get_parent()
	if p != null:
		return p
	return get_tree().current_scene


# ─── Fog ───────────────────────────────────────────────────────────

func _spawn_dust(world_pos: Vector3) -> void:
	if dust_shader == null:
		return

	var root := Node3D.new()
	root.name = "StalagmiteDust"
	_debris_parent().add_child(root)   # nicht unter self (sonst mit ausgeblendet)
	root.global_position = world_pos

	var materials: Array[ShaderMaterial] = []
	for i in range(dust_billboard_count):
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(dust_size, dust_size)
		quad.mesh = mesh
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat := ShaderMaterial.new()
		mat.shader = dust_shader
		mat.set_shader_parameter("opacity", dust_opacity)
		mat.set_shader_parameter("noise_offset", Vector2(randf() * 10.0, randf() * 10.0))
		quad.material_override = mat
		materials.append(mat)

		quad.position = Vector3(
			randf_range(-dust_size, dust_size) * 0.15, 0.0,
			randf_range(-dust_size, dust_size) * 0.15
		)
		root.add_child(quad)

	var tween := create_tween()
	tween.set_parallel(true)
	for mat in materials:
		tween.tween_method(func(v: float): mat.set_shader_parameter("progress", v), 0.0, 1.0, dust_duration)
	tween.tween_property(root, "global_position", world_pos + Vector3(0.0, dust_rise_height, 0.0), dust_duration)
	tween.chain().tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
	)

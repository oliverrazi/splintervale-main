extends SpringArm3D

@export var smooth_speed: float = 5.0
var target_position: Vector3

# ---------------------------
# Occlusion (neu)
# ---------------------------
@export var occlusion_enabled := true
@export var occlusion_max_hits := 32
@export var occlusion_collision_mask := 2
## Puffer in Einheiten - Objekte müssen mindestens so weit VOR dem Spieler sein
@export var occlusion_distance_buffer := 0.5


# Optional: falls dein Camera3D-Node nicht direkt unter dem SpringArm liegt,
# kannst du hier einen NodePath setzen.
@export var camera_path: NodePath
var _camera: Camera3D

var _occluded: Dictionary = {} # collider -> true

func _ready():
	target_position = global_position

	if camera_path != NodePath():
		_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null:
		_camera = find_child("", true, false) as Camera3D
		if _camera == null:
			_camera = get_viewport().get_camera_3d()

func _process(delta: float) -> void:
	handle_camera()

	var parent_position = get_parent().global_position
	target_position = target_position.lerp(parent_position, smooth_speed * delta)
	global_position = target_position

func _physics_process(_delta: float) -> void:
	var space := get_world_3d().direct_space_state
	
	var ray := PhysicsRayQueryParameters3D.new()
	ray.from = _camera.global_position
	ray.to = Vector3(21.49667, 1.5, 28.22174)
	ray.collision_mask = 0xFFFFFFFF
	ray.collide_with_bodies = true
	
	if occlusion_enabled:
		_update_occlusion()
	
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		var collider = hit["collider"]

func _update_occlusion() -> void:
	if _camera == null:
		return

	var player := get_parent() as Node3D
	if player == null:
		return

	var from_pos: Vector3 = _camera.global_transform.origin
	var to_pos: Vector3 = player.global_transform.origin + Vector3(0, 1.0, 0)
	var direction: Vector3 = (to_pos - from_pos).normalized()
	var distance_to_player := from_pos.distance_to(to_pos)

	var space := get_world_3d().direct_space_state

	var excluded: Array[RID] = []
	if player is CollisionObject3D:
		excluded.append((player as CollisionObject3D).get_rid())

	var current: Dictionary = {}
	var current_from := from_pos

	for i in occlusion_max_hits:
		var ray_query := PhysicsRayQueryParameters3D.new()
		ray_query.from = current_from
		ray_query.to = to_pos
		ray_query.collision_mask = occlusion_collision_mask
		ray_query.collide_with_bodies = true
		ray_query.exclude = excluded

		var result := space.intersect_ray(ray_query)
		if result.is_empty():
			break

		var collider = result.get("collider")
		var hit_position: Vector3 = result["position"]
		var distance_to_hit := from_pos.distance_to(hit_position)

		if collider is CollisionObject3D:
			excluded.append((collider as CollisionObject3D).get_rid())

		if distance_to_hit < distance_to_player - occlusion_distance_buffer:
			var target := _find_occludable_target(collider)
			if target != null:
				current[target] = true
				if not _occluded.has(target):
					target.call("set_occluded", true, player.global_position)

		current_from = hit_position + direction * 0.1

	# HIER IST DIE ÄNDERUNG:
	# Zuerst alle NOCH okkludierten Objekte updaten
	for key in current.keys():
		if is_instance_valid(key):
			key.call("update_player_position", player.global_position)
	
	# Dann die NICHT MEHR okkludierten mit korrekter Position un-okkludieren
	for key in _occluded.keys():
		if not is_instance_valid(key):
			continue
		if not current.has(key):
			# WICHTIG: Player-Position mitgeben, nicht Vector3.ZERO!
			key.call("set_occluded", false, player.global_position)

	_occluded = current


func _find_occludable_target(obj: Object) -> Node:
	if obj is Node:
		var n: Node = obj as Node
		while n != null:
			if n.has_method("set_occluded"):
				return n
			n = n.get_parent()
	return null

func handle_camera():
	if Input.is_action_just_pressed("rotate_left"):
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "rotation:y", self.rotation.y + PI/2, 0.5)

	elif Input.is_action_just_pressed("rotate_right"):
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "rotation:y", self.rotation.y - PI/2, 0.5)

	elif Input.is_action_pressed("rotate_right") and Input.is_action_pressed("rotate_left"):
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "rotation:y", PI, 0.5)

func handle_zoom():
	if Input.is_action_just_pressed("zoom_in"):
		if int(spring_length) > 0:
			var tween = create_tween()
			tween.set_parallel(true)
			tween.set_trans(Tween.TRANS_SINE)
			tween.set_ease(Tween.EASE_OUT)
			var newlength = int(spring_length) - 1
			tween.tween_property(self, "spring_length", newlength, 0.5)
			if int(newlength) <= 0:
				tween.tween_property(self, "position", Vector3(0, 0.2, 0), 0.5)

	elif Input.is_action_just_pressed("zoom_out"):
		if int(spring_length) < 6:
			var tween = create_tween()
			tween.set_parallel(true)
			tween.set_trans(Tween.TRANS_SINE)
			tween.set_ease(Tween.EASE_OUT)
			var newlength = int(spring_length) + 1
			tween.tween_property(self, "spring_length", newlength, 0.5)
			if int(newlength) > 0:
				tween.tween_property(self, "position", Vector3(0, 0, 0), 0.5)

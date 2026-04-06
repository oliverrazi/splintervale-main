extends Node

var player_scene: PackedScene = preload("res://character_body_3d.tscn")
var player_instance: Node3D


func _ready() -> void:
	_create_player()
	await get_tree().process_frame
	_add_player_to_scene()
	get_tree().tree_changed.connect(_check_scene)


func _create_player() -> void:
	player_instance = player_scene.instantiate()
	player_instance.add_to_group("player")


func _check_scene() -> void:
	# Player wurde gefreed (z.B. durch Szenen-Laden)
	if not is_instance_valid(player_instance):
		_create_player()

	if not player_instance.is_inside_tree():
		call_deferred("_add_player_to_scene")


func _add_player_to_scene() -> void:
	if not get_tree() or not get_tree().current_scene:
		return

	# Prüfe ob die Szene schon einen Player hat (z.B. Overworld)
	var existing: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if existing:
		player_instance = existing
		_move_to_spawn_point()
		return

	# Kein Player in der Szene → wir fügen unseren ein (Caves etc.)
	if not is_instance_valid(player_instance):
		_create_player()
	if player_instance.get_parent():
		player_instance.get_parent().remove_child(player_instance)
	get_tree().current_scene.add_child(player_instance)
	_move_to_spawn_point()



func _move_to_spawn_point() -> void:
	# Suche SpawnPoints-Container in der aktuellen Szene
	var spawn_container: Node = get_tree().current_scene.find_child("SpawnPoints")
	if not spawn_container:
		return

	# Prüfe ob GlobalCaveData einen bestimmten Spawn vorgibt
	var cave_data: Node = get_node_or_null("/root/GlobalCaveData")
	var target_id: String = ""
	if cave_data:
		target_id = cave_data.pending_spawn_id

	var marker: Marker3D = null

	# Bestimmten Spawn suchen
	if not target_id.is_empty():
		marker = spawn_container.get_node_or_null(target_id) as Marker3D

	# Fallback: ersten Marker nehmen
	if not marker and spawn_container.get_child_count() > 0:
		marker = spawn_container.get_child(0) as Marker3D

	if marker:
		player_instance.global_position = marker.global_position
		player_instance.global_rotation.y = marker.global_rotation.y

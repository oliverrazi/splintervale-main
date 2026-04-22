extends Node
## Hält die persistente Player-Instanz und platziert sie beim Szenenwechsel
## am richtigen Spawn-Marker.

var player_scene: PackedScene = preload("res://character_body_3d.tscn")
var player_instance: Node3D

## Spawn-ID für den nächsten Szenenwechsel. Wird vom CaveEntrance-Trigger
## oder anderen Transitions vorher gesetzt.
var pending_spawn_id: String = ""

var _check_pending: bool = false


func _ready() -> void:
	_create_player()
	get_tree().tree_changed.connect(_on_tree_changed)


func _create_player() -> void:
	player_instance = player_scene.instantiate()
	player_instance.add_to_group("player")


func _on_tree_changed() -> void:
	if _check_pending:
		return
	_check_pending = true
	call_deferred("_do_check")


func _do_check() -> void:
	_check_pending = false
	_check_scene()


func _check_scene() -> void:
	var tree := get_tree()
	if not tree or not tree.current_scene:
		return
	var scene := tree.current_scene

	if not is_instance_valid(player_instance):
		_create_player()

	# Player ist schon in dieser Szene → nichts tun
	if player_instance.get_parent() == scene:
		return

	_install_player_in_scene(scene)


func _install_player_in_scene(scene: Node) -> void:
	# Aus alter Szene entkoppeln
	if player_instance.get_parent():
		player_instance.get_parent().remove_child(player_instance)

	# Spawn-Position bestimmen (GameManager Save-Load hat Vorrang)
	var spawn_pos := Vector3.ZERO
	var spawn_rot := 0.0
	var found_spawn := false

	if not _gm_has_pending_position():
		var marker := _find_spawn_marker(scene)
		if marker:
			spawn_pos = marker.global_position
			spawn_rot = marker.global_rotation.y
			found_spawn = true
			pending_spawn_id = ""

	# Velocity nullen
	if player_instance is CharacterBody3D:
		(player_instance as CharacterBody3D).velocity = Vector3.ZERO

	# Einfügen
	scene.add_child(player_instance)

	# Position anwenden
	if found_spawn:
		player_instance.global_position = spawn_pos
		player_instance.global_rotation.y = spawn_rot


func _gm_has_pending_position() -> bool:
	if not has_node("/root/GameManager"):
		return false
	var gm := get_node("/root/GameManager")
	return "_has_pending_position" in gm and gm._has_pending_position


func _find_spawn_marker(scene: Node) -> Marker3D:
	# Gezielter Spawn per ID
	if not pending_spawn_id.is_empty():
		var found := scene.find_child(pending_spawn_id, true, false)
		if found is Marker3D:
			return found as Marker3D
		return null

	# Fallback: erster Marker im SpawnPoints-Container
	var container := scene.find_child("SpawnPoints", true, false)
	if container:
		for child in container.get_children():
			if child is Marker3D:
				return child as Marker3D
	return null


func ensure_player() -> Node3D:
	if not is_instance_valid(player_instance):
		_create_player()
	return player_instance


func detach() -> void:
	ensure_player()
	if player_instance.get_parent():
		player_instance.get_parent().remove_child(player_instance)
